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
var music_volume := 0.55
var quality := 2                 # 0 low, 1 medium, 2 high
var camera_shake := 1.0
var rumble := true
var show_fps := false
var crowd_density := 1.0         # 0.4 .. 1.2, scales people and traffic
var last_seen_version := ""
var damage_numbers := false
var bindings := {}               # action -> {"key": physical keycode} or {"mouse": button index}

const REBINDABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"], ["move_right", "Move right"],
	["sprint", "Sprint"], ["jump", "Jump / glide"], ["dash", "Dash"], ["attack", "Attack"], ["special", "Special move"],
	["grab", "Grab / throw / hijack"], ["consume", "Consume"], ["tether", "Tether"], ["focus", "Focus"],
	["thermal", "Thermal vision"], ["decoy", "Decoy"], ["cycle_defense", "Shield / armor"],
	["devastator_spikes", "Groundspike"], ["devastator_tendrils", "Tendril Barrage"], ["artillery", "Artillery"],
	["evolve_menu", "Skills menu"], ["map", "Map"],
]
var _defaults := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# remember the default keyboard/mouse events so "reset" can restore them
	for pair in REBINDABLE:
		var a: String = pair[0]
		var evs: Array = []
		for e in InputMap.action_get_events(a):
			if e is InputEventKey or e is InputEventMouseButton:
				evs.append(e)
		_defaults[a] = evs
	load_settings()
	apply_bindings()
	apply()


func apply_bindings() -> void:
	for pair in REBINDABLE:
		var a: String = pair[0]
		if not bindings.has(a):
			continue
		for e in InputMap.action_get_events(a):
			if e is InputEventKey or e is InputEventMouseButton:
				InputMap.action_erase_event(a, e)
		var b: Dictionary = bindings[a]
		if b.has("key"):
			var k := InputEventKey.new()
			k.physical_keycode = int(b["key"])
			InputMap.action_add_event(a, k)
		elif b.has("mouse"):
			var m := InputEventMouseButton.new()
			m.button_index = int(b["mouse"])
			InputMap.action_add_event(a, m)
	changed.emit()


func bind(action: String, event: InputEvent) -> void:
	if event is InputEventKey:
		bindings[action] = {"key": (event as InputEventKey).physical_keycode}
	elif event is InputEventMouseButton:
		bindings[action] = {"mouse": (event as InputEventMouseButton).button_index}
	apply_bindings()
	save_settings()


func reset_bindings() -> void:
	bindings.clear()
	for a in _defaults:
		for e in InputMap.action_get_events(a):
			if e is InputEventKey or e is InputEventMouseButton:
				InputMap.action_erase_event(a, e)
		for e in _defaults[a]:
			InputMap.action_add_event(a, e)
	save_settings()
	changed.emit()


## Human-readable name of the first keyboard/mouse input bound to an action.
func key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var phys := (e as InputEventKey).physical_keycode
			if DisplayServer.get_name() == "headless":
				return OS.get_keycode_string(phys)
			return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(phys))
		if e is InputEventMouseButton:
			match (e as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
				MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
				_: return "Mouse %d" % (e as InputEventMouseButton).button_index
	return "—"


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
	crowd_density = cfg.get_value("video", "crowd_density", crowd_density)
	last_seen_version = cfg.get_value("meta", "last_seen_version", "")
	damage_numbers = cfg.get_value("video", "damage_numbers", false)
	volume = cfg.get_value("audio", "volume", volume)
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	bindings = cfg.get_value("controls", "bindings", {})


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
	cfg.set_value("video", "crowd_density", crowd_density)
	cfg.set_value("meta", "last_seen_version", last_seen_version)
	cfg.set_value("video", "damage_numbers", damage_numbers)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("controls", "bindings", bindings)
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
