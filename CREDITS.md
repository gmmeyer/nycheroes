# Credits

The city is built from open data. The game must keep showing the credit
lines below wherever a license asks for one (the aerial photos do).

## City data

- **Aerial photos:** NYC 2024 orthoimagery (6-inch, flown March 2024), by
  the NYC Office of Technology and Innovation and the New York State
  Statewide Digital Orthoimagery Program. License: CC BY 4.0, per the
  city's metadata
  (https://github.com/CityOfNewYork/nyc-geo-metadata/blob/master/Metadata/Metadata_AerialImagery.md).
  Credited in the game's HUD.
- **Building shapes:** NYC 3-D Building Model (LoD2 CityGML), NYC Office of
  Technology and Innovation, via NYC Open Data (tnru-abg2).
- **Building footprints and heights, borough outlines, parks, roadbed,
  hydrography, piers (and the ferry slips' fender racks and the marinas'
  docks) and bridge structures:** NYC Open Data (datasets 5zhs-2jue,
  gthc-hcne, enfh-gkve, i36f-5ih7, pjs3-c3z5, 6hbv-tek4, r9cu-9r7b). The
  boats moored in Brooklyn Bridge Park's marina are where the aerial photos
  (above) show them.
- **Street trees, street centerlines and land cover:** NYC Parks Forestry
  Tree Points (hn5i-inap), the Citywide Street Centerline (CSCL, inkn-q76z)
  and the 2017 LiDAR land cover map (he6d-2qns), via NYC Open Data.
- **Street furniture:** NYC Open Data: hydrants (5bgh-vtsn), bus stop
  shelters (t4f2-8md7), LinkNYC kiosks (s4kf-3yrf), seating locations
  (esmy-s8q5), bicycle parking (592z-n7dk), DSNY litter baskets
  (8znf-7b2c), parking meters (693u-uax6) and newsstands (w9zq-xm8b); MTA
  subway entrances and exits (data.ny.gov, i9wp-a4ja).
- **Bridge tower positions and some towers' massing** (placement and setback
  heights for towers newer than the city's 3-D model): © OpenStreetMap
  contributors (ODbL), https://www.openstreetmap.org/copyright.
- **Ground elevation:** USGS 3D Elevation Program, 1/3 arc-second DEM
  (public domain, U.S. Government work).
- **Planted medians, other parks and special pavements:** NYC Open Data:
  Planimetric Database medians (ees7-4ufv) and other open space
  (b7j8-z8a7: cemeteries, recreation areas), NYC Parks Greenstreets
  (mk9u-qu7i), NYC DOT pedestrian plazas (k5k6-6jex), and the Department
  of City Planning's Publicly Owned Waterfront (jr73-mxkz: the city's,
  state's and federal parks on the water, among them the National Park
  Service's Statue of Liberty, Ellis Island and Governors Island national
  monuments and Gateway National Recreation Area, and New York State's
  parks); street names from the street centerline (inkn-q76z).
- **The Unisphere's continents:** Natural Earth 1:110m land (public
  domain, naturalearthdata.com), reduced to 7.5-degree cells in
  `tools/citygen/landmarks.py`.
- **Elevated railways and walkways on decks:** NYC Open Data: Planimetric
  Database railroad lines (anc7-97cy: elevated, embankment, open-cut and
  at-grade track centerlines, named by line), railroad structures
  (dwer-xbgx: elevated stations) and sidewalks (52n9-sdep: the walkways on
  bridges and raised streets); the rail bridge and railroad viaduct
  outlines are in the bridge structures above (r9cu-9r7b).

`tools/citygen/fetch_data.py` and `tools/citygen/aerial.py` list exactly
what is downloaded from where.

## Characters

- Mannequin and animations: "Universal Animation Library [Standard]" by
  Quaternius, CC0 1.0 (see `assets/characters/mannequin/CREDITS.txt`).

## Sounds

