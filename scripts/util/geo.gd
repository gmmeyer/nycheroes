class_name Geo
## Latitude and longitude to world meters: the transverse Mercator projection
## the city's tiles are built in (tools/citygen/common.py PROJECTION: centered
## on Times Square, WGS84, scale 1), +X east and +Z south like Godot's.
## Snyder's series (Map Projections: A Working Manual, 8-9 and 8-10), good to
## well under a millimeter across the five boroughs.

const ORIGIN_LAT := 40.7580
const ORIGIN_LON := -73.9855
const A := 6378137.0  # WGS84
const F := 1.0 / 298.257223563
const E2 := F * (2.0 - F)
const EP2 := E2 / (1.0 - E2)


## A world position (y 0) for a latitude and longitude in degrees.
static func to_world(lat: float, lon: float) -> Vector3:
	var phi := deg_to_rad(lat)
	var s := sin(phi)
	var c := cos(phi)
	var n := A / sqrt(1.0 - E2 * s * s)
	var t := tan(phi) * tan(phi)
	var cc := EP2 * c * c
	var a := deg_to_rad(lon - ORIGIN_LON) * c
	var a2 := a * a
	var east := n * (a + (1.0 - t + cc) * a2 * a / 6.0
		+ (5.0 - 18.0 * t + t * t + 72.0 * cc - 58.0 * EP2) * a2 * a2 * a / 120.0)
	var north := _meridian(phi) - _meridian(deg_to_rad(ORIGIN_LAT)) + n * tan(phi) * (a2 / 2.0
		+ (5.0 - t + 9.0 * cc + 4.0 * cc * cc) * a2 * a2 / 24.0
		+ (61.0 - 58.0 * t + t * t + 600.0 * cc - 330.0 * EP2) * a2 * a2 * a2 / 720.0)
	return Vector3(east, 0.0, -north)


## Distance along the meridian from the equator to latitude `phi` (radians).
static func _meridian(phi: float) -> float:
	var e4 := E2 * E2
	var e6 := e4 * E2
	return A * ((1.0 - E2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0) * phi
		- (3.0 * E2 / 8.0 + 3.0 * e4 / 32.0 + 45.0 * e6 / 1024.0) * sin(2.0 * phi)
		+ (15.0 * e4 / 256.0 + 45.0 * e6 / 1024.0) * sin(4.0 * phi)
		- 35.0 * e6 / 3072.0 * sin(6.0 * phi))
