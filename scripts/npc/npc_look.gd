class_name NpcLook
## Colors for the shared mannequin model: pedestrians in everyday colors,
## thugs in dark gang colors. Materials are shared between NPCs of a color.

const PEDESTRIAN_COLORS := [
	Color(0.85, 0.82, 0.75), Color(0.25, 0.32, 0.5), Color(0.6, 0.18, 0.2), Color(0.3, 0.45, 0.3),
	Color(0.9, 0.7, 0.3), Color(0.55, 0.4, 0.6), Color(0.35, 0.35, 0.38), Color(0.8, 0.5, 0.45),
	Color(0.2, 0.55, 0.65), Color(0.65, 0.6, 0.5), Color(0.95, 0.95, 0.95), Color(0.15, 0.15, 0.18),
]
const SKIN_TONES := [
	Color(0.96, 0.8, 0.69), Color(0.87, 0.67, 0.53), Color(0.71, 0.5, 0.36), Color(0.5, 0.33, 0.22),
	Color(0.36, 0.23, 0.16),
]
## [body, joints] per gang.
const GANG_COLORS := [
	[Color(0.1, 0.1, 0.12), Color(0.6, 0.08, 0.06)],
	[Color(0.12, 0.14, 0.2), Color(0.85, 0.45, 0.1)],
	[Color(0.08, 0.08, 0.08), Color(0.2, 0.6, 0.25)],
]

static var _materials := {}


## Paints the mannequin's body (surface 0) and joints (surface 1).
static func paint(model: Node, body: Color, joints: Color) -> void:
	var mesh := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	mesh.set_surface_override_material(0, _material(body))
	mesh.set_surface_override_material(1, _material(joints))


static func paint_pedestrian(model: Node) -> void:
	paint(model, PEDESTRIAN_COLORS.pick_random(), SKIN_TONES.pick_random())


static func paint_thug(model: Node, gang: int) -> void:
	var colors: Array = GANG_COLORS[gang % GANG_COLORS.size()]
	paint(model, colors[0], colors[1])


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.65
		_materials[color] = material
	return _materials[color]
