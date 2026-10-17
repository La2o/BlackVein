extends CanvasLayer
## Everything on screen: health and biomass, powers, alert level, compass,
## minimap, event list and feed, button prompts (keyboard or controller),
## screen effects, and the pause, evolve, controls and map menus.

const SCREEN_FX := preload("res://shaders/screen_fx.gdshader")
const SPEED_LINES := preload("res://shaders/speed_lines.gdshader")

const KEYS := {
	"attack": ["LMB", "X"], "special": ["RMB", "Y"], "grab": ["E", "RB"], "consume": ["F", "LB"],
	"jump": ["Space", "A"], "dash": ["Q", "B"], "tether": ["C", "LT"], "focus": ["Z", "L3"],
	"thermal": ["V", "R3"], "decoy": ["B", "D-pad Down"], "defense": ["X", "D-pad Up"],
	"spikes": ["G", "LB+X"], "tendrils": ["T", "LB+Y"], "forms": ["1-6 / Wheel", "D-pad L/R"],
	"evolve": ["Tab", "Back"], "pause": ["Esc", "Start"], "sprint": ["Shift", "RT"],
}

var player: Node
var using_pad := false

var root: Control
var screen_fx: ColorRect
var speed_lines: ColorRect
var health_bar: ProgressBar
var health_back: ProgressBar
var biomass_bar: ProgressBar
var xp_bar: ProgressBar
var ep_label: Label
var status_label: Label
var form_label: Label
var ability_label: Label
var prompt_label: Label
var notify_label: Label
var feed_box: VBoxContainer
var events_label: RichTextLabel
var alert_label: Label
var suspicion_bar: ProgressBar
var compass: Control
var minimap: Control
var crosshair: Control
var charge_bar: ProgressBar
var help_panel: PanelContainer
var pause_menu: PanelContainer
var evolve_menu: PanelContainer
var big_map: Control
var death_panel: Control
var title_card: Control
var _notify_timer := 0.0
var _damage := 0.0
var _thermal := 0.0
var _thermal_target := 0.0
var _focus := 0.0
var _focus_target := 0.0
var _evolve_rows := {}
var _evolve_ep_label: Label
var _feed_items: Array = []
var _title_timer := 4.5
var _health_shown := 1.0


func _ready() -> void:
	Game.hud = self
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_screen_fx()
	_build_status()
	_build_center()
	_build_right()
	_build_bottom()
	_build_help()
	_build_pause()
	_build_evolve()
	_build_big_map()
	_build_death()
	_build_title()
	Game.notify.connect(_on_notify)
	Game.event_feed.connect(_on_feed)
	Game.alert_changed.connect(_on_alert_changed)
	Game.player_died.connect(func(): death_panel.visible = true)
	Game.player_respawned.connect(func(): death_panel.visible = false)


# ------------------------------------------------------------------ builders

func _label(text: String, size := 18, color := Color.WHITE, outline := 5) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(color: Color, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 100.0
	b.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(3)
	bg.border_color = Color(1, 1, 1, 0.15)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _panel_style(alpha := 0.82) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.03, 0.035, alpha)
	s.border_color = Color(0.7, 0.08, 0.06, 0.8)
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(18)
	return s


func _build_screen_fx() -> void:
	speed_lines = ColorRect.new()
	speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = SPEED_LINES
	speed_lines.material = m
	root.add_child(speed_lines)
	screen_fx = ColorRect.new()
	screen_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m2 := ShaderMaterial.new()
	m2.shader = SCREEN_FX
	screen_fx.material = m2
	screen_fx.visible = false
	root.add_child(screen_fx)


func _build_status() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	var title := _label("BLACKVEIN", 15, Color(1, 0.25, 0.2), 4)
	box.add_child(title)
	var hstack := Control.new()
	hstack.custom_minimum_size = Vector2(320, 18)
	hstack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hstack)
	health_back = _bar(Color(1, 1, 1, 0.5), 320, 18)
	hstack.add_child(health_back)
	health_bar = _bar(Color(0.85, 0.1, 0.08), 320, 18)
	var transparent_bg := StyleBoxEmpty.new()
	health_bar.add_theme_stylebox_override("background", transparent_bg)
	hstack.add_child(health_bar)
	biomass_bar = _bar(Color(1.0, 0.45, 0.1), 260, 10)
	box.add_child(biomass_bar)
	ep_label = _label("LEVEL 1", 16, Color(1, 0.85, 0.45))
	box.add_child(ep_label)
	xp_bar = _bar(Color(1, 0.8, 0.3), 260, 5)
	box.add_child(xp_bar)
	status_label = _label("", 14, Color(0.85, 0.85, 0.85))
	box.add_child(status_label)


