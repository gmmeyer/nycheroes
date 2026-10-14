class_name CombatEffects
extends Node3D
## Visual effects for fights: blood sprays, blood pools under bodies, and the
## shockwave ring and dust of a ground slam. Lives in the "floating" group so
## effects stay put when the world origin shifts.

const MAX_POOLS := 40
const BLOOD_POOL_SHADER := preload("res://shaders/blood_pool.gdshader")
const SHOCKWAVE_SHADER := preload("res://shaders/shockwave_ring.gdshader")

var _drop_mesh: SphereMesh
var _dust_mesh: QuadMesh
var _dust_fade: Gradient
var _plane_mesh: PlaneMesh
var _pool_material: ShaderMaterial
var _pools: Array[Node3D] = []


func _ready() -> void:
	add_to_group("floating")
	Combat.effects = self
	_drop_mesh = _sphere(0.035, _material(Color(0.42, 0.01, 0.01), 0.25))
	_dust_mesh = _soft_puff()
	_dust_fade = Gradient.new()
	_dust_fade.set_color(0, Color(0.78, 0.75, 0.68, 0.55))
	_dust_fade.set_color(1, Color(0.78, 0.75, 0.68, 0.0))
	_plane_mesh = PlaneMesh.new()
	_plane_mesh.size = Vector2.ONE
	_pool_material = ShaderMaterial.new()
	_pool_material.shader = BLOOD_POOL_SHADER


## A spray of blood droplets from `at`, mostly along `direction`.
func blood_burst(at: Vector3, direction: Vector3, amount := 1.0) -> void:
	var spray := _burst(_drop_mesh, at, int(14 * amount) + 6, 0.9)
	spray.direction = direction if direction.length_squared() > 0.01 else Vector3.UP
	spray.spread = 40.0
	spray.initial_velocity_min = 2.0
	spray.initial_velocity_max = 4.0 + 4.0 * amount
	spray.gravity = Vector3(0.0, -18.0, 0.0)
	spray.scale_amount_min = 0.6
	spray.scale_amount_max = 1.8


## A pool of blood spreading on the ground below `at`.
func blood_pool(at: Vector3, size := 1.6) -> void:
	var ground: Variant = _ground_below(at)
	if ground == null:
		return
	var pool := MeshInstance3D.new()
	pool.mesh = _plane_mesh
	pool.material_override = _pool_material
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.position = ground + Vector3.UP * 0.02
	pool.rotation.y = randf() * TAU
	pool.scale = Vector3(0.1, 1.0, 0.1)
	add_child(pool)
	var final_scale := Vector3(size * randf_range(0.8, 1.2), 1.0, size * randf_range(0.8, 1.2))
	create_tween().tween_property(pool, "scale", final_scale, 3.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_pools.append(pool)
	if _pools.size() > MAX_POOLS:
		_pools.pop_front().queue_free()


## A ground slam: an expanding ring and a burst of dust.
func shockwave(at: Vector3, radius: float) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _plane_mesh
	var material := ShaderMaterial.new()
	material.shader = SHOCKWAVE_SHADER
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = at + Vector3.UP * 0.15
	ring.scale = Vector3(0.5, 1.0, 0.5)
	add_child(ring)
	var tween := create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3(radius * 2.4, 1.0, radius * 2.4), 0.45).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("strength", value), 1.0, 0.0, 0.45)
	tween.chain().tween_callback(ring.queue_free)

	var dust := _burst(_dust_mesh, at + Vector3.UP * 0.5, int(radius * 5.0), 1.4)
	dust.direction = Vector3.UP
	dust.spread = 85.0
	dust.flatness = 0.8
	dust.initial_velocity_min = radius * 1.2
	dust.initial_velocity_max = radius * 2.2
	dust.damping_min = radius * 1.5
	dust.damping_max = radius * 2.5
	dust.gravity = Vector3(0.0, 0.5, 0.0)
	dust.scale_amount_min = 1.5
	dust.scale_amount_max = 3.5
	dust.color_ramp = _dust_fade


func _burst(mesh: Mesh, at: Vector3, amount: int, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.mesh = mesh
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.position = at
	add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles


func _ground_below(at: Vector3) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 6.0, Combat.WORLD_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else null


## A camera-facing quad with a soft round falloff, tinted by the particle color.
static func _soft_puff() -> QuadMesh:
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	falloff.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = falloff
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	var mesh := QuadMesh.new()
	mesh.material = material
	return mesh


static func _sphere(radius: float, material: Material) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = material
	return mesh


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
