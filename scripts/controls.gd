extends Node
## Sets up keyboard, mouse and gamepad controls when the game starts,
## so nothing has to be configured by hand in the editor.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Movement
	_add("move_forward", [_k(KEY_W), _k(KEY_UP), _ja(JOY_AXIS_LEFT_Y, -1.0)])
	_add("move_back", [_k(KEY_S), _k(KEY_DOWN), _ja(JOY_AXIS_LEFT_Y, 1.0)])
	_add("move_left", [_k(KEY_A), _k(KEY_LEFT), _ja(JOY_AXIS_LEFT_X, -1.0)])
	_add("move_right", [_k(KEY_D), _k(KEY_RIGHT), _ja(JOY_AXIS_LEFT_X, 1.0)])
	_add("look_left", [_ja(JOY_AXIS_RIGHT_X, -1.0)])
	_add("look_right", [_ja(JOY_AXIS_RIGHT_X, 1.0)])
	_add("look_up", [_ja(JOY_AXIS_RIGHT_Y, -1.0)])
	_add("look_down", [_ja(JOY_AXIS_RIGHT_Y, 1.0)])
	_add("sprint", [_k(KEY_SHIFT), _ja(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_add("jump", [_k(KEY_SPACE), _jb(JOY_BUTTON_A)])
	_add("dash", [_k(KEY_Q), _jb(JOY_BUTTON_B)])
	# Combat
	_add("attack", [_mb(MOUSE_BUTTON_LEFT), _jb(JOY_BUTTON_X)])
	_add("special", [_mb(MOUSE_BUTTON_RIGHT), _jb(JOY_BUTTON_Y)])
	_add("grab", [_k(KEY_E), _jb(JOY_BUTTON_RIGHT_SHOULDER)])
	_add("consume", [_k(KEY_F), _jb(JOY_BUTTON_LEFT_SHOULDER)])
	# Gamepad: hold LB and press X / Y for the two devastators
	_add("devastator_mod", [_jb(JOY_BUTTON_LEFT_SHOULDER)])
	_add("tether", [_k(KEY_C), _mb(MOUSE_BUTTON_MIDDLE), _ja(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_add("focus", [_k(KEY_Z), _jb(JOY_BUTTON_LEFT_STICK)])
	_add("thermal", [_k(KEY_V), _jb(JOY_BUTTON_RIGHT_STICK)])
	_add("decoy", [_k(KEY_B), _jb(JOY_BUTTON_DPAD_DOWN)])
	_add("devastator_spikes", [_k(KEY_G)])
	_add("devastator_tendrils", [_k(KEY_T)])
	_add("artillery", [_k(KEY_R)])   # controller: hold LB + press RB
	_add("cycle_defense", [_k(KEY_X), _jb(JOY_BUTTON_DPAD_UP)])
	_add("form_next", [_mbw(MOUSE_BUTTON_WHEEL_DOWN), _jb(JOY_BUTTON_DPAD_RIGHT)])
	_add("form_prev", [_mbw(MOUSE_BUTTON_WHEEL_UP), _jb(JOY_BUTTON_DPAD_LEFT)])
	_add("form_1", [_k(KEY_1)])
	_add("form_2", [_k(KEY_2)])
	_add("form_3", [_k(KEY_3)])
	_add("form_4", [_k(KEY_4)])
	_add("form_5", [_k(KEY_5)])
	_add("form_6", [_k(KEY_6)])
	_add("form_7", [_k(KEY_7)])
	# Menus
	_add("evolve_menu", [_k(KEY_TAB), _k(KEY_U), _jb(JOY_BUTTON_BACK)])
	_add("map", [_k(KEY_M)])
	_add("pause", [_k(KEY_ESCAPE), _jb(JOY_BUTTON_START)])
	_add("toggle_help", [_k(KEY_F1), _k(KEY_H)])
	_add("respawn", [_k(KEY_F5)])
	_add("fullscreen", [_k(KEY_F11)])


func _add(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for e in events:
		InputMap.action_add_event(action, e)


func _k(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _jb(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _ja(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _mb(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _mbw(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.factor = 1.0
	return e
