// Checks a co-op signaling server's protocol (server.mjs here, or the
// Durable Object at /signal in tools/cloudflare): rooms, the full mesh of
// signals, a new host when the host leaves, joining again with the same room
// code, and (with --slow, half a minute more) players who stop pinging: passed
// over for host, and dropped when another player says it lost them (but not
// one that kept pinging).
// Plays four fake players over plain WebSockets; no game or browser needed.
// Usage: node protocol_check.mjs <ws url> [--slow]
//   e.g. node protocol_check.mjs ws://127.0.0.1:8070
//        node protocol_check.mjs wss://nycheroes.party/signal --slow

const [, , url, ...flags] = process.argv;
if (!url) {
  console.log('Usage: node protocol_check.mjs <ws url> [--slow]');
  process.exit(2);
}
const slow = flags.includes('--slow');
let failures = 0;

function check(ok, text, detail = '') {
  if (!ok) failures++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${text}${detail ? `  (${detail})` : ''}`);
}

/** A fake player: a socket with a queue of what the server said. */
function player(name) {
  const ws = new WebSocket(url);
  const queue = [];
  let wake = null;
  ws.addEventListener('message', (event) => {
    queue.push(event.data === 'pong' ? { type: 'pong' } : JSON.parse(event.data));
    wake?.();
  });
  const closed = new Promise((resolve) => ws.addEventListener('close', resolve));
  return new Promise((resolve, reject) => {
    ws.addEventListener('error', () => reject(new Error(`${name} couldn't connect to ${url}`)));
    ws.addEventListener('open', () => resolve({
      name,
      closed,
      send: (message) => ws.send(typeof message === 'string' ? message : JSON.stringify(message)),
      close: () => ws.close(),
      /** The next message (or null after `ms`), skipping none. */
      next: async (ms = 5000) => {
        const end = Date.now() + ms;
        while (!queue.length && Date.now() < end) {
          await new Promise((r) => { wake = r; setTimeout(r, end - Date.now()); });
        }
        return queue.shift() ?? null;
      },
      pending: () => queue.length,
    }));
  });
}

const describe = (message) => JSON.stringify(message, (key, value) => (key === 'ice' || key === 'data' ? undefined : value));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

