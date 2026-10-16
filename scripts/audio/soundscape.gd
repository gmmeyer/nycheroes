class_name Soundscape
extends RefCounted
## What the city sounds like at a spot, from the soundscape map
## (assets/audio/soundscape.png, made by tools/audio/soundscape_map.py from
## the city's land cover map): how green, how watery and how built up the
## surroundings are, and the ground's height. Imported as an Image, so it's
## read on the CPU, and blended between its 64 m pixels.

const MAP := "res://assets/audio/soundscape.png"
## Where the map lies (world meters; from soundscape_map.py): its top-left
## corner, north up, and its pixel size.
const MIN_X := -23446.89
const MIN_Z := -17496.85
const PIXEL := 64.0

## Times Square's sign district (tools/citygen/props.py SIGN_ALONG and
## SIGN_ACROSS): meters along Manhattan's avenues (29 degrees east of north)
## and across them (east), from 46th Street and Broadway.
const SQUARE_ALONG := Vector2(-330.0, 420.0)
const SQUARE_ACROSS := Vector2(-120.0, 110.0)
const AVENUE_ALONG := Vector2(0.485, 0.875)
const AVENUE_ACROSS := Vector2(0.875, -0.485)

static var _shared: Soundscape

var _image: Image
var _width := 0
var _height := 0


## The one map everything reads (loaded the first time it's asked for).
static func shared() -> Soundscape:
	if _shared == null:
		_shared = Soundscape.new()
	return _shared


func _init() -> void:
	_image = load(MAP) as Image
	if _image == null:
		push_warning("No soundscape map; the city will sound the same everywhere.")
		return
	_width = _image.get_width()
	_height = _image.get_height()


## At a world position (x, z): green (trees and grass), water and built up,
## each 0..1, and the ground's height in meters, as (r, g, b, a). Off the map
## it's open water.
func sample(world_position: Vector3) -> Color:
	if _image == null:
		return Color(0.0, 0.0, 0.5, 0.0)
	var x := (world_position.x - MIN_X) / PIXEL - 0.5
	var y := (world_position.z - MIN_Z) / PIXEL - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var top := _pixel(x0, y0).lerp(_pixel(x0 + 1, y0), fx)
	var bottom := _pixel(x0, y0 + 1).lerp(_pixel(x0 + 1, y0 + 1), fx)
	var value := top.lerp(bottom, fy)
	value.a *= 255.0  # meters
	return value


## How close a world position is to Times Square: 1 inside the sign
## district, fading to 0 about 150 m outside it.
static func times_square(world_position: Vector3) -> float:
	var east_north := Vector2(world_position.x, -world_position.z)
	var along := east_north.dot(AVENUE_ALONG)
	var across := east_north.dot(AVENUE_ACROSS)
	var outside := Vector2(maxf(maxf(SQUARE_ALONG.x - along, along - SQUARE_ALONG.y), 0.0),
		maxf(maxf(SQUARE_ACROSS.x - across, across - SQUARE_ACROSS.y), 0.0)).length()
	return 1.0 - smoothstep(0.0, 150.0, outside)


func _pixel(x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= _width or y >= _height:
		return Color(0.0, 1.0, 0.0, 0.0)
	return _image.get_pixel(x, y)
