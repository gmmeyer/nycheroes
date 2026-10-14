// Signaling server for co-op: introduces players so their browsers can connect
// to each other directly over WebRTC. Game traffic never passes through here.
//
// The host asks for a room and gets a short code; friends join with the code.
// The server then relays WebRTC offers, answers and network candidates between
// the host and each player (players only ever talk to the host, so they never
// learn each other's addresses).
//
// Usage: npm install && node server.mjs
// Environment:
//   PORT              port to listen on (default 8070)
//   ICE_SERVERS       JSON list of WebRTC ICE servers handed to players, e.g.
//                     [{"urls":"stun:stun.l.google.com:19302"},
//                      {"urls":"turn:turn.example.com:3478","username":"u","credential":"p"}]
//   ALLOWED_ORIGINS   comma-separated page origins allowed to connect (default: any)
//
// Protocol (JSON text messages):
//   player -> server  {type: "host"}                     server -> {type: "hosted", code, id: 1, ice}
//   player -> server  {type: "join", code}               server -> {type: "joined", code, id, ice}
//                                                        host   <- {type: "peer_joined", id}
//   player -> server  {type: "signal", to, data}         to     <- {type: "signal", from, data}
//   host   <- {type: "peer_left", id}   players <- {type: "room_closed"}   anyone <- {type: "error", message}

import { createServer } from 'node:http';
import { WebSocketServer } from 'ws';

const PORT = Number(process.env.PORT ?? 8070);
const ICE_SERVERS = process.env.ICE_SERVERS
  ? JSON.parse(process.env.ICE_SERVERS)
  : [{ urls: ['stun:stun.l.google.com:19302'] }];
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS ?? '').split(',').map((o) => o.trim()).filter(Boolean);
const MAX_PLAYERS = 8;
const HOST_ID = 1;
// No 0/O, 1/I/L: codes get read out loud and typed.
const CODE_LETTERS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 4;
const HEARTBEAT_MS = 30000;

/** code -> {code, players: Map<id, socket>} */
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
  socket.on('pong', () => { socket.alive = true; });
  socket.on('message', (raw, isBinary) => {
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
      const room = { code: newCode(), players: new Map([[HOST_ID, socket]]) };
      rooms.set(room.code, room);
      Object.assign(socket, { room, id: HOST_ID });
      send(socket, { type: 'hosted', code: room.code, id: HOST_ID, ice: ICE_SERVERS });
      log(`room ${room.code} opened`);
      break;
    }
    case 'join': {
      if (socket.room) return send(socket, { type: 'error', message: 'Already in a game' });
      const code = String(message.code ?? '').trim().toUpperCase();
      const room = rooms.get(code);
      if (!room) return send(socket, { type: 'error', message: `No game with code ${code}` });
      // The lowest free number, so player numbers (and colors) stay small.
      let id = HOST_ID + 1;
      while (room.players.has(id)) id++;
      if (id > MAX_PLAYERS) return send(socket, { type: 'error', message: 'That game is full' });
      room.players.set(id, socket);
      Object.assign(socket, { room, id });
      send(socket, { type: 'joined', code, id, ice: ICE_SERVERS });
      send(room.players.get(HOST_ID), { type: 'peer_joined', id });
      log(`room ${code}: player ${id} joined (${room.players.size} players)`);
      break;
    }
    case 'signal': {
      const room = socket.room;
      const to = Number(message.to);
      // Only host <-> player pairs talk.
      if (!room || (socket.id !== HOST_ID && to !== HOST_ID)) return;
      const target = room.players.get(to);
      if (target) send(target, { type: 'signal', from: socket.id, data: message.data });
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
  if (socket.id === HOST_ID) {
    for (const player of room.players.values()) {
      send(player, { type: 'room_closed' });
      player.room = null;
    }
    rooms.delete(room.code);
    log(`room ${room.code} closed`);
  } else {
    send(room.players.get(HOST_ID), { type: 'peer_left', id: socket.id });
    log(`room ${room.code}: player ${socket.id} left`);
  }
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
