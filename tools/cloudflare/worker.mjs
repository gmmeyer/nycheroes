// The public web build on Cloudflare: one Worker that serves the game and its
// city tiles as static assets, the engine (index.wasm, too big for a static
// asset) from an R2 bucket, and co-op signaling at /signal from a Durable
// Object (the same protocol as tools/signaling/server.mjs, which stays the
// local server, plus TURN relay credentials for players whose networks block
// direct connections). Deploy with tools/deploy_cloudflare.ps1.

const MAX_PLAYERS = 8;
const FIRST_HOST = 1;
// No 0/O, 1/I/L: codes get read out loud and typed.
const CODE_LETTERS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 4;
const MAX_MESSAGE = 64 * 1024;
// Players ping ("ping", answered "pong" without waking the object) every 10 s;
// one that hasn't for this long is gone, if another player says it lost touch.
const PING_TIMEOUT_MS = 25000;
// STUN only: what players get when the TURN relay isn't available.
const ICE_SERVERS = [{ urls: ['stun:stun.l.google.com:19302', 'stun:stun.cloudflare.com:3478'] }];
// Cloudflare's TURN relay (Realtime TURN), from the TURN key in the Worker
// secrets TURN_KEY_ID and TURN_KEY_API_TOKEN (tools/cloudflare/.dev.vars for
// `wrangler dev`). It hands out short-lived credentials for it.
const TURN_API = 'https://rtc.live.cloudflare.com/v1/turn/keys';
// A relayed connection drops when its credentials expire, so they outlast a
// long evening's game (seconds).
const TURN_TTL = 6 * 3600;
// Players hosting or joining within this long share credentials, so a burst
// of joins asks Cloudflare once; after a failed request, STUN only for a bit.
const TURN_REUSE_MS = 5 * 60 * 1000;
const TURN_RETRY_MS = 30 * 1000;
const TURN_TIMEOUT_MS = 3000;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/signal') {
      if (request.headers.get('Upgrade') !== 'websocket') {
        return new Response('signaling ok\n', { headers: { 'content-type': 'text/plain' } });
      }
      // One room keeper for everyone: a few games at a time fit easily.
      return env.ROOMS.get(env.ROOMS.idFromName('lobby')).fetch(request);
    }
    if (url.pathname === '/index.wasm') {
      return wasm(request, env);
    }
    return env.ASSETS.fetch(request);
  },
};

async function wasm(request, env) {
  const object = await env.FILES.get('index.wasm', { onlyIf: request.headers });
  if (object === null) {
    return new Response('Not found', { status: 404 });
  }
  const headers = new Headers({
    'content-type': 'application/wasm',
    etag: object.httpEtag,
    // Revalidate every load, so a new build is picked up right away.
    'cache-control': 'public, max-age=0, must-revalidate',
  });
  if (!('body' in object) || !object.body) {
    return new Response(null, { status: 304, headers });
  }
  return new Response(object.body, { headers });
}

// Rooms of players, kept in the sockets' attachments ({code, id, since, host})
// so they survive the Durable Object sleeping between messages. Players
// connect to each other in a full mesh. One is the host (`host` is set on it):
// first the one who opened the room; when the host leaves, the player who has
// been in the room longest takes over, passing over any who stopped pinging
// (see tools/signaling/server.mjs for the protocol). A room and its code last
// until its last player leaves.
export class Rooms {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.ice = null; // {servers: Promise, until}: the ICE servers being handed out
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  async fetch() {
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({});
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket, raw) {
    if (raw === 'ping') return send(socket, 'pong'); // (normally answered without waking us)
    let message;
    try {
      if (typeof raw !== 'string' || raw.length > MAX_MESSAGE) throw new Error();
      message = JSON.parse(raw);
    } catch {
      return send(socket, { type: 'error', message: 'Bad message' });
    }
    // Hosting and joining hand out ICE servers: get them first, so the rooms
    // can't change between the checks below and the replies.
    const ice = message?.type === 'host' || message?.type === 'join' ? await this.iceServers() : null;
    const me = socket.deserializeAttachment() ?? {};
    switch (message?.type) {
      case 'host': {
        if (me.code) return send(socket, { type: 'error', message: 'Already in a game' });
        const code = this.newCode();
        socket.serializeAttachment({ code, id: FIRST_HOST, since: Date.now(), host: true });
        send(socket, { type: 'hosted', code, id: FIRST_HOST, ice });
        break;
      }
      case 'join': {
        if (me.code) return send(socket, { type: 'error', message: 'Already in a game' });
        const code = String(message.code ?? '').trim().toUpperCase();
        const players = this.players(code);
        if (players.size === 0) return send(socket, { type: 'error', message: `No game with code ${code}` });
        // The lowest free number, so player numbers (and colors) stay small.
        let id = FIRST_HOST;
        while (players.has(id)) id++;
        if (id > MAX_PLAYERS) return send(socket, { type: 'error', message: 'That game is full' });
        socket.serializeAttachment({ code, id, since: Date.now() });
        send(socket, { type: 'joined', code, id, host: this.hostOf(players), peers: [...players.keys()], ice });
        // Everyone there sends the newcomer an offer. Their credentials may be
        // older than a long game; these are fresh.
        for (const player of players.values()) send(player, { type: 'peer_joined', id, ice });
        break;
      }
      case 'signal': {
        const target = me.code && this.players(me.code).get(Number(message.to));
        if (target && target !== socket) send(target, { type: 'signal', from: me.id, data: message.data });
        break;
      }
      case 'lost': {
        // Someone lost touch with this player: if it stopped pinging too, its
        // connection died without closing.
        const target = me.code && this.players(me.code).get(Number(message.id));
        if (target && target !== socket && Date.now() - this.lastSeen(target) > PING_TIMEOUT_MS) {
          this.leave(target);
          try {
            target.close(1001, 'Stopped pinging');
          } catch {
            // Already closed.
          }
        }
        break;
      }
      default:
        send(socket, { type: 'error', message: 'Unknown message' });
    }
  }

