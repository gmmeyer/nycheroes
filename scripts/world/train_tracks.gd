class_name TrainTracks
extends RefCounted
## The el tracks of the loaded near tiles, as a graph that Trains' trains run
## on. Each tile brings its pieces of track (world-space polylines in the
## direction trains run on them, see CityTileDecoder.SURFACE_TRAINS); pieces
## meet at nodes whose ids are the same in every tile, so they link up across
## tiles: the pieces leaving a node are the ones whose from-node it is. At a
## node a train goes on along a piece of its own line if there is one, else
## the straightest, and never turns back (a crossover to the track running
## the other way is a dead end to it, so trains keep to their tracks).

## Trains go on onto pieces at most this far off their heading (cosine).
const FOLLOW := 0.85

## A piece of track between two nodes.
class Piece:
	## World-space points in the order trains run, the distance along it at
	## each, and its length.
	var points: PackedVector3Array
	var along := PackedFloat32Array()
	var length := 0.0
	## The speed limit at each point (m/s).
	var speeds: PackedFloat32Array
	## Where trains stop (each a platform's middle), as distances along it.
	var stops := PackedFloat32Array()
	var from_node := 0
	var to_node := 0
	## Its line's service (Trains.SERVICES) and CityTileDecoder.TRACK_* flags.
	var service := 0
	var flags := 0
	## Unit directions where it starts and ends (going on past them), and at
	## each point (the mean of the segments either side).
	var start_direction := Vector3.FORWARD
	var end_direction := Vector3.FORWARD
	var tangents := PackedVector3Array()
	## Gone with its tile: trains on it must go too.
	var removed := false

	func measure() -> void:
		along.resize(points.size())
		along[0] = 0.0
		for k in range(1, points.size()):
			along[k] = along[k - 1] + points[k].distance_to(points[k - 1])
		length = along[along.size() - 1]
		start_direction = (points[1] - points[0]).normalized()
		end_direction = (points[points.size() - 1] - points[points.size() - 2]).normalized()
		tangents.resize(points.size())
		tangents[0] = start_direction
		tangents[points.size() - 1] = end_direction
		for k in range(1, points.size() - 1):
			tangents[k] = (points[k + 1] - points[k - 1]).normalized()

	## The point `d` along it; before its start or past its end, the track
	## goes on straight.
	func point_at(d: float) -> Vector3:
		if d <= 0.0:
			return points[0] + start_direction * d
		if d >= length:
			return points[points.size() - 1] + end_direction * (d - length)
		var k := clampi(along.bsearch(d) - 1, 0, points.size() - 2)
		var span := along[k + 1] - along[k]
		return points[k].lerp(points[k + 1], (d - along[k]) / span) if span > 0.0001 else points[k]

	## The speed limit `d` along it (the lower of the points either side).
	func speed_at(d: float) -> float:
		var k := clampi(along.bsearch(d) - 1, 0, points.size() - 2)
		return minf(speeds[k], speeds[k + 1])

	func is_main() -> bool:
		return flags & CityTileDecoder.TRACK_MAIN != 0


## Pieces by tile: Vector2i -> Array[Piece].
var tiles := {}
## Each tile's running tracks (where trains may appear) and their running
## total length: Vector2i -> [Array[Piece], PackedFloat32Array].
var tile_mains := {}
## Each tile's pieces' bounding box on the ground (x, z): Vector2i -> Rect2.
var tile_bounds := {}

var _leaving := {}  # node id -> Array[Piece] leaving it
var _arriving := {}  # node id -> Array[Piece] ending at it


## Adds a tile's tracks (its decoded trains surface, world-space), replacing
## any it had. Returns the pieces that went (see remove_tile).
func set_tile(key: Vector2i, tracks: Dictionary) -> Array[Piece]:
	var removed := remove_tile(key)
	if tracks.is_empty() or tracks.tracks.is_empty():
		return removed
	var stride := CityTileDecoder.TRAIN_INFO_STRIDE
	var info: PackedFloat32Array = tracks.info
	var added: Array[Piece] = []
	var mains: Array[Piece] = []
	var totals := PackedFloat32Array()
	var bounds := Rect2(tracks.tracks[0][0].x, tracks.tracks[0][0].z, 0.0, 0.0)
	for n in tracks.tracks.size():
		var piece := Piece.new()
		piece.points = tracks.tracks[n]
		piece.speeds = tracks.speeds[n]
		piece.measure()
		if piece.length < 0.5:
			continue
		for k: int in tracks.stops[n]:
			piece.stops.append(piece.along[k])
		piece.from_node = int(info[n * stride])
		piece.to_node = int(info[n * stride + 1])
		piece.service = int(info[n * stride + 2])
		piece.flags = int(info[n * stride + 3])
		added.append(piece)
		_leaving.get_or_add(piece.from_node, [] as Array[Piece]).append(piece)
		_arriving.get_or_add(piece.to_node, [] as Array[Piece]).append(piece)
		if piece.is_main():
			mains.append(piece)
			totals.append((totals[totals.size() - 1] if not totals.is_empty() else 0.0) + piece.length)
		for p in piece.points:
			bounds = bounds.expand(Vector2(p.x, p.z))
	if added.is_empty():
		return removed
	tiles[key] = added
	tile_bounds[key] = bounds
	if not mains.is_empty():
		tile_mains[key] = [mains, totals]
	return removed


## Takes a tile's pieces out of the graph. Returns them (marked removed), so
## trains on them can go too.
func remove_tile(key: Vector2i) -> Array[Piece]:
	var removed: Array[Piece] = []
	if not tiles.has(key):
		return removed
	removed.assign(tiles[key])
	tiles.erase(key)
	tile_mains.erase(key)
	tile_bounds.erase(key)
	for piece in removed:
		piece.removed = true
		_unlist(_leaving, piece.from_node, piece)
		_unlist(_arriving, piece.to_node, piece)
	return removed


## The pieces ending at a node.
func arriving(node: int) -> Array:
	return _arriving.get(node, [])


## Where a train of `service` goes on from the end of `piece`: a piece of
## its own line, else the straightest; null if none goes on (yet).
func next(piece: Piece, service: int) -> Piece:
	return _pick(_leaving.get(piece.to_node, []), piece.end_direction, service, true)


## Where a train of `service` on `piece` came from (for laying out a new
## train behind its front), as next() picks; null if none.
func previous(piece: Piece, service: int) -> Piece:
	return _pick(_arriving.get(piece.from_node, []), piece.start_direction, service, false)


func _pick(choices: Array, heading: Vector3, service: int, ahead: bool) -> Piece:
	var best: Piece = null
	var best_score := -INF
	for other: Piece in choices:
		var straight := heading.dot(other.start_direction if ahead else other.end_direction)
		if straight < FOLLOW:
			continue
		var score := straight + (1.0 if other.service == service else 0.0)
		if score > best_score:
			best_score = score
			best = other
	return best


static func _unlist(index: Dictionary, node: int, piece: Piece) -> void:
	var list: Array = index.get(node, [])
	list.erase(piece)
	if list.is_empty():
		index.erase(node)
