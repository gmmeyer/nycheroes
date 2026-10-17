// Checks a co-op signaling server's protocol (server.mjs here, or the
// Durable Object at /signal in tools/cloudflare): rooms, the full mesh of
// signals, a new host when the host leaves, joining again with the same room
// code, rooms rebuilt by their players after a restart (two coming back at
// once, a friend joining before the host is back, the host's place and the
// players' order kept, a player's socket dropping on its side only, a player
// the room let go coming back, a host that never comes back), public games
// (players asking for one fill a room up to its public places, the next opens
// another, friends join a full one with its code up to the mesh's limit, a
// place freed goes to the next player asking, versions kept apart, a room
// closing with its last player, a rebuilt room staying public), and (with
// --slow, half a minute more) players who stop pinging: passed over for host,
// and dropped when another player says it lost them (but not one that kept
// pinging). With --restart, it also holds a room while you restart the server
// (or the Durable Object: restart `wrangler dev`), then comes back to it.
// Plays fake players over plain WebSockets; no game or browser needed. Its
// public games use a version of their own, so real players' aren't touched.
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
  await publicCheck();
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

/**
 * Public games: matchmaking fills a room up to its public places (6), then
 * opens another; friends join a full one with its code (up to 8); a place
 * freed goes to the next player asking; games of other versions get rooms of
 * their own; a room closes with its last player; a room rebuilt after a
 * restart stays public. With versions of its own (so real players are left
 * out), the rooms are all this check's.
 */
async function publicCheck() {
  const PUBLIC_PLAYERS = 6;
  const version = 1000000 + Math.floor(Math.random() * 1000000);
  const ask = async (name, v = version) => {
    const p = await player(name);
    p.send({ type: 'public', version: v });
    p.answer = await p.next();
    return p;
  };

  const first = await ask('Pub1');
  check(first.answer?.type === 'hosted' && first.answer.id === 1 && first.answer.public === true && first.answer.key,
    'the first player asking for the public game opens a public room as its host', describe(first.answer));
  const code = first.answer.code;
  const room = [first];
  for (let n = 2; n <= PUBLIC_PLAYERS; n++) {
    const p = await ask(`Pub${n}`);
    const heard = await Promise.all(room.map((q) => q.next()));
    check(p.answer?.type === 'joined' && p.answer.code === code && p.answer.id === n && p.answer.public === true
      && p.answer.host === 1 && describe(p.answer.peers) === describe(room.map((_, i) => i + 1))
      && heard.every((m) => m?.type === 'peer_joined' && m.id === n),
    `player ${n} asking is put in the same room, and everyone there hears of it`, describe(p.answer));
    room.push(p);
  }

  const next = await ask('Pub7');
  check(next.answer?.type === 'hosted' && next.answer.public === true && next.answer.code !== code && next.answer.id === 1,
    `with ${PUBLIC_PLAYERS} in it, the next player asking opens another public room`, describe(next.answer));
  check(await quiet(room, 500), 'nobody in the full room hears of it');

  const friends = [];
  for (const id of [7, 8]) {
    const f = await player(`Friend${id}`);
    f.send({ type: 'join', code, version });
    const joined = await f.next();
    await Promise.all([...room, ...friends].map((q) => q.next()));
    check(joined?.type === 'joined' && joined.id === id && joined.public === true,
      `a friend joins the full public room with its code: player ${id}`, describe(joined));
    friends.push(f);
  }
  const ninth = await player('Friend9');
  ninth.send({ type: 'join', code, version });
  const full = await ninth.next();
  check(full?.type === 'error' && full.reason === 'full', 'a ninth is turned away: the game is full', describe(full));
  ninth.close();

  room[2].close();
  const left = await Promise.all([...room.filter((_, i) => i !== 2), ...friends].map((q) => q.next()));
  check(left.every((m) => m?.type === 'peer_left' && m.id === 3 && m.host === 1),
    'player 3 leaves the public room: everyone there hears of it', left.map(describe).join(' '));
  for (const f of friends) f.close();
  await Promise.all(room.filter((_, i) => i !== 2).map(async (q) => { await q.next(); await q.next(); }));
  const back = await ask('Pub3again');
  check(back.answer?.type === 'joined' && back.answer.code === code && back.answer.id === 3,
    'a place is free again: the next player asking gets it (player 3), not the emptier room', describe(back.answer));
  await Promise.all(room.filter((_, i) => i !== 2).map((q) => q.next()));
  await next.next(200); // (nothing for it)

  const other = await ask('Other', version + 1);
  check(other.answer?.type === 'hosted' && other.answer.public === true && ![code, next.answer.code].includes(other.answer.code),
    'a player of another version gets a public room of its own', describe(other.answer));
  const stranger = await player('Stranger');
  stranger.send({ type: 'join', code, version: version + 1 });
  const turned = await stranger.next();
  check(turned?.type === 'error' && turned.reason === 'version',
    'joining a room of another version with its code is turned away', describe(turned));
  stranger.close();
  const old = await player('Old');
  old.send({ type: 'join', code: next.answer.code });
  const oldJoined = await old.next();
  check(oldJoined?.type === 'joined' && oldJoined.public === true && oldJoined.id === 2,
    'a game from before versions (it sends none) joins a public room with its code', describe(oldJoined));
  await next.next();
  const host = await player('Private');
  host.send({ type: 'host', version });
  const hosted = await host.next();
  check(hosted?.type === 'hosted' && hosted.public === undefined, 'hosting still opens a private room', describe(hosted));
  const seventh = await ask('Pub8');
  check(seventh.answer?.type === 'joined' && seventh.answer.code === next.answer.code && seventh.answer.id === 3,
    'with the first room full, a player asking goes to the other public room (not the private one)',
    describe(seventh.answer));

  for (const p of [next, old, seventh, other, host]) p.close();
  await sleep(500);
  const late = await player('Late');
  late.send({ type: 'join', code: next.answer.code });
  const closed = await late.next();
  check(closed?.type === 'error' && closed.reason === 'no_room', 'a public room closes with its last player', describe(closed));
  late.close();
  for (const p of [...room.filter((_, i) => i !== 2), back]) p.close();
  await sleep(500);
  const fresh = await ask('Fresh');
  check(fresh.answer?.type === 'hosted' && fresh.answer.public === true && fresh.answer.code !== code,
    'once every public room has closed, the next player asking opens a new one', describe(fresh.answer));
  fresh.close();

  // After a restart: a player comes back to its public room (rebuilt from
  // what it says), and the next player asking is put in it.
  const lost = await unknownCode();
  const rebuilt = version + 2;
  const r = await player('R2');
  r.send({ type: 'rejoin', code: lost, id: 2, key: 'key-r2', host: 1, players: [1, 2], public: true, version: rebuilt });
  const rBack = await r.next();
  check(rBack?.type === 'rejoined' && rBack.public === true, 'a player rebuilds its public room after a restart',
    describe(rBack));
  const newcomer = await ask('Newcomer', rebuilt);
  check(newcomer.answer?.type === 'joined' && newcomer.answer.code === lost && newcomer.answer.id === 3
    && newcomer.answer.public === true && describe(newcomer.answer.peers) === '[1,2]',
  'the next player asking is put in the rebuilt room (the host\'s place still kept)', describe(newcomer.answer));
  r.close();
  newcomer.close();
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
