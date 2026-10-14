extends MeshInstance3D
## Keeps the ocean plane under the camera. The shader works in world
## coordinates, so the waves stay put while the plane moves. It also fades the
## ocean into the fog before the plane's edge or the camera's far limit,
## whichever is nearer, so the edge never shows.

const SNAP := 100.0


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var p := camera.global_position
	global_position = Vector3(snappedf(p.x, SNAP), 0.0, snappedf(p.z, SNAP))
	var material := material_override as ShaderMaterial
	material.set_shader_parameter("origin_offset", Vector2(WorldOrigin.offset.x, WorldOrigin.offset.z))

	var edge := minf(camera.far, (mesh as PlaneMesh).size.x * 0.5 - SNAP)
	material.set_shader_parameter("fade_start", edge * 0.6)
	material.set_shader_parameter("fade_end", edge * 0.95)
	var env := get_world_3d().environment
	if env:
		material.set_shader_parameter("fog_color", _linear(env.fog_light_color) * env.fog_light_energy)
		material.set_shader_parameter("fog_density", env.fog_density if env.fog_enabled else 0.0)


func _linear(color: Color) -> Vector3:
	var c := color.srgb_to_linear()
	return Vector3(c.r, c.g, c.b)
