# Reference views: the game next to real photos

Step 6, item 7 ("check against reality"). Sixteen viewpoints a player
actually sees, each a free-licensed photo from Wikimedia Commons next to the
game at the same camera pose. Re-run after each phase; the differences below
drive the next work. Newest round first: round 3 (2026-10-16) and its
improvements table, then round 1 (2026-10-15) and its table, now nearly all
done.

## How to run

```
tools/citygen/.venv/Scripts/python.exe tools/reference/compare.py
```

It downloads any missing photo to `build/reference/photos/` (gitignored;
photos are never committed), screenshots https://nycheroes.party at every
view in headless Chrome (`tools/reference/shoot.mjs`, CDP port 9384), and
writes photo | game pairs to `build/reference/compare/<label>/<view>.jpg`
plus `_all.jpg` (every view on one sheet) and `measures.md` /
`measures.json` (below). Options:

- `--site http://localhost:8060/index.html` to check a local build (serve
  `build/web` over HTTP first; see ROADMAP "Working on the project").
- `--label NAME` names the output folder (default `<host>-<date>`).
- `--also live-20261015,facades-after` adds earlier runs' screenshots as
  middle columns (before | after), and measures them too.
- `--only times_square,flatiron` for a few views; `--skip-shots` to
  recompose from the screenshots already taken. An `--only` run into an
  existing label keeps the other views' rows in `report.json` and
  `measures.json`.
- `--query weather=overcast` (or `time=19:00`, ...) adds launch options to
  every view, to match a photo's weather or light under its own label.
- `--profile %TEMP%\reference\chrome-profile` keeps Chrome's cache and
  shader cache between runs: every view then loads in 5-7 s. A fresh
  profile (the default, deleted afterwards) downloads the game and its
  first tiles (about 100 MB) and compiles the shaders: about 22 s for the
  first view.
- `--port` picks the DevTools port (default 9384) when other headless
  Chromes are running.
- `--pose LAT,LON,HEADING[,PITCH[,EYE]]` prints a `?cam=` pose for a
  photo's position and compass heading (uses `data/cache/terrain.npy` for
  the ground height), for adding views.

A run takes about 2 minutes with a warm profile (16 views). Every view
loads `?cam=...&spawn=...&quality=high&gangs=0` at 2560x1440 and waits for
the game's "[city] ... ready" log plus 6 s for trees and props.

**Measures.** For each view, on the photo's and each game run's crop
(same field of view; shrunk to 480 px high): `lower_v`, the mean HSV value
of the lower half (buildings and street); `lower_v_sd`, its spread
(contrast, deep shade); `lower_s`, mean saturation there; `warm_s`, the
median saturation of warm pixels (hue under 50 degrees: brick, brownstone,
tan stone) and `warm`, their share; `green`, the share of foliage and lawn
(it also counts green paint, like the els); `edges`, the share of the lower
half on a strong edge (detail and clutter); `top`, the median color of the
top 5% (the sky, where there is sky). The mean row covers only the views
every column has. Round 1's "lower half 0.45 vs 0.37" is the same
`lower_v`.

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
to eyeball a top-down view. A feature's offset from the photo's center
gives its bearing off the camera's axis: atan(offset / f), with f = half
the photo's width / tan(hfov / 2) in pixels; two such features, or one plus
its known height, fix the position. To try several poses in one go, put
variants in a scratch copy of `views.json` and run `shoot.mjs --views` on
it. Note how in `pose_note`.

