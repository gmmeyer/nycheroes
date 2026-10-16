class_name TrafficLanes
extends RefCounted
## The driving lanes of the loaded near tiles, as a graph that Traffic's cars
## drive on. Each tile brings its streets' lanes (world-space polylines, see
## CityTileDecoder.SURFACE_TRAFFIC); lanes meet at nodes (intersections, or
## where a street just goes on), and node ids are the same in every tile, so
## lanes link up across tiles: the lanes leaving a node are the ones whose
## from-node it is. Between a lane's end (its stop line) and the next lane's
## start, a car drives a connector: a curve through the intersection, built the
## first time a car takes it and kept until either lane unloads.
##
## Each intersection keeps track of the connectors with cars on them (its Box):
## a car only drives into the intersection if its connector doesn't cross (or
## merge with) one that's in use, so cars take turns where there's no signal,
## and a turning car waits while an oncoming one crosses its way. Where there's
## no signal, the widest street has the right of way (Lane.priority; Traffic
## has the others yield to it). A car that has waited long can claim the box
## next, so a busy stream can't keep it out for good.

## What a connector does, from the angle between the lane coming in and the one
## going out.
enum Turn { STRAIGHT, LEFT, RIGHT, U_TURN }

## Movements within this angle of dead ahead go straight (radians, 35 degrees).
const STRAIGHT_ANGLE := 0.61
## Past this angle a movement turns back the way it came (radians, 150 degrees).
const U_TURN_ANGLE := 2.62
## Connectors get a point at least every this many meters.
const CONNECTOR_STEP := 2.5
## Sideways acceleration cars accept in turns (m/s^2), and the slowest speed
## a turn asks for (m/s).
const TURN_GRIP := 2.2
const MIN_TURN_SPEED := 3.0
## How often a car goes straight on where it could also turn.
const STRAIGHT_SHARE := 0.7

## A stretch of road a car drives along: a lane, or a connector between two.
class Path:
	## World-space points in driving order (on the road), and the distance
	## along the path at each.
	var points: PackedVector3Array
	var along := PackedFloat32Array()
	var length := 0.0
	## Each segment's heading (radians; it runs along (sin yaw, 0, cos yaw)).
	var yaws := PackedFloat32Array()
	## Speed limit (m/s).
	var speed := 11.2
	## Cars on it (Traffic's car slots), the front-most first.
	var cars := PackedInt32Array()
	## Where it is in Traffic's list of paths with cars on them (-1: not there).
	var busy_index := -1
	## Gone with its tile: cars must leave it.
	var removed := false

	func measure() -> void:
		along.resize(points.size())
		yaws.resize(points.size() - 1)
		along[0] = 0.0
		for k in range(1, points.size()):
			var step := points[k] - points[k - 1]
			along[k] = along[k - 1] + step.length()
			yaws[k - 1] = atan2(step.x, step.z) if absf(step.x) + absf(step.z) > 0.0001 else 0.0
		for k in range(1, yaws.size()):
			if absf(points[k + 1].x - points[k].x) + absf(points[k + 1].z - points[k].z) <= 0.0001:
				yaws[k] = yaws[k - 1]  # a point repeated: keep heading
		length = along[along.size() - 1]

	## The segment holding distance `d` (points k and k + 1), searched from `hint`.
	func segment_at(d: float, hint: int) -> int:
		var last := points.size() - 2
		var k := clampi(hint, 0, last)
		while k < last and d > along[k + 1]:
			k += 1
		while k > 0 and d < along[k]:
			k -= 1
		return k

	## The point at distance `d` along the path, on segment k (see segment_at).
	## Before the start or past the end, the first or last segment goes on.
	func point_on(k: int, d: float) -> Vector3:
		var a := along[k]
		var span := along[k + 1] - a
		if span <= 0.0001:
			return points[k]
		return points[k].lerp(points[k + 1], (d - a) / span)


