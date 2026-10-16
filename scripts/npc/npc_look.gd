class_name NpcLook
## Clothes for the shared mannequin model, painted in bands by height
## (shaders/npc.gdshader): pedestrians in everyday New York clothes (mostly
## dark coats and jeans, some bright tops, a few skirts and work clothes),
## thugs in their gang's dark color with its bright color on the joints.
## Every character gets a material of its own, used on both surfaces (two
## draw calls, as before). Instance uniforms would do it with one material,
## but the Compatibility renderer gives each instance that has them 16 vec4s
## of a uniform buffer that holds 1024 on GPUs with 16 kB uniform blocks
## (WebGL 2's minimum): about 60 characters.

const SHADER := preload("res://shaders/npc.gdshader")

## Palettes, in sRGB.
const COATS := [
	Color(0.08, 0.08, 0.09), Color(0.08, 0.08, 0.09), Color(0.2, 0.2, 0.22), Color(0.11, 0.14, 0.24),
	Color(0.24, 0.17, 0.12), Color(0.29, 0.3, 0.2), Color(0.6, 0.47, 0.32), Color(0.34, 0.34, 0.36),
	Color(0.33, 0.1, 0.12), Color(0.12, 0.2, 0.16),
]
const SHIRTS := [
	Color(0.9, 0.9, 0.88), Color(0.9, 0.9, 0.88), Color(0.68, 0.68, 0.68), Color(0.48, 0.48, 0.5),
	Color(0.08, 0.08, 0.09), Color(0.13, 0.16, 0.28), Color(0.6, 0.7, 0.84), Color(0.76, 0.68, 0.56),
	Color(0.36, 0.4, 0.3),
]
const BRIGHT := [
	Color(0.75, 0.12, 0.13), Color(0.92, 0.74, 0.15), Color(0.15, 0.52, 0.3), Color(0.16, 0.3, 0.72),
	Color(0.9, 0.5, 0.6), Color(0.9, 0.45, 0.12), Color(0.1, 0.52, 0.58), Color(0.45, 0.25, 0.6),
]
const JEANS := [Color(0.12, 0.16, 0.27), Color(0.25, 0.33, 0.49), Color(0.44, 0.52, 0.65)]
const TROUSERS := [
	Color(0.08, 0.08, 0.09), Color(0.2, 0.2, 0.22), Color(0.4, 0.4, 0.42), Color(0.58, 0.51, 0.38),
	Color(0.13, 0.16, 0.27),
]
const SUITS := [Color(0.11, 0.13, 0.22), Color(0.2, 0.2, 0.22), Color(0.08, 0.08, 0.09), Color(0.38, 0.38, 0.4)]
const OFFICE_SHIRTS := [Color(0.9, 0.9, 0.88), Color(0.6, 0.7, 0.84)]
const SKIRTS := [
	Color(0.08, 0.08, 0.09), Color(0.11, 0.13, 0.22), Color(0.4, 0.4, 0.42), Color(0.72, 0.62, 0.5),
	Color(0.6, 0.14, 0.16),
]
## Hi-vis yellow and orange with work trousers; a delivery uniform's brown.
const HI_VIS := [Color(0.78, 0.88, 0.14), Color(0.95, 0.45, 0.08)]
const WORK_TROUSERS := [Color(0.12, 0.16, 0.27), Color(0.25, 0.33, 0.49), Color(0.58, 0.51, 0.38)]
const UNIFORM_BROWN := Color(0.32, 0.21, 0.12)
const SHOES := [Color(0.06, 0.06, 0.06), Color(0.06, 0.06, 0.06), Color(0.2, 0.13, 0.08), Color(0.42, 0.42, 0.44)]
const DRESS_SHOES := [Color(0.06, 0.06, 0.06), Color(0.2, 0.13, 0.08)]
const SNEAKERS := Color(0.88, 0.88, 0.86)
const BOOTS := [Color(0.55, 0.4, 0.24), Color(0.2, 0.13, 0.08), Color(0.06, 0.06, 0.06)]
const TIGHTS := Color(0.07, 0.07, 0.08)
const SKIN_TONES := [
	Color(0.92, 0.76, 0.64), Color(0.88, 0.7, 0.56), Color(0.84, 0.64, 0.5), Color(0.74, 0.54, 0.39),
	Color(0.62, 0.43, 0.3), Color(0.5, 0.33, 0.22), Color(0.36, 0.23, 0.16),
]
const HAIR := [
	Color(0.05, 0.04, 0.04), Color(0.05, 0.04, 0.04), Color(0.05, 0.04, 0.04), Color(0.14, 0.09, 0.06),
	Color(0.14, 0.09, 0.06), Color(0.3, 0.2, 0.12), Color(0.55, 0.42, 0.25), Color(0.74, 0.62, 0.4),
	Color(0.4, 0.17, 0.1), Color(0.55, 0.55, 0.55), Color(0.78, 0.78, 0.76),
]
## [dark, bright] per gang: the dark one for their clothes, the bright one on
## the joints.
const GANG_COLORS := [
	[Color(0.1, 0.1, 0.12), Color(0.6, 0.08, 0.06)],
	[Color(0.12, 0.14, 0.2), Color(0.85, 0.45, 0.1)],
	[Color(0.08, 0.08, 0.08), Color(0.2, 0.6, 0.25)],
]

