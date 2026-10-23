extends Node
## Headless check that pedestrians keep to their side of a lane up steps:
## walks one up and back down a lane like the TKTS steps' (times_square.py's
## step_lanes(): 27 risers of 18 cm, each 10 cm of lane, between treads),
## stepped aside as far as dodging takes it, and checks every move that it
## stays that far from the lane. Steep bits of lane used to pull it toward
## the lane, so it jumped sideways at every step. Needs no city tiles.
## Run: godot --headless --path . res://tests/pedestrian_steps_test.tscn

const AVENUE := Vector3(0.485, 0.0, -0.875)
const RISERS := 27
const RISE := 4.9 / RISERS
const RUN := 0.45
const APPROACH := 4.0
## Each move's length (m along the lane), and how far off its side may be.
const MOVE := 0.01
const TOLERANCE := 0.01


func _ready() -> void:
	var lane := PackedVector3Array([-AVENUE * APPROACH, -AVENUE * 0.05])
	for k in RISERS:
		var height := Vector3.UP * (k + 1) * RISE
		lane.append(AVENUE * (k * RUN + 0.05) + height)
		lane.append(AVENUE * ((k + 1) * RUN - 0.05) + height)
	var pedestrian: Pedestrian = load("res://scenes/npc/pedestrian.tscn").instantiate()
	add_child(pedestrian)
	pedestrian.process_mode = Node.PROCESS_MODE_DISABLED  # moved by hand below
	pedestrian.setup(null, lane, 0, 0.0)
	var problems := 0
	for side in [Pedestrian.MAX_SIDE_STEP, -0.8]:
		pedestrian._side = side
		var worst := 0.0
		var moves := 0
		for heading in [1.0, -1.0]:
			pedestrian._heading = heading
			var steps := 0
			while steps < 4000 and pedestrian._heading == heading:
				pedestrian._move(MOVE)
				steps += 1
				var flat := pedestrian.world_position - lane[0]
				var across := Vector3(-AVENUE.z, 0.0, AVENUE.x)
				worst = maxf(worst, absf(flat.dot(across) - side))
			moves += steps
		print("side %.1f m: %d moves up and down the steps, at most %.3f m off it" % [side, moves, worst])
		if worst > TOLERANCE:
			problems += 1
	print("pedestrian steps test finished: %d problems" % problems)
	get_tree().quit(1 if problems else 0)