class Lane extends Path:
	var from_node := 0
	var to_node := 0
	## Counted from the center line (0 is next to it, or the left-most on a
	## one-way street), of `lanes` going this way.
	var lane := 0
	var lanes := 1
	## Its signal's phase offset (TrafficSignals), or -1 without one.
	var signal_offset := -1.0
	## Whether it ends at an intersection (else the street just goes on), and
	## whether its street is the widest there: where there's no signal, it has
	## the right of way.
	var at_intersection := false
	var priority := false
	## Unit directions (on the ground) where it starts and ends.
	var start_direction := Vector3.FORWARD
	var end_direction := Vector3.FORWARD
	## Connectors built from its end, by the lane they lead to.
	var connectors := {}
	## The car that left it last (a slot, or -1): until that car is off the
	## connector it took, the next car here keeps its distance from it, whichever
	## way it went.
	var last_exit := -1


class Connector extends Path:
	var in_lane: Lane
	var out_lane: Lane
	var turn := Turn.STRAIGHT
	var box: Box
	## A rough outline on the ground (start, middle, end) for telling whether
	## two connectors cross.
	var outline := PackedVector2Array()
	## Whether it crosses another connector of its box (cached both ways).
	var conflicts := {}
	## Cars holding it (Traffic's slots): from when they're too close to the
	## stop line to stop comfortably until their back is off it.
	var occupants := PackedInt32Array()


## An intersection's box: which of its connectors have cars on them, and the
## connector of a car that has waited long and goes next.
class Box:
	var node := 0
	var busy: Array[Connector] = []
	var claim: Connector
	var claim_slot := -1


## Lanes by tile: Vector2i -> Array[Lane].
var tiles := {}
## Each tile's lanes' total length (m) and, per lane, the running total, for
## picking a random spot on its roads: Vector2i -> PackedFloat32Array.
var tile_totals := {}
## Each tile's lanes' bounding box on the ground (x, z): Vector2i -> Rect2.
var tile_bounds := {}

var _leaving := {}  # node id -> Array[Lane] leaving it
var _arriving := {}  # node id -> Array[Lane] ending at it
var _boxes := {}  # node id -> Box


## Adds a tile's lanes (world-space polylines and their info, see
## CityTileDecoder.TRAFFIC_INFO_STRIDE), replacing any it had. Returns the
## lanes that went (see remove_tile).
func set_tile(key: Vector2i, polylines: Array[PackedVector3Array], info: PackedFloat32Array) -> Array[Lane]:
	var removed := remove_tile(key)
	if polylines.is_empty():
		return removed
	var stride := CityTileDecoder.TRAFFIC_INFO_STRIDE
	var added: Array[Lane] = []
	var totals := PackedFloat32Array()
	var total := 0.0
	var bounds := Rect2(polylines[0][0].x, polylines[0][0].z, 0.0, 0.0)
	for n in polylines.size():
		var points := polylines[n]
		var lane := Lane.new()
		lane.points = points
		lane.measure()
		if lane.length < 0.5:
			continue
		var base := n * stride
		lane.from_node = int(info[base])
		lane.to_node = int(info[base + 1])
		lane.speed = info[base + 2]
		lane.lane = int(info[base + 3])
		lane.lanes = maxi(int(info[base + 4]), 1)
		lane.signal_offset = info[base + 5]
		lane.at_intersection = info[base + 6] > 0.5
		lane.priority = info[base + 6] > 1.5
		lane.start_direction = _flat(points[1] - points[0])
		lane.end_direction = _flat(points[points.size() - 1] - points[points.size() - 2])
		added.append(lane)
		_leaving.get_or_add(lane.from_node, [] as Array[Lane]).append(lane)
		_arriving.get_or_add(lane.to_node, [] as Array[Lane]).append(lane)
		total += lane.length
		totals.append(total)
		for p in points:
			bounds = bounds.expand(Vector2(p.x, p.z))
	if added.is_empty():
		return removed
	tiles[key] = added
	tile_totals[key] = totals
	tile_bounds[key] = bounds
	return removed


