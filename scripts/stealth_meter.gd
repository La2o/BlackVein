extends Control
## Stealth meter (Prototype 2 style): an eye at the top of the screen that opens as the military
## grows suspicious (UNSEEN -> NOTICED -> SPOTTED / SEARCHING), and arrows around the middle of the
## screen pointing at every soldier who is noticing you right now.

var _shown := 0.0     # fades the meter in and out
var _pulse := 0.0
var _detect := 0.0    # smoothed fill


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Soldiers within `radius` who can see you and find you suspicious (npc.gd sets `noticing`).
static func watchers(radius := 90.0) -> Array:
	var out := []
	var p := Game.player
	if p == null:
		return out
	for s in p.get_tree().get_nodes_in_group("military"):
		var n := s as Node3D
		if n and n.get("noticing") == true and n.global_position.distance_to(p.global_position) < radius:
			out.append(n)
	return out


func state() -> String:
	match Game.alert_level:
		Game.Alert.ALERT: return "SPOTTED"
		Game.Alert.SEARCHING: return "SEARCHING"
	return "NOTICED" if Game.suspicion > 0.02 else "UNSEEN"


func detection() -> float:
	match Game.alert_level:
		Game.Alert.ALERT: return 1.0
		Game.Alert.SEARCHING: return clampf(Game.search_timer / 22.0, 0.0, 1.0)
	return clampf(Game.suspicion, 0.0, 1.0)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	_pulse += real
	var p := Game.player
	var want := 0.0
	if p and not p.is_dead() and p.vehicle == null:
		if Game.alert_level != Game.Alert.HIDDEN or Game.suspicion > 0.01:
			want = 1.0
		elif Game.nearest_in_group("military", p.global_position, 70.0) != null:
			want = 0.75
	_shown = move_toward(_shown, want, real * 3.0)
	_detect = lerpf(_detect, detection(), 1.0 - exp(-8.0 * real))
	queue_redraw()


func _draw() -> void:
	if _shown <= 0.01:
		return
	var st := state()
	var col := Color(0.55, 0.85, 1.0)
	if st == "NOTICED":
		col = Color(1.0, 0.8, 0.3)
	elif st == "SEARCHING":
		col = Color(1.0, 0.6, 0.2)
	elif st == "SPOTTED":
		col = Color(1.0, 0.25, 0.2)
	col.a = _shown
	var c := Vector2(size.x * 0.5, 82.0)
	var w := 34.0
	var h := 15.0 + 5.0 * _detect
	# the eye: an almond outline, an iris ring that fills with suspicion, a pupil that dilates
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for k in 17:
		var t := k / 16.0
		var x := lerpf(-w, w, t)
		var y := sin(t * PI) * h
		top.append(c + Vector2(x, -y))
		bottom.append(c + Vector2(x, y))
	var almond := top.duplicate()
	for k in range(bottom.size() - 2, 0, -1):
		almond.append(bottom[k])
	draw_colored_polygon(almond, Color(0.04, 0.04, 0.05, 0.6 * _shown))
	draw_polyline(top, col, 2.5, true)
	draw_polyline(bottom, col, 2.5, true)
	var iris := 11.0
	draw_arc(c, iris, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.3 * _shown), 2.0, true)
	if _detect > 0.01:
		draw_arc(c, iris, -PI * 0.5, -PI * 0.5 + TAU * _detect, 32, col, 3.5, true)
	var pupil := lerpf(3.0, 7.5, _detect)
	if st == "SPOTTED":
		pupil += sin(_pulse * 10.0) * 1.0
	draw_circle(c, pupil, col)
	var font := get_theme_default_font()
	var label := st
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string_outline(font, c + Vector2(-tw * 0.5, h + 22.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4,
		Color(0, 0, 0, 0.8 * _shown))
	draw_string(font, c + Vector2(-tw * 0.5, h + 22.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	# arrows towards the soldiers who are noticing you, around the centre of the screen
	var p := Game.player
	if p == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var centre := size * 0.5
	var fwd := -cam.global_transform.basis.z
	var cam_yaw := atan2(fwd.x, fwd.z)
	for n in watchers():
		var to: Vector3 = (n as Node3D).global_position - p.global_position
		var ang := atan2(to.x, to.z) - cam_yaw
		var dir := Vector2(-sin(ang), -cos(ang))
		var tip := centre + dir * 150.0
		var side := Vector2(-dir.y, dir.x)
		var a_col := Color(1.0, 0.25, 0.2, 0.9) if Game.is_hunted() else Color(1.0, 0.8, 0.3, 0.85)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 16.0 + side * 9.0, tip - dir * 16.0 - side * 9.0]), a_col)
