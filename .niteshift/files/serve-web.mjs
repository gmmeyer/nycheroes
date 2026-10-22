// The sandbox's preview of the web build: one origin, like the public site
// (tools/cloudflare/worker.mjs), so the game's own defaults work unchanged.
//   /           build/web (the export from .niteshift/files/build-web)
//   /tiles/...  the public site's city tiles (https://nycheroes.party/tiles/),
//               since building them here takes many GB of downloads (TILES_URL
//               points elsewhere)
//   /signal     WebSocket to the local signaling server (tools/signaling on
//               SIGNALING_PORT); the preview is https, so the game asks for
//               wss://<host>/signal
// Files are served with no-cache, so a reload after a rebuild picks it up.
// Usage: node serve-web.mjs  (PORT, default 8060)
import { createServer, request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { connect } from 'node:net';
import { createReadStream, statSync } from 'node:fs';
import { dirname, extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const WEB = join(ROOT, 'build', 'web');
const PORT = Number(process.env.PORT ?? 8060);
const SIGNALING_PORT = Number(process.env.SIGNALING_PORT ?? 8070);
const TILES_URL = new URL(process.env.TILES_URL ?? 'https://nycheroes.party/tiles/');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
  '.json': 'application/json',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

function log(...args) {
  console.log(new Date().toISOString(), ...args);
}

function serveFile(req, res, pathname) {
  let path = normalize(join(WEB, decodeURIComponent(pathname)));
  if (path !== WEB && !path.startsWith(WEB + sep)) {
    res.writeHead(403).end('Forbidden');
    return;
  }
  let stat;
  try {
    stat = statSync(path);
    if (stat.isDirectory()) {
      path = join(path, 'index.html');
      stat = statSync(path);
    }
  } catch {
    res.writeHead(404, { 'content-type': 'text/plain' }).end(
      pathname === '/' ? 'No web build yet: run .niteshift/files/build-web\n' : 'Not found\n');
    return;
  }
  res.writeHead(200, {
    'content-type': TYPES[extname(path)] ?? 'application/octet-stream',
    'content-length': stat.size,
    'cache-control': 'no-cache',
  });
  if (req.method === 'HEAD') {
    res.end();
    return;
  }
  createReadStream(path).pipe(res);
}

function proxyTile(req, res, pathname, search) {
  const target = new URL(pathname.slice('/tiles/'.length) + search, TILES_URL);
  const headers = {};
  for (const name of ['accept', 'accept-encoding', 'if-none-match', 'if-modified-since', 'range']) {
    if (req.headers[name]) headers[name] = req.headers[name];
  }
  const upstream = httpsRequest(target, { method: req.method, headers }, (up) => {
    const out = {};
    for (const name of ['content-type', 'content-length', 'content-encoding', 'etag', 'last-modified',
      'cache-control', 'content-range', 'accept-ranges']) {
      if (up.headers[name]) out[name] = up.headers[name];
    }
    res.writeHead(up.statusCode ?? 502, out);
    up.pipe(res);
  });
  upstream.setTimeout(30000, () => upstream.destroy(new Error('timeout')));
  upstream.on('error', (err) => {
    log('tile proxy failed', target.href, err.message);
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'text/plain' });
    res.end('Tile proxy failed\n');
  });
  upstream.end();
}

function proxySignalingCheck(req, res) {
  const upstream = httpRequest({ host: '127.0.0.1', port: SIGNALING_PORT, path: '/', method: 'GET' }, (up) => {
    res.writeHead(up.statusCode ?? 502, { 'content-type': up.headers['content-type'] ?? 'text/plain' });
    up.pipe(res);
  });
  upstream.on('error', () => res.writeHead(502, { 'content-type': 'text/plain' }).end('Signaling server down\n'));
  upstream.end();
}

const server = createServer((req, res) => {
  const url = new URL(req.url ?? '/', 'http://localhost');
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405).end();
  } else if (url.pathname.startsWith('/tiles/')) {
    proxyTile(req, res, url.pathname, url.search);
  } else if (url.pathname === '/signal') {
    proxySignalingCheck(req, res);
  } else {
    serveFile(req, res, url.pathname);
  }
});

// WebSocket upgrades on /signal go to the signaling server as they are.
server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url ?? '/', 'http://localhost');
  if (url.pathname !== '/signal') {
    socket.destroy();
    return;
  }
  const upstream = connect(SIGNALING_PORT, '127.0.0.1', () => {
    let raw = `${req.method} / HTTP/1.1\r\n`;
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      raw += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\r\n`;
    }
    upstream.write(raw + '\r\n');
    if (head.length) upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });
  upstream.on('error', (err) => {
    log('signaling proxy failed', err.message);
    socket.destroy();
  });
  socket.on('error', () => upstream.destroy());
});

server.listen(PORT, () => log(`serving ${WEB} on port ${PORT}; tiles from ${TILES_URL.href}; /signal -> :${SIGNALING_PORT}`));
