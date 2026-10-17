class_name HeroOutfit
extends Node3D
## Accessories are batched per bone and material (no cloth simulation). All
## dimensions below are in the mannequin's rest space; inverse bind transforms
## place them on the correct animated bone, including forearms, shins and feet.
const SUIT_SHADER := preload("res://shaders/hero_suit.gdshader")
const CAPE_SHADER := preload("res://shaders/hero_cape.gdshader")
static var _body_mesh: ArrayMesh
var profile: Dictionary
var _skeleton: Skeleton3D
var _body: MeshInstance3D
var _batches := {}
var _attachments := {}
var _materials := {}
var _cape: ShaderMaterial

func setup(skeleton: Skeleton3D, body: MeshInstance3D, value: Dictionary) -> void:
	_skeleton = skeleton
	_body = body
	apply(value)

func apply(value: Dictionary) -> void:
	var validated := HeroAppearance.sanitize(value)
	if profile == validated:
		return
	profile = validated
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_batches.clear()
	_attachments.clear()
	_materials.clear()
	_cape = null
	_paint_body()
	for key: String in ["primary", "secondary", "accent", "skin", "hair_color"]:
		var material := StandardMaterial3D.new()
		material.albedo_color = HeroAppearance.color(profile, key)
		material.roughness = 0.65 if key in ["skin", "hair_color"] else 0.42
		material.metallic = 0.45 if profile.suit == "mech" and key in ["primary", "secondary"] else 0.0
		_materials[key] = material
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("101725")
	dark.roughness = 0.3
	_materials["dark"] = dark
	_face()
	_hair()
	_boots()
	_headgear()
	_belt()
	if profile.suit == "mech":
		_mech()
	if profile.cape != "none":
		_make_cape()
	_finish_batches()

func set_motion(speed: float) -> void:
	if _cape:
		_cape.set_shader_parameter("motion", clampf(speed / 45.0, 0.0, 1.0))

func _paint_body() -> void:
	if _body_mesh == null:
		_body_mesh = ArrayMesh.new()
		for surface in _body.mesh.get_surface_count():
			var arrays := _body.mesh.surface_get_arrays(surface)
			var coords := PackedVector2Array()
			for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				coords.append(Vector2(point.x, point.y))
			arrays[Mesh.ARRAY_TEX_UV2] = coords
			_body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_body.mesh = _body_mesh
	var style: int = HeroAppearance.OPTIONS.suit.find(profile.suit)
	for surface in _body.mesh.get_surface_count():
		var material := ShaderMaterial.new()
		material.shader = SUIT_SHADER
		for key: String in ["primary", "secondary", "accent"]:
			material.set_shader_parameter(key, HeroAppearance.color(profile, key))
		material.set_shader_parameter("skin_color", HeroAppearance.color(profile, "skin"))
		material.set_shader_parameter("suit_style", style)
		material.set_shader_parameter("boot_height", 0.22 if profile.boots == "ankle" else 0.49)
		material.set_shader_parameter("joints", surface == 1)
		_body.set_surface_override_material(surface, material)

func _attach(bone: String) -> BoneAttachment3D:
	var existing: BoneAttachment3D = _attachments.get(bone)
	if existing:
		return existing
	var attachment := BoneAttachment3D.new()
	attachment.name = bone
	attachment.use_external_skeleton = true
	attachment.external_skeleton = NodePath("../..")
	attachment.bone_name = bone
	add_child(attachment)
	_attachments[bone] = attachment
	return attachment

func _part(bone: String, mesh: Mesh, center: Vector3, scale_size: Vector3, material: String, rotation := Vector3.ZERO) -> void:
	var key := bone + ":" + material
	if not _batches.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = surface
	var rest := _skeleton.get_bone_global_rest(_skeleton.find_bone(bone))
	var placement := Transform3D(Basis.from_euler(rotation).scaled(scale_size), center)
	(_batches[key] as SurfaceTool).append_from(mesh, 0, rest.affine_inverse() * placement)

func _sphere(bone: String, center: Vector3, dimensions: Vector3, material: String) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	_part(bone, mesh, center, dimensions, material)

