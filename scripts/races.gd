extends Node3D
## Time trials: four fixed courses. A glowing beacon in the street starts a timed run through rings on the rooftops.
## (Different from the random Rooftop Race world event: these are always there and keep your best time.)
## Walk into a beacon to start. Best times are saved in Game.flags["race_best"] (race index -> seconds).

const RACES := 4
const RINGS := 8
const START_RADIUS := 3.0
const RING_RADIUS := 5.5

var starts: Array[Vector3] = []
var courses: Array = []          # per race: Array[Vector3] of ring centres
var pars: Array[float] = []      # par time per race (seconds)
var active := -1                 # race being run, -1 when none
var next_ring := 0
var time := 0.0
var countdown := 0.0

var _beacons: Array[Node3D] = []
var _rings: Array[Node3D] = []
var _label: Label
var _beam_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _next_mat: StandardMaterial3D
var _cooldown := 0.0


func setup(city: City) -> void:
	_beam_mat = _glow(Color(0.25, 0.85, 1.0, 0.35), 2.5)
	_ring_mat = _glow(Color(0.25, 0.85, 1.0, 0.5), 1.5)
	_next_mat = _glow(Color(1.0, 0.85, 0.2, 0.85), 4.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = city.city_seed + 97
	var tops: Array[Vector3] = []
	var h := city.city_half_size() - 10.0
	for b in city.buildings:
		var a: AABB = b["aabb"]
		var c := a.get_center()
		if absf(c.x) > h or absf(c.z) > h or city.in_base(c):
			continue
		tops.append(Vector3(c.x, a.end.y + 3.0, c.z))
	# four starts spread around the map, each on a street corner
	var quadrants := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for r in RACES:
		var q: Vector2 = quadrants[r]
		var i := clampi(int(city.blocks * (0.5 + q.x * 0.22)), 0, city.blocks)
		var j := clampi(int(city.blocks * (0.5 + q.y * 0.22)), 0, city.blocks)
		var start := Vector3(city.street_x(i), 0.0, city.street_z(j))
		var course := _plan_course(start, tops, rng)
		if course.size() < 4:
			continue
		starts.append(start)
		courses.append(course)
		var length := 0.0
		var prev := start
		for p in course:
			length += prev.distance_to(p)
			prev = p
		pars.append(snappedf(length / 17.0 + 4.0, 1.0))   # a brisk rooftop pace
		_beacons.append(_make_beacon(start))
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 6)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.position.y = 128
	_label.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	layer.add_child(_label)
	_label.offset_left = -300
	_label.offset_right = 300


