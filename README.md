# NYC Heroes

A superhero game that runs in a web browser: all five boroughs of New York
City at 1:1 scale, built from open data and surrounded by ocean. Players
fly, web-swing, super-speed and super-jump around the city, fight gangs of
thugs on the street, and play co-op with each other.

Play it at **https://nycheroes.party** (computers, phones and tablets).
Windows and Mac versions are on the site's download page.

## What's in it

- **The city:** about 1.08 million buildings from the NYC 3-D Building
  Model, real streets, sidewalks, parks, water, bridges, elevated railways,
  trees, street furniture, shop signs and street name signs, plus
  hand-modeled landmarks. Streamed in 500 m / 1 km / 4 km tiles so the
  whole city shows from the air.
- **Life on the streets:** pedestrians on real sidewalk lanes, traffic that
  obeys signals, subway trains on the elevated lines, day and night, and a
  city soundscape.
- **The hero:** running, super speed, charged super jumps, flight, web
  swinging, swimming, punch combos, dive attacks and landing slams; a
  customizable look and outfit.
- **Co-op:** one big public game by default, or a private game with a code.
  Peers connect over WebRTC (relayed through TURN when they must).

## Controls

| Action | Keyboard and mouse | Gamepad |
|---|---|---|
| Move | WASD | Left stick |
| Look | Mouse | Right stick |
| Jump (hold to charge) | Space | A |
| Descend | C | B |
| Sprint / super speed | Shift | L3 or left bumper |
| Toggle flight | F | Y |
| Web | E or right mouse | Right trigger |
| Attack | Left mouse | X |
| Co-op menu | M | |
| Hero and options | O or Esc | |
| Time of day | T | |

Phones and tablets get touch controls.

## Running it locally

You need [Godot 4.7.2](https://godotengine.org/) (the project uses the
Compatibility renderer and Jolt physics).

- **In the editor:** open `project.godot` and run. The editor reads city
  tiles from `data/tiles`, which isn't in git; build them (below) or point
  the game at a copy with `-- --tiles=<dir>`.
- **Web build:** `tools/build_web.ps1 -Serve` (Windows) exports to
  `build/web` and serves it at http://localhost:8060 along with the co-op
  signaling server (run `npm install` in `tools/signaling` first). On
  Linux, `.niteshift/files/build-web` exports the build and
  `node .niteshift/files/serve-web.mjs` serves it, fetching tiles from the
  public site.
- **Desktop builds:** `tools/build_desktop.ps1` makes the Windows and Mac
  zips in `build/desktop`. They stream tiles from the public site unless
  given `-- --tiles=<dir>`.

### Building the city tiles

The tiles are generated from public data by `tools/citygen` (Python 3.14,
`pip install -r tools/citygen/requirements.txt`):

```sh
python tools/citygen/fetch_data.py   # ~4 GB download, ~33 GB unpacked
python tools/citygen/build_tiles.py  # ~12 minutes on many cores, lots of RAM
```

Output goes to `data/tiles/nyc`. See "Working on the project" in
[docs/ROADMAP.md](docs/ROADMAP.md) for partial rebuilds and the other
generators.

### Launch options

Add them to the URL (`?quality=low&time=21:00`) or, on desktop, after
`--` on the command line (`-- --quality=low`). A few useful ones:
`?quality=low|medium|high`, `?time=HH:MM`, `?spawn=x,y,z,yaw`,
`?peds=N`, `?traffic=N`, `?gangs=N`, `?solo=1`, `?host`, `?join=CODE`,
`?stats`. The full list is in [docs/ROADMAP.md](docs/ROADMAP.md).

## Tests

Game tests are headless Godot scenes in `tests/` that exit non-zero on
failure:

```sh
godot --headless --path . res://tests/hero_moves_test.tscn
```

The co-op tests start the signaling server, so run `npm install` in
`tools/signaling` first. Python tests for the city and audio tools:

```sh
python -m unittest discover -s tools/citygen -p 'test_*.py'
python -m unittest discover -s tools/audio -p 'test_*.py'
```

## Project layout

| Path | What |
|---|---|
| `scenes/`, `scripts/` | The game (GDScript): hero, NPCs, combat, world streaming, traffic, trains, audio, networking, UI |
| `shaders/` | Building facades, ground, landmarks, water, sky, signs and more |
| `assets/` | Audio, textures, models and fonts |
| `tests/` | Headless test and benchmark scenes |
| `tools/citygen/` | Builds the city tiles from NYC open data |
| `tools/signaling/` | Co-op signaling server (Node) |
| `tools/cloudflare/` | The public site: a Worker, R2 and a Durable Object for signaling |
| `tools/audio/` | Builds the game's sound bank |
| `docs/` | Roadmap, design notes and reference comparisons |

## Documentation

- [docs/ROADMAP.md](docs/ROADMAP.md): what's been built, how, and the
  constraints it works within; also the full developer guide.
- [docs/REFERENCE.md](docs/REFERENCE.md): the game next to real photos of
  the same views.
- [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md),
  [docs/FLIGHT_STREAMING.md](docs/FLIGHT_STREAMING.md),
  [docs/LOW_QUALITY.md](docs/LOW_QUALITY.md): notes on specific features.
- [CREDITS.md](CREDITS.md): data sources, assets and their licenses.
