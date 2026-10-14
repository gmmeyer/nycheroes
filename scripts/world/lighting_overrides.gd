extends WorldEnvironment
## Lighting overrides from launch options, for tuning without re-exporting:
## ?ambient=0.5&sun=1.2&tonemap=2&exposure=1&white=1&fog=0.00005&sky=1

@export var sun: DirectionalLight3D


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
	if LaunchOptions.has("fog"):
		env.fog_density = _float("fog")
	if LaunchOptions.has("sky"):
		env.background_energy_multiplier = _float("sky")
	if LaunchOptions.has("sun"):
		sun.light_energy = _float("sun")


func _float(name: String) -> float:
	return LaunchOptions.get_string(name).to_float()
