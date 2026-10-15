# Roadmap

A superhero game that runs in a web browser: an accurate 1:1 scale New York
City, surrounded by ocean like a GTA map, where players fly, web-swing,
super-speed and super-jump around the city and fight thugs on the street.

**Platform:** Godot 4.7 web export (Compatibility renderer, WebGL 2). Every
feature has to run in a browser, on computers and on phones (step 7); see
"Constraints" below. Mac and Windows versions come last (step 9).

| Step | What | Status |
|------|------|--------|
| 1 | Manhattan you can fly around | Done (`fd47a17`) |
| 2 | Hero with superpowers | Done (`fd9c7ff`) |
| 3 | Street fights | Done (`ba5e606`) |
| 4 | All five boroughs and bridges | Done (`bfa80ab`) |
| 5 | Co-op multiplayer | Done (`c1e717a`); public at https://nycheroes.party |
| 6 | Realism from open data | In progress (real shape, stylized facades, trees, water towers, street paint, roofs and night done) |
| 7 | Phones and tablets | In progress |
| 8 | Overpasses and missing bridges | Planned |
| 9 | Mac and Windows versions | Planned (last) |

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
  towers off from where they really stand (fixed in step 8). Bridges to New
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
- **Known gaps (step 8):** overpasses on land stay at street level, and a
  few bridges are missing from the data.

## 5. Co-op multiplayer (done)

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
- **Public (2026-10-15):** https://nycheroes.party on Cloudflare: the game,
  its tiles and signaling (a Durable Object at `/signal`) from one Worker
  (`tools/deploy_cloudflare.ps1`, see "Working on the project"); published
  after every step.
- **Still to do:** a TURN relay for players whose networks block direct
  connections (only STUN today). If the host leaves, the game ends for
  everyone.

## 6. Realism from open data (in progress)

Chosen over Google's Photorealistic 3D Tiles, which can't run in our browser
game without switching engines, cost money per player session, can't be
cached, and have unclear terms for game use.

**Art direction (decided 2026-10-15): cartoony but real.** Real shapes and
real building types from the data, drawn in a stylized way (curated
palettes, soft toon shading, bold simple details) rather than with photos.
The aerial photos stay only as a comparison (`?aerial=1`).

In order:

1. **Real shape (done, below):** terrain, building shapes, curbs and
   medians. (Bridges and overpasses come in step 8.)
2. **Real view from above (done, below, now opt-in):** the city's 2024
   aerial photos draped over streets, parks and roofs; replaced by the
   stylized look by default.
3. **Real architecture (done, below):** every building's type from
   the city's tax lot data (PLUTO: building class, year, floors, retail
   space, landmark status), drawn as stylized facades: real floor counts,
   storefronts, fire escapes, cornices, blank side walls; rooftop water
   towers.
4. **Street life:** trees and street paint (done, below); hydrants, bus
   shelters, LinkNYC kiosks, benches, bike parking, parking meters, subway
   entrances, street and traffic lights; parked cars and traffic.
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