## Takes a tile's lanes out of the graph, with every connector into or out of
## them. Returns them (marked removed), so cars on them can go too.
func remove_tile(key: Vector2i) -> Array[Lane]:
	var removed: Array[Lane] = []
	if not tiles.has(key):
		return removed
	removed.assign(tiles[key])
	tiles.erase(key)
	tile_totals.erase(key)
	tile_bounds.erase(key)
	for lane in removed:
		lane.removed = true
		_unlist(_leaving, lane.from_node, lane)
		_unlist(_arriving, lane.to_node, lane)
		for connector: Connector in lane.connectors.values():
			_drop_connector(connector)
		lane.connectors.clear()
		# Connectors into it, from lanes that stay.
		for incoming: Lane in _arriving.get(lane.from_node, []):
			var connector: Connector = incoming.connectors.get(lane)
			if connector:
				_drop_connector(connector)
				incoming.connectors.erase(lane)
	return removed


## The lanes leaving a node.
func leaving(node: int) -> Array:
	return _leaving.get(node, [])


## The lanes ending at a node.
func arriving(node: int) -> Array:
	return _arriving.get(node, [])


## The connector from one lane to another (built the first time it's asked for).
func connector(from: Lane, to: Lane) -> Connector:
	var found: Connector = from.connectors.get(to)
	if found:
		return found
	found = _build_connector(from, to)
	from.connectors[to] = found
	return found


## Picks where a car on `lane` goes next: one of the lanes leaving its end.
## Mostly straight on, keeping its lane number; right turns from the right-most
## lane and left turns from the left-most (or from any lane, where there's no
## way straight on). Never back the way it came unless it's a dead end. Null
## if no lane leaves there (yet).
func pick_next(lane: Lane) -> Lane:
	var outs: Array = leaving(lane.to_node)
	if outs.is_empty():
		return null
	var straight: Array[Lane] = []
	var lefts: Array[Lane] = []
	var rights: Array[Lane] = []
	var backs: Array[Lane] = []
	for out: Lane in outs:
		match turn_between(lane, out):
			Turn.STRAIGHT:
				straight.append(out)
			Turn.LEFT:
				lefts.append(out)
			Turn.RIGHT:
				rights.append(out)
			_:
				backs.append(out)
	if straight.is_empty() and lefts.is_empty() and rights.is_empty():
		return _keep_lane(backs, lane, false)  # a dead end: turn around
	var may_left := lane.lane == 0 or straight.is_empty()
	var may_right := lane.lane == lane.lanes - 1 or straight.is_empty()
	var roll := randf()
	if not straight.is_empty() and (roll < STRAIGHT_SHARE or (lefts.is_empty() or not may_left)
			and (rights.is_empty() or not may_right)):
		return _keep_lane(straight, lane, false)
	if not rights.is_empty() and may_right and (lefts.is_empty() or not may_left or randf() < 0.55):
		return _keep_lane(rights, lane, true)
	if not lefts.is_empty() and may_left:
		return _keep_lane(lefts, lane, false)
	return _keep_lane(straight if not straight.is_empty() else (rights if not rights.is_empty() else lefts), lane, false)


## How a car gets from one lane into another.
func turn_between(from: Lane, to: Lane) -> Turn:
	var a := from.end_direction
	var b := to.start_direction
	var angle := atan2(a.z * b.x - a.x * b.z, a.x * b.x + a.z * b.z)
	if to.to_node == from.from_node and to.from_node == from.to_node and absf(angle) > U_TURN_ANGLE * 0.8:
		return Turn.U_TURN
	if absf(angle) < STRAIGHT_ANGLE:
		return Turn.STRAIGHT
	if absf(angle) > U_TURN_ANGLE:
		return Turn.U_TURN
	# Negative is clockwise seen from above (x east, z south): a right turn.
	return Turn.RIGHT if angle < 0.0 else Turn.LEFT


## Whether a car on `connector` may drive into its intersection now (as car
## `slot`): no connector in use there crosses or merges with it, and (unless
## `with_claims` is off: a car with the right of way where there's no signal)
## no other car has claimed the box with one that does.
func box_free(connector: Connector, slot: int, with_claims := true) -> bool:
	var box := connector.box
	if box == null:
		return true
	for other in box.busy:
		if other != connector and conflict(connector, other):
			return false
	var claimed := box.claim != null and box.claim_slot != slot and box.claim != connector
	if with_claims and claimed and conflict(connector, box.claim):
		return false
	return true


