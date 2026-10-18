extends Node
## Weather: clear skies, rain storms and thick fog roll through every few
## minutes. Rain follows the camera; fog and storms cut visibility, which
## makes thermal vision useful and hiding easier.

enum W { CLEAR, RAIN, FOG }
const NAMES := ["Clear", "Rain", "Fog"]

var current: int = W.CLEAR
var _timer := 240.0
var _blend := 0.0       # 0 clear .. 1 full effect
var _rain: CPUParticles3D
var _rain_sound: AudioStreamPlayer
var _env: Environment
var _base_fog := 0.0024
var _wet := 0.0


func _ready() -> void:
	Game.set_meta("weather", self)


func setup(env: Environment) -> void:
	_env = env
	_base_fog = env.fog_density
	_rain = CPUParticles3D.new()
	_rain.amount = 900
	_rain.lifetime = 1.0
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(28, 1, 28)
	_rain.direction = Vector3.DOWN
	_rain.spread = 3.0
	_rain.initial_velocity_min = 38.0
	_rain.initial_velocity_max = 46.0
	_rain.gravity = Vector3(1.5, -10, 0)
	var drop := BoxMesh.new()
	drop.size = Vector3(0.02, 0.7, 0.02)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = m
	_rain.mesh = drop
	_rain.emitting = false
	add_child(_rain)
	_rain_sound = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://sfx/rain.wav"):
		_rain_sound.stream = load("res://sfx/rain.wav")   # loops via its .import settings
	_rain_sound.volume_db = -60.0
	add_child(_rain_sound)


func set_weather(w: int) -> void:
	if w == current:
		return
	current = w
	_blend = 0.0
	match w:
		W.RAIN: Game.feed("A storm rolls in", Color(0.7, 0.8, 1))
		W.FOG: Game.feed("Thick fog settles over the streets", Color(0.8, 0.8, 0.85))
		W.CLEAR: Game.feed("The skies clear", Color(1, 0.95, 0.8))


func _process(delta: float) -> void:
	if _env == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = randf_range(180.0, 360.0)
		var r := randf()
		set_weather(W.CLEAR if r < 0.5 else (W.RAIN if r < 0.8 else W.FOG))
	_blend = minf(1.0, _blend + delta / 12.0)
	var fog_target := _base_fog
	var rain_on := current == W.RAIN
	match current:
		W.RAIN: fog_target = _base_fog * 2.6
		W.FOG: fog_target = _base_fog * 5.0
	_env.fog_density = lerpf(_env.fog_density, fog_target, delta * 0.3)
	# clouds and wet streets
	var dn: Node = Game.daynight
	if dn:
		var cover_t := 0.45
		var dark_t := 0.0
		match current:
			W.RAIN:
				cover_t = 0.9
				dark_t = 0.75
			W.FOG:
				cover_t = 0.75
				dark_t = 0.35
		dn.cloud_cover = move_toward(dn.cloud_cover, cover_t, delta * 0.03)
		dn.cloud_dark = move_toward(dn.cloud_dark, dark_t, delta * 0.04)
	if Game.city:
		var wet_t := 1.0 if rain_on else 0.0
		_wet = move_toward(_wet, wet_t, delta * (0.08 if rain_on else 0.02))
		Game.city.set_wetness(_wet)
	if Game.interiors and Game.interiors.is_inside():
		rain_on = false
	if rain_on != _rain.emitting:
		_rain.emitting = rain_on
	if Game.player:
		var cam: Camera3D = Game.player.camera
		_rain.global_position = cam.global_position + Vector3(0, 16, 0) + Game.player.velocity * 0.4
	if _rain_sound.stream:
		var want := -14.0 if rain_on else -60.0
		_rain_sound.volume_db = move_toward(_rain_sound.volume_db, want, delta * 8.0)
		if _rain_sound.volume_db > -59.0 and not _rain_sound.playing:
			_rain_sound.play()
		elif _rain_sound.volume_db <= -59.0 and _rain_sound.playing:
			_rain_sound.stop()


func is_bad_weather() -> bool:
	return current != W.CLEAR


func name_text() -> String:
	return NAMES[current]
