// The public web build on Cloudflare: one Worker that serves the game and its
// city tiles as static assets, the engine (index.wasm, too big for a static
// asset) and the Windows and Mac versions' zips (downloads/, see
// tools/build_desktop.ps1) from an R2 bucket, and co-op signaling at /signal from a Durable
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
// Players come back within seconds of a restart; one that hasn't after this
// long is gone, if another player says it lost touch.
const AWAY_TIMEOUT_MS = 10000;
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
    if (DOWNLOADS.includes(url.pathname)) {
      return download(request, env, url.pathname.slice(1));
    }
    return env.ASSETS.fetch(request);
  },
};

// The desktop versions (tools/deploy_cloudflare.ps1 -Desktop uploads them).
const DOWNLOADS = ['/downloads/nyc-heroes-windows.zip', '/downloads/nyc-heroes-macos.zip'];

// A zip from R2, resumable (Range requests); browsers keep it for a few
// minutes, so a new version shows up soon after it's uploaded. HEAD (the
// downloads page asks for the sizes) doesn't read the file.
async function download(request, env, key) {
  const head = request.method === 'HEAD';
  const range = request.headers.has('range') ? request.headers : undefined;
  const object = head ? await env.FILES.head(key) : await env.FILES.get(key, { onlyIf: request.headers, range });
  if (object === null) {
    return new Response('Not found', { status: 404 });
  }
  const headers = new Headers({
    'content-type': 'application/zip',
    'content-disposition': `attachment; filename="${key.split('/').pop()}"`,
    'accept-ranges': 'bytes',
    etag: object.httpEtag,
    'cache-control': 'public, max-age=300',
  });
  if (head) {
    headers.set('content-length', String(object.size));
    return new Response(null, { headers });
  }
  if (!('body' in object) || !object.body) {
    return new Response(null, { status: 304, headers });
  }
  if (range && object.range) {
    const start = object.range.offset ?? object.size - object.range.suffix;
    const length = object.range.length ?? object.size - start;
    headers.set('content-range', `bytes ${start}-${start + length - 1}/${object.size}`);
    return new Response(object.body, { status: 206, headers });
  }
  return new Response(object.body, { headers });
}

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

