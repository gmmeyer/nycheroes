class_name HeroMode
extends Node
## One way the hero moves (on foot, flying, swinging). The Hero runs whichever
## mode is active; modes are its child nodes and are named by their node name.

var hero: Hero


func enter(_previous: StringName) -> void:
	pass


func exit() -> void:
	pass


## Sets hero.velocity and moves the hero. Returns the mode to switch to, or &"" to stay.
func physics_update(_delta: float) -> StringName:
	return &""
