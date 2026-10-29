# AGENTS.md

Guidance for coding agents working in this repository. Read
[README.md](README.md) for what the game is; the full developer guide is
"Working on the project" and "Constraints" near the end of
[docs/ROADMAP.md](docs/ROADMAP.md).

## The project

NYC Heroes: a Godot 4.7.2 game (GDScript, Compatibility renderer / WebGL 2,
Jolt physics) that runs in the browser first, and also on phones and as
Windows and Mac builds. The city is generated offline by Python
(`tools/citygen`) into binary tiles that the game streams.

- `scripts/`: game code by area (`hero/`, `npc/`, `combat/`, `world/`,
  `net/`, `audio/`, `ui/`, `util/`, `camera/`, `game/`). Autoloads:
  `Settings`, `WorldOrigin`, `Net`, `Combat`.
- `scenes/world.tscn` is the main scene.
- `shaders/`: one `.gdshader` per material family; `building.gdshader` and
  `landmark.gdshader` are the big ones.
- `tools/citygen/`: data download (`fetch_data.py`), geometry cache
  (`prepare.py`), tile builder (`build_tiles.py`) and per-feature modules
  (bridges, landmarks, traffic, trains, street signs, ...).
- `tools/signaling/` (Node co-op signaling), `tools/cloudflare/` (the
  public site), `tools/web/` (web export post-processing),
  `tools/audio/` (sound bank).
- `.niteshift/`: Linux sandbox setup and services (Godot install, web
  export, preview server that proxies `/tiles/` to the public site).

## Commands

```sh
# Game tests: headless scenes, non-zero exit on failure
godot --headless --path . res://tests/<name>_test.tscn
# Co-op tests need the signaling server's packages first
npm install --prefix tools/signaling

# Python tests (synthetic data; no downloads needed)
python -m unittest discover -s tools/citygen -p 'test_*.py'
python -m unittest discover -s tools/audio -p 'test_*.py'

# Web export (Linux); Windows: tools/build_web.ps1 [-Serve]
.niteshift/files/build-web
node --test tools/web/fix_audio_loops.test.mjs   # after an export

# Shader compile time, against a served web build
node tools/shader_compile_check.mjs http://localhost:8060/
```

On a fresh checkout run `godot --headless --path . --import` once before
tests or exports, so `class_name` scripts resolve.

Pick the tests that cover what you changed (hero movement:
`hero_moves_test`; fights: `combat_test`; streaming: `streaming_test`,
`flight_streaming_regression`; co-op: `coop_*`; traffic and trains:
`traffic_test`, `trains_test`; options: `options_test`; the Go to box:
`address_test`). Each test's header comment says what it checks and how to
run it.

## City data and tiles

- `data/` (raw downloads, `data/cache`, `data/tiles`) is gitignored and
  large. Don't run `fetch_data.py` or a full `build_tiles.py` unless asked:
  they take many GB and a long time.
- In a git worktree there's no `data/`: set `NYC_DATA_DIR` to the main
  checkout's `data` folder for the Python tools, and pass
  `-- --tiles=<dir>` to the game and tests.
- To check a citygen change, rebuild a few tiles into a copy:
  `build_tiles.py --out <copy>/nyc --only lod0:0,-1 ...`.
- After changing `prepare.py`, delete `data/cache`. When a change needs new
  tiles, say so in the commit message ("Tiles holding them need
  rebuilding").
- Tile format changes must stay in step between `tools/citygen/build_tiles.py`
  and `scripts/world/city_tile_decoder.gd`.

## Constraints that bite

- **Browser first.** Everything must work in the web build: WebGL 2,
  single-threaded, on phones too. Desktop-only code paths must be guarded
  (`OS.has_feature("web")`).
- **Floating origin.** World position = scene position +
  `WorldOrigin.offset`. Anything physics-driven or cached by position must
  survive an origin shift.
- **Shader compile time** dominates first load on Windows browsers (ANGLE
  compile time grows with roughly the square of the inlined code). In big
  shaders, call each heavy helper from one place, avoid dynamically indexed
  `const` arrays, and put rare features in a shader of their own. Run
  `tools/shader_compile_check.mjs` after shader changes; targets are in
  ROADMAP.md.
- **Co-op.** Heroes are driven by a plain `HeroInput` per physics tick, and
  everything other players see is plain state synced by `PlayerSync`. Keep
  new hero state network-visible the same way.
- Use AgX tonemapping, real normals, and sRGB colors in shaders (see
  ROADMAP.md "Constraints").

## Conventions

- GDScript: tabs, static types (`var x := ...`, typed arrays and returns),
  `class_name` on reusable scripts, `##` doc comments on classes, constants
  and non-obvious members explaining *why*. Commit `.uid` files alongside
  new scripts.
- Python (citygen): plain modules, `numpy`/`shapely`/`pyproj`; unit tests
  as `test_*.py` beside the code using synthetic geometry.
- Line endings are LF everywhere (`.gitattributes`).
- Don't let Godot import `build/`: build scripts create `build/.gdignore`.
- Commit messages: a plain-English subject describing the result as a
  player would see it ("Pedestrians no longer jump sideways at every step on
  the TKTS steps"), and a body explaining what changed and why, in prose.
- Update the docs with the work: the relevant step in `docs/ROADMAP.md`
  (including test and launch option lists), `docs/REFERENCE.md` for
  realism work checked against photos, and `CREDITS.md` for any new data
  source or asset and its license.

## Deploying

The public site is https://nycheroes.party, deployed with
`tools/deploy_cloudflare.ps1` or `.niteshift/files/deploy-cloudflare`
(use `--dry-run` first). Deploying is outward-facing: only do it when
asked.
