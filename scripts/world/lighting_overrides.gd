extends WorldEnvironment
## Lighting overrides from launch options, for tuning without re-exporting:
## ?ambient=0.5&sun=1.2&tonemap=2&exposure=1&white=1&fog=0.00005&sky=1
## ?agx_contrast=1.25&agx_white=16 (AgX tonemapping), ?saturation=1.1
## ?sun_dir=235,42 points the sun from that azimuth (degrees clockwise from
## north) and elevation (degrees above the horizon); ?sun_color=1,0.93,0.8 (sRGB).
## ?sh_<uniform>=<value> sets a uniform of the city's building and ground
## shaders and the sky shader, wherever it exists: one number, or
## comma-separated numbers for vectors and colors (sRGB), e.g.
## ?sh_ambient_energy=0.6&sh_toon_softness=0.05&sh_zenith_color=0.3,0.5,0.85

## Launch options starting with this set shader uniforms.
const SHADER_OPTION_PREFIX := "sh_"

@export var sun: DirectionalLight3D
## Its building and ground materials take the sh_ options.
@export var city: CityStreamer


func _ready() -> void:
	var env := environment
	if LaunchOptions.has("ambient"):
		env.ambient_light_energy = _float("ambient")
	if LaunchOptions.has("tonemap"):
		env.tonemap_mode = int(_float("tonemap")) as Environment.ToneMapper
	if LaunchOptions.has("exposure"):
		env.tonemap_exposure = _float("exposure")
	if LaunchOptions.has("white"):
		env.tonemap_white = _float("white")
	if LaunchOptions.has("agx_contrast"):
		env.tonemap_agx_contrast = _float("agx_contrast")
	if LaunchOptions.has("agx_white"):
		env.tonemap_agx_white = _float("agx_white")
	if LaunchOptions.has("saturation"):
		env.adjustment_enabled = true
		env.adjustment_saturation = _float("saturation")
	if LaunchOptions.has("fog"):
		env.fog_density = _float("fog")
	if LaunchOptions.has("sky"):
		env.background_energy_multiplier = _float("sky")
	if LaunchOptions.has("sun"):
		sun.light_energy = _float("sun")
	var angles := LaunchOptions.get_floats("sun_dir")
	if angles.size() == 2:
		sun.rotation = sun_rotation(angles[0], angles[1])
	var sun_color := LaunchOptions.get_floats("sun_color")
	if sun_color.size() == 3:
		sun.light_color = Color(sun_color[0], sun_color[1], sun_color[2])
	_apply_shader_options()


## The rotation that shines a directional light from the sun at `azimuth`
## (degrees clockwise from north) and `elevation` (degrees above the horizon).
## World x is east and z south; the light shines along its -z axis.
static func sun_rotation(azimuth: float, elevation: float) -> Vector3:
	return Vector3(deg_to_rad(-elevation), deg_to_rad(180.0 - azimuth), 0.0)


func _apply_shader_options() -> void:
	var materials: Array[ShaderMaterial] = []
	if city:
		for material in [city.building_material, city.ground_material]:
			if material is ShaderMaterial:
				materials.append(material)
	if environment.sky and environment.sky.sky_material is ShaderMaterial:
		materials.append(environment.sky.sky_material)
	for material in materials:
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var option := SHADER_OPTION_PREFIX + String(uniform.name)
			if LaunchOptions.has(option):
				material.set_shader_parameter(uniform.name, _shader_value(LaunchOptions.get_floats(option), uniform.type))


## Launch option numbers as a value of the uniform's type.
static func _shader_value(numbers: PackedFloat64Array, type: int) -> Variant:
	var n := numbers.size()
	match type:
		TYPE_BOOL:
			return n > 0 and numbers[0] != 0.0
		TYPE_INT:
			return int(numbers[0]) if n > 0 else 0
		TYPE_VECTOR2 when n >= 2:
			return Vector2(numbers[0], numbers[1])
		TYPE_VECTOR3 when n >= 3:
			return Vector3(numbers[0], numbers[1], numbers[2])
		TYPE_COLOR when n >= 3:
			return Color(numbers[0], numbers[1], numbers[2], numbers[3] if n >= 4 else 1.0)
	return numbers[0] if n > 0 else 0.0


func _float(name: String) -> float:
	return LaunchOptions.get_string(name).to_float()
