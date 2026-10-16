// The public web build on Cloudflare: one Worker that serves the game and its
// city tiles as static assets, the engine (index.wasm, too big for a static
// asset) from an R2 bucket, and co-op signaling at /signal from a Durable
// Object (the same protocol as tools/signaling/server.mjs, which stays the
// local server, plus TURN relay credentials for players whose networks block
// direct connections). Deploy with tools/deploy_cloudflare.ps1.

const MAX_PLAYERS = 8;
const HOST_ID = 1;
// No 0/O, 1/I/L: codes get read out loud and typed.
const CODE_LETTERS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 4;
const MAX_MESSAGE = 64 * 1024;
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

// Rooms of players, kept in the sockets' attachments ({code, id}) so they
// survive the Durable Object sleeping between messages.
export class Rooms {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.ice = null; // {servers: Promise, until}: the ICE servers being handed out
  }

  async fetch() {
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({});
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket, raw) {
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
        socket.serializeAttachment({ code, id: HOST_ID });
        send(socket, { type: 'hosted', code, id: HOST_ID, ice });
        break;
      }
      case 'join': {
        if (me.code) return send(socket, { type: 'error', message: 'Already in a game' });
        const code = String(message.code ?? '').trim().toUpperCase();
        const players = this.players(code);
        if (!players.has(HOST_ID)) return send(socket, { type: 'error', message: `No game with code ${code}` });
        // The lowest free number, so player numbers (and colors) stay small.
        let id = HOST_ID + 1;
        while (players.has(id)) id++;
        if (id > MAX_PLAYERS) return send(socket, { type: 'error', message: 'That game is full' });
        socket.serializeAttachment({ code, id });
        send(socket, { type: 'joined', code, id, ice });
        // The host's credentials may be older than a long game; these are fresh.
        send(players.get(HOST_ID), { type: 'peer_joined', id, ice });
        break;
      }
      case 'signal': {
        const to = Number(message.to);
        // Only host <-> player pairs talk.
        if (!me.code || (me.id !== HOST_ID && to !== HOST_ID)) return;
        send(this.players(me.code).get(to), { type: 'signal', from: me.id, data: message.data });
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

  leave(socket) {
    const me = socket.deserializeAttachment() ?? {};
    if (!me.code) return;
    socket.serializeAttachment({});
    const players = this.players(me.code);
    if (me.id === HOST_ID) {
      for (const player of players.values()) {
        send(player, { type: 'room_closed' });
        player.serializeAttachment({});
      }
    } else {
      send(players.get(HOST_ID), { type: 'peer_left', id: me.id });
    }
  }

  /** The open sockets in room `code`, by player id. */
  players(code) {
    const found = new Map();
    for (const socket of this.ctx.getWebSockets()) {
      const them = socket.deserializeAttachment() ?? {};
      if (them.code === code) found.set(them.id, socket);
    }
    return found;
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
    socket.send(JSON.stringify(message));
  } catch {
    // Closed meanwhile.
  }
}
