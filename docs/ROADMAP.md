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
| 6 | Realism from open data | In progress (real shape, facades, trees, water towers, paint, roofs, night, furniture, cars and traffic, first landmarks, sound done) |
| 7 | Phones and tablets | Done in emulation; real phones to check |
| 8 | Overpasses and missing bridges | Done (raised roads, the Kosciuszko, real tower positions) |
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
- **Relay (2026-10-15):** players whose networks block direct connections
  go through Cloudflare's TURN relay: the signaling Durable Object hands out
  credentials (good for 6 hours, shared for 5 minutes) with Cloudflare's
  STUN, falling back to STUN only if Cloudflare doesn't answer. Browsers use
  the relay only when going direct fails; `?relay=1` forces it. The local
  signaling server stays STUN only. Tested with two headless Chrome players
  connected relay-only.
- **Still to do:** if the host leaves, the game ends for everyone.

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
4. **Street life:** trees, street paint, street lights and street
   furniture (done, below); parked cars and traffic.
5. **Landmarks:** about 25 hand-made iconic buildings and bridges (first
   batch of 8 done, below; self-made and free, decided 2026-10-15).
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
  still matches today's building (outline, and not shorter than the
  footprint's height): about 299,000 do. A taller model wins, since
  footprint heights often measure a podium or stop below a spire (fixed
  2026-10-15 after the reference check: the MetLife Building had been
  Grand Central's 48 m block, and One World Trade Center and the Bank of
  America Tower lacked their spires). Newer buildings keep their prisms.
- Towers newer than the 3-D model (2014) get massing from a table
  (`tools/citygen/towers.py`): 32 towers over about 150 m that had no
  usable model, whose footprint record alone drew a flat box over the
  whole lot up to the spire's tip (One Vanderbilt, Central Park Tower,
  111 West 57th, the Shops at Hudson Yards at 386 m) or a stump where the
  height was measured during construction (55 and 10 Hudson Yards, 56
  Leonard, 270 Park). Each gets its real place on the lot, podium,
  setbacks, taper, crown and steel spire at published heights, plus a
  chosen look (glass tone, limestone, terracotta). Older buildings beside
  them keep the model's shape (the Dime Savings Bank). Marble Collegiate
  Church uses the model's 47 m church instead of a 65 m box. About 3,900
  triangles up close in all. Some model surfaces face the wrong way;
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
  store, industrial, institution, hotel, other. Houses are rowhouses where
  PLUTO's proximity code says attached on both sides, houses where it says
  detached (else by class, year and borough). Plus details: storefronts
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
  citywide canopy map (16 m pixels, 1.8 MB, from the land cover map) darkens
  wooded parks and yards in the ground shader, so woods still read from the
  air. Paint has its own shader (`shaders/markings.gdshader`): dashes,
  double lines and crosswalk bars drawn from the strip coordinates,
  anti-aliased, nudged toward the camera so it never flickers against the
  road.
- Famous prewar landmarks (offices, apartments, hotels, institutions marked
  as landmarks) get limestone, granite or terracotta instead of brick: the
  Empire State, Chrysler and Woolworth buildings read as stone.
- Cost: full-detail tiles 1,088 MB in total (+150 MB: trees and water
  towers 74, paint 76), plus the 1.8 MB canopy map; 3.4 million trees and
  9,637 water towers citywide. About +0.3-0.8 ms per frame (draw calls in
  midtown 190 to 290); every view still at the 145 FPS cap.
- Still to do: parked cars and traffic.

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
- More lamps (581,000 in all): cobra-heads every 30 m along both edges of
  every bridge deck, at the deck's height (`bridges.py`), and post-tops on
  park paths, wherever the land cover map shows paving in a park, at
  least 22 m apart (paths under tree canopy are hidden in that map, so
  open paths and plazas get most of them).
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

**Times Square's signs (done):**
- Street walls in the sign district (42nd to about 50th Street around
  Broadway and Seventh Avenue, a box in `tools/citygen/props.py`) carry a
  new face flag, SIGNS (256).
