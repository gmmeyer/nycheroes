class_name HeroInput
extends RefCounted
## One physics tick of control input for a Hero. PlayerInput fills it for the
## local player; a network peer could fill it for a remote one.

## Movement stick: x = right, y = back (like Input.get_vector).
var stick := Vector2.ZERO
## Stick turned into a world-space direction on the ground, relative to the camera.
var move := Vector3.ZERO
## Where the camera looks (unit vector, world space). Flight and webs follow it.
var aim := Vector3.FORWARD
## Climb/descend while flying: +1 up, -1 down.
var vertical := 0.0
var jump_held := false
var sprint_held := false
var web_held := false
var attack_held := false
## One-shot: set by the input source, cleared by the hero after it's handled.
var fly_toggle_pressed := false


func clear() -> void:
	stick = Vector2.ZERO
	move = Vector3.ZERO
	vertical = 0.0
	jump_held = false
	sprint_held = false
	web_held = false
	attack_held = false
	fly_toggle_pressed = false
