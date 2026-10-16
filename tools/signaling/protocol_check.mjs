// Checks a co-op signaling server's protocol (server.mjs here, or the
// Durable Object at /signal in tools/cloudflare): rooms, the full mesh of
// signals, a new host when the host leaves, joining again with the same room
// code, rooms rebuilt by their players after a restart (two coming back at
// once, a friend joining before the host is back, the host's place and the
// players' order kept, a player's socket dropping on its side only, a player
// the room let go coming back, a host that never comes back), and (with
// --slow, half a minute more) players who stop pinging: passed over for host,
// and dropped when another player says it lost them (but not one that kept
// pinging). With --restart, it also holds a room while you restart the server
// (or the Durable Object: restart `wrangler dev`), then comes back to it.
// Plays fake players over plain WebSockets; no game or browser needed.
// Usage: node protocol_check.mjs <ws url> [--slow] [--restart]
//   e.g. node protocol_check.mjs ws://127.0.0.1:8070
//        node protocol_check.mjs wss://nycheroes.party/signal --slow

const [, , url, ...flags] = process.argv;
if (!url) {
  console.log('Usage: node protocol_check.mjs <ws url> [--slow] [--restart]');
  process.exit(2);
}
const slow = flags.includes('--slow');
const restart = flags.includes('--restart');
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

const describe = (message) => JSON.stringify(message, (key, value) => (['ice', 'data', 'key'].includes(key) ? undefined : value));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const CODE_LETTERS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/** A room code the server has no room for (it says so), as after a restart. */
async function unknownCode() {
  const probe = await player('probe');
  try {
    for (;;) {
      let code = '';
      for (let i = 0; i < 4; i++) code += CODE_LETTERS[Math.floor(Math.random() * CODE_LETTERS.length)];
      probe.send({ type: 'join', code });
      const answer = await probe.next();
      if (answer?.type === 'error' && answer.reason === 'no_room') return code;
      if (answer?.type !== 'joined') throw new Error(`no room code free of rooms (${describe(answer)}): a server from before rejoining?`);
    }
  } finally {
    probe.close();
  }
}

/** Nothing more comes for these players for a moment. */
async function quiet(players, ms = 1000) {
  await sleep(ms);
  return players.every((p) => p.pending() === 0);
}

/** A fake player that connects once the server takes connections again. */
async function playerAgain(name, ms = 60000) {
  const end = Date.now() + ms;
  for (;;) {
    try {
      return await player(name);
    } catch (error) {
      if (Date.now() > end) throw error;
      await sleep(500);
    }
  }
}

try {
  const a = await player('A');
  a.send({ type: 'host' });
  const hosted = await a.next();
  check(hosted?.type === 'hosted' && hosted.id === 1 && /^\w{4}$/.test(hosted.code) && typeof hosted.key === 'string',
    'A hosts as player 1, with a key to come back with', describe(hosted));
  const code = hosted.code;

  const b = await player('B');
  b.send({ type: 'join', code });
  const bJoined = await b.next();
  check(bJoined?.type === 'joined' && bJoined.id === 2 && bJoined.host === 1 && describe(bJoined.peers) === '[1]'
    && typeof bJoined.key === 'string' && bJoined.key !== hosted.key,
    'B joins as player 2 (with a key of its own), A hosting', describe(bJoined));
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
  check(gone?.type === 'error' && gone.reason === 'no_room', 'once everyone left, the room is gone', describe(gone));
  f.close();

  await rebuildCheck();
  if (restart) await restartCheck();
} catch (error) {
  check(false, String(error));
}
console.log(`protocol check finished: ${failures} problems`);
process.exit(failures ? 1 : 0);

/**
 * A restart loses every room and closes every socket; the players come back
 * and rebuild their rooms. The server can't tell that from players claiming a
 * room it never had, so this makes one up: players 1 (hosting), 3 and 2, who
 * came in that order.
 */
