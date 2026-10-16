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
| 6 | Realism from open data | In progress (real shape, facades, trees, water towers, paint, roofs, night, furniture, cars and traffic, facade materials and stoops, ground details, first landmarks, landmarks in stone, waterfront landmarks, sound done) |
| 7 | Phones and tablets | Done in emulation; real phones to check |
| 8 | Overpasses and missing bridges | Done (raised roads, the Kosciuszko, real tower positions, elevated railways and their trains) |
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
- Pedestrians wear everyday clothes (reference improvement 17): mostly dark
  coats and jeans, some bright tops, a few suits, skirts and work clothes,
  with varied skin and hair. `shaders/npc.gdshader` paints the mannequin in
  bands (shoes, trousers or a skirt, a shirt or coat, skin, hair) cut on
  the rest pose, which `NpcLook` writes into the mesh's UVs, so poses and
  ragdolls keep their clothes. Thugs wear their gang's dark color with its
  bright one on the joints, the same in every co-op game. One material per
  character (instance uniforms would reserve 16 vec4s each in a uniform
  buffer of 1024 on some GPUs); same draw calls, 0.1-0.2 s to compile.
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
  `build_tiles.py` builds tiles on all cores (about 4 minutes then; now
  about 12 with 20 workers: each holds the whole city, about 3.5 GB, so the
  default count is what free memory allows). Three levels
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
- **Connections:** browsers connect directly over WebRTC, every player to
  every other (a full mesh, so nobody's traffic depends on the host's
  connection). A small signaling server (`tools/signaling`, Node.js) only
  introduces players by room code; game traffic never goes through it. It
  also hands out the STUN/TURN servers to use (`ICE_SERVERS`), so a relay can
  be added without rebuilding the game.
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
- **Tested:** `tests/coop_test.tscn` runs a host and a second game through
  the signaling server and over ENet (desktop has no WebRTC) and checks
  positions, thugs showing up and fighting both ways, and players far apart.
  Two headless Chrome instances also connected over WebRTC through the
  signaling server.
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
- **Host leaving (2026-10-15):** the game goes on without the host. The
  signaling server names the player who has been in the room longest the new
  host (passing over any who stopped pinging: a dead connection, or a game
  paused in a background tab) and tells everyone; the room keeps its code,
  so friends can still join (with the lowest free player number). The new
  host's game turns its copies of the thugs into thugs it runs, and the
  other players hand over their copies (thugs near them it never heard of),
  so fights carry on with the same thugs, none doubled; a thug the new host
  has no ground for yet waits until it loads. Each host numbers new thugs in
  its own series, above every number it has seen. Everyone sees "Player 2
  is now the host". Games ping the signaling server every 10 s and tell it
  when they lose touch with a player; one that has also stopped pinging for
  25 s is dropped, so a host whose network died is replaced in about half a
  minute. If only the connection between two players broke (both still
  pinging), the one with the lower number connects again through the
  server. The menu shows the room code, the link and who's hosting to
  everyone; "Stop hosting" became "Leave game".
  `tests/coop_migration_test.tscn` runs four games: the host's game is
  killed, the next player takes over the same thugs (which hurt and are
  beaten by the others), a broken connection between two players comes
  back, a fourth joins with the same code, a player leaves, and a host whose
  game stops answering is replaced. `tools/signaling/protocol_check.mjs`
  checks either signaling server (local, or the Durable Object). In four
  headless Chrome pages over WebRTC (signaling by the Durable Object, run
  locally), the host's tab closed, the next player took over its thugs
  within a quarter second, and a fourth joined with the same code.