**Building shapes (done):**
- From the city's own 3-D Building Model (Office of Technology and
  Innovation, LoD2 CityGML, 0.9 GB zip), the source TUM's model was built
  from. `tools/citygen/buildings3d.py` reads it straight from the zip and
  keeps the 308,000 buildings whose roofs aren't one flat level: setbacks,
  towers and spires (the Empire State Building's tiers and mast, the
  Chrysler Building's crown).
- They replace the footprint prisms by building ID (BIN) where the model
  still matches today's building (outline and height): about 295,000 do.
  Newer buildings keep their prisms. Some model surfaces face the wrong way;
  roofs are turned up and walls toward open air.
- The model is massing only: roofs are flat levels, not pitched.
- Mid-detail tiles use real shapes for buildings 40 m and taller, far tiles
  for 120 m and taller (the skyline).
- Roofs are marked in the tiles (so sloped ones aren't drawn with windows).
  Webs look in a wider fan, since walls high enough to swing from now often
  step back from the street.
- Cost: full-detail tiles grew to 757 MB in total (mid 187 MB, far 29 MB).

**Curbs and medians (done):**
- Up close, streets sit 15 cm below the sidewalks behind concrete curbs.
  Medians are left out of the city's road data, so they're raised islands
  with curbs too (green where the parks data has them, like Park Avenue's).
  Hairline gaps between road pieces are closed first so no curbs cross the
  street.
- Heroes and thugs step up curbs and other ledges up to 35 cm
  (`scripts/util/ledge_climb.gd`); Godot's character controller alone
  treats any step as a wall.
- Waterfronts and piers sit at least 2 m above sea level (the pier data's
  median deck height is 2.1 m).
- Cost: full-detail tiles grew to 852 MB in total.

**Aerial photos (done; opt-in since the cartoony-but-real decision):**
- The city's 2024 orthoimagery (NYC OTI with the NYS Statewide Digital
  Orthoimagery Program, 6-inch, flown March 2024). The city's metadata gives
  CC BY 4.0, though its map service points to the general NYC.gov terms;
  we went with CC BY 4.0, and the HUD shows the credit whenever photos are
  on screen (see `CREDITS.md`). They're true orthophotos: roofs line up with
  the footprints instead of leaning.
- `tools/citygen/aerial.py` downloads the city's web-map tiles at zoom 18
  (about 0.45 m per pixel; 74,000 tiles, 1.2 GB, cached in data/raw) and
  resamples them into one JPEG per city tile in our projection: 0.5 m per
  pixel up close (1128 px), 2 m mid (564 px), 16 m far (266 px), each with a
  margin (32, 64, 128 m) for roofs that overhang their tile. 1.2 GB in all;
  a player only downloads the tiles around them (about 9 MB at the start).
- The game drapes each photo over its tile's ground, bridges and roofs; walls
  keep their painted windows. Within about 100 m of the camera the ground
  goes back to its plain colors, since the photo is blurry at eye level.
- The photos have the morning's shadows baked in: the shader softens them,
  and the game's sun now shines from the same direction (south-east), so its
  own shadows agree. Parks are tinted greener (bare March trees), and the
  asphalt and ambient light were lightened so shaded streets aren't black.
- `?aerial=0` turns photos off; `?aerial_shadow=` and `?aerial_brightness=`
  tune them. Photo textures take about 150-230 MB of GPU memory; decoding a
  close-up photo takes about 7 ms on the web, at most one per frame.

**Stylized facades and ground (done):**
- `tools/citygen/facades.py` joins every building to its tax lot (PLUTO,
  via the footprints' `mappluto_bbl`; 99.97% match) and picks one of 16
  New York types: house, rowhouse/brownstone, walk-up, prewar / postwar /
  modern apartments, prewar / midcentury / modern offices, cast-iron loft
  (also any prewar building in the SoHo cast-iron and Tribeca districts),
  store, industrial, institution, hotel, other. Plus details: storefronts
  where there's retail space, fire escapes on walk-ups built before 1930,
  cornices before 1940, landmarks; and the floor height from the real floor
  count.
- Tiles carry this per face (uv2.x = type + 64 x flags, uv2.y = floor height
  in dm + seed). `build_tiles.py` marks walls that face a street (fronts get
  windows, shops and fire escapes; side and back walls are mostly blank
  brick), and paved ground away from streets near homes as yards. Merged
  far blocks take the type of most of their buildings.
- The look (`shaders/building.gdshader`, `ground.gdshader`, `toon.gdshaderinc`,
  `patterns.gdshaderinc`, `sky.gdshader`): stylized realism with curated
  palettes per type, soft toon lighting (warm afternoon sun from the
  south-west, cool sky shadows, warm bounce on shaded walls), bold simple
  details (lintels, AC units, fire escapes, awnings, lit shop windows,
  cornices, cast-iron arches, glass that reflects the sky), sidewalk flags,
  asphalt patches, mottled grass, lawns and patios in yards, cartoon clouds.
  Details fade to their average color in the distance.
- `?sun_dir=az,el`, `?saturation=`, `?sh_<uniform>=<value>` and friends
  tune the look from the URL (`scripts/world/lighting_overrides.gd`).
- Cost: full-detail tiles 938 MB in total (mid 225 MB); frame rate unchanged.

**Trees, water towers and street paint (tile format v6):**
- Street trees: all ~886,000 living trees in the Parks Department's street
  tree inventory (Forestry Tree Points), each with its species and trunk
  size: London planes and oaks get broad crowns, Callery pears and ginkgos
  narrow ones, pines and cedars are conifers; honeylocusts and ginkgos are
  light green, oaks and lindens dark, purple-leaf plums and 'Crimson King'
  maples red. Height comes from trunk size. Trees the data puts in the road
  (it and the road outlines disagree by a meter or two) step onto the curb.
- Every other tree (parks, back yards, woods) comes from the city's 2017
  land cover map (LiDAR, 6-inch pixels; `tools/citygen/landcover.py`
  samples its 8x reduced layer onto a 2 m grid): one tree per 7 m cell of
  canopy, on a jittered grid, kept off streets and buildings and away from
  street trees, taller where the canopy is thick, with conifers in patches.
- Rooftop water towers: a guess per building from its type, floors (six and
  up, under 160 m) and borough (most likely on prewar Manhattan walk-ups,
  apartments, offices and lofts; rare on Staten Island), at a back corner of
  the roof, on the real roof level where the 3-D model has one. A few big
  roofs get two; 15% are steel.
- Street paint from the city's street centerlines (CSCL: lanes, width,
  traffic direction): double yellow lines on two-way streets, dashed lane
  lines (10-foot dashes, 30-foot gaps), edge lines on highways, and at
  intersections with a bigger street, high-visibility crosswalks and stop
  lines on the lanes coming in (`tools/citygen/markings.py`). Lines are
  strips with coordinates along and across them, and the game's shader
  paints the dashes and the double line, so a line costs a few vertices
  instead of a quad per dash; strip pieces that would hang over a curb or
  median are left out. Crosswalks and stop lines are measured across the
  road surface, curb to curb. Only street-level roads get paint.
- Tiles carry props as points (position, height, width, yaw, type, tone,
  trunk, seed) in a props surface, and paint as its own mesh surface (no
  collision), in full-detail tiles only.
- The game draws props with instancing (`scripts/world/city_props.gd`,
  meshes built in code in `prop_meshes.gd`): one draw call for all of a
  tile's trees (90-triangle trees in three shapes, picked per tree in the
  shader, with wind sway), one for its water towers (140 triangles: staved
  wood or steel tank, hoops, roof, legs), and cheap 30-triangle stand-ins
  for tree shadows. Trees fade out by about 850 m; beyond that, a
  citywide canopy map (8 m pixels, 3.9 MB, from the land cover map) darkens
  wooded parks and yards in the ground shader, so woods still read from the
  air. Paint has its own shader (`shaders/markings.gdshader`): dashes,
  double lines and crosswalk bars drawn from the strip coordinates,
  anti-aliased, nudged toward the camera so it never flickers against the
  road.
- Famous prewar landmarks (offices, apartments, hotels, institutions marked
  as landmarks) get limestone, granite or terracotta instead of brick: the
  Empire State, Chrysler and Woolworth buildings read as stone.
- Cost: full-detail tiles 1,088 MB in total (+150 MB: trees and water
  towers 74, paint 76), plus the 3.9 MB canopy map; 3.4 million trees and
  9,637 water towers citywide. About +0.3-0.8 ms per frame (draw calls in
  midtown 190 to 290); every view still at the 145 FPS cap.
- Still to do: other street furniture.

**Roofs: parapets and pitched roofs (done):**
- Up close, flat roofs get 1 m parapets: the walls rise above the roof
  with an inner face, and the shader draws the band solid (no windows)
  under its coping or cornice, and the inside as plain wall. Rowhouse rows
  show their party walls; the parapets cast toon shadows on the roofs.
- Detached houses (the 3-D model's roofs are flat levels) get gable or hip
  roofs, 28-40 degrees, over their footprint's smallest enclosing
  rectangle when the footprint fills most of it, peaking at the data's
  height; walls rise to the roof line with gable ends, and shingle rows
  follow the eaves. Other houses keep flat roofs.
- Cost: full-detail tiles 1,201 MB (+113 MB); frame rate unchanged.

**Night: time of day, street lights, lit windows (done):**
- `scripts/world/time_of_day.gd` owns the clock: the sun follows New York's
  real arc (through azimuth 235°, elevation 42° at 15:30; sunset about
  19:25), a full moon takes over the light at night, and the sky, fog,
  ambient light and exposure blend from day through dusk to night. Shader
  globals (`night`, `dusk`, `city_lights`, `clock_hours`, the street light
  map) reach every city shader through `shaders/night.gdshaderinc`; with
  them at 0, the day looks exactly as before.
- **T** steps to the next of dawn, day, dusk and night; `?time=HH:MM` sets
  the clock, `?daylength=MINUTES` runs it.
- 545,000 street lights (new prop type 4): the city publishes no lamp
  positions, so they stand along every curb about every 35 m, 0.6 m onto
  the sidewalk, arms over the street; historic post-tops in and beside
  parks. Drawn instanced (52- and 78-triangle lamps), with glowing lenses
  and halos that turn into dots in the distance.
- Light pools: each near tile adds its lamps to a 2 km street light map
  (a SubViewport, 2 m pixels, redrawn only when tiles change or the camera
  moves 256 m) that the ground, paint, wall feet, tree crowns and posts
  sample; beyond about 650 m streets get an average glow instead.
- Lit windows hashed per window by building type and hour (homes busy in
  the evening, offices emptying late), warm with some cool and the odd TV;
  shops glow and pull down roll gates after 21:00; lobbies glow; masonry
  landmarks' setbacks above 40 m are floodlit (the Empire State and
  Chrysler tops). Far away, windows settle into an even glow.
- Night sky with stars, a moon and city-lit clouds; dusk and dawn colors;
  bridge cables strung with lights; moonlit, darker water.
- Cost: about one more draw call per near tile at night; frame rate the
  same as by day.
- `?demo=city` flies the camera over the city, day into night, for videos
  (with "[demo] pause"/"resume" around loading, so recordings skip it).

Groundwork: streamed imagery in GPU-compressed formats (Godot 4.7 can load
DDS/KTX at runtime), instancing and LOD for props, a multi-threaded web build
for background decoding, and quality presets for weaker laptops.

**Decisions to make before step 6:**
- Whether the Mac and Windows versions (step 9) get extra looks from
  Godot's Forward+ renderer (ambient occlusion, reflections, volumetric fog,
  which WebGL lacks), or match the browser exactly.