async function rebuildCheck() {
  const code = await unknownCode();
  const keys = { 1: 'key-one', 2: 'key-two', 3: 'key-three' };
  const claim = (id) => ({ type: 'rejoin', code, id, key: keys[id], host: 1, players: [1, 3, 2] });

  const [p2, p3] = [await player('P2'), await player('P3')];
  p2.send(claim(2));
  p3.send(claim(3));
  const [p2Back, p3Back] = [await p2.next(), await p3.next()];
  check([[p2Back, 2], [p3Back, 3]].every(([back, id]) => back?.type === 'rejoined' && back.id === id && back.host === 1
    && describe(back.players) === '[1,3,2]' && !back.back),
    "after a restart, two players come back at once: the room is rebuilt, the host's place kept",
    `${describe(p2Back)} ${describe(p3Back)}`);

  const n = await player('N');
  n.send({ type: 'join', code });
  const nJoined = await n.next();
  check(nJoined?.type === 'joined' && nJoined.id === 4 && nJoined.host === 1 && describe(nJoined.peers) === '[1,3,2]',
    'a friend joins before the host is back: player 4, the host still 1', describe(nJoined));
  const [p2SeesN, p3SeesN] = [await p2.next(), await p3.next()];
  check(p2SeesN?.type === 'peer_joined' && p2SeesN.id === 4 && p3SeesN?.type === 'peer_joined' && p3SeesN.id === 4,
    'the players back hear of the friend (they make offers)', `${describe(p2SeesN)} ${describe(p3SeesN)}`);

  const p1 = await player('P1');
  p1.send(claim(1));
  const [p1Back, p1SeesN] = [await p1.next(), await p1.next()];
  check(p1Back?.type === 'rejoined' && p1Back.id === 1 && p1Back.host === 1 && describe(p1Back.players) === '[1,3,2,4]'
    && !p1Back.back && p1SeesN?.type === 'peer_joined' && p1SeesN.id === 4 && !p1SeesN.back,
    'the host comes back, still the host, and hears of the friend (it makes the offer)',
    `${describe(p1Back)} ${describe(p1SeesN)}`);
  check(await quiet([p2, p3, n]), "the others aren't told anything: nothing changed for them");
  p1.send({ type: 'signal', to: 4, data: { kind: 'offer', sdp: '1-to-4' } });
  const signal = await n.next();
  check(signal?.type === 'signal' && signal.from === 1 && signal.data?.sdp === '1-to-4', 'the host and the friend can signal',
    describe(signal));

  const p2Again = await player("P2'");
  p2Again.send(claim(2));
  const p2AgainBack = await p2Again.next();
  const p2Closed = await Promise.race([p2.closed.then(() => true), sleep(5000).then(() => false)]);
  check(p2AgainBack?.type === 'rejoined' && p2AgainBack.id === 2 && !p2AgainBack.back && p2Closed
    && await quiet([p1, p3, n]),
    "P2's socket drops on its side only: its new one takes over, the old one is closed, nobody else hears of it",
    describe(p2AgainBack));

  const x = await player('X');
  x.send({ type: 'rejoin', code, id: 4, key: 'not-the-key', host: 4, players: [4] });
  const turnedAway = await x.next();
  check(turnedAway?.type === 'error' && await quiet([n]), "someone else can't take player 4's place", describe(turnedAway));
  x.close();

  p1.close();
  const leftAnswers = [await p3.next(), await p2Again.next(), await n.next()];
  check(leftAnswers.every((m) => m?.type === 'peer_left' && m.id === 1 && m.host === 3),
    'the host leaves: player 3 hosts, in the room longest (as before the restart)',
    leftAnswers.map(describe).join(' '));

  p3.close();
  const [p2SeesP3Left, nSeesP3Left] = [await p2Again.next(), await n.next()];
  check(p2SeesP3Left?.type === 'peer_left' && p2SeesP3Left.host === 2 && nSeesP3Left?.type === 'peer_left',
    "P3's socket drops: the room lets it go, P2 hosts", `${describe(p2SeesP3Left)} ${describe(nSeesP3Left)}`);
  const p3Again = await player("P3'");
  p3Again.send(claim(3));
  const p3AgainBack = await p3Again.next();
  check(p3AgainBack?.type === 'rejoined' && p3AgainBack.id === 3 && p3AgainBack.back === true && p3AgainBack.host === 2
    && describe(p3AgainBack.players) === '[2,4,3]',
    'P3 comes back to its number, the room as it is now (P2 hosting)', describe(p3AgainBack));
  const [p2SeesP3, nSeesP3] = [await p2Again.next(), await n.next()];
  check(p2SeesP3?.type === 'peer_joined' && p2SeesP3.id === 3 && p2SeesP3.back === true
    && nSeesP3?.type === 'peer_joined' && nSeesP3.id === 3 && nSeesP3.back === true,
    'the others hear it came back (they connect to it again)', `${describe(p2SeesP3)} ${describe(nSeesP3)}`);
  for (const p of [p2Again, p3Again, n]) p.close();

  // A host that never comes back.
  const lonely = await unknownCode();
  const q = await player('Q');
  q.send({ type: 'rejoin', code: lonely, id: 2, key: 'key-q', host: 1, players: [1, 2] });
  const qBack = await q.next();
  check(qBack?.type === 'rejoined' && qBack.host === 1 && describe(qBack.players) === '[1,2]',
    'a player comes back to a room whose host is still away', describe(qBack));
  q.send({ type: 'lost', id: 1 });
  check(await quiet([q], 1500), 'it says it lost the host right away: nothing happens, the host may be coming');
  await sleep(10000);
  q.send({ type: 'lost', id: 1 });
  const qSeesHostGone = await q.next();
  check(qSeesHostGone?.type === 'peer_left' && qSeesHostGone.id === 1 && qSeesHostGone.host === 2,
    'ten seconds on, still not back: the host is dropped, and that player hosts', describe(qSeesHostGone));
  const r = await player('R');
  r.send({ type: 'join', code: lonely });
  const rJoined = await r.next();
  check(rJoined?.type === 'joined' && rJoined.id === 1 && rJoined.host === 2,
    "a friend joining now gets the old host's number", describe(rJoined));
  q.close();
  r.close();
}

