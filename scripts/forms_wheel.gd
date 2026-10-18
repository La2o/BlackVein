extends Control
## The forms wheel: a radial menu with every body-part form, opened with Alt /
## hold X / hold D-pad Up. Time slows down while it's open. Point with the mouse or
## a stick, release (or click) to switch. Head on top, arms right, legs bottom, body left.

const PARTS := {
	"head": ["HEAD", Color(0.35, 0.72, 1.0)],
	"arms": ["ARMS", Color(1.0, 0.32, 0.26)],
	"legs": ["LEGS", Color(0.4, 0.95, 0.42)],
	"body": ["BODY", Color(0.78, 0.45, 1.0)],
}
const ICONS := {
	"head": ["eye", "thermal", "night", "predator"],
	"arms": ["fists", "claws", "hammer", "blade", "whip", "muscle", "spikes"],
	"legs": ["legs", "runner", "leaper", "crawler", "crusher"],
	"body": ["torso", "shield", "armor", "wings"],
}
const SHORT := {
	"head": ["Normal", "Thermal", "Night", "Predator"],
	"arms": ["Fists", "Claws", "Hammer", "Blade", "Whip", "Muscle", "Spikes"],
	"legs": ["Normal", "Runner", "Leaper", "Crawler", "Crusher"],
	"body": ["Normal", "Shield", "Armor", "Wings"],
}
const DESC := {
	"head": ["Regular eyesight.", "Warm bodies glow through smoke and darkness.",
		"Bright green sight for the darkest nights.", "Soldiers, infected and targets glow through walls."],
	"arms": ["Fast punches. Special: Uppercut.", "Lightning slashes. Special: Spike Line.",
		"Huge, slow hits that crush vehicles. Special: Ground Slam.", "Long reach, cuts tanks apart. Special: Whirlwind.",
		"Lash enemies from far away. Special: Whip Grab.", "Send people flying. Special: Thunderclap.",
		"Fire piercing bone spikes. Special: Spike Storm."],
	"legs": ["Regular legs.", "Much faster sprint and longer running jumps.", "Huge jumps; hard landings become stomps.",
		"Cling to walls and run along buildings forever.", "Plow through people and cars. Can't be knocked back."],
	"body": ["No body form.", "Blocks bullets and rockets from the front.", "Take far less damage and ram through anything.",
		"Flesh wings: glide fast and flap higher."],
}

var open := false
var hovered := -1
var entries: Array = []
var _cursor := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func _powers() -> PlayerPowers:
	return Game.player.powers if Game.player else null


func _build_entries() -> void:
	entries.clear()
	var pw := _powers()
	for part in ["head", "arms", "legs", "body"]:
		var n: int = ICONS[part].size()
		for i in n:
			var skill := ""
			var unlocked := true
			match part:
				"head":
					skill = pw.VISION_SKILLS[i]
					unlocked = pw.vision_unlocked(i)
				"arms":
					skill = pw.FORM_SKILLS[i]
					unlocked = pw.form_unlocked(i)
				"legs":
					skill = pw.LEG_SKILLS[i]
					unlocked = pw.legs_unlocked(i)
				"body":
					skill = pw.DEFENSE_SKILLS[i]
					unlocked = pw.defense_unlocked(i)
			entries.append({"part": part, "index": i, "skill": skill, "unlocked": unlocked})


func _equipped(e: Dictionary) -> bool:
	var pw := _powers()
	match e["part"]:
		"head": return pw.vision == e["index"]
		"arms": return pw.form == e["index"]
		"legs": return pw.legs == e["index"]
		"body": return pw.defense == e["index"]
	return false


func open_wheel() -> void:
	if open or Game.player == null or Game.player.is_dead():
		return
	_build_entries()
	position = Vector2.ZERO
	size = get_viewport_rect().size
	open = true
	visible = true
	_cursor = Vector2.ZERO
	hovered = -1
	_t = 0.0
	Game.wheel_slowmo = true
	Game._apply_time_scale()
	Game.fx.sound_ui("zap", -8.0)


func close_wheel(apply: bool) -> void:
	if not open:
		return
	open = false
	visible = false
	Game.wheel_slowmo = false
	Game._apply_time_scale()
	if apply and hovered >= 0:
		_apply(entries[hovered])


func _apply(e: Dictionary) -> void:
	var pw := _powers()
	if not e["unlocked"]:
		Game.locked_message(e["skill"])
		return
	if _equipped(e):
		return
	var i: int = e["index"]
	match e["part"]:
		"head": pw.set_vision(i)
		"arms": pw.set_form(i)
		"legs": pw.set_legs(i)
		"body": pw.set_defense(i)


func _step() -> float:
	return TAU / maxf(entries.size(), 1.0)


func _start_angle() -> float:
	# head entries centered on the top
	return -PI * 0.5 - ICONS["head"].size() * 0.5 * _step()


