extends Node
## The event director: keeps the streets populated (civilians, roaming
## infected) and starts world events every minute or two:
## outbreaks, convoys, hunter packs, street battles, supply drops,
## strike teams, airstrikes, VIP targets and gunship patrols.

const PICKUP := preload("res://scripts/pickup.gd")
const HIVE := preload("res://scripts/hive.gd")
const PROJECTILE := preload("res://scripts/projectile.gd")
const TRAFFIC := preload("res://scripts/traffic.gd")

const EVENT_TYPES := {
	"outbreak": {"name": "Infection Outbreak", "weight": 3.0, "color": Color(1, 0.25, 0.2)},
	"convoy": {"name": "Military Convoy", "weight": 2.0, "color": Color(0.6, 0.8, 0.4)},
	"hunters": {"name": "Hunter Pack", "weight": 2.0, "color": Color(1, 0.4, 0.1)},
	"battle": {"name": "Street Battle", "weight": 2.5, "color": Color(1, 0.7, 0.3)},
	"supply": {"name": "Supply Drop", "weight": 2.0, "color": Color(0.4, 1, 0.5)},
	"strike_team": {"name": "Strike Team", "weight": 1.0, "color": Color(0.4, 0.7, 1)},
	"airstrike": {"name": "Bombing Run", "weight": 1.2, "color": Color(1, 0.3, 0.3)},
	"target": {"name": "High-Value Target", "weight": 1.5, "color": Color(0.8, 0.6, 1)},
	"gunship": {"name": "Gunship Patrol", "weight": 1.2, "color": Color(0.6, 0.8, 1)},
	"leviathan": {"name": "BOSS: The Leviathan", "weight": 0.7, "color": Color(1, 0.3, 0.1)},
	"juggernaut": {"name": "BOSS: Juggernaut", "weight": 0.7, "color": Color(0.9, 0.9, 0.95)},
	"origin": {"name": "ORIGIN: Patient Zero", "weight": 0.3, "color": Color(0.35, 0.75, 1.0)},
	"race": {"name": "Rooftop Race", "weight": 1.6, "color": Color(1, 0.85, 0.2)},
}

var active_events: Array[Dictionary] = []
var units_parent: Node3D
var _event_timer := 30.0
var _pop_timer := 1.0
var _next_id := 1
var _was_night := false
var _played_time := 0.0


func _ready() -> void:
	Game.director = self
	add_to_group("event_listeners")


func _process(delta: float) -> void:
	if Game.player == null or Game.city == null or not Game.city.nav_ready:
		return
	if Game.interiors and Game.interiors.is_inside():
		return   # the city waits while you're indoors
	_played_time += delta
	_pop_timer -= delta
	if _pop_timer <= 0.0:
		_pop_timer = 1.5
		_maintain_population()
	_event_timer -= delta
	if _event_timer <= 0.0:
		_event_timer = randf_range(55.0, 100.0)
		if active_events.size() < 2:
			if origin_ready() and not active_events.any(func(e): return e["type"] == "origin"):
				start_random_event("origin")
			else:
				start_random_event()
	for e in active_events.duplicate():
		_update_event(e, delta)
	if Game.daynight:
		var night: bool = Game.daynight.is_night()
		if night and not _was_night:
			Game.feed("Night falls. The infected grow bolder.", Color(0.7, 0.6, 1))
		elif not night and _was_night:
			Game.feed("Dawn breaks over the city.", Color(1, 0.9, 0.6))
		_was_night = night


# ------------------------------------------------------------------ population