func _build_center() -> void:
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(func():
		crosshair.draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1, 0.8))
		crosshair.draw_arc(Vector2.ZERO, 9.0, 0, TAU, 24, Color(1, 1, 1, 0.25), 1.5))
	root.add_child(crosshair)
	charge_bar = _bar(Color(1, 0.85, 0.4), 220, 8)
	charge_bar.set_anchors_preset(Control.PRESET_CENTER)
	charge_bar.position = Vector2(-110, 40)
	charge_bar.visible = false
	root.add_child(charge_bar)
	notify_label = _label("", 34, Color.WHITE, 8)
	notify_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notify_label.position = Vector2(-500, 110)
	notify_label.size = Vector2(1000, 50)
	root.add_child(notify_label)
	compass = Control.new()
	compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass.position = Vector2(-300, 18)
	compass.size = Vector2(600, 46)
	compass.custom_minimum_size = Vector2(600, 46)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	root.add_child(compass)
	prompt_label = _label("", 20, Color(1, 0.92, 0.8), 6)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.position = Vector2(-400, -150)
	prompt_label.size = Vector2(800, 30)
	root.add_child(prompt_label)


func _build_right() -> void:
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	frame.position = Vector2(-232, 20)
	frame.size = Vector2(210, 210)
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.08, 0.09, 0.75)
	st.border_color = Color(0.7, 0.08, 0.06, 0.7)
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", st)
	root.add_child(frame)
	minimap = Control.new()
	minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	frame.add_child(minimap)
	alert_label = _label("HIDDEN", 18, Color(0.6, 0.9, 1.0))
	alert_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	alert_label.position = Vector2(-232, 236)
	alert_label.size = Vector2(210, 24)
	alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(alert_label)
	suspicion_bar = _bar(Color(1, 0.8, 0.3), 160, 6)
	suspicion_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	suspicion_bar.position = Vector2(-207, 264)
	suspicion_bar.visible = false
	root.add_child(suspicion_bar)
	events_label = RichTextLabel.new()
	events_label.bbcode_enabled = true
	events_label.fit_content = true
	events_label.scroll_active = false
	events_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	events_label.position = Vector2(-380, 280)
	events_label.size = Vector2(358, 240)
	events_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	events_label.add_theme_font_size_override("normal_font_size", 15)
	events_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	events_label.add_theme_constant_override("outline_size", 5)
	root.add_child(events_label)


func _build_bottom() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(24, -120)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	form_label = _label("", 24, Color(1, 0.4, 0.3), 6)
	box.add_child(form_label)
	ability_label = _label("", 14, Color(0.9, 0.85, 0.8))
	box.add_child(ability_label)
	feed_box = VBoxContainer.new()
	feed_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	feed_box.position = Vector2(24, -330)
	feed_box.size = Vector2(600, 200)
	feed_box.alignment = BoxContainer.ALIGNMENT_END
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed_box)


func _build_help() -> void:
	help_panel = PanelContainer.new()
	help_panel.add_theme_stylebox_override("panel", _panel_style(0.88))
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.position = Vector2(-470, -330)
	help_panel.custom_minimum_size = Vector2(940, 0)
	help_panel.visible = false
	root.add_child(help_panel)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(900, 0)
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.add_theme_font_size_override("bold_font_size", 17)
	rt.text = _controls_text()
	help_panel.add_child(rt)