func _input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventMouseMotion:
		_cursor += (event as InputEventMouseMotion).relative
		if _cursor.length() > 170.0:
			_cursor = _cursor.normalized() * 170.0
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			close_wheel(true)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			close_wheel(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") or (event is InputEventJoypadButton and event.is_action_pressed("ui_cancel")):
		close_wheel(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.is_action_pressed("ui_accept"):
		close_wheel(true)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not open:
		return
	_t += delta / maxf(Engine.time_scale, 0.05)
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() < 0.4 and Game.hud and Game.hud.using_pad:
		stick = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if stick.length() > 0.45:
		_cursor = stick.normalized() * 150.0
	if _cursor.length() > 45.0:
		var a := fposmod(_cursor.angle() - _start_angle(), TAU)
		hovered = clampi(int(a / _step()), 0, entries.size() - 1)
	# releasing the button picks what you're pointing at
	if _t > 0.1 and not Input.is_action_pressed("cycle_defense") and not Input.is_action_pressed("forms_wheel"):
		close_wheel(true)
	queue_redraw()


func _draw() -> void:
	if not open:
		return
	var c := get_viewport_rect().size * 0.5
	var r_in := 105.0
	var r_out := 255.0
	var font := get_theme_default_font()
	draw_circle(c, r_out + 46.0, Color(0, 0, 0, 0.45))
	var step := _step()
	var start := _start_angle()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var col: Color = PARTS[e["part"]][1]
		var a0 := start + i * step + 0.012
		var a1 := start + (i + 1) * step - 0.012
		var pop := 14.0 if i == hovered else 0.0
		var fill := col.darkened(0.55)
		fill.a = 0.8
		if not e["unlocked"]:
			fill = Color(0.12, 0.12, 0.13, 0.8)
		if i == hovered:
			fill = col.darkened(0.15) if e["unlocked"] else Color(0.3, 0.3, 0.32, 0.9)
		var pts := PackedVector2Array()
		for k in 9:
			var a := lerpf(a0, a1, k / 8.0)
			pts.append(c + Vector2(cos(a), sin(a)) * (r_out + pop))
		for k in 9:
			var a := lerpf(a1, a0, k / 8.0)
			pts.append(c + Vector2(cos(a), sin(a)) * (r_in + pop * 0.5))
		draw_colored_polygon(pts, fill)
		if _equipped(e):
			draw_arc(c, r_out + pop + 5.0, a0, a1, 10, Color(1, 0.85, 0.3), 5.0, true)
		var mid := (a0 + a1) * 0.5
		var ip := c + Vector2(cos(mid), sin(mid)) * (r_in + (r_out - r_in) * 0.58 + pop * 0.7)
		var icol := Color(1, 1, 1, 0.95) if e["unlocked"] else Color(0.55, 0.55, 0.58, 0.8)
		_icon(ICONS[e["part"]][e["index"]], ip + Vector2(0, -8), icol)
		var label: String = SHORT[e["part"]][e["index"]]
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, ip + Vector2(-lw * 0.5, 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, icol)
		if not e["unlocked"]:
			_icon("lock", ip + Vector2(14, -22), Color(1, 0.8, 0.4, 0.9))
	# part names around the rim
	var idx := 0
	for part in ["head", "arms", "legs", "body"]:
		var n: int = ICONS[part].size()
		var mid := start + (idx + n * 0.5) * step
		var name_s: String = PARTS[part][0]
		var p := c + Vector2(cos(mid), sin(mid)) * (r_out + 32.0)
		var w := font.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string_outline(font, p + Vector2(-w * 0.5, 6), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0, 0, 0, 0.8))
		draw_string(font, p + Vector2(-w * 0.5, 6), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PARTS[part][1])
		idx += n
	# center: what you're pointing at
	draw_circle(c, r_in - 6.0, Color(0.03, 0.03, 0.04, 0.92))
	if _cursor.length() > 10.0:
		draw_line(c, c + _cursor.limit_length(r_in - 14.0), Color(1, 1, 1, 0.35), 2.0, true)
	if hovered >= 0:
		var e: Dictionary = entries[hovered]
		var pw := _powers()
		var title := ""
		match e["part"]:
			"head": title = pw.VISION_NAMES[e["index"]]
			"arms": title = pw.FORM_NAMES[e["index"]]
			"legs": title = pw.LEG_NAMES[e["index"]]
			"body": title = pw.DEFENSE_NAMES[e["index"]]
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		draw_string(font, c + Vector2(-tw * 0.5, -38), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, PARTS[e["part"]][1])
		var desc: String = DESC[e["part"]][e["index"]]
		if not e["unlocked"]:
			var sk: Array = Game.SKILLS.get(e["skill"], ["", "", "", 0, 0])
			desc = "LOCKED. Unlock %s in Skills (level %d)." % [sk[0], sk[4]]
		draw_multiline_string(font, c + Vector2(-82, -14), desc, HORIZONTAL_ALIGNMENT_CENTER, 164, 13, 5, Color(0.9, 0.9, 0.9))
	else:
		var hint := "Point to choose"
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, c + Vector2(-hw * 0.5, 5), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.8, 0.8))


