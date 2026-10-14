# Roadmap

A superhero game that runs in a web browser: an accurate 1:1 scale New York
City, surrounded by ocean like a GTA map, where players fly, web-swing,
super-speed and super-jump around the city and fight thugs on the street.

**Platform:** Godot 4.7 web export (Compatibility renderer, WebGL 2). Every
feature has to run in a browser; see "Constraints" below.

| Step | What | Status |
|------|------|--------|
| 1 | Manhattan you can fly around | Done (`fd47a17`) |
| 2 | Hero with superpowers | Done (`fd9c7ff`) |
| 3 | Street fights | Done (`ba5e606`) |
| 4 | All five boroughs and bridges | Done |
| 5 | Co-op multiplayer | Planned |
| 6 | Realism from open data | Planned |
| 7 | Overpasses and missing bridges | Planned (last) |

## 1. Manhattan you can fly around (done)

- `tools/citygen` downloads NYC Open Data (building footprints with roof
  heights, shoreline, parks, street surfaces) and builds 500 m tiles: full
  detail (lod0) nearby, simplified (lod1) out to the horizon.
- The game streams tiles around the camera, and re-centers the world as you
  move (`WorldOrigin`) so float precision holds across the whole city.

## 2. Hero with superpowers (done)

Running, 60 m/s super speed, charged super jumps (~100 m), flight up to
150 m/s, web swinging, and swimming. Movement modes are separate scripts;
the hero is driven by a plain input object per physics tick so a network
peer can drive one later. Nearby tiles get collision.

## 3. Street fights (done)

- Pedestrians walk real sidewalk lanes (traced from street data), run from
  danger, and can never be hurt.
- Gangs of thugs surround and attack the hero, at most two swinging at once.
- Punch combos, dive attacks, landing slams and super speed rams; defeated
  thugs ragdoll, bleed, and stay on the street while you're nearby.
- Hero health, knockouts, and a HUD with a marker to the nearest thug.

## 4. All five boroughs and bridges (done)

- **Data:** citywide buildings (1.08M footprints), streets, parks, lakes and
  reservoirs, rivers and bays, beaches, marshes, piers, and bridge structures
  from NYC Open Data.
- **Coastline:** the city limits become the coast, so the whole city is an
  archipelago in the ocean, like a GTA map. Lakes and rivers are cut out of
  the land; beaches and marshes get their own ground colors.
- **Scale:** `prepare.py` turns the raw data into cached geometry once;
  `build_tiles.py` builds tiles on all cores (about 4 minutes). Three levels
  of detail, each drawn until all of its children have loaded:
  - near: 500 m tiles, full detail, collision and walking lanes, 420 MB
    total;
  - mid: 1 km tiles, small buildings merged into blocks, 105 MB;
  - far: 4 km tiles, buildings merged by height band, 24 MB, so the whole
    city shows from the air.
- **Bridges:** 104 bridge decks over water, ramping down to the street on
  each shore, with parapets and columns. The six big suspension bridges
  (Brooklyn, Manhattan, Williamsburg, Verrazzano, Throgs Neck and Whitestone)
  have towers and cables, spaced by their real main spans. Without depth data
  each main span is centered over the water, which puts the Throgs Neck
  towers off from where they really stand (fixed in step 7). Bridges to New
  Jersey and Nassau County are left out (ocean in this world).
- **Results:** in the browser every spot tested loads in 1.5–3.5 s (8–10 s
  for a cold first load), at 150 FPS with under 1M triangles. The headless
  `tests/streaming_test.tscn` checks for missing or doubled tiles across all
  five boroughs.
- **Kept open for step 6:** the prepared building data keeps each building's
  ID (BIN and BBL) for joining city records later; the tile format is
  versioned for added layers.
- **Ceiling:** nobody goes above 1 km (`WorldOrigin.CEILING`, about twice
  the height of One World Trade Center), including the free camera. The ocean
  fades into the haze before its edge, so the edge of the world never shows.
- **Known gaps (step 7):** overpasses on land stay at street level, and a
  few bridges are missing from the data.

## 5. Co-op multiplayer (planned)

- Peer-to-peer over WebRTC (built into Godot web builds). One player's
  browser hosts: it runs the thugs and decides every hit (all hits already go
  through `Combat`), and each player moves their own hero.
- Needs a tiny matchmaking ("signaling") service to introduce players, e.g. a
  free-tier serverless function, and ideally a relay (TURN) fallback for
  players whose networks block direct connections.