## A chain of rooftops leading away from the start, each 30-75 m from the last.
func _plan_course(start: Vector3, tops: Array[Vector3], rng: RandomNumberGenerator) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var prev := start
	var heading := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
	for k in RINGS:
		var best := Vector3.INF
		var best_score := -INF
		for t in tops:
			var d := Vector2(t.x - prev.x, t.z - prev.z)
			var dl := d.length()
			if dl < 30.0 or dl > 75.0 or out.has(t):
				continue
			var score := d.normalized().dot(heading) + rng.randf_range(0.0, 0.6) - absf(t.y - prev.y) * 0.004
			if score > best_score:
				best_score = score
				best = t
		if best == Vector3.INF:
			break
		out.append(best)
		var nd := Vector2(best.x - prev.x, best.z - prev.z).normalized()
		heading = (heading * 0.6 + nd * 0.4).rotated(rng.randf_range(-0.5, 0.5)).normalized()
		prev = best
	return out


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_beacon(at: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.2
	cm.bottom_radius = 1.2
	cm.height = 90.0
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 45.0
	n.add_child(beam)
	var ring := _ring_mesh(2.4)
	ring.rotation.x = 0.0
	ring.position.y = 0.15
	n.add_child(ring)
	return n


func _ring_mesh(radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.3
	tm.outer_radius = radius
	mi.mesh = tm
	mi.material_override = _ring_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func best_time(r: int) -> float:
	var bests: Dictionary = Game.flags.get("race_best", {})
	return float(bests.get(str(r), 0.0))


func start_race(r: int) -> void:
	active = r
	next_ring = 0
	time = 0.0
	countdown = 3.0
	for b in _beacons:
		b.visible = false
	for k in courses[r].size():
		var p: Vector3 = courses[r][k]
		var ring := _ring_mesh(RING_RADIUS)
		add_child(ring)
		ring.global_position = p
		_rings.append(ring)
	_point_rings()
	var best := best_time(r)
	Game.say("TIME TRIAL %d  ·  par %s%s" % [r + 1, _fmt(pars[r]), ("  ·  best " + _fmt(best)) if best > 0.0 else ""], Color(1, 0.9, 0.5))
	Game.fx.sound("pickup", Game.player.global_position, 0.0, 0.2)


func _point_rings() -> void:
	var p := Game.player
	for k in _rings.size():
		var ring: MeshInstance3D = _rings[k]
		ring.visible = k >= next_ring and k <= next_ring + 2
		ring.material_override = _next_mat if k == next_ring else _ring_mat
		# face the ring toward the approach so you fly through it
		var from: Vector3 = p.global_position if k == 0 else (_rings[k - 1] as Node3D).global_position
		var d := ring.global_position - from
		d.y = 0.0
		if d.length() > 0.5:
			ring.global_basis = Basis.looking_at(d.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI / 2.0)


func end_race(finished: bool) -> void:
	var r := active
	active = -1
	for ring in _rings:
		ring.queue_free()
	_rings.clear()
	for b in _beacons:
		b.visible = true
	_label.visible = false
	_cooldown = 4.0
	if not finished:
		Game.say("Time trial abandoned", Color(1, 0.6, 0.5))
		return
	var bests: Dictionary = Game.flags.get("race_best", {})
	var old := float(bests.get(str(r), 0.0))
	var first := old <= 0.0
	var record := first or time < old
	if record:
		bests[str(r)] = snappedf(time, 0.01)
	Game.flags["race_best"] = bests
	Game.stat_max("trials", bests.size())
	var xp := 150 if first else 40
	if time <= pars[r]:
		xp += 60
	Game.add_xp(xp, "Time trial %d: %s%s%s" % [r + 1, _fmt(time), "  under par!" if time <= pars[r] else "", "  NEW BEST" if record and not first else ""])
	Game.fx.sound("evolve", Game.player.global_position, 0.0)


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


func _process(delta: float) -> void:
	var p := Game.player
	if p == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if active < 0:
		if _cooldown > 0.0 or p.is_dead() or p.vehicle != null:
			return
		for r in starts.size():
			var s: Vector3 = starts[r]
			if Vector2(p.global_position.x - s.x, p.global_position.z - s.z).length() < START_RADIUS and p.global_position.y < s.y + 4.0:
				start_race(r)
				return
		return
	if p.is_dead() or p.vehicle != null:
		end_race(false)
		return
	_label.visible = true
	if countdown > 0.0:
		countdown -= delta
		_label.text = "%d" % int(ceil(countdown)) if countdown > 0.0 else "GO!"
		return
	time += delta
	var course: Array = courses[active]
	_label.text = "TRIAL %d   %s   ·   ring %d/%d   ·   par %s" % [active + 1, _fmt(time), next_ring, course.size(), _fmt(pars[active])]
	if time > pars[active] * 2.5 + 30.0:
		end_race(false)
		return
	var target: Vector3 = course[next_ring]
	if p.global_position.distance_to(target) < RING_RADIUS:
		next_ring += 1
		Game.fx.sound("pickup", target, -4.0, 0.1)
		Game.fx.burst_ring(target, Color(1, 0.85, 0.2, 0.7), 3.0)
		if next_ring >= course.size():
			end_race(true)
			return
		_point_rings()