## Whether two connectors of the same box get in each other's way: they cross,
## or lead into the same lane. Connectors out of the same lane never do (the
## cars follow each other).
func conflict(a: Connector, b: Connector) -> bool:
	var known: Variant = a.conflicts.get(b)
	if known != null:
		return known
	var crossing := false
	if a.in_lane != b.in_lane:
		crossing = a.out_lane == b.out_lane
		for i in a.outline.size() - 1:
			for j in b.outline.size() - 1:
				if crossing:
					break
				crossing = Geometry2D.segment_intersects_segment(a.outline[i], a.outline[i + 1], b.outline[j],
					b.outline[j + 1]) != null
	a.conflicts[b] = crossing
	b.conflicts[a] = crossing
	return crossing


func _build_connector(from: Lane, to: Lane) -> Connector:
	var connector := Connector.new()
	connector.in_lane = from
	connector.out_lane = to
	connector.turn = turn_between(from, to)
	var p := from.points[from.points.size() - 1]
	var q := to.points[0]
	var chord := Vector2(q.x - p.x, q.z - p.z).length()
	var points := PackedVector3Array([p])
	if chord > 0.3:
		# A cubic Bezier leaving along the lane coming in and arriving along the
		# one going out; a turn back the way it came swings wide enough to make it.
		var reach := chord * (0.33 if connector.turn == Turn.STRAIGHT else 0.5)
		if connector.turn == Turn.U_TURN:
			reach = maxf(chord, 4.0)
		var c1 := p + from.end_direction * reach
		var c2 := q - to.start_direction * reach
		var steps := clampi(ceili((chord + reach) / CONNECTOR_STEP), 2, 16)
		for k in range(1, steps):
			var t := float(k) / steps
			var u := 1.0 - t
			points.append(p * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + q * (t * t * t))
	points.append(q)
	connector.points = points
	connector.measure()
	connector.speed = maxf(from.speed, to.speed)
	if connector.turn != Turn.STRAIGHT:
		# Through the turn at the speed its radius allows.
		var angle := acos(clampf(from.end_direction.dot(to.start_direction), -1.0, 1.0))
		var radius := connector.length / maxf(angle, 0.1)
		connector.speed = clampf(sqrt(TURN_GRIP * radius), MIN_TURN_SPEED, connector.speed)
	var middle := connector.points[connector.points.size() / 2]
	connector.outline = PackedVector2Array([Vector2(p.x, p.z), Vector2(middle.x, middle.z), Vector2(q.x, q.z)])
	connector.box = _boxes.get_or_add(from.to_node, _new_box(from.to_node))
	return connector


func _new_box(node: int) -> Box:
	var box := Box.new()
	box.node = node
	return box


func _drop_connector(connector: Connector) -> void:
	connector.removed = true
	var box := connector.box
	if box == null:
		return
	box.busy.erase(connector)
	if box.claim == connector:
		box.claim = null
		box.claim_slot = -1
	for other: Connector in connector.conflicts:
		other.conflicts.erase(connector)
	connector.conflicts.clear()
	if box.busy.is_empty() and box.claim == null and not _arriving.has(box.node):
		_boxes.erase(box.node)


## Of `choices` (lanes of one or more streets), the street closest to dead
## ahead and its lane nearest `lane`'s number: the right-most for a right turn.
func _keep_lane(choices: Array[Lane], lane: Lane, right_most: bool) -> Lane:
	var best: Lane = null
	var best_score := INF
	for out in choices:
		var heading := absf(lane.end_direction.signed_angle_to(out.start_direction, Vector3.UP))
		var number := out.lanes - 1 if right_most else mini(lane.lane, out.lanes - 1)
		var score := heading * 10.0 + absf(out.lane - number) + randf() * 0.5
		if score < best_score:
			best_score = score
			best = out
	return best


static func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length_squared() > 1e-8 else Vector3.FORWARD


static func _unlist(index: Dictionary, node: int, lane: Lane) -> void:
	var list: Array = index.get(node, [])
	list.erase(lane)
	if list.is_empty():
		index.erase(node)
