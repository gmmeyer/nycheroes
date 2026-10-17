// Test the actual exported engine class, not a copy of its implementation.
// Export first, then: node --test tools/web/fix_audio_loops.test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { patchWebAudio, sampleNodeClass } from './fix_audio_loops.mjs';

const source = readFileSync(process.env.GODOT_WEB_JS || 'build/web/index.js', 'utf8');
const patched = patchWebAudio(source);

function makeVoice(loopMode = 'forward', pitch = 1.3, offset = 7.95) {
  const sources = [];
  const context = {
    currentTime: 0,
    createBufferSource() {
      const listeners = new Map();
      const node = {
        loop: false, playbackRate: { value: 1 },
        addEventListener: (name, fn) => listeners.set(name, fn),
        removeEventListener: name => listeners.delete(name),
        connect() {}, disconnect() {},
        start(when, at) { this.started = { when, at, pitch: this.playbackRate.value }; },
        stop() { listeners.get('ended')?.(); },
      };
      sources.push(node);
      return node;
    },
  };
  const AudioSampleNode = new Function('GodotAudio', `return (${sampleNodeClass(patched)});`)({ ctx: context });
  const voice = Object.assign(Object.create(AudioSampleNode.prototype), {
    offset, startTime: 0, pauseTime: 0, isPaused: false, isStarted: false,
    loopMode, _playbackRate: 1, _pitchScale: pitch, _sourceStartTime: 0,
    _onended: null, _positionWorklet: null, _sampleNodeBuses: new Map(),
    _source: context.createBufferSource(),
    getSample: () => ({ loopMode, loopBegin: 0, loopEnd: 0, getAudioBuffer: () => ({ duration: 8 }) }),
  });
  voice._addEndedListener();
  voice.start();
  return { voice, sources, context };
}

test('forward samples loop on the audio thread even when starting near the end', () => {
  for (const offset of [0, 4.3, 7.95]) {
    const { voice, sources } = makeVoice('forward', 1.3, offset);
    assert.equal(voice._source.loop, true);
    assert.deepEqual(voice._source.started, { when: 0, at: offset, pitch: 1.3 });
    assert.equal(sources.length, 1);
  }
});

test('changed pitch survives a pause and resume', () => {
  const { voice, context, sources } = makeVoice();
  voice.setPitchScale(0.75);
  context.currentTime = 2;
  voice.pause(true);
  voice.pause(false);
  assert.equal(sources.length, 2);
  assert.equal(voice._source.loop, true);
  assert.equal(voice._source.started.pitch, 0.75);
});

test('unpause does not restart a sound that is already playing', () => {
  const { voice, sources } = makeVoice();
  voice.pause(false);
  voice.pause(false);
  assert.equal(sources.length, 1);
});

test('one-shot effects still finish and do not loop', () => {
  const { voice } = makeVoice('disabled', 0.9, 0);
  let finished = 0;
  voice.stop = () => finished++;
  assert.equal(voice._source.loop, false);
  voice._onended();
  assert.equal(finished, 1);
});

test('patch is idempotent and rejects unknown engine code', () => {
  assert.equal(patchWebAudio(patched), patched);
  assert.throws(() => patchWebAudio('different engine'), /Unknown Godot/);
  assert.throws(() => patchWebAudio(patched.replace('_addEndedListener(){', '_changedListener(){')), /implementation changed/);
});
