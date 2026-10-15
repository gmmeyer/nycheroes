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
- **Ground elevation:** USGS 3D Elevation Program, 1/3 arc-second DEM
  (public domain, U.S. Government work).

`tools/citygen/fetch_data.py` and `tools/citygen/aerial.py` list exactly
what is downloaded from where.

## Characters

- Mannequin and animations: "Universal Animation Library [Standard]" by
  Quaternius, CC0 1.0 (see `assets/characters/mannequin/CREDITS.txt`).

## Engine

- Godot Engine 4.7 (MIT license), https://godotengine.org.
