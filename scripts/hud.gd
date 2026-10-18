extends CanvasLayer
## Everything on screen: health and biomass, powers, alert level, compass,
## minimap, event list and feed, button prompts (keyboard or controller),
## screen effects, and the pause, evolve, controls and map menus.

const SCREEN_FX := preload("res://shaders/screen_fx.gdshader")
const SPEED_LINES := preload("res://shaders/speed_lines.gdshader")
const FORMS_WHEEL := preload("res://scripts/forms_wheel.gd")

const KEYS := {
	"attack": ["LMB", "X"], "special": ["RMB", "Y"], "grab": ["E", "RB"], "consume": ["F", "LB"],
	"jump": ["Space", "A"], "dash": ["Q", "B"], "tether": ["C", "LT"], "focus": ["Z", "L3"],
	"thermal": ["V", "R3"], "decoy": ["B", "D-pad Down"], "defense": ["X", "D-pad Up"],
	"wheel": ["Alt / hold X", "Hold D-pad Up"],
	"spikes": ["G", "LB+X"], "tendrils": ["T", "LB+Y"], "artillery": ["R", "LB+RB"], "forms": ["1-7 / Wheel", "D-pad L/R"],
	"evolve": ["Tab", "Back"], "pause": ["Esc", "Start"], "sprint": ["Shift", "RT"], "wardrobe": ["I", "LB+B"],
	"creature": ["N", "LB+D-pad Down"],
}

var player: Node
var whats_new_panel: Control = null   # the "what's new" popup while it is showing
var wheel: Control
var wheel_open: bool:
	get:
		return wheel != null and wheel.open