/** Holds a room while the server restarts, then comes back to it. */
async function restartCheck() {
  const a = await player('A');
  a.send({ type: 'host' });
  const { code, key: aKey } = (await a.next()) ?? {};
  const b = await player('B');
  b.send({ type: 'join', code });
  const { key: bKey } = (await b.next()) ?? {};
  await a.next();
  const c = await player('C');
  c.send({ type: 'join', code });
  const { key: cKey } = (await c.next()) ?? {};
  await Promise.all([a.next(), b.next()]);
  console.log(`....  room ${code} (players 1, 2, 3): restart the server now (waiting up to 2 minutes)`);
  const dropped = await Promise.race([Promise.all([a.closed, b.closed, c.closed]).then(() => true),
    sleep(120000).then(() => false)]);
  check(dropped, 'the restart closes every socket');
  if (!dropped) return;

  const claim = (id, key) => ({ type: 'rejoin', code, id, key, host: 1, players: [1, 2, 3] });
  const [b2, c2] = [await playerAgain("B'"), await playerAgain("C'")];
  b2.send(claim(2, bKey));
  c2.send(claim(3, cKey));
  const [bBack, cBack] = [await b2.next(), await c2.next()];
  check(bBack?.type === 'rejoined' && bBack.id === 2 && cBack?.type === 'rejoined' && cBack.id === 3
    && bBack.host === 1 && describe(cBack.players) === '[1,2,3]',
    'B and C come back to the same room, as the same players, A still the host', `${describe(bBack)} ${describe(cBack)}`);
  const d = await player('D');
  d.send({ type: 'join', code });
  const dJoined = await d.next();
  check(dJoined?.type === 'joined' && dJoined.id === 4 && dJoined.host === 1, 'D joins with the code: player 4',
    describe(dJoined));
  await Promise.all([b2.next(), c2.next()]);
  const a2 = await player("A'");
  a2.send(claim(1, aKey));
  const [aBack, aSeesD] = [await a2.next(), await a2.next()];
  check(aBack?.type === 'rejoined' && aBack.id === 1 && aBack.host === 1 && aSeesD?.type === 'peer_joined' && aSeesD.id === 4,
    'A comes back, still the host, and hears of D', `${describe(aBack)} ${describe(aSeesD)}`);
  a2.close();
  const leftAnswers = [await b2.next(), await c2.next(), await d.next()];
  check(leftAnswers.every((m) => m?.type === 'peer_left' && m.id === 1 && m.host === 2),
    'A leaves: B hosts', leftAnswers.map(describe).join(' '));
  for (const p of [b2, c2, d]) p.close();
}
