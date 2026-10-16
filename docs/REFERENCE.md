# Reference views: the game next to real photos

Step 6, item 7 ("check against reality"). Thirteen viewpoints a player
actually sees, each a free-licensed photo from Wikimedia Commons next to the
game at the same camera pose. Re-run after each phase; the differences below
drive the next work.

## How to run

```
tools/citygen/.venv/Scripts/python.exe tools/reference/compare.py
```

It downloads any missing photo to `build/reference/photos/` (gitignored;
photos are never committed), screenshots https://nycheroes.party at every
view in headless Chrome (`tools/reference/shoot.mjs`, CDP port 9384), and
writes photo | game pairs to `build/reference/compare/<label>/<view>.jpg`
plus `_all.jpg` (every view on one sheet). Options:

- `--site http://localhost:8060/index.html` to check a local build (serve
  `build/web` over HTTP first; see ROADMAP "Working on the project").
- `--label NAME` names the output folder (default `<host>-<date>`).
- `--also live-20261015` adds an earlier run's screenshots as a middle
  column (before | after).
- `--only times_square,flatiron` for a few views; `--skip-shots` to
  recompose from the screenshots already taken.
- `--profile %TEMP%\reference\chrome-profile` keeps Chrome's cache: the
  first view then loads in about 8 s instead of about 140 s (the game and
  its first tiles are about 100 MB).
- `--pose LAT,LON,HEADING[,PITCH[,EYE]]` prints a `?cam=` pose for a
  photo's position and compass heading (uses `data/cache/terrain.npy` for
  the ground height), for adding views.

A run takes about 3 minutes cold (13 views). Every view loads
`?cam=...&spawn=...&quality=high&gangs=0` at 2560x1440 and waits for the
game's "[city] ... ready" log plus 6 s for trees and props.

**How the pairs line up.** The free camera's vertical field of view is 70
degrees (102 degrees across at 16:9); each photo's is worked out from its
EXIF 35 mm equivalent focal length (`photo.hfov` in `views.json`). Both are
cropped to the field of view they share, measured from each camera's optical
axis (the screen center in the game; `photo.principal` for photos whose
horizon was moved in editing), and kept clear of the HUD text. So a building
that's the same size and in the same place in both panels really is the
same size and place.