var _night := 0.0
var _night_target := 0.0
var _sense := 0.0
var _sense_target := 0.0
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
var goal_label: Label
var stats_label: Label
var form_label: Label
var ability_label: Label
var prompt_label: Label
var notify_label: Label
var feed_box: VBoxContainer
var events_label: RichTextLabel
var alert_label: Label
var suspicion_bar: ProgressBar
var stealth_label: Label   # "Blending in" / "Standing out: flying" while soldiers are near
var stealth_meter: Control  # the eye at the top of the screen (stealth_meter.gd)
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
var settings_panel: PanelContainer
var _settings_first: VBoxContainer
var _pad_label: Label
var rebind_panel: PanelContainer
var wardrobe_panel: PanelContainer
var _wardrobe_list: VBoxContainer
var ach_panel: PanelContainer
var _ach_text: RichTextLabel
var _rebind_buttons := {}
var _rebinding := ""
var combo_label: Label
var fps_label: Label
var version_label: Label
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_label: Label
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
	_build_settings()
	_build_extras()
	_build_achievements()
	_build_wardrobe()
	wheel = Control.new()
	wheel.set_script(FORMS_WHEEL)
	add_child(wheel)
	Game.notify.connect(_on_notify)
	Game.event_feed.connect(_on_feed)
	Game.alert_changed.connect(_on_alert_changed)
	Game.player_died.connect(func(): death_panel.visible = true)
	Game.player_respawned.connect(func(): death_panel.visible = false)
	_maybe_show_whats_new()


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
	goal_label = _label("", 15, Color(1, 0.9, 0.55))
	box.add_child(goal_label)


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
	stealth_meter = Control.new()
	stealth_meter.set_script(preload("res://scripts/stealth_meter.gd"))
	root.add_child(stealth_meter)
	stealth_label = _label("", 13, Color(0.6, 0.9, 1.0), 3)
	stealth_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stealth_label.position = Vector2(-232, 270)
	stealth_label.size = Vector2(210, 18)
	stealth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(stealth_label)
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
Space jump (keeps your speed) — keep holding to leap higher   |   [color=#9fd0ff]A[/color]
Space in the air: double jump, hold to glide   |   [color=#9fd0ff]A[/color]
Q dash (works in the air)   |   [color=#9fd0ff]B[/color]
On a wall: W climbs, A/D runs sideways, Space wall jumps, let go of Shift to drop

[b]FIGHT[/b]
Left click attack (in the air: dive bomb)   |   [color=#9fd0ff]X[/color]
Right click special move for your current form   |   [color=#9fd0ff]Y[/color]
1–7 or mouse wheel: Fists, Claws, Hammerfist, Blade, Whipfist, Musclemass, Bone Spikes   |   [color=#9fd0ff]D-pad left/right[/color]
X cycle defense: Shield / Armor / none   |   [color=#9fd0ff]D-pad up[/color]
E grab a person or car, press again to throw · hijack tanks and gunships · pick up guns   |   [color=#9fd0ff]RB[/color]
F consume someone: heal, gain biomass and steal their disguise   |   [color=#9fd0ff]LB[/color]
I disguise wardrobe: switch between every identity you've consumed   |   [color=#9fd0ff]hold LB + B[/color]
While holding someone: right-click brands them as your ally (Dominate skill)   |   [color=#9fd0ff]Y[/color]
G Groundspike devastator (50 biomass)   |   [color=#9fd0ff]hold LB + X[/color]
T Tendril Barrage devastator (80 biomass)   |   [color=#9fd0ff]hold LB + Y[/color]
R Artillery strike (needs a military disguise)   |   [color=#9fd0ff]hold LB + RB[/color]

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
	pause_menu.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	pause_menu.position = Vector2(70, -330)
	pause_menu.visible = false
	root.add_child(pause_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pause_menu.add_child(v)
	var t := _label("BLACKVEIN", 40, Color(1, 0.25, 0.2), 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	stats_label = _label("", 14, Color(0.85, 0.85, 0.85), 3)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stats_label)
	v.add_child(_menu_button("Resume", func(): toggle_pause(false)))
	v.add_child(_menu_button("Skills", func():
		pause_menu.visible = false
		open_evolve()))
	v.add_child(_menu_button("Save game", func(): Game.save_game(true)))
	v.add_child(_menu_button("Controls", func():
		help_panel.visible = not help_panel.visible))
	v.add_child(_menu_button("Map", func():
		big_map.visible = not big_map.visible))
	v.add_child(_menu_button("Settings", func():
		pause_menu.visible = false
		open_settings()))
	v.add_child(_menu_button("Disguises", func():
		toggle_pause(false)
		open_wardrobe()))
	v.add_child(_menu_button("Achievements & memories", func():
		ach_panel.visible = not ach_panel.visible
		_refresh_achievements()))
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
	_evolve_ep_label.text = "Level %d   ·   %d / %d XP   ·   %d skill point%s   ·   level bonus +%d%% health & damage" % [
		Game.level, Game.xp, Game.xp_to_next(Game.level), Game.skill_points, "" if Game.skill_points == 1 else "s",
		Game.level_bonus_percent()]
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


func _build_extras() -> void:
	combo_label = _label("", 30, Color(1, 0.8, 0.3), 7)
	combo_label.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	combo_label.position = Vector2(-330, -40)
	combo_label.size = Vector2(300, 80)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(combo_label)
	fps_label = _label("", 14, Color(0.7, 1, 0.7))
	fps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fps_label.position = Vector2(-110, -50)
	root.add_child(fps_label)
	# build number in the corner, so screenshots and bug reports say which version they're from
	version_label = _label("v" + str(ProjectSettings.get_setting("application/config/version", "")), 13,
		Color(1, 1, 1, 0.45), 3)
	version_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	version_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(version_label)
	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.position = Vector2(-300, 66)
	boss_box.custom_minimum_size = Vector2(600, 0)
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.visible = false
	root.add_child(boss_box)
	boss_label = _label("", 20, Color(1, 0.4, 0.3), 6)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_label)
	boss_bar = _bar(Color(0.8, 0.1, 0.1), 600, 14)
	boss_box.add_child(boss_bar)


func _build_settings() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.add_theme_stylebox_override("panel", _panel_style(0.94))
	settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	settings_panel.position = Vector2(-340, -330)
	settings_panel.custom_minimum_size = Vector2(680, 660)
	settings_panel.visible = false
	root.add_child(settings_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	settings_panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	_settings_first = v
	v.add_child(_label("SETTINGS", 34, Color(1, 0.3, 0.25), 6))
	_pad_label = _label("", 15, Color(0.6, 0.9, 1), 3)
	v.add_child(_pad_label)
	_slider_row(v, "Mouse sensitivity", 0.2, 3.0, Settings.mouse_sensitivity, func(x): Settings.mouse_sensitivity = x)
	_slider_row(v, "Controller look speed", 0.3, 2.5, Settings.stick_sensitivity, func(x): Settings.stick_sensitivity = x)
	_check_row(v, "Invert look up/down", Settings.invert_y, func(b): Settings.invert_y = b)
	_slider_row(v, "Field of view", 55.0, 100.0, Settings.fov, func(x): Settings.fov = x)
	_slider_row(v, "Volume", 0.0, 1.0, Settings.volume, func(x): Settings.volume = x)
	_slider_row(v, "Music", 0.0, 1.0, Settings.music_volume, func(x): Settings.music_volume = x)
	_slider_row(v, "Camera shake", 0.0, 1.5, Settings.camera_shake, func(x): Settings.camera_shake = x)
	_check_row(v, "Controller rumble", Settings.rumble, func(b): Settings.rumble = b)
	_check_row(v, "Show FPS", Settings.show_fps, func(b): Settings.show_fps = b)
	_check_row(v, "Damage numbers", Settings.damage_numbers, func(b): Settings.damage_numbers = b)
	_slider_row(v, "Crowd density", 0.4, 1.2, Settings.crowd_density, func(x): Settings.crowd_density = x)
	var row := HBoxContainer.new()
	var l := _label("Graphics quality", 18)
	l.custom_minimum_size = Vector2(260, 0)
	row.add_child(l)
	var opt := OptionButton.new()
	for q in ["Low (fast)", "Medium", "High", "Ultra (global illumination)"]:
		opt.add_item(q)
	opt.selected = Settings.quality
	opt.custom_minimum_size = Vector2(300, 40)
	opt.item_selected.connect(func(i):
		Settings.quality = i
		Settings.apply()
		Settings.save_settings())
	row.add_child(opt)
	v.add_child(row)
	v.add_child(_menu_button("Change keys", func():
		settings_panel.visible = false
		_open_rebind()))
	v.add_child(_menu_button("Back", func(): close_settings()))
	_build_rebind()


const WHATS_NEW := """[b][color=#ff5544]WHAT'S NEW in 0.11[/color][/b]

[b]A map four times bigger[/b] — downtown skyscrapers, brick midtown and parks, suburbs of houses and
gardens to the south and west, warehouses and the military base to the east, and farmland with barns
and silos to the north. Press M to see it.

[b][color=#ff5544]0.10[/color][/b]
[b]Real people[/b] — everyone in the city is now a rigged, animated character with a real face, hair and
fitted gear.
[b]Real textures[/b] — brick, concrete, asphalt and paving. Try Ultra graphics in Settings.
[b]Stealth[/b] — parkour all you like in a disguise that fits. Flying, powers and fights give you
away; inside bases even running does. Watch "Blending in / Standing out" near soldiers.
Consume someone unseen for bonus XP.
[b]Guns[/b] — grenade launchers and heavy machine guns. Hold aim on a tank or gunship to lock
rockets on.
[b]New soldiers[/b] — grenadiers and heavy gunners.
[b]Levels[/b] — every level gives +2% health and damage, right away.

Full list: CHANGELOG.md"""


func _maybe_show_whats_new() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if Settings.last_seen_version == version:
		return
	var first_time := Settings.last_seen_version == ""
	Settings.last_seen_version = version
	Settings.save_settings()
	if first_time:
		return
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(0.92))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-330, -160)
	panel.custom_minimum_size = Vector2(660, 0)
	root.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(620, 0)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.text = WHATS_NEW
	v.add_child(rt)
	var ok := _menu_button("Let's go", close_whats_new)
	v.add_child(ok)
	# a real popup: the game waits, the mouse is free to click and the button has keyboard/pad focus
	whats_new_panel = panel
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ok.grab_focus.call_deferred()


func close_whats_new() -> void:
	if whats_new_panel == null:
		return
	if is_instance_valid(whats_new_panel):
		whats_new_panel.queue_free()
	whats_new_panel = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_wardrobe() -> void:
	wardrobe_panel = PanelContainer.new()
	wardrobe_panel.add_theme_stylebox_override("panel", _panel_style(0.94))
	wardrobe_panel.set_anchors_preset(Control.PRESET_CENTER)
	wardrobe_panel.position = Vector2(-380, -330)
	wardrobe_panel.custom_minimum_size = Vector2(760, 660)
	wardrobe_panel.visible = false
	root.add_child(wardrobe_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	wardrobe_panel.add_child(v)
	v.add_child(_label("DISGUISES", 34, Color(1, 0.3, 0.25), 6))
	v.add_child(_label("Every identity you consume is kept here. Change while nobody is watching to lose the military;\nchange in front of soldiers and your cover is blown.", 14, Color(0.85, 0.85, 0.85), 3))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	_wardrobe_list = VBoxContainer.new()
	_wardrobe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wardrobe_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_wardrobe_list)
	v.add_child(_menu_button("Close", func(): close_wardrobe()))


func _any_menu_open() -> bool:
	return wardrobe_panel.visible or evolve_menu.visible or settings_panel.visible or rebind_panel.visible \
		or pause_menu.visible or help_panel.visible or big_map.visible or ach_panel.visible


func _back_out() -> void:
	if wardrobe_panel.visible:
		close_wardrobe()
	elif rebind_panel.visible:
		if _rebinding != "":
			_rebinding = ""
			_refresh_rebind()
			return
		rebind_panel.visible = false
		open_settings()
	elif settings_panel.visible:
		close_settings()
	elif evolve_menu.visible:
		close_evolve()
	elif ach_panel.visible or help_panel.visible or big_map.visible:
		ach_panel.visible = false
		help_panel.visible = false
		big_map.visible = false
		if pause_menu.visible:
			(pause_menu.get_child(0).get_child(2) as Button).grab_focus()
	elif pause_menu.visible:
		toggle_pause(false)


func open_wardrobe() -> void:
	if player == null or player.is_dead() or pause_menu.visible or evolve_menu.visible:
		return
	for c in _wardrobe_list.get_children():
		c.queue_free()
	var entries: Array = [[-1, "true", "Your true form"]]
	for i in Game.disguises.size():
		var d: Dictionary = Game.disguises[i]
		entries.append([i, d["kind"], str(d["label"])])
	var first: Button = null
	for e in entries:
		var info: Array = Game.DISGUISE_INFO.get(e[1], ["?", ""])
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 56)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		var who: String = e[2]
		var wearing: bool = (e[0] == -1 and player.model.true_form) or \
			(e[0] >= 0 and not player.model.true_form and player.model.outfit == Game.disguises[e[0]]["outfit"])
		b.text = "%s%s — %s\n%s" % ["▶ " if wearing else "", info[0], who.capitalize(), info[1]]
		var idx: int = e[0]
		b.pressed.connect(func():
			close_wardrobe()
			player.powers.wear_disguise(idx))
		_wardrobe_list.add_child(b)
		if first == null:
			first = b
	if Game.disguises.is_empty():
		_wardrobe_list.add_child(_label("Consume someone (F / LB) to add their identity here.", 15, Color(0.9, 0.8, 0.6), 3))
	wardrobe_panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	first.grab_focus()


func close_wardrobe() -> void:
	wardrobe_panel.visible = false
	get_tree().paused = pause_menu.visible or evolve_menu.visible
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_achievements() -> void:
	ach_panel = PanelContainer.new()
	ach_panel.add_theme_stylebox_override("panel", _panel_style(0.94))
	ach_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	ach_panel.position = Vector2(-560, -330)
	ach_panel.custom_minimum_size = Vector2(520, 660)
	ach_panel.visible = false
	root.add_child(ach_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 640)
	ach_panel.add_child(scroll)
	_ach_text = RichTextLabel.new()
	_ach_text.bbcode_enabled = true
	_ach_text.fit_content = true
	_ach_text.custom_minimum_size = Vector2(480, 0)
	_ach_text.add_theme_font_size_override("normal_font_size", 15)
	scroll.add_child(_ach_text)


func _refresh_achievements() -> void:
	var lines: Array[String] = ["[b][color=#ff5544]ACHIEVEMENTS[/color][/b]\n"]
	var got := 0
	for a in Game.ACHIEVEMENTS:
		var done := Game.has_achievement(a[0])
		if done:
			got += 1
		var prog := mini(Game.achievement_progress(a[3]), int(a[4]))
		var mark := "[color=#ffd84d]★[/color]" if done else "[color=#666666]☆[/color]"
		var count := "" if done or int(a[4]) <= 1 else "  %d/%d" % [prog, int(a[4])]
		lines.append("%s [b]%s[/b]  [color=#aaaaaa]%s%s[/color]" % [mark, a[1], a[2], count])
	lines[0] = "[b][color=#ff5544]ACHIEVEMENTS  %d/%d[/color][/b]\n" % [got, Game.ACHIEVEMENTS.size()]
	var mems: Array = Game.stats.get("memory_log", [])
	lines.append("\n[b][color=#99ccff]MEMORIES  %d[/color][/b]" % mems.size())
	if mems.is_empty():
		lines.append("[color=#aaaaaa]Consume scientists and commanders to absorb their memories.[/color]")
	for m in mems:
		lines.append("[color=#cfe0ff]• %s[/color]" % str(m).replace("Memory absorbed: ", ""))
	_ach_text.text = "\n".join(lines)


func _build_rebind() -> void:
	rebind_panel = PanelContainer.new()
	rebind_panel.add_theme_stylebox_override("panel", _panel_style(0.95))
	rebind_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	rebind_panel.offset_left = 200
	rebind_panel.offset_right = -200
	rebind_panel.offset_top = 40
	rebind_panel.offset_bottom = -40
	rebind_panel.visible = false
	root.add_child(rebind_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	rebind_panel.add_child(v)
	v.add_child(_label("KEYS", 30, Color(1, 0.3, 0.25), 6))
	v.add_child(_label("Click an action, then press the new key or mouse button. Esc cancels. Controller buttons stay as they are.", 14, Color(0.85, 0.85, 0.85), 3))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 20)
	scroll.add_child(grid)
	for pair in Settings.REBINDABLE:
		var action: String = pair[0]
		var l := _label(pair[1], 17)
		l.custom_minimum_size = Vector2(280, 0)
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(220, 36)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			_rebinding = action
			b.text = "Press a key...")
		grid.add_child(b)
		_rebind_buttons[action] = b
	v.add_child(_menu_button("Reset to defaults", func():
		Settings.reset_bindings()
		_refresh_rebind()))
	v.add_child(_menu_button("Back", func():
		rebind_panel.visible = false
		_rebinding = ""
		open_settings()))


func _refresh_rebind() -> void:
	for action in _rebind_buttons:
		(_rebind_buttons[action] as Button).text = Settings.key_name(action)


func _open_rebind() -> void:
	rebind_panel.visible = true
	_refresh_rebind()
	(_rebind_buttons[Settings.REBINDABLE[0][0]] as Button).grab_focus()


func _slider_row(parent: Control, text: String, lo: float, hi: float, value: float, setter: Callable) -> void:
	var row := HBoxContainer.new()
	var l := _label(text, 18)
	l.custom_minimum_size = Vector2(260, 0)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = (hi - lo) / 100.0
	sl.value = value
	sl.custom_minimum_size = Vector2(300, 32)
	var val := _label("%.2f" % value, 16, Color(0.9, 0.9, 0.9))
	sl.value_changed.connect(func(x):
		setter.call(x)
		val.text = "%.2f" % x if hi <= 5.0 else "%d" % int(x)
		Settings.apply()
		Settings.save_settings())
	row.add_child(sl)
	row.add_child(val)
	parent.add_child(row)


func _check_row(parent: Control, text: String, value: bool, setter: Callable) -> void:
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = value
	cb.add_theme_font_size_override("font_size", 18)
	cb.toggled.connect(func(b):
		setter.call(b)
		Settings.apply()
		Settings.save_settings())
	parent.add_child(cb)


func open_settings() -> void:
	settings_panel.visible = true
	_pad_label.text = Controls.pad_summary()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var first := _settings_first.get_child(2).get_child(1) as Control
	first.grab_focus()


func close_settings() -> void:
	settings_panel.visible = false
	toggle_pause(true)


# ------------------------------------------------------------------ menus

func toggle_pause(on: bool) -> void:
	pause_menu.visible = on
	if on:
		var mins := int(Game.play_time / 60.0)
		stats_label.text = "Level %d  ·  %d XP total  ·  played %dh %02dm\nSoldiers %d  ·  Infected %d  ·  Consumed %d  ·  Events %d  ·  Best combo x%d" % [
			Game.level, Game.total_xp, mins / 60, mins % 60, int(Game.kills.get("military", 0)), int(Game.kills.get("infected", 0)),
			Game.stat("consumes"), Game.stat("events"), Game.best_combo]
	if not on:
		help_panel.visible = false
		big_map.visible = false
		ach_panel.visible = false
	get_tree().paused = on or evolve_menu.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
	if on:
		(pause_menu.get_child(0).get_child(2) as Button).grab_focus()


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
	if _rebinding != "" and event.is_pressed() and (event is InputEventKey or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_rebinding = ""
		else:
			Settings.bind(_rebinding, event)
			_rebinding = ""
		_refresh_rebind()
		return
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_pad = false


func _unhandled_input(event: InputEvent) -> void:
	# Esc / B / jump also close the "what's new" popup (Enter, Space and A press its button)
	if whats_new_panel and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")
			or event.is_action_pressed("jump")):
		close_whats_new()
		get_viewport().set_input_as_handled()
		return
	# B / Esc backs out of whatever menu is open
	if event.is_action_pressed("ui_cancel") and not event is InputEventKey and _any_menu_open():
		_back_out()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("disguise_menu"):
		if wardrobe_panel.visible:
			close_wardrobe()
		else:
			open_wardrobe()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if wardrobe_panel.visible:
			close_wardrobe()
		elif rebind_panel.visible:
			rebind_panel.visible = false
			open_settings()
		elif settings_panel.visible:
			close_settings()
		elif evolve_menu.visible:
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


## head forms: 0 normal, 1 thermal, 2 night vision, 3 predator sense
func set_vision(v: int) -> void:
	_thermal_target = 1.0 if v == 1 else 0.0
	_night_target = 1.0 if v == 2 else 0.0
	_sense_target = 1.0 if v == 3 else 0.0


func open_wheel() -> void:
	if _any_menu_open() or get_tree().paused:
		return
	wheel.open_wheel()


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
	_update_combo_and_boss()
	compass.queue_redraw()
	minimap.queue_redraw()
	if big_map.visible:
		big_map.queue_redraw()


func _update_combo_and_boss() -> void:
	if Game.combo >= 3:
		combo_label.text = "x%d\n%s" % [Game.combo, Game.combo_rank()]
		combo_label.modulate.a = clampf(Game.combo_timer, 0.0, 1.0)
		var hot := clampf(Game.combo / 40.0, 0.0, 1.0)
		combo_label.add_theme_color_override("font_color", Color(1, 0.85 - hot * 0.6, 0.3 - hot * 0.2))
	else:
		combo_label.text = ""
	fps_label.visible = Settings.show_fps
	if Settings.show_fps:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	var b := Game.boss
	if b and is_instance_valid(b) and b.has_method("is_alive") and b.is_alive():
		boss_box.visible = true
		boss_label.text = str(b.get("boss_name"))
		boss_bar.value = float(b.get("hp")) / maxf(float(b.get("max_hp")), 1.0) * 100.0
	else:
		boss_box.visible = false


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
	var goal := Game.current_goal_text()
	goal_label.text = ("GOAL: " + goal) if goal != "" else ""


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
	suspicion_bar.visible = false   # the stealth meter's eye shows suspicion now
	_update_stealth_label()
	suspicion_bar.value = Game.suspicion * 100.0


const KEY_ACTIONS := {
	"attack": "attack", "special": "special", "grab": "grab", "consume": "consume", "jump": "jump", "dash": "dash",
	"tether": "tether", "focus": "focus", "thermal": "thermal", "decoy": "decoy", "defense": "cycle_defense",
	"spikes": "devastator_spikes", "tendrils": "devastator_tendrils", "artillery": "artillery",
	"evolve": "evolve_menu", "sprint": "sprint", "wardrobe": "disguise_menu", "creature": "creature_form",
}


func _update_stealth_label() -> void:
	var p := Game.player
	stealth_label.visible = false
	if p == null or p.is_dead() or p.vehicle != null or Game.alert_level != Game.Alert.HIDDEN:
		return
	var near := Game.nearest_in_group("military", p.global_position, 70.0)
	if near == null:
		return
	var why: String = p.stand_out_reason()
	stealth_label.visible = true
	if why == "":
		stealth_label.text = "Blending in"
		stealth_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	else:
		stealth_label.text = "Standing out: " + why
		stealth_label.add_theme_color_override("font_color", Color(1, 0.55, 0.35))


func _k(action: String) -> String:
	if using_pad:
		return KEYS[action][1]
	if KEY_ACTIONS.has(action):
		return Settings.key_name(KEY_ACTIONS[action])
	return KEYS[action][0]


func _update_powers_text() -> void:
	var pw: Node = player.powers
	var f: int = pw.form
	form_label.text = "%s" % pw.FORM_NAMES[f].to_upper()
	if pw.creature != 0:
		form_label.text = "%s  ·  %s" % [pw.CREATURE_NAMES[pw.creature].to_upper(), form_label.text]
	if pw.weapon != "":
		form_label.text = "%s  (%d)" % [str(pw.WEAPONS[pw.weapon]["name"]).to_upper(), pw.ammo]
		if pw.weapon == "launcher":
			if pw.lock_target:
				form_label.text += "   LOCKED"
			elif pw._lock_on:
				form_label.text += "   locking..."
			else:
				form_label.text += "   (hold %s on a vehicle to lock on)" % _k("special")
	var parts: Array[String] = []
	parts.append("%s %s" % [_k("special"), pw.SPECIAL_NAMES[f]])
	var forms_owned := 0
	for i in pw.FORM_NAMES.size():
		if pw.form_unlocked(i):
			forms_owned += 1
	if forms_owned > 1:
		parts.append("%s forms" % _k("forms"))
	parts.append("%s forms wheel" % _k("wheel"))
	var loadout: Array[String] = []
	if pw.vision != 0:
		loadout.append(pw.VISION_NAMES[pw.vision])
	if pw.defense != 0:
		loadout.append(pw.DEFENSE_NAMES[pw.defense])
	if pw.legs != 0:
		loadout.append(pw.LEG_NAMES[pw.legs])
	if not loadout.is_empty():
		parts.append("[%s]" % " · ".join(loadout))
	parts.append("%s grab   %s consume   %s disguises" % [_k("grab"), _k("consume"), _k("wardrobe")])
	if Game.has_skill("brute_form") or Game.has_skill("stalker_form") or Game.has_skill("wraith_form"):
		parts.append("%s creature form" % _k("creature"))
	var line2: Array[String] = []
	if Game.has_skill("tether"):
		line2.append("%s tether" % _k("tether"))
	if Game.has_skill("focus"):
		line2.append("%s focus%s" % [_k("focus"), " ON" if pw.focus_on else ""])
	if Game.has_skill("decoy"):
		line2.append("%s decoy%s" % [_k("decoy"), "" if pw.decoy_cooldown <= 0.0 else " %ds" % int(ceil(pw.decoy_cooldown))])
	if Game.has_skill("thermal") or Game.has_skill("night_vision"):
		line2.append("%s vision" % _k("thermal"))
	if Game.has_skill("groundspike"):
		line2.append("%s spikes" % _k("spikes"))
	if Game.has_skill("tendrils"):
		line2.append("%s tendrils" % _k("tendrils"))
	if Game.has_skill("dominate"):
		line2.append("allies %d/%d" % [pw.ally_count(), pw.max_allies()])
	if Game.has_skill("artillery"):
		line2.append("%s artillery%s" % [_k("artillery"), "" if pw.artillery_cooldown <= 0.0 else " %ds" % int(ceil(pw.artillery_cooldown))])
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
		text = "%s throw   %s %s" % [_k("attack"), _k("special"), "brand as ally" if pw.held_kind == "npc" and Game.has_skill("dominate") else "drop"]
		if pw.held_kind == "npc":
			text += "   %s consume" % _k("consume")
	elif Game.interiors and Game.interiors.prompt() != "":
		text = "%s %s" % [_k("grab"), Game.interiors.prompt()]
	else:
		var pos: Vector3 = player.global_position
		var v := Game.nearest_in_group("hijackable", pos, 9.0, func(n): return n.has_method("can_hijack") and n.can_hijack(player))
		var pick := Game.nearest_in_group("pickups", pos, 2.8)
		var food := Game.nearest_in_group("npcs", pos, 3.4, func(n): return n.can_be_consumed())
		if v:
			text = "%s hijack %s" % [_k("grab"), "gunship" if v.is_in_group("helicopters") else "tank"]
		elif pick and player.powers.WEAPONS.has(pick.get("kind")):
			text = "%s pick up %s" % [_k("grab"), str(player.powers.WEAPONS.get(pick.get("kind"), {"name": "weapon"})["name"]).to_lower()]
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
		if e["timer"] < 900.0 and e["type"] in ["supply", "target", "outbreak", "gunship", "convoy", "race"]:
			timer = "  %d:%02d" % [int(e["timer"]) / 60, int(e["timer"]) % 60]
		lines.append("[right][color=#%s][b]%s[/b]  %dm%s[/color]\n[color=#cccccc]%s[/color][/right]" % [col.to_html(false), e["name"], d, timer, e["desc"]])
	events_label.text = "\n".join(lines)


func _update_screen_fx(delta: float) -> void:
	_damage = maxf(0.0, _damage - delta * 1.5)
	_thermal = move_toward(_thermal, _thermal_target, delta * 4.0)
	_focus = move_toward(_focus, _focus_target, delta * 4.0)
	_night = move_toward(_night, _night_target, delta * 4.0)
	_sense = move_toward(_sense, _sense_target, delta * 4.0)
	var low := clampf(1.0 - player.health / maxf(player.max_health, 1.0) / 0.3, 0.0, 1.0)
	var m := screen_fx.material as ShaderMaterial
	m.set_shader_parameter("thermal", _thermal)
	m.set_shader_parameter("damage", _damage)
	m.set_shader_parameter("low_health", low if not player.is_dead() else 0.0)
	m.set_shader_parameter("focus", _focus)
	m.set_shader_parameter("night", _night)
	m.set_shader_parameter("sense", _sense)
	m.set_shader_parameter("wheel", 1.0 if wheel_open else 0.0)
	screen_fx.visible = _thermal > 0.0 or _damage > 0.0 or low > 0.0 or _focus > 0.0 or _night > 0.0 or _sense > 0.0 or wheel_open
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
	if Game.interiors and Game.interiors.is_inside():
		# indoors: draw the floor plan instead of the city
		minimap.draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.06, 0.95))
		for r in Game.interiors.map_cells():
			var rr: Rect2 = r
			var q := PackedVector2Array([
				_to_map(Vector3(rr.position.x, 0, rr.position.y), c, yaw, scale * 2.5, origin),
				_to_map(Vector3(rr.end.x, 0, rr.position.y), c, yaw, scale * 2.5, origin),
				_to_map(Vector3(rr.end.x, 0, rr.end.y), c, yaw, scale * 2.5, origin),
				_to_map(Vector3(rr.position.x, 0, rr.end.y), c, yaw, scale * 2.5, origin),
			])
			minimap.draw_colored_polygon(q, Color(0.32, 0.32, 0.36))
		for n in get_tree().get_nodes_in_group("npcs"):
			var node := n as Node3D
			if node.global_position.y > c.y + 20.0 or not node.call("is_alive"):
				continue
			var col := Color(1, 0.25, 0.25) if node.is_in_group("military") else (Color(1, 0.55, 0.1) if node.is_in_group("infected") else (Color(1, 0.35, 0.85) if node.is_in_group("allies") else Color(0.8, 0.8, 0.8)))
			minimap.draw_circle(_to_map(node.global_position, c, yaw, scale * 2.5, origin), 3.0, col)
		var fa0 := wrapf(_bearing(player.facing) - yaw, -PI, PI)
		minimap.draw_colored_polygon(PackedVector2Array([origin + Vector2(0, -9).rotated(-fa0), origin + Vector2(5, 6).rotated(-fa0), origin + Vector2(-5, 6).rotated(-fa0)]), Color.WHITE)
		return
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
	var br: Rect2 = Game.city.base_rect
	if br.size != Vector2.ZERO:
		var bpts := PackedVector2Array([
			_to_map(Vector3(br.position.x, 0, br.position.y), c, yaw, scale, origin),
			_to_map(Vector3(br.end.x, 0, br.position.y), c, yaw, scale, origin),
			_to_map(Vector3(br.end.x, 0, br.end.y), c, yaw, scale, origin),
			_to_map(Vector3(br.position.x, 0, br.end.y), c, yaw, scale, origin),
		])
		minimap.draw_colored_polygon(bpts, Color(0.35, 0.45, 0.25, 0.8))
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
	for n in get_tree().get_nodes_in_group("allies"):
		var ap := _to_map((n as Node3D).global_position, c, yaw, scale, origin)
		minimap.draw_circle(ap, 3.2, Color(1, 0.35, 0.85))
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
	if Game.interiors:
		for e in Game.interiors.entrances:
			var ep := _to_map(e["pos"], c, yaw, scale, origin)
			if (ep - origin).length() < size.x * 0.5:
				minimap.draw_rect(Rect2(ep - Vector2(4, 4), Vector2(8, 8)), e["color"])
				minimap.draw_rect(Rect2(ep - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0), false, 1.5)
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
	# districts as soft colour under the buildings
	var district_cols := [Color(0.2, 0.2, 0.24, 0.6), Color(0.22, 0.2, 0.2, 0.55), Color(0.14, 0.3, 0.14, 0.7),
		Color(0.2, 0.26, 0.2, 0.55), Color(0.25, 0.24, 0.2, 0.55), Color(0.3, 0.28, 0.14, 0.6)]
	var city: City = Game.city
	for cell in city.districts:
		var c: Vector2i = cell
		if c.x < 0 or c.y < 0 or c.x >= city.blocks or c.y >= city.blocks:
			continue
		var o := Vector3(city.x0 + city.street_width + c.x * city.period, 0, city.z0 + city.street_width + c.y * city.period)
		var q0: Vector2 = to2.call(o)
		var q1: Vector2 = to2.call(o + Vector3(city.block_size, 0, city.block_size))
		big_map.draw_rect(Rect2(q0, q1 - q0), district_cols[city.districts[cell]])
	for b in Game.city.buildings:
		var a: AABB = b["aabb"]
		if absf(a.get_center().x) > half or absf(a.get_center().z) > half:
			continue
		var p0: Vector2 = to2.call(a.position)
		var p1: Vector2 = to2.call(a.end)
		big_map.draw_rect(Rect2(Vector2(p0.x, p0.y), Vector2(p1.x - p0.x, p1.y - p0.y)), Color(0.3, 0.3, 0.33))
	var font := ThemeDB.fallback_font
	var br: Rect2 = Game.city.base_rect
	if br.size != Vector2.ZERO:
		var b0: Vector2 = to2.call(Vector3(br.position.x, 0, br.position.y))
		var b1: Vector2 = to2.call(Vector3(br.end.x, 0, br.end.y))
		big_map.draw_rect(Rect2(b0, b1 - b0), Color(0.35, 0.45, 0.25, 0.9))
		big_map.draw_string(font, b0 + Vector2(4, (b1.y - b0.y) * 0.5), "MILITARY BASE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 1, 0.6))
	for n in get_tree().get_nodes_in_group("hives"):
		big_map.draw_circle(to2.call((n as Node3D).global_position), 8.0, Color(1, 0.1, 0.1))
	if Game.interiors:
		for e in Game.interiors.entrances:
			var ep: Vector2 = to2.call(e["pos"])
			big_map.draw_rect(Rect2(ep - Vector2(6, 6), Vector2(12, 12)), e["color"])
			big_map.draw_string(font, ep + Vector2(10, 18), str(e["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, e["color"])
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