- `building.gdshader` covers them, from above the shopfronts up to 40-60 m,
  with invented, animated billboards: bays of big screens, tall banners,
  dark steel frames, neon outlines and chasing bulbs, a scrolling news
  ticker; slides (color gradients, typed-out text, sunbursts, waves, giant
  glowing words, cartoon cans) change every 6-12 s. No real brands. Lit by
  day, blazing at night; far away a wall settles into one bright color.
  Only SIGNS walls pay for it.
- At night the streets and sidewalks there glow in slowly drifting pink,
  cyan and amber (`ground.gdshader`, whose box must match `props.py`).
- Frame rate unchanged (within noise; the screens fill about 40% of the
  frame at street level).

**Street furniture (done):**
- From the city's inventories, where they really stand: 110k fire
  hydrants, 38k bike racks, 21k litter baskets, 13k parking meters, 5.7k
  benches and leaning bars, 3.3k bus shelters, 2.2k LinkNYC kiosks (and
  the tall 5G poles), 1.8k subway entrances (green globes, red for exit
  only, elevators) and 361 newsstands. Points the data puts in the road
  move onto the sidewalk; hydrants and parking meters within 6 m of a curb
  move to 0.5 m from it (the data puts some by the building line);
  everything faces its nearest street.
- Traffic signals, which have no citywide data: one pole per approach,
  just behind the crosswalk on the right, its arm reaching over the road,
  at intersections with a street at least 14 m wide or with 3 lanes (about
  30,000 poles).
- 215,000 pieces in all, as new prop types 5-14 in the props surface.
- Drawn with two instanced meshes per near tile (`prop_meshes.gd`,
  `shaders/street_furniture.gdshader`): one holds every small piece
  (hydrant, bench, wire basket, solar compactor, hoop and U racks,
  Muni-Meter; 236 triangles), the other every large one (bus shelter, Link
  kiosk and 5G pole, subway stair, street elevator, traffic signal,
  newsstand; 352 triangles), and each instance folds away the shapes it
  isn't. Cartoon glass; ads and kiosk screens that change every 8 s;
  magazine racks; a street name sign on each signal. Signals cycle green,
  yellow and red, with WALK and the flashing hand; their lenses and subway
  globes stay visible far away. Subway stairs lead down into the dark
  (drawn by the shader, no geometry under the sidewalk), lit warm at night;
  shelters and newsstands light the sidewalk around them at night.
- Small pieces are gone by about 260 m, large ones by about 580 m (low
  preset: 90 and 300 m; medium: 220 and 500 m). No shadows: they cost 3-11%
  of the frame rate for little to see.
- Cost: full-detail tiles +3.4 MB (1,215 MB); about 10 more draw calls in
  busy views, about 4% of the uncapped frame rate (0.08 ms a frame); every
  view still at the 145 FPS cap, day and night.
- Still to do: which end of a subway stair is open (the data doesn't say,
  so every stair opens the same way along its curb); wave bike racks are
  drawn as U racks.

**Parked cars and traffic (in progress):**
- Data (`tools/citygen/traffic.py`, from the street centerlines): driving
  lanes for every street and at-grade highway, following the paint (the
  same lane count and width as the dashed lines, keeping right of the
  center line), from where they leave an intersection to their stop line,
  with their intersections' ids (shared across tiles, so lanes link up),
  speed limit (25 mph streets, 40 mph highways) and signal phase, in a new
  tile surface (format v7): 178,574 lanes.
- Coordinated signals: each signalized intersection starts its 60 s cycle
  somewhere else, and approaches within 45 degrees of its widest street go
  green while the others are red, half a cycle apart; the poles carry their
  phase, so the lights and the cars agree.
- Parked cars where the data has parking lanes (2: both curbs, 1: the
  right-hand curb), short of crosswalks, 15 feet clear of hydrants (the
  law) and clear of bus stops, out of the travel lanes; a mix of sedans,
  SUVs, hatchbacks, minivans, pickups, vans, a few taxis and box trucks, in
  real cars' colors; new prop type 15: 1.1 million cars.
