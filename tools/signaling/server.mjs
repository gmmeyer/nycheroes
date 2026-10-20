// Signaling server for co-op: introduces players so their browsers can connect
// to each other directly over WebRTC. In private rooms game traffic never
// passes through here; public rooms are relayed (below).
//
// The host asks for a room and gets a short code; friends join with the code.
// Every player connects to every other (a full mesh), so the server relays
// WebRTC offers, answers and network candidates between any two players in a
// room: the players already there each send the newcomer an offer.
//
// Public games: a player asking for the public game ("public") is put in the
// public room with the most players that has a place free (PUBLIC_PLAYERS at
// most), of those for its version of the game, or opens a new one when they're
// all full (or there are none). Public rooms have codes like any other, so
// friends can join one with its code (up to MAX_PLAYERS, the full mesh's
// limit). A game's version is a number it sends when hosting, joining or
// asking for the public game (games that can't play together have different
// ones); joining a room of another version with its code is turned away.
// Games from before public rooms never ask for one, and send no version.
//
// Relayed public rooms: a game that can ("public" with `relay: true`) is put in
// one big public room instead, whose game traffic goes through this server
// rather than a mesh: each player sends its packets here as binary messages
// and the server passes them on to the players they're for. Everyone online
// then plays in one room (up to RELAY_PUBLIC_PLAYERS by matchmaking, plus
// RELAY_EXTRA friends with the code), not rooms of six. Their WebRTC signals
// aren't needed. Binary messages:
//   player -> server  [channel u8][mode u8][count u16][count x player id u16][packet]
//                     (count 0: every other player in the room)
//   server -> player  [from u16][channel u8][mode u8][packet]
// (numbers little-endian; channel and mode are Godot's, passed on as they are).
//
// One player is the room's host (the one whose game runs the thugs): first
// the one who opened it. When the host leaves, the player who has been in the
// room longest takes over (passing over any who stopped pinging: their
// connection may be dead, or the game paused in a background tab); everyone
// is told in the peer_left message. The room and its code last until the last
// player leaves.
//
// Players ping ("ping", answered "pong") every 10 s. A player who loses touch
// with another tells the server ("lost"); if that one hasn't pinged for
// PING_TIMEOUT_MS, its connection is taken for dead and it leaves the room.
//
// A restart (or a Worker deploy restarting the Durable Object in
// tools/cloudflare) forgets every room and closes every socket, but the games
// play on over their own connections: each connects again and rejoins its room
// as the same player ("rejoin"), saying who was in it, in the order they came,
// and who hosted (and whether the room is public, and its version). The first
// one back rebuilds the room from that; the places of the others (the host's
// role too) are kept for them until they're back, so a friend joining
// meanwhile gets a free number, and those coming back later are told to
// connect to the friend. One still away after AWAY_TIMEOUT_MS whom another
// player has lost touch with is taken to have left. A player whose socket
// alone dropped (so the room let it go) rejoins the same way, and the others
// connect to it again. Hosting or joining gives a player a key, so only it can
// take its place back.
//
// Usage: npm install && node server.mjs
// Environment:
//   PORT              port to listen on (default 8070)
//   ICE_SERVERS       JSON list of WebRTC ICE servers handed to players, e.g.
//                     [{"urls":"stun:stun.l.google.com:19302"},
//                      {"urls":"turn:turn.example.com:3478","username":"u","credential":"p"}]
//   ALLOWED_ORIGINS   comma-separated page origins allowed to connect (default: any)
//   RELAY_PUBLIC_PLAYERS  players a relayed public room takes by matchmaking (default 64)
//
// Protocol (JSON text messages, plus "ping"/"pong" as plain text):
//   player -> server  {type: "host", version}      server -> {type: "hosted", code, id: 1, key, ice}
//   player -> server  {type: "join", code, version}
//                                                  server -> {type: "joined", code, id, key, host, peers, ice, public}
//                                                  others <- {type: "peer_joined", id}
//   player -> server  {type: "public", version, relay}
//                                                  server -> {type: "joined", ..., public: true} (as for "join"),
//                                                            or {type: "hosted", ..., public: true} (a new room)
//                                                            (with relay: true too, for a relayed room)
//   player -> server  {type: "rejoin", code, id, key, host, players, public, version}
//                                                  server -> {type: "rejoined", code, id, host, players, back, ice, public}
//                                                  then   <- {type: "peer_joined", id, back} for each player who
//                                                            joined while it was away (it makes the offer)
//                                                  if back: others <- {type: "peer_joined", id, back: true}
//   player -> server  {type: "signal", to, data}   to     <- {type: "signal", from, data}
//   player -> server  {type: "lost", id}           (drops player id if it stopped pinging, or isn't back)
//   others <- {type: "peer_left", id, host}        anyone <- {type: "error", message, reason}
// `peers` and `players` are in the order the players came (`players` includes
// the player itself); `public` is true in public rooms (left out in others),
// and `relay` in relayed ones (hosted, joined and rejoined say so; rejoin too);
// games from before public rooms send no `version` (and no `public`). An error
// with reason "no_room" answers a join for a code with no room: after a
// restart, perhaps not yet; "full", a room with no place free; "version", a
// room of another version of the game.