func _maintain_population() -> void:
	var p := Game.player
	var ppos: Vector3 = p.global_position
	var civs := 0
	for c in get_tree().get_nodes_in_group("civilians"):
		var n := c as Node3D
		var d := n.global_position.distance_to(ppos)
		if d > 175.0 and str(n.get("event_tag")) == "":
			n.queue_free()
		elif d < 130.0:
			civs += 1
	var want_civs := 42
	if Game.daynight and Game.daynight.is_night():
		want_civs = 24
	want_civs = int(want_civs * Settings.crowd_density)
	if Game.military.crowded():
		want_civs = mini(want_civs, civs)
	for k in mini(4, want_civs - civs):
		var pos: Vector3 = Game.city.random_sidewalk_point(ppos, 32.0, 125.0)
		# don't pop people into existence right in front of the camera
		var cam_fwd: Vector3 = p.aim_direction()
		var to_pos := (pos - ppos)
		if to_pos.length() < 70.0 and Vector3(cam_fwd.x, 0, cam_fwd.z).normalized().dot(Vector3(to_pos.x, 0, to_pos.z).normalized()) > 0.25:
			continue
		Game.military.spawn_npc("scientist" if randf() < 0.02 else "civilian", pos)
	var inf := 0
	for c in get_tree().get_nodes_in_group("infected"):
		var n := c as Node3D
		var d := n.global_position.distance_to(ppos)
		if d > 190.0 and str(n.get("event_tag")) == "":
			n.queue_free()
		elif d < 140.0:
			inf += 1
	var cars := 0
	for c in get_tree().get_nodes_in_group("traffic"):
		if (c as Node3D).global_position.distance_to(ppos) < 160.0:
			cars += 1
	var want_cars := int((4 if Game.is_hunted() else 14) * Settings.crowd_density)
	if cars < want_cars:
		var cell: Vector2i = Game.city.nearest_intersection(Game.city.random_street_point(ppos, 70.0, 150.0))
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var nxt: Vector2i = cell + dirs[randi() % 4]
		nxt = Vector2i(clampi(nxt.x, 0, Game.city.blocks), clampi(nxt.y, 0, Game.city.blocks))
		if nxt != cell:
			var t := CharacterBody3D.new()
			t.set_script(TRAFFIC)
			units_parent.add_child(t)
			var start: Vector3 = Game.city.intersection_pos(cell)
			var dir := (Game.city.intersection_pos(nxt) - start).normalized()
			t.global_position = start + dir * 9.0 + dir.cross(Vector3.UP) * 3.0 + Vector3.UP * 0.2
			t.setup(cell, nxt)
	var want_inf := 3
	if Game.daynight and Game.daynight.is_night():
		want_inf = 14
	if Game.military.crowded():
		want_inf = 0
	for k in mini(3, want_inf - inf):
		var pos: Vector3 = Game.city.random_street_point(ppos, 80.0, 140.0)
		Game.military.spawn_npc("infected", pos)


# ------------------------------------------------------------------ events

func start_random_event(forced := "") -> void:
	var options: Array[String] = []
	var weights: Array[float] = []
	var active_types := active_events.map(func(e): return e["type"])
	for t in EVENT_TYPES:
		if t in active_types:
			continue
		if t == "strike_team" and Game.level < 8:
			continue
		if t in ["hunters", "gunship"] and Game.level < 3:
			continue
		if t == "leviathan" and Game.level < 10:
			continue
		if t == "juggernaut" and Game.level < 12:
			continue
		if t == "origin" and not Game.flags.get("origin_done", false):
			continue
		if t in ["leviathan", "juggernaut"] and (active_types.has("leviathan") or active_types.has("juggernaut")):
			continue
		options.append(t)
		weights.append(EVENT_TYPES[t]["weight"])
	if options.is_empty():
		return
	var chosen := forced
	if chosen == "":
		var total := 0.0
		for w in weights:
			total += w
		var r := randf() * total
		for i in options.size():
			r -= weights[i]
			if r <= 0.0:
				chosen = options[i]
				break
		if chosen == "":
			chosen = options[0]
	call("_start_" + chosen)