try {
  const a = await player('A');
  a.send({ type: 'host' });
  const hosted = await a.next();
  check(hosted?.type === 'hosted' && hosted.id === 1 && /^\w{4}$/.test(hosted.code), 'A hosts as player 1', describe(hosted));
  const code = hosted.code;

  const b = await player('B');
  b.send({ type: 'join', code });
  const bJoined = await b.next();
  check(bJoined?.type === 'joined' && bJoined.id === 2 && bJoined.host === 1 && describe(bJoined.peers) === '[1]',
    'B joins as player 2, A hosting', describe(bJoined));
  const aSeesB = await a.next();
  check(aSeesB?.type === 'peer_joined' && aSeesB.id === 2, 'A hears B joined', describe(aSeesB));

  const c = await player('C');
  c.send({ type: 'join', code: code.toLowerCase() });
  const cJoined = await c.next();
  check(cJoined?.type === 'joined' && cJoined.id === 3 && cJoined.host === 1 && describe(cJoined.peers) === '[1,2]',
    'C joins as player 3 and hears of A and B', describe(cJoined));
  const [aSeesC, bSeesC] = [await a.next(), await b.next()];
  check(aSeesC?.type === 'peer_joined' && aSeesC.id === 3 && bSeesC?.type === 'peer_joined' && bSeesC.id === 3,
    'A and B both hear C joined (both make offers)', `${describe(aSeesC)} ${describe(bSeesC)}`);

  b.send({ type: 'signal', to: 3, data: { kind: 'offer', sdp: 'b-to-c' } });
  const signal = await c.next();
  check(signal?.type === 'signal' && signal.from === 2 && signal.data?.sdp === 'b-to-c',
    'B and C (neither hosting) can signal each other', describe(signal));

  c.send('ping');
  check((await c.next())?.type === 'pong', 'a ping gets a pong');

  a.close();
  const [bSeesLeft, cSeesLeft] = [await b.next(), await c.next()];
  check(bSeesLeft?.type === 'peer_left' && bSeesLeft.id === 1 && bSeesLeft.host === 2
    && cSeesLeft?.type === 'peer_left' && cSeesLeft.id === 1 && cSeesLeft.host === 2,
    'the host leaves: B and C hear player 2 hosts now', `${describe(bSeesLeft)} ${describe(cSeesLeft)}`);

  const d = await player('D');
  d.send({ type: 'join', code });
  const dJoined = await d.next();
  check(dJoined?.type === 'joined' && dJoined.id === 1 && dJoined.host === 2 && describe(dJoined.peers) === '[2,3]',
    'D joins with the same code: player 1 again, B hosting', describe(dJoined));
  const [bSeesD, cSeesD] = [await b.next(), await c.next()];
  check(bSeesD?.type === 'peer_joined' && bSeesD.id === 1 && cSeesD?.type === 'peer_joined' && cSeesD.id === 1,
    'B and C hear D joined', `${describe(bSeesD)} ${describe(cSeesD)}`);

  c.close();
  const [bSeesCLeft, dSeesCLeft] = [await b.next(), await d.next()];
  check(bSeesCLeft?.type === 'peer_left' && bSeesCLeft.id === 3 && bSeesCLeft.host === 2
    && dSeesCLeft?.type === 'peer_left' && dSeesCLeft.id === 3 && dSeesCLeft.host === 2,
    'C (not hosting) leaves: B still hosts', `${describe(bSeesCLeft)} ${describe(dSeesCLeft)}`);

  d.send({ type: 'lost', id: 2 });
  check(await b.next(1500) === null && await d.next(1500) === null, 'D says it lost B, but B is fine: nothing happens');

  if (slow) {
    // E joins. B (hosting) and E keep pinging past the timeout; D goes quiet,
    // as if its network dropped or its game paused in a background tab.
    const pingFor = async (ms, players) => {
      const start = Date.now();
      while (Date.now() - start < ms) {
        for (const p of players) p.send('ping');
        for (const p of players) await p.next(1000);
        await sleep(4000);
      }
    };
    const e = await player('E');
    e.send({ type: 'join', code });
    const eJoined = await e.next();
    check(eJoined?.type === 'joined' && eJoined.id === 3 && eJoined.host === 2, 'E joins as player 3, B hosting',
      describe(eJoined));
    await b.next();
    await d.next();
    await pingFor(27000, [b, e]);
    e.send({ type: 'lost', id: 2 });
    check(await b.next(1500) === null && await e.next(1500) === null,
      'B kept pinging past the timeout: E saying it lost B changes nothing');
    b.close();
    const [dSeesBLeft, eSeesBLeft] = [await d.next(), await e.next()];
    check(dSeesBLeft?.type === 'peer_left' && dSeesBLeft.id === 2 && dSeesBLeft.host === 3
      && eSeesBLeft?.type === 'peer_left' && eSeesBLeft.id === 2 && eSeesBLeft.host === 3,
      'B leaves: E hosts, not D (in the room longer, but not pinging)', `${describe(dSeesBLeft)} ${describe(eSeesBLeft)}`);
    e.send({ type: 'lost', id: 1 });
    const eSeesDGone = await e.next();
    check(eSeesDGone?.type === 'peer_left' && eSeesDGone.id === 1 && eSeesDGone.host === 3,
      'E says it lost D, which stopped pinging: D is dropped', describe(eSeesDGone));
    const dClosed = await Promise.race([d.closed.then(() => true), sleep(5000).then(() => false)]);
    check(dClosed, "the server closed D's socket");
    e.close();
  } else {
    b.close();
    const dSeesBLeft = await d.next();
    check(dSeesBLeft?.type === 'peer_left' && dSeesBLeft.id === 2 && dSeesBLeft.host === 1,
      'B leaves: D hosts the room alone', describe(dSeesBLeft));
    d.close();
  }

  await sleep(500);
  const f = await player('F');
  f.send({ type: 'join', code });
  const gone = await f.next();
  check(gone?.type === 'error', 'once everyone left, the room is gone', describe(gone));
  f.close();
} catch (error) {
  check(false, String(error));
}
console.log(`protocol check finished: ${failures} problems`);
process.exit(failures ? 1 : 0);