func _controls_text() -> String:
	return """[b][color=#ff4433]BLACKVEIN — CONTROLS[/color][/b]   (keyboard & mouse  |  [color=#9fd0ff]controller[/color])

[b]MOVE[/b]
WASD move · Mouse look   |   [color=#9fd0ff]Left stick · Right stick[/color]
Shift sprint — run into a wall to run up it   |   [color=#9fd0ff]RT[/color]
Space tap jump, hold to charge a super jump   |   [color=#9fd0ff]A[/color]
Space in the air: double jump, hold to glide   |   [color=#9fd0ff]A[/color]
Q dash (works in the air)   |   [color=#9fd0ff]B[/color]
On a wall: W climbs, A/D runs sideways, Space wall jumps, let go of Shift to drop

[b]FIGHT[/b]
Left click attack (in the air: dive bomb)   |   [color=#9fd0ff]X[/color]
Right click special move for your current form   |   [color=#9fd0ff]Y[/color]
1–6 or mouse wheel: Fists, Claws, Hammerfist, Blade, Whipfist, Musclemass   |   [color=#9fd0ff]D-pad left/right[/color]
X cycle defense: Shield / Armor / none   |   [color=#9fd0ff]D-pad up[/color]
E grab a person or car, press again to throw · hijack tanks and gunships · pick up guns   |   [color=#9fd0ff]RB[/color]
F consume someone: heal, gain biomass and steal their disguise   |   [color=#9fd0ff]LB[/color]
G Groundspike devastator (50 biomass)   |   [color=#9fd0ff]hold LB + X[/color]
T Tendril Barrage devastator (80 biomass)   |   [color=#9fd0ff]hold LB + Y[/color]

[b]NEW POWERS[/b]
C Tether: zip to any surface, yank enemies, latch onto helicopters   |   [color=#9fd0ff]LT[/color]
Z Focus: slow motion (drains biomass)   |   [color=#9fd0ff]L3[/color]
B Biomass Decoy: a clone that draws fire, then explodes   |   [color=#9fd0ff]D-pad down[/color]
V Thermal vision   |   [color=#9fd0ff]R3[/color]

[b]GETTING STRONGER[/b]
Kills, consumes and world events give XP. Every level gives skill points. Open Skills to unlock forms, powers and upgrades. The game saves automatically.

[b]STAYING HIDDEN[/b]
Walking calmly blends in. Super speed, wall running, powers and violence get noticed.
When they're searching, break line of sight. Consuming someone unseen changes your disguise instantly.

Tab skills (spend skill points)  |  [color=#9fd0ff]Back[/color]     Esc menu  |  [color=#9fd0ff]Start[/color]     M map     F1 this help     F11 fullscreen     F5 unstick"""


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 46)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _build_pause() -> void:
	pause_menu = PanelContainer.new()
	pause_menu.add_theme_stylebox_override("panel", _panel_style())
	pause_menu.set_anchors_preset(Control.PRESET_CENTER)
	pause_menu.position = Vector2(-170, -200)
	pause_menu.visible = false
	root.add_child(pause_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pause_menu.add_child(v)
	var t := _label("BLACKVEIN", 40, Color(1, 0.25, 0.2), 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(_menu_button("Resume", func(): toggle_pause(false)))
	v.add_child(_menu_button("Skills", func():
		pause_menu.visible = false
		open_evolve()))
	v.add_child(_menu_button("Save game", func(): Game.save_game(true)))
	v.add_child(_menu_button("Controls", func():
		help_panel.visible = not help_panel.visible))
	v.add_child(_menu_button("Map", func():
		big_map.visible = not big_map.visible))
	var new_btn := _menu_button("New game (erase save)", func(): pass)
	new_btn.pressed.connect(func():
		if new_btn.text.begins_with("Sure"):
			Game.new_game()
		else:
			new_btn.text = "Sure? Press again to erase")
	v.add_child(new_btn)
	v.add_child(_menu_button("Save and quit", func():
		Game.save_game()
		get_tree().quit()))


func _build_evolve() -> void:
	evolve_menu = PanelContainer.new()
	evolve_menu.add_theme_stylebox_override("panel", _panel_style(0.94))
	evolve_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	evolve_menu.offset_left = 60
	evolve_menu.offset_right = -60
	evolve_menu.offset_top = 40
	evolve_menu.offset_bottom = -40
	evolve_menu.visible = false
	root.add_child(evolve_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	evolve_menu.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(_label("SKILLS", 36, Color(1, 0.3, 0.25), 6))
	_evolve_ep_label = _label("", 20, Color(1, 0.85, 0.45))
	_evolve_ep_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_evolve_ep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_evolve_ep_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)
	var col_a := VBoxContainer.new()
	var col_b := VBoxContainer.new()
	for c in [col_a, col_b]:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_theme_constant_override("separation", 6)
		cols.add_child(c)
	var i := 0
	for cat in Game.CATEGORIES:
		var col: VBoxContainer = col_a if i % 2 == 0 else col_b
		i += 1
		col.add_child(_label(cat.to_upper(), 20, Color(1, 0.5, 0.4), 5))
		for id in Game.SKILLS:
			var sk: Array = Game.SKILLS[id]
			if sk[2] != cat:
				continue
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 52)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_font_size_override("font_size", 15)
			btn.clip_text = true
			btn.pressed.connect(func():
				if Game.unlock_skill(id):
					Game.fx.sound_ui("evolve", 0.0)
				else:
					Game.fx.sound_ui("ui", -6.0)
				_refresh_evolve())
			col.add_child(btn)
			_evolve_rows[id] = {"button": btn}
	v.add_child(_menu_button("Back to the city", func(): close_evolve()))


func _refresh_evolve() -> void:
	_evolve_ep_label.text = "Level %d   ·   %d / %d XP   ·   %d skill point%s" % [Game.level, Game.xp, Game.xp_to_next(Game.level),
		Game.skill_points, "" if Game.skill_points == 1 else "s"]
	for id in _evolve_rows:
		var sk: Array = Game.SKILLS[id]
		var b: Button = _evolve_rows[id]["button"]
		var rank := Game.skill_rank(id)
		var max_rank: int = sk[5]
		var reason := Game.skill_block_reason(id)
		var head: String = sk[0]
		if max_rank > 1:
			head += "  " + "●".repeat(rank) + "○".repeat(max_rank - rank)
		elif rank > 0:
			head += "  ✓"
		var cost := "%d pt" % int(sk[3])
		var tail := ("[%s]" % reason) if reason != "" else ("Unlock — " + cost)
		if reason == "Maxed":
			tail = "Owned" if max_rank == 1 else "Maxed"
		b.text = "%s     %s\n%s" % [head, tail, sk[1]]
		b.disabled = reason != ""
		b.modulate = Color(1, 1, 1) if rank > 0 or reason == "" else Color(0.7, 0.7, 0.7)


func _build_big_map() -> void:
	big_map = Control.new()
	big_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	big_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_map.visible = false
	big_map.draw.connect(_draw_big_map)
	root.add_child(big_map)


func _build_death() -> void:
	death_panel = ColorRect.new()
	(death_panel as ColorRect).color = Color(0.25, 0, 0, 0.45)
	death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_panel.visible = false
	root.add_child(death_panel)
	var l := _label("YOU WERE TORN APART", 48, Color(1, 0.3, 0.25), 8)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-400, -60)
	l.size = Vector2(800, 60)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_panel.add_child(l)
	var l2 := _label("Your biomass is regrowing on a rooftop far away...", 20, Color(1, 0.85, 0.8))
	l2.set_anchors_preset(Control.PRESET_CENTER)
	l2.position = Vector2(-400, 10)
	l2.size = Vector2(800, 30)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_panel.add_child(l2)