**Caveats.** Photos are from different seasons, times and weather (several
show bare March/April trees, overcast skies, rain or sunset light); the
game runs at its default 15:30 on a clear day unless `--query` says
otherwise. Judge shape, placement, scale and palette, and treat light and
foliage differences with care. For light, shoot the gray-day photos
(fifth_ave_esb, totr_south, grand_concourse, st_george, roosevelt_ave) again
with `--query weather=overcast`, and totr_north with `--query time=19:00`:
without `?date` the game's sun keeps April 6's arc (solar noon 12:59), so
the photo's 19:36 in August (sun 4 degrees up) is 19:00 in the game, and
19:36 is already dusk there; `--query "date=2022-08-10&time=19:36"` puts
the sun where it was for the photo (the same light, measured within 0.01).
roosevelt_ave's street is wet and mirrors the sky, so its lower half
measures bright (0.59): compare it by eye. Traffic is live: a bus can drive
through a camera that stands in a roadway (grand_concourse, roosevelt_ave)
and block the view; shoot that view again.

## The views

Runs (labels under `build/reference/compare/` and `shots/`):
- round 1, `live-20261015`: the live site on 2026-10-15 (tile format v6);
- round 2, `facades-after`: a local build of the facade work, early
  2026-10-16, the only one of the per-feature checks (`looks-*`,
  `towers-after`, `facades-*`) with all 13 views;
- round 3, `live-20261016`: the live site on 2026-10-16 (tile format v7,
  build `6ad1e882`), its sheets photo | round 1 | round 2 | round 3, plus
  `live-20261016-overcast` (the gray-day photos with `weather=overcast`)
  and `live-20261016-sunset` (totr_north with `time=19:00`).