func _new_event(type: String, pos: Vector3, duration: float, desc: String) -> Dictionary:
	var e := {
		"id": _next_id, "type": type, "name": EVENT_TYPES[type]["name"], "color": EVENT_TYPES[type]["color"],
		"pos": pos, "timer": duration, "units": [], "desc": desc, "tag": "ev%d" % _next_id, "data": {},
	}
	_next_id += 1
	active_events.append(e)
	Game.feed("%s: %s" % [e["name"], desc], e["color"])
	Game.say(e["name"].to_upper(), e["color"])
	Game.fx.sound_ui("alert", -6.0)
	return e


func _end_event(e: Dictionary, success: bool, reward := 0, text := "") -> void:
	active_events.erase(e)
	if success:
		Game.stat_add("events")
		if e["type"] in ["leviathan", "juggernaut", "origin"]:
			Game.stat_add("bosses")
	if success and reward > 0:
		Game.add_ep(reward, text if text != "" else e["name"] + " complete")
	elif text != "":
		Game.feed(text, Color(0.8, 0.8, 0.8))
	# let leftover tagged units become normal, despawnable units
	for u in e["units"]:
		if is_instance_valid(u) and "event_tag" in u:
			u.event_tag = ""


func _alive_units(e: Dictionary) -> Array:
	var out := []
	for u in e["units"]:
		if is_instance_valid(u) and u.has_method("is_alive") and u.is_alive():
			out.append(u)
	return out


func on_unit_removed(_unit: Node, _how: String) -> void:
	pass


func on_supply_taken(pickup: Node) -> void:
	for e in active_events.duplicate():
		if e["type"] == "supply" and e["data"].get("crate") == pickup:
			_end_event(e, true, 0, "")
			Game.feed("Supply cache secured", Color(0.4, 1, 0.5))


func _update_event(e: Dictionary, delta: float) -> void:
	e["timer"] -= delta
	var alive := _alive_units(e)
	match e["type"]:
		"outbreak":
			var hives := alive.filter(func(u): return u.is_in_group("hives"))
			if hives.is_empty():
				_end_event(e, true, 200, "Outbreak contained")
			elif e["timer"] <= 0.0:
				if hives.size() < 3:
					var origin: Vector3 = hives[0].global_position
					var pos: Vector3 = Game.city.random_street_point(origin, 40.0, 70.0)
					e["units"].append(_spawn_hive(pos, e["tag"]))
					Game.feed("The outbreak is spreading!", e["color"])
				e["timer"] = 180.0
			else:
				e["pos"] = hives[0].global_position
		"leviathan", "juggernaut", "origin":
			var boss = e["data"].get("boss")
			if not is_instance_valid(boss) or not boss.is_alive():
				Game.boss = null
				if e["type"] == "origin" and not Game.flags.get("origin_done", false):
					Game.flags["origin_done"] = true
					_end_event(e, true, 1000, "Patient Zero is gone")
					_ending()
				else:
					_end_event(e, true, 400, "Boss defeated")
				Game.fx.sound_ui("evolve", 2.0)
			else:
				e["pos"] = boss.global_position
				Game.boss = boss
		"convoy", "hunters", "strike_team":
			if alive.is_empty():
				var rewards := {"convoy": 220, "hunters": 260, "strike_team": 320}
				var texts := {"convoy": "Convoy destroyed", "hunters": "Hunter pack wiped out", "strike_team": "Strike team eliminated"}
				_end_event(e, true, rewards[e["type"]], texts[e["type"]])
			else:
				e["pos"] = (alive[0] as Node3D).global_position
				if e["type"] == "convoy":
					var moving := alive.filter(func(u): return u.get("route") != null and u.route.size() > 0)
					if moving.is_empty() and e["timer"] <= 0.0:
						for u in alive:
							u.queue_free()
						_end_event(e, false, 0, "The convoy got away")
				elif e["type"] == "strike_team" and not Game.is_hunted():
					Game.raise_alert(Game.player.global_position, "")
		"battle":
			var soldiers := alive.filter(func(u): return u.is_in_group("military"))
			var infected := alive.filter(func(u): return u.is_in_group("infected"))
			if soldiers.is_empty() or infected.is_empty() or e["timer"] <= 0.0:
				_end_event(e, true, 100, "Street battle over")
		"supply":
			if e["timer"] <= 0.0:
				var crate = e["data"].get("crate")
				if is_instance_valid(crate):
					crate.queue_free()
				_end_event(e, false, 0, "Someone else grabbed the supply drop")
		"airstrike":
			if e["timer"] <= 0.0 and not e["data"].get("dropped", false):
				e["data"]["dropped"] = true
				_drop_bombs(e["pos"])
				e["timer"] = 4.0
			elif e["timer"] <= 0.0:
				_end_event(e, false, 0, "")
		"target":
			var sci = e["data"].get("scientist")
			if not is_instance_valid(sci):
				if e["data"].get("consumed", false) or not is_instance_valid(sci):
					_end_event(e, true, 0, "")
				return
			if not sci.is_alive():
				_end_event(e, false, 0, "The target was killed")
				return
			e["pos"] = sci.global_position
			for u in alive:
				if u != sci:
					u.patrol_center = sci.global_position
			if e["timer"] <= 0.0:
				sci.queue_free()
				_end_event(e, false, 0, "The target was evacuated")
		"race":
			_update_race(e)
		"gunship":
			if alive.is_empty():
				_end_event(e, true, 120, "Gunship patrol destroyed")
			elif e["timer"] <= 0.0:
				for u in alive:
					if not u.is_player_controlled():
						u.queue_free()
				_end_event(e, false, 0, "The gunship returned to base")
			else:
				e["pos"] = (alive[0] as Node3D).global_position