import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { WebSocketServer } from 'ws';

const PORT = Number(process.env.PORT ?? 8070);
const ICE_SERVERS = process.env.ICE_SERVERS
  ? JSON.parse(process.env.ICE_SERVERS)
  : [{ urls: ['stun:stun.l.google.com:19302'] }];
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS ?? '').split(',').map((o) => o.trim()).filter(Boolean);
const MAX_PLAYERS = 8;
// Public rooms take this many players by matchmaking, leaving places for
// friends joining with the code.
const PUBLIC_PLAYERS = 6;
// Relayed public rooms (no mesh): this many by matchmaking, RELAY_EXTRA more
// with the code. Player numbers are 16 bits in relayed messages.
const RELAY_PUBLIC_PLAYERS = Math.min(Number(process.env.RELAY_PUBLIC_PLAYERS ?? 64), 1000);
const RELAY_EXTRA = 8;
const RELAY_MAX_PLAYERS = RELAY_PUBLIC_PLAYERS + RELAY_EXTRA;
// Highest player number in any room.
const MAX_ID = Math.max(MAX_PLAYERS, RELAY_MAX_PLAYERS);
const FIRST_HOST = 1;
// No 0/O, 1/I/L: codes get read out loud and typed.
const CODE_LETTERS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 4;
const HEARTBEAT_MS = 30000;
// Players ping every 10 s; one that hasn't for this long is gone.
const PING_TIMEOUT_MS = 25000;
// Players come back within seconds of a restart; one that hasn't after this
// long is gone, if another player says it lost touch.
const AWAY_TIMEOUT_MS = 10000;

/**
 * code -> {code, host, players: Map<id, player>, public, relay, version, opened},
 * players in the order they came: their sockets ({room, id, key, since, seen,
 * back}), or, after a restart, places kept for those not back yet ({away: true,
 * id, since, at}). `version` is the game's (null from games before public rooms).
 */
const rooms = new Map();

const http = createServer((request, response) => {
  // A plain GET is a health check.
  response.writeHead(200, { 'content-type': 'text/plain' });
  const open = [...rooms.values()].filter((room) => room.public).length;
  response.end(`signaling ok, ${rooms.size} rooms (${open} public)\n`);
});
const wss = new WebSocketServer({
  server: http,
  maxPayload: 64 * 1024,
  verifyClient: ({ origin }) => ALLOWED_ORIGINS.length === 0 || ALLOWED_ORIGINS.includes(origin),
});

wss.on('connection', (socket) => {
  socket.alive = true;
  socket.seen = Date.now();
  socket.on('pong', () => { socket.alive = true; });
  socket.on('message', (raw, isBinary) => {
    socket.seen = Date.now();
    if (isBinary) return relay(socket, raw);
    if (raw.toString() === 'ping') return socket.send('pong');
    let message;
    try {
      message = JSON.parse(raw.toString());
    } catch {
      return send(socket, { type: 'error', message: 'Bad message' });
    }
    handle(socket, message);
  });
  socket.on('close', () => leave(socket));
});

function handle(socket, message) {
  switch (message?.type) {
    case 'host':
      if (socket.room) return send(socket, { type: 'error', message: 'Already in a game' });
      open(socket, { public: false, relay: false, version: versionOf(message) });
      break;
    case 'join': {
      if (socket.room) return send(socket, { type: 'error', message: 'Already in a game' });
      const code = String(message.code ?? '').trim().toUpperCase();
      const room = rooms.get(code);
      if (!room) return send(socket, { type: 'error', message: `No game with code ${code}`, reason: 'no_room' });
      const version = versionOf(message);
      if (version !== null && room.version !== null && version !== room.version) {
        return send(socket, { type: 'error', message: OTHER_VERSION, reason: 'version' });
      }
      admit(socket, room);
      break;
    }
    case 'public': {
      if (socket.room) return send(socket, { type: 'error', message: 'Already in a game' });
      const version = versionOf(message);
      const relayed = message.relay === true;
      const room = publicRoom(version, relayed);
      if (room) admit(socket, room);
      else open(socket, { public: true, relay: relayed, version });
      break;
    }
    case 'rejoin':
      rejoin(socket, message);
      break;
    case 'signal': {
      const target = socket.room?.players.get(Number(message.to));
      if (target && target !== socket) send(target, { type: 'signal', from: socket.id, data: message.data });
      break;
    }
    case 'lost': {
      const room = socket.room;
      const target = room?.players.get(Number(message.id));
      if (target && target !== socket && gone(target)) {
        log(`room ${room.code}: player ${target.id} ${target.away ? 'is not back' : 'stopped pinging'}`);
        leave(target, room);
        if (!target.away) target.terminate();
      }
      break;
    }
    default:
      send(socket, { type: 'error', message: 'Unknown message' });
  }
}

