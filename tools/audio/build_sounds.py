"""Builds the game's sounds into assets/audio/ as mono Ogg Vorbis (the list of
sounds and how loud each plays is scripts/audio/sound_bank.gd).

Some are synthesized here with numpy (whooshes, webs, wind, booms, rubble);
the rest are cut from CC0 recordings: Kenney's audio packs (kenney.nl) and
Freesound uploads whose pages say Creative Commons 0 (CREDITS.md lists every
one). Download them once into a folder of their own (`fetch` checks each
Freesound page's license before downloading its preview), then build:

    python tools/audio/build_sounds.py fetch <downloads dir>
    python tools/audio/build_sounds.py build <downloads dir> <ffmpeg>

with tools/citygen's Python (numpy). Recordings are trimmed, cut into single
sounds where a file has several takes, faded, looped where they loop (the
end crossfaded into the start), filtered and normalized; one-off sounds are
44.1 kHz, the ambience's beds 22.05 kHz to keep the download small. Godot's
web build decodes every sound into memory as 48 kHz stereo anyway (384 kB
a second) and copies it for each play, so loops are kept short. Everything
is seeded, so a rebuild makes the same files.
"""

import json
import re
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio"
RATE = 44100
BED_RATE = 22050

KENNEY_PACKS = {
    "kenney_impact-sounds": "https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
    "kenney_rpg-audio": "https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip",
    "kenney_interface-sounds": "https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
    "kenney_sci-fi-sounds": "https://kenney.nl/media/pages/assets/sci-fi-sounds/6b296f9ecf-1677589334/kenney_sci-fi-sounds.zip",
}

# Freesound uploads used (id: what for). All Creative Commons 0.
FREESOUND = {
    "552120": "day street bed (quantumriver, Busy New York City Street)",
    "369891": "night bed (SpliceSound, NYC night rooftop, Bushwick)",
    "495866": "far city hum (Yakobb1, City Ambience Distant)",
    "639703": "Times Square bed (olofgud, Times square 1700)",
    "578150": "birds bed (cynthia_1968, morning birds urban)",
    "688301": "bird calls (Shankfosho, Park Birds [Clean])",
    "455685": "crickets bed (kyles, crickets night, Montreal)",
    "438839": "waves lapping bed (craigsmith, Pier Lap)",
    "469363": "far siren (brunoboselli, Distant Ambulance Siren)",
    "568814": "far sirens (TRP, Sirens distant, urban echoes)",
    "547667": "horn (DuranBurrus, Car Horn)",
    "553150": "horn (Brett+Butter, Car Horn Honk, distant, Brooklyn)",
    "349922": "horn (DeVern, Car Horn Honk)",
    "637923": "horn (kyles, truck horn honk quick polite)",
    "196139": "horn (BiblicalBricksProductions, Car honk)",
    "369054": "car engine loop (AndrewAlexander, car idle ext loop)",
    "813116": "dog (qubodup, Distant Dog Bark)",
    "792440": "dog (Sadiquecat, Thuir distant dog bark)",
    "467132": "hero grunts (CalGre, Good Guy Grunts)",
    "467121": "thug grunts (CalGre, Evil Guy Grunts)",
    "511023": "thug efforts (ale-batec, Male Fight Grunts)",
    "610998": "thug knocked down (unfa, Medium Male Pain Grunts)",
    "345083": "thug shout (metrostock99, HEY VERY LOW 4)",
    "480787": "thug shouts (craigsmith, Men with Gruff Voices Grunting)",
    "222582": "scream (queen_westeros, MAN SCREAM)",
    "220814": "scream (EricSueiro, woman scream)",
    "609973": "scream (starnezio, woman scream)",
    "670315": "scream (ColtoBene, Woman Scream)",
    "618193": "scream (JalynCatbtg, Woman Screaming)",
    "504626": "body fall (leonelmail, BODY FALL - V HVY - DIRT)",
    "346694": "body fall (Body fall_02)",
    "82027": "body fall (raubana, Body Fall Over)",
    "807962": "splash (Logicogonist, splash 1b)",
    "867464": "splash (qubodup, Waboba Moon Ball Water Splash 9)",
    "438845": "swim strokes (craigsmith, Person Swimming)",
}


# ---------------------------------------------------------------- fetching