# ------------------------------------------------------------------ event starters

func _event_pos(min_d := 70.0, max_d := 180.0) -> Vector3:
	return Game.city.random_street_point(Game.player.global_position, min_d, max_d)


func _spawn_hive(pos: Vector3, tag: String) -> Node3D:
	var h := StaticBody3D.new()
	h.set_script(HIVE)
	units_parent.add_child(h)
	h.global_position = Vector3(pos.x, 0.0, pos.z)
	h.setup({"tag": tag})
	return h


func _start_outbreak() -> void:
	var pos := _event_pos(80.0, 200.0)
	var e := _new_event("outbreak", pos, 240.0, "Destroy the hive near " + Game.city.location_name(pos))
	e["units"].append(_spawn_hive(pos, e["tag"]))
	for k in 6:
		e["units"].append(Game.military.spawn_npc("infected", pos + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)), {"tag": e["tag"]}))
	Game.panic_at(pos, 60.0)


func _start_convoy() -> void:
	var city := Game.city
	var n: int = city.blocks
	var horizontal := randf() < 0.5
	var lane := randi_range(1, n - 1)
	var route: Array[Vector2i] = []
	var reverse := randf() < 0.5
	for k in range(n + 1):
		var idx := (n - k) if reverse else k
		route.append(Vector2i(idx, lane) if horizontal else Vector2i(lane, idx))
	var start: Vector3 = city.intersection_pos(route[0])
	var second: Vector3 = city.intersection_pos(route[1])
	var dir := (second - start).normalized()
	var yaw := atan2(-dir.x, -dir.z)
	var e := _new_event("convoy", start, 200.0, "Armored convoy moving along " + city.street_name_at((start + second) * 0.5))
	var kinds := ["tank", "truck", "truck"]
	for k in kinds.size():
		var r: Array[Vector2i] = route.duplicate()
		r.pop_front()
		var lane_off := dir.cross(Vector3.UP) * 3.6
		var v: Node3D = Game.military.spawn_ground_vehicle(kinds[k], start - dir * (k * 14.0) + lane_off, yaw, {"tag": e["tag"], "route": r})
		v.set("_cell", route[0])
		v.set("_next_cell", route[0])
		e["units"].append(v)