- Budget for landmark models (buy/commission vs. free and self-made).
- How large the browser download may grow.

## 7. Phones and tablets (in progress)

Added 2026-10-15 at the user's request: the game should be playable on a
phone, in the phone's browser, at https://nycheroes.party.

- **Touch controls:** a virtual stick to move, dragging anywhere else to
  turn the camera, and buttons for jump (hold for a super jump), punch
  (in the air: dive attack), web swing, fly (with up and down), super speed
  and the co-op menu. They show up on touch screens only; a keyboard and
  mouse keep working as before.
- **The page:** landscape (asking to turn the phone otherwise), fullscreen
  where the browser allows it, no page scrolling, pinch zoom or text
  selection getting in the way of the controls.
- **Performance:** a phone quality preset picked automatically (lower
  render resolution, shorter view distances, fewer shadows, smaller
  crowds), within phone browsers' memory limits (iOS Safari is the
  tightest).
- **Testing:** Chrome's phone emulation (touch events, a phone-sized
  screen) in the automated checks, and real phones on the public site.

## 8. Overpasses and missing bridges (planned)

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

## 9. Mac and Windows versions (planned, last)

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
- **Animated characters in Chrome on Windows** go through ANGLE (WebGL on
  Direct3D 11), which treats Godot's skinned-vertex buffers as dynamic and
  stalls on them until a pose stays still for ~30 frames.
  `scripts/util/skin_warmup.gd` holds each character's pose briefly the
  first time it's on screen and stops animating characters off screen; that
  took a crowded Times Square from 22-35 FPS to the 180 FPS cap.