def fetch(downloads: Path) -> None:
    """Downloads the Kenney packs and the Freesound previews (CC0 checked)."""
    downloads.mkdir(parents=True, exist_ok=True)
    for name, url in KENNEY_PACKS.items():
        folder = downloads / name
        if (folder / "x").exists():
            continue
        folder.mkdir(exist_ok=True)
        archive = folder / f"{name}.zip"
        archive.write_bytes(_get(url))
        with zipfile.ZipFile(archive) as z:
            z.extractall(folder / "x")
        license_text = (folder / "x" / "License.txt").read_text(errors="replace")
        if "CC0" not in license_text:
            sys.exit(f"{name}: License.txt doesn't say CC0")
        print(f"{name}: CC0")
    folder = downloads / "freesound"
    folder.mkdir(exist_ok=True)
    records = folder / "sources.jsonl"
    for sound_id in FREESOUND:
        if (folder / f"{sound_id}.ogg").exists():
            continue
        page = _get(f"https://freesound.org/s/{sound_id}/").decode("utf-8", "replace")
        license_link = re.search(r'title="Go to the full license text" href="([^"]+)"', page)
        if not license_link or "publicdomain/zero" not in license_link.group(1):
            sys.exit(f"Freesound {sound_id} isn't CC0")
        preview = re.search(r'(https://cdn\.freesound\.org/previews/[^"]+)-lq\.mp3', page).group(1) + "-hq.ogg"
        (folder / f"{sound_id}.ogg").write_bytes(_get(preview))
        artist = re.search(r'og:audio:artist" content="([^"]*)"', page).group(1)
        title = re.search(r'og:audio:title" content="([^"]*)"', page).group(1)
        with records.open("a", encoding="utf-8") as f:
            f.write(json.dumps({"id": sound_id, "artist": artist, "title": title, "license": "CC0"}) + "\n")
        print(f"freesound {sound_id}: {artist}, {title}: CC0")