- **Signaling restarts (2026-10-16):** a game the signaling server drops (a
  Worker deploy restarts the Durable Object and closes every socket) plays
  on over its own connections and comes back: it connects again (after half
  a second, then less often, up to every 5 s) and rejoins its room as the
  same player, with a key the server gave it, saying who is in the room, in
  the order they came, and who hosts. A server that lost the room rebuilds
  it from the first player back and keeps the others' numbers (and the
  host's role) until they're back, in Durable Object storage: a friend
  joining meanwhile gets a free number, and the players coming back later
  connect to them. One still away after 10 s whom another player has lost
  touch with is taken to have left (handing on the host's role if it had
  it). A player whose own socket dropped (so the server let it go) comes
  back the same way and the others connect to it again; a host the server
  let go finds the next player hosting and plays on in their game. Players
  coming back get fresh TURN credentials from the new Durable Object
  (shared as before); connections made earlier keep theirs. The menu and
  the HUD's co-op line say nothing for 5 s, then a quiet "reconnecting...".
  Games from before this still work with the new server (on a restart they
  leave their game, as before). `tests/coop_reconnect_test.tscn` runs four
  games: the server is killed mid-game and the games play on (positions, a
  fight, the same room, number and host); it starts again and two come back
  while the host holds off; a fourth joins with the code before the host is
  back and gets number 4; the host comes back and connects to it; the
  host's own socket drops (the next player takes over, and it comes back as
  a player); the new host's game closes and the next in line takes over.
  `protocol_check.mjs` covers rebuilt rooms (two players back at once, a
  friend joining before the host, the host's place and the players' order
  kept, a stale socket replaced, a stranger turned away, a host that never
  comes back) and, with `--restart`, a real restart; both servers pass, the
  Durable Object restarted under `wrangler dev`. In three headless Chrome
  pages over WebRTC (signaling by the Durable Object under `wrangler dev`,
  restarted and down for about 10 s), no connection between players dropped:
  the HUD read "3 players · reconnecting..." meanwhile, all three were back
  in the room within 13 s of losing it, a fourth joined with the code, and
  closing the host's tab passed its role on in a fifth of a second.

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
5. **Landmarks:** about 25 hand-made iconic buildings and bridges (two
   batches, 22 buildings done, and four bridges, below; self-made and free,
   decided 2026-10-15).
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
  them keep the model's shape (the Dime Savings Bank). About 3,900
  triangles up close in all. (Marble Collegiate Church, whose footprint
  measures its spire's tip, 65 m, was a special case drawing the model's
  47 m church; churches.py draws it now, below.) Some model surfaces face the wrong way;
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
  real arc on April 6 (through azimuth 235°, elevation 42° at 15:30; sunset
  about 19:25; `?date=MM-DD` picks another day's, below), a full moon takes
  over the light at night, and the sky, fog,
  ambient light and exposure blend from day through dusk to night. Shader
  globals (`night`, `dusk`, `city_lights`, `clock_hours`, the street light
  map) reach every city shader through `shaders/night.gdshaderinc`; with
  them at 0, the day looks exactly as before.
- **T** steps to the next of dawn, day, dusk and night; `?time=HH:MM` sets
  the clock, `?daylength=MINUTES` runs it. `?date=MM-DD` (or `YYYY-MM-DD`)
  puts the sun on New York's arc that day, on the city's clock (daylight
  saving time in summer; the Astronomical Almanac's low-precision sun, good
  to a minute or so), and moves T's dawn and dusk with sunrise and sunset:
  `?date=12-21` sets at 16:32, `?date=06-21` at 20:31.
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

**Times Square, closer to the real one (done; reference improvement 11):**
- Bigger screens fitted to the walls: sign walls at least 6 m wide measure
  uv.x from their own corner (`build_tiles.py` SIGN_FACE_MIN), and the
  shader finds each face's width from the moments of uv.x (the same trick as
  wall tops), so it lays the screens out across each face: columns 13-30 m
  wide (per building), tiers 9-22 m high, a tall banner at one end of some
  faces, a few tiers split in two. They sit in black cladding with dark gaps
  of 0.9-2 m and a thin bezel, a strip of cladding at the corners. Narrow
  facets (rounded corners) keep the old layout that runs on along the
  building. Neon tubes and chasing bulbs are rarer (today's walls are LED).
- Ads drawn like photos, softly lit, on about half the wide screens:
  cartoon portraits (head and shoulders in studio light, blinking, the
  brand's word beside them), landscapes (sky, a low sun, hazy ridges, a
  glinting shore, slowly panning) and film posters (a dark figure against a
  glow, light rays, a glowing title). Still no real brands.
- One Times Square is a stack of screens 5-14 m high from above its shops
  to the top of both its parts (68 and 102 m): `tools/citygen/times_square.py`
  lists it by BIN (SIGN_TOWERS), and its sign walls carry SIGN_TOWER in the
  FRONT_PART field (SIGNS faces never have stoops, so the field is free
  there). About two in three of the other tall sign buildings carry screens
  higher up too: a row 8-14 m high near the top, or a stack 24-60 m tall up
  one edge of a face.
- The TKTS booth in Father Duffy Square: the data's 4.9 m box (BIN 1085637)
  becomes 27 red glass steps up to 4.9 m, facing south over the square, with
  glass sides (each step's edge glows through) and the ticket windows at the
  back. Glossy treads, risers glowing red at night (`tkts_glow`); you can
  climb them, and three walking lanes run up them.
- Granite benches (8 by 0.9 m, 0.45 m high; 17 of them) in lines down the
  middle of the plazas, clear of street furniture and trees.
- A drum of screens 11 m across and 14 m high around the corner of 47th
  Street and Seventh Avenue, over the TKTS steps, showing an invented cola
  brand (a white ribbon over red, rising bubbles), like the curved cola
  signs that have hung over the north end of the square.
- Walls on the plazas count as street fronts in the sign district
  (`times_square.faces_plaza()`): Broadway's roadbed from 42nd to 47th Street
  is pavement in the data, so walls on it had neither shop fronts nor
  billboards (One Times Square's long east face among them).
- A thicker crowd: walking lanes across the plazas every 3 m (out to 22 m
  from the curb) beside the curbside ones; within 60 m of the sign district,
  `crowd_manager.gd` keeps `plaza_crowd` (1.5) times as many pedestrians (68
  on high, 36 on medium, 18 on low), three in four newcomers on lanes in the
  district, so the plazas fill up. Pedestrians more than 25 m from the camera
  take a new pose 12 times a second (each at its own moment) instead of every
  frame; each new pose is a skinning pass (see SkinWarmup).
- All of it is in the buildings surface and the building shader's sign
  code (`plaza_piece()` paints the steps, benches and drum); faces carry
  SIGNS plus a part (`times_square.py`). The ground is unchanged.
- Cost: no extra draw calls for the screens, steps, benches and drum (303
  and 276 in the two Times Square test views without pedestrians, before and
  after); tiles +23 kB (+0.4%) in the 8 tiles that change (the steps are 218
  triangles, the drum 164, the benches 170). Each pedestrian costs about
  50 µs a frame (Chrome, uncapped): with 68 in the district the test views
  ran at 160 and 152 FPS, against 174 and 216 with 33 (twice the crowd, 90,
  dropped below the 145 FPS cap, hence 1.5). The pose rate saves about 7%
  at 90 pedestrians. The building shader now inlines `facade()` once
  instead of twice (sign walls paint their facade only where the screens
  leave it showing), so it isn't bigger to compile than before; its first
  compile in Chrome on Windows was already slow (1-4 minutes on a busy
  machine) before this.

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

**Shop signs, sidewalk sheds, bike docks and plaza furniture (done;
reference round 3's 23, 24 and 31):**
- Shop fronts (`props.shop_fronts()`): the street walls of every building
  with shops (PLUTO's retail area, or a store; not in Times Square's sign
  district), as drawn (the 3-D model's walls where it draws the building),
  are split into shops 5-8.5 m wide (7-12 m in towers). Each gets, over the
  sign band the building shader paints:
  - a sign across the whole shop: a painted board 0.8-1.3 m tall, a light
    box (lit from inside, softly by day and brightly at night), or channel
    letters (cut out, standing off a dark or pale fascia; lit at night);
  - on 20-45% of shops an awning under it (cloth with a valance, ribbed
    aluminum, or a quarter-round dome), reaching 0.9-1.5 m out but never
    closer than 0.7 m to the curb, its lowest edge at least 2.2 m up; cloth
    ones and domes carry the shop's name;
  - on 15-35% a blade sign at one end, by the next floor, its name up the
    panel;
  - on low buildings (2-6 floors) with offices (PLUTO's office area, 17,200
    of the 85,000 shop buildings), boards on the next floor over 55% of
    shops (dentists, tax services, dance studios), and over 15% on
    commercial streets without; 6% of shops there hang a vinyl banner
    (GRAND OPENING, SE RENTA).
  Commercial streets (at least 12 shop buildings within 60 m: 34,800 of
  them) get the most signs, light boxes and awnings; towers and newer offices
  mostly channel letters; lofts and warehouses half as many signs. Walls with
  another building 0.5 or 1.5 m in front get nothing: they're party walls
  that the facade code marks as street fronts because a street lies beyond
  the neighbor (30-50% of shop walls in dense blocks; signs and awnings
  there poked out of the neighbor, mirrored).
- Names: 64 invented ones (no real brands: kinds of shops like PIZZA and
  FARMACIA, family and fancy names like Mama Rosa and LUCKY GARDEN, the
  upstairs businesses, banners), Spanish ones three times likelier in the
  Bronx, Brooklyn and Queens, set in four typefaces under the SIL Open Font
  License (Anton, Lilita One, Alfa Slab One, Pacifico) by
  `tools/citygen/sign_names.py` into one texture: a signed distance field
  (`assets/signs/sign_names.png`, 1024 x 2048, one channel, 465 kB in the
  download, 2.8 MB on the GPU with mipmaps), so letters stay crisp up close
  and get outlines for free; its bottom row of pixels holds each name's
  width, which the shader reads to fit the name to the sign. Colors come
  in schemes: a bold color with light letters, light with colored letters,
  dark with yellow or white, yellow with red; awnings in the shop's color, a
  third of them striped.
- Sidewalk sheds (`props.shed_sections()`): the Department of Buildings'
  permits (DOB NOW: Build, Approved Permits, work type Sidewalk Shed, issued
  and not expired or signed off on the day of the download: 7,869 on
  2026-10-16) put sheds on 6,585 buildings (by BIN, else the nearest building
  within 20 m). A shed runs along each street wall with at least 2 m of
  sidewalk, reaching to 0.5 m short of the curb (1.6-3.6 m), its deck
  3.0-3.5 m up, in sections of up to 3.2 m: plywood in 4 x 8 ft sheets
  painted hunter green (82%; white, black or blue), steel posts at both
  sides, a header beam with knee braces, a parapet with stenciled warnings,
  a white underside with a lamp every 3 m, lit by day and brighter at night,
  when they light the sidewalk (pools in the street light map). Shops behind
  a shed keep only their signs above it.
- The bike share's docks (`props.prepare_bike_docks()`): Citi Bike's 2,518
  stations from its public GBFS feed (Lyft's data license allows the data
  inside a product, not as a dataset of its own, and none of the system's
  names or marks: the bikes are a generic blue, with no logos). Each
  station's docks stand in a row along the nearest curb: in the parking lane
  where the station is in the street (1,115; parked cars keep clear), else on
  the sidewalk or plaza at least 2.4 m from the curb, the bikes toward the
  street; sections of four docks 0.8 m apart, each holding its own share of
  bikes (45-100%), a green light on each dock, the station's kiosk (map,
  screen, solar panel) at one end: 18,900 sections.
- Plaza furniture (`props.plaza_furniture()`) in the DOT's pedestrian
  plazas: planters every 7 m along edges by the street (long boxes or round
  tubs of shrubs and flowers), bistro tables with three chairs on a jittered
  4 m grid in seating areas (55% of 12 m squares), 30% under an umbrella
  (none in Times Square's sign district, whose tables stand bare), and a food
  kiosk in 60% of plazas of 900 m² or more; all 1.6 m from street
  furniture, trees and lamps.
- New prop types 17-23 (signs, awnings, shed sections, dock sections and
  kiosks, tables, planters, food kiosks; older game builds skip them),
  three MultiMeshes per near tile: shop fronts on one mesh
  (`PropMeshes.shop_fronts()`, 158 vertices for every shape) with
  `shaders/shop_sign.gdshader`; sheds on a small mesh of their own (140
  vertices: Manhattan tiles hold hundreds of sections, and every instance
  runs all its mesh's vertices) and docks with plaza furniture on another
  (604 vertices), both with `shaders/street_extras.gdshader`, laid out like
  the street furniture. Added to `street_furniture.gdshader` instead, they
  doubled its compile time (0.9 to 1.3-1.7 s: the D3D compiler's time grows
  with about the square of a shader's code), so they have a shader of their
  own (0.3-0.4 s). No shadows. Signs and awnings shrink away at 62% of the
  large furniture's distances (260-360 m on high), sheds at 78%, docks and
  tables with the small furniture: at the large furniture's they cost about
  0.5 ms a frame.
- Data: `fetch_data.py` fetches the shed permits (`sidewalk_sheds.json`) and
  the stations (`bike_stations.json`); `prepare.py` makes `shops.pkl`,
  `sheds.pkl` and `bike_docks.pkl`.
- Cost: tiles about +11 MB (+0.6% in 23 random near tiles: 130 signs and
  awnings, 24 shed sections and 11 dock sections a tile; +1.6% in the 25
  tiles around the five views, Midtown's up to +3%). Draw calls +5 to +14 in
  the five views. Uncapped on the dev machine (1600x900, back and forth with
  master): within the noise at Roosevelt Avenue, the Flatiron, Fifth Avenue
  and DUMBO (305 to 303, 303 to 308, 314 to 320, 325 to 312 FPS), Times
  Square 311 to 291 (+0.2 ms). Shader compile time at Times Square:
  shop_sign.gdshader 0.2-0.3 s, street_extras.gdshader 0.3-0.5 s, 12 more
  programs (109 to 121); ready after 24-25 s before, 21.5-22.6 s after (the
  noise is building.gdshader's). Download +0.5 MB (index.pck, the names).
- Still to do: fewer continuous storefronts on lofts (round 3's 23 asked
  for it; it's in `facades.py` and the building shader); the painted sign
  band shows where a shop has no sign or channel letters.

**Utility poles and overhead wires (done; reference round 3's 30):**
- Where (`tools/citygen/poles.py`): the city publishes no pole positions, so
  they're inferred. Streets (centerline segments of up to 4 lanes and 20 m
  of roadbed) lined with houses: of the buildings within 22 m of the curb (at
  least 4), 60% are houses and rowhouses up to 13 m tall (PLUTO's classes A
  and B, and C walk-ups under four floors) and at most 10% are over 16 m; or
  low-rise shopping streets among them (a quarter houses, three quarters
  houses and low shop buildings). In the Bronx, Brooklyn, Queens and Staten
  Island, but not within 4.5 km of Brooklyn Borough Hall (downtown and the
  brownstone neighborhoods, whose lines run underground, like Manhattan's):
  45,363 of 95,285 street segments.
- Lines: segments meeting within 35 degrees of straight on join into lines
  along their streets (16,241), each with its poles on one side all the way
  (where the houses are, if one side has 2.5 times the other's, else either),
  so the wires run on across the intersections.
- Poles (prop type 24): evenly along each stretch between the streets that
  join on the poles' side, about 40 m apart (give or take 2 m), 3 m back from
  a crossing street's curb, 0.6 m onto the sidewalk from the curb (a ray from
  the centerline out through the road surface finds it), stepped 1.6 m along
  the curb out of a street tree's trunk: 161,729 creosoted poles, 10.5-12 m,
  with a crossarm on two braces and its insulators, a pin on the top for a
  third wire on 40% of the lines (three-phase), brackets for the secondary
  and the phone cable, and a transformer can on 18%.
- Street lights: a cobra-head on 90% of the poles (145,579), its arm 2.2 m
  long, 3 m under the pole's top: a street light whose own pole folds away
  (uv.y 1). The curb lamps of the streets the poles line go (those whose
  nearest centerline is one), so those streets are lit from one side, as in
  Queens: in the 29 sample tiles with poles 3,403 curb lamps gave way to
  2,020 on poles (6,260 lamps to 4,877; Staten Island's house tiles about 40%
  fewer), about 245,000 citywide; their streets are darker at night.
- Wires (prop type 25, one prop a span): a span from each pole to the next
  along its line, up to 62 m (143,190): bare primaries on the crossarm's ends
  (and the pin), the black secondary 1.6 m under the top, phone and cable TV
  4.1 and 4.6 m under it; a service drop from the nearest pole within 36 m to
  each house and low shop building (at least 35 m², the wall it reaches
  within 14 m of a street, under the eaves of a pitched roof or 1.4 m under a
  flat one's, not through another building: 613,369), so drops cross the
  street to the houses opposite, as in the Ridgewood photo; and a down guy
  from each line's end poles to an anchor 3.5 m further out along the
  sidewalk (17,337), in a yellow guard.
- Drawing: poles on a mesh of their own (`PropMeshes.utility_pole()`, 320
  vertices) drawn by the street lights' shader, shrinking away with the
  lamps (450-650 m); wires on one more MultiMesh per near tile
  (`PropMeshes.wires()`: six strips of 8 quads, 108 vertices; a drop or guy
  folds five away), whose shader (`shaders/wires.gdshader`) hangs each wire
  in a parabola between the span's ends (the near pole's foot and height, the
  span's length and yaw, the latter to a tenth of a milliradian in the tiles,
  and how far the far end's top is above) and turns it into a ribbon facing
  the camera, at least a pixel wide, thinning out and gone at half the large
  furniture's distances (210-290 m on high, 180-250 on medium, 110-150 on
  low). Unshaded, no shadows, no collision: webs and flight pass through
  them (and the poles, like every prop). The mesh's box holds a span
  whichever way it runs.
- Data: `prepare.py` makes `poles.pkl` (27 MB, about 70 s).
- Cost: near tiles +1.1% where there are poles (24 tiles in Ridgewood, the
  Bronx and Staten Island; +0.1-0.4% around the Grand Concourse, +0.8% over
  all 36 sample tiles), about +13 MB citywide (scaled from the sample). Draw
  calls +2 per near tile with poles (the poles everywhere the lamps draw, the
  wires within 660 m of a tile's center): +9-10 in street views in
  Ridgewood, the Bronx and Staten Island, +6 at the Grand Concourse, +1 at
  St. George; triangles +0.12-0.36 M. Uncapped frame rate (1600x900, back and
  forth with master on a busy machine): within the noise in all seven views.
  Shader compile time at a Ridgewood pole: street_light.gdshader 0.2 s before
  and after, wires.gdshader 0.1 s, 6 more programs (139 to 145); ready after
  32.9 and 37.2 s before, 33.0 and 33.2 s after. Download +10 kB (index.pck).
- Still to do: wires from house to house along the fronts (the Ridgewood
  photo's), back-lot pole lines (common in Queens and Staten Island), and
  trimming street trees round the wires.

**Ground details (done):**
- Planted medians and malls (`tools/citygen/ground_details.py`): of the
  city's 8,048 raised medians (Planimetric Database), 3,727 are planted:
  Parks Department malls, parkways and Greenstreets, medians the land cover
  map shows as grass, and curb-lined medians along the Grand Concourse,
  Park Avenue (46th to 96th Street), Broadway (60th to 168th) and the
  Ocean, Eastern and Pelham Parkways. Curb-lined ones up to 9 m wide become
  shrub beds (new ground kind 20): a concrete edge, then clipped shrubs
  0.7 m high, a hedge around a lawn where there's room, with leafy clumps
  and stretches of flowers drawn by the ground shader (the shrubs' height
  in uv2.y wraps the leaves up their sides). Grass strips and highway
  medians are lawn; wide malls (the parkways') are lawn where the land
  cover has grass or trees, paved on their walks. Street trees on shrub
  beds stay under 7.5 m (Park Avenue's pears and hawthorns), narrow
  medians get no canopy trees, and no walking lanes run along medians.
- Parks the parks layer lacks, as lawn where the 2017 land cover map shows
  grass or trees (outlines smoothed; woods come from the canopy map as in
  any park): City Planning's Publicly Owned Waterfront parks not run by
  the Parks Department (Brooklyn Bridge Park, Hudson River Park, Battery
  Park City, the Statue of Liberty and Ellis Island, Governors Island,
  Gateway's units, Riverbank, Roberto Clemente, Gantry Plaza, East River
  and Shirley Chisholm State Parks, Roosevelt Island's), and the
  Planimetric Open Space's cemeteries (Green-Wood, Calvary, Woodlawn...)
  and recreation areas: 6,383 lawns, 3,425 ha. Paths in the waterfront
  parks get post-top lamps.
- Special pavements: dark concrete pavers in the DOT's 93 pedestrian
  plazas (Times Square, Herald Square, the Flatiron...), and Belgian block,
  with asphalt patches, on a list of streets in DUMBO and Vinegar Hill, the
  Meatpacking District, SoHo, Tribeca, the Financial District and the
  Seaport (ground kinds 21 and 22; the direction their rows run in uv2.y).
- Historic post-tops instead of cobra-heads along the Grand Concourse,
  Ocean and Eastern Parkways, Riverside Drive and Fifth Avenue along
  Central Park (`props.HISTORIC_LAMP_STREETS`, picked by the street
  centerline's names).
- Cost (random samples): near tiles +3.0% (109 tiles), mid +3.8% (20),
  far about +5% (tiles with new parks grow most: Governors Island's
  +68%); draw calls and triangles on screen unchanged.

**Parked cars and traffic (done):**
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
  right of way: the others wait while one of its cars is less than 4 s
  from the line (counting cars still on their way onto a short stretch of
  it), and give their way back to one that turns up while they can still
  stop; no car appears just short of a line it would have the right of way
  at while a car giving way crosses. Signals along a street are timed as a
  green wave for 10 m/s. Cars stop for heroes, thugs (down or up) and
  pedestrians 25 m ahead. They appear out of sight (or grow in far away)
  and leave beyond 360 m; 120 cars on high (medium 60, low 25), a third of
  them yellow cabs in Manhattan below 110th Street, 2.5% buses. One
  MultiMesh for all of them, plus headlight and taillight glows at night
  (one more draw call). Script time about 0.25 ms a frame (driving steps at
  30 Hz, far and behind-the-camera cars redrawn less often).

**Trees, parks and sky after the reference check (done):**
- Street tree crowns clear a truck (at least 3.4 m up, 40% of the height
  on big trees) and are open clumps that differ per tree, with gaps up
  close; lighter greens (darker again after the next check, below); small
  flowering trees shorter, Callery pears teardrop-shaped.
- Woods past the tree distance show round sunlit crowns painted on the
  ground in the trees' colors, and at a slant trees hide the ground behind
  them. From Top of the Rock that still read as lawn and paths (the next
  check): woods from afar are now clumps of crowns, below.
- A deeper blue sky with a horizon haze band; fog 0.0001 on high (medium
  0.00013, low 0.00016) with a warm tint toward the sun.
- `?weather=overcast`: a grey deck, soft light, faint shadows, grey water
  and fog; dusk and night follow. Same draw calls and triangles.

**Light at the ends of the day and in gray weather (done; reference improvement 18):**
- Shade: the toon ambient's ground bounce (what walls get half of) is a
  light gray instead of warm, so shade on light walls is a cool gray, not
  beige (the Guggenheim's shaded side #9B8F7F to #959086). The sky's share
  (streets, roofs) is unchanged. Bluer turned brownstone and marble gray in
  shade: the palettes count on some warmth there.
- Low sun: the dusk and dawn keyframes keep the zenith blue over a pale
  horizon, with the warm band under the sun (`dusk_band` 0.6) and peach
  clouds; the sun stays gold at full strength, the shade turns blue
  (`dusk_ambient`), the haze is a cool gray, and glass and water reflect
  blue overhead and the pale horizon instead of orange all round
  (TimeOfDay's `DUSK_MATERIALS`); exposure 1.25, AgX contrast 1.25. The
  warm light starts with the sun 20° up (was 30°). Before, the sky went
  mauve to the zenith and the whole city pink-gray.
- Overcast: a bright deck over darker, more contrasty streets: exposure 0.9,
  AgX contrast 1.3, less fill in the shade (ambient ×1.12, was ×1.45), a
  darker ground bounce, darker wall feet (canyon occlusion ×0.65), thinner
  fog (×1.3, was ×1.8). The Compatibility renderer clamps the 3-D buffer at
  1.0 before tone mapping, so no sky gets past what AgX makes of 1.0 (about
  #C5 at the day's contrast) however bright its colors; the overcast look
  lowers AgX white to 2.0, its minimum, which lifts the deck to #D8 and
  leaves mid-tones alone. The night keyframes set AgX contrast and white
  back, so the night is unchanged.
- Sun path: the default arc is New York's on April 6; `?date=MM-DD` (or
  `YYYY-MM-DD`) gives any day's (above, under Night).
- Measured against the photos (REFERENCE.md round 3's 18): at
  `time=19:00` totr_north's top of frame #948187 to #9AB1CC (the photo's
  blue #95B7CD), lower half 0.36 to 0.40 (0.42), contrast 0.14 to 0.17
  (0.21), warm share 0.70 to 0.41 (0.21); overcast, the deck #9B-#B4 to
  #CC-#D8 (#D4-#E1), lower half 0.50 to 0.42 (0.41), contrast 0.13 to 0.16
  (0.20); the clear day's means of 13 unchanged in value (0.40) and
  masonry saturation (0.24 to 0.23).
- Cost: values only (keyframes, uniform defaults, environment settings, and
  three material uniforms set once at the start): the compiled shaders are
  byte for byte the same (hashed), so compile time is unchanged.

**Woods from afar, darker street trees (done; reference round 3's 20 and
16's trees):**
- Why Central Park still read as lawn and paths from Top of the Rock: the
  woods were only painted on the ground. They did draw there, out to the
  park's north end, but from 280 m up the ground 1-4 km away is seen at
  4-15 degrees, so 8 m crowns are squeezed under a pixel along the view by
  about 1.5 km (sooner on medium and low, which draw fewer lines) and fade
  to their average: a flat green a little darker than the lawns (the park's
  pixels spread 0.023 in value, the photo's 0.11). Drives and paths are
  pavement and road, which woods don't cover, so they drew through; and flat
  ground has no tree mass to stand against the sky (Staten Island's hills
  from the ferry).
- Now woods past the trees are clumps of crowns that stand up: one for each
  16 m square of the land cover map (the canopy map's pixels) that is at
  least 15% canopy, in the middle of its canopy, as wide as that much canopy
  (1.3 times the side of a square of it: 7-23 m, so woods close over and
  lone trees stay small), as tall as canopy trees there (8-21 m), in the
  canopy trees' tones (no red-leaved clumps), conifers in their patches
  (`props.canopy_clumps()`, `LandCover.canopy_cells()`). Far tiles have one
  per 32 m square with at least 30% canopy (20-46 m wide). They're a new
  prop type (16) in tiles of every level, kept clear of decks overhead (mid
  and far tiles get a props surface with just these; older game builds skip
  the type): 1.21 million in near tiles, 1.21 million in mid, 0.21 million
  in far.
- Each tile's clumps are one more MultiMesh (`PropMeshes.canopy()`: one
  lumpy blob, 20 triangles, no trunk), drawn by the trees' shader, which grows
  them in between 600 and 800 m from the camera as the trees shrink away
  (650-850 m) and shades each clump's lower part as if in its neighbors'
  shade (`canopy_tint`, `canopy_shading`); no shadows. Near tiles' clumps
  draw once the tile's center is 240 m away, mid tiles' out to 6 km, far
  tiles' to 9 km; medium draws them to 4 km and not in far tiles, low not at
  all (only the ground's painted woods; `CityStreamer.set_canopy_ranges()`,
  from `Quality`).
- From Top of the Rock the park is now canopy edge to edge, with the
  reservoir, the lakes and the biggest lawns showing and the paths hidden;
  Staten Island's hills and St. George's slope have tree mass. The park's
  pixels spread 0.050 in value (0.023 before, the photo 0.11) and 0.21 of
  them sit on a strong edge (0.09; the photo 0.64). What's left is mostly
  haze: with `?fog=0.00003` the canopy measures (67, 86, 64), value 0.34,
  saturation 0.29, against the photo's (77, 104, 95), 0.42, 0.34 (round 3's
  25 is about the haze). Measured before the light change above (18).
- Street trees, and the woods with them, are darker, less saturated and a
  little cooler (`tree.gdshader`'s FOLIAGE and CONIFER, the ground shader's
  woods tones in step). Foliage in six street views (Flatiron, Park Slope,
  Grand Concourse, Guggenheim, Park and Fifth Avenues): saturation 0.77 to
  0.60, value 0.29 to 0.19 (the photos 0.44 and 0.18).
- Cost: tiles +55 MB (near 1,481 MB, +1.6%; mid 275 MB, +11%; far 39 MB,
  +13%, so about 4 MB more at the start). On the dev machine at 1920x1080,
  uncapped (back and forth with the build before): Top of the Rock, north,
  on high 276 to 302 draw calls, 3.1 to 3.8 million triangles, 364 to 338
  FPS (+0.2 ms a frame); medium 152 to 171 draw calls, 1.6 to 2.0 million,
  463 to 445 FPS (+0.1 ms); low unchanged (118 draw calls). Staten Island
  from 300 m, high: 175 to 198 draw calls, 3.0 to 3.9 million triangles,
  486 to 415 FPS (+0.35 ms); over Central Park from 350 m, 306 to 329,
  +0.5 ms. Still at the 145 FPS cap. The cost is the clumps' vertices, not
  their pixels (shrunk to nothing they cost the same), so they're one
  20-triangle blob: two blobs looked the same and cost twice as much.
  Shader compile time unchanged (tree.gdshader 0.3-0.4 s; the ground
  shader only changed values).

**Facade materials and rowhouse fronts (done):**
- Each masonry building has a wall material from the tax lot data
  (`facades.py`): brownstone, red, brown or buff brick, limestone, paint or
  siding, by borough, era and historic district. Brooklyn and Harlem rows
  are brownstone and limestone, Ridgewood's buff brick, DUMBO's warehouses
  deep red, prewar Manhattan limestone and cream; houses in a row share
  theirs, far blocks take their buildings' majority. Palettes were retuned
  against the reference photos: muted, weathered masonry and dark glass.
- Rowhouses and walk-ups have stoops (`tools/citygen/fronts.py`, near tiles
  only): steps up to the parlor floor between stone cheek walls, the front
  door on the landing, real geometry with collision, kept 4 m from the curb
  (so narrow sidewalks drop some); areaway walls and fences with a gate.
  Rows' and tenements' cornices are deep and bracketed.
- Cost: full-detail tiles +117 MB (+5.3 M triangles; stoops alone +78 MB),
  about 0.25 M more triangles per frame in brownstone blocks, same draw
  calls.

**Churches, and rowhouse fronts' second pass (done; reference round 3's 27
and 29):**
- Churches (`tools/citygen/churches.py`): the buildings on PLUTO class M1
  lots (church, synagogue, chapel) at least 120 m2 and 7 m, with at most
  three floors or tall ones (not a parish house or school on the lot):
  2,906. Built before 1945 they're Gothic (pointed arches; always where the
  footprint measures a spire above the 3-D model's tower) or Romanesque
  (round arches), in brownstone, gray stone, limestone, red or buff brick
  by era (those over 1,500 m2 and landmarks in stone); later ones modern
  brick. The prepared kinds and materials are `data/cache/churches.pkl`.
- Their shapes: the 3-D model's biggest level is the nave; if its outline
  fills most of its enclosing rectangle it gets a gable roof with the ridge
  at the level's height (the model's levels sit at about the ridge),
  48-58 degrees on Gothic churches (38-46 Romanesque, 24-34 modern) where
  the eaves stay at least 58% of the way up, else shallower, overhanging
  0.25 m, its walls drawn again up to it (gable ends to the ridge).
  Smaller parts rising 3 m above it are towers (517 churches): their tops
  get spires (octagonal and inset on square towers, with pinnacles at a
  square stage's corners on Gothic ones; low pyramid caps on 60% of
  Romanesque ones), 1.8-2.8 times the tower's width, or up to the
  footprint's height where that's above the model's (Marble Collegiate's
  65 m). Churches the model has as one flat level get the gable over their
  footprint. They're drawn this way at every level where they stand on
  their own (tall ones in mid and far tiles too), never get water towers,
  and keep the model even where the footprint is much taller (a spire's
  tip).
- `shaders/church.gdshader` paints them, from their own surface in each tile
  (CityTileDecoder.SURFACE_CHURCHES = 10, with collision): no floors;
  stained glass behind protective glazing in tall windows between
  buttresses, in stages up walls over 13 m or so, under a corbel table; a
  gable facing a street has wooden doors in a deep arch and a rose window
  (a long street wall, a door in its middle bay); towers rise in stages
  (string courses, a narrow window each) to a belfry with louvered openings,
  half with a clock under it keeping the game's time; roofs and spires in
  slate, some copper or red tile, some spires stone; at night some windows
  glow for evening services. Each part only sets an opening's numbers (its
  middle, width, sill, where its arch springs, what fills it) and one arch
  test, one stained-glass painter and one masonry call draw them: 0.4-0.6 s
  to compile, building.gdshader untouched.
- Rowhouse fronts (`fronts.py`, near tiles): iron railings on 70% of
  brownstone and limestone stoops and 60% of others, the cheek walls a 22 cm
  curb under them; yards behind a stone wall or (75% of brick houses', 35%
  of brownstones') an iron fence on a curb, between brick posts with white
  pyramid caps in Queens, iron posts elsewhere; a box hedge or a shrub
  behind (none in 15% of yards); striped metal awnings over 60% of Queens
  rows' doors and 12% of others' (none on brownstone or limestone). Prewar
  rows' and tenements' cornices stand 0.6 m out over a sloping underside:
  faces of the building's own surface marked FRONT, so the shader paints
  its cornice on them, brackets and all. Queens' prewar buff brick rows
  (Ridgewood's) and 20% of other bayed rows have their bays rounded into bow
  fronts (six facets).
- The railings, fences, posts, plants and awnings are a surface of their
  own (SURFACE_FRONTS = 11, without collision, drawn while their tile's
  center is within 600 m), painted by `shaders/fronts.gdshader`: panels of
  pickets and rails (and posts at the ends) with the gaps cut out, drawn
  from both sides; 0.3-0.4 s to compile. building.gdshader lost its painted
  iron railings and fences (fragment 262,977 to 261,465 characters).
- Measured against the photos (`build/reference/compare/churches-fronts`,
  against master): Marble Collegiate's lower half 0.34 to 0.30 (the photo
  0.29); Ridgewood, from a pose 2.2 m further out (the camera stood at the
  stoops), 0.48 to 0.43 (0.33), strong edges 0.069 to 0.079 (0.155).
- Cost: near tiles +8.9% (+131 MB, extrapolated from 60 random tiles;
  brownstone and Ridgewood blocks +22-43%: fronts surface 150-300 KB, the
  cornices and bows about 100-200 KB), churches +0.3%. One more draw call
  (and shadow caster) per near tile with fronts or churches, and per mid or
  far tile with a tall church. Frame time unchanged within the noise in
  Park Slope, Bed-Stuy and Ridgewood (uncapped, back and forth with master
  on a busy machine). Shader compile time: Times Square 34-40 s to ready
  before, 34-37 s after (interleaved on a busy machine: building.gdshader's
  color variant 18.9-25.6 s before, 18.7-21.2 s after, plus church.gdshader
  0.5 s; fronts.gdshader compiles where rows are in view).

**The els' steel and stairs (done; reference round 3's 26):**
- Lattice and rivets (`tools/citygen/els.py`): the subway els' side girders
  are riveted lattice girders, painted with the landmark bridges' lattice
  (chords top and bottom, posts and crossed diagonals every 2.4 m over the
  dark inside of the deck, their uv.y 0..1 up the girder), and the columns,
  cap girders and the girders under each track riveted plates: stiffeners
  every 1.5 m with a shadow beside each, rivets down them and in a row over
  each plate seam. Where a deck is low its sides stay plate down to the
  ground. The rivets are new in the shared steel code of
  `shaders/ground.gdshader` behind a new flag (RIVETS, 8), so the landmark
  bridges' steel is as it was; the els' palette's panel is 2.4 m (was 5,
  unused).
- Dark undersides: under the deck the floor beams and the bracing under
  each track are painted as lattice too (uv across each track's strip;
  between the tracks floor beams only) over the deep shade of the deck's
  underside, so from the street the el reads as dark steel framework, light
  only on its members.
- Stairs from the street up to the stations: from each of the MTA's stair
  entrances to a station the MTA lists as elevated or on a viaduct (the
  entrances and stations tables, `station_entrances` and `subway_stations`;
  449 entrances), up to the platform within 15 m: along the platform's
  outer side, just outside it, toward its middle; from entrances further
  out (at the corners of cross streets) a first run climbs straight in
  toward the el to a corner landing first. Flights at 35 degrees with steps
  about 18 cm high and a landing every 4.5 m of rise, a landing at the top
  reaching over to the platform (a gap in its windscreen), concrete treads
  lit at night like the platforms, steel risers and underside, riveted
  stringers under lattice railings, posts under the landings; collision.
  None where the platform's side toward the entrance is at the tracks
  (island platforms, reached from below), where it wouldn't fit beside the
  platform, or where it would meet an el column or come within 1.6 m of a
  track: 262 stairs. Props keep off them, and the subway entrance props at
  their feet (railings down and globes) go. The station outlines' narrow
  strips (their stairs' roofs, under 2.2 m wide) are no longer built as
  bits of platform.
- Measured (`build/reference/compare/el-steel`, roosevelt_ave): the el's
  underside at the top of the frame #161C1A on master to #060909 (the photo
  #0D100F), the frame's green share 0.12 to 0.04 (0.04); the street
  unchanged (lower half 0.25). The stair on 82nd Street stands where the
  photo's does.
- Cost: the 509 near tiles with els (or their trains) +1.1% (312 MB
  compressed, +3.5 MB; the stairs are about 220 triangles each), mid and
  far tiles +0.1%; no new draw calls. Shader compile time: the ground
  shader's color variant is 1.1% longer (125,703 characters) and about 0.15
  s slower to compile (2.3-2.4 s to 2.4-2.6 s at Times Square, three
  interleaved pairs on a busy machine; 1.4-1.8 s to 1.9-2.0 s in two
  quieter ones); building.gdshader unchanged.

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
  more detail (the statue's face and drape, gargoyles, crown fins); more
  landmarks in the second batch (below).

**Landmark bridges (done, 2026-10-16):**
- `tools/citygen/bridge_landmarks.py` builds four bridges by hand at their
  real dimensions over their main spans (anchorage to anchorage, or between
  the towers); `bridges.py`'s generic deck, columns and lamps stay on their
  approaches. Positions from OpenStreetMap; dimensions from NYC DOT, the
  HAER records and the figures Wikipedia cites.
  - The Brooklyn Bridge: granite towers to 84.3 m, each with two pointed
    arches 35.7 m high over the roadway, the piers standing proud, a string
    course and cornice; four cables over four stiffening trusses (open up
    close, with crossbeams over the roadways), suspenders every 2.8 m and
    the diagonal stays fanning from the tower tops; the wooden promenade
    5.5 m above the roadways, widening around the towers' central piers,
    with historic lanterns instead of cobra-heads; limestone anchorages;
    the roadway cambered from 36.35 m at the towers to 41.1 m mid-river;
    granite sides and piers on the approaches.
  - The Manhattan Bridge: blue steel towers of four tapering columns on
    masonry piers, X bracing, arched portals under the top girder and under
    the deck, finials; four cables over four 7.3 m trusses; the upper
    roadways over the subway tracks (two each side), the lower roadway 6.2 m
    down between the inner trusses (climbing to the upper level at the
    anchorages), the walkway and bikeway outside; granite anchorages.
  - The Hell Gate Bridge (newly built, from the railroad structures): the
    two-hinged arch with its humped upper chord, hangers and posts, four
    tracks, granite towers with arched passages, Hell Gate Red; its 3.3 km
    viaduct as a generic deck with a ballast bed.
  - The High Bridge (newly built, from the pedestrian structures): granite
    arches on their piers, the 1928 steel arch over the Harlem River, the
    brick walkway level from bluff to bluff, lampposts.
- Drawn in the structures surface like the other bridges (no extra draw
  calls, collision up close): new structure kinds (painted steel, walkways,
  track beds) and per-bridge palettes in uv2.y, painted in
  `ground.gdshader`; far off, steel bands are painted as open trusses.
  At night the towers (and the High Bridge's arches) are floodlit and the
  cables keep their necklace lights.
- Traffic follows the decks (lanes and paint read the road tops). Paths
  the data codes as bridges without lanes (the promenade, the Manhattan
  Bridge's walkway and bikeway, the High Bridge) no longer get cars, and
  raised-road decks stay off the hand-made bridges (a phantom deck under
  the High Bridge is gone).
- Cost: triangles near / mid / far: Brooklyn 31.2k / 8.9k / 3.9k (was
  7.9k / 6.1k / 4.5k), Manhattan 23.5k / 7.6k / 2.6k (was 6.9k / 5.4k /
  3.8k), Hell Gate with its viaduct 16.7k / 12.2k / 6.3k, the High Bridge
  2.3k / 1.3k / 0.5k. Tiles +1.6 MB near, +0.5 MB mid, +0.2 MB far.
- Next: the Manhattan Bridge's arch and colonnade, the anchorages' arched
  vaults, the Williamsburg and Queensboro by hand, the Hell Gate viaduct's
  real heights over Wards and Randalls Islands (it stays at the arch's
  44 m there).

**Landmarks, second batch (done):**
- Fourteen more in `landmarks.py`, the same way (in place of their data
  buildings by BIN, all three detail levels, own materials, collision up
  close), from published dimensions and the city's 3-D model and aerial
  photos (sources with each):
  - the Guggenheim: the rotunda's white bands spiraling up as one strip
    (24 samples a turn), each leaning out over a glass strip, 30 m across at
    the foot to 38 m at the roof (29.7 m), the skylight's twelve-sided dome,
    the Monitor, the bridge with the museum's name, the annex's limestone
    grid;
  - the Public Library: the 3-D model's massing in Vermont marble (arched
    windows, pilasters, cornice), the portico's six columns and three
    arches, the terrace, the steps and the lions on their pedestals;
  - St. Patrick's: aisles, clerestory and transepts with pointed windows
    and buttresses, steep slate roofs, the apse, the west front with its
    portal and rose window, two towers with octagonal lanterns and spires to
    100.4 m, pinnacles;
  - the UN: the Secretariat (blue-green glass, marble ends, the mechanical
    floors' grilles) and the General Assembly (curving walls, the roof
    sweeping down and up again, glass between marble piers at the ends, the
    dome), the Conference Building from the 3-D model;
  - Citigroup Center on its four stilts and core, aluminum bands, the crown
    sloping 45 degrees to the south (white at night), St. Peter's;
  - the Hearst Tower: the 1928 base with pylons and urns, the clerestory,
    the diagrid (painted, nodes on the corners every other tier) and the
    "bird's mouth" corners in the geometry;
  - the Met: the 3-D model's galleries with skylit roofs, the wings'
    pilasters and windows, Hunt's three great arches, four pairs of columns
    each crowned by its uncarved block, the grand steps;
  - the Vessel (a copper honeycomb of stairs, inside and out), the Oculus
    (a glass hall between white ribs that cross over the skylight into
    wings to 51 m, lit from inside at night), Yankee Stadium (the 3-D
    model's stands in blue seats, the limestone wall with its arches and
    YANKEE STADIUM in gold, the frieze, the field with its diamond, the video
    board);
  - the Unisphere: a steel lattice of meridians and parallels with the
    continents as plates (Natural Earth's 1:110m land in 7.5-degree cells),
    tilted 23.5 degrees, three orbit rings, the tripod, the fountain pool;
    painted on a solid globe further away;
  - Coney Island: the Wonder Wheel (blue A-frames, 16 spokes, the curved
    tracks, 8 fixed and 16 swinging cars, the sign; chasing bulbs at night)
    and the Parachute Jump (the red lattice tower, twelve arms and their
    ring; its LEDs in waves of color at night);
  - Radio City Music Hall's marquee round the corner of Sixth Avenue and
    50th Street (the name in lights, chasing bulbs) and the vertical RADIO
    CITY sign, on its building's 3-D model shape.
- Their own materials (41-58) are painted by a shader of their own,
  `shaders/landmark.gdshader`, on a new tile surface (kind 8, landmarks;
  the game gives it that material and collision); their faces in the first
  batch's materials (paving, stone, copper) stay in the buildings surface.
  Folded into `building.gdshader` instead, they pushed the time Chrome on
  Windows (ANGLE's D3D compiler) takes to compile it past 6 minutes.
  Measured on this machine, idle: the city's first load takes 200-265 s
  of GPU-process compiling already at HEAD, nearly all of it the buildings'
  shader (the game freezes meanwhile; Chrome caches it afterwards), and
  about the same (190 s) with the landmark shader added. Worth fixing on
  its own: a cold first load of nycheroes.party in Chrome on Windows likely
  freezes for minutes.
- Landmarks can now stand without a data building (`at=`, the Unisphere)
  and see the terrain around them (steps, the field, the pool).
- 432 Park Avenue and the Edge (30 Hudson Yards) were already in
  `towers.py`; bridges and supertalls are other work.
- Landmark institutions no longer get storefronts where PLUTO lists retail
  area (the Racquet Club on Park Avenue; 147 buildings).
- Cost: 18,900 / 7,800 / 2,300 triangles (near / mid / far), in place of
  their data buildings'; tiles +178 kB over the 34 that hold them (near
  +74 kB, mid +80 kB, far +25 kB); one more draw call in each of those
  tiles.

**Landmarks in stone, not toys (done; reference round 3's 22):**
- St. Patrick's west front is built, not painted, with a few Gothic helpers
  in `landmarks.py` (faces with openings set back in orders, gabled frames,
  crockets, pinnacles, an openwork spire), from Wikipedia's figures: the main
  portal (31 by 51 ft) set back 12 ft in three orders to the bronze doors
  (16.5 ft) under a row of niches, the side portals in two, each under a
  crocketed gablet; the rose window (26 ft) in a pointed arch set back
  twice, its glass dark and muted (sixteen lights round a quatrefoil, no
  more rainbow); the crocketed central gable (156 ft) with a wheel of blind
  tracery and the cross; each tower's traceried window under a gable, four
  small lancets to a side, buttresses at the corners stepping back in three
  stages with small pinnacles on the setbacks, the battlement and clustered
  pinnacles at 136 ft; the octagonal lanterns' paired openings, gablets and
  pinnacles; the spires in tiers of pierced tracery (painted, narrowing with
  the faces) between moldings, crockets up their eight edges. The aisles'
  and transepts' pinnacles are real pinnacles too. Gray-tan Tuckahoe marble,
  blotchy and grimier low down (`CATHEDRAL_MARBLE`); floodlit at night.
- The Guggenheim: the spiral in 72 samples a turn (24 before) with smooth
  normals, white-gray instead of cream; its ground floor as photos show it:
  the lobby's glass set back under the base drum that carries the bridge's
  band round the rotunda's front, then three bands to the roof.
- The others, a view each: the Vessel was a bright orange waffle cone (its
  copper muted now, its openings showing the flights across the bowl); the
  Met's column pairs stood flat against the wall (shadow behind each pair);
  the rest read as intended. The Statue of Liberty's mint green and its
  low-poly statue are painted by building.gdshader: left for later.
- Compile time: landmark.gdshader's tables indexed per pixel went from
  seven to two (the made-up letters and the three words in one table,
  looked up once, so glyph() is compiled once; the ad colors and the
  stained glass as formulas), which paid for St. Patrick's code. Its color
  program compiles as fast as before: medians of nine interleaved compiles
  of the captured programs, 2.38 s at master and 2.42 s now (busy machine;
  about 2 s idle). The waterfront's materials (below) cost 0.4 s inside it,
  so they have a shader of their own.
- Cost: St. Patrick's 679 / 505 / 318 triangles to 11,127 / 3,057 / 302
  (near / mid / far), the Guggenheim 1,820 / 1,048 / 109 to 3,386 / 1,686 /
  127; St. Patrick's near tile +180 kB, the Guggenheim's +23 kB; no new draw
  calls. Still at the 145 FPS cap in both views.

**Waterfront landmarks (done; reference round 3's 28):**
- Piers: the city's pier outlines (Planimetric hydrography structures,
  feature 2800) were never drawn out over the water, because
  `prepare_ground` adds them to the land and then takes the water away,
  piers with it. `build_tiles.py` adds the 1,216 piers (1.25 km²) back to
  the land (`landmarks.piers()`, no cache change), with seawalls round them,
  and keeps the raised-water surfaces off them (the elevation model has the
  decks in it, so water round piers passed for raised water). Every tile
  with a pier changes: Chelsea Piers' and Brooklyn Bridge Park's piers, the
  Hudson River Park piers, the ferry racks and docks.
- St. George Ferry Terminal: the 3-D model's massing in glass toward the
  harbor (the 2005 waiting room's curtain wall, 40 ft high; ENR) and brick
  elsewhere; four slip houses where the slips meet it (brick towers either
  side, a white steel frame over the opening, the transfer bridge's deck,
  the terminal's glass behind), their places and headings from the city's
  aerial photos; the slips' timber fender racks over the hydrography
  structures' outlines (3 to 4.5 m above the water, darker where the tide
  wets them); two Staten Island ferries in their slips (95 by 21 m,
  double-ended, orange, two passenger decks, pilothouses at both ends,
  windows lit at night).
- Whitehall Terminal (Frederic Schwartz, 2005): glass on three sides and
  corrugated stainless toward the slips over the 3-D model's massing; its
  lowest tier beyond the building is the long canopy on columns, the words
  along its fascia; the slips' racks (the hydrography structures' 2810
  outlines, not drawn before) and a ferry in the east slip.
- Chelsea Piers: the Pier 60 and 61 sheds (the 3-D model's side aisles and
  stepped monitor roof) in metal panels with bands of windows; the golf
  range's netting on Pier 59 as its six pairs of 46 m poles and their
  cables (the height from their shadows in the aerial photos).
- Brooklyn Bridge Park: Pier 2's three roofs in ridged bays on steel
  columns, open-sided (the data had a 10 m box over the whole pier); the
  Pier 3 uplands' berm along Furman Street (9.1 m high, about 240 m long;
  the park's press release, its line from the aerial photos), a meadow whose
  trees and crowns stand on it (`landmarks.lift()` raises them); the ONE15
  marina's floating docks (the narrow parts of the pier outline there)
  decked in timber, the attenuators' pilings, and the 15 boats moored in the
  aerial photos (found as bright hulls on the water: place, heading, length
  and beam), cabins, flybridges and masts.
- Their materials (60, 61: glass, brick, panels and white steel; timber,
  decking, boats and ferries) are painted by `shaders/waterfront.gdshader`
  on a tile surface of their own (kind 12, waterfront), compiled only near
  the waterfront: 0.4 s. In landmark.gdshader they added 0.4 s to its 2 s.
- Cost: triangles near / mid / far: St. George 2,433 / 1,754 / 746,
  Whitehall 1,456 / 1,053 / 384, Chelsea Piers' sheds 368 / 170 / 47 and
  golf range 504 / 432 / 144, Pier 2 1,836 / 1,836 / 108, the berm 3,864 /
  946 / 190, the marina 1,898 / 1,517 / 662; one more draw call in the
  tiles that hold them. The 26 tiles rebuilt here: +804 kB (+6%), the
  piers' ground included.
- Next: the lawns, trees and fields on Brooklyn Bridge Park's piers (the
  2017 land cover has Piers 3 and 5 paved and Pier 1 as water), St.
  George's white arched canopy (84 ft by 320 ft), the Battery Maritime
  Building's green cast iron and slips, more boats in summer.

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
- The headless test (`tests/audio_test.tscn`) no longer depends on luck.
  While it checks the engines on the cars it drives past the hero, Traffic
  is paused: its reports of the real cars, ten times a second, took the
  engines off the test's cars, and they all faded out together and came
  back, so a check landing in that moment read "0 engines" (2 runs of 4 on
  a loaded machine). The four engines must now stay on their cars the whole
  way. And thugs still walking up look at the hero again until one has
  shouted: each shouts only half the time it spots the hero, so all four
  kept quiet about 1 run in 16.

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
  two, 25 three), at the heights the lidar survey measures (below), else
  each level 7 m above the low ground around them (5 m clearance under a
  2 m deck). They ramp between the levels at their ends and never dip below
  the ground; carriageways and ramps at one level merge into one deck. Bridge outlines on land give viaducts their true edges
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
- **Elevated railways** (`tools/citygen/els.py`): the subway's els (the 7
  over Queens Boulevard and Roosevelt Avenue, the J/M/Z over Broadway, the
  4 on Jerome Avenue, the 2/5 on White Plains Road, the N/W in Astoria, the
  Culver Viaduct, the 1 over 125th Street, the West End, Sea Beach,
  Brighton and Culver lines, the A in the Rockaways...) and the railroads'
  viaducts (Metro-North's Park Avenue Viaduct, the LIRR in Jamaica), from
  the planimetric railroad lines (every track's centerline, coded elevated
  or viaduct), the rail bridge and viaduct outlines (their true edges) and
  the elevated stations' outlines. 391 km of track. Decks sit 7.5 m over
  the street (5.3 m clear under the girders) and hold their height over
  dips and roads at most 3% steep, worked out over the whole track network
  at once, so the 1 crosses the 125th Street valley high; they come down at
  3.5% where a track goes on into an embankment, a cut or a tunnel (yard
  leads on their own). The Culver Viaduct clears the Gowanus Canal at 30 m.
  Subway els are open steel painted el green: ties and rails on each
  track, girders under them and along the edges, bents every 15 m (8,350:
  a cap girder on columns with knee braces, standing at the curbs, out of
  the travel lanes and the roadway of cross streets); the railroads' are
  concrete. 1,015 station platforms clear of the tracks, with windscreens
  and canopies on posts, lit at night. Collision everywhere (run along the
  tracks, stand on the canopies); parked cars and other props keep out of
  the columns and from under the decks. The Hell Gate's approaches and the
  tracks on the big bridges stay with those bridges. Shading reuses the
  landmark bridges' steel (palette 0 is the els' green), track bed and
  concrete: no new shader code. Cost: about 2.6 million triangles near,
  0.53 million mid, 54,000 far; in the tiles around the 7, the J and the 4,
  near tiles +5.6% bytes (+8% triangles), mid +6.5%, far +3.6%.
- **Roadbed under decks:** the city's roadbed outlines take in raised roads,
  so road was drawn on the ground under viaducts and bridge approaches (over
  lots and parks). Under decks at least 3 m up, away from the streets at
  grade, the roadbed is cut back (3,571 outlines, about 2.3 km²); the
  ground there is pavement or park again, with curbs along the streets
  that do pass under.
- **Walking lanes on decks:** the planimetric sidewalk outlines on bridges
  and raised streets that run along them get a walking lane at the deck's
  height, on the highest roadway or hand-made walkway there (967; the
  Williamsburg's and Queensboro's walkways among them).
- **Signals where ramps meet streets:** ramps and bridges arriving at a
  signalized street intersection take the phase of the street approach in
  line with them (or the crossing one's): 434 ends.
- **Viaduct heights from the lidar survey** (`tools/citygen/lidar.py`): the
  city's 2017 topobathymetric lidar (NOAA's copy as Entwine point tiles; the
  830 MB around the raised roads download into `data/raw/lidar` on the first
  build) gives the surfaces every 10 m along the 551 km of raised roads,
  matched to the elevation model through the ground around. The raised
  roads' heights are fitted to them over the whole network at once (a
  smoothed least-squares fit: each station follows the surface that runs on
  with its neighbors' and the roads it meets, so bridges, roofs and roads
  over or under it drop out), held 5.5 m over the streets and roads passing
  under and 4.5 m under those passing over (by the level codes), and falling
  back on 7 m a level where the survey sees no deck (about half the stations
  follow a surface). The Gowanus Expressway now stands 31 m over the Gowanus
  Canal and 12-14 m over Third Avenue, the Cross Bronx's ramps onto the
  Alexander Hamilton Bridge 33 m over the Major Deegan, the BQE 20-38 m on
  the Kosciuszko approaches, the Bruckner 10-16 m, the Kew Gardens
  interchange up to 15 m, the big bridges' land approaches at their real
  heights (the Manhattan Bridge's 20-30 m). Roads at street level in the
  data between two raised ones (level codes that dip for no street) stay up,
  and viaducts crossing a creek or canal on a bridge outline hold their
  height over it. Decks bend between the heights of the roads on them
  (within 20 m). Over the network: stacked crossings less than 1 m apart
  went from 33 to 1, raised road ends less than 4.5 m over a street from 534
  to 1, ramps steeper than 20% from 4.3 to 2.0 km. Cost: the viaducts' near
  tiles about +1%, mid +3%; no new draw calls.
- **The BQE's triple cantilever** (`tools/citygen/cantilever.py`), Remsen to
  Orange Street under the Brooklyn Heights Promenade: the Staten
  Island-bound roadway on the lower deck, the Queens-bound one on the middle
  deck and the Promenade on top, each set back about 5 m from the one below
  and cantilevered off the retaining wall cut into the bluff, at the lidar's
  heights over Furman Street (5.1, 10.6 and 16 m: Furman Street 3.7 m above
  sea level, the Promenade 19.7), stacked on north to the Columbia Heights
  overpass and rising over Joralemon Street at the south end (NYC DOT's BQE
  Central scope and 2018 section, the expert panel's report, the bridge
  inventory's 4.2 m clearances, photos from Brooklyn Bridge Park). The
  roadways' centerlines (levels 5 and 9, along the decks' west edges) are
  moved onto their decks, so traffic drives both; their ramps north of it
  climb out of a trench to the Sands Street interchange. The bluff the
  bare-earth model puts there is cut away under the structure (a floor a
  meter under Furman Street, walls where the cut meets higher ground) and
  filled up behind it to the gardens 2.2 m below the Promenade, sloping back
  down to the model's ground; Columbia Heights bridges the cut. Curved
  soffits, square-paneled walls, rust fascias, green-gray pipe railings on
  posts, the Promenade's pavers, planted strip, brown fence over a rounded
  edge and post-top lamps, its walking lanes; collision everywhere. Shading
  reuses the landmark bridges' kinds and palettes: no new shader code. Cost:
  the four near tiles around it +247 KB (+13%; +15% triangles, a third of
  them paint), the mid ones +89 KB (+10%), the far one +23 KB (+2%); no new
  draw calls.
- **Sunken roads** (`tools/citygen/trenches.py`): the 200 km of streets,
  highways and ramps below street level by the centerlines' level codes (9
  and 5) but the triple cantilever's: the BQE's trench along Hicks Street,
  the Cross Bronx's cuts through East Tremont and the Trans-Manhattan
  Expressway's, the Gowanus and Prospect Expressways, the Grand Central, the
  Long Island and Van Wyck Expressways' depressed stretches, the Central Park
  transverses, the underpasses. The lidar survey every 10 m along them (300
  MB more of its point tiles, ground points included): the surfaces over the
  centerline and the lowest surface across the road, out to 40 m either side.
  Heights follow the lowest surface the way a road can (climbing at most 8%):
  one that jumps 3 m above where the road could have come up to is something
  over it (a bridge, a building, a tunnel's lid), holding the road 5 m under
  it; then a smoothed least-squares fit over the whole network, like the
  viaducts'. Covered stretches at least 45 m long where the survey can't see
  the road are tunnels (20 km: the Battery Park Underpass, under the Bridge
  Apartments, the First Avenue tunnel); ends at street level stay on the
  street, and ramps climbing out of a cut onto a viaduct start from its
  height. A few roads by the water the survey has under sea level stay half
  a meter above it.
- **The cuts:** along every sunken road but its tunnels, a strip out to the
  walls where the survey sees them (else the road's width and a 1.5 m
  shoulder; medians between carriageways closed; never under a building or a
  street running along the edge) is cut down, with the road's surface over
  it (3.3 km²); concrete retaining walls where its edge meets higher ground
  (side walls where the road runs higher), parapets on those 2 m high or
  more, and cobra-head lamps along them. The elevation model's 10 m pixels
  blur the cuts' edges, so the ground within 15 m of a cut at least 1.5 m
  deep comes up to the ground 15 m out. 408 cross streets and bridge outlines
  span the cuts on flat decks at the street's height (road and sidewalk on
  top, fascia and capped parapets over the cut; 198 of the city's outlines,
  the rest the streets' own width), and 245 tunnel portals open into the
  walls, the first 25 m of tunnel built, under the ground over them.
  Generalizes the triple cantilever's cut: its ground wraps the cantilever's,
  with its deck, underside and wall builders, no road special-cased. Far
  tiles, which draw no streets, keep their ground whole.
- **Lanes and paint in the cuts:** the sunken roads join the raised roads'
  network (same node ids at street-level ends, so traffic drives through the
  cuts and up their ramps), their driving lanes and paint on the cut's road
  surface; collision everywhere (a hero lands in a cut, runs along it and up
  against its walls). Walking lanes, props, trees and utility poles stay out
  of the cuts but for the bridges. Cost: near tiles with a cut +4.5% bytes
  (+6% triangles; up to +16% in Washington Heights), mid +7%, far none;
  0-3% more draw calls in those views; no new shader code.
- **Trains on the els** (`tools/citygen/trains.py`, `scripts/world/trains.gd`,
  the track graph in `train_tracks.gd`): every subway el track's centerline
  at its rails' height, cut into pieces at switches and junctions and at
  least every 250 m, each running the way trains do on it: trains keep
  right, so a track with tracks alongside to its left runs along its line,
  one with tracks to its right against it; tracks with none alongside
  (flyovers, switches) follow the tracks they join; a three-track el's
  middle track (express, rush hours only) gets pieces both ways (below).
  Along each piece the
  curves' speed limits (0.8 m/s² sideways, 4.5 m/s at the tightest) and the
  stops (the middle of each platform beside the track; express tracks run
  through); bits of el too short to run on (a line on an embankment
  crossing a street) are left out. A new near-tile surface (kind 9, one
  vertex per point and no indices, so earlier games skip it; no format
  change): 1,410 pieces, 225 km of track, 333 stops in 244 tiles, linked
  across tiles by node ids like the driving lanes.
- **The trains:** up to 4 at once (medium 3, low 2; `?trains=N`) within 1 km
  of the camera, appearing out of sight, past 650 m or out of a tunnel, gone
  past 1.3 km, into a tunnel or with their tiles. The numbered lines' cars
  (the A Division's) are 15.5 m long and 2.7 m wide, 10 to a train (the 7
  11); the lettered lines' 18.4 m and 3.05 m, 8 or 10 (the J/Z and the M 8);
  each train shows one of its line's route bullets in the MTA's colors (the
  2 or the 5 on White Plains Road, the N or W in Astoria...). They run at up
  to 18 m/s, slowing for curves ahead in time, pull away at 1.1 m/s², stop
  with their middle at the platform's middle for 20-30 s, keep 60 m behind
  the train ahead, cross junctions where tracks merge one at a time, and
  stop 12 m short of a hero or thug on the tracks. Where an el's tracks go
  on into a tunnel or down to the ground, trains run in and come out (the
  cars past the end vanish); at a terminal's bumper they turn back (below).
- **Riding:** heroes within 80 m of a train give its cars collision (a box
  each, on a new physics layer 6, "trains", which heroes collide with and
  webs, cameras and thugs don't), moved every physics tick with
  `constant_linear_velocity`, so a hero landing on a roof rides along;
  trains are drawn between physics ticks like heroes, so the rider stays
  put on the roof.
- **Look:** one 62-triangle car mesh (`PropMeshes.train_car()`) drawn as
  one MultiMesh, the cars turned to their heading in
  `shaders/train.gdshader` (the script writes each car's middle and heading,
  no rotations): stainless sides fluted below the windows, sliding doors,
  tinted windows, a sign near each end with the route bullet (a 5x7 pixel
  font in a tiny texture), air conditioners on the roof, cab ends dark round
  their windows with the bullet over them, headlights at the front and red
  lights at the back, the underframe and trucks with their wheels; the
  windows light up at night. 0.2 s to compile. Two nearest trains rumble
  (wheels over the rail joints, the steel el roaring, quicker as they speed
  up) and squeal on curves and braking into stations (synthesized,
  `tools/audio/build_sounds.py --only`).
- **Yellow platform edges:** a 0.6 m strip along the els' platform edges at
  the tracks, the road paint's solid yellow in the near tiles' markings (no
  new shader code).
- **Signal heads on el columns:** traffic signals whose poles would reach
  into an el (or stand in a column) hang on the nearest column within 12 m
  instead, facing the same traffic, where the deck clears their heads: a
  new signal variant (the heads alone, no pole, mast arm or street sign).
  60 in the 28 near tiles around the 7, the J and the 4.
- **Through the gaps, over the Williamsburg Bridge:** stretches of el
  track up to 500 m long through outlines left to the bridges, between els
  on both sides, stay els, deck, bents and all: Queensboro Plaza (the 7's
  and the N/W's approaches cross the Queensboro Bridge's ramp), the Culver
  Viaduct over the Gowanus Canal beside the 9th Street Bridge, the 6 over
  the Bronx River beside the Westchester Avenue Bridge, the 7 over the
  Flushing River (19 stretches). And from the J's el at its end at the
  Williamsburg Bridge, its two tracks go on over the bridge for trains
  (`els._bridge_tracks`): the planimetric tracks through the bridge's
  outline, the straight way on at its crossovers, at the height of the
  bridge's deck under them (22 m where the el meets it, 41 m over the main
  span), 2.2 km to where they go underground on the Manhattan side.
  Before, trains vanished at all of these.
- **Express trains:** a three-track el's middle track (the 7's, the 4's on
  Jerome Avenue, the 2/5's, the 6's, the Culver's...) has pieces both ways
  (60 km toward Manhattan, 45 km away), flagged which way they run; they
  stop only at the platforms beside them (express stations), and run onto
  the local tracks over the switches at their ends. The game runs one way,
  by the time of day at the start (`Trains.EXPRESS_HOURS`): toward Manhattan
  6-10, away from it 15-20 (the evening rush, so at the default 15:30), else
  none; `TrainTracks.express` leaves out the other way's pieces.
- **Turning back at terminals:** at a dead end with a platform within 200
  m of it, trains wait 12 s at the bumper and go back the way they came,
  their last car now leading (the cars stand where they were). The tiles
  bring the way back (`trains._turn_backs`): the terminal's track reversed
  (TURN_BACK pieces, no stops) to the first switch at least 200 m back (a
  train's length) onto a track running the other way, else (at 13 of the
  14: the data's crossovers there seldom lead that way) to a crossover made
  200 m back (or further, every 20 m) onto the track alongside running
  that way (an S over 45 m at 8 m/s, cutting that track at a new node).
  The track between that switch and the bumper is TERMINAL: one train in it
  at a time (`Trains._control` claims it, like a junction, before running
  in; the train keeps it until it has come back out). 14 of the 18 dead
  ends (all of them now with a platform by the bumper, see below): Woodlawn,
  Wakefield, Pelham Bay Park, Van Cortlandt Park, Ditmars Boulevard,
  Lefferts Boulevard, Far Rockaway, Coney Island's West End tracks...; not
  single-track ones (the Franklin Avenue Shuttle), where trains still wait
  until they're out of sight. The trains surface now has 2,104 pieces (357
  km, express tracks counted both ways) and 372 stops in 273 near tiles.
- **Commuter trains:** Metro-North's trains on the Park Avenue Viaduct
  (their names start "METRO-NORTH") and the LIRR's on its viaducts (Atlantic
  Avenue, Jamaica), 23.5 km: cars like an M7, 25.9 m long and 3.2 m wide
  with two doors a side, 8 to a train on Metro-North, 10 on the LIRR, a
  plain disc in the MTA's blue on their signs; they stop at the elevated
  stations' platforms there (Harlem-125th Street...).
- **No traps:** pieces that lead only into dead ends without a stop (stubs,
  yard leads, and express tracks' ways into any dead end) are left out, so
  no train runs into one and stands there (before, a train that took one
  waited until it was out of sight).
- **Speed limits from the point before:** a point's curve limit now holds
  from the point before it, so trains brake for it in time (before, a
  train placed between two points could run over the next point's limit).
- **Never through each other:** a train no longer appears (nor is put, by
  a test) on or close before a junction or a terminal's track that another
  train has claimed: that one is crossing it, or about to, and doesn't stop
  for the new one. The trains test put its express train on the switch at
  the end of the 7's express track, its front where the switch meets the
  local track, and in 1 run of 3 a local train was coming up to that point
  too close to stop. And a train that has run into another (its front past
  the other's back) now stops at once; before, it took no notice of the
  train it overlapped, and the two ran on through each other for good
  (10,742 frames of overlap in that run). The test now puts its express
  train on a running piece of the express track, not on the switch (it
  had run on as a local).
- **Cost:** about 0.1 ms of script a frame in Chrome with 4 trains near the
  camera (drawing 0.07-0.09 ms, running 0.06 ms a physics tick; trains out
  of view, far off or standing are drawn less often), 1 draw call, 2,700
  triangles; the trains' tracks, platform edges and signals add about 2.4
  KB to a near tile with an el (+0.35%), about 0.9 MB in all.
- **Still to do:** sunken roads' cuts are plain concrete (no stone facing
  on the Cross Bronx's or the Central Park transverses' walls, no fences
  along the parapets); tunnels go 25 m in, then a wall; where the centerlines
  draw no carriageway the cut is the road's width; the lidar is from 2017
  (the Kosciuszko's second span and the Kew Gardens interchange's rebuild
  came later). Trains: none on the subway's tracks on
  embankments and in cuts (they vanish where an el comes down to them), on
  the Manhattan Bridge (its tracks are at grade in the data, between
  tunnels), or on the Hell Gate's; the J's tracks over the Williamsburg
  Bridge run on its road deck (a generic bridge) and end high on its
  Manhattan approach; single-track terminals don't turn trains back; the
  express trains' way is set at the start; each co-op player's game runs
  its own trains.

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
  USGS elevation tiles, the 3-D building model, the land cover map and the
  bike share's stations, about 4 GB with 33 GB unpacked; the sidewalk shed
  permits are the ones up on the day of the download), then `build_tiles.py` (its first run also
  fetches the lidar survey's point tiles around raised and sunken roads,
  1.1 GB, `lidar.py`),
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
- Shop signs' names: `python tools/citygen/sign_names.py build` (with the
  venv's Python) draws them into `assets/signs/sign_names.png`, downloading
  its fonts to `data/raw/fonts` the first time; the list is in that file.
- Web build: `tools/build_web.ps1` (add `-Serve` to play at
  http://localhost:8060; it also runs the co-op signaling server on port
  8070, after `npm install` in `tools/signaling`).
- Shader compile time (measured 2026-10-16): on Windows, browsers (ANGLE on
  D3D11) compile every shader a view needs with the D3D compiler, which
  inlines every function call and takes time growing with about the square
  of the code it ends up with: twice the code, four times the time. A first
  visit's page freezes meanwhile (later visits use the browser's shader
  cache). At Times Square, cold, on the dev machine (RTX 5090, Ryzen
  9950X3D, idle), that was 87-155 s to the city's "ready", over half of it
  on building.gdshader; now 19-27 s.
  - Godot compiles four "default" variants of every 3-D shader before the
    ones it draws with, and this game never draws with them. The page's
    `html/head_include` (in `export_presets.cfg`) hands ANGLE empty shaders
    for them: they're the 3-D shaders without a lightmap flag, and every
    variant Godot draws with has one (DISABLE_LIGHTMAP here). That saved two
    thirds of all compiling. After a Godot upgrade, check the console: "drew
    with an emptied default shader variant" means it no longer holds.
  - In shader code, call each heavy helper from one place: let the branches
    set its arguments and make one call after them (building.gdshader:
    `facade_for()`, `wall_texture()`, `window_light()` through
    `WindowLight`, `screen()`'s `TextLine`; landmark.gdshader's
    `landmark_wall_2()`). A helper called from three branches is compiled
    three times over, and the total is then squared. Big features that few
    tiles have belong in a shader of their own on a surface of their own
    (landmark.gdshader, waterfront.gdshader), compiled only once they're in
    view. Avoid adding dynamically indexed `const` arrays to the big
    shaders: ANGLE turns each into a per-pixel copy, which made the building
    shader compile about a third slower. Every line counts: 70 lines of
    waterfront materials made landmark.gdshader compile 0.4 s (20%) slower.
  - Check after changing shaders: `node tools/shader_compile_check.mjs
    http://localhost:8060/` (headless Chrome with a fresh profile: the time
    to "ready", and the compile time per shader and per program; `--cam=`
    and `--time=` pick the view, `--peds=` and `--gangs=` bring in
    pedestrians and thugs, which it leaves out by default). Keep Times
    Square around 20 s to ready on the dev machine, building.gdshader's
    color variant under about 10 s and every other shader under about 2 s.
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
  `res://tests/coop_test.tscn`, `res://tests/coop_migration_test.tscn` and
  `res://tests/coop_reconnect_test.tscn` (they run the signaling server, so
  `npm install` in `tools/signaling` first; `-- --port=N` picks its port,
  default 8071),
  `res://tests/audio_test.tscn` and
  `res://tests/traffic_test.tscn` (75 s of
  midtown traffic: no red light run, no overlaps, cars stop for the hero,
  and leave with their tiles) and `res://tests/trains_test.tscn` (the 7 at
  74th Street for 2 minutes with an express train on its middle track: no
  overlaps or speeding, stops at the platforms' middles, a train stops for
  the hero on the tracks and carries the hero on its roof, and trains leave
  with their tiles; then a train turns back at Woodlawn's bumper and comes
  out onto the other track, alone on the terminal's track; it needs tiles
  with the trains surface around the 7, the 4 on Jerome Avenue and
  Woodlawn; `TRAINS_TERMINAL_ONLY=1` goes straight to Woodlawn).
- Launch options (URL or `-- --name=value` on desktop): `?cam=x,y,z,yaw,pitch`
  free camera, `?spawn=x,y,z,yaw` hero start, `?stats` console stats,
  `?peds=N`, `?gangs=N`, `?traffic=N`, `?trains=N` (0: none), `?demo` / `?demo=fight` / `?demo=city` / `?demo=new` scripted tours for videos,
  `?host` / `?join=CODE` co-op, `?signal=wss://...` signaling server
  (default: the page's host, port 8070), `?relay=1` co-op only through the
  TURN relay (testing), `?weather=overcast`, `?date=MM-DD` (or
  `YYYY-MM-DD`) the sun's arc on that day, `?fog_scatter=` (sun tint of
  the fog), `?tree_shadows=0` trees without shadows,
  `--tiles=DIR` (desktop and tests) read the city from a tile copy.
