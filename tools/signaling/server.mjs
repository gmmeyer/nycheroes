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
// Usage: npm install && node server.mjs
// Environment:
//   PORT              port to listen on (default 8070)
//   ICE_SERVERS       JSON list of WebRTC ICE servers handed to players, e.g.
//                     [{"urls":"stun:stun.l.google.com:19302"},
//                      {"urls":"turn:turn.example.com:3478","username":"u","credential":"p"}]
//   ALLOWED_ORIGINS   comma-separated page origins allowed to connect (default: any)
//
// Protocol (JSON text messages, plus "ping"/"pong" as plain text):
//   player -> server  {type: "host"}               server -> {type: "hosted", code, id: 1, ice}
//   player -> server  {type: "join", code}         server -> {type: "joined", code, id, host, peers, ice}
//                                                  others <- {type: "peer_joined", id}
//   player -> server  {type: "signal", to, data}   to     <- {type: "signal", from, data}
//   player -> server  {type: "lost", id}           (drops player id if it stopped pinging)
//   others <- {type: "peer_left", id, host}        anyone <- {type: "error", message}

import { createServer } from 'node:http';
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

/** code -> {code, host, players: Map<id, socket>}, players in the order they came */
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
      Object.assign(socket, { room, id: FIRST_HOST });
      send(socket, { type: 'hosted', code: room.code, id: FIRST_HOST, ice: ICE_SERVERS });
      log(`room ${room.code} opened`);
      break;
    }
    case 'join': {
      if (socket.room) return send(socket, { type: 'error', message: 'Already in a game' });
      const code = String(message.code ?? '').trim().toUpperCase();
      const room = rooms.get(code);
      if (!room) return send(socket, { type: 'error', message: `No game with code ${code}` });
      // The lowest free number, so player numbers (and colors) stay small.
      let id = FIRST_HOST;
      while (room.players.has(id)) id++;
      if (id > MAX_PLAYERS) return send(socket, { type: 'error', message: 'That game is full' });
      const peers = [...room.players.keys()];
      room.players.set(id, socket);
      Object.assign(socket, { room, id });
      send(socket, { type: 'joined', code, id, host: room.host, peers, ice: ICE_SERVERS });
      for (const peer of peers) send(room.players.get(peer), { type: 'peer_joined', id });
      log(`room ${code}: player ${id} joined (${room.players.size} players)`);
      break;
    }
    case 'signal': {
      const target = socket.room?.players.get(Number(message.to));
      if (target && target !== socket) send(target, { type: 'signal', from: socket.id, data: message.data });
      break;
    }
    case 'lost': {
      const target = socket.room?.players.get(Number(message.id));
      if (target && target !== socket && Date.now() - target.seen > PING_TIMEOUT_MS) {
        log(`room ${socket.room.code}: player ${target.id} stopped pinging`);
        leave(target);
        target.terminate();
      }
      break;
    }
    default:
      send(socket, { type: 'error', message: 'Unknown message' });
  }
}

function leave(socket) {
  const room = socket.room;
  if (!room) return;
  socket.room = null;
  room.players.delete(socket.id);
  if (room.players.size === 0) {
    rooms.delete(room.code);
    log(`room ${room.code} closed`);
    return;
  }
  const wasHost = room.host === socket.id;
  if (wasHost) room.host = nextHost(room);
  for (const player of room.players.values()) send(player, { type: 'peer_left', id: socket.id, host: room.host });
  log(`room ${room.code}: player ${socket.id} left${wasHost ? `, player ${room.host} hosts now` : ''}`);
}

/** The player who has been in the room longest, of those still pinging if any. */
function nextHost(room) {
  const now = Date.now();
  for (const [id, player] of room.players) {
    if (now - player.seen <= PING_TIMEOUT_MS) return id;
  }
  return room.players.keys().next().value;
}

function newCode() {
  for (;;) {
    let code = '';
    for (let i = 0; i < CODE_LENGTH; i++) code += CODE_LETTERS[Math.floor(Math.random() * CODE_LETTERS.length)];
    if (!rooms.has(code)) return code;
  }
}

function send(socket, message) {
  if (socket && socket.readyState === socket.OPEN) socket.send(JSON.stringify(message));
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