The last three views were added in round 3 (an el street with Queens shops,
and two landmarks); their photos are also listed in `CREDITS.md`.

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
| roosevelt_ave | Roosevelt Ave at 82nd St, Jackson Heights, under the 7 | `8557,21.9,1151.5,-53.0,0.0` | [82 Street vc](https://commons.wikimedia.org/wiki/File:82_Street_vc.jpg) (2009) | Doug Letterman, [CC BY 2.0](https://creativecommons.org/licenses/by/2.0) |
| st_patricks | St. Patrick's Cathedral from Fifth Ave at Rockefeller Center | `703,23.1,-105,-119.0,45.0` | [Saint Patricks Cathedral in New York - NYC - USA - panoramio](https://commons.wikimedia.org/wiki/File:Saint_Patricks_Cathedral_in_New_York_-_NYC_-_USA_-_panoramio.jpg) (2010) | diego_cue, [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) |
| guggenheim | The Guggenheim from Fifth Ave at 88th St | `2188.5,34.7,-2756.5,-68.0,14.0` | [NYC - Guggenheim Museum](https://commons.wikimedia.org/wiki/File:NYC_-_Guggenheim_Museum.jpg) (2012) | Jean-Christophe BENOIST, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0) |

The images are for comparison only. If any are ever shown publicly, credit
them as in this table (and `CREDITS.md`) and keep the share-alike terms.

## Round 3 (2026-10-16)

The live site after facade materials and stoops, ground details, the four
landmark bridges, Times Square, the second batch of landmarks, newer
towers' massing, elevated lines, parked cars and traffic, and the trees,
parks and sky work. Images:
`build/reference/compare/live-20261016/<name>.jpg` (photo | round 1 |
round 2 | round 3), measures in `measures.md` there.

### Measured

Means over the 13 views every round has:

| Measure | Photos | Round 1 | Round 2 | Round 3 |
|---------|--------|---------|---------|---------|
| Lower half, mean value | 0.37 | 0.45 | 0.42 | 0.41 |
| Lower half, contrast (spread of value) | 0.20 | 0.17 | 0.17 | 0.17 |
| Lower half, saturation | 0.27 | 0.33 | 0.29 | 0.31 |
| Masonry (warm pixels), saturation | 0.27 | 0.36 | 0.27 | 0.30 |
| Strong-edge share (detail, clutter) | 0.222 | 0.108 | 0.094 | 0.091 |
| Clear sky at the top (promenade) | #6C8BCD | #7C9EBE | #769CCE | #769CCE |

The four gray-day photos (fifth_ave_esb, totr_south, grand_concourse,
st_george) against the game's clear day and `?weather=overcast`
(`live-20261016-overcast`): lower half 0.41 in the photos, 0.48 clear, 0.50
overcast; contrast 0.20, 0.15, 0.13; the top of the frame #D4D8DE-#E1DED5
in the photos, #9BA0A7-#B4B7BA in the game's overcast.

### What improved

- **Skyline massing**: One Vanderbilt tapers to its crown and spire, the
  Bank of America Tower has its spire, 53 West 53rd its spiky crown, the
  MetLife Building closes Park Avenue's vista, One World Trade Center has
  its taper and spire from the Promenade. 520 Fifth Avenue (2025) stands
  where the 2024 photo has none, rightly.
- **Bridges**: the Brooklyn Bridge's web of cables, suspenders and stays,
  the raised wooden promenade and lanterns (lower half 0.51 in round 1,
  0.33 now, the photo 0.33); the Manhattan Bridge's blue steel tower with
  its X bracing and arched portal under DUMBO's arch, at its real place, and
  the deep truss deck.
- **Facades**: Ridgewood's rows are buff brick with flat roofs, cornices
  and railed stoops (masonry saturation 0.90 in round 1, 0.32 now, the
  photo 0.37); Park Slope is brownstone with stoops, bays and deep cornices
  (0.85, now 0.61, the photo 0.26); DUMBO's lofts are red brick; the Marble
  Collegiate site is no longer a 65 m office box.
- **Landmarks**: the Flatiron (its prow and cornice, no water tower); St.
  Patrick's spires and the Guggenheim's rotunda, Monitor and annex stand
  at the right size and place (new views).
- **Ground**: Park Avenue's median and the Grand Concourse's malls are
  planted; Times Square is dark pavers; Washington Street in DUMBO is
  cobbled.
- **Street life**: parked cars line the curbs where the data has parking
  lanes (Fifth and Park Avenues), taxis and buses drive; Times Square has a
  crowd.
- **Times Square**: screens in black cladding to the top of One Times
  Square; the canyon is a little darker (0.35, now 0.32, the photo 0.27).
- **Sky and weather**: the clear-day sky matches the clear photos; the
  overcast preset's gray deck, gray water and soft light read like the
  gray-day photos.

### What still differs, view by view

**times_square**
- The screens are flat, saturated graphics (red, green and orange fields,
  invented glyphs): the lower half is twice as saturated as the photo's
  (0.37 vs 0.18). Real ads are photos, mostly dark and muted, a few bright.
- Pedestrians are mannequins in one solid color each (white, orange, blue
  bodies); next to the photo's people in dark coats and jeans they read as
  crash-test dummies.
- Missing: the sidewalk shed on the left, the food kiosk and stands, the
  litter of signs and poles. The dark glass towers on the west side come
  out tan stone.

**fifth_ave_esb**
- Marble Collegiate Church reads as a beige seven-story apartment block
  with a white apartment tower: the 3-D model's nave and tower get floors
  and office windows. No steeple, no stone, no pointed windows. The facade
  types have no church.
- The street wall is lighter and paler than the real brown brick and
  brownstone (lower half 0.37 vs 0.29; warm share 0.36 vs 0.68).
- With `?weather=overcast` the sky matches, but the street gets brighter
  (0.49) instead of darker: the real gray day is in deep shade at street
  level.

**flatiron**
- The Flatiron is cream-yellow; the real one is gray-beige limestone and
  terracotta. The lower half is much brighter (0.37 vs 0.23).
- The photo stands on a plaza with a Citi Bike dock (about 40 bikes),
  planters and umbrellas, with a sidewalk shed on the right; the game looks
  across asphalt and crosswalks to the Flatiron, though the camera is
  inside the DOT's Worth Square plaza outline (and 2 m from the Flatiron
  plaza's): check that the plazas between 23rd and 25th Streets get their
  pavers.
- Street trees are bright lime green.

**park_ave**
- Parked cars line both curbs in the photo; the game has a few, and few
  moving cars.
- The Waldorf Astoria is still salmon-pink brick (real: pale limestone and
  tan brick). The Racquet Club is a beige office grid (real: a rusticated
  palazzo with tall arched windows). MetLife is a plain gray box (real: an
  elongated octagon with its name on top).

**totr_south**
- The city past a few hundred meters is smooth: strong-edge share 0.06 vs
  0.37, six times less. Window grids fade to flat color, roofs are bare (no
  bulkheads, water towers, terraces), and the haze washes the far city pale.
  Towers are tan and beige where real ones are gray, black glass and
  limestone.

**totr_north**
- Central Park is still pale lawn with paths from 280 m; the real park is
  dense dark canopy edge to edge. The far crowns don't show here.
- 111 West 57th is a pale stick; from the south it is dark glass with
  bronze bands (the terracotta is on its east and west faces).
- At the photo's sun height (`time=19:00`) the game's sky is a flat mauve
  up to the zenith and the city pink-gray; the real sky stays blue overhead,
  with gold light on the towers and blue shade.

**brooklyn_bridge**
- Too saturated and too orange: lower half saturation 0.46 vs 0.29,
  masonry-hue saturation 0.55 vs 0.28. The real steel is a muted gray-tan,
  the planks weathered gray-brown.
- The trusses between the promenade and the roadways read as solid brown
  walls; the real ones are open lattice, with the roadway and its cars
  seen through them. The nearest cables are thick, like planks.

**dumbo**
- The tower is bright, flat sky blue; the real steel is dark blue-gray, a
  lattice with deep shadow. The brick is too saturated (0.51 vs 0.36).
- The lofts' ground floors are continuous storefronts with sign bands
  (real: brick with windows and doors), there are no fire escapes (the
  photo's right building has a full stack), windows are flat rectangles
  (real: segmental arches in deep reveals), a crosswalk is painted on the
  cobbles, and the street is empty (real: a crowd of tourists).

**promenade**
- The foreground is light bare paving with lamp posts and a lone conifer
  where the photo has the planted berm, trees, the marina and Pier 5.
- Water is light blue with even ripple stripes; the real river is dark gray
  blue. The skyline is uniform gray-blue boxes with low contrast (edges
  0.07 vs 0.31); real towers run from black glass to white limestone, crisp
  at 1-2 km on a clear day.

**park_slope**
- Brownstone, but 2.3 times too saturated (0.61 vs 0.26): orange-red where
  the real stone is chocolate brown; one front is bright red brick.
- The stoops are solid masses without iron railings (Ridgewood's have
  them), and there are no front-yard walls or plantings. Street trees still
  start low and are bright lime green.

**queens_ridgewood**
- The fronts are flat or square; the real ones are rounded bow fronts. The
  cornices are thin bands (real: deep pressed metal, painted white).
- Missing: the iron fences on brick posts with pyramid caps, the striped
  metal door awnings, overhead wires and poles. The camera seems 2-3 m too
  close to the houses: check the pose.

**grand_concourse**
- The buildings are bright red-orange brick (real: brown and tan, six
  stories, carved entrances); traffic is sparse (a handful of cars where
  the photo shows a dozen or more); single lanterns where the real posts
  are ornate twin-arm; lime green trees.

**st_george**
- Unchanged: no ferry slips (a long red-brick block on the water), no
  wooded hill behind the town, light blue striped water. With
  `weather=overcast` the tones are right but the deck is darker than the
  photo's bright gray (#B4B7BA vs #E1DED5).

**roosevelt_ave** (new)
- Matches: the 7's deck over the street, bents with columns at the curbs,
  two- and three-story shop buildings, the cross street.
- The el is a smooth, evenly lit, mid-green slab on plain columns (it is
  38% of the frame, all counted as "green"); the real one is a dark, rusty
  teal lattice of riveted girders, the street under it in deep shade with
  light through the gaps.
- The real street is a wall of big, bright, mismatched shop signs, awnings,
  banners and signs on the upper floors; the game has one uniform shop band
  with small glyph signs. A busy sidewalk and about ten cars against an
  empty street; no station stairs.

**st_patricks** (new)
- Matches: the spires' place and height, the front's width.
- The cathedral is flat white with a rainbow rose window and plain dark
  lancets: a toy. The real front is gray-tan marble, mostly in shade (lower
  half 0.35 vs 0.64), covered in pinnacles, crockets, tracery and gables
  over three portals; the spires are openwork. The Olympic Tower at left is
  dark glass (the game's is white with blue bands).

**guggenheim** (new)
- Matches: the rotunda's size and place, the Monitor, the annex, the
  brightness (0.48 vs 0.51).
- The bands are faceted (about ten flat faces in view) and the shaded side
  turns beige; the real rotunda is smooth, and cool gray in shade. The low
  band with the museum's name and the recessed lobby read as a glass ground
  floor.

### Across all views

- **Brightness**: the lower half went from 0.45 to 0.41 (photos 0.37):
  half the gap. What's left is in the canyons and under structures:
  Times Square, the Flatiron, Park and Fifth Avenues, under the el. The
  game has no deep shade, so its contrast stays at 0.17 against 0.20.
- **Saturation by material**: right on average (0.30 vs 0.27) but not by
  material: brownstone, DUMBO's red brick, the Brooklyn Bridge's steel, the
  Manhattan Bridge's blue, the el's green and Times Square's screens are
  too saturated; Ridgewood's buff is right; Midtown's stone is a little
  dull (Park Avenue 0.15 vs 0.25).
- **Detail**: the strong-edge share went down a little each round (0.108,
  0.094, 0.091) against the photos' 0.222. A cartoony look should stay
  below the photos, but the biggest gaps are views from above and across
  water (four to six times), where the far city loses its windows and
  roofs, and street views where the photos' clutter is people, cars, signs
  and awnings.
- **Light**: the clear day is right; shade on white surfaces is warm beige
  where the photos' is cool gray (the toon shading's warm bounce); the
  overcast street is too bright and flat; dusk loses the blue sky.
- **Street life**: parked cars are in, but moving traffic is sparse and
  pedestrians are few (outside Times Square) and look like mannequins.
- **Landmarks** are in the right place at the right size and read as
  simplified toys up close: flat white or cream, no ornament, faceted
  curves, bright rainbow glass.

## Improvements after round 3, in priority order

Ranked by how far each would move the look toward the photos for its
effort; numbered on from round 1's table. Shader compile time: see ROADMAP
"Shader compile time" (Times Square about 20 s to ready on the dev machine,
building.gdshader's color variant under about 10 s, every other shader under
about 2 s; check with `tools/shader_compile_check.mjs`).

| # | What | Effort | Where |
|---|------|--------|-------|
| 16 | (done 2026-10-16; street trees with 20: darker, less saturated, a little cooler greens, foliage saturation 0.77 to 0.60 and value 0.29 to 0.19 in six street views, the photos 0.44 and 0.18) **Color pass on the materials that stand out**: brownstone toward chocolate (masonry saturation 0.61, aim about 0.3), DUMBO's red brick (0.51, aim 0.36), the Brooklyn Bridge's steel and planks (0.55, aim 0.3: gray-tan and weathered gray-brown), the Manhattan Bridge's and the els' paint darker and grayer, the Flatiron and St. Patrick's gray-beige stone instead of cream and white, the Waldorf limestone, street trees darker and bluer, water darker gray-blue with fewer stripes, Times Square's screens darker and less saturated on average (0.37, aim about 0.2). Re-measure with `compare.py`. Compile time: values only, no new code. **Done** (`build/reference/compare/colorpass`, against round 3): masonry saturation in Park Slope 0.61 to 0.31, DUMBO 0.51 to 0.37, the Brooklyn Bridge 0.55 to 0.29 (its lower half 0.46 to 0.24); the Manhattan Bridge's tower blue-gray (saturation 0.50 to 0.36, value 0.68 to 0.53), the 7's steel dark green-gray (Roosevelt Avenue's green share 0.38 to 0.11); the Waldorf in limestone (landmark apartments and hotels: 90% limestone), the Flatiron and St. Patrick's (and the Library's and the UN's marble) gray-beige; the East River 0.75 to 0.66 in value with lower, softer ripples (rougher water); Times Square's screens about a quarter darker by day in muted ad colors, more of them dark slides and posters, its lower half 0.37 to 0.33. The rest of Times Square's gap is the plaza's blue shade (now 0.18, the photo's pavement 0.06), the green litter bin by the camera, the tickers and shop fronts. The toon light and tone mapping about double a palette's saturation in shade, so these palettes sit at 0.1-0.25. Means of 13: lower half saturation 0.31 to 0.27 (photos 0.27), masonry 0.30 to 0.24 (0.27: Midtown's stone and Fifth Avenue's brick were already low). Shader compile time unchanged or lower (Times Square, interleaved on a busy machine: building.gdshader's color variant 24-26 s before, 19-20 s after). | small | `shaders/building.gdshader`, `landmark.gdshader` and `ground.gdshader` palettes, `ocean.gdshader` |
| 17 | (done 2026-10-16: `shaders/npc.gdshader`, banded on the rest pose so poses and ragdolls keep their clothes; thugs keep their gang colors on the joints; 0.1-0.2 s to compile, same draw calls) **Dressed pedestrians**: the mannequin painted in bands by height (shoes, trousers or skirt, shirt or coat, skin on hands and head, hair), in everyday palettes (dark coats, jeans, a few bright tops); today one solid color per body. Compile time: one more small program either way (a textured StandardMaterial3D or a tiny shader that bands by height) for a skinned mesh: check its skinning variant on ANGLE, under 2 s. | small | `scripts/npc/npc_look.gd`, the mannequin material |
| 18 | (done 2026-10-16) **Light at the ends of the day and in gray weather**: keep the zenith blue at a low sun (at `time=19:00` the sky is mauve to the top) with gold light and blue shade on the city; a brighter overcast deck (#9B-#B4 in the game, #D4-#E1 in the photos) over darker, more contrasty streets (0.50 vs 0.41); cooler shade on light surfaces (now beige). Compile time: keyframes and uniforms; the sky shader is small. **Done** (`build/reference/compare/day-light-sunset`, `day-light-overcast` and `day-light`, against round 3 and master after the color pass): at `time=19:00` the sky stays blue overhead (the top of the frame #948187 to #9AB1CC; the photo's blue #95B7CD) over a pale horizon, warm under the sun, with peach clouds, gold sunlight on the west faces and blue-gray shade; totr_north's lower half 0.36 to 0.40 (the photo 0.42), contrast 0.14 to 0.17 (0.21), warm share 0.70 to 0.41 (0.21), but saturation 0.24 to 0.17 (0.33: the photo is vivid). Overcast: the deck #9B-#B4 to #CC-#D8 (photos #D4-#E1), the gray-day views' lower half 0.50 to 0.42 (photos 0.41), contrast 0.13 to 0.16 (0.20). The Compatibility renderer clamps the 3-D buffer at 1.0 before tone mapping, so with the default AgX white no sky gets past about #C5-#CC however bright its colors; the overcast look lowers AgX white to 2.0 (its minimum), which lifts the top and leaves mid-tones alone. Shade: the walls' ground bounce is a light gray instead of warm, so the Guggenheim's shaded side goes from tan #9B8F7F to gray #959086; a bluer shade (tried) turned brownstone and St. Patrick's marble gray, as the color pass's palettes count on some warmth there. Clear-day means of 13: lower half 0.40 either way, masonry saturation 0.24 to 0.23 (Park Slope 0.31 to 0.23, the photo 0.26; DUMBO 0.37 to 0.34, 0.37; the Brooklyn Bridge 0.29 to 0.26, 0.28), warm share 0.33 to 0.28 (0.30); St. Patrick's front, in shade, went from warm (0.60) to gray (0.18; the photo 0.45). Sun path: `?date=MM-DD` puts the sun on New York's arc that day (without it, April 6's). Shader compile time unchanged: values only, so the compiled shaders are byte for byte the same (all 110 programs at Times Square at 19:00, hashed; 21-35 s to ready before and after, interleaved on a busy machine). | small | `shaders/sky.gdshader`, `scripts/world/time_of_day.gd`, `toon.gdshaderinc` |
| 19 | **Busy streets**: more moving cars on avenues and boulevards (the photos show a dozen or more in view where the game has a handful), and pedestrians by retail frontage and subway entrances, not only in Times Square's plazas (Roosevelt Avenue, DUMBO, the Flatiron, Fifth Avenue). Watch the frame time on low and medium. | small-medium | `scripts/world/traffic.gd`, `scripts/npc/crowd_manager.gd`, `scripts/util/quality.gd` |
| 20 | (done 2026-10-16: the painted woods did draw, but seen at a slant their crowns fade to a flat green by about 1.5 km, and paths and far tiles' wooded lots are paving; now clumps of crowns stand in tiles of every level, from the land cover map, grown in by the trees' shader from 600-800 m; the park's pixels spread 0.050 in value, from 0.023 (the photo 0.11), the rest is haze, see 25; high +26 draw calls, +0.7 M triangles and +0.2 ms a frame at Top of the Rock, medium +19 draw calls and +0.1 ms, low none; tiles +55 MB, far tiles +13%; compile time unchanged) **Central Park and wooded hills as canopy from above**: from Top of the Rock the park is still lawn and paths, and Staten Island's hill has no tree mass; find why the far crowns don't draw at 1-4 km and draw them. | small-medium | `shaders/tree.gdshader`, `ground.gdshader`, `scripts/world/city_props.gd` |
| 21 | **Shade under decks and in canyons**: darken the ground and lower walls under el decks and bridge approaches (the roadbed cut already knows the outlines) and down narrow, tall streets (street width against wall height), toward lower half 0.37 and contrast 0.20. Compile time: one more term in building.gdshader, its biggest shader: bake it per vertex in the tiles and apply it once in the shared lighting path, not in each facade branch. | medium | `tools/citygen/build_tiles.py`, `ground.gdshader`, `building.gdshader` |
| 22 | **Landmarks in stone, not toys**: St. Patrick's gray-tan marble with pinnacles, crockets, gables over the three portals, openwork spires and a muted rose window; the Guggenheim's bands smooth (more segments) and white-gray; check the other landmarks the same way (a view each). Compile time: landmark.gdshader compiles only when a landmark is in view; keep it under 2 s. | small-medium | `tools/citygen/landmarks.py`, `shaders/landmark.gdshader` |
| 23 | **Shop signs and awnings**: on retail frontage, sign boards of varied sizes and colors, fabric and aluminum awnings, banners and a few upper-floor signs on commercial streets (Roosevelt Avenue and its kind in every borough); fewer continuous storefronts on lofts. Compile time: as instanced props with a small shader of their own; growing building.gdshader's storefront code would add to its compile time. | medium | `tools/citygen/props.py`, `scripts/world/prop_meshes.gd`, `facades.py` |
| 24 | **Sidewalk sheds**: green plywood-and-pipe sheds over the sidewalk (two of the 16 photos have one; the city has thousands up at any time), from the Department of Buildings' sidewalk shed permits on NYC Open Data. Compile time: reuse the street furniture shader. | small-medium | `tools/citygen/fetch_data.py`, `props.py`, `prop_meshes.gd` |
| 25 | **Detail at a distance**: window grids and dark glass kept out to 2-3 km (a cheap far pattern), roof bulkheads and water towers on mid tiles, less haze within 3 km on a clear day (with `?fog=0.00003` Central Park's canopy from Top of the Rock measures close to the photo's: value 0.34 vs 0.42, saturation 0.29 vs 0.34; at the default fog 0.47 and 0.18); the strong-edge share from Top of the Rock and the Promenade is 0.06-0.07 against 0.31-0.37. Compile time: building.gdshader's far path; measure before and after. | medium | `building.gdshader`, `build_tiles.py` (mid-tile roofs), `time_of_day.gd` fog |
| 26 | **The els' steel**: lattice girders and rivets painted on the flat faces, dark undersides, the stairs from the street up to the stations (the MTA's entrances data, already fetched). Compile time: painting in the shared steel code of landmark.gdshader. | small-medium | `tools/citygen/els.py`, `landmark.gdshader` |
| 27 | **Churches**: houses of worship (PLUTO building class M) in stone with tall pointed windows, no floor grid, steep roofs, the 3-D model's towers as belfries with spires; today Marble Collegiate and the city's other churches read as apartment blocks. Compile time: a new facade type grows building.gdshader; make it a variant inside `facade_for()`, or give churches their own surface and shader. | medium | `tools/citygen/facades.py`, `building.gdshader` or a separate surface |
| 28 | **Waterfront landmarks** (round 1's 14): the St. George ferry slips and the Whitehall terminal, piers with their sheds, Brooklyn Bridge Park's planted berm and marina. | medium | `landmarks.py`, `ground_details.py` |
| 29 | **Rowhouse fronts, second pass**: iron railings on brownstone stoops, front-yard walls and plantings, rounded bow fronts in Ridgewood, deeper painted metal cornices, iron fences on brick posts, door awnings. | medium | `tools/citygen/fronts.py`, `building.gdshader` |
| 30 | **Overhead wires and wooden utility poles** on house streets in Queens, the Bronx and Staten Island (no data: along streets lined with houses). | small-medium | `props.py`, `prop_meshes.gd` |
| 31 | **Citi Bike docks and plaza furniture**: docks from Citi Bike's public station feed (check its data license first), umbrella tables, planters and kiosks on the DOT's plazas. | small | `fetch_data.py`, `props.py` |

Smaller things seen once: the Flatiron plazas drawn as asphalt (above);
the Ridgewood camera may stand 2-3 m too close to the houses; 111 West
57th's south face (dark glass and bronze, not terracotta); the
Guggenheim's ground floor (the name band and the recessed lobby).

## Round 1 (2026-10-15)

The live site with tile format v6 (no cars yet); 13 views. Images:
`build/reference/compare/live-20261015/<name>.jpg`.

### What matched

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

### What differed, view by view

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

### Across all views (measured)

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

### Improvements after round 1, in priority order

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
| 13 | (done 2026-10-16; moving traffic still sparse: round 3's 19) **Parked cars and traffic**: every street photo is lined with parked cars; without them streets look wider and emptier than they are. | in progress | traffic work |
| 14 | (open; carried over as round 3's 28) **Waterfront landmarks**: the St. George ferry slips (and the Manhattan terminal), piers with their sheds. | medium | landmarks |
| 15 | (done 2026-10-16: the DOT's plazas; cobbled streets by name) **Special pavements**: Belgian block in DUMBO and parts of SoHo and the Meatpacking District, pavers in plazas (Times Square, Flatiron). A hand-made list of areas, like the sign district box. **Done** (the DOT's plazas; a list of cobbled streets by name). | small | `ground.gdshader`, `props.py`-style box list |

Smaller things seen once: a water tower on the Flatiron's roof (skip water
towers on landmarks), storefronts on the Racquet Club (PLUTO's retail area
isn't always a shopfront; skip them on landmark institutions), cobra-head
lamps on the Grand Concourse (historic posts on designated boulevards; done).