func _start_hunters() -> void:
	var pos := _event_pos(100.0, 160.0)
	var e := _new_event("hunters", pos, 999.0, "Hunters are stalking the streets. Kill them.")
	for k in randi_range(2, 3):
		var h: Node3D = Game.military.spawn_npc("hunter", pos + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), {"tag": e["tag"]})
		e["units"].append(h)


func _start_battle() -> void:
	var pos := _event_pos(60.0, 150.0)
	var e := _new_event("battle", pos, 150.0, "Soldiers and infected clash at " + Game.city.location_name(pos))
	for k in 8:
		var kind := "rocket_soldier" if k < 2 else "soldier"
		e["units"].append(Game.military.spawn_npc(kind, pos + Vector3(randf_range(-10, 10), 0, randf_range(-14, -6)), {"tag": e["tag"]}))
	for k in 14:
		e["units"].append(Game.military.spawn_npc("infected", pos + Vector3(randf_range(-10, 10), 0, randf_range(6, 16)), {"tag": e["tag"]}))
	if randf() < 0.5:
		e["units"].append(Game.military.spawn_npc("hunter", pos + Vector3(0, 0, 20), {"tag": e["tag"]}))
	Game.panic_at(pos, 60.0)


func _start_supply() -> void:
	var roof: Vector3 = Game.city.random_roof_point(Game.player.global_position, 70.0, 200.0)
	var e := _new_event("supply", roof, 120.0, "A supply cache landed on a rooftop. Get there first.")
	var crate := Area3D.new()
	crate.set_script(PICKUP)
	units_parent.add_child(crate)
	crate.global_position = roof + Vector3(1.5, 0.0, 1.5)
	crate.setup("supply", 150)
	e["data"]["crate"] = crate
	Game.fx.smoke_column(crate.global_position, Color(0.3, 1.0, 0.4, 0.7), 120.0)


func _start_strike_team() -> void:
	var pos := _event_pos(90.0, 140.0)
	var e := _new_event("strike_team", pos, 999.0, "An elite strike team is hunting you. They see through disguises.")
	for k in 5:
		e["units"].append(Game.military.spawn_npc("elite", pos + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), {"tag": e["tag"]}))
	var heli: Node3D = Game.military.spawn_helicopter(pos + Vector3(0, 70, 0), {"tag": e["tag"], "patrol": pos})
	e["units"].append(heli)
	Game.raise_alert(Game.player.global_position, "")


func _start_airstrike() -> void:
	var target := _event_pos(50.0, 140.0)
	var hives := get_tree().get_nodes_in_group("hives")
	if not hives.is_empty():
		target = (hives[0] as Node3D).global_position
	airstrike(target, false)


func airstrike(target: Vector3, at_player: bool) -> void:
	var e := _new_event("airstrike", target, 8.0, "Bombers are hitting %s. Clear the red smoke!" % Game.city.location_name(target))
	if at_player:
		e["desc"] = "Bombers are targeting your last position!"
	Game.fx.smoke_column(target, Color(1.0, 0.15, 0.1, 0.8), 10.0)
	Game.panic_at(target, 50.0)


func _drop_bombs(center: Vector3) -> void:
	for k in 12:
		var off := Vector3(randf_range(-18, 18), 0, randf_range(-18, 18))
		get_tree().create_timer(k * 0.25, false).timeout.connect(func():
			var b := Node3D.new()
			b.set_script(PROJECTILE)
			units_parent.add_child(b)
			b.launch(center + off + Vector3(0, 90, 0), Vector3(randf_range(-2, 2), -40, randf_range(-2, 2)), null, "bomb"))
	Game.fx.sound_ui("alert", -2.0)