func _build_title() -> void:
	title_card = Control.new()
	title_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_card)
	var t := _label("BLACKVEIN", 96, Color(1, 0.18, 0.12), 12)
	t.set_anchors_preset(Control.PRESET_CENTER)
	t.position = Vector2(-500, -150)
	t.size = Vector2(1000, 110)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_card.add_child(t)
	var s := _label("The city is infected. So are you.", 24, Color(1, 0.9, 0.85), 6)
	s.set_anchors_preset(Control.PRESET_CENTER)
	s.position = Vector2(-500, -40)
	s.size = Vector2(1000, 30)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_card.add_child(s)
	var h := _label("F1 / Back for controls   ·   Esc / Start for menu", 18, Color(0.9, 0.9, 0.9), 5)
	h.set_anchors_preset(Control.PRESET_CENTER)
	h.position = Vector2(-500, 0)
	h.size = Vector2(1000, 30)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_card.add_child(h)


# ------------------------------------------------------------------ menus

func toggle_pause(on: bool) -> void:
	pause_menu.visible = on
	if not on:
		help_panel.visible = false
		big_map.visible = false
	get_tree().paused = on or evolve_menu.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
	if on:
		(pause_menu.get_child(0).get_child(1) as Button).grab_focus()


func open_evolve() -> void:
	evolve_menu.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_evolve()
	for key in _evolve_rows:
		var b: Button = _evolve_rows[key]["button"]
		if not b.disabled:
			b.grab_focus()
			return
	var vb := evolve_menu.get_child(0)
	(vb.get_child(vb.get_child_count() - 1) as Button).grab_focus()


