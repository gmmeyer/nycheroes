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
  hydrography, piers and bridge structures:** NYC Open Data (datasets
  5zhs-2jue, gthc-hcne, enfh-gkve, i36f-5ih7, pjs3-c3z5, 6hbv-tek4,
  r9cu-9r7b).
- **Street trees, street centerlines and land cover:** NYC Parks Forestry
  Tree Points (hn5i-inap), the Citywide Street Centerline (CSCL, inkn-q76z)
  and the 2017 LiDAR land cover map (he6d-2qns), via NYC Open Data.
- **Street furniture:** NYC Open Data: hydrants (5bgh-vtsn), bus stop
  shelters (t4f2-8md7), LinkNYC kiosks (s4kf-3yrf), seating locations
  (esmy-s8q5), bicycle parking (592z-n7dk), DSNY litter baskets
  (8znf-7b2c), parking meters (693u-uax6) and newsstands (w9zq-xm8b); MTA
  subway entrances and exits (data.ny.gov, i9wp-a4ja).
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
  rubble, getting back up, and wind up high.
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

## Engine

- Godot Engine 4.7 (MIT license), https://godotengine.org.