func _start_target() -> void:
	var pos: Vector3 = Game.city.random_sidewalk_point(Game.player.global_position, 80.0, 170.0)
	var memories := [
		"Memory absorbed: the virus was engineered as a weapon. Project name: BLACKVEIN.",
		"Memory absorbed: the military plans to burn the whole district if the outbreak spreads.",
		"Memory absorbed: there is a cure prototype hidden in a lab under Wall St.",
		"Memory absorbed: you were the first test subject. You volunteered.",
		"Memory absorbed: the hunters were soldiers once.",
	]
	var e := _new_event("target", pos, 240.0, "Consume the scientist for his memories. He has an armed escort.")
	var sci: Node3D = Game.military.spawn_npc("scientist", pos, {"tag": e["tag"], "memory": memories[randi() % memories.size()]})
	e["data"]["scientist"] = sci
	e["units"].append(sci)
	for k in 4:
		e["units"].append(Game.military.spawn_npc("elite" if k == 0 else "soldier", pos + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), {"tag": e["tag"]}))


func _start_leviathan() -> void:
	var pos := _event_pos(110.0, 170.0)
	var e := _new_event("leviathan", pos, 999.0, "A colossal infected is tearing through the city. It's coming for you.")
	var boss: Node3D = Game.military.spawn_npc("leviathan", pos, {"tag": e["tag"]})
	boss.global_position += Vector3.UP * 2.5
	e["data"]["boss"] = boss
	e["units"].append(boss)
	Game.boss = boss
	Game.fx.sound("roar", pos, 10.0, 0.05)


func _start_juggernaut() -> void:
	var cell: Vector2i = Game.city.nearest_intersection(_event_pos(120.0, 180.0))
	var pos: Vector3 = Game.city.intersection_pos(cell)
	var e := _new_event("juggernaut", pos, 999.0, "The military deployed its prototype super-tank to hunt you down.")
	var boss: Node3D = Game.military.spawn_ground_vehicle("juggernaut", pos, randf() * TAU, {"tag": "hunt_boss" + e["tag"]})
	e["data"]["boss"] = boss
	e["units"].append(boss)
	Game.boss = boss


## The finale unlocks once you have pieced together 5 memories at level 18+.
func origin_ready() -> bool:
	var mems: Array = Game.stats.get("memory_log", [])
	return mems.size() >= 5 and Game.level >= 18 and not Game.flags.get("origin_done", false)


func _start_origin() -> void:
	var cell := Vector2i(Game.city.blocks / 2 + 1, Game.city.blocks / 2 + 2)
	var pos: Vector3 = Game.city.intersection_pos(cell)
	var first: bool = not Game.flags.get("origin_done", false)
	var desc := "Your memories lead to a hidden lab under the city. Something is waiting." if first \
		else "Patient Zero has regrown. End it again."
	var e := _new_event("origin", pos, 999.0, desc)
	# the lab hatch
	var hatch := Node3D.new()
	units_parent.add_child(hatch)
	hatch.global_position = pos
	hatch.reset_physics_interpolation()
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 5.0
	cm.bottom_radius = 5.0
	cm.height = 0.2
	ring.mesh = cm
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.05, 0.1, 0.15)
	blue.emission_enabled = true
	blue.emission = Color(0.2, 0.6, 1.0)
	blue.emission_energy_multiplier = 1.5
	ring.material_override = blue
	ring.position = Vector3(0, 0.15, 0)
	hatch.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.7, 1.0)
	light.light_energy = 5.0
	light.omni_range = 25.0
	light.position = Vector3(0, 4, 0)
	hatch.add_child(light)
	Game.fx.smoke_column(pos, Color(0.3, 0.7, 1.0, 0.6), 120.0)
	e["units"].append(hatch)
	var boss: Node3D = Game.military.spawn_npc("patient_zero", pos + Vector3(0, 1.0, 0), {"tag": e["tag"]})
	e["data"]["boss"] = boss
	e["units"].append(boss)
	Game.boss = boss
	if first:
		Game.feed("The memories fit together: BLACKVEIN was born in that lab. So were you.", Color(0.6, 0.85, 1))


func _ending() -> void:
	Game.say("PATIENT ZERO IS CONSUMED BY THE CITY", Color(0.5, 0.85, 1))
	var lines := [
		"The virus has only one host left that matters: you.",
		"The military will keep coming. The infected will keep rising.",
		"But the city belongs to BLACKVEIN now.",
		"(Keep playing — everything keeps going, and Patient Zero may return.)",
	]
	for k in lines.size():
		get_tree().create_timer(2.5 + k * 3.0, false).timeout.connect(Game.feed.bind(lines[k], Color(0.7, 0.9, 1)))


