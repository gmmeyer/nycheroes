// Screenshots the game at the reference camera poses (tools/reference/views.json)
// in headless Chrome, driven over the Chrome DevTools Protocol.
//
// Usage: node tools/reference/shoot.mjs --chrome <chrome.exe> --url <index.html URL>
//          --out <dir> --views <views.json> [--only a,b] [--width 2560] [--height 1440]
//          [--port 9384] [--settle 6000] [--timeout 300000] [--profile <dir>]
//          [--query weather=overcast]
//
// Each view loads <url>?cam=...&spawn=...&quality=high&gangs=0[&extra][&query],
// waits for the game's "[city] ... ready" log (no tile left to load), lets props
// and trees settle, and saves <out>/<name>.png plus <out>/report.json (views
// shot earlier into the same folder keep their entries). --query adds launch
// options to every view (a view's extra_query adds them to one). compare.py
// runs this; it can also be run on its own. --profile keeps Chrome's cache
// between runs (faster reruns; by default every run starts from a clean
// temporary profile and downloads the game again, about 100 MB).
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const args = {};
for (let i = 2; i < process.argv.length; i += 2) args[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
const width = Number(args.width ?? 2560);
const height = Number(args.height ?? 1440);
const port = Number(args.port ?? 9384);
const settleMs = Number(args.settle ?? 6000);
const timeoutMs = Number(args.timeout ?? 300000);
const only = args.only ? new Set(args.only.split(',')) : null;
const views = JSON.parse(readFileSync(args.views, 'utf8')).views.filter((v) => !only || only.has(v.name));
mkdirSync(args.out, { recursive: true });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const keepProfile = Boolean(args.profile);
const profile = keepProfile ? args.profile : mkdtempSync(join(tmpdir(), 'reference-cdp-'));
mkdirSync(profile, { recursive: true });
const browser = spawn(args.chrome, [
  '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  `--window-size=${width},${height}`, '--ignore-gpu-blocklist', '--no-first-run',
  '--no-default-browser-check', '--hide-scrollbars', 'about:blank',
], { stdio: 'ignore' });

function viewQuery(view) {
  const parts = [`cam=${view.cam}`];
  if (view.spawn) parts.push(`spawn=${view.spawn}`);
  parts.push('quality=high', 'gangs=0');
  if (view.extra_query) parts.push(view.extra_query);
  if (args.query) parts.push(args.query);
  return parts.join('&');
}

try {
  let targets;
  for (let i = 0; i < 100 && !targets; i++) {
    try { targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); } catch { await sleep(200); }
  }
  const page = targets.find((t) => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r, { once: true }));
  let nextId = 0;
  const pending = new Map();
  let logs = [];
  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
    else if (msg.method === 'Runtime.consoleAPICalled') {
      logs.push(msg.params.args.map((a) => a.value ?? a.description ?? '').join(' '));
    } else if (msg.method === 'Runtime.exceptionThrown') {
      const d = msg.params.exceptionDetails;
      logs.push('[exception] ' + (d.exception?.description ?? d.text));
    }
  });
  const send = (method, params = {}) => new Promise((r) => {
    const id = ++nextId; pending.set(id, r); ws.send(JSON.stringify({ id, method, params }));
  });
  await send('Runtime.enable');
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
  await send('Emulation.setFocusEmulationEnabled', { enabled: true });

  const report = [];
  for (const view of views) {
    logs = [];
    const started = Date.now();
    const url = `${args.url}?${viewQuery(view)}`;
    await send('Page.navigate', { url });
    let readyAt = null;
    while (Date.now() - started < timeoutMs) {
      if (logs.some((l) => l.includes('[city]') && l.includes('ready'))) { readyAt = Date.now() - started; break; }
      await sleep(250);
    }
    await sleep(view.settle_ms ?? settleMs);
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(join(args.out, `${view.name}.png`), Buffer.from(shot.result.data, 'base64'));
    report.push({ view: view.name, url, readyMs: readyAt, logs: logs.filter((l) => !l.includes('[stats]')).slice(-25) });
    console.log(`${view.name}: ${readyAt === null ? 'NOT READY (timeout)' : `ready in ${(readyAt / 1000).toFixed(1)} s`}`);
  }
  const reportPath = join(args.out, 'report.json');
  if (existsSync(reportPath)) {  // keep the views shot earlier into this folder
    const shot = new Set(report.map((r) => r.view));
    report.unshift(...JSON.parse(readFileSync(reportPath, 'utf8')).report.filter((r) => !shot.has(r.view)));
  }
  writeFileSync(reportPath, JSON.stringify({
    width, height, url: args.url, query: args.query ?? '', taken: new Date().toISOString(), report,
  }, null, 2));
  ws.close();
} finally {
  browser.kill();
  await sleep(500);
  if (!keepProfile) {
    try { rmSync(profile, { recursive: true, force: true }); } catch { /* Chrome may still hold files */ }
  }
}
