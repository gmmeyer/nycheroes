extends MeshInstance3D
## Keeps the ocean plane under the camera. The shader works in world
## coordinates, so the waves stay put while the plane moves.

const SNAP := 100.0


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var p := camera.global_position
	global_position = Vector3(snappedf(p.x, SNAP), 0.0, snappedf(p.z, SNAP))
	var material := material_override as ShaderMaterial
	material.set_shader_parameter("origin_offset", Vector2(WorldOrigin.offset.x, WorldOrigin.offset.z))