## Rooftop Race: glowing rings across the rooftops, hit them all before time runs out.
func _start_race() -> void:
	var p: Vector3 = Game.player.global_position
	var points: Array[Vector3] = []
	var cur: Vector3 = Game.city.random_roof_point(p, 20.0, 70.0)
	for k in 8:
		points.append(cur + Vector3(0, 4.0, 0))
		cur = Game.city.random_roof_point(cur, 35.0, 85.0)
	var e := _new_event("race", points[0], 30.0 + points.size() * 11.0, "Reach every ring before time runs out. Sprint, jump, glide!")
	e["data"]["points"] = points
	e["data"]["index"] = 0
	e["data"]["started"] = false
	e["data"]["rings"] = []
	for k in points.size():
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 3.6
		t.outer_radius = 4.2
		t.rings = 32
		t.ring_segments = 8
		ring.mesh = t
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 0.85, 0.2, 0.9 if k == 0 else 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = m
		units_parent.add_child(ring)
		ring.global_position = points[k]
		var nxt: Vector3 = points[mini(k + 1, points.size() - 1)]
		var dir := (nxt - points[k])
		dir.y = 0
		if dir.length() > 0.1:
			ring.look_at(points[k] + dir, Vector3.UP)
		ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		ring.reset_physics_interpolation()
		e["data"]["rings"].append(ring)
		e["units"].append(ring)


func _update_race(e: Dictionary) -> void:
	var d: Dictionary = e["data"]
	var points: Array = d["points"]
	var idx: int = d["index"]
	if idx >= points.size():
		return
	var target: Vector3 = points[idx]
	e["pos"] = target
	var rings: Array = d["rings"]
	for k in rings.size():
		var r = rings[k]
		if is_instance_valid(r):
			r.rotate_object_local(Vector3.UP, 0.03)
	if Game.player.global_position.distance_to(target) < 6.0:
		if is_instance_valid(rings[idx]):
			rings[idx].queue_free()
		Game.fx.burst_ring(target, Color(1, 0.85, 0.2, 0.8), 6.0)
		Game.fx.sound_ui("pickup", -2.0)
		idx += 1
		d["index"] = idx
		if not d["started"]:
			d["started"] = true
			d["t0"] = Game.play_time
		e["timer"] += 4.0
		if idx >= points.size():
			var bonus := int(maxf(0.0, e["timer"]) * 4.0)
			var took: float = Game.play_time - float(d.get("t0", Game.play_time))
			var best: float = float(Game.stats.get("race_best", 9999.0))
			var record := took < best
			if record:
				Game.stats["race_best"] = took
			_end_event(e, true, 220 + bonus + (100 if record else 0), "Race complete in %.1f s%s" % [took, "  NEW RECORD" if record else "  (best %.1f s)" % best])
			Game.stat_add("races")
			return
		if is_instance_valid(rings[idx]):
			(rings[idx].material_override as StandardMaterial3D).albedo_color.a = 0.9
		Game.feed("Ring %d / %d" % [idx, points.size()], e["color"])
	elif e["timer"] <= 0.0:
		for r in rings:
			if is_instance_valid(r):
				r.queue_free()
		_end_event(e, false, 0, "Out of time — the race is over")


func _start_gunship() -> void:
	var pos := _event_pos(60.0, 140.0)
	var e := _new_event("gunship", pos, 150.0, "A gunship is patrolling. Take it down or steal it.")
	var a := randf() * TAU
	var heli: Node3D = Game.military.spawn_helicopter(pos + Vector3(cos(a) * 80.0, 60.0, sin(a) * 80.0), {"tag": e["tag"], "patrol": pos})
	e["units"].append(heli)