- Cost so far: full-detail tiles +35 MB (1,249 MB).
- Cars (`PropMeshes.car()`, `shaders/car.gdshader`): one 128-triangle
  mesh for nine models (sedan, hatchback, SUV, minivan, pickup, delivery
  van, yellow taxi with its roof sign, box truck, MTA bus), shaped per model
  by the shader from a table of proportions; toon paint in 12 real-car
  colors, tinted glass, painted-on lights, grille, plates and door seams,
  a contact shadow; at night headlights, taillights, brake lights and
  blinkers from per-car flags. Parked cars are one MultiMesh per near tile
  (no shadows: they'd cost 20-30 draw calls), shrinking away by 460 m
  (medium 320 m, low 170 m); street lights light them at night.
- `scripts/world/traffic_signals.gd` (TrafficSignals) is the one clock and
  timing (60 s: green 43%, yellow 5%, 1.2 s all-red at each switch, WALK for
  18% then the flashing hand) that the signal shader (through the
  `signal_clock` shader global) and the traffic agree on; phases are exact
  1024ths so the GPU's half floats hold them.
- Moving traffic (`scripts/world/traffic.gd`, lane graph in
  `traffic_lanes.gd`): cars drive the lanes at 82-97% of the limit, keep
  their distance (also across intersections), stop at red and at yellow
  when they can, never enter an intersection without room beyond it, and
  drive curves between lanes through intersections, reserving them so
  crossing paths are never used at once. Mostly straight on, right turns
  from the right lane and left from the left, blinkers before turns,
  U-turns only at dead ends. Without a signal the wider street has the
  right of way. Signals along a street are timed as a green wave for
  10 m/s. Cars stop for heroes, thugs (down or up) and pedestrians 25 m
  ahead. They appear out of sight (or grow in far away) and leave beyond
  360 m; 120 cars on high (medium 60, low 25), a third of them yellow cabs
  in Manhattan below 110th Street, 2.5% buses. One MultiMesh for all of
  them, plus headlight and taillight glows at night (one more draw call).
  Script time about 0.25 ms a frame (driving steps at 30 Hz, far and
  behind-the-camera cars redrawn less often).

**Trees, parks and sky after the reference check (done):**
- Street tree crowns clear a truck (at least 3.4 m up, 40% of the height
  on big trees) and are open clumps that differ per tree, with gaps up
  close; lighter greens; small flowering trees shorter, Callery pears
  teardrop-shaped.
- Woods past the tree distance show round sunlit crowns in the trees'
  colors, and at a slant trees hide the ground behind them, so Central Park
  reads as canopy from Top of the Rock.
- A deeper blue sky with a horizon haze band; fog 0.0001 on high (medium
  0.00013, low 0.00016) with a warm tint toward the sun.
- `?weather=overcast`: a grey deck, soft light, faint shadows, grey water
  and fog; dusk and night follow. Same draw calls and triangles.

**Landmarks, first batch (done):**
- `tools/citygen/landmarks.py` builds eight landmarks by hand, at their real
  dimensions, in place of their data buildings (by BIN):
  - the Empire State: setbacks, the 86th-floor deck, the crown's steps, the
    mooring mast with its four wings, the antenna to 443.2 m;
  - Chrysler: seven tiers of Nirosta arches with triangular windows, the
    eagles, the spire to 318.9 m;
  - One World Trade Center: glass-fin podium, eight triangles tapering to a
    square turned 45 degrees at 417 m, the spire to 541.3 m;
  - the Flatiron; the Woolworth (copper pyramid, turrets, lantern); Grand
    Central (three great windows, the Glory of Commerce, the clock showing
    the game's time); 30 Rock;
  - the Statue of Liberty: Fort Wood's star, Hunt's pedestal with its
    loggias, a low-poly statue facing south-east (robe, raised torch,
    seven-rayed crown, tablet).
- Setbacks come from the city's 3-D model, cut into terraces; crowns, masts
  and spires from published heights. They're baked into each tile's
  buildings surface at all three detail levels: no extra draw calls, and
  collision up close (you can land on the Empire State's antenna).
- Landmark materials (archetype ids 16 and up) get their own paint in the
  building shader: limestone piers with aluminum spandrels, terracotta,
  curtain walls, copper, granite, gold. At night the Empire State's tower
  lights shine from the 72nd floor up (colors set by uniforms), Chrysler's
  triangles glow, and the statue is floodlit with a blazing torch.
- Cost: 9,160 / 5,141 / 3,022 triangles (near / mid / far); tiles 70 kB
  smaller in total.
- Next: Liberty Island's lawns (federal land, missing from the parks data),
  more detail (the statue's face and drape, gargoyles, crown fins), and
  more landmarks: the Guggenheim, the Unisphere, the Public Library, St.
  Patrick's, Citigroup Center, the Met, the UN Secretariat, the Hearst
  Tower, 432 Park, the Vessel and Edge, the Oculus, the Wonder Wheel and
  Parachute Jump, Yankee Stadium; the Brooklyn and Manhattan Bridges.

**Sound (done; added 2026-10-15 at the user's request):**
- The hero: footsteps on the run animation's foot contacts (grass, boards,
  concrete), super speed's wind and zoom, jumps and the super jump's
  charge and boom, landings by fall speed, rushing air when flying,
  falling, swinging or diving, web thwips, creaks and swing whooshes,
  punches, dives, hits, splashes. Fights: hits, grunts, shouts, knockdowns,
  bodies landing; fleeing pedestrians scream now and then.
- The city (`scripts/audio/city_ambience.gd`): eight looping beds (day and
  night streets, the far hum up high, the Times Square crowd, birds by day
  and crickets at night in green areas, waves near water, wind up high)
  crossfading with the time of day and with where you are, from a 64 m
  soundscape map made from the land cover map; horns, far sirens, bird
  calls and dogs around you. The nearest 4 moving cars get engine loops
  pitched by speed, and cars held up by someone in the road honk.
- Positional in co-op; buses Master, SFX, Ambience and UI; N or the touch
  UI's speaker button mutes, remembered between visits (`?mute=1|0`,
  `?audio=0` leaves sound out). Nothing plays before the first click, tap or
  key (browsers' rule).
- 118 sounds, CC0 (Kenney packs, Freesound uploads checked one by one,
  listed in CREDITS.md) or synthesized; 1.6 MB with the soundscape map;
  `tools/audio/build_sounds.py` rebuilds them. Cost: about 0.05-0.1 ms a
  frame; in the browser 25-60 MB of decoded samples (Godot's web build keeps
  them as float at the mix rate, set to 32 kHz on the web to save a third).

Groundwork: streamed imagery in GPU-compressed formats (Godot 4.7 can load
DDS/KTX at runtime), instancing and LOD for props, a multi-threaded web build
for background decoding, and quality presets for weaker laptops.

**Decisions to make before step 6:**
- Whether the Mac and Windows versions (step 9) get extra looks from
  Godot's Forward+ renderer (ambient occlusion, reflections, volumetric fog,
  which WebGL lacks), or match the browser exactly.
- Budget for landmark models (buy/commission vs. free and self-made).
- How large the browser download may grow.

## 7. Phones and tablets (done in emulation; real phones to check)

Added 2026-10-15 at the user's request: the game should be playable on a
phone, in the phone's browser, at https://nycheroes.party.

- **Touch controls** (`scripts/ui/touch_controls.gd`, drawn in code): a
  floating stick on the left 42% of the screen (it follows the thumb past
  its rim; walking speed follows how far it's pushed), dragging anywhere
  else turns the camera, and buttons on the right: PUNCH (DIVE in the air),
  JUMP (hold for a super jump; UP while flying), DOWN (flying), WEB (hold),
  FLY, SPEED (a toggle, off 0.8 s after the stick is let go), CO-OP and
  fullscreen. Holding WEB or JUMP and sliding also turns the camera. They
  press the same input actions as the keyboard, so the hero is unchanged.
  The UI is measured in CSS pixels, so it's the same physical size on
  every phone.
- **Detection** (`scripts/util/device.gd`): on when the browser's main
  pointer is a finger, or at the first real touch; `?touch=1` / `?touch=0`
  force it. Off on desktop and in headless tests.
- **Co-op on a phone:** a Close button, 44 px controls, and a real HTML
  text box over the room-code field so the phone's keyboard comes up
  (`scripts/ui/web_text_field.gd`; Godot's experimental virtual keyboard
  doesn't work on iOS).
- **The page** (the export's head include): covers the notch, no zoom,
  scrolling, pull-to-refresh, selection or long-press menu; a "turn your
  phone sideways" overlay in portrait; fullscreen and landscape lock on the
  first tap where browsers allow it (iPhones can't; the overlay suggests
  Add to Home Screen, which runs without browser bars).
- **Quality presets** (`scripts/util/quality.gd`; `?quality=low|medium|high`,
  else phones low, tablets medium, computers high):

  | | low | medium | high |
  |---|---|---|---|
  | 3-D resolution | 540 lines | 720 lines | full |
  | MSAA | off | 2x | 4x |
  | Sun shadows | off | 2 splits, 300 m | 4 splits, 1500 m |
  | Tree shadows | off | off | on |
  | Load distances (m) | 350 / 800 / 7000 | 500 / 1100 / 12000 | 700 / 1500 / 30000 |
  | Pedestrians, gangs | 12, 1 | 24, 2 | 45, 2 |

  Denser fog on low and medium hides where the city stops. Measured in
  Chrome at Times Square (the worst spot) with a 3x phone screen: about
  0.75 GB for the whole tab on low (iOS Safari kills tabs at about
  1-1.5 GB); the canopy map was then cut to 16 m pixels, which saves about
  100 MB more.
- **Low and medium were slow** (a quarter of high's frame rate in Chrome on
  Windows): after drawing the smaller 3-D image, Godot copies its depth and
  stencil up to the full-size screen, and ANGLE stretches stencil on the
  CPU. `quality.gd` leaves stencil out of stretched copies (nothing reads
  it), which took low at Times Square from about 100 to about 320 FPS
  uncapped, faster than high. Unmeasured on real phones' browsers.
- **Tested** with Chrome's phone emulation and scripted multi-touch
  (moving while looking, super speed, jumps, swinging, flying, punching and
  diving, typing a room code) on 844x390 and 667x375 screens, with notch
  insets; desktop unchanged.
- **Still to check on real phones:** frame rate and heat on low (and
  whether tablets should get medium), whether iOS Safari keeps the tab
  alive, fullscreen and landscape lock on Android, Add to Home Screen on
  iPhone, the keyboard for room codes, notch and home-bar spacing, how the
  stick, look speed and buttons feel, "Copy link" on iOS, and whether edge
  swipes (back gestures) leave the game. `?stats` shows FPS on a phone.

## 8. Overpasses and missing bridges (done)

Comes after step 6 because it needs step 6's real ground heights.

- **Overpasses** (`tools/citygen/overpasses.py`): raised roads from the
  street centerlines' level codes (13 street level, 17 one level up, 21
  two, 25 three), each level 7 m above the low ground around them (5 m
  clearance under a 2 m deck). They ramp between the levels at their ends
  and never dip below the ground; carriageways and ramps at one level merge
  into one deck. Bridge outlines on land give viaducts their true edges
  (the Gowanus, the Major Deegan). Outlines without a raised road (rail
  bridges over streets, streets over rail cuts and sunken highways) span
  between the ground at their ends and rise 7 m over streets passing
  under. The city's elevation model is bare earth with bridges removed, so
  it gives only the ground. 543 raised-road decks (about 490 km), 355 other
  decks.
- **Two levels of road:** decks have bents every 36 m that stand in the
  medians of streets below or beside their lanes, parapets, lamps, and
  collision (you can land on them, run under them, swing from them). Low
  decks get abutment walls. On streets that cross dips on decks, the paint,
  lanes and props ride on the deck; nothing pokes up through a deck
  overhead.
- **Driving lanes and paint on decks:** same lanes format, linked to the
  streets through shared node ids, including street-level ramps and
  bridges, so traffic uses them.
- **Missing bridges:** the Kosciuszko (a pair of single-tower cable-stayed
  spans, towers on the Queens bank); City Island, Macombs Dam and Cropsey
  Avenue bridges now built; 21 small creek crossings the data lacks.
- **Towers** where they really stand (OpenStreetMap's bridge supports, each
  pair within a few meters of the published main span): the Verrazzano,
  Brooklyn, Manhattan, Williamsburg, Throgs Neck and Bronx-Whitestone; the
  RFK's suspension span over Hell Gate; the Queensboro's four cantilever
  towers with truss chords.
- **Cost:** near tiles about +25 MB (+2%), mid +7 MB, far +1.8 MB; 2-12%
  more draw calls in viaduct views.
- **Still to do:** the roadbed drawn on the ground under viaducts, elevated
  subway lines, rail and pedestrian bridges over water (Hell Gate, the High
  Bridge), sunken roads (the triple cantilever), walking lanes on decks,
  signal phases where ramps meet streets; tall viaducts come out lower
  than real (7 m per level).

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
- **3-D below screen resolution** in the Compatibility renderer ends with a
  stretched depth+stencil copy; on ANGLE/D3D11 the stencil part runs on the
  CPU and stalls every frame. `Quality.STRETCHED_BLIT_FIX` drops the
  stencil from stretched copies.
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
  `prepare.py` or re-downloading. To try a change on a few tiles, copy a
  full build somewhere and run `build_tiles.py --out <copy>/nyc --only
  lod0:0,-1 lod1:0,-1 ...` (about 2 minutes: it rebuilds the bridges and
  those tiles and updates the copy's manifest), then serve the copy as
  `tiles/`. In a git worktree (no `data/`), set `NYC_DATA_DIR` to the main
  checkout's `data` folder for the tools, and run the game or tests with
  `-- --tiles=<dir>`.
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
  arrives brotli-compressed (9.6 MB). Tile URLs carry the build's id (from
  the manifest), and a tile that arrives broken or stale (an edge cache
  just after a deploy) is fetched again, past any cache, after 1.5 s and
  3 s. Co-op relay: TURN key "nycheroes-coop" in the Worker secrets
  `TURN_KEY_ID` / `TURN_KEY_API_TOKEN` (for `wrangler dev`, in
  `tools/cloudflare/.dev.vars`, gitignored); $0.05/GB after 1,000 GB free.
- Tests (headless): `godot --headless --path . res://tests/hero_moves_test.tscn`,
  `res://tests/combat_test.tscn`, `res://tests/streaming_test.tscn`,
  `res://tests/coop_test.tscn`, `res://tests/audio_test.tscn` and
  `res://tests/traffic_test.tscn` (75 s of
  midtown traffic: no red light run, no overlaps, cars stop for the hero,
  and leave with their tiles).
- Launch options (URL or `-- --name=value` on desktop): `?cam=x,y,z,yaw,pitch`
  free camera, `?spawn=x,y,z,yaw` hero start, `?stats` console stats,
  `?peds=N`, `?gangs=N`, `?traffic=N` (0: none), `?demo` / `?demo=fight` scripted tours for videos,
  `?host` / `?join=CODE` co-op, `?signal=wss://...` signaling server
  (default: the page's host, port 8070), `?relay=1` co-op only through the
  TURN relay (testing), `?weather=overcast`, `?fog_scatter=` (sun tint of
  the fog), `?tree_shadows=0` trees without shadows,
  `--tiles=DIR` (desktop and tests) read the city from a tile copy.
