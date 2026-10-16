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
| 6 | Realism from open data | In progress (real shape, facades, trees, water towers, paint, roofs, night, furniture, cars and traffic, facade materials and stoops, ground details, first landmarks, sound done) |
| 7 | Phones and tablets | Done in emulation; real phones to check |
| 8 | Overpasses and missing bridges | Done (raised roads, the Kosciuszko, real tower positions, elevated railways) |
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
  default count is what memory allows). Three levels
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
  close; lighter greens; small flowering trees shorter, Callery pears
  teardrop-shaped.
- Woods past the tree distance show round sunlit crowns in the trees'
  colors, and at a slant trees hide the ground behind them, so Central Park
  reads as canopy from Top of the Rock.
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
- **Still to do:** other sunken roads (the BQE's trench along Hicks Street,
  the Cross Bronx's cuts: no lanes or paint below street level yet); trains
  on the els; signal heads on el columns (signal poles under an el are left
  out); yellow platform edges; the lidar is from 2017 (the Kosciuszko's
  second span and the Kew Gardens interchange's rebuild came later).

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
  4 GB with 33 GB unpacked), then `build_tiles.py` (its first run also
  fetches the lidar survey's point tiles around raised roads, 830 MB,
  `lidar.py`),
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
    (landmark.gdshader), compiled only once they're in view. Avoid adding
    dynamically indexed `const` arrays to the big shaders: ANGLE turns each
    into a per-pixel copy, which made the building shader compile about a
    third slower.
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
  and leave with their tiles).
- Launch options (URL or `-- --name=value` on desktop): `?cam=x,y,z,yaw,pitch`
  free camera, `?spawn=x,y,z,yaw` hero start, `?stats` console stats,
  `?peds=N`, `?gangs=N`, `?traffic=N` (0: none), `?demo` / `?demo=fight` / `?demo=city` / `?demo=new` scripted tours for videos,
  `?host` / `?join=CODE` co-op, `?signal=wss://...` signaling server
  (default: the page's host, port 8070), `?relay=1` co-op only through the
  TURN relay (testing), `?weather=overcast`, `?date=MM-DD` (or
  `YYYY-MM-DD`) the sun's arc on that day, `?fog_scatter=` (sun tint of
  the fog), `?tree_shadows=0` trees without shadows,
  `--tiles=DIR` (desktop and tests) read the city from a tile copy.