func close_evolve() -> void:
	evolve_menu.visible = false
	get_tree().paused = pause_menu.visible
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_pad = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if evolve_menu.visible:
			close_evolve()
		elif help_panel.visible and not pause_menu.visible:
			help_panel.visible = false
		else:
			toggle_pause(not pause_menu.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("evolve_menu"):
		if evolve_menu.visible:
			close_evolve()
		elif not pause_menu.visible:
			open_evolve()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_help"):
		help_panel.visible = not help_panel.visible
		_title_timer = minf(_title_timer, 0.5)
	elif event.is_action_pressed("map"):
		big_map.visible = not big_map.visible
	elif event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ effects API

func flash_damage(amount: float) -> void:
	_damage = minf(1.0, _damage + amount)


func set_thermal(on: bool) -> void:
	_thermal_target = 1.0 if on else 0.0


func set_focus(on: bool) -> void:
	_focus_target = 1.0 if on else 0.0


func _on_notify(text: String, color: Color) -> void:
	notify_label.text = text
	notify_label.add_theme_color_override("font_color", color)
	_notify_timer = 2.5


func _on_feed(text: String, color: Color) -> void:
	var l := _label(text, 16, color)
	feed_box.add_child(l)
	_feed_items.append({"label": l, "t": 9.0})
	while _feed_items.size() > 7:
		var old: Dictionary = _feed_items.pop_front()
		(old["label"] as Label).queue_free()


func _on_alert_changed(level: int) -> void:
	if level == Game.Alert.ALERT:
		Game.fx.sound_ui("alert", -4.0)


# ------------------------------------------------------------------ per-frame

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	if player == null:
		player = Game.player
		if player == null:
			return
	_title_timer -= real
	title_card.modulate.a = clampf(_title_timer, 0.0, 1.0)
	title_card.visible = _title_timer > 0.0
	_notify_timer -= real
	notify_label.modulate.a = clampf(_notify_timer * 2.0, 0.0, 1.0)
	for item in _feed_items.duplicate():
		item["t"] -= real
		(item["label"] as Label).modulate.a = clampf(item["t"], 0.0, 1.0)
		if item["t"] <= 0.0:
			(item["label"] as Label).queue_free()
			_feed_items.erase(item)
	_update_bars(real)
	_update_alert()
	_update_powers_text()
	_update_prompt()
	_update_events()
	_update_screen_fx(real)
	charge_bar.visible = player.charging
	charge_bar.value = player.charge * 100.0
	compass.queue_redraw()
	minimap.queue_redraw()
	if big_map.visible:
		big_map.queue_redraw()


func _update_bars(delta: float) -> void:
	var hp_ratio: float = player.health / maxf(player.max_health, 1.0)
	health_bar.value = hp_ratio * 100.0
	_health_shown = move_toward(_health_shown, hp_ratio, delta * 0.35) if _health_shown > hp_ratio else hp_ratio
	health_back.value = _health_shown * 100.0
	biomass_bar.value = player.biomass / maxf(player.max_biomass, 1.0) * 100.0
	var pts := ""
	if Game.skill_points > 0:
		pts = "   ·   %d skill point%s  (%s)" % [Game.skill_points, "s" if Game.skill_points > 1 else "", _k("evolve")]
	ep_label.text = "LEVEL %d%s" % [Game.level, pts]
	xp_bar.value = float(Game.xp) / float(Game.xp_to_next(Game.level)) * 100.0 if Game.level < Game.MAX_LEVEL else 100.0
	var disguise_text: String = "Disguise: " + str(player.disguise).replace("_", " ").capitalize()
	var time_text: String = Game.daynight.time_text() if Game.daynight else ""
	var loc: String = Game.city.street_name_at(player.global_position) if Game.city else ""
	status_label.text = "%s   ·   %s   ·   %s" % [disguise_text, loc, time_text]


func _update_alert() -> void:
	match Game.alert_level:
		Game.Alert.HIDDEN:
			alert_label.text = "HIDDEN"
			alert_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		Game.Alert.SEARCHING:
			alert_label.text = "SEARCHING  %d" % int(Game.search_timer)
			alert_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		Game.Alert.ALERT:
			alert_label.text = "ALERT  " + "◆".repeat(int(ceil(Game.heat))) + "◇".repeat(5 - int(ceil(Game.heat)))
			alert_label.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	suspicion_bar.visible = Game.alert_level == Game.Alert.HIDDEN and Game.suspicion > 0.02
	suspicion_bar.value = Game.suspicion * 100.0


func _k(action: String) -> String:
	return KEYS[action][1 if using_pad else 0]


func _update_powers_text() -> void:
	var pw: Node = player.powers
	var f: int = pw.form
	form_label.text = "%s" % pw.FORM_NAMES[f].to_upper()
	if pw.weapon != "":
		form_label.text = "%s  (%d)" % ["ASSAULT RIFLE" if pw.weapon == "rifle" else "ROCKET LAUNCHER", pw.ammo]
	var parts: Array[String] = []
	parts.append("%s %s" % [_k("special"), pw.SPECIAL_NAMES[f]])
	var forms_owned := 0
	for i in 6:
		if pw.form_unlocked(i):
			forms_owned += 1
	if forms_owned > 1:
		parts.append("%s forms" % _k("forms"))
	if pw.defense_unlocked(1) or pw.defense_unlocked(2):
		parts.append("%s defense: %s" % [_k("defense"), pw.DEFENSE_NAMES[pw.defense]])
	parts.append("%s grab   %s consume" % [_k("grab"), _k("consume")])
	var line2: Array[String] = []
	if Game.has_skill("tether"):
		line2.append("%s tether" % _k("tether"))
	if Game.has_skill("focus"):
		line2.append("%s focus%s" % [_k("focus"), " ON" if pw.focus_on else ""])
	if Game.has_skill("decoy"):
		line2.append("%s decoy%s" % [_k("decoy"), "" if pw.decoy_cooldown <= 0.0 else " %ds" % int(ceil(pw.decoy_cooldown))])
	if Game.has_skill("thermal"):
		line2.append("%s thermal%s" % [_k("thermal"), " ON" if pw.thermal_on else ""])
	if Game.has_skill("groundspike"):
		line2.append("%s spikes" % _k("spikes"))
	if Game.has_skill("tendrils"):
		line2.append("%s tendrils" % _k("tendrils"))
	if line2.is_empty():
		line2.append("Earn XP to unlock more powers  (%s skills)" % _k("evolve"))
	ability_label.text = "   ".join(parts) + "\n" + "   ".join(line2)


func _update_prompt() -> void:
	var pw: Node = player.powers
	var text := ""
	if player.is_dead():
		text = ""
	elif player.vehicle:
		var heli: bool = player.vehicle.is_in_group("helicopters")
		if heli:
			text = "%s missiles   %s minigun   %s up   %s down   %s jump out" % [_k("attack"), _k("special"), _k("jump"), _k("sprint"), _k("grab")]
		else:
			text = "%s fire   %s boost   %s jump out" % [_k("attack"), _k("sprint"), _k("grab")]
	elif pw.held:
		text = "%s throw   %s drop" % [_k("attack"), _k("special")]
		if pw.held_kind == "npc":
			text += "   %s consume" % _k("consume")
	else:
		var pos: Vector3 = player.global_position
		var v := Game.nearest_in_group("hijackable", pos, 9.0, func(n): return n.has_method("can_hijack") and n.can_hijack(player))
		var pick := Game.nearest_in_group("pickups", pos, 2.8)
		var food := Game.nearest_in_group("npcs", pos, 3.4, func(n): return n.can_be_consumed())
		if v:
			text = "%s hijack %s" % [_k("grab"), "gunship" if v.is_in_group("helicopters") else "tank"]
		elif pick and pick.get("kind") != "supply":
			text = "%s pick up %s" % [_k("grab"), "rifle" if pick.get("kind") == "rifle" else "rocket launcher"]
		elif food:
			text = "%s consume %s   %s grab" % [_k("consume"), str(food.get("label")), _k("grab")]
		elif player.state == player.State.WALL:
			text = "%s wall jump" % _k("jump")
	prompt_label.text = text


func _update_events() -> void:
	if Game.director == null:
		return
	var lines: Array[String] = []
	for e in Game.director.active_events:
		var d := int(player.global_position.distance_to(e["pos"]))
		var col: Color = e["color"]
		var timer := ""
		if e["timer"] < 900.0 and e["type"] in ["supply", "target", "outbreak", "gunship", "convoy"]:
			timer = "  %d:%02d" % [int(e["timer"]) / 60, int(e["timer"]) % 60]
		lines.append("[right][color=#%s][b]%s[/b]  %dm%s[/color]\n[color=#cccccc]%s[/color][/right]" % [col.to_html(false), e["name"], d, timer, e["desc"]])
	events_label.text = "\n".join(lines)


func _update_screen_fx(delta: float) -> void:
	_damage = maxf(0.0, _damage - delta * 1.5)
	_thermal = move_toward(_thermal, _thermal_target, delta * 4.0)
	_focus = move_toward(_focus, _focus_target, delta * 4.0)
	var low := clampf(1.0 - player.health / maxf(player.max_health, 1.0) / 0.3, 0.0, 1.0)
	var m := screen_fx.material as ShaderMaterial
	m.set_shader_parameter("thermal", _thermal)
	m.set_shader_parameter("damage", _damage)
	m.set_shader_parameter("low_health", low if not player.is_dead() else 0.0)
	m.set_shader_parameter("focus", _focus)
	screen_fx.visible = _thermal > 0.0 or _damage > 0.0 or low > 0.0 or _focus > 0.0
	var spd: float = player.velocity.length()
	var sm := speed_lines.material as ShaderMaterial
	sm.set_shader_parameter("intensity", clampf((spd - 22.0) / 25.0, 0.0, 1.0))


# ------------------------------------------------------------------ compass and maps

func _bearing(v: Vector3) -> float:
	return atan2(-v.x, -v.z)


func _draw_compass() -> void:
	var w := compass.size.x
	var cx := w * 0.5
	var px_per_rad := w / deg_to_rad(150.0)
	var yaw: float = player.yaw if player else 0.0
	compass.draw_rect(Rect2(0, 8, w, 22), Color(0, 0, 0, 0.35))
	var font := ThemeDB.fallback_font
	var dirs := {"N": 0.0, "W": PI * 0.5, "S": PI, "E": -PI * 0.5}
	for k in 24:
		var a := k * TAU / 24.0
		var rel := wrapf(a - yaw, -PI, PI)
		var x := cx - rel * px_per_rad
		if x < 0 or x > w:
			continue
		compass.draw_line(Vector2(x, 24), Vector2(x, 30), Color(1, 1, 1, 0.4), 1.0)
	for name in dirs:
		var rel: float = wrapf(dirs[name] - yaw, -PI, PI)
		var x := cx - rel * px_per_rad
		if x < 0 or x > w:
			continue
		compass.draw_string(font, Vector2(x - 6, 25), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))
	compass.draw_line(Vector2(cx, 4), Vector2(cx, 32), Color(1, 0.3, 0.2, 0.9), 2.0)
	if Game.director and player:
		for e in Game.director.active_events:
			var v: Vector3 = e["pos"] - player.global_position
			var rel := wrapf(_bearing(v) - yaw, -PI, PI)
			var x := clampf(cx - rel * px_per_rad, 6, w - 6)
			var col: Color = e["color"]
			compass.draw_colored_polygon(PackedVector2Array([Vector2(x, 6), Vector2(x + 7, 16), Vector2(x, 26), Vector2(x - 7, 16)]), col)
			compass.draw_string(font, Vector2(x - 20, 44), "%dm" % int(v.length()), HORIZONTAL_ALIGNMENT_CENTER, 40, 12, col)
	if Game.alert_level != Game.Alert.HIDDEN and player:
		var v2: Vector3 = Game.last_known_pos - player.global_position
		if v2.length() > 8.0:
			var rel2 := wrapf(_bearing(v2) - yaw, -PI, PI)
			var x2 := clampf(cx - rel2 * px_per_rad, 6, w - 6)
			compass.draw_circle(Vector2(x2, 16), 4.0, Color(1, 0.85, 0.3))