const OTHER_VERSION = 'That game is on another version of NYC Heroes. Reload the page (or get the new version), then try again.';

/** Opens a room with this player as its host. */
function open(socket, { public: isPublic, relay: relayed, version }) {
  const room = {
    code: newCode(), host: FIRST_HOST, players: new Map([[FIRST_HOST, socket]]), public: isPublic, relay: relayed,
    version, opened: Date.now(),
  };
  rooms.set(room.code, room);
  Object.assign(socket, { room, id: FIRST_HOST, key: randomUUID(), since: Date.now() });
  send(socket, { type: 'hosted', code: room.code, id: FIRST_HOST, key: socket.key, ice: ICE_SERVERS, ...publicFlag(room) });
  log(`${room.relay ? 'relayed ' : ''}${room.public ? 'public ' : ''}room ${room.code} opened`);
}

/** Puts a player in a room, as its lowest free number; everyone there sends it an offer. */
function admit(socket, room) {
  // The lowest free number, so player numbers (and colors) stay small.
  let id = FIRST_HOST;
  while (room.players.has(id)) id++;
  if (id > capacity(room)) return send(socket, { type: 'error', message: 'That game is full', reason: 'full' });
  const peers = [...room.players.keys()];
  room.players.set(id, socket);
  Object.assign(socket, { room, id, key: randomUUID(), since: Date.now() });
  send(socket, {
    type: 'joined', code: room.code, id, key: socket.key, host: room.host, peers, ice: ICE_SERVERS, ...publicFlag(room),
  });
  for (const peer of peers) send(room.players.get(peer), { type: 'peer_joined', id });
  log(`room ${room.code}: player ${id} joined (${room.players.size} players)`);
}

/**
 * The public room to put a player in: of those for its version with a place
 * free, the one with the most players (places kept for players not back since
 * a restart count too), the oldest of those. Null if there's none.
 */
function publicRoom(version, relayed) {
  let best = null;
  for (const room of rooms.values()) {
    if (!room.public || room.relay !== relayed || room.version !== version) continue;
    if (room.players.size >= (relayed ? RELAY_PUBLIC_PLAYERS : PUBLIC_PLAYERS)) continue;
    if (!best || room.players.size > best.players.size
      || (room.players.size === best.players.size && room.opened < best.opened)) best = room;
  }
  return best;
}

function publicFlag(room) {
  return { ...(room.public && { public: true }), ...(room.relay && { relay: true }) };
}

/** How many players a room can have: a mesh's limit, or a relayed room's. */
function capacity(room) {
  return room.relay ? RELAY_MAX_PLAYERS : MAX_PLAYERS;
}

/**
 * A packet from a player in a relayed room (see the top), passed on to the
 * players it's for, saying who it's from.
 */
function relay(socket, data) {
  const room = socket.room;
  if (!room?.relay || !Buffer.isBuffer(data) || data.length < 4) return;
  const count = data.readUInt16LE(2);
  const start = 4 + count * 2;
  if (data.length < start) return;
  const out = Buffer.allocUnsafe(data.length - start + 4);
  out.writeUInt16LE(socket.id, 0);
  out[2] = data[0];
  out[3] = data[1];
  data.copy(out, 4, start);
  if (count === 0) {
    for (const player of room.players.values()) if (player !== socket) sendBinary(player, out);
    return;
  }
  for (let i = 0; i < count; i++) {
    const target = room.players.get(data.readUInt16LE(4 + i * 2));
    if (target && target !== socket) sendBinary(target, out);
  }
}

/** The game's version a message gives, or null (games from before public rooms send none). */
function versionOf(message) {
  return Number.isInteger(message?.version) ? message.version : null;
}

