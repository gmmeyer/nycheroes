# Reference views: the game next to real photos

Step 6, item 7 ("check against reality"). Sixteen viewpoints a player
actually sees, each a free-licensed photo from Wikimedia Commons next to the
game at the same camera pose. Re-run after each phase; the differences below
drive the next work. Newest round first: round 4 (2026-10-16, closing step
6) and its backlog of remaining gaps, then round 3 (2026-10-16) and its
improvements table, all done, then round 1 (2026-10-15) and its table.

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
  and `live-20261016-sunset` (totr_north with `time=19:00`);
- round 4, `live-20261016-r4`: the live site on the evening of 2026-10-16
  (tile format v7, build `6ad29c41`), its sheets photo | round 1 | round 3 |
  round 4 (round 2's measures are in round 3's `measures.json`: same
  crops), plus `live-20261016-r4-overcast` (photo | round 3 overcast |
  round 4 | round 4 overcast) and `live-20261016-r4-sunset` (totr_north at
  the photo's own sun, `date=2022-08-10&time=19:36`: photo | round 3 at
  19:00 | round 4 | round 4 at dusk). The promenade and queens_ridgewood
  poses changed after round 3's shots (see the table), so those two views'
  earlier columns stand a little differently.

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
| promenade | Lower Manhattan from the Brooklyn Heights Promenade | `-1086,22.0,6948,38.0,0.0` (until 2026-10-16 `-1086,19.6,6948`, inside the fence) | [View across the East River towards Lower Manhattan from the Brooklyn Heights Promenade](https://commons.wikimedia.org/wiki/File:2024-05-22_13_06_18_View_across_the_East_River_towards_Lower_Manhattan_from_the_Brooklyn_Heights_Promenade_in_Brooklyn,_New_York_City,_New_York.jpg) (2024) | Famartin, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| park_slope | Park Slope brownstone row | `834,34.7,9675,48.0,12.8` | [Park Slope](https://commons.wikimedia.org/wiki/File:Park_Slope.JPG) (2012) | Mark O'Neill, [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) |
| queens_ridgewood | Ridgewood, Queens: brick rowhouses on 60th Lane | `7672.1,26.2,6637.8,-32.5,10.0` (until 2026-10-16 `7674,26.2,6639`) | [60th Lane Ridgewood](https://commons.wikimedia.org/wiki/File:60th_Lane_Ridgewood.jpg) (2022) | Kidfly182, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| grand_concourse | Grand Concourse at E 170th St, Bronx, north | `6081,35.6,-9032,-27.4,0.0` | [Grand Concourse, Bronx - 20220616](https://commons.wikimedia.org/wiki/File:Grand_Concourse,_Bronx_-_20220616.jpg) (2022) | Andre Carrotflower, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| st_george | St. George, Staten Island, from the ferry | `-6892,10.0,12442,112.5,6.0` | [St. George Ferry Terminal, Staten Island](https://commons.wikimedia.org/wiki/File:St._George_Ferry_Terminal,_Staten_Island,_New_York_City,_20231002_1621_1749.jpg) (2023) | Jakub Hałun, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0) |
| roosevelt_ave | Roosevelt Ave at 82nd St, Jackson Heights, under the 7 | `8557,21.9,1151.5,-53.0,0.0` | [82 Street vc](https://commons.wikimedia.org/wiki/File:82_Street_vc.jpg) (2009) | Doug Letterman, [CC BY 2.0](https://creativecommons.org/licenses/by/2.0) |
| st_patricks | St. Patrick's Cathedral from Fifth Ave at Rockefeller Center | `703,23.1,-105,-119.0,45.0` | [Saint Patricks Cathedral in New York - NYC - USA - panoramio](https://commons.wikimedia.org/wiki/File:Saint_Patricks_Cathedral_in_New_York_-_NYC_-_USA_-_panoramio.jpg) (2010) | diego_cue, [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) |
| guggenheim | The Guggenheim from Fifth Ave at 88th St | `2188.5,34.7,-2756.5,-68.0,14.0` | [NYC - Guggenheim Museum](https://commons.wikimedia.org/wiki/File:NYC_-_Guggenheim_Museum.jpg) (2012) | Jean-Christophe BENOIST, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0) |

The images are for comparison only. If any are ever shown publicly, credit
them as in this table (and `CREDITS.md`) and keep the share-alike terms.

## Round 4 (2026-10-16, closing step 6)

The live site after all of round 3's improvements (16-31: the color pass,
dressed pedestrians, dusk and overcast light, busy streets, canopy from
afar, shade in canyons and under decks, landmarks in stone, shop signs,
awnings and sheds, detail at a distance, the els' steel and stairs,
churches, waterfront landmarks, rowhouse fronts, utility poles and wires,
bike docks and plaza furniture), plus step 8's trains on the els, the BQE's
triple cantilever, sunken roads and viaduct heights from the lidar. Of
step 8's work only the cantilever is in a view (the promenade camera stands
on it, behind its fence); four trains ran on the 7 near Roosevelt Avenue,
none overhead when it was shot. Images:
`build/reference/compare/live-20261016-r4/<name>.jpg` (photo | round 1 |
round 3 | round 4), measures in `measures.md` there; the gray-day and dusk
runs in `live-20261016-r4-overcast` and `live-20261016-r4-sunset`.

### Measured

Means over the 13 views every round has (the "distance" rows are the mean,
over the views, of each view's difference from its own photo, so errors
can't cancel out):

| Measure | Photos | Round 1 | Round 2 | Round 3 | Round 4 |
|---------|--------|---------|---------|---------|---------|
| Lower half, mean value | 0.37 | 0.45 | 0.42 | 0.41 | 0.36 |
| Lower half, distance from each photo | | 0.086 | 0.088 | 0.075 | 0.056 |
| Views within 0.03 of their photo | | 3 | 1 | 2 | 7 |
| Lower half, contrast (spread of value) | 0.20 | 0.17 | 0.17 | 0.17 | 0.17 |
| Lower half, saturation | 0.27 | 0.33 | 0.29 | 0.31 | 0.28 |
| Masonry (warm pixels), saturation | 0.27 | 0.36 | 0.27 | 0.30 | 0.26 |
| Masonry saturation, distance from each photo | | 0.14 | 0.10 | 0.11 | 0.06 |
| Masonry share of the lower half | 0.30 | 0.30 | 0.28 | 0.33 | 0.28 |
| Strong-edge share (detail, clutter) | 0.222 | 0.108 | 0.094 | 0.091 | 0.101 |
| Clear sky at the top (promenade) | #6C8BCD | #7C9EBE | #769CCE | #769CCE | #769CCE |

Over all 16 views, round 3 to round 4: lower half 0.42 to 0.37 (photos
0.39; within 0.03 of its photo: 2 views to 8), saturation 0.30 to 0.28
(0.25), masonry saturation 0.29 to 0.27 (0.26), strong edges 0.095 to
0.104 (0.212).

The four gray-day photos (fifth_ave_esb, totr_south, grand_concourse,
st_george) against `weather=overcast`: lower half 0.41 in the photos, 0.50
in round 3's overcast, 0.40 now (0.42 on the clear day); contrast 0.20,
0.13, 0.16; the top of the frame #D4D8DE-#E1DED5 in the photos,
#9DA1A8-#B4B7BA in round 3, #C8CACF-#D8D8D8 now.

Dusk: totr_north at the photo's own sun (`date=2022-08-10&time=19:36`),
against round 3's `time=19:00` (the same sun height): the top of the frame
#948187 (mauve) to #9BB1CC (the photo's top is cloud, #CACABD; its blue sky
about #95B7CD), lower half 0.36 to 0.39 (0.42), contrast 0.14 to 0.17
(0.20), warm share 0.70 to 0.38 (0.21), strong edges 0.064 to 0.153
(0.336), but saturation 0.24 to 0.17 (0.33).

### What improved since round 3

- **Light and shade** (16, 18, 21, 25): the lower half's mean now matches
  the photos' (0.36 vs 0.37), and not by errors cancelling: seven of the 13
  views are within 0.03 of their photo (two in round 3). Times Square 0.32
  to 0.26 (the photo 0.27), Fifth Avenue 0.37 to 0.28 (0.29), Park Avenue
  0.31 to 0.25 (0.25), Top of the Rock south 0.41 to 0.35 (0.36) and north
  0.49 to 0.44 (0.42), the Brooklyn Bridge 0.33 to 0.30 (0.33), the Grand
  Concourse 0.46 to 0.45 (0.45). The overcast deck is as bright as the
  photos' and the street under it darker, as in them; dusk keeps a blue sky
  over gold light and blue-gray shade.
- **Color by material** (16): masonry saturation in Park Slope 0.61 to
  0.24 (the photo 0.26), DUMBO 0.51 to 0.40 (0.36), the Brooklyn Bridge
  0.55 to 0.26 (0.28; its lower half 0.46 to 0.21, 0.29), Roosevelt Avenue
  0.43 to 0.29 (0.14); the Manhattan Bridge's tower blue-gray, the 7's
  steel dark green-gray (green share 0.38 to 0.05, the photo 0.04), the
  Waldorf in limestone, the Flatiron and St. Patrick's gray-beige.
- **The far city** (20, 25): from Top of the Rock Central Park is dark
  canopy edge to edge (pale lawn and paths in all three earlier rounds),
  and window grids carry to the horizon under less haze: strong edges
  south 0.061 to 0.104 (0.367), north 0.169 to 0.279 (0.336). Staten
  Island's hill is wooded behind St. George.
- **Street life** (17, 19, 23, 24, 31): pedestrians in dark coats, jeans
  and a few bright tops instead of one-color mannequins; a row of cars and
  a cab at Fifth Avenue's crossing, three cabs and a bus at the Flatiron, a
  dozen cars and a bus on the Grand Concourse; planters, bistro chairs and
  umbrellas on the Flatiron plaza, tables and chairs in Times Square; a
  green sidewalk shed on DUMBO's Washington Street, a bike dock on the
  Grand Concourse, named shop signs and awnings under the 7 (a pharmacy, a
  dry cleaner, a noodle house).
- **Churches and landmarks** (22, 27): Marble Collegiate is a gray stone
  Gothic church with its tower, belfry and spire where the photo has them
  (the beige apartment block is gone); St. Patrick's front is built, in
  gray-tan marble (lower half 0.64 to 0.50, the photo 0.35; warm share 0.21
  to 0.64, 0.45); the Guggenheim's bands are smooth and its shaded side
  gray (warm share 0.16 to 0.07, 0.11).
- **The els** (26): under the 7 the steel is riveted lattice over a dark
  deck (the top of the frame #23331E to #050807, the photo #0D100F), and
  the stair up to the 82nd Street station stands where the photo's does.
- **Waterfront** (28): St. George has its slips, terminal and two orange
  ferries where it had a red-brick block (lower half 0.67 to 0.61, the
  photo 0.56; strong edges 0.025 to 0.037, 0.107); from the Promenade, the
  marina's docks and pilings, the piers and a ferry at Whitehall.
- **Rowhouse fronts** (29, 30): Ridgewood's bow fronts, deep painted
  cornices, brick posts with white pyramid caps, striped door awnings and a
  service drop; iron railings on Park Slope's stoops.

### What still differs most, view by view

**times_square**
- The screens are still flat fields of saturated color with invented
  glyphs (lower half saturation 0.36, the photo's 0.18); real screens show
  photographs, most of them dark.
- The shaded plaza pavers are navy blue (#232836, saturation 0.5; the
  photo's pavement is gray). The west side's towers are tan stone where the
  photo's are dark glass; no food kiosk or newsstand in view.

**fifth_ave_esb**
- Marble Collegiate's spire is a short, dark slate pyramid; the real one is
  pale stone, taller, over a clock stage with corner pinnacles.
- The neighbors are red brick and tan where the photo's are dark brown
  brick and brownstone; the warm share fell to 0.21 (the photo 0.68) as the
  church went gray (in the photo's sun it is warm brown-gray stone).
- Full green trees against bare March ones; a white sidewalk shed at the
  left edge where the photo has a green construction fence.

**flatiron**
- Too bright (0.35 vs 0.23): the photo is backlit, the Flatiron's west face
  in shade, while the game's 15:30 sun lights it. The stone is smooth pale
  gray without the real one's rustication and terracotta; the tower at the
  left is red-brown brick (dark gray-brown, with balconies).
- The plaza has its furniture, but not the photo's bike dock (the feed puts
  it along the plaza's west curb, just right of the view) or its crowd.

**park_ave**
- MetLife is a plain gray box (an elongated octagon with its name on top);
  the Racquet Club is a beige office grid (a rusticated palazzo with tall
  arched windows).
- A few parked cars where the photo has unbroken rows on both curbs; navy
  asphalt in the shade. Midtown's stone is now a little too gray (masonry
  saturation 0.09 vs 0.25).

**totr_south**
- Smoother than the photo (strong edges 0.104 vs 0.367): mid-distance roofs
  are bare (the photo's bulkheads, mechanical floors and terraces), and
  towers are similar gray and tan boxes where real ones run from black
  glass to white stone; the Bank of America Tower is dark gray (pale,
  reflective glass in the photo).

**totr_north**
- 111 West 57th is a pale stick (from the south it is dark glass with
  bronze bands); 53 West 53rd is wide and blocky (slender, with its
  diagonal exterior grid); Rockefeller Center's roof gardens, the photo's
  foreground, are missing.
- At dusk 53 West 53rd's glass breaks into a checkerboard of gold and blue
  squares, and the city is pale and hazy (saturation 0.17 vs 0.33): the
  photo's gold light is vivid.

**brooklyn_bridge**
- The trusses between the promenade and the roadways are solid brown
  walls; the real ones are open lattice, with the roadway and its cars seen
  below. The nearest cables still read as planks. Strong edges 0.041 vs
  0.298, the biggest gap of any view; the frame is all brown (warm share
  0.86 vs 0.49).

**dumbo**
- Now too dark (0.24 vs 0.38; round 3 0.33): canyon shade at 15:30 and
  maroon brick, where the photo has morning sun on orange-red brick.
- Windows are flat rectangles (segmental arches in deep reveals); no fire
  escapes (the right building has a full stack); a crosswalk painted on the
  cobbles; a few pedestrians where the photo has a crowd of tourists.

**promenade**
- The park below is light paving with lamps and a lone conifer where the
  photo has the berm's dense trees and shrubs (green share 0.08 vs 0.21).
- The river is light blue with even ripples (dark gray-blue); the skyline
  is uniform gray boxes (strong edges 0.083 vs 0.313).

**park_slope**
- The brownstone is right in color (masonry saturation 0.24 vs 0.26), but
  the camera stands at a stoop's foot and the stoop's shaded side fills the
  lower half (0.27 vs 0.46); the photo has low stone yard walls and
  plantings between the sidewalk and the stoops. Check the yards' depth
  and the pose.
- Trees are full, low, green crowns (tall bare planes); fronts are smooth
  (bays, window hoods, deep bracketed cornices).

**queens_ridgewood**
- All the parts are there now. The hedges behind the posts are flat
  dark-green slabs that hide the iron pickets, and the brick is a little
  orange (lower half saturation 0.45 vs 0.23, masonry 0.42 vs 0.37); the
  cornices are plain boxes (pressed metal with ornament). Still bright and
  close (0.44 vs 0.33).

**grand_concourse**
- The closest street view (lower half 0.45 vs 0.45, contrast 0.18 vs
  0.21). The brick is one mauve-red (dark brown and tan in the photo, with
  carved entrances); single lanterns where the real posts are tall and
  ornate, twin-armed; full, bright trees.

**st_george**
- The slip houses read low and pale (tall dark brick with dark mouths), and
  the ferries are orange drums in two slips; at 2 km the town is still
  smooth (strong edges 0.037 vs 0.107). The overcast tones match (the deck
  #D8D8D8 vs #E1DED5).

**roosevelt_ave**
- The corner building in front is a brown office front where the photo has
  a bakery's awning and lit window (PLUTO lists no retail there); the shop
  signs are fewer, smaller and unlit (a wall of bright signs, lit at dusk);
  a few pedestrians against a crowd; the deck's underside is a flat dark
  slab with painted lattice (deep beams with light between them); navy
  asphalt (lower half saturation 0.38 vs 0.11). The photo's street is wet
  and lit (0.59): compare by eye.

**st_patricks**
- The front is in the 15:30 sun (0.50 vs 0.35; in shade in the photo). The
  ornament is still sparse: the spires read as stepped cones, with few
  pinnacles and crockets. The Olympic Tower at the left is white with blue
  bands (dark glass).

**guggenheim**
- The slots between the bands are shallow window strips (deep, dark
  recesses); the museum's name on the base band is missing; navy asphalt in
  the shade.

### Across all views

- **Brightness** is right on average and in seven of the 13 views. Most of
  the rest is the photos' light: the Flatiron and St. Patrick's photos are
  in shade, DUMBO's in morning sun, where the game's 15:30 sun lights or
  shades them the other way. A next round should shoot each view at its
  photo's date and hour too (a view's `extra_query`).
- **Contrast** stayed at 0.17 (photos 0.20) through four rounds. Lit faces
  are flat, and the photos' spread comes from small dark details: deep
  window reveals, the shadows between the Guggenheim's bands, people,
  awnings, the el's beams.
- **Color**: the means match (saturation 0.28 vs 0.27, masonry 0.26 vs
  0.27), and each view's masonry is 0.06 from its photo's on average (0.14
  in round 1). Two errors are left: Times Square's screens, and the shade
  on the ground, which is navy blue (saturation 0.46-0.51 on Park Avenue,
  in Times Square and under the 7, where the photos' shaded pavement is
  about 0.08). The toon ambient lights faces that point up with
  `ambient_sky` (0.66, 0.72, 0.86), on a bluish asphalt.
- **Detail**: the strong-edge share rose for the first time (0.091 to
  0.101; photos 0.222), all of it in the far views (Top of the Rock, the
  Promenade, St. George). Street views stayed flat or fell (Fifth Avenue
  0.116 to 0.095, as the church's walls replaced an office grid). At street
  level the photos' detail is crowds, parked cars, sign clutter and
  ornament.
- **Street life**: moving and parked cars read right by eye; pedestrians
  are dressed now, but few in view, and there are no crowds.
- **Landmarks** stand in the right place, at the right size, in the right
  material. Up close their ornament is still sparse, and a few (MetLife,
  the Racquet Club, 53 West 53rd, 111 West 57th) are still plain boxes.

## Remaining gaps after round 4: backlog for after step 9

Step 6 closes with this round, so nothing here is scheduled: the user
decides what comes next. Ranked as before, by how far each would move the
look toward the photos for its effort; numbered on from round 3's table.
Shader compile time (ROADMAP "Shader compile time"): Times Square about
20 s to ready on the dev machine, building.gdshader's color variant under
about 10 s (it is at about 10.7 s), every other shader under about 2 s
(landmark.gdshader is at about 2.4 s). **Compile time** marks the items
that would grow a shader at or over its budget.

| # | What | Effort | Where |
|---|------|--------|-------|
| 32 | **Gray shade on the ground**: shaded asphalt and pavers are navy (#151B27-#232836, saturation 0.46-0.51 on Park Avenue, in Times Square and under the 7) where the photos' shaded pavement is neutral gray (about 0.08); it is much of the excess lower-half saturation in Times Square (0.36 vs 0.18) and on Roosevelt Avenue (0.38 vs 0.11). Grayer sky light on faces that point up, or a grayer asphalt palette; keep the walls' shade as it is (round 3's 18: bluer wall shade turned brownstone gray). Compile time: values only. | small | `shaders/toon.gdshaderinc` (`ambient_sky`), `ground.gdshader` palette |
| 33 | **Times Square's screens as photos**: still flat fields of saturated color and invented glyphs; real screens show photographs (faces, products, dark backgrounds). A small atlas of painted, photo-like ads (made for the game, no brands) sampled by the screens in place of the drawn fields, mostly dark. **Compile time**: the screens are building.gdshader's `screen()`; a texture lookup in place of drawn content need not grow it, but measure (`tools/shader_compile_check.mjs`), or give the sign district's screens a surface and shader of their own. | medium | `shaders/building.gdshader` (`screen()`), an ad atlas in `assets/` |
| 34 | **Crowds**: DUMBO's corner, Roosevelt Avenue's sidewalks, the Flatiron plaza and the Guggenheim's front have 15-30 people each in the photos' frames, the game a handful (Times Square's crowd is there; busy streets left the rest open, as it wants people cheaper than skinned characters). People past 10-15 m as an instanced crowd, a walk cycle baked into a texture and played in the vertex shader (or impostors), dressed like the pedestrians, placed by the busyness grid. Compile time: one new small shader, not skinned (no ANGLE skinning variant); keep it under 2 s. | medium-large | `scripts/npc/crowd_manager.gd`, a new crowd mesh and shader |
| 35 | **The far city's contrast and roofs**: from Top of the Rock and the Promenade the strong-edge share is 0.104 and 0.083 against 0.367 and 0.313: towers are similar gray-blue and tan boxes where real ones run from black glass to white limestone, and roofs are bare where the photos show bulkheads, mechanical floors and terraces. First a wider far palette (darker dark glass, brighter limestone, more tower-to-tower variation); then roof clutter, as cheap props on mid tiles' prisms like the water towers (round 3's 25 drew the 20-40 m buildings from the 3-D model instead: mid tiles 24% bigger and no visible change from Top of the Rock, so measure before keeping it). **Compile time**: palette values in building.gdshader's far path are free; new code there counts against its budget. | medium | `building.gdshader` far palette, `tools/citygen/build_tiles.py` mid-tile roofs, `scripts/world/city_props.gd` |
| 36 | **The Brooklyn Bridge's open trusses**: the stiffening trusses between the promenade and the roadways are solid brown walls; the real ones are open lattice with the roadway and its cars below, and the nearest suspenders and stays read as planks. Strong edges 0.041 vs 0.298, the biggest gap of any view. Chords, posts and diagonals as geometry; thinner near cables. Compile time: none (geometry; the lattice paint is already in landmark.gdshader). | small-medium | `tools/citygen/bridge_landmarks.py` |
| 37 | **Facade relief up close**: windows are flat rectangles flush with the wall, where DUMBO's lofts have segmental arches in deep reveals, Park Slope bays and window hoods, Ridgewood pressed-metal cornices with ornament, the Grand Concourse carved entrances; DUMBO's loft has no fire escape where the photo's has a full stack. Contrast has stayed at 0.17 (photos 0.20) for four rounds, and much of the photos' comes from these small shadows. **Compile time**: building.gdshader's facade code is at its budget, so do it as geometry in near tiles (window insets and arch heads, like the stoops and cornices) or on fronts.gdshader's surface (0.3-0.4 s); tiles grow. | medium-large | `tools/citygen/facades.py`, `fronts.py`, `build_tiles.py` |
| 38 | **Brooklyn Bridge Park's foreground and the river**: from the Promenade the park below is light paving with lamps and one conifer where the photo has the Pier 3 berm's dense trees and shrubs (green share 0.08 vs 0.21); Piers 3 and 5 need hand-made lawn and field outlines (round 3's 28); the river is light blue with even ripples (dark gray-blue in the photo). Compile time: none (ground classes and trees; ocean values). | small-medium | `tools/citygen/ground_details.py`, `landmarks.py`, `shaders/ocean.gdshader` |
| 39 | **Landmarks, a third look**: MetLife's elongated octagon and name; the Racquet Club's rusticated arcade; Marble Collegiate's pale stone spire over a clock stage; the Guggenheim's deep, dark slots between the bands and its name; 111 West 57th's dark south face; 53 West 53rd's slender taper and diagonal grid; Rockefeller Center's roof gardens; St. Patrick's denser pinnacles and crockets. **Compile time**: landmark.gdshader is already over 2 s (it compiles only with a landmark in view); prefer geometry and church.gdshader (0.4-0.6 s), and measure. | medium | `tools/citygen/landmarks.py`, `towers.py`, `churches.py` |
| 40 | **Glass and haze at dusk**: at the photo's dusk 53 West 53rd's glass breaks into a checkerboard of gold and blue window squares where the real dark glass stays dark with a gold edge, and the city is pale (saturation 0.17 vs 0.33): dusk keeps the full haze that the clear day halved. **Compile time**: the window reflections are building.gdshader's; values are free, new code counts against its budget. The haze is values in `time_of_day.gd`. | small | `building.gdshader` window reflection, `scripts/world/time_of_day.gd` |
| 41 | **Street trees by season**: five of the sixteen photos (four from March and April, Park Avenue's from late November) show bare or budding trees with tall, clear trunks; the game's trees are full, round and green all year, and start low. With `?date=` already moving the sun, trees could follow it: bare branches from about November to April. Compile time: tree.gdshader (0.3-0.4 s) gets a branch look, or a second mesh; keep it under 2 s. | medium | `scripts/world/prop_meshes.gd`, `shaders/tree.gdshader`, `time_of_day.gd` |

Smaller things seen once: Park Slope's camera at a stoop's foot (check the
yards' depth and the pose); DUMBO's canyon too dark (lighter, more orange
brick, or check it at the photo's morning hour); Roosevelt Avenue's corner
building, which PLUTO gives no retail, and its unlit shops at dusk;
Ridgewood's hedges hiding the iron fences; the overcast Grand Concourse a
little darker than its photo (0.36 vs 0.45: the photo's clouds are broken,
with sun on the street).

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
| 19 | (done 2026-10-16) **Busy streets**: more moving cars on avenues and boulevards (the photos show a dozen or more in view where the game has a handful), and pedestrians by retail frontage and subway entrances, not only in Times Square's plazas (Roosevelt Avenue, DUMBO, the Flatiron, Fifth Avenue). Watch the frame time on low and medium. **Done** (`build/reference/compare/busy-after`, master in the middle column; ROADMAP "Busy streets"): 180 moving cars on high (120), 90 on medium (60), 35 on low (25), more of them on wide streets and highways and ahead of the camera, and they keep to the wider streets at intersections; pedestrians start by weight of a busyness grid that near tiles' props make as they load (shop signs and awnings, subway stairs, LinkNYC kiosks, newsstands, bus stops, plaza furniture: no tile rebuild), ahead of the camera, and where it sees while the streets first fill; busy streets keep up to 1.5 times as many on high (68, like Times Square). In sight (`?stats`: in view and not behind a building; high, medians of 4 loads), cars before -> after: Times Square 22 -> 49, Fifth Avenue 8 -> 26, the Flatiron 29 -> 57, Park Avenue 21 -> 47, Roosevelt Avenue 19 -> 40, DUMBO 4 -> 7; pedestrians 34 -> 51, 5 -> 15, 11 -> 36, 6 -> 18, 3 -> 9, 4 -> 18 (the game's frame is wider and deeper than the photos': by eye, Fifth Avenue's crossing now has a row of cars and a cab, the Flatiron three cabs, Park Avenue a bus). Paid for by cheaper pedestrians (30 poses a second past 8 m instead of every frame; behind a building in view, not drawn or animated): frame time on medium -1.3 to +0.1 ms, low +0.04 to +0.27 ms, high -0.9 to +0.7 ms (uncapped A/B on a busy machine). Still short: the photos' crowds at Roosevelt Avenue and DUMBO's corner, which want people cheaper than skinned characters. | small-medium | `scripts/world/traffic.gd`, `traffic_lanes.gd`, `city_streamer.gd`, `scripts/npc/crowd_manager.gd`, `pedestrian.gd`, `scripts/util/quality.gd` |
| 20 | (done 2026-10-16: the painted woods did draw, but seen at a slant their crowns fade to a flat green by about 1.5 km, and paths and far tiles' wooded lots are paving; now clumps of crowns stand in tiles of every level, from the land cover map, grown in by the trees' shader from 600-800 m; the park's pixels spread 0.050 in value, from 0.023 (the photo 0.11), the rest is haze, see 25; high +26 draw calls, +0.7 M triangles and +0.2 ms a frame at Top of the Rock, medium +19 draw calls and +0.1 ms, low none; tiles +55 MB, far tiles +13%; compile time unchanged) **Central Park and wooded hills as canopy from above**: from Top of the Rock the park is still lawn and paths, and Staten Island's hill has no tree mass; find why the far crowns don't draw at 1-4 km and draw them. | small-medium | `shaders/tree.gdshader`, `ground.gdshader`, `scripts/world/city_props.gd` |
| 21 | (done 2026-10-16) **Shade under decks and in canyons**: darken the ground and lower walls under el decks and bridge approaches (the roadbed cut already knows the outlines) and down narrow, tall streets (street width against wall height), toward lower half 0.37 and contrast 0.20. Compile time: one more term in building.gdshader, its biggest shader: bake it per vertex in the tiles and apply it once in the shared lighting path, not in each facade branch. **Done** (`build/reference/compare/f3-after` in the facades-3 worktree, against `f3-base`, master 1828499 with its tiles; ROADMAP "Facades, third pass"): each tile's ground, street paint and walls' feet carry the share of the sky they see (`tools/citygen/shade.py`: rays over a height field of the ground, the buildings and the decks around the tile; under a deck only the sky past its edge, and half of what it hides, for the els' open steel), and the shared toon ambient turns it into light (`sky_light`: 1.15 with all the sky in view to 0.6 with none; a street seeing three quarters of it keeps its old light); walls fade back to full light by the height their canyon reaches. Means of 13: lower half 0.381 to 0.361 (photos 0.366); contrast 0.161 to 0.164 (0.201): darker shade alone hardly moves it, as most frames are mostly shade or mostly sun. Times Square 0.265 to 0.240 (0.269), Fifth Avenue 0.312 to 0.285 (0.293), Park Avenue 0.283 to 0.263 (0.248), Top of the Rock south 0.407 to 0.351 (0.357) and north 0.485 to 0.438 (0.417), with 25's haze; DUMBO's narrow canyon 0.305 to 0.226 (0.381: wet cobbles and a bright morning in the photo); under the 7 on Roosevelt Avenue 0.247 to 0.218 (the photo is wet and lit, 0.59); the Flatiron 0.333 to 0.330 (0.226) and Ridgewood 0.429 to 0.439 (0.329) are open, so a little lighter. The gray-day looks kept (five views with `weather=overcast`: 0.368 to 0.363), and dusk (`totr_north` at 19:00: 0.398 to 0.390). Compile time unchanged: building.gdshader's color variant 10.96 s on master and 10.73 s now (medians of nine interleaved compiles of the captured programs; fragment 261,465 to 261,407 characters: the canyon term is worked out once, before the facade branches), ground.gdshader 1.72 and 1.74 s. Tiles (the 578 the views load): near +4.4%, mid +6.2% (with 25's water towers), far +6.5%; about 0.3 s more per tile to build. | medium | `tools/citygen/build_tiles.py`, `ground.gdshader`, `building.gdshader` |
| 22 | (done 2026-10-16) **Landmarks in stone, not toys**: St. Patrick's gray-tan marble with pinnacles, crockets, gables over the three portals, openwork spires and a muted rose window; the Guggenheim's bands smooth (more segments) and white-gray; check the other landmarks the same way (a view each). Compile time: landmark.gdshader compiles only when a landmark is in view; keep it under 2 s. **Done** (`build/reference/compare/landmarks-stone`, against round 3): St. Patrick's west front is built, not painted: the main portal set back 3.7 m in three orders to the bronze doors under a row of niches, the side portals in two, each under a crocketed gablet; the rose window (7.9 m) in its own pointed arch, set back twice, dark muted glass in sixteen lights round a quatrefoil instead of the rainbow; the crocketed central gable with a wheel of blind tracery and its cross; the towers' traceried windows under gables, buttresses stepping back in three stages with pinnacles on the setbacks, clustered pinnacles on top, the lanterns' gablets and pinnacles, the spires in tiers of pierced tracery with crockets up their eight edges; gray-tan Tuckahoe marble, grimier low down. Lower half 0.64 to 0.52 (the photo 0.35: its front is in shade, the game's in the 15:30 sun; at 10:00 it is brown-gray), masonry saturation 0.16 to 0.24 (0.24), warm share 0.21 to 0.59 (0.45), strong edges 0.163 to 0.176 (0.134). The Guggenheim: 72 samples a turn (24) with smooth normals, white-gray, and its ground floor as in the photo (the lobby's glass set back under the base drum that carries the bridge's band round the front, then three bands): lower half 0.48 to 0.50 (0.51), warm share 0.16 to 0.07 (0.11: no beige shade), strong edges 0.125 to 0.108 (smooth bands; the photo's 0.186 is its crowd and cars). The others, a view each: the Vessel was a bright orange waffle cone (muted copper now, its openings showing the flights across the bowl), the Met's columns stood flat against the wall (shadow behind each pair now); the Statue of Liberty's mint green and low-poly statue are building.gdshader's (left for later); the rest read as intended. Compile time unchanged: landmark.gdshader's color program 2.38 s at master and 2.42 s now (medians of nine interleaved compiles of the captured programs, busy machine), as the tables it indexed per pixel went from seven to two (the three words and the made-up letters in one table, looked up once, so the glyph is compiled once; the ad colors and the stained glass as formulas), and the waterfront (28) got a shader of its own. | small-medium | `tools/citygen/landmarks.py`, `shaders/landmark.gdshader` |
| 23 | (done 2026-10-16; the lofts' storefronts with 21 and 25) **Shop signs and awnings**: on retail frontage, sign boards of varied sizes and colors, fabric and aluminum awnings, banners and a few upper-floor signs on commercial streets (Roosevelt Avenue and its kind in every borough); fewer continuous storefronts on lofts. Compile time: as instanced props with a small shader of their own; growing building.gdshader's storefront code would add to its compile time. **Done** (`build/reference/compare/signs-after` in the street-signs worktree, against `signs-base`, master before it; ROADMAP "Shop signs, sidewalk sheds, bike docks and plaza furniture"): every shop on a street wall (PLUTO's retail area, or a store; walls as drawn, party walls left out) gets a sign over the painted band: a board end to end, a light box or channel letters, with 64 invented names (no brands) in four OFL typefaces from a signed-distance-field texture; awnings on 20-45% of shops (cloth with the shop's name on the valance, ribbed aluminum, quarter-round domes), blade signs on 15-35%, upstairs boards on low buildings with offices (PLUTO's office area) and on commercial streets (12 shop buildings within 60 m), banners on a few. New prop types 17 and 18, one MultiMesh per near tile, `shop_sign.gdshader` (0.2-0.3 s to compile). Measures (five views): DUMBO's strong-edge share 0.098 to 0.111 (the photo 0.188), its lower half's saturation 0.23 to 0.26 (0.33), Fifth Avenue's edges 0.081 to 0.085 (a white shed now stands at the left edge, where the photo has a green construction fence); Roosevelt Avenue unchanged within the noise (0.060 to 0.056; the photo 0.184): its shops are 40-80 m off under the el, and PLUTO gives the corner building in front (the photo's bakery) no retail, so it keeps its office lobby; the mean of 5 within the noise of traffic and pedestrians (0.094 to 0.095), lower-half saturation 0.30 to 0.32 (0.23). Left: fewer continuous storefronts on lofts (in `facades.py` and building.gdshader, other work's files then); DUMBO's warehouses get half as many signs instead. **Lofts done** (facades-3 worktree): shops fill the share of a street front that PLUTO's retail area is of the lot's ground floor (all of it from three quarters up), lofts and warehouses (LOFT, INDUSTRIAL, and prewar buildings in the old warehouse districts, condominiums' lots by their neighbors' district) at most 30%: the front is cut into store-wide slots as the shader draws them, the shops evenly spread, the walls between without RETAIL (doors, loading doors; masonry offices no longer get a glass lobby along the whole front) and without signs (25,214 of 85,033 shop buildings, 2,348 of them lofts and warehouses). DUMBO's Washington Street: one shop at the corner, then brick, windows and doors, as in the photo. Also the party walls: the facade code marked 14% of street-level shop walls in dense tiles (up to 21% in SoHo) as street fronts where a street lay beyond a narrow neighbor; a wall is a front now only if no other building stands between it and the street, for the building's mesh, stoops, cornices and the signs alike. | medium | `tools/citygen/props.py`, `scripts/world/prop_meshes.gd`, `facades.py` |
| 24 | (done 2026-10-16) **Sidewalk sheds**: green plywood-and-pipe sheds over the sidewalk (two of the 16 photos have one; the city has thousands up at any time), from the Department of Buildings' sidewalk shed permits on NYC Open Data. Compile time: reuse the street furniture shader. **Done**: the permits are DOB NOW: Build's Approved Permits with work type Sidewalk Shed, issued and not expired or signed off on the day of the download (7,869 on 2026-10-16, on 6,585 buildings; NYC Open Data, rbx6-tga4). Sheds run along those buildings' street walls with at least 2 m of sidewalk, to 0.5 m short of the curb, decks 3.0-3.5 m up, in 3.2 m sections (prop type 19): hunter-green plywood (a few white, black or blue), steel posts, header beam and knee braces, a parapet with stenciled warnings, lamps under the deck that light the sidewalk at night. The photos' sheds are from 2015 and 2018, so the views don't show them; DUMBO's view now has one (Washington Street's west side). Compile time: added to the street furniture shader they doubled its compile time (0.9 to 1.3-1.7 s), so sheds, docks and plaza furniture have `street_extras.gdshader` instead (0.3-0.4 s); sheds are on a small mesh of their own (140 vertices), shrinking away at 78% of the large furniture's distance. | small-medium | `tools/citygen/fetch_data.py`, `props.py`, `prop_meshes.gd` |
| 25 | (done 2026-10-16) **Detail at a distance**: window grids and dark glass kept out to 2-3 km (a cheap far pattern), roof bulkheads and water towers on mid tiles, less haze within 3 km on a clear day (with `?fog=0.00003` Central Park's canopy from Top of the Rock measures close to the photo's: value 0.34 vs 0.42, saturation 0.29 vs 0.34; at the default fog 0.47 and 0.18); the strong-edge share from Top of the Rock and the Promenade is 0.06-0.07 against 0.31-0.37. Compile time: building.gdshader's far path; measure before and after. **Done** (`build/reference/compare/f3-after`, against `f3-base`): window grids stay: the facades' box-filtered floors and windows are pulled only 10% toward their average when small (was 60%), no new code; a clear day's haze is half the dusk's on high (fog 0.00005; 0.8 of it on medium, all of it on low, whose fog hides where their tiles stop), dusk, night and an overcast keep theirs (`Quality.clear_fog()`, TimeOfDay's looks); mid tiles have the water towers of the buildings they draw one by one (162-256 per Manhattan mid tile, drawn to 2.5 km, no shadows); their roof bulkheads are the 3-D model's (40 m and up; drawing the 20-40 m buildings from it too made mid tiles 24% bigger for no change from Top of the Rock, so they stay prisms). Strong edges: Top of the Rock south 0.060 to 0.104 (photo 0.367), north 0.167 to 0.279 (0.336); the Promenade 0.079 to 0.082 (0.313: its lower half is the foreground, paving where the photo has the berm's trees; its camera is now behind the fence, 2.4 m higher, as the landmarks work meant); means of 13 0.084 to 0.100 (0.222). Costs: +5-6 draw calls and +0.2-0.3 M triangles at Times Square and Top of the Rock (one water tower MultiMesh per mid tile); compile time unchanged (above). The rest of the gap: the photos' lit windows, rooftop clutter and people at street level. | medium | `building.gdshader`, `build_tiles.py` (mid-tile roofs), `time_of_day.gd` fog |
| 26 | (done 2026-10-16) **The els' steel**: lattice girders and rivets painted on the flat faces, dark undersides, the stairs from the street up to the stations (the MTA's entrances data, already fetched). Compile time: painting in the shared steel code of landmark.gdshader. **Done** (`build/reference/compare/el-steel`, against round 3; the els are drawn by the ground shader, so the painting went into its shared steel code): the side girders a riveted lattice (the landmark bridges' lattice, a 2.4 m panel), columns, cap girders and track girders riveted plates with stiffeners (rivets behind a new flag, so the landmark bridges' steel is unchanged), the floor beams and the bracing under the tracks as lattice over the deep shade of the deck's underside. 262 stairs from the MTA's stair entrances to elevated stations (the entrances data had them, but not which station each serves: the station each entrance leads to and the stations' structure, two small MTA tables, tell the els' entrances from those of subway stations under an el, like Jackson Heights' and 161st Street's): along the platform's outer side, from corners of cross streets coming in toward the el first, lattice railings, landings, posts, collision; the subway entrance props at their feet go. roosevelt_ave: the top of the frame (the el's underside) #23331E in round 3, #161C1A on master, now #060909 (the photo #0D100F), green share 0.38, 0.12, now 0.04 (0.04); the lower half (the street) unchanged at 0.25; the stair on 82nd Street stands where the photo's does. Compile time: ground.gdshader's color variant +1.1% in length, about 0.15 s slower to compile (interleaved, on a busy machine). | small-medium | `tools/citygen/els.py`, `shaders/ground.gdshader` |
| 27 | (done 2026-10-16) **Churches**: houses of worship (PLUTO building class M) in stone with tall pointed windows, no floor grid, steep roofs, the 3-D model's towers as belfries with spires; today Marble Collegiate and the city's other churches read as apartment blocks. Compile time: a new facade type grows building.gdshader; make it a variant inside `facade_for()`, or give churches their own surface and shader. **Done** (`build/reference/compare/churches-fronts`, against master): 2,906 buildings on class M1 lots (church, synagogue, chapel) big and tall enough to be one (`tools/citygen/churches.py`) are Gothic (pointed arches; always where the footprint measures a spire above the 3-D model's tower), Romanesque (round) or, from 1945, modern (tall narrow windows), in brownstone, gray stone, limestone, red or buff brick by era (big ones and landmarks in stone). Walls have no floors: tall stained-glass windows between buttresses (in stages up very tall walls) under a corbel table; a gable facing the street has a portal and a rose window. The model's nave level gets a gable roof with its ridge at the level's height (48-58 degrees on Gothic churches, shallower where the eaves would drop below 58% of the ridge); its towers (on 517 churches) rise in stages to belfries with louvers, half of them with a clock that keeps the game's time, under spires (octagonal on square towers, with pinnacles at a square stage's corners; to the footprint's height where that's above the model's): slate, copper or stone. Marble Collegiate reads as a gray stone Gothic church with its tower, octagonal belfry and spire where the photo has them (lower half 0.34 to 0.30, the photo 0.29; it was a towers.py special case drawing the bare model). Churches have their own surface and a small shader (`church.gdshader`, 0.4-0.6 s to compile; building.gdshader unchanged), one more draw call per tile with a church (mid and far tiles too, for tall ones); tiles +0.3%. | medium | `tools/citygen/facades.py`, `building.gdshader` or a separate surface |
| 28 | (done 2026-10-16) **Waterfront landmarks** (round 1's 14): the St. George ferry slips and the Whitehall terminal, piers with their sheds, Brooklyn Bridge Park's planted berm and marina. **Done** (`build/reference/compare/landmarks-stone`): the piers out over the water weren't drawn at all (the data adds them to the land and then takes the water away, piers with it): 1,216 pier outlines (1.25 km²) are land again. St. George: the terminal in glass toward the harbor and brick, four brick slip houses with white steel frames, the slips' timber racks (the city's hydrography structures) and two orange ferries in their slips, lit at night, where it was a long red-brick block. Whitehall: glass on three sides, stainless toward the slips, the sinuous canopy with the words, the racks and a ferry. Chelsea Piers' sheds in metal panels with window bands, the golf range's 46 m poles and cables; Brooklyn Bridge Park's Pier 2 as open roofs on columns (it was a 10 m box over the whole pier), the Pier 3 berm (9.1 m high, 240 m along Furman Street, a meadow with its trees standing on it) and the ONE15 marina's docks, pilings and the boats moored in the aerial photos. st_george: lower half 0.67 to 0.63 (0.56, overcast), strong edges 0.025 to 0.029 (0.107: at 2 km the slips are a few pixels). The promenade camera now stands behind the Promenade's new fence (the triple cantilever's): from 2.4 m higher it sees the marina, the docks and the piers. Piers 3 and 5 are paving (the 2017 land cover has them paved, Pier 1 as water); their lawns and fields need hand-made outlines. | medium | `landmarks.py`, `ground_details.py` |
| 29 | (done 2026-10-16) **Rowhouse fronts, second pass**: iron railings on brownstone stoops, front-yard walls and plantings, rounded bow fronts in Ridgewood, deeper painted metal cornices, iron fences on brick posts, door awnings. **Done** (`build/reference/compare/churches-fronts`; `tools/citygen/fronts.py`): iron railings on 70% of brownstone and limestone stoops and 60% of others, see-through (pickets and rails, posts at the ends), the cheek walls a curb under them; yards behind a stone wall or (75% of brick houses', 35% of brownstones') an iron fence on a curb, between brick posts with white pyramid caps in Queens, with a box hedge or a shrub behind; Queens' prewar buff brick rows' bays rounded into bow fronts (Ridgewood's; 20% of other bayed rows'); prewar rows' and tenements' cornices stand 0.6 m out over a sloping underside, painted by the cornice code the walls already had; striped metal awnings over 60% of Queens rows' doors (12% elsewhere, none on brownstone). The railings, fences, posts, plants and awnings are a surface of their own without collision (`fronts.gdshader`, 0.3-0.4 s to compile; drawn within 600 m of their tile), one more draw call per near tile; building.gdshader lost its painted iron (fragment 262,977 to 261,465 characters; its compile time unchanged within the noise). The Ridgewood pose moved 2.2 m out from the houses (it stood at the stoops); there the lower half is 0.48 to 0.43 (the photo 0.33) and the strong-edge share 0.069 to 0.079 (0.155). Park Slope's camera still stands at the stoops' feet, looking along them (lower half 0.28 either way; the photo 0.46). Tiles: near tiles +8.9% (+131 MB, from 60 random tiles; brownstone and Ridgewood blocks +22-43%); frame time unchanged within the noise in Park Slope, Bed-Stuy and Ridgewood. | medium | `tools/citygen/fronts.py`, `building.gdshader` |
| 30 | (done 2026-10-16) **Overhead wires and wooden utility poles** on house streets in Queens, the Bronx and Staten Island (no data: along streets lined with houses). **Done** (`build/reference/compare/poles-after` in the poles-wires worktree, against `poles-base`, master before it; ROADMAP "Utility poles and overhead wires"): street segments whose frontage is mostly houses and rowhouses (PLUTO's classes A, B and C under four floors; or low shopping streets among them), in the Bronx, Queens, Staten Island and Brooklyn beyond 4.5 km of Borough Hall, join into lines along their streets with wooden poles every 40 m or so along one curb (161,729 on 16,241 lines; `tools/citygen/poles.py`, a new prepared cache): crossarms with insulators, a pin on the top for three-phase lines, transformer cans on 18%, and the street lights on them (cobra-heads on 90%; those streets' curb lamps go, so they're lit from one side as in Queens, and darker at night). Spans run pole to pole across the intersections, service drops from the nearest pole to 613,369 houses (across the street to the far side's, as in the photo), down guys in yellow guards at the lines' ends. New prop types 24 (poles: the street lights' shader on a mesh of their own) and 25 (wires: one prop a span, which `shaders/wires.gdshader` hangs in a sag and turns to face the camera, at least a pixel wide, gone by 210-290 m; 0.1 s to compile; no shadows, no collision); two more draw calls per near tile with poles (+9-10 in Ridgewood, Bronx and Staten Island street views), tiles +1.1% there. In the Ridgewood view the pole line stands across the street, behind the camera's left: the crop shows one drop reaching the row's cornice, and its measures are unchanged (lower half 0.43, strong edges 0.079; the photo 0.33 and 0.155, whose other wires run along the house fronts, house to house). | small-medium | `props.py`, `prop_meshes.gd` |
| 31 | (done 2026-10-16) **Citi Bike docks and plaza furniture**: docks from Citi Bike's public station feed (check its data license first), umbrella tables, planters and kiosks on the DOT's plazas. **Done**: the GBFS feed's license (Lyft's Bikeshare Data License Agreement) allows the data inside a product, not as a dataset of its own, and none of the system's names or marks, so the bikes are a generic blue without logos (credited in `CREDITS.md`). 2,518 stations: rows of docks along the nearest curb, in the parking lane where the station is in the street (parked cars keep clear), else on the sidewalk or plaza, sections of four docks with 45-100% bikes and the kiosk at one end (prop type 20, 18,900 sections). The plazas get planters along their edges by the street, bistro tables with chairs in seating areas, 30% under umbrellas (none in Times Square's sign district), and food kiosks in big ones (types 21-23). The Flatiron photo's dock row is in the plaza 5-15 m from the camera; the game's, where the feed puts it, runs along the plaza's west curb, just right of that view. | small | `fetch_data.py`, `props.py` |

Smaller things seen once: the Flatiron plazas drawn as asphalt (above);
the Ridgewood camera stood 2-3 m too close to the houses (moved 2.2 m out
with 29); 111 West 57th's south face (dark glass and bronze, not
terracotta); the Guggenheim's ground floor (the name band and the recessed
lobby).

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
