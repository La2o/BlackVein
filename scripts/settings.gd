extends Node
## Player settings: mouse and stick sensitivity, invert Y, field of view,
## volume, graphics quality, camera shake and controller rumble.
## Saved to user://settings.cfg and applied immediately.

signal changed

const PATH := "user://settings.cfg"

var mouse_sensitivity := 1.0     # multiplier
var stick_sensitivity := 1.0     # multiplier
var invert_y := false
var fov := 72.0
var volume := 0.8
var quality := 2                 # 0 low, 1 medium, 2 high
var camera_shake := 1.0
var rumble := true
var show_fps := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	stick_sensitivity = cfg.get_value("controls", "stick_sensitivity", stick_sensitivity)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	rumble = cfg.get_value("controls", "rumble", rumble)
	fov = cfg.get_value("video", "fov", fov)
	quality = cfg.get_value("video", "quality", quality)
	camera_shake = cfg.get_value("video", "camera_shake", camera_shake)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	volume = cfg.get_value("audio", "volume", volume)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "stick_sensitivity", stick_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "rumble", rumble)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "camera_shake", camera_shake)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("audio", "volume", volume)
	cfg.save(PATH)


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)
	var vp := get_viewport()
	match quality:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = 0.75
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
		1:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 0.9
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
		_:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 1.0
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
	if Game.world:
		var we := Game.world.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we:
			we.environment.ssao_enabled = quality >= 2
			we.environment.glow_enabled = quality >= 1
		var sun := Game.world.get_node_or_null("Sun") as DirectionalLight3D
		if sun:
			sun.directional_shadow_max_distance = [90.0, 160.0, 220.0][quality]
	changed.emit()
