// Measures a first visit's shader compiling: opens the web build in headless
// Chrome with a fresh profile (so no shader cache), times every WebGL shader
// compile and program link until the city says it's ready, and prints the
// time to ready, the time spent waiting on the GPU process's compiler, and
// that time per shader (named after the shaders/*.gdshader whose uniforms it
// has) and per program. On Windows that compiler is ANGLE's D3D one, which is
// what makes first visits slow (see "Shader compile time" in docs/ROADMAP.md).
// The page's own WebGL calls are wrapped before it loads; a link is charged
// with the wait at the first query after it, when the compile really happens.
// Needs Node 22+ and Chrome; serve the build first (tools/build_web.ps1 -Serve).
// Usage: node shader_compile_check.mjs [url] [--cam=x,y,z,yaw,pitch] [--time=HH:MM]
//            [--port=9350] [--chrome=path] [--timeout=300]
//   e.g. node tools/shader_compile_check.mjs http://localhost:8060/
// The default view is Times Square at street level (tools/reference/views.json),
// with no pedestrians, thugs or traffic.
import { spawn } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const found = args.find((a) => a.startsWith(`--${name}=`));
  return found ? found.slice(name.length + 3) : fallback;
};
const url = args.find((a) => !a.startsWith('--')) ?? 'http://localhost:8060/';
const cam = option('cam', '13,16.1,-67,159.5,10.0');
const time = option('time', '');
const port = Number(option('port', '9350'));
const timeoutMs = Number(option('timeout', '300')) * 1000;
const chrome = option('chrome', process.platform === 'win32'
  ? 'C:/Program Files/Google/Chrome/Application/chrome.exe' : 'google-chrome');

// Each shader's own uniforms (not its includes'), to tell programs apart.
const shaderDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'shaders');
const uniformsOf = {};
for (const file of readdirSync(shaderDir).filter((f) => f.endsWith('.gdshader'))) {
  const code = readFileSync(join(shaderDir, file), 'utf8');
  uniformsOf[file] = [...code.matchAll(/^\s*uniform\s+\w+\s+(\w+)/gm)].map((m) => m[1]);
}
const nameOf = (source) => {
  let best = null;
  let bestCount = 0;
  for (const [file, uniforms] of Object.entries(uniformsOf)) {
    const count = uniforms.filter((u) => source.includes(`m_${u}`)).length;
    if (count > bestCount || (count === bestCount && count > 0 && uniforms.length < uniformsOf[best].length)) {
      best = file;
      bestCount = count;
    }
  }
  if (best && bestCount >= Math.min(2, uniformsOf[best].length)) return best;
  return source.includes('scene_data_block') ? '(other 3-D)' : '(engine)';
};
// What a program is for: Godot's specialization defines at the top of its source.
const variantOf = (source) => {
  const head = source.split('#define samplerExternalOES')[0];
  const has = (name) => new RegExp(`^#define ${name}$`, 'm').test(head);
  if (!source.includes('scene_data_block')) return '';
  if (!has('DISABLE_LIGHTMAP') && !has('USE_LIGHTMAP') && !has('USE_LIGHTMAP_CAPTURE')) return 'default (unused)';
  if (has('MODE_RENDER_DEPTH')) return has('RENDER_SHADOWS') ? 'shadow' : 'depth';
  return 'color';
};

// Injected before the page's scripts.
const hook = `(() => {
  const P = WebGL2RenderingContext.prototype;
  const now = () => performance.now();
  const sc = (window.__shaderCompile = { programs: [] });
  const shaders = new WeakMap();
  const programs = new WeakMap();
  const wrap = (name, fn) => { const orig = P[name]; P[name] = function (...a) { return fn.call(this, orig, ...a); }; };
  const timed = (fn) => function (orig, obj, ...a) {
    const t = now(); const r = orig.call(this, obj, ...a); fn(obj, now() - t); return r;
  };
  wrap('createShader', function (orig, type) {
    const s = orig.call(this, type); if (s) shaders.set(s, { type, source: '', ms: 0 }); return s;
  });
  wrap('shaderSource', function (orig, s, source) {
    const info = shaders.get(s); if (info) info.source = source; return orig.call(this, s, source);
  });
  for (const name of ['compileShader', 'getShaderParameter', 'getShaderInfoLog']) {
    wrap(name, timed((s, ms) => { const info = shaders.get(s); if (info) info.ms += ms; }));
  }
  wrap('attachShader', function (orig, p, s) {
    let info = programs.get(p);
    if (!info) { info = { shaders: [], ms: 0 }; programs.set(p, info); }
    info.shaders.push(s);
    return orig.call(this, p, s);
  });
  wrap('linkProgram', function (orig, p) {
    const info = programs.get(p); const t = now(); const r = orig.call(this, p);
    if (info) { info.ms += now() - t; info.at = t; sc.programs.push(info); }
    return r;
  });
  for (const name of ['getProgramParameter', 'getProgramInfoLog']) {
    wrap(name, timed((p, ms) => { const info = programs.get(p); if (info) info.ms += ms; }));
  }
  wrap('useProgram', function (orig, p) {
    const info = p && programs.get(p);
    if (!info || info.used) return orig.call(this, p);
    const t = now(); const r = orig.call(this, p); info.ms += now() - t; info.used = true; return r;
  });
  sc.summary = () => sc.programs.map((p) => {
    const parts = p.shaders.map((s) => shaders.get(s)).filter(Boolean);
    const fragment = parts.find((s) => s.type === 0x8B30) ?? parts[0];
    return { ms: p.ms + parts.reduce((a, s) => a + s.ms, 0), at: p.at, source: fragment ? fragment.source : '' };
  });
})();`;