/** A player coming back to its room after its socket dropped, or after we restarted. */
function rejoin(socket, message) {
  if (socket.room) return send(socket, { type: 'error', message: 'Already in a game' });
  const code = String(message.code ?? '').trim().toUpperCase();
  const id = Number(message.id);
  const key = String(message.key ?? '');
  if (!isCode(code) || !Number.isInteger(id) || id < FIRST_HOST || id > MAX_ID) {
    return send(socket, { type: 'error', message: 'Bad message' });
  }
  const room = rooms.get(code) ?? rebuild(code, id, message);
  // Any player back may know better than the first (a game from before public
  // rooms doesn't say).
  if (message.public === true) room.public = true;
  if (message.relay === true) room.relay = true;
  room.version ??= versionOf(message);
  const there = room.players.get(id);
  let since = Date.now();
  let back = false;
  let missed = [];
  if (there && !there.away) {
    // Their old socket is still open here: it dropped on their side first.
    if (there.key !== key) return send(socket, { type: 'error', message: `Someone else is player ${id} in game ${code} now` });
    since = there.since;
    there.room = null;
    there.terminate();
  } else if (there) {
    since = there.since;
    // Players who joined meanwhile wait for an offer from them.
    missed = [...room.players.values()].filter((player) => !player.away && player.since >= there.at);
  } else {
    // The room let them go meanwhile: everyone connects to them again.
    if (room.players.size >= capacity(room)) return send(socket, { type: 'error', message: 'That game is full', reason: 'full' });
    back = true;
  }
  room.players.set(id, socket); // (in their old place, if they had one)
  Object.assign(socket, { room, id, key, since, back });
  send(socket, {
    type: 'rejoined', code, id, host: room.host, players: [...room.players.keys()], back, ice: ICE_SERVERS, ...publicFlag(room),
  });
  for (const player of missed) send(socket, { type: 'peer_joined', id: player.id, back: player.back });
  if (back) {
    for (const player of room.players.values()) {
      if (player !== socket) send(player, { type: 'peer_joined', id, back: true });
    }
  }
  log(`room ${code}: player ${id} ${back ? 'came back' : 'is back'}`);
}

/**
 * A room we lost (a restart), as the first player back says it was: who was
 * in it, in the order they came, who hosted, whether it was public and its
 * version. The places of all of them are kept until they're back (the first
 * takes its own at once).
 */
function rebuild(code, id, message) {
  const claimed = Array.isArray(message.players) ? message.players : [];
  const ids = [...new Set([...claimed, id].map(Number))]
    .filter((n) => Number.isInteger(n) && n >= FIRST_HOST && n <= MAX_ID);
  const host = ids.includes(Number(message.host)) ? Number(message.host) : id;
  const now = Date.now();
  const room = {
    code, host, players: new Map(), public: message.public === true, relay: message.relay === true,
    version: versionOf(message), opened: now,
  };
  ids.forEach((n, i) => room.players.set(n, { away: true, id: n, since: now - ids.length + i, at: now }));
  rooms.set(code, room);
  log(`${room.public ? 'public ' : ''}room ${code} rebuilt: players ${ids.join(', ')}, player ${host} hosting`);
  return room;
}

/** Takes a player (a socket, or a place kept for one) out of their room, handing it to a new host if they hosted. */
function leave(player, room = player.room) {
  if (!room || room.players.get(player.id) !== player) return;
  player.room = null;
  room.players.delete(player.id);
  if (![...room.players.values()].some((other) => !other.away)) {
    // Nobody's here (any still away can rebuild it).
    rooms.delete(room.code);
    log(`room ${room.code} closed`);
    return;
  }
  const wasHost = room.host === player.id;
  if (wasHost) room.host = nextHost(room);
  for (const other of room.players.values()) send(other, { type: 'peer_left', id: player.id, host: room.host });
  log(`room ${room.code}: player ${player.id} left${wasHost ? `, player ${room.host} hosts now` : ''}`);
}

/** The player who has been in the room longest, of those here and still pinging if any. */
function nextHost(room) {
  const now = Date.now();
  const here = [...room.players.values()].filter((player) => !player.away);
  return (here.find((player) => now - player.seen <= PING_TIMEOUT_MS) ?? here[0]).id;
}

/** Whether a player another has lost touch with is gone: it stopped pinging, or isn't back since a restart. */
function gone(player) {
  return player.away ? Date.now() - player.at > AWAY_TIMEOUT_MS : Date.now() - player.seen > PING_TIMEOUT_MS;
}

function newCode() {
  for (;;) {
    let code = '';
    for (let i = 0; i < CODE_LENGTH; i++) code += CODE_LETTERS[Math.floor(Math.random() * CODE_LETTERS.length)];
    if (!rooms.has(code)) return code;
  }
}

function isCode(code) {
  return code.length === CODE_LENGTH && [...code].every((letter) => CODE_LETTERS.includes(letter));
}

function send(socket, message) {
  if (socket && !socket.away && socket.readyState === socket.OPEN) socket.send(JSON.stringify(message));
}

function sendBinary(socket, data) {
  if (socket && !socket.away && socket.readyState === socket.OPEN) socket.send(data, { binary: true });
}

function log(text) {
  console.log(`[signaling] ${text}`);
}

// Drop connections that stopped answering (closed laptops, dropped Wi-Fi).
setInterval(() => {
  for (const socket of wss.clients) {
    if (!socket.alive) {
      socket.terminate();
      continue;
    }
    socket.alive = false;
    socket.ping();
  }
}, HEARTBEAT_MS);

http.listen(PORT, () => log(`listening on port ${PORT}`));