def _get(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


# ---------------------------------------------------------------- audio in and out

class Sources:
    """Finds and decodes downloaded files (by name, anywhere under the folder)."""

    def __init__(self, downloads: Path, ffmpeg: str):
        self.ffmpeg = ffmpeg
        self.index = {p.name: p for p in downloads.rglob("*.ogg")}

    def load(self, name: str, rate: int = RATE) -> np.ndarray:
        path = self.index.get(name)
        if path is None:
            sys.exit(f"missing download: {name}")
        raw = subprocess.run([self.ffmpeg, "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(rate),
                              "-f", "f32le", "-"], capture_output=True, check=True).stdout
        return np.frombuffer(raw, np.float32).astype(np.float64)

    def freesound(self, sound_id: str, rate: int = RATE) -> np.ndarray:
        return self.load(f"{sound_id}.ogg", rate)


def write(name: str, x: np.ndarray, rate: int, quality: float, ffmpeg: str) -> None:
    pcm = np.clip(x, -1.0, 1.0).astype(np.float32).tobytes()
    out = OUT / f"{name}.ogg"
    subprocess.run([ffmpeg, "-v", "error", "-y", "-f", "f32le", "-ar", str(rate), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", str(out)],
                   input=pcm, check=True)


# ---------------------------------------------------------------- processing

def db(value: float) -> float:
    return 10.0 ** (value / 20.0)


def normalize(x: np.ndarray, rms_db: float = -16.0, peak_db: float = -1.0) -> np.ndarray:
    """To an RMS over its loud part, without peaks above peak_db."""
    peak = np.max(np.abs(x)) + 1e-12
    envelope = np.abs(x)
    loud = x[envelope > peak * db(-40.0)]
    rms = np.sqrt(np.mean(loud ** 2)) + 1e-12
    return x * min(db(rms_db) / rms, db(peak_db) / peak)


def fades(x: np.ndarray, rate: int, fade_in: float = 0.004, fade_out: float = 0.04) -> np.ndarray:
    x = x.copy()
    n_in, n_out = int(fade_in * rate), int(fade_out * rate)
    if n_in:
        x[:n_in] *= np.linspace(0.0, 1.0, n_in) ** 2
    if n_out:
        x[-n_out:] *= np.linspace(1.0, 0.0, n_out) ** 2
    return x


def spectral(x: np.ndarray, rate: int, gain) -> np.ndarray:
    """A zero-phase filter: gain(frequencies) in the frequency domain (zero padded)."""
    n = len(x)
    size = 1 << int(np.ceil(np.log2(n + rate // 10)))
    spectrum = np.fft.rfft(x, size)
    spectrum *= gain(np.fft.rfftfreq(size, 1.0 / rate))
    return np.fft.irfft(spectrum, size)[:n]


def highpass(f: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    return 1.0 / np.sqrt(1.0 + (cutoff / np.maximum(f, 1e-3)) ** (2 * order))


def lowpass(f: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    return 1.0 / np.sqrt(1.0 + (f / cutoff) ** (2 * order))


def band(f, center, octaves):
    """A soft band around `center` (Hz), `octaves` wide (Gaussian in log frequency)."""
    return np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / center) / octaves) ** 2)


def loudness_track(x: np.ndarray, rate: int, hop: float = 0.25) -> np.ndarray:
    n = int(hop * rate)
    frames = len(x) // n
    return 20 * np.log10(np.sqrt(np.mean(x[:frames * n].reshape(frames, n) ** 2, axis=1)) + 1e-9)


def steadiest(x: np.ndarray, rate: int, seconds: float, avoid: tuple = ()) -> int:
    """Start (samples) of the window with the most even loudness: least spread,
    no bursts far above its median (horns, trains: those are played on their
    own), and away from the `avoid` (start, end) seconds."""
    hop = 0.25
    track = loudness_track(x, rate, hop)
    width = int(seconds / hop)
    best, best_cost = 0, np.inf
    for start in range(0, max(len(track) - width, 1)):
        t0, t1 = start * hop, start * hop + seconds
        if any(t0 < b and t1 > a for a, b in avoid):
            continue
        window = track[start:start + width]
        median = np.median(window)
        cost = np.std(window) + 0.5 * max(np.max(window) - median - 6.0, 0.0)
        if cost < best_cost:
            best, best_cost = start, cost
    return int(best * hop * rate)


def make_loop(x: np.ndarray, rate: int, seconds: float, start: int | None = None, crossfade: float = 1.5,
              avoid: tuple = ()) -> np.ndarray:
    """A `seconds` long seamless loop: a steady stretch whose end fades into its start."""
    n, fade = int(seconds * rate), int(crossfade * rate)
    if start is None:
        start = steadiest(x, rate, seconds + crossfade, avoid)
    piece = x[start:start + n + fade]
    if len(piece) < n + fade:
        sys.exit("recording too short for the loop")
    t = np.linspace(0.0, 1.0, fade)
    loop = piece[:n].copy()
    # Equal power: the start fades in under the stretch just past the end.
    loop[:fade] = piece[:fade] * np.sqrt(t) + piece[n:n + fade] * np.sqrt(1.0 - t)
    return loop


def takes(x: np.ndarray, rate: int, min_len: float = 0.15, max_len: float = 2.5, floor_db: float = -32.0,
          gap: float = 0.08) -> list[tuple[int, int]]:
    """Separate sounds in a file of several takes: (start, end) of each stretch
    louder than floor_db below the file's peak, joined across short gaps."""
    hop = int(0.005 * rate)
    frames = len(x) // hop
    envelope = np.sqrt(np.mean(x[:frames * hop].reshape(frames, hop) ** 2, axis=1))
    loud = envelope > envelope.max() * db(floor_db)
    found, start, quiet = [], None, 0
    for i, on in enumerate(loud):
        if on:
            if start is None:
                start = i
            quiet = 0
        elif start is not None:
            quiet += 1
            if quiet * hop > gap * rate:
                found.append((start, i - quiet + 1))
                start, quiet = None, 0
    if start is not None:
        found.append((start, frames))
    out = []
    for a, b in found:
        a = max(a * hop - int(0.015 * rate), 0)
        b = min(b * hop + int(0.06 * rate), len(x))
        if min_len * rate <= b - a <= max_len * rate:
            out.append((a, b))
    return out


def pick_takes(x: np.ndarray, rate: int, count: int, min_centroid: float = 0.0, **kwargs) -> list[np.ndarray]:
    """The `count` loudest separate takes (brighter than min_centroid Hz, to
    tell birds from cars), in the order they come in the file."""
    found = [ab for ab in takes(x, rate, **kwargs) if centroid(x[ab[0]:ab[1]], rate) >= min_centroid]
    found.sort(key=lambda ab: -np.max(np.abs(x[ab[0]:ab[1]])))
    chosen = sorted(found[:count])
    if len(chosen) < count:
        print(f"    only {len(chosen)} takes of {count}")
    return [x[a:b] for a, b in chosen]


def loudest_windows(x: np.ndarray, rate: int, seconds: float, count: int, spacing: float = 1.0) -> list[np.ndarray]:
    """`count` windows `seconds` long around the loudest moments, at least
    `spacing` seconds apart (for takes that run into each other), in order."""
    track = loudness_track(x, rate, 0.05)
    order = np.argsort(-track)
    centers = []
    for i in order:
        t = i * 0.05 + 0.025
        if all(abs(t - c) >= spacing for c in centers):
            centers.append(t)
        if len(centers) == count:
            break
    out = []
    for c in sorted(centers):
        a = int(np.clip(c - seconds * 0.35, 0.0, len(x) / rate - seconds) * rate)
        out.append(x[a:a + int(seconds * rate)])
    return out


def centroid(x: np.ndarray, rate: int) -> float:
    spectrum = np.abs(np.fft.rfft(x))
    freqs = np.fft.rfftfreq(len(x), 1.0 / rate)
    return float((spectrum * freqs).sum() / (spectrum.sum() + 1e-12))


def cut(x: np.ndarray, rate: int, start: float, end: float) -> np.ndarray:
    return x[int(start * rate):int(end * rate)]


# ---------------------------------------------------------------- synthesis

class Synth:
    """Noise shaped by time-varying spectra (overlap-added random-phase frames)
    and swept tones; looping sounds wrap around so they loop seamlessly."""

    FRAME = 2048
    HOP = 512

    def __init__(self, seed: int):
        self.rng = np.random.default_rng(seed)

    def noise(self, seconds: float, shape, rate: int = RATE, loop: bool = False) -> np.ndarray:
        """shape(t, f) -> magnitude, with t (frames, 1) seconds and f (1, bins)
        Hz; frame i is centered on sample i * HOP. A loop wraps its frames
        around its end (and shape should repeat over `seconds`)."""
        n = int(seconds * rate)
        frames = int(np.ceil(n / self.HOP)) + (0 if loop else 1)
        t = ((np.arange(frames) * self.HOP) / rate)[:, None]
        f = np.fft.rfftfreq(self.FRAME, 1.0 / rate)[None, :]
        magnitude = np.broadcast_to(shape(t, f), (frames, f.shape[1]))
        phase = self.rng.uniform(0.0, 2 * np.pi, magnitude.shape)
        blocks = np.fft.irfft(magnitude * np.exp(1j * phase), self.FRAME, axis=1) * np.hanning(self.FRAME)
        half = self.FRAME // 2
        if loop:
            out = np.zeros(n)
            span = np.arange(self.FRAME)
            for i, block in enumerate(blocks):
                np.add.at(out, (span + i * self.HOP - half) % n, block)
            return out
        out = np.zeros(n + 2 * self.FRAME)
        for i, block in enumerate(blocks):
            out[i * self.HOP:i * self.HOP + self.FRAME] += block
        return out[half:half + n]

    @staticmethod
    def tone(freq: np.ndarray, rate: int = RATE, harmonics=(1.0,)) -> np.ndarray:
        """A tone following freq (Hz per sample), with harmonic amplitudes."""
        phase = 2 * np.pi * np.cumsum(freq) / rate
        return sum(a * np.sin(phase * (k + 1)) for k, a in enumerate(harmonics))


def mix(*parts: np.ndarray) -> np.ndarray:
    """Sounds of any lengths added up, from their starts."""
    out = np.zeros(max(len(part) for part in parts))
    for part in parts:
        out[:len(part)] += part
    return out


def swell(t, peak, attack_power=1.5, decay=None):
    """0 -> 1 at `peak` seconds -> down: a whoosh's loudness."""
    rise = np.clip(t / peak, 0.0, 1.0) ** attack_power
    fall = np.exp(-np.maximum(t - peak, 0.0) / (decay if decay else peak))
    return rise * fall


def bell(t, center, width):
    return np.exp(-0.5 * ((t - center) / width) ** 2)


def whoosh(synth: Synth, seconds, peak, low, high, octaves, body=0.25, decay=None):
    """Air pushed past: a band of noise sweeping from `low` up to `high` Hz at
    `peak` seconds and back down, loudest there; `body` adds weight below."""
    def shape(t, f):
        sweep = np.exp(np.log(low) + (np.log(high) - np.log(low)) * bell(t, peak, peak * 0.8))
        level = swell(t, peak, 1.6, decay)
        return level * (band(f, sweep, octaves) + body * band(f, sweep * 0.25, 1.0)) * (f / 1000.0 + 0.05) ** -0.3
    return synth.noise(seconds, shape)


def thump(seconds, start_hz, end_hz, decay, rate=RATE):
    """A deep knock: a sine falling from start_hz to end_hz, dying away."""
    t = np.arange(int(seconds * rate)) / rate
    freq = end_hz + (start_hz - end_hz) * np.exp(-t / (decay * 0.6))
    knock = Synth.tone(freq, rate, (1.0, 0.3, 0.1)) * np.exp(-t / decay) * np.clip(t / 0.003, 0, 1)
    return fades(knock, rate, 0.0, seconds * 0.3)


def rubble(synth: Synth, seconds, grains, rate=RATE):
    """Pebbles and chunks falling: short bursts, thinning out over time."""
    rng = synth.rng
    n = int(seconds * rate)
    out = np.zeros(n + rate)
    times = rng.exponential(seconds * 0.3, grains)
    times = times[times < seconds * 0.9]
    for at in times:
        length = int(rng.uniform(0.003, 0.014) * rate)
        burst = rng.normal(0, 1, length) * np.exp(-np.arange(length) / (length * 0.3))
        center = rng.uniform(1200, 6000) if rng.random() < 0.8 else rng.uniform(300, 1000)
        burst = spectral(burst, rate, lambda f, c=center: band(f, c, 0.6))
        level = np.exp(-at / (seconds * 0.4)) * rng.uniform(0.2, 1.0)
        i = int(at * rate)
        out[i:i + length] += burst * level
    return out[:n]


def make_synth(ffmpeg: str) -> None:
    s = Synth(7)
    sounds = {}
    for i, (seconds, peak, low, high) in enumerate([(0.22, 0.08, 700, 2100), (0.2, 0.07, 800, 2400),
                                                    (0.26, 0.09, 600, 1800), (0.24, 0.08, 750, 2600)]):
        sounds[f"whoosh_punch_{i + 1}"] = whoosh(s, seconds, peak, low, high, 0.9, decay=0.06)
    for i, (seconds, peak, low, high) in enumerate([(0.4, 0.13, 350, 1300), (0.42, 0.15, 300, 1100)]):
        sounds[f"whoosh_heavy_{i + 1}"] = whoosh(s, seconds, peak, low, high, 1.1, body=0.6, decay=0.1)
    for i, (seconds, peak, low, high) in enumerate([(0.75, 0.38, 250, 900), (0.8, 0.4, 220, 800),
                                                    (0.7, 0.33, 280, 1000)]):
        sounds[f"whoosh_swing_{i + 1}"] = whoosh(s, seconds, peak, low, high, 1.0, body=0.35, decay=0.22)

    # Dive: a rising rush and a whistle.
    t = np.arange(int(1.0 * RATE)) / RATE
    rush = s.noise(1.0, lambda t, f: np.clip(t / 0.9, 0, 1) ** 1.2 * band(f, 300 * (2500 / 300) ** np.clip(t / 0.95, 0, 1), 0.8))
    whistle = Synth.tone(900 * (2200 / 900) ** np.clip(t / 0.95, 0, 1) * (1 + 0.01 * np.sin(2 * np.pi * 7 * t)))
    dive = normalize(rush) + 0.08 * whistle * np.clip(t / 0.9, 0, 1) ** 2
    sounds["dive"] = fades(dive, RATE, 0.02, 0.15)

    # Take-off: a low push and a rising whoosh.
    sounds["takeoff"] = mix(whoosh(s, 0.8, 0.12, 200, 1400, 1.0, body=0.5, decay=0.3), 0.5 * normalize(thump(0.4, 90, 45, 0.12)))

    # Super speed's burst: a zing and a rush.
    t = np.arange(int(0.7 * RATE)) / RATE
    zing = Synth.tone(700 * (2600 / 700) ** np.clip(t / 0.25, 0, 1), RATE, (1.0, 0.25, 0.1)) * swell(t, 0.05, 1.0, 0.15)
    sounds["zoom"] = normalize(whoosh(s, 0.7, 0.15, 500, 3000, 0.9, decay=0.25)) + 0.12 * zing

    # Webs: a click, a resonant swish falling fast, and a tonal edge.
    for i, (hi, lo, length) in enumerate([(3600, 1100, 0.16), (4200, 1300, 0.14), (3200, 950, 0.17)]):
        t = np.arange(int(length * RATE)) / RATE
        fall = lo + (hi - lo) * np.exp(-t / 0.03)
        swish = s.noise(length, lambda tt, f, hi=hi, lo=lo: np.exp(-tt / 0.045) * np.clip(tt / 0.004, 0, 1)
                        * band(f, lo + (hi - lo) * np.exp(-tt / 0.03), 0.25))
        edge = Synth.tone(fall * 0.7, RATE, (1.0, 0.3)) * np.exp(-t / 0.035) * np.clip(t / 0.003, 0, 1)
        click = np.zeros_like(t)
        click[:int(0.003 * RATE)] = s.rng.normal(0, 1, int(0.003 * RATE))
        click = spectral(click, RATE, lambda f: highpass(f, 2500, 3))
        sounds[f"thwip_{i + 1}"] = normalize(swish) + 0.35 * normalize(edge) + 0.4 * normalize(click)
    sounds["web_release"] = s.noise(0.13, lambda t, f: swell(t, 0.05, 1.0, 0.03) * band(f, 900 * (2600 / 900) ** np.clip(t / 0.1, 0, 1), 0.4))

    # Booms: a super jump's launch, heavy landings, the slam's punch.
    launch = 0.9 * normalize(thump(0.8, 75, 35, 0.2)) + 0.5 * normalize(
        s.noise(0.8, lambda t, f: np.exp(-t / 0.07) * lowpass(f, 1500))) + 0.6 * normalize(
        whoosh(s, 0.8, 0.22, 300, 1500, 1.0, body=0.4, decay=0.3))
    sounds["launch"] = fades(launch, RATE, 0.001, 0.2)
    for i, (hz, decay) in enumerate([(80, 0.2), (70, 0.24)]):
        crunch = s.noise(0.6, lambda t, f: np.exp(-t / 0.05) * lowpass(f, 2200) * highpass(f, 120))
        sounds[f"land_heavy_{i + 1}"] = fades(normalize(thump(0.6, hz, 38, decay)) + 0.45 * normalize(crunch), RATE, 0.001, 0.1)
    for i in range(2):
        sounds[f"debris_{i + 1}"] = fades(rubble(s, 1.0, 120 + 30 * i), RATE, 0.001, 0.2)

    # Getting back up from a knockout: energy rising, then let go.
    t = np.arange(int(0.95 * RATE)) / RATE
    rise = Synth.tone(200 * (900 / 200) ** np.clip(t / 0.55, 0, 1), RATE, (1.0, 0.5, 0.3)) * np.clip(t / 0.55, 0, 1) ** 2 * (t < 0.6)
    burst = whoosh(s, 0.95, 0.6, 250, 1800, 1.0, body=0.6, decay=0.15)
    sounds["powerup"] = fades(0.25 * normalize(rise) + normalize(burst) + 0.5 * normalize(np.concatenate(
        [np.zeros(int(0.55 * RATE)), thump(0.4, 80, 40, 0.15)]))[:len(t)], RATE, 0.01, 0.1)

    for name, x in sounds.items():
        write(name, fades(normalize(x, -16.0), RATE, 0.001, 0.02), RATE, 4, ffmpeg)

    # Loops (seamless: the noise wraps around).
    loops = {}
    def gusts(t, length, parts):
        return 1.0 + sum(a * np.sin(2 * np.pi * k * t / length + p) for k, a, p in parts)
    loops["air_low"] = s.noise(4.0, lambda t, f: gusts(t, 4.0, [(2, 0.3, 0.0), (5, 0.15, 1.0)])
                               * band(f, 260, 1.4) * (f / 100 + 0.2) ** -0.2, loop=True)
    loops["air_high"] = s.noise(4.0, lambda t, f: gusts(t, 4.0, [(3, 0.3, 0.5), (11, 0.15, 2.0)])
                                * (band(f, 2600, 1.1) + 0.15 * band(f, 1800, 0.12)), loop=True)
    loops["speed_loop"] = s.noise(3.0, lambda t, f: gusts(t, 3.0, [(12, 0.25, 0.0), (5, 0.15, 1.0)])
                                  * (band(f, 900, 1.2) + 0.08 * band(f, 3100, 0.1)), loop=True)
    t = np.arange(int(2.0 * RATE)) / RATE
    hum = Synth.tone(np.full(len(t), 55.0), RATE, (1.0, 0.5, 0.35, 0.2, 0.15))
    loops["charge_loop"] = normalize(hum) + 0.5 * normalize(
        s.noise(2.0, lambda tt, f: (1 + 0.4 * np.sin(2 * np.pi * 12 * tt / 2.0)) * band(f, 420, 0.9), loop=True))
    for name, x in loops.items():
        write(name, normalize(x, -16.0), RATE, 3, ffmpeg)
    wind = s.noise(6.0, lambda t, f: gusts(t, 6.0, [(1, 0.45, 0.0), (2, 0.3, 1.0), (5, 0.2, 2.0)])
                   * (lowpass(f, 650, 2) * highpass(f, 60) * (f / 100 + 0.3) ** -0.4
                      + 0.12 * gusts(t, 6.0, [(3, 0.6, 0.3)]) * band(f, 950, 0.08)), BED_RATE, loop=True)
    write("amb_wind", normalize(wind, -20.0), BED_RATE, 2, ffmpeg)


# ---------------------------------------------------------------- recordings

def make_recorded(src: Sources, ffmpeg: str) -> None:
    kenney = {"impact": "footstep_{}_00{}.ogg", "punch": "impactPunch_{}_00{}.ogg"}

    def one_shot(name, x, rms=-16.0, quality=4, hp=40.0, fade_out=0.04, fade_in=0.0003):
        # (Kenney's files start right on the hit: a longer fade in would blunt it.)
        x = spectral(x, RATE, lambda f: highpass(f, hp))
        write(name, fades(normalize(x, rms), RATE, fade_in, fade_out), RATE, quality, ffmpeg)

    # Footsteps and impacts (Kenney Impact Sounds).
    for surface in ("concrete", "grass", "wood"):
        for i in range(5):
            # Short: on the web every play copies the whole sound.
            x = src.load(kenney["impact"].format(surface, i))[:int(0.22 * RATE)]
            one_shot(f"step_{surface}_{i + 1}", x, -18.0, fade_out=0.03)
    for weight, name in (("medium", "punch"), ("heavy", "punch_heavy")):
        for i in range(5):
            one_shot(f"{name}_{i + 1}", src.load(kenney["punch"].format(weight, i)), -14.0)
    for i in range(3):
        one_shot(f"land_{i + 1}", src.load(f"impactSoft_heavy_00{i}.ogg"), -14.0, hp=30.0)
    for i in range(3):
        one_shot(f"jump_{i + 1}", src.load(f"cloth{i + 1}.ogg")[:int(0.4 * RATE)], -20.0)
    for i in range(3):
        one_shot(f"creak_{i + 1}", src.load(f"creak{i + 1}.ogg")[:int(0.55 * RATE)], -18.0, fade_out=0.12)
    one_shot("ui_toggle", src.load("toggle_002.ogg"), -18.0)
    # The slam: Kenney's low explosion with a deeper thump under it.
    boom = src.load("lowFrequency_explosion_000.ogg")
    under = np.zeros_like(boom)
    knock = thump(0.9, 60, 28, 0.35)
    under[:len(knock)] = knock
    one_shot("slam", (normalize(boom) + 0.7 * normalize(under))[:int(1.4 * RATE)], -12.0, hp=25.0, fade_out=0.3)

    # Voices.
    def voice_takes(prefix, sound_id, count, rms=-15.0, **kwargs):
        for i, x in enumerate(pick_takes(src.freesound(sound_id), RATE, count, **kwargs)):
            one_shot(f"{prefix}_{i + 1}", x, rms, hp=90.0, fade_out=0.05, fade_in=0.003)
    hero = pick_takes(src.freesound("467132"), RATE, 6, max_len=1.0)
    for i, x in enumerate(hero[:4]):
        one_shot(f"hero_hurt_{i + 1}", x, -15.0, hp=90.0, fade_out=0.05, fade_in=0.003)
    for i, x in enumerate(hero[4:6]):
        one_shot(f"hero_effort_{i + 1}", x, -15.0, hp=90.0, fade_out=0.05, fade_in=0.003)
    voice_takes("thug_hurt", "467121", 5, max_len=1.0)
    voice_takes("thug_effort", "511023", 3, max_len=0.8)
    voice_takes("thug_down", "610998", 3, min_len=0.4, max_len=1.3)
    # Gruff yelling runs on without gaps: the loudest moments.
    shouts = [src.freesound("345083")] + loudest_windows(src.freesound("480787"), RATE, 1.0, 3, spacing=1.5)
    for i, x in enumerate(shouts):
        one_shot(f"thug_shout_{i + 1}", x, -14.0, hp=90.0, fade_in=0.02, fade_out=0.12)
    screams = [src.freesound("222582"), src.freesound("220814")[:int(0.9 * RATE)],
               src.freesound("609973")[:int(1.2 * RATE)], src.freesound("670315"), src.freesound("618193")[:int(1.2 * RATE)]]
    for i, x in enumerate(screams):
        one_shot(f"scream_{i + 1}", x, -16.0, hp=150.0, fade_out=0.15, fade_in=0.003)

    # Bodies and water.
    for i, sound_id in enumerate(("504626", "346694", "82027")):
        one_shot(f"body_fall_{i + 1}", src.freesound(sound_id)[:int(0.8 * RATE)], -14.0, hp=35.0, fade_out=0.1)
    one_shot("splash_1", src.freesound("807962")[:int(1.1 * RATE)], -14.0, fade_out=0.3)
    one_shot("splash_2", src.freesound("867464"), -14.0, fade_out=0.2)
    for i, x in enumerate(pick_takes(src.freesound("438845"), RATE, 3, min_len=0.25, max_len=1.0, floor_db=-20.0)):
        one_shot(f"swim_{i + 1}", x, -18.0)

    # The city's odd sounds.
    horns = [pick_takes(src.freesound("547667"), RATE, 1, min_len=0.1, max_len=3.0, floor_db=-24.0)[0],
             loudest_windows(src.freesound("553150"), RATE, 1.0, 1)[0],
             cut(src.freesound("349922"), RATE, 2.45, 3.1),
             loudest_windows(src.freesound("637923"), RATE, 1.0, 1)[0],
             pick_takes(src.freesound("196139"), RATE, 1, min_len=0.1, max_len=3.0, floor_db=-24.0)[0]]
    for i, x in enumerate(horns):
        # Some honks come with their street's noise: fade it in and out gently.
        one_shot(f"horn_{i + 1}", x, -16.0, hp=150.0, fade_out=0.15, fade_in=0.1 if i in (1, 3) else 0.003)
    siren_a = src.freesound("469363", BED_RATE)  # far away: no highs to keep
    siren_b = src.freesound("568814", BED_RATE)
    # (Short: the browser keeps every sound decoded, and copies it for each play.)
    for i, x in enumerate((loudest_windows(siren_a, BED_RATE, 10.0, 1)[0], cut(siren_b, BED_RATE, 1.0, 9.0))):
        x = spectral(x, BED_RATE, lambda f: highpass(f, 100))
        write(f"siren_{i + 1}", fades(normalize(x, -18.0), BED_RATE, 0.8, 1.5), BED_RATE, 2, ffmpeg)
    birds = pick_takes(src.freesound("688301"), RATE, 4, min_len=0.12, max_len=1.2, floor_db=-22.0, min_centroid=2000.0)
    for i, x in enumerate(birds):
        one_shot(f"bird_{i + 1}", x, -18.0, hp=1200.0)
    one_shot("dog_1", src.freesound("813116"), -16.0, hp=150.0)
    dog = pick_takes(src.freesound("792440"), RATE, 1, min_len=0.15, max_len=2.0, floor_db=-20.0)
    one_shot("dog_2", dog[0] if dog else src.freesound("792440"), -16.0, hp=150.0)

    # Engine loop for traffic.
    engine = src.freesound("369054")
    write("engine", normalize(make_loop(spectral(engine, RATE, lambda f: highpass(f, 35)), RATE, 2.5, start=0,
                                        crossfade=0.6), -16.0), RATE, 3, ffmpeg)

    # Beds (22.05 kHz).
    def bed(name, sound_id, seconds, rms=-20.0, hp=45.0, lp=None, avoid=(), start=None):
        x = src.freesound(sound_id, BED_RATE)
        x = spectral(x, BED_RATE, lambda f: highpass(f, hp) * (lowpass(f, lp, 2) if lp else 1.0))
        loop = make_loop(x, BED_RATE, seconds, start=start, avoid=avoid)
        write(name, normalize(loop, rms, -3.0), BED_RATE, 2, ffmpeg)
    # Beds are short loops: Godot's web build keeps each sound as 48 kHz
    # stereo samples (384 kB a second) and copies one for every play.
    bed("amb_traffic_day", "552120", 10.0)
    bed("amb_traffic_night", "369891", 10.0, avoid=((0.0, 100.0), (1250.0, 1400.0)))
    bed("amb_city_far", "495866", 8.0, lp=2500.0)
    bed("amb_times_square", "639703", 12.0)
    bed("amb_birds", "578150", 8.0, hp=900.0)
    bed("amb_crickets", "455685", 6.0, hp=1500.0)
    bed("amb_water", "438839", 8.0, hp=60.0)


def main() -> None:
    if len(sys.argv) >= 3 and sys.argv[1] == "fetch":
        fetch(Path(sys.argv[2]))
        return
    if len(sys.argv) < 4 or sys.argv[1] != "build":
        sys.exit(__doc__)
    downloads, ffmpeg = Path(sys.argv[2]), sys.argv[3]
    OUT.mkdir(parents=True, exist_ok=True)
    make_synth(ffmpeg)
    make_recorded(Sources(downloads, ffmpeg), ffmpeg)
    total = sum(p.stat().st_size for p in OUT.glob("*.ogg"))
    print(f"{len(list(OUT.glob('*.ogg')))} sounds, {total / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