- **Floating origin.** World positions are scene positions plus
  `WorldOrigin.offset`; anything physics-driven must survive a shift.

## Working on the project

- Rebuild city data: `tools/citygen/fetch_data.py` (NYC Open Data, the
  USGS elevation tiles, the 3-D building model and the land cover map, about
  4 GB with 33 GB unpacked), then `build_tiles.py`,
  then, only for the photo comparison, `aerial.py` (downloads and lays out
  the aerial photos once; after later `build_tiles.py` runs, `aerial.py
  mark` re-adds them to the manifest). Python venv in `tools/citygen/.venv`,
  `requirements.txt` alongside.
  Prepared geometry is cached in `data/cache`; delete it after changing
  `prepare.py` or re-downloading.
- Web build: `tools/build_web.ps1` (add `-Serve` to play at
  http://localhost:8060; it also runs the co-op signaling server on port
  8070, after `npm install` in `tools/signaling`).
- Public site: `tools/deploy_cloudflare.ps1 [-Build]` publishes the web
  build to https://nycheroes.party (`tools/cloudflare`): one Worker serves the game and
  tiles as static assets (only changed files upload), `index.wasm` (over
  the 25 MiB asset limit) from the R2 bucket `nyc-hero-files`, and co-op
  signaling at `/signal` from a Durable Object (the game uses it by
  default over https). Needs `npx wrangler login` once, or a Cloudflare
  CLI login (`cf auth login`), which it lends to Wrangler; `npx wrangler dev`
  in `tools/cloudflare` runs it locally. First load: the 39.5 MB engine
  arrives brotli-compressed (9.6 MB).
- Tests (headless): `godot --headless --path . res://tests/hero_moves_test.tscn`,
  `res://tests/combat_test.tscn`, `res://tests/streaming_test.tscn` and
  `res://tests/coop_test.tscn`.
- Launch options (URL or `-- --name=value` on desktop): `?cam=x,y,z,yaw,pitch`
  free camera, `?spawn=x,y,z,yaw` hero start, `?stats` console stats,
  `?peds=N`, `?gangs=N`, `?demo` / `?demo=fight` scripted tours for videos,
  `?host` / `?join=CODE` co-op, `?signal=wss://...` signaling server
  (default: the page's host, port 8070), `?tree_shadows=0` trees without
  shadows.