// Rooms of players, kept in the sockets' attachments ({code, id, since, key,
// host, back}) so they survive the Durable Object sleeping between messages.
// Players connect to each other in a full mesh. One is the host (`host` is set
// on it): first the one who opened the room; when the host leaves, the player
// who has been in the room longest takes over, passing over any who stopped
// pinging (see tools/signaling/server.mjs for the protocol). A room and its
// code last until its last player leaves.
//
// A restart (a deploy) loses every room and closes every socket; the players
// play on, come back and rebuild their rooms ("rejoin"). Until they're all
// back, the places of those still away are kept in storage, under
// "away:<code>" ({[id]: {since, at, host}}), as they have no socket to carry
// them.
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
    // Hosting, joining and rejoining hand out ICE servers: get them first, so
    // the rooms can't change between the checks below and the replies.
    const ice = ['host', 'join', 'rejoin'].includes(message?.type) ? await this.iceServers() : null;
    const me = socket.deserializeAttachment() ?? {};
    switch (message?.type) {
      case 'host': {
        if (me.code) return send(socket, { type: 'error', message: 'Already in a game' });
        const code = this.newCode();
        const key = crypto.randomUUID();
        this.setAway(code, {}); // (left from a room that had this code before a restart)
        socket.serializeAttachment({ code, id: FIRST_HOST, since: Date.now(), key, host: true });
        send(socket, { type: 'hosted', code, id: FIRST_HOST, key, ice });
        break;
      }
      case 'join': {
        if (me.code) return send(socket, { type: 'error', message: 'Already in a game' });
        const code = String(message.code ?? '').trim().toUpperCase();
        const players = this.players(code);
        if (players.size === 0) return send(socket, { type: 'error', message: `No game with code ${code}`, reason: 'no_room' });
        // The lowest free number, so player numbers (and colors) stay small.
        let id = FIRST_HOST;
        while (players.has(id)) id++;
        if (id > MAX_PLAYERS) return send(socket, { type: 'error', message: 'That game is full' });
        const key = crypto.randomUUID();
        socket.serializeAttachment({ code, id, since: Date.now(), key });
        send(socket, { type: 'joined', code, id, key, host: this.hostOf(players), peers: [...players.keys()], ice });
        // Everyone there sends the newcomer an offer. Their credentials may be
        // older than a long game; these are fresh.
        for (const player of players.values()) send(player, { type: 'peer_joined', id, ice });
        break;
      }
      case 'rejoin':
        this.rejoin(socket, message, ice);
        break;
      case 'signal': {
        const target = me.code && this.players(me.code).get(Number(message.to));
        if (target && target !== socket) send(target, { type: 'signal', from: me.id, data: message.data });
        break;
      }
      case 'lost': {
        // Someone lost touch with this player: if it stopped pinging too, its
        // connection died without closing; if it isn't back since a restart,
        // it isn't coming.
        const target = me.code && this.players(me.code).get(Number(message.id));
        if (target && target !== socket && this.gone(target)) {
          this.leave(target);
          if (!target.away) {
            try {
              target.close(1001, 'Stopped pinging');
            } catch {
              // Already closed.
            }
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

  /** A player coming back to its room after its socket dropped, or after we restarted. */
  rejoin(socket, message, ice) {
    if (socket.deserializeAttachment()?.code) return send(socket, { type: 'error', message: 'Already in a game' });
    const code = String(message.code ?? '').trim().toUpperCase();
    const id = Number(message.id);
    const key = String(message.key ?? '');
    if (!isCode(code) || !Number.isInteger(id) || id < FIRST_HOST || id > MAX_PLAYERS) {
      return send(socket, { type: 'error', message: 'Bad message' });
    }
    const found = this.players(code);
    const players = found.size > 0 ? found : this.rebuild(code, id, message);
    const there = players.get(id);
    let since = Date.now();
    let host = false;
    let back = false;
    let missed = [];
    if (there && !there.away) {
      // Their old socket is still open here: it dropped on their side first.
      const them = there.deserializeAttachment() ?? {};
      if (them.key !== key) return send(socket, { type: 'error', message: `Someone else is player ${id} in game ${code} now` });
      ({ since, host = false } = them);
      there.serializeAttachment({});
      try {
        there.close(1000, 'Rejoined');
      } catch {
        // Already closed.
      }
    } else if (there) {
      ({ since, host = false } = there);
      const away = this.away(code);
      delete away[id];
      this.setAway(code, away);
      // Players who joined meanwhile wait for an offer from them.
      missed = [...players.values()].filter((player) => !player.away && info(player).since >= there.at);
    } else {
      // The room let them go meanwhile: everyone connects to them again.
      if (players.size >= MAX_PLAYERS) return send(socket, { type: 'error', message: 'That game is full' });
      back = true;
    }
    socket.serializeAttachment({ code, id, since, key, ...(host && { host }), ...(back && { back }) });
    const now = this.players(code);
    send(socket, { type: 'rejoined', code, id, host: this.hostOf(now), players: [...now.keys()], back, ice });
    for (const player of missed) send(socket, { type: 'peer_joined', id: info(player).id, back: info(player).back });
    if (back) {
      for (const player of now.values()) {
        if (player !== socket) send(player, { type: 'peer_joined', id, back: true, ice });
      }
    }
  }

  /**
   * A room we lost (a restart), as the first player back says it was: who was
   * in it, in the order they came, and who hosted. The places of all of them
   * are kept until they're back (the first takes its own at once). Returns its
   * players (all away), as players() does.
   */
  rebuild(code, id, message) {
    const claimed = Array.isArray(message.players) ? message.players : [];
    const ids = [...new Set([...claimed, id].map(Number))]
      .filter((n) => Number.isInteger(n) && n >= FIRST_HOST && n <= MAX_PLAYERS);
    const host = ids.includes(Number(message.host)) ? Number(message.host) : id;
    const now = Date.now();
    // Places left from rooms nobody came back to go.
    const open = new Set(this.ctx.getWebSockets().map((socket) => socket.deserializeAttachment()?.code));
    for (const [name] of [...this.ctx.storage.kv.list({ prefix: 'away:' })]) {
      if (!open.has(name.slice('away:'.length))) this.ctx.storage.kv.delete(name);
    }
    const away = {};
    ids.forEach((n, i) => { away[n] = { since: now - ids.length + i, at: now, ...(n === host && { host: true }) }; });
    this.setAway(code, away);
    return new Map(ids.map((n) => [n, { ...away[n], away: true, code, id: n }]));
  }

  /** Takes a player (a socket, or a place kept for one) out of their room, handing it to a new host if they hosted. */
  leave(player) {
    const me = info(player);
    if (!me.code) return;
    if (player.away) {
      const away = this.away(me.code);
      delete away[me.id];
      this.setAway(me.code, away);
    } else {
      player.serializeAttachment({});
    }
    const players = this.players(me.code);
    if (players.size === 0) {
      this.setAway(me.code, {}); // nobody's here (any still away can rebuild it)
      return;
    }
    if (me.host) {
      // The player who has been in the room longest, of those here and still pinging if any.
      const now = Date.now();
      const here = [...players.values()].filter((other) => !other.away);
      const next = here.find((other) => now - this.lastSeen(other) <= PING_TIMEOUT_MS) ?? here[0];
      next.serializeAttachment({ ...next.deserializeAttachment(), host: true });
    }
    const host = this.hostOf(players);
    for (const other of players.values()) send(other, { type: 'peer_left', id: me.id, host });
  }

  /** The id of the host of a room (its players, from players()). */
  hostOf(players) {
    for (const [id, player] of players) {
      if (info(player).host) return id;
    }
    return players.keys().next().value;
  }

  /**
   * Everyone in room `code`, by player id, in the order they came: their open
   * sockets, and (after a restart) places kept for those not back yet
   * ({away: true, code, id, since, at, host}). With nobody here, there's no room.
   */
  players(code) {
    const found = [];
    for (const socket of this.ctx.getWebSockets()) {
      const them = socket.deserializeAttachment() ?? {};
      if (them.code === code) found.push([them, socket]);
    }
    if (found.length > 0) {
      for (const [id, them] of Object.entries(this.away(code))) {
        const place = { ...them, away: true, code, id: Number(id) };
        found.push([place, place]);
      }
    }
    found.sort(([a], [b]) => (a.since ?? 0) - (b.since ?? 0) || a.id - b.id);
    return new Map(found.map(([them, player]) => [them.id, player]));
  }

  /** Places kept in room `code` for players not back since a restart, by player id. */
  away(code) {
    return this.ctx.storage.kv.get(`away:${code}`) ?? {};
  }

  setAway(code, away) {
    if (Object.keys(away).length > 0) {
      this.ctx.storage.kv.put(`away:${code}`, away);
    } else {
      this.ctx.storage.kv.delete(`away:${code}`);
    }
  }

  /** When a player was last heard from: their last ping, or when they came. */
  lastSeen(socket) {
    const pinged = this.ctx.getWebSocketAutoResponseTimestamp(socket)?.getTime() ?? 0;
    return Math.max(pinged, socket.deserializeAttachment()?.since ?? 0);
  }

  /** Whether a player another has lost touch with is gone: it stopped pinging, or isn't back since a restart. */
  gone(player) {
    return player.away ? Date.now() - player.at > AWAY_TIMEOUT_MS : Date.now() - this.lastSeen(player) > PING_TIMEOUT_MS;
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

/** What a player in a room is: a socket's attachment, or a place kept for one away. */
function info(player) {
  return player.away ? player : player.deserializeAttachment() ?? {};
}

function isCode(code) {
  return code.length === CODE_LENGTH && [...code].every((letter) => CODE_LETTERS.includes(letter));
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
  if (!socket || socket.away) return;
  try {
    socket.send(typeof message === 'string' ? message : JSON.stringify(message));
  } catch {
    // Closed meanwhile.
  }
}