const profile = mkdtempSync(join(tmpdir(), 'shader-compile-'));
const browser = spawn(chrome, ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  '--window-size=1600,900', '--ignore-gpu-blocklist', '--no-first-run', '--no-default-browser-check', 'about:blank'],
{ stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
try {
  let targets;
  for (let i = 0; i < 100 && !targets; i++) {
    try { targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); } catch { await sleep(200); }
  }
  const ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r, { once: true }));
  let nextId = 0;
  const pending = new Map();
  const logs = [];
  ws.addEventListener('message', (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
    else if (msg.method === 'Runtime.consoleAPICalled') {
      logs.push({ type: msg.params.type, text: msg.params.args.map((a) => a.value ?? a.description ?? '').join(' ') });
    }
  });
  const send = (method, params = {}) => new Promise((r) => {
    const id = ++nextId; pending.set(id, r); ws.send(JSON.stringify({ id, method, params }));
  });
  await send('Runtime.enable');
  await send('Page.enable');
  await send('Page.addScriptToEvaluateOnNewDocument', { source: hook });
  const query = `cam=${cam}&peds=0&gangs=0&traffic=0${time ? `&time=${time}` : ''}`;
  const started = Date.now();
  await send('Page.navigate', { url: `${url}${url.includes('?') ? '&' : '?'}${query}` });
  let ready = null;
  while (Date.now() - started < timeoutMs && ready === null) {
    const line = logs.find((l) => l.text.includes('[city]') && l.text.includes('ready'));
    if (line) ready = Date.now() - started;
    else await sleep(250);
  }
  await sleep(3000);  // the first frames after ready can still compile
  const result = await send('Runtime.evaluate', { expression: 'JSON.stringify(window.__shaderCompile.summary())', returnByValue: true });
  const programs = JSON.parse(result.result.result.value ?? '[]')
    .map((p) => ({ ...p, shader: nameOf(p.source), variant: variantOf(p.source) }));
  const total = programs.reduce((a, p) => a + p.ms, 0);
  const seconds = (ms) => (ms / 1000).toFixed(1);
  console.log(`Ready after ${ready === null ? 'TIMEOUT' : seconds(ready) + ' s'}; ${programs.length} programs, `
    + `${seconds(total)} s waiting on shader compiles.`);
  const perShader = {};
  for (const p of programs) perShader[p.shader] = (perShader[p.shader] ?? 0) + p.ms;
  console.log('\nPer shader (s):');
  for (const [name, ms] of Object.entries(perShader).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${seconds(ms).padStart(6)}  ${name}`);
  }
  console.log('\nSlowest programs (s):');
  for (const p of [...programs].sort((a, b) => b.ms - a.ms).slice(0, 10)) {
    console.log(`  ${seconds(p.ms).padStart(6)}  ${p.shader} ${p.variant} (fragment ${p.source.length} chars)`);
  }
  const problems = logs.filter((l) => l.type === 'error' || /SHADER ERROR|failed to compile/i.test(l.text));
  if (problems.length) {
    console.log('\nErrors in the console:');
    for (const l of problems.slice(0, 10)) console.log(`  ${l.text.slice(0, 300)}`);
  }
  ws.close();
} finally {
  browser.kill();
  await sleep(1000);
  try { rmSync(profile, { recursive: true, force: true }); } catch {}
}