- Positions are sent in world coordinates, since every player has their own
  floating origin.
- Aimed at small groups (about 2–8 players).

## 6. Realism from open data (planned)

Chosen over Google's Photorealistic 3D Tiles, which can't run in our browser
game without switching engines, cost money per player session, can't be
cached, and have unclear terms for game use.

In order:

1. **Real shape:** terrain from the NYC 1-foot elevation model; real roof
   shapes and setbacks from TUM's open LoD2 model, merged with today's
   footprints by building ID; curbs, medians and piers. (Bridges and
   overpasses come in step 7.)
2. **Real view from above:** NY State aerial photos (2024/2025) draped on
   streets, parks and roofs. The license needs confirming first.
3. **Real architecture:** styles chosen from city tax-lot data (PLUTO:
   building class, year, floors, landmark status) with real photo textures
   (CC0 libraries); storefronts, fire escapes, cornices, rooftop water towers.
4. **Street life:** street trees (tree census), hydrants, bus shelters,
   LinkNYC kiosks, benches, bike parking, parking meters, subway entrances,
   street and traffic lights; parked cars and traffic.
5. **Landmarks:** about 25 hand-made iconic buildings and bridges.
6. **Light and atmosphere:** sun position for NYC, clouds, haze, glass
   reflections, night mode with lit windows and street lights.
7. **Check against reality:** about 10 reference viewpoints compared side by
   side with real photos after each phase (`?cam=` start positions).

Groundwork: streamed imagery in GPU-compressed formats (Godot 4.7 can load
DDS/KTX at runtime), instancing and LOD for props, a multi-threaded web build
for background decoding, and quality presets for weaker laptops.

**Decisions to make before step 6:**
- Browser only, or also a high-end desktop build (Godot's Forward+ renderer
  has ambient occlusion, reflections and volumetric fog that WebGL lacks).
- Budget for landmark models (buy/commission vs. free and self-made).
- How large the browser download may grow.

## 7. Overpasses and missing bridges (planned, last)

Comes after step 6 because it needs step 6's real ground heights.

- **Overpasses:** about 1,000 bridge outlines in the city data cross land,
  not water (2.3 km²): highway overpasses, raised stretches of expressways
  like the Major Deegan, and rail bridges over streets. Today they're
  skipped, and the roads on top are drawn flat at street level.
- **How high:** the street centerline data marks which road sections are
  bridges; deck heights come from the city's elevation data (step 6). Each
  raised road ramps down where it meets the ground.
- **Two levels of road:** the deck on top gets columns and collision (you can
  land on it, run under it, and swing from it); the street underneath stays,
  with its sidewalks and pedestrians.
- **Missing bridges:** add by hand the bridges the data lacks or has only in
  part, starting with the Kosciuszko Bridge (the BQE over Newtown Creek),
  which the data has only as a 149 m² scrap. Check the full list of the
  city's named bridges for others.
- **Tower positions:** place suspension towers where they really stand
  instead of centering them over the water (the Throgs Neck is off today).

## Constraints

- **Browser only, WebGL 2.** Godot web builds use the Compatibility renderer;
  official WebGPU support doesn't exist yet. Lighting gotchas we've measured:
  use AgX tonemapping, give meshes real normals, write shader colors in sRGB.
- **Single-threaded by default.** Tile decoding happens on the main thread
  within a per-frame budget. A threaded build needs cross-origin isolation
  headers from the host.
- **Floating origin.** World positions are scene positions plus
  `WorldOrigin.offset`; anything physics-driven must survive a shift.

## Working on the project

- Rebuild city data: `tools/citygen/fetch_data.py`, then `build_tiles.py`
  (Python venv in `tools/citygen/.venv`, `requirements.txt` alongside).
  Prepared geometry is cached in `data/cache`; delete it after changing
  `prepare.py` or re-downloading.
- Web build: `tools/build_web.ps1` (add `-Serve` to play at
  http://localhost:8060).
- Tests (headless): `godot --headless --path . res://tests/hero_moves_test.tscn`,
  `res://tests/combat_test.tscn` and `res://tests/streaming_test.tscn`.
- Launch options (URL or `-- --name=value` on desktop): `?cam=x,y,z,yaw,pitch`
  free camera, `?spawn=x,y,z,yaw` hero start, `?stats` console stats,
  `?peds=N`, `?gangs=N`, `?demo` / `?demo=fight` scripted tours for videos.