## Rest-pose heights (m) of the shoes' and boots' tops; how far out the arm
## long sleeves reach; hairlines (forehead, nape) for a hat and for none.
const SHOE_TOP := 0.1
const BOOT_TOP := 0.17
const LONG_SLEEVES := 0.7
const HAT := Vector2(1.73, 1.6)
const BALD := Vector2(2.0, 2.0)

## The mannequin's mesh with each vertex's rest-pose position in UV and UV2.
static var _mesh: ArrayMesh


static func paint_pedestrian(model: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_dress(model, _pedestrian_clothes(rng), rng)


## A thug's clothes follow from its `net_id`, so every player in co-op sees
## the same ones.
static func paint_thug(model: Node, gang: int, net_id: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = net_id
	var colors: Array = GANG_COLORS[gang % GANG_COLORS.size()]
	var clothes := {
		top_color = _vary(rng, colors[0]),
		bottom_color = _pick(rng, [JEANS[0], TROUSERS[0], TROUSERS[1]]),
		shoe_color = SNEAKERS if rng.randf() < 0.5 else SHOES[0],
		cuts = Vector4(rng.randf_range(0.86, 0.94), SHOE_TOP, SHOE_TOP, LONG_SLEEVES),
		joint_color = Color(colors[1], 1.0),
	}
	if rng.randf() < 0.3:
		clothes.hair_color = colors[0]  # a beanie
		clothes.hairline = HAT
	_dress(model, clothes, rng)


static func _pedestrian_clothes(rng: RandomNumberGenerator) -> Dictionary:
	var top: Color
	var bottom: Color = _pick(rng, JEANS) if rng.randf() < 0.55 else _pick(rng, TROUSERS)
	var shoes: Color = SNEAKERS if rng.randf() < 0.3 else _pick(rng, SHOES)
	var hem := rng.randf_range(0.9, 0.97)
	var leg_hem := SHOE_TOP
	var shoe_top := SHOE_TOP
	var sleeves := LONG_SLEEVES
	var tights := false
	var kind := rng.randf()
	if kind < 0.4:  # a coat or jacket
		top = _pick(rng, COATS)
		if rng.randf() < 0.4:
			hem = rng.randf_range(0.55, 0.72)
	elif kind < 0.75:  # a T-shirt, sweater or hoodie
		top = _pick(rng, BRIGHT) if rng.randf() < 0.4 else _pick(rng, SHIRTS)
		if rng.randf() < 0.5:
			sleeves = rng.randf_range(0.3, 0.38)
		if rng.randf() < 0.15:  # shorts
			leg_hem = rng.randf_range(0.62, 0.7)
	elif kind < 0.87:  # a suit, or a shirt and dark trousers
		bottom = _pick(rng, SUITS)
		if rng.randf() < 0.6:
			top = bottom
			hem = rng.randf_range(0.82, 0.88)
		else:
			top = _pick(rng, OFFICE_SHIRTS)
		shoes = _pick(rng, DRESS_SHOES)
	elif kind < 0.95:  # a skirt or dress
		top = _pick(rng, BRIGHT) if rng.randf() < 0.3 else _pick(rng, SHIRTS + COATS)
		bottom = top if rng.randf() < 0.3 else _pick(rng, SKIRTS)
		leg_hem = rng.randf_range(0.42, 0.6)
		tights = rng.randf() < 0.5
	else:  # work clothes: hi-vis or a delivery uniform, and boots
		if rng.randf() < 0.7:
			top = _pick(rng, HI_VIS)
			bottom = _pick(rng, WORK_TROUSERS)
		else:
			top = UNIFORM_BROWN
			bottom = UNIFORM_BROWN
		if rng.randf() < 0.4:
			sleeves = rng.randf_range(0.3, 0.38)
		shoes = _pick(rng, BOOTS)
		shoe_top = BOOT_TOP
		leg_hem = BOOT_TOP
	var clothes := {
		top_color = _vary(rng, top),
		bottom_color = _vary(rng, bottom),
		shoe_color = shoes,
		cuts = Vector4(hem, leg_hem, shoe_top, sleeves),
	}
	if tights:
		clothes.legs_color = TIGHTS
	return clothes


## Gives the character under `model` the dressed mesh and a material with
## `clothes` (shader parameters), adding skin, and hair unless it has some.
static func _dress(model: Node, clothes: Dictionary, rng: RandomNumberGenerator) -> void:
	var mesh := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	mesh.mesh = _dressed_mesh(mesh.mesh)
	clothes.skin_color = _pick(rng, SKIN_TONES)
	if not clothes.has("legs_color"):
		clothes.legs_color = clothes.skin_color
	if not clothes.has("hair_color"):
		clothes.hair_color = _pick(rng, HAIR)
		var roll := rng.randf()
		if roll < 0.07:
			clothes.hairline = BALD
		elif roll < 0.15:  # a hat or beanie
			clothes.hair_color = _pick(rng, COATS)
			clothes.hairline = HAT
		else:
			clothes.hairline = Vector2(rng.randf_range(1.74, 1.78), rng.randf_range(1.57, 1.66))
	var material := ShaderMaterial.new()
	material.shader = SHADER
	for parameter in clothes:
		material.set_shader_parameter(parameter, clothes[parameter])
	mesh.material_override = material


## The mannequin's mesh with each vertex's rest-pose position (the T-pose it
## was modeled in) written over its UVs, which nothing else uses: UV = (|x|,
## y), UV2 = (z, 1 on the joints surface). Made once from the first
## character's mesh; the hero keeps the original.
static func _dressed_mesh(original: Mesh) -> ArrayMesh:
	if _mesh != null:
		return _mesh
	_mesh = original.duplicate()
	for surface in _mesh.get_surface_count():
		var vertices: PackedVector3Array = _mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var data: PackedByteArray = RenderingServer.mesh_get_surface(_mesh.get_rid(), surface)["attribute_data"]
		var format := _mesh.surface_get_format(surface)
		var count := vertices.size()
		var stride := RenderingServer.mesh_surface_get_format_attribute_stride(format, count)
		var uv := RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_TEX_UV)
		var uv2 := RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_TEX_UV2)
		for i in count:
			var v := vertices[i]
			data.encode_float(i * stride + uv, absf(v.x))
			data.encode_float(i * stride + uv + 4, v.y)
			data.encode_float(i * stride + uv2, v.z)
			data.encode_float(i * stride + uv2 + 4, float(surface))
		_mesh.surface_update_attribute_region(surface, 0, data)
	return _mesh


## A color a little lighter or darker, so outfits don't repeat exactly.
static func _vary(rng: RandomNumberGenerator, color: Color) -> Color:
	return Color(color * rng.randf_range(0.88, 1.12), 1.0)


static func _pick(rng: RandomNumberGenerator, colors: Array) -> Color:
	return colors[rng.randi() % colors.size()]
