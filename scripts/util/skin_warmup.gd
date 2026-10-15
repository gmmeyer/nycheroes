class_name SkinWarmup
extends VisibleOnScreenNotifier3D
## Animates a character only while it's on screen, and holds its pose for a
## moment the first time it is, which keeps it cheap to draw in browsers on
## Windows. Web builds only.
##
## There, WebGL runs on Direct3D 11 through ANGLE. The Compatibility renderer
## skins each character on the GPU into its own vertex buffer, and ANGLE treats
## that buffer as "dynamic": after every change, the next draw copies the
## vertices back from the GPU (waiting for it), and every draw uploads them
## again. Once a buffer has been drawn enough times without changing, ANGLE
## draws it in place for good. A moving character never stays still that long
## by itself, so this holds its pose until it has. Even then each skinning pass
## costs a little (on NVIDIA, ANGLE flushes the GPU queue after each one), so
## off screen the pose stays put too: thugs still cast shadows there, and a
## still shadow costs nothing. Without this, Times Square with 45 pedestrians
## and 9 thugs ran at ~15-25 FPS on a busy GPU.

## Frames on screen to hold the pose for. ANGLE switched after about 25-30 in tests.
const HOLD_FRAMES := 40

## True while the pose is held on screen (pedestrians stand still meanwhile).
var holding := false

var _player: AnimationPlayer
var _player_mode := Node.PROCESS_MODE_INHERIT
var _hold_animation := &""
var _posed := false
var _frames_left := HOLD_FRAMES


## Gives the animated character under `model` (a mannequin with an
## AnimationPlayer) a warm-up, and returns it (null when not needed). With
## `hold_animation`, switches to that animation (say, standing idle) to hold.
static func add_to(model: Node, hold_animation := &"") -> SkinWarmup:
	if not OS.has_feature("web"):
		return null
	var mesh := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var warmup := SkinWarmup.new()
	warmup._player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	warmup._player_mode = warmup._player.process_mode
	warmup._hold_animation = hold_animation
	warmup.aabb = mesh.get_aabb()
	mesh.add_child(warmup)
	# Anything that moves the bones (the animation, a seek, a ragdoll) starts the count over.
	(mesh.get_node(mesh.skeleton) as Skeleton3D).skeleton_updated.connect(warmup._start_over)
	return warmup


func _process(_delta: float) -> void:
	if not _posed:
		_posed = true  # let the animation pose the character once first
		return
	var on_screen := is_on_screen()
	var hold := on_screen and _frames_left > 0
	if hold and not holding and _hold_animation != &"" and _player.active:
		_player.play(_hold_animation, 0.0)
		_player.advance(0.0)
	holding = hold
	var animate := on_screen and not hold
	_player.process_mode = _player_mode if animate else Node.PROCESS_MODE_DISABLED
	if hold:
		_frames_left -= 1


func _start_over() -> void:
	if _frames_left > 0:
		_frames_left = HOLD_FRAMES