Every sound is either synthesized for the game or cut from recordings
dedicated to the public domain under Creative Commons 0 (CC0 1.0, which
asks for no credit; they're listed anyway). `tools/audio/build_sounds.py`
downloads them (checking each Freesound page says CC0), cuts, loops and
normalizes them into `assets/audio/`; `scripts/audio/sound_bank.gd` says
which file is which sound.

- **Synthesized** (numpy, in `build_sounds.py`): punch, swing and dive
  whooshes, web shots and releases, take-off, super speed's zoom and wind,
  the air rushing past, a super jump's charge and launch, heavy landings,
  rubble, getting back up, wind up high, and the trains on the els'
  rumble and squeal.
- **Kenney** (kenney.nl, CC0): "Impact Sounds" (footsteps on concrete,
  grass and wood; punches; soft landings), "RPG Audio" (cloth for jumps,
  creaks for the web's tension), "Sci-fi Sounds" (the low explosion under a
  ground slam), "Interface Sounds" (the sound switch's click).
- **Freesound** (freesound.org, each CC0), by uploader:
  - City beds: quantumriver, "Recording of Busy New York City Street"
    (552120, the day's street); SpliceSound, "New York City night evening
    rooftop ambience traffic, Bushwick, Brooklyn" (369891, the night);
    Yakobb1, "City Ambience Distant Stereo" (495866, the far-off hum up
    high); olofgud, "Times square 1700" (639703, Times Square's crowd);
    cynthia_1968, "morning-birds-urban-city-ambience-field-recording"
    (578150, birds); kyles, "crickets night short nice some skyline
    Montreal, Canada" (455685, crickets); craigsmith, "G54-04-Pier Lap"
    (438839, waves lapping).
  - Around the city: Shankfosho, "Park Birds [Clean]" (688301, bird
    calls); brunoboselli, "Distant Ambulance Siren" (469363) and TRP,
    "200829 Sirens, distant, ambulence, police, urban echoes roof" (568814),
    far sirens; horns from DuranBurrus, "Car Horn" (547667), Brett+Butter,
    "Car Horn Honk 01 - Single, Distant - EXT Day Brooklyn Street corner"
    (553150), DeVern, "Car Horn Honk" (349922), kyles, "truck real horn
    honk quick polite warning" (637923) and BiblicalBricksProductions, "Car
    honk" (196139); AndrewAlexander, "car_idle_ext_loop" (369054, passing
    cars' engines); qubodup, "Distant Dog Bark" (813116) and Sadiquecat,
    "Thuir Distant dog bark" (792440).
  - Voices: CalGre, "Good Guy Grunts" (467132, the hero) and "Evil Guy
    Grunts" (467121, thugs hurt); ale-batec, "Male Fight Grunts" (511023,
    thugs swinging); unfa, "Medium Male Pain Grunts" (610998, thugs going
    down); metrostock99, "HEY VERY LOW 4" (345083) and craigsmith, "R07-46
    Men with Gruff Voices Grunting" (480787), thugs' shouts; screams of
    fleeing bystanders from queen_westeros, "MAN SCREAM" (222582),
    EricSueiro, "woman scream" (220814), starnezio, "woman scream" (609973),
    ColtoBene, "Woman Scream" (670315) and JalynCatbtg, "Woman Screaming"
    (618193).
  - Bodies and water: leonelmail, "BODY FALL - V HVY - DIRT" (504626);
    "Body fall_02" (346694, by a since-deleted user); raubana, "Body Fall
    Over" (82027); Logicogonist, "splash 1b" (807962); qubodup, "Waboba
    Moon Ball Water Splash 9" (867464); craigsmith, "G54-26-Person
    Swimming" (438845).
- **Soundscape map** (`assets/audio/soundscape.png`, from the city's land
  cover map and the USGS elevation model above, by
  `tools/audio/soundscape_map.py`): where parks, water and built-up blocks
  are, for the ambience.

## Reference photos

Not part of the game: free-licensed photos from Wikimedia Commons that
`tools/reference/compare.py` downloads (to `build/reference/photos/`, never
committed) to compare the game with reality (`docs/REFERENCE.md`). If any
are shown publicly, credit them as below and keep the share-alike terms.

- times_square: "Times Square looking south from 46th Street", Dough4872,
  CC BY-SA 4.0.
- fifth_ave_esb: "29th St 5th Av 03 - Marble Collegiate Church",
  Tdorante10, CC BY-SA 4.0.
- flatiron: "Flatiron Building - panoramio (5)", qwesy qwesy, CC BY 3.0.
- park_ave: "Park Ave - panoramio", Elvis Boaventura, CC BY 3.0.
- totr_south: "New York skyline from Top of the Rock", Hugo Maestá,
  CC BY-SA 4.0.
- totr_north: "Sunset at the Top of the Rock (north side)", Nicolas Lh.,
  CC BY-SA 2.0.
- brooklyn_bridge: "Brooklyn Bridge, New York City, 20231005 0939 2163",
  Jakub Hałun, CC BY-SA 4.0.
- dumbo: "Manhattan Bridge and Empire State Building from Washington
  Street, Dumbo, Brooklyn, New York", Christian David, CC BY-SA 4.0.
- promenade: "View across the East River towards Lower Manhattan from the
  Brooklyn Heights Promenade" (2024-05-22), Famartin, CC BY-SA 4.0.
- park_slope: "Park Slope", Mark O'Neill, CC BY-SA 3.0.
- queens_ridgewood: "60th Lane Ridgewood", Kidfly182, CC BY-SA 4.0.
- grand_concourse: "Grand Concourse, Bronx - 20220616", Andre
  Carrotflower, CC BY-SA 4.0.
- st_george: "St. George Ferry Terminal, Staten Island, New York City,
  20231002 1621 1749", Jakub Hałun, CC BY 4.0.
- roosevelt_ave: "82 Street vc", Doug Letterman, CC BY 2.0.
- st_patricks: "Saint Patricks Cathedral in New York - NYC - USA -
  panoramio", diego_cue, CC BY-SA 3.0.
- guggenheim: "NYC - Guggenheim Museum", Jean-Christophe BENOIST,
  CC BY 3.0.

Each file's Commons page is in `tools/reference/views.json` (`photo.page`).

## Engine

- Godot Engine 4.7 (MIT license), https://godotengine.org.