**Adding a view.** Find a Commons photo with a geotag and EXIF focal length
(the Commons API's `list=geosearch` around a point works well), get the pose
with `--pose`, add an entry to `tools/reference/views.json` (copy the
license fields from the file page), run with `--only <name>`, and adjust:
geotags are often 5-20 m off, and the reliable fix is to line up two or
three landmarks whose positions are known (the footprint data has them), not
to eyeball a top-down view. Note how in `pose_note`.

**Caveats.** Photos are from different seasons, times and weather (several
show bare March/April trees, overcast skies or sunset light); the game is
always at its default 15:30 on a clear day. Judge shape, placement, scale and
palette, and treat light and foliage differences with care. The live site
currently serves tile format v6 (build `6ad14745`), so parked cars and
traffic, still in progress, don't show yet.

## The views

Images from the first run: `build/reference/compare/live-20261015/<name>.jpg`.

| Name | What | `?cam=` | Photo (Commons) | Author, license |
|------|------|---------|-----------------|-----------------|
| times_square | Times Square from Duffy Square, south | `13,16.1,-67,159.5,10.0` | [Times Square looking south from 46th Street](https://commons.wikimedia.org/wiki/File:Times_Square_looking_south_from_46th_Street.jpeg) (2019) | Dough4872, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| fifth_ave_esb | Fifth Ave at 29th St: Marble Collegiate Church, Empire State | `-127,14.2,1445,3.8,17.0` | [29th St 5th Av 03 - Marble Collegiate Church](https://commons.wikimedia.org/wiki/File:29th_St_5th_Av_03_-_Marble_Collegiate_Church.jpg) (2018) | Tdorante10, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| flatiron | The Flatiron from the 23rd St plaza | `-291,13.8,1711,167.1,13.0` | [Flatiron Building - panoramio (5)](https://commons.wikimedia.org/wiki/File:Flatiron_Building_-_panoramio_(5).jpg) (2015) | qwesy qwesy, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0) |
| park_ave | Park Ave at 53rd St, south to the MetLife Building | `1090,17.4,-122,150.3,0.0` | [Park Ave - panoramio](https://commons.wikimedia.org/wiki/File:Park_Ave_-_panoramio.jpg) (2015) | Elvis Boaventura, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0) |
| totr_south | Midtown from Top of the Rock, south | `510,280.0,-117,158.7,-0.8` | [New York skyline from Top of the Rock](https://commons.wikimedia.org/wiki/File:New_York_skyline_from_Top_of_the_Rock.jpg) (2024) | Hugo Maestá, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| totr_north | Central Park and 57th St from Top of the Rock, north | `525,280.0,-137,-25.0,-2.5` | [Sunset at the Top of the Rock (north side)](https://commons.wikimedia.org/wiki/File:Sunset_at_the_Top_of_the_Rock_(north_side)_-_Flickr_-_Nicolas_Lh..jpg) (2022) | Nicolas Lh., [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0) |
| brooklyn_bridge | Brooklyn Bridge promenade toward Manhattan | `-761,43.5,5975,42.2,1.5` | [Brooklyn Bridge, New York City, 20231005 0939 2163](https://commons.wikimedia.org/wiki/File:Brooklyn_Bridge,_New_York_City,_20231005_0939_2163.jpg) (2023) | Jakub Hałun, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| dumbo | DUMBO: Washington St framing the Manhattan Bridge | `-346,6.2,6100,-6.7,0.0` | [Manhattan Bridge and Empire State Building from Washington Street](https://commons.wikimedia.org/wiki/File:Manhattan_Bridge_and_Empire_State_Building_from_Washington_Street,_Dumbo,_Brooklyn,_New_York.jpg) (2026) | Christian David, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| promenade | Lower Manhattan from the Brooklyn Heights Promenade | `-1086,19.6,6948,38.0,0.0` | [View across the East River towards Lower Manhattan from the Brooklyn Heights Promenade](https://commons.wikimedia.org/wiki/File:2024-05-22_13_06_18_View_across_the_East_River_towards_Lower_Manhattan_from_the_Brooklyn_Heights_Promenade_in_Brooklyn,_New_York_City,_New_York.jpg) (2024) | Famartin, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| park_slope | Park Slope brownstone row | `834,34.7,9675,48.0,12.8` | [Park Slope](https://commons.wikimedia.org/wiki/File:Park_Slope.JPG) (2012) | Mark O'Neill, [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) |
| queens_ridgewood | Ridgewood, Queens: brick rowhouses on 60th Lane | `7674,26.2,6639,-32.5,10.0` | [60th Lane Ridgewood](https://commons.wikimedia.org/wiki/File:60th_Lane_Ridgewood.jpg) (2022) | Kidfly182, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| grand_concourse | Grand Concourse at E 170th St, Bronx, north | `6081,35.6,-9032,-27.4,0.0` | [Grand Concourse, Bronx - 20220616](https://commons.wikimedia.org/wiki/File:Grand_Concourse,_Bronx_-_20220616.jpg) (2022) | Andre Carrotflower, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| st_george | St. George, Staten Island, from the ferry | `-6892,10.0,12442,112.5,6.0` | [St. George Ferry Terminal, Staten Island](https://commons.wikimedia.org/wiki/File:St._George_Ferry_Terminal,_Staten_Island,_New_York_City,_20231002_1621_1749.jpg) (2023) | Jakub Hałun, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0) |

The images are for comparison only. If any are ever shown publicly, credit
them as in this table and keep the share-alike terms.

## What matches

- **Street layout and widths** are right wherever the pose is right: Fifth
  Avenue's 17 m roadway, Park Avenue's two roadways and median, the
  Grand Concourse's main road, malls and service roads, the Flatiron plaza,
  Park Slope's 9.5 m street and 8 m sidewalk plus front yard.
- **Buildings that have a 3-D model shape** stand in the right place at the
  right height: the Empire State Building, the Flatiron, the Paramount
  Building's stepped tower in Times Square, the Waldorf, Washington Street's
  warehouses in DUMBO, row heights and rhythm in Park Slope.
- Terrain (Park Slope rising toward the park, St. George's hill),
  Lower Manhattan's skyline width from Brooklyn, rooftop water towers,
  traffic signals and lamps where streets have them.

## What differs, view by view

**times_square**
- Signs: real ones are giant photographic screens filling whole facades,
  with black frames and dark gaps between them; the game's are many smaller,
  flat, saturated panels of invented glyphs, on every street wall to the
  same 40-60 m.
- One Times Square (center) is covered in screens to the top in reality; in
  the game it's bare orange brick above a low sign band.
- The plaza: real dark gray pavers, the red TKTS steps, planters, kiosks
  and a dense crowd; the game's is an empty light-gray slab with a handful
  of pedestrians.
- Light: the real canyon is in deep shade under a bright sky; the game is
  evenly lit and brighter (mean value of the lower half 0.36 vs 0.27).
- Since this run (improvement 11, ROADMAP "Times Square, closer to the real
  one"): bigger screens fitted to each face in black cladding, ads drawn like
  photos, One Times Square stacked with screens to the top, the red TKTS
  steps, benches, twice the crowd. Still different: the plaza's paving, the
  canyon's light, and real photographic content.

**fifth_ave_esb**
- Marble Collegiate Church is drawn as a 65 m tall cream box with office
  windows that fills the left half of the view. Its footprint height is the
  steeple's tip; the city's 3-D model has the real church (47 m with the
  steeple) but was rejected by the height check (see improvement 1).
- The Empire State Building matches (center right, right size).
- Neighbors: real brown and gray brick and limestone, darker and more
  varied; the game's are cream and tan with even window grids.
- Real: bare March trees, a construction fence, cars and people; game:
  full low crowns and empty streets. Overcast vs. clear sky.

**flatiron**
- The Flatiron matches in place, height and shape, but has a water tower
  on its roof (the real one shows none).
- The tower at left is the right size; it's dark gray-brown brick with
  balconies in reality, bright orange brick in the game.
- The plaza: real Citi Bike dock (about 40 bikes), planters, umbrellas,
  kiosks and crowds; the game's is plain pavement (the outline is right).

**park_ave**
- The MetLife Building, the end of the vista, is missing: its footprint
  record (shared with Grand Central) is 48 m tall, and the 3-D model's
  242 m shape was rejected by the height check. The game shows sky there.
- The median is paved and lined with full-size trees that wall off the
  vista; the real one is planted beds with shrubs and a few small trees.
- The Waldorf Astoria is pale limestone and brick with twin crowns in
  reality, a reddish terracotta-toned slab without crowns in the game. The
  Racquet Club (right) gets a row of storefronts (PLUTO lists retail area)
  instead of its rusticated arcade.
- Parked cars line both curbs in reality. (270 Park Avenue, finished in
  2025, is right to appear in the game; the 2015 photo predates it.)

**totr_south**
- One Vanderbilt (left) is a flat-topped 427 m box over its whole
  footprint; the real tower tapers to a crown and spire. It's the biggest
  error in the skyline.
- The Bank of America Tower (right) is a flat box at 271 m; the real one
  rises to 366 m with its spire (the 3-D model has it, 369 m to the tip,
  but was rejected by the height check). 4 Times Square loses its mast the
  same way.
- Foreground towers are dark glass and gray limestone in reality, light tan
  and beige in the game; real roofs carry mechanical floors and water
  towers.
- Real distance haze is stronger; the game's far city is clearer and
  lighter.

**totr_north**
- Central Park reads as pale flat green with gray patches; the real park is
  dense dark tree canopy edge to edge (trees fade out by about 850 m and the
  canopy map tint is too weak). The park outline and the Reservoir are right.
- 111 West 57th is a fat full-height box over Steinway Hall's whole lot
  (the 3-D model holds its 87 m predecessor); the real tower is a slender,
  tapering blade. 53 West 53rd (no 3-D shape) is a full-footprint blue box
  in front of it; the real one tapers. One57's curved top is stepped (the
  model's roofs are flat levels).
- Real light is sunset gold (the photo is at 19:36); try `?time=19:36` here
  when judging light.

**brooklyn_bridge**
- The real promenade is a raised wooden walkway between the two roadways;
  the game has one flat gray deck.
- The real bridge is a dense web: four main cables, close-set vertical
  suspenders and diagonal stays, steel trusses. The game has two main
  cables and thick, sparse white rods that read as poles; it looks like a
  modern bridge.
- The Manhattan tower is a plain tan block; the real one is granite with
  twin Gothic arches. Cobra-head lamps instead of the historic lanterns.

**dumbo**
- Framing and building heights match.
- The Manhattan Bridge tower is a white plain portal; the real one is
  riveted blue steel with an arched portal and ornament. The deck is a thin
  slab; the real one is a deep stiffening truss.
- The tower stands about 25 m from its real place: it shows about 6 degrees
  left of Washington Street's axis instead of slightly right (main spans
  are centered over the water; step 8 fixes tower positions).
- The warehouses are red brick lofts in reality, tan brick with continuous
  storefronts in the game. The street is Belgian block (cobbles) in reality,
  asphalt with a high-visibility crosswalk in the game.

**promenade**
- Skyline width and heights are broadly right, but One World Trade Center
  is a flat-topped box without its taper or spire (the 3-D model, 548 m to
  the spire tip, was rejected by the height check), and other towers lack
  their crowns. Real towers range from black glass to limestone; the game's
  are similar gray-blue boxes.
- Foreground: Brooklyn Bridge Park (planted berm, marina, Pier 5) is bare
  paving with a couple of blocks; the piers' lawns aren't in the parks
  layer (the berm is).
- Water is light blue with ripple lines in the game, darker gray-blue in
  reality; the clear sky is a deeper blue in reality.

**park_slope**
- The brownstones are bright red brick with white lintels; the real row is
  chocolate brownstone (saturation 0.63 vs 0.31).
- The defining features are missing: stoops, areaway walls and railings,
  bay windows, deep bracketed cornices.
- Street trees: real tall London planes with high crowns (bare in April);
  the game's crowns are low, dense and dark, and fill the top of the frame.

**queens_ridgewood**
- These attached rowhouses are typed as detached houses, so the game gives
  them gable roofs, siding colors and plain fronts. The real row is buff
  brick with rounded bow fronts, flat roofs with pressed-metal cornices,
  stoops and iron fences on pyramid-capped posts.
- The brick is red-orange in the game (saturation 0.61), buff in reality
  (0.24). Real houses sit behind 3 m areaways; the game's are at the
  sidewalk. Overhead wires and utility poles are missing.

**grand_concourse**
- Layout matches closely.
- The malls between the main road and the service roads are planted (grass,
  shrubs, trees) in reality and gray paved islands in the game.
- Lamps: the Concourse's ornate twin-arm historic posts vs. cobra-heads.
- Buildings: real six-story dark brown and tan brick prewar apartments;
  the game's are cream and red-orange, lighter.
- Real traffic (cars, a bus) gives the road its scale; the game's is empty.

**st_george**
- The terminal's three big slips (dark brick with steel gantries) are
  missing; the waterfront is a long red-brick block.
- The wooded hill rising behind St. George doesn't read: no tree mass at
  this distance, and the buildings form an even band.
- Sky and water: overcast and silver in the photo; the game is always
  clear blue.

## Across all views (measured)

- The lower half of the frame (buildings and street) is brighter in the
  game: mean value 0.45 vs 0.37 over the 13 views. Saturation is about the
  same overall but doubles on residential brick (0.61-0.63 vs 0.24-0.31 in
  Park Slope and Ridgewood) and is far lower on the bridge and towers.
- The clear-day sky near the zenith is about #88A3BE in the game; clear
  photos show about #7190D1. 4 of 13 photos are overcast; the game has no
  overcast.
- Data checks behind the findings (from `data/cache`):
  - **3-D shapes rejected by the height check** (model and footprint
    heights differ by more than max(6 m, 25%)): 4,746 buildings whose model
    is taller (422 of them over 50 m, 28 over 100 m: the MetLife Building,
    One World Trade Center's spire, the Bank of America Tower, 4 Times
    Square, MoMA / 53 West 53rd, Carnegie Hall's block), and 335 whose
    footprint is taller (spires counted as roof height: Marble Collegiate
    and other churches).
  - **Towers with no 3-D shape at all** (newer than the model): 82 of 284
    buildings over 150 m and 41 of 94 over 200 m (One Vanderbilt, Central
    Park Tower, 111 West 57th, the Hudson Yards towers, 270 Park Avenue).
  - **Attached houses typed as detached**: of 601,000 buildings typed
    "house", 79,000 share walls on two sides (rows like Ridgewood's), most
    in Brooklyn (27% of its houses), the Bronx (20%) and Queens (10%).

## Improvements, in priority order

| # | What | Effort | Where |
|---|------|--------|-------|
| 1 | (done 2026-10-15) **Accept the 3-D model when the footprint height is the odd one out.** Compare the footprint height with the model's main roof (area-weighted roof level or a high percentile of roof levels) instead of its tip, so spires and masts stop failing the check; take the model when the outlines overlap well and the model is taller (a footprint record shared with a low podium, like MetLife's with Grand Central); for institutions, accept a model shorter than a footprint height that is really a steeple tip. Keep rejecting models much shorter than today's building (replaced buildings, like 111 W 57th's 87 m predecessor). Check MetLife, One WTC, the Bank of America Tower, 4 Times Square, Marble Collegiate, 111 W 57th. | small | `tools/citygen/build_tiles.py` (`_shape_matches`) |
| 2 | (done 2026-10-15) **Massing for supertalls newer than the model** (41 of 94 buildings over 200 m): today full-footprint boxes up to the spire tip. A small table of the ~40 tallest (height to roof, setbacks or taper, crown, spire) with parametric shapes, or fold them into the landmark set. One Vanderbilt, Central Park Tower, 111 W 57th, 53 W 53rd, Hudson Yards, 270 Park first. | medium | `tools/citygen` (new table), step 6 landmarks |
| 3 | (done 2026-10-15) **Attached houses to the rowhouse type**: PLUTO's ProxCode (attached / semi-attached) or shared walls between footprints; no pitched roof on attached rows; flat roof with cornice. About 79,000 buildings. | small | `tools/citygen/facades.py`, pitched-roof test in `build_tiles.py` |
| 4 | (done 2026-10-16) **Facade palette and brightness**: darker, less saturated brick overall; brownstone for rowhouses in Brooklyn and Harlem historic districts; buff and tan brick for Queens and Bronx rows and Bronx apartments; red brick for industrial lofts; darker glass for midcentury and modern offices; limestone for prewar towers like the Waldorf. Aim for the measured photo values (lower-half value about 0.37, brick saturation about 0.3). | small-medium | `shaders/building.gdshader` palettes, `facades.py` tones |
| 5 | (done 2026-10-16) **Street tree shape**: raise the crown base with trunk size (planes and oaks clear about 4-6 m), lighter and more open crowns, smaller young trees; they currently wall off streets at eye level. Optional: a bare-branch winter look. | small-medium | `scripts/world/prop_meshes.gd`, `tools/citygen/props.py` |
| 6 | (done 2026-10-16) **Planted medians and malls**: Park Avenue's beds, the Grand Concourse malls, Broadway's malls uptown: grass and shrub beds instead of paving, fewer full-size trees on narrow medians. | small | `build_tiles.py` median classes, `ground.gdshader`, shrub prop |
| 7 | (done 2026-10-16) **Rowhouse fronts**: stoops, areaway walls and railings, bay and bow fronts, deep bracketed cornices for rowhouses and walk-ups. Drawn in the shader where possible, stoops as props at the door. | medium | `building.gdshader`, `props.py`, `prop_meshes.gd` |
| 8 | (done 2026-10-16) **Distant parks and woods**: darker, bumpier canopy at distance (Central Park from above reads as pale lawn), maybe cheap tree clumps in mid tiles; also reads the wooded hills of Staten Island. | small-medium | `ground.gdshader` canopy tint, mid-tile props |
| 9 | (done 2026-10-16) **Sky, haze and weather**: a deeper clear-day zenith, stronger distance haze, an overcast preset (`?weather=overcast`) to compare with gray-day photos. | small | `shaders/sky.gdshader`, `scripts/world/time_of_day.gd` |
| 10 | (done 2026-10-16, with the Hell Gate and High Bridges; the brooklyn_bridge pose moved to the geotag, on the promenade) **The two Brooklyn bridges as landmarks**: Brooklyn Bridge's granite Gothic towers, four cables with suspenders and stays, raised promenade; Manhattan Bridge's blue steel towers and deep truss; the towers at their real positions (with step 8). | medium-large | `tools/citygen/bridge_landmarks.py` |
| 11 | (done 2026-10-16) **Times Square**: screens up to the top of One Times Square; bigger screens with dark frames and gaps; the red TKTS steps; more pedestrians in plazas. | small | `building.gdshader` sign code, `props.py` box, crowd |
| 12 | (done 2026-10-16: City Planning's Publicly Owned Waterfront, cemeteries; lawn where the land cover shows grass) **Parks missing from the parks layer**: Brooklyn Bridge Park's piers (and likely other parks not run by the Parks Department, e.g. Hudson River Park's piers) are bare paving. Add them from another source. **Done** (City Planning's Publicly Owned Waterfront, cemeteries; lawn where the land cover shows grass). | small-medium | `tools/citygen/fetch_data.py` / `prepare.py` |
| 13 | **Parked cars and traffic** (in progress): every street photo is lined with parked cars; without them streets look wider and emptier than they are. | in progress | traffic work |
| 14 | **Waterfront landmarks**: the St. George ferry slips (and the Manhattan terminal), piers with their sheds. | medium | landmarks |
| 15 | (done 2026-10-16: the DOT's plazas; cobbled streets by name) **Special pavements**: Belgian block in DUMBO and parts of SoHo and the Meatpacking District, pavers in plazas (Times Square, Flatiron). A hand-made list of areas, like the sign district box. **Done** (the DOT's plazas; a list of cobbled streets by name). | small | `ground.gdshader`, `props.py`-style box list |

Smaller things seen once: a water tower on the Flatiron's roof (skip water
towers on landmarks), storefronts on the Racquet Club (PLUTO's retail area
isn't always a shopfront; skip them on landmark institutions), cobra-head
lamps on the Grand Concourse (historic posts on designated boulevards; done).
