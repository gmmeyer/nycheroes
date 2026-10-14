# Roadmap

A superhero game that runs in a web browser: an accurate 1:1 scale New York
City, surrounded by ocean like a GTA map, where players fly, web-swing,
super-speed and super-jump around the city and fight thugs on the street.

**Platform:** Godot 4.7 web export (Compatibility renderer, WebGL 2). Every
feature has to run in a browser; see "Constraints" below. Mac and Windows
versions come last (step 8).

| Step | What | Status |
|------|------|--------|
| 1 | Manhattan you can fly around | Done (`fd47a17`) |
| 2 | Hero with superpowers | Done (`fd9c7ff`) |
| 3 | Street fights | Done (`ba5e606`) |
| 4 | All five boroughs and bridges | Done (`bfa80ab`) |
| 5 | Co-op multiplayer | Done (`c1e717a`); public hosting still to do |
| 6 | Realism from open data | In progress (terrain done) |
| 7 | Overpasses and missing bridges | Planned |
| 8 | Mac and Windows versions | Planned (last) |

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

## 5. Co-op multiplayer (done; public hosting still to do)

- **Joining:** press M for the co-op menu. "Host a game" gives a 4-letter
  room code and an invite link (`?join=CODE`); friends join with either.
  Players who join start next to the host's hero. Up to 8 players.
- **Connections:** browsers connect directly over WebRTC, every player to the
  host (Godot relays between the others). A small signaling server
  (`tools/signaling`, Node.js) only introduces players by room code; game
  traffic never goes through it. It also hands out the STUN/TURN servers to
  use (`ICE_SERVERS`), so a relay can be added without rebuilding the game.
- **Who runs what:** each player moves their own hero and sends its state 20
  times a second; other games show a copy, drawn a moment in the past so it
  moves smoothly. The host runs every thug and spawns gangs near every
  player, loading the streets around each player's hero so thugs there have
  ground to stand on. It tells each player about thugs within 400 m.
- **Hits:** a player's punch on a thug shows at once on their screen and is
  reported to the host, which applies it and tells everyone else. Thugs
  punching another player's hero are sent to that player. Pedestrians stay
  local to each player but run from fights anywhere.
- **Positions** go between games in world coordinates, since each player has
  their own floating origin.
- **Tested:** `tests/coop_test.tscn` runs a host and a second game over ENet
  (desktop has no WebRTC) and checks positions, thugs showing up and fighting
  both ways, and players far apart. Two headless Chrome instances also
  connected over WebRTC through the signaling server.
- **Still to do:** host the game, its tiles and the signaling server publicly
  (with `wss://`), and add a TURN relay for players whose networks block
  direct connections. If the host leaves, the game ends for everyone.

## 6. Realism from open data (in progress)

Chosen over Google's Photorealistic 3D Tiles, which can't run in our browser
game without switching engines, cost money per player session, can't be
cached, and have unclear terms for game use.

In order:

1. **Real shape:** terrain (done, below); real roof shapes and setbacks from
   TUM's open LoD2 model, merged with today's footprints by building ID;
   curbs, medians and piers. (Bridges and overpasses come in step 7.)
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

**Terrain (done):**
- Ground heights come from the USGS 3DEP 1/3 arc-second elevation model
  (about 10 m, bare earth, 2 tiles, 660 MB), resampled onto a 5 m grid in
  our map projection (`tools/citygen/terrain.py`). It's used instead of the
  city's 1-foot model (3.3 GB, undocumented format), whose extra detail our
  ground mesh can't show yet.
- Streets, sidewalks and parks bend with the terrain every 20 m (40 m and
  160 m in the coarser tiles). Heights in between are blended the same way
  the mesh is, so sidewalk lanes and building bases sit exactly on it.
- Buildings stand on their lowest corner; uphill, their walls run into the
  ground. Bridges ramp down to the real street height at each end.