func _to_map(p: Vector3, center: Vector3, yaw: float, scale: float, origin: Vector2) -> Vector2:
	var d := Vector2(p.x - center.x, p.z - center.z)
	var f := Vector2(-sin(yaw), -cos(yaw))
	var r := Vector2(cos(yaw), -sin(yaw))
	return origin + Vector2(d.dot(r), -d.dot(f)) * scale


func _draw_minimap() -> void:
	if player == null or Game.city == null:
		return
	var size := minimap.size
	var origin := size * 0.5
	var radius_m := 120.0
	var scale := size.x * 0.5 / radius_m
	var c: Vector3 = player.global_position
	var yaw: float = player.yaw
	minimap.draw_rect(Rect2(Vector2.ZERO, size), Color(0.14, 0.14, 0.15, 0.9))
	for b in Game.city.buildings:
		var a: AABB = b["aabb"]
		var mid := a.get_center()
		if Vector2(mid.x - c.x, mid.z - c.z).length() > radius_m + 60.0:
			continue
		var pts := PackedVector2Array([
			_to_map(Vector3(a.position.x, 0, a.position.z), c, yaw, scale, origin),
			_to_map(Vector3(a.end.x, 0, a.position.z), c, yaw, scale, origin),
			_to_map(Vector3(a.end.x, 0, a.end.z), c, yaw, scale, origin),
			_to_map(Vector3(a.position.x, 0, a.end.z), c, yaw, scale, origin),
		])
		var hcol := clampf(float(b["height"]) / 150.0, 0.0, 1.0)
		minimap.draw_colored_polygon(pts, Color(0.32 + hcol * 0.2, 0.32 + hcol * 0.18, 0.34 + hcol * 0.15))
	if Game.alert_level != Game.Alert.HIDDEN:
		var lk := _to_map(Game.last_known_pos, c, yaw, scale, origin)
		var col := Color(1, 0.85, 0.3, 0.25) if Game.alert_level == Game.Alert.SEARCHING else Color(1, 0.2, 0.15, 0.25)
		minimap.draw_circle(lk, 25.0 * scale, col)
	for n in get_tree().get_nodes_in_group("hives"):
		var p := _to_map((n as Node3D).global_position, c, yaw, scale, origin)
		minimap.draw_circle(p, 6.0, Color(1, 0.1, 0.1))
	for n in get_tree().get_nodes_in_group("infected"):
		var p := _to_map((n as Node3D).global_position, c, yaw, scale, origin)
		var big := (n as Node).is_in_group("hunters")
		minimap.draw_circle(p, 4.5 if big else 2.0, Color(1, 0.55, 0.1))
	for n in get_tree().get_nodes_in_group("military"):
		var node := n as Node3D
		var p := _to_map(node.global_position, c, yaw, scale, origin)
		if node.is_in_group("vehicles"):
			minimap.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color(1, 0.2, 0.2))
		else:
			minimap.draw_circle(p, 2.2, Color(1, 0.25, 0.25) if Game.is_hunted() else Color(0.6, 0.75, 0.5))
	for n in get_tree().get_nodes_in_group("pickups"):
		var p := _to_map((n as Node3D).global_position, c, yaw, scale, origin)
		minimap.draw_circle(p, 3.0, Color(0.4, 1, 0.5))
	if Game.director:
		for e in Game.director.active_events:
			var p := _to_map(e["pos"], c, yaw, scale, origin)
			var off := p - origin
			if off.length() > size.x * 0.5 - 8.0:
				p = origin + off.normalized() * (size.x * 0.5 - 8.0)
			var col: Color = e["color"]
			minimap.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)]), col)
	# player arrow
	var fa := wrapf(_bearing(player.facing) - yaw, -PI, PI)
	var tip := Vector2(0, -9).rotated(-fa)
	var l := Vector2(-5, 6).rotated(-fa)
	var r := Vector2(5, 6).rotated(-fa)
	minimap.draw_colored_polygon(PackedVector2Array([origin + tip, origin + r, origin + l]), Color(1, 1, 1))


