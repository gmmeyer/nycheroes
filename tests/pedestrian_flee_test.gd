extends Node
## Headless check that pedestrians running from danger don't get stuck where
## their lane gives out: on a raised plaza (a curb down to the road at x = 12)
## with a bench (0.45 m high) just past one lane's end, it scares one on a
## lane that ends facing away from the danger, and one on a lane that bends
## back toward it, and checks that each keeps running (never sprints in
## place), stays out of the bench and off the road, ends up well past where
## its lane gave out, and once calm walks back onto its lane. They used to
## turn around at the end and back again every frame, sprinting in place
## until they calmed down (crowds of them, at the ends of Times Square's
## plaza lanes). Needs no city tiles.
## Run: godot --headless --path . res://tests/pedestrian_flee_test.tscn

const DT := 1.0 / 60.0
const CURB_X := 12.0
const ROAD_DROP := 0.15
## The bench: x from, x to, half its length (along z), height.
const BENCH := Vector4(10.8, 11.7, 3.0, 0.45)
const SIDE := 0.5
## Frames it may sprint without getting anywhere (leaving the lane mid-frame).
const STALL_FRAMES := 3
## How much further from the danger than where the lane gave out it must get.
const PAST_LANE := 2.0
const RETURN_TIME := 60.0

var _problems := 0


func _ready() -> void:
	_box(Vector3(-40.0, -1.0, -40.0), Vector3(CURB_X, 0.0, 40.0))  # the plaza
	_box(Vector3(CURB_X, -1.0, -40.0), Vector3(60.0, -ROAD_DROP, 40.0))  # the road
	_box(Vector3(BENCH.x, 0.0, -BENCH.z), Vector3(BENCH.y, BENCH.w, BENCH.z))
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Ends facing away from the danger, at the bench.
	_run("lane end", PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)]),
			Vector3(-5.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0))
	# Bends back toward it.
	_run("lane bend", PackedVector3Array([Vector3(0.0, 0.0, -18.0), Vector3(8.0, 0.0, -10.0), Vector3(0.0, 0.0, -2.0)]),
			Vector3(-5.0, 0.0, -10.0), Vector3(8.0, 0.0, -10.0))
	print("pedestrian flee test finished: %d problems" % _problems)
	get_tree().quit(1 if _problems else 0)


## Scares a pedestrian on `lane` from `threat` and follows it until it's back
## on the lane; its lane gives out at `gives_out`.
func _run(label: String, lane: PackedVector3Array, threat: Vector3, gives_out: Vector3) -> void:
	var pedestrian: Pedestrian = load("res://scenes/npc/pedestrian.tscn").instantiate()
	add_child(pedestrian)
	pedestrian.process_mode = Node.PROCESS_MODE_DISABLED  # moved by hand below
	pedestrian.visible = false  # (no screams)
	pedestrian.setup(null, lane, 0, 0.3)
	pedestrian._side = SIDE
	pedestrian._move(0.0)
	pedestrian.scare(threat)
	var start := _flat(pedestrian.world_position, threat)
	var stalls := 0
	var trespasses := 0
	var furthest := 0.0
	var time := 0.0
	var calm_at := -1.0
	while time < 120.0:
		var before := pedestrian.world_position
		var speed := pedestrian._walk(DT)
		time += DT
		var moved := Vector2(pedestrian.world_position.x - before.x, pedestrian.world_position.z - before.z).length()
		if speed > 0.0 and moved < speed * DT * 0.5:
			stalls += 1
		if _trespassing(pedestrian.world_position):
			trespasses += 1
		if pedestrian.is_panicking():
			furthest = maxf(furthest, _flat(pedestrian.world_position, threat))
		elif calm_at < 0.0:
			calm_at = time
		if calm_at >= 0.0 and (time > calm_at + RETURN_TIME or _on_lane(pedestrian.world_position, lane)):
			break
	var needed := _flat(gives_out, threat) + PAST_LANE
	var back := _on_lane(pedestrian.world_position, lane)
	print("%s: from %.1f m to %.1f m from the danger (needs %.1f), %d frames sprinting in place, %d in the bench or road, %s"
			% [label, start, furthest, needed, stalls, trespasses,
			"back on its lane %.1f s after calming down" % (time - calm_at) if back else "never back on its lane"])
	if stalls > STALL_FRAMES or trespasses > 0 or furthest < needed or not back:
		_problems += 1
	pedestrian.queue_free()


func _trespassing(at: Vector3) -> bool:
	var in_bench := at.x > BENCH.x and at.x < BENCH.y and absf(at.z) < BENCH.z
	return in_bench or at.x > CURB_X


## Whether `at` is SIDE from the lane, walking along it (to its left or right).
func _on_lane(at: Vector3, lane: PackedVector3Array) -> bool:
	for k in lane.size() - 1:
		var flat := Geometry3D.get_closest_point_to_segment(at, lane[k], lane[k + 1])
		if absf(flat.distance_to(at) - SIDE) < 0.05:
			return true
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _box(from: Vector3, to: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = CityStreamer.COLLISION_LAYER
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = to - from
	shape.position = (from + to) * 0.5
	body.add_child(shape)
	add_child(body)