  async webSocketClose(socket) {
    this.leave(socket);
  }

  async webSocketError(socket) {
    this.leave(socket);
  }

  /** Takes a player out of their room, handing it to a new host if they hosted. */
  leave(socket) {
    const me = socket.deserializeAttachment() ?? {};
    if (!me.code) return;
    socket.serializeAttachment({});
    const players = this.players(me.code);
    if (players.size === 0) return;
    if (me.host) {
      // The player who has been in the room longest, of those still pinging if any.
      const now = Date.now();
      const next = [...players.values()].find((player) => now - this.lastSeen(player) <= PING_TIMEOUT_MS)
        ?? players.values().next().value;
      next.serializeAttachment({ ...next.deserializeAttachment(), host: true });
    }
    const host = this.hostOf(players);
    for (const player of players.values()) send(player, { type: 'peer_left', id: me.id, host });
  }

  /** The id of the host of a room (its players, from players()). */
  hostOf(players) {
    for (const [id, socket] of players) {
      if (socket.deserializeAttachment()?.host) return id;
    }
    return players.keys().next().value;
  }

  /** The open sockets in room `code`, by player id, in the order they came. */
  players(code) {
    const found = [];
    for (const socket of this.ctx.getWebSockets()) {
      const them = socket.deserializeAttachment() ?? {};
      if (them.code === code) found.push([them, socket]);
    }
    found.sort(([a], [b]) => (a.since ?? 0) - (b.since ?? 0) || a.id - b.id);
    return new Map(found.map(([them, socket]) => [them.id, socket]));
  }

  /** When a player was last heard from: their last ping, or when they came. */
  lastSeen(socket) {
    const pinged = this.ctx.getWebSocketAutoResponseTimestamp(socket)?.getTime() ?? 0;
    return Math.max(pinged, socket.deserializeAttachment()?.since ?? 0);
  }

  newCode() {
    for (;;) {
      let code = '';
      for (let i = 0; i < CODE_LENGTH; i++) code += CODE_LETTERS[Math.floor(Math.random() * CODE_LETTERS.length)];
      if (this.players(code).size === 0) return code;
    }
  }

  /** STUN and TURN servers for a player, with credentials shared for a few minutes. */
  iceServers() {
    if (!this.ice || Date.now() > this.ice.until) {
      // Players asking while the request is out wait for the same answer.
      const ice = (this.ice = { servers: turnServers(this.env), until: Infinity });
      ice.servers.then((servers) => {
        ice.until = Date.now() + (servers === ICE_SERVERS ? TURN_RETRY_MS : TURN_REUSE_MS);
      });
    }
    return this.ice.servers;
  }
}

/** Cloudflare's STUN and TURN servers with fresh credentials, else STUN only. */
async function turnServers(env) {
  if (!env.TURN_KEY_ID || !env.TURN_KEY_API_TOKEN) return ICE_SERVERS;
  try {
    const response = await fetch(`${TURN_API}/${env.TURN_KEY_ID}/credentials/generate-ice-servers`, {
      method: 'POST',
      headers: { authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify({ ttl: TURN_TTL }),
      signal: AbortSignal.timeout(TURN_TIMEOUT_MS),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const { iceServers } = await response.json();
    if (!Array.isArray(iceServers)) throw new Error('no iceServers');
    // Browsers block port 53, so trying it would only slow connecting down.
    const servers = iceServers
      .map((server) => ({ ...server, urls: [server.urls].flat().filter((url) => !/:53(\?|$)/.test(url)) }))
      .filter((server) => server.urls.length > 0);
    if (!servers.some((server) => server.username)) throw new Error('no TURN server');
    return servers;
  } catch (error) {
    console.log(`TURN credentials unavailable (${error}), handing out STUN only`);
    return ICE_SERVERS;
  }
}

function send(socket, message) {
  if (!socket) return;
  try {
    socket.send(typeof message === 'string' ? message : JSON.stringify(message));
  } catch {
    // Closed meanwhile.
  }
}
