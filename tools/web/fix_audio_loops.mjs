// Godot 4.7.2's web SampleNode restarts loops in an `ended` callback.
// That repeats the initial random offset, introduces main-thread gaps, copies
// the buffer every lap, and resets pitch. Use Web Audio's native looping for
// this game's full-buffer Vorbis loops and restore pitch on pause/resume.
// Upstream pitch bug: https://github.com/godotengine/godot/issues/123786
// Run after export: node tools/web/fix_audio_loops.mjs build/web/index.js
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const MARKER = '/* NYC native audio loops v1 */';
const HOOK = '_addEndedListener(){';
const FIX = MARKER + 'this._syncPlaybackRate();' +
  'const nycSample=this.getSample();' +
  'if(this.loopMode==="forward"&&nycSample.loopBegin===0&&nycSample.loopEnd===0){' +
  'this._source.loop=true;}';

export function sampleNodeClass(source) {
  const start = source.indexOf('SampleNode:class SampleNode{');
  const end = source.indexOf('},deleteSampleNode:', start);
  if (start < 0 || end < 0) throw new Error('Unknown Godot web audio runtime; review the loop compatibility fix after upgrading Godot.');
  return source.slice(start + 'SampleNode:'.length, end + 1);
}

export function patchWebAudio(source) {
  const original = sampleNodeClass(source);
  if (original.includes(HOOK + FIX) && original.includes('_unpause(){if(!this.isPaused){return}this._restart();')) return source;
  if (source.includes(MARKER) || original.split(HOOK).length !== 2 ||
      !original.includes('case"forward":case"backward":self.restart();') ||
      !original.includes('_unpause(){this._restart();')) {
    throw new Error('Godot web audio implementation changed; refusing to apply a partial loop fix.');
  }
  const patched = original.replace(HOOK, HOOK + FIX)
    // An unpause on an already-playing source used to restart it too.
    .replace('_unpause(){this._restart();', '_unpause(){if(!this.isPaused){return}this._restart();');
  return source.replace(original, patched);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const file = process.argv[2];
  if (!file) throw new Error('Usage: node tools/web/fix_audio_loops.mjs <exported index.js>');
  const original = readFileSync(file, 'utf8');
  const patched = patchWebAudio(original);
  if (patched !== original) writeFileSync(file, patched);
  console.log('[audio] native web loops and preserved pitch verified');
}