## little line drawings for each form
func _icon(kind: String, p: Vector2, col: Color) -> void:
	var w := 2.5
	match kind:
		"eye", "thermal", "night", "predator":
			var pts := PackedVector2Array()
			for k in 13:
				var a := PI * k / 12.0
				pts.append(p + Vector2(-cos(a) * 14, -sin(a) * 7))
			for k in 13:
				var a := PI * k / 12.0
				pts.append(p + Vector2(cos(a) * 14, sin(a) * 7))
			draw_polyline(pts, col, w, true)
			var iris := col
			match kind:
				"thermal": iris = Color(1, 0.45, 0.1)
				"night": iris = Color(0.4, 1, 0.4)
				"predator": iris = Color(1, 0.2, 0.15)
			draw_circle(p, 4.5, iris)
			if kind == "predator":
				draw_arc(p, 11, 0, TAU, 16, iris, 1.5, true)
		"fists":
			draw_rect(Rect2(p - Vector2(9, 7), Vector2(18, 14)), col, false, w)
			for k in 3:
				draw_line(p + Vector2(-9 + 6 * (k + 1), -7), p + Vector2(-9 + 6 * (k + 1), -1), col, 1.5)
		"claws":
			for k in 3:
				draw_line(p + Vector2(-9 + k * 7, 10), p + Vector2(-3 + k * 7, -12), col, w, true)
		"hammer":
			draw_rect(Rect2(p - Vector2(12, 10), Vector2(24, 12)), col)
			draw_line(p + Vector2(0, 2), p + Vector2(0, 13), col, 4.0)
		"blade":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 12), p + Vector2(3, 12), p + Vector2(1, -14)]), col)
		"whip":
			var pts2 := PackedVector2Array()
			for k in 12:
				pts2.append(p + Vector2(-13 + k * 2.4, sin(k * 1.1) * 6))
			draw_polyline(pts2, col, w, true)
		"muscle":
			draw_circle(p + Vector2(-4, 0), 8, col)
			draw_circle(p + Vector2(6, 3), 6, col)
		"spikes":
			for k in 3:
				var b := p + Vector2(-10 + k * 9, 8)
				draw_colored_polygon(PackedVector2Array([b + Vector2(-4, 0), b + Vector2(4, 0), b + Vector2(0, -18)]), col)
		"legs":
			draw_line(p + Vector2(-5, -12), p + Vector2(-6, 12), col, w)
			draw_line(p + Vector2(5, -12), p + Vector2(6, 12), col, w)
		"runner":
			for k in 2:
				var o := Vector2(-6 + k * 9, 0)
				draw_polyline(PackedVector2Array([p + o + Vector2(-5, -9), p + o + Vector2(3, 0), p + o + Vector2(-5, 9)]), col, w, true)
		"leaper":
			var pts3 := PackedVector2Array()
			for k in 9:
				pts3.append(p + Vector2(-7 if k % 2 == 0 else 7, -12 + k * 3))
			draw_polyline(pts3, col, w, true)
		"crawler":
			draw_circle(p, 5, col)
			for k in 3:
				var y := -5 + k * 5
				draw_polyline(PackedVector2Array([p + Vector2(-4, y), p + Vector2(-11, y - 5), p + Vector2(-14, y + 3)]), col, 1.8, true)
				draw_polyline(PackedVector2Array([p + Vector2(4, y), p + Vector2(11, y - 5), p + Vector2(14, y + 3)]), col, 1.8, true)
		"crusher":
			draw_rect(Rect2(p - Vector2(10, 4), Vector2(20, 12)), col)
			draw_line(p + Vector2(0, -14), p + Vector2(0, -4), col, 4.0)
		"torso":
			draw_circle(p + Vector2(0, -9), 4, col)
			draw_rect(Rect2(p - Vector2(7, 4), Vector2(14, 16)), col, false, w)
		"shield":
			var hexa := PackedVector2Array()
			for k in 7:
				var a := TAU * k / 6.0
				hexa.append(p + Vector2(cos(a), sin(a)) * 12)
			draw_polyline(hexa, col, w, true)
			draw_circle(p, 3.5, col)
		"armor":
			for k in 3:
				draw_rect(Rect2(p + Vector2(-10, -11 + k * 8), Vector2(20, 6)), col)
		"wings":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-2, 0), p + Vector2(-15, -11), p + Vector2(-12, 3), p + Vector2(-16, 9)]), col)
			draw_colored_polygon(PackedVector2Array([p + Vector2(2, 0), p + Vector2(15, -11), p + Vector2(12, 3), p + Vector2(16, 9)]), col)
		"lock":
			draw_rect(Rect2(p - Vector2(5, 0), Vector2(10, 8)), col)
			draw_arc(p, 4, PI, TAU, 8, col, 2.0)
