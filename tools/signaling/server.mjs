// Signaling server for co-op: introduces players so their browsers can connect
// to each other directly over WebRTC. Game traffic never passes through here.
//
// The host asks for a room and gets a short code; friends join with the code.
// Every player connects to every other (a full mesh), so the server relays
// WebRTC offers, answers and network candidates between any two players in a
// room: the players already there each send the newcomer an offer.
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
// and who hosted. The first one back rebuilds the room from that; the places
// of the others (the host's role too) are kept for them until they're back, so
// a friend joining meanwhile gets a free number, and those coming back later
// are told to connect to the friend. One still away after AWAY_TIMEOUT_MS whom
// another player has lost touch with is taken to have left. A player whose
// socket alone dropped (so the room let it go) rejoins the same way, and the
// others connect to it again. Hosting or joining gives a player a key, so only
// it can take its place back.
//
// Usage: npm install && node server.mjs
// Environment:
//   PORT              port to listen on (default 8070)
//   ICE_SERVERS       JSON list of WebRTC ICE servers handed to players, e.g.
//                     [{"urls":"stun:stun.l.google.com:19302"},
//                      {"urls":"turn:turn.example.com:3478","username":"u","credential":"p"}]
//   ALLOWED_ORIGINS   comma-separated page origins allowed to connect (default: any)
//
// Protocol (JSON text messages, plus "ping"/"pong" as plain text):
//   player -> server  {type: "host"}               server -> {type: "hosted", code, id: 1, key, ice}
//   player -> server  {type: "join", code}         server -> {type: "joined", code, id, key, host, peers, ice}
//                                                  others <- {type: "peer_joined", id}
//   player -> server  {type: "rejoin", code, id, key, host, players}
//                                                  server -> {type: "rejoined", code, id, host, players, back, ice}
//                                                  then   <- {type: "peer_joined", id, back} for each player who
//                                                            joined while it was away (it makes the offer)
//                                                  if back: others <- {type: "peer_joined", id, back: true}
//   player -> server  {type: "signal", to, data}   to     <- {type: "signal", from, data}
//   player -> server  {type: "lost", id}           (drops player id if it stopped pinging, or isn't back)
//   others <- {type: "peer_left", id, host}        anyone <- {type: "error", message, reason}
// `peers` and `players` are in the order the players came (`players` includes
// the player itself). An error with reason "no_room" answers a join for a code
// with no room: after a restart, perhaps not yet.

import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { WebSocketServer } from 'ws';

const PORT = Number(process.env.PORT ?? 8070);
const ICE_SERVERS = process.env.ICE_SERVERS
  ? JSON.parse(process.env.ICE_SERVERS)
  : [{ urls: ['stun:stun.l.google.com:19302'] }];
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS ?? '').split(',').map((o) => o.trim()).filter(Boolean);
const MAX_PLAYERS = 8;
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
 * code -> {code, host, players: Map<id, player>}, players in the order they
 * came: their sockets ({room, id, key, since, seen, back}), or, after a
 * restart, places kept for those not back yet ({away: true, id, since, at}).
 */
const rooms = new Map();

const http = createServer((request, response) => {
  // A plain GET is a health check.
  response.writeHead(200, { 'content-type': 'text/plain' });
  response.end(`signaling ok, ${rooms.size} rooms\n`);
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
    if (!isBinary && raw.toString() === 'ping') return socket.send('pong');
    let message;
    try {
      message = JSON.parse(isBinary ? '' : raw.toString());
    } catch {
      return send(socket, { type: 'error', message: 'Bad message' });
    }
    handle(socket, message);
  });
  socket.on('close', () => leave(socket));
});

function handle(socket, message) {
  switch (message?.type) {
    case 'host': {
      if (socket.room) return send(socket, { type: 'error', message: 'Already in a game' });
      const room = { code: newCode(), host: FIRST_HOST, players: new Map([[FIRST_HOST, socket]]) };
      rooms.set(room.code, room);
      Object.assign(socket, { room, id: FIRST_HOST, key: randomUUID(), since: Date.now() });
      send(socket, { type: 'hosted', code: room.code, id: FIRST_HOST, key: socket.key, ice: ICE_SERVERS });
      log(`room ${room.code} opened`);
      break;
    }
    case 'join': {
      if (socket.room) return send(socket, { type: 'error', message: 'Already in a game' });
      const code = String(message.code ?? '').trim().toUpperCase();
      const room = rooms.get(code);
      if (!room) return send(socket, { type: 'error', message: `No game with code ${code}`, reason: 'no_room' });
      // The lowest free number, so player numbers (and colors) stay small.
      let id = FIRST_HOST;
      while (room.players.has(id)) id++;
      if (id > MAX_PLAYERS) return send(socket, { type: 'error', message: 'That game is full' });
      const peers = [...room.players.keys()];
      room.players.set(id, socket);
      Object.assign(socket, { room, id, key: randomUUID(), since: Date.now() });
      send(socket, { type: 'joined', code, id, key: socket.key, host: room.host, peers, ice: ICE_SERVERS });
      for (const peer of peers) send(room.players.get(peer), { type: 'peer_joined', id });
      log(`room ${code}: player ${id} joined (${room.players.size} players)`);
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

/** A player coming back to its room after its socket dropped, or after we restarted. */
function rejoin(socket, message) {
  if (socket.room) return send(socket, { type: 'error', message: 'Already in a game' });
  const code = String(message.code ?? '').trim().toUpperCase();
  const id = Number(message.id);
  const key = String(message.key ?? '');
  if (!isCode(code) || !Number.isInteger(id) || id < FIRST_HOST || id > MAX_PLAYERS) {
    return send(socket, { type: 'error', message: 'Bad message' });
  }
  const room = rooms.get(code) ?? rebuild(code, id, message);
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
    if (room.players.size >= MAX_PLAYERS) return send(socket, { type: 'error', message: 'That game is full' });
    back = true;
  }
  room.players.set(id, socket); // (in their old place, if they had one)
  Object.assign(socket, { room, id, key, since, back });
  send(socket, { type: 'rejoined', code, id, host: room.host, players: [...room.players.keys()], back, ice: ICE_SERVERS });
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
 * in it, in the order they came, and who hosted. The places of all of them are
 * kept until they're back (the first takes its own at once).
 */
function rebuild(code, id, message) {
  const claimed = Array.isArray(message.players) ? message.players : [];
  const ids = [...new Set([...claimed, id].map(Number))]
    .filter((n) => Number.isInteger(n) && n >= FIRST_HOST && n <= MAX_PLAYERS);
  const host = ids.includes(Number(message.host)) ? Number(message.host) : id;
  const now = Date.now();
  const room = { code, host, players: new Map() };
  ids.forEach((n, i) => room.players.set(n, { away: true, id: n, since: now - ids.length + i, at: now }));
  rooms.set(code, room);
  log(`room ${code} rebuilt: players ${ids.join(', ')}, player ${host} hosting`);
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