- 904 lakes, reservoirs, ponds and creeks above sea level (Central Park
  Reservoir at 37 m, Silver Lake at 69 m) get their own water surface over
  a lake bed; creeks follow the terrain downhill. Heroes swim at whatever
  level the water is.
- The hero is dropped onto the ground at spawn; pedestrians and gangs spawn
  only when the hero is near street level (not above it).
- Cost: full-detail tiles grew from 420 to 600 MB in total (mid-detail 105
  to 170 MB); the far tiles that load first barely changed (27 MB).

Groundwork: streamed imagery in GPU-compressed formats (Godot 4.7 can load
DDS/KTX at runtime), instancing and LOD for props, a multi-threaded web build
for background decoding, and quality presets for weaker laptops.

**Decisions to make before step 6:**
- Whether the Mac and Windows versions (step 8) get extra looks from
  Godot's Forward+ renderer (ambient occlusion, reflections, volumetric fog,
  which WebGL lacks), or match the browser exactly.
- Budget for landmark models (buy/commission vs. free and self-made).
- How large the browser download may grow.

## 7. Overpasses and missing bridges (planned)

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

## 8. Mac and Windows versions (planned, last)

Downloadable versions of the game for Windows and macOS, alongside the
browser version. Godot exports both from the same project; the export
templates for both are already installed.

- **Builds:** export presets for Windows (64-bit) and macOS (one app for
  Apple Silicon and Intel), made by a build script like the web one. Desktop
  versions can drop browser limits: multi-threaded tile loading and more
  detail drawn further out.
- **Renderer:** keep the Compatibility renderer so all three look the same,
  or use Forward+ on desktop for better lighting (decided before step 6).
- **City tiles:** either ship them with the download (about 550 MB; the game
  already loads tiles from a `tiles` folder next to the executable), or
  stream them from the same server as the web version so the download stays
  small. Streaming also keeps every version on the same city data.
- **Co-op with browser players:** desktop Godot has no built-in WebRTC, so
  add the official WebRTC plugin (webrtc-native GDExtension) for Windows and
  macOS; then desktop and browser players can join the same games.
- **Signing:** macOS apps need an Apple Developer account ($99/year) for
  signing and notarization, or Macs warn that the app can't be checked; a Mac
  is also needed to test the macOS build. Windows builds run unsigned, but
  SmartScreen warns about them until they're signed with a code-signing
  certificate.

## Constraints

- **Browser first, WebGL 2.** Godot web builds use the Compatibility renderer;
  official WebGPU support doesn't exist yet. Lighting gotchas we've measured:
  use AgX tonemapping, give meshes real normals, write shader colors in sRGB.
- **Single-threaded by default.** Tile decoding happens on the main thread
  within a per-frame budget. A threaded build needs cross-origin isolation
  headers from the host.
- **Floating origin.** World positions are scene positions plus
  `WorldOrigin.offset`; anything physics-driven must survive a shift.

## Working on the project

- Rebuild city data: `tools/citygen/fetch_data.py` (NYC Open Data and the
  USGS elevation tiles), then `build_tiles.py` (Python venv in
  `tools/citygen/.venv`, `requirements.txt` alongside).
  Prepared geometry is cached in `data/cache`; delete it after changing
  `prepare.py` or re-downloading.
- Web build: `tools/build_web.ps1` (add `-Serve` to play at
  http://localhost:8060; it also runs the co-op signaling server on port
  8070, after `npm install` in `tools/signaling`).
- Tests (headless): `godot --headless --path . res://tests/hero_moves_test.tscn`,
  `res://tests/combat_test.tscn`, `res://tests/streaming_test.tscn` and
  `res://tests/coop_test.tscn`.
- Launch options (URL or `-- --name=value` on desktop): `?cam=x,y,z,yaw,pitch`
  free camera, `?spawn=x,y,z,yaw` hero start, `?stats` console stats,
  `?peds=N`, `?gangs=N`, `?demo` / `?demo=fight` scripted tours for videos,
  `?host` / `?join=CODE` co-op, `?signal=wss://...` signaling server
  (default: the page's host, port 8070).