func _box(bone: String, center: Vector3, dimensions: Vector3, material: String, rotation := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	_part(bone, mesh, center, dimensions, material, rotation)

func _finish_batches() -> void:
	var meshes := {}
	for key: String in _batches:
		var pieces := key.split(":")
		var bone := pieces[0]
		var mesh: ArrayMesh = meshes.get(bone, ArrayMesh.new())
		var surface: SurfaceTool = _batches[key]
		surface.set_material(_materials[pieces[1]])
		surface.commit(mesh)
		meshes[bone] = mesh
	for bone: String in meshes:
		var instance := MeshInstance3D.new()
		instance.name = "Accessories"
		instance.mesh = meshes[bone]
		_attach(bone).add_child(instance)
	_batches.clear()

func _face() -> void:
	# Simple original stylized facial details, visible with an open face.
	for side in [-1.0, 1.0]:
		_sphere("DEF-head", Vector3(side * 0.116, 1.693, 0.012), Vector3(0.046, 0.072, 0.044), "skin")
		_sphere("DEF-head", Vector3(side * 0.044, 1.708, 0.113), Vector3(0.027, 0.019, 0.022), "dark")
	_sphere("DEF-head", Vector3(0.0, 1.68, 0.12), Vector3(0.026, 0.043, 0.026), "skin")

func _hair() -> void:
	if profile.hair == "none" or profile.headgear == "helmet":
		return
	var head := "DEF-head"
	if profile.hair in ["crop", "swept", "ponytail"]:
		_sphere(head, Vector3(0, 1.795, 0.006), Vector3(0.245, 0.105, 0.24), "hair_color")
		_sphere(head, Vector3(0, 1.744, -0.066), Vector3(0.23, 0.14, 0.13), "hair_color")
	if profile.hair == "swept":
		for i in 4:
			_sphere(head, Vector3(-0.082 + i * 0.052, 1.816 + i * 0.009, 0.034 - i * 0.018), Vector3(0.092, 0.11, 0.21), "hair_color")
	elif profile.hair == "curls":
		for ring in 2:
			for i in 9:
				var angle := TAU * i / 9.0
				_sphere(head, Vector3(cos(angle) * (0.105 - ring * 0.045), 1.79 + ring * 0.065, sin(angle) * (0.10 - ring * 0.035)), Vector3.ONE * 0.105, "hair_color")
	elif profile.hair == "crest":
		_sphere(head, Vector3(0, 1.79, 0), Vector3(0.24, 0.09, 0.22), "hair_color")
		for i in 5:
			_sphere(head, Vector3(0, 1.842 + sin(i / 4.0 * PI) * 0.045, -0.085 + i * 0.041), Vector3(0.075, 0.14, 0.08), "hair_color")
	elif profile.hair == "ponytail":
		_sphere(head, Vector3(0, 1.75, -0.17), Vector3(0.10, 0.12, 0.13), "accent")
		_sphere(head, Vector3(0, 1.61, -0.20), Vector3(0.125, 0.30, 0.13), "hair_color")

func _boots() -> void:
	for side in [-1.0, 1.0]:
		var suffix := ".L" if side > 0 else ".R"
		var x: float = side * 0.089
		_sphere("DEF-foot" + suffix, Vector3(x, 0.07, 0.055), Vector3(0.147, 0.115, 0.31), "secondary")
		_box("DEF-foot" + suffix, Vector3(x, 0.022, 0.065), Vector3(0.145, 0.035, 0.27), "dark")
		if profile.boots == "armored":
			_box("DEF-shin" + suffix, Vector3(x, 0.30, 0.025), Vector3(0.15, 0.34, 0.17), "primary")
			_box("DEF-shin" + suffix, Vector3(x, 0.35, 0.119), Vector3(0.035, 0.23, 0.016), "accent")
		elif profile.boots == "tall":
			_sphere("DEF-shin" + suffix, Vector3(x, 0.39, 0.003), Vector3(0.145, 0.14, 0.15), "secondary")
			_box("DEF-shin" + suffix, Vector3(x, 0.432, 0.083), Vector3(0.075, 0.025, 0.02), "accent")

func _headgear() -> void:
	var head := "DEF-head"
	match profile.headgear:
		"visor":
			_sphere(head, Vector3(0, 1.707, 0.10), Vector3(0.25, 0.08, 0.098), "secondary")
			_box(head, Vector3(0, 1.709, 0.151), Vector3(0.185, 0.032, 0.012), "accent")
		"mask":
			for side in [-1.0, 1.0]:
				_sphere(head, Vector3(side * 0.05, 1.71, 0.115), Vector3(0.10, 0.065, 0.043), "secondary")
				_sphere(head, Vector3(side * 0.05, 1.712, 0.139), Vector3(0.049, 0.021, 0.013), "accent")
			_box(head, Vector3(0, 1.71, 0.139), Vector3(0.035, 0.026, 0.02), "secondary")
		"crown":
			_sphere(head, Vector3(0, 1.765, 0.012), Vector3(0.252, 0.035, 0.24), "accent")
			_box(head, Vector3(0, 1.785, 0.131), Vector3(0.052, 0.075, 0.025), "accent", Vector3(0, 0, PI / 4.0))
		"helmet":
			_sphere(head, Vector3(0, 1.704, 0.0), Vector3(0.29, 0.32, 0.285), "primary")
			_sphere(head, Vector3(0, 1.713, 0.114), Vector3(0.245, 0.105, 0.10), "dark")
			_box(head, Vector3(0, 1.722, 0.169), Vector3(0.19, 0.028, 0.014), "accent")
			_box(head, Vector3(0, 1.622, 0.123), Vector3(0.115, 0.04, 0.058), "secondary")

func _belt() -> void:
	_sphere("DEF-hips", Vector3(0, 1.013, -0.005), Vector3(0.335, 0.048, 0.245), "secondary")
	_box("DEF-hips", Vector3(0, 1.015, 0.125), Vector3(0.07, 0.052, 0.025), "accent")

func _mech() -> void:
	_sphere("DEF-spine.003", Vector3(0, 1.353, 0.012), Vector3(0.46, 0.28, 0.33), "primary")
	_box("DEF-spine.003", Vector3(0, 1.34, 0.19), Vector3(0.085, 0.095, 0.032), "accent", Vector3(0, 0, PI / 4.0))
	_box("DEF-spine.002", Vector3(0, 1.18, 0.10), Vector3(0.26, 0.10, 0.10), "secondary")
	for side in [-1.0, 1.0]:
		var suffix := ".L" if side > 0 else ".R"
		_sphere("DEF-upper_arm" + suffix, Vector3(side * 0.265, 1.454, -0.06), Vector3(0.26, 0.25, 0.29), "primary")
		_box("DEF-upper_arm" + suffix, Vector3(side * 0.27, 1.57, -0.055), Vector3(0.15, 0.025, 0.17), "accent")
		_sphere("DEF-forearm" + suffix, Vector3(side * 0.61, 1.44, -0.065), Vector3(0.245, 0.18, 0.20), "primary")
		_box("DEF-forearm" + suffix, Vector3(side * 0.61, 1.454, 0.042), Vector3(0.15, 0.05, 0.02), "accent")
		_sphere("DEF-thigh" + suffix, Vector3(side * 0.09, 0.753, 0.01), Vector3(0.20, 0.31, 0.22), "primary")
		_sphere("DEF-shin" + suffix, Vector3(side * 0.089, 0.48, 0.035), Vector3(0.18, 0.15, 0.19), "primary")

func _make_cape() -> void:
	_cape = ShaderMaterial.new()
	_cape.shader = CAPE_SHADER
	_cape.set_shader_parameter("cape_color", HeroAppearance.color(profile, "primary"))
	_cape.set_shader_parameter("trim_color", HeroAppearance.color(profile, "accent"))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rest := _skeleton.get_bone_global_rest(_skeleton.find_bone("DEF-spine.003")).affine_inverse()
	var length := 0.6 if profile.cape == "short" else 1.12
	var columns := 12
	var rows := 14
	for row in rows:
		for col in columns:
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var u := float(col + corner.x) / columns
				var v := float(row + corner.y) / rows
				var tail := v
				if profile.cape == "split":
					tail *= 1.0 - 0.26 * pow(1.0 - abs(u * 2.0 - 1.0), 8.0)
				var point := Vector3((u - 0.5) * (0.38 + v * 0.40), 1.46 - tail * length, -0.155 - v * 0.14 - sin(u * PI * 6.0) * v * 0.016)
				surface.set_uv(Vector2(u, v))
				surface.add_vertex(rest * point)
	surface.generate_normals()
	surface.set_material(_cape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Cape"
	mesh.mesh = surface.commit()
	# Vertex motion needs a slightly wider bound than the resting cloth.
	mesh.extra_cull_margin = 0.7
	_attach("DEF-spine.003").add_child(mesh)
	for side in [-1.0, 1.0]:
		_sphere("DEF-spine.003", Vector3(side * 0.15, 1.45, -0.14), Vector3(0.065, 0.04, 0.045), "accent")