func _draw_big_map() -> void:
	if player == null or Game.city == null:
		return
	var vs := big_map.size
	big_map.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.03, 0.035, 0.88))
	var half: float = Game.city.city_half_size() + 30.0
	var scale := minf(vs.x, vs.y) * 0.9 / (half * 2.0)
	var origin := vs * 0.5
	var to2 := func(p: Vector3) -> Vector2: return origin + Vector2(p.x, p.z) * scale
	for b in Game.city.buildings:
		var a: AABB = b["aabb"]
		if absf(a.get_center().x) > half or absf(a.get_center().z) > half:
			continue
		var p0: Vector2 = to2.call(a.position)
		var p1: Vector2 = to2.call(a.end)
		big_map.draw_rect(Rect2(Vector2(p0.x, p0.y), Vector2(p1.x - p0.x, p1.y - p0.y)), Color(0.3, 0.3, 0.33))
	var font := ThemeDB.fallback_font
	for n in get_tree().get_nodes_in_group("hives"):
		big_map.draw_circle(to2.call((n as Node3D).global_position), 8.0, Color(1, 0.1, 0.1))
	if Game.director:
		for e in Game.director.active_events:
			var p: Vector2 = to2.call(e["pos"])
			var col: Color = e["color"]
			big_map.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -10), p + Vector2(10, 0), p + Vector2(0, 10), p + Vector2(-10, 0)]), col)
			big_map.draw_string(font, p + Vector2(14, 5), e["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
	var pp: Vector2 = to2.call(player.global_position)
	big_map.draw_circle(pp, 7.0, Color.WHITE)
	big_map.draw_string(font, pp + Vector2(10, -10), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	big_map.draw_string(font, Vector2(40, 50), "MAP  (M to close)   North is up", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.4, 0.3))
