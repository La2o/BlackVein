extends Node
## The military: keeps patrols around the player and escalates its response
## with heat (soldiers -> rocket teams -> tanks -> gunships -> strike teams
## and airstrikes). Also offers spawn helpers to the event director.

const NPC := preload("res://scripts/npc.gd")
const GROUND_VEHICLE := preload("res://scripts/ground_vehicle.gd")
const HELICOPTER := preload("res://scripts/helicopter.gd")

var units_parent: Node3D
var _timer := 3.0
var _airstrike_timer := 30.0
var _ambient_tank: Node3D = null
var _commander_respawn := 0.0
var _commander: Node3D = null
var _base_units: Array[Node3D] = []


func _ready() -> void:
	Game.military = self


func crowded() -> bool:
	return Game.npc_count > Game.NPC_CAP


func spawn_npc(kind: String, pos: Vector3, extra := {}) -> CharacterBody3D:
	var n := CharacterBody3D.new()
	n.set_script(NPC)
	units_parent.add_child(n)
	n.global_position = pos + Vector3.UP * 0.6
	n.setup(kind, extra)
	n.patrol_center = pos
	return n


func spawn_ground_vehicle(kind: String, pos: Vector3, yaw: float, extra := {}) -> CharacterBody3D:
	var v := CharacterBody3D.new()
	v.set_script(GROUND_VEHICLE)
	units_parent.add_child(v)
	v.global_position = pos + Vector3.UP * 0.3
	v.rotation.y = yaw
	v.setup(kind, extra)
	return v


func spawn_helicopter(pos: Vector3, extra := {}) -> CharacterBody3D:
	var h := CharacterBody3D.new()
	h.set_script(HELICOPTER)
	units_parent.add_child(h)
	h.global_position = pos
	h.setup(extra)
	return h


func _process(delta: float) -> void:
	if Game.player == null or Game.city == null or not Game.city.nav_ready:
		return
	if Game.interiors and Game.interiors.is_inside():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 2.0
	_maintain()


## Keeps the military base garrisoned while the player is in the area.
func _maintain_base(ppos: Vector3) -> void:
	var city: City = Game.city
	if city.base_rect.size == Vector2.ZERO:
		return
	var center: Vector3 = city.base_points["center"]
	var d := ppos.distance_to(center)
	_commander_respawn -= 2.0
	var alive: Array[Node3D] = []
	for u in _base_units:
		if is_instance_valid(u) and u.has_method("is_alive") and u.is_alive():
			alive.append(u)
	_base_units = alive
	if d > 330.0:
		for u in _base_units:
			u.queue_free()
		_base_units.clear()
		return
	if d > 260.0:
		return
	var soldiers := _base_units.filter(func(u): return u.is_in_group("npcs") and u.kind != "commander").size()
	var has_commander: bool = is_instance_valid(_commander) and _commander.is_alive()
	if _commander != null and not has_commander:
		_commander = null
		_commander_respawn = 600.0
	var has_tank := _base_units.any(func(u): return u.is_in_group("vehicles") and u.get("kind") == "tank")
	var has_heli := _base_units.any(func(u): return u.is_in_group("helicopters"))
	# reinforce slowly so clearing the base actually matters
	if soldiers < 10 and (d > 120.0 or randf() < 0.15):
		var kind := "rocket_soldier" if randf() < 0.25 else "soldier"
		var s := spawn_npc(kind, city.random_base_point(), {"tag": "base"})
		s.in_base = true
		_base_units.append(s)
	if not has_commander and _commander_respawn <= 0.0 and d > 50.0:
		var c := spawn_npc("commander", city.base_points["command"] + Vector3(4, 0, 0), {"tag": "base"})
		c.in_base = true
		_base_units.append(c)
		_commander = c
	if not has_tank and d > 100.0:
		var t := spawn_ground_vehicle("tank", city.base_points["tank"], PI * 0.5, {"tag": "base"})
		t.abandoned = true      # parked until the base is attacked
		t.set_meta("base_tank", true)
		_base_units.append(t)
	if not has_heli and d > 100.0:
		var h := spawn_helicopter(city.base_points["helipad"] + Vector3(0, 1.6, 0), {"tag": "base", "patrol": center})
		h.parked = true
		_base_units.append(h)
	# wake up the base when it's under attack
	if Game.is_hunted() and Game.last_known_pos.distance_to(center) < 120.0:
		for u in _base_units:
			if u.has_meta("base_tank") and u.abandoned and u.pilot == null:
				u.abandoned = false
			if u.is_in_group("helicopters") and u.parked:
				u.parked = false


func _count(group: String, near: Vector3, radius: float, filter := "") -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group(group):
		var node := u as Node3D
		if node == null or node.global_position.distance_to(near) > radius:
			continue
		if filter != "" and node.get("kind") != filter:
			continue
		n += 1
	return n


func _maintain() -> void:
	var p := Game.player
	var ppos: Vector3 = p.global_position
	# despawn far-away, untagged units
	for u in get_tree().get_nodes_in_group("military"):
		var node := u as Node3D
		if node and str(node.get("event_tag")) == "" and node.global_position.distance_to(ppos) > 280.0 and node != _ambient_tank:
			node.queue_free()
	_maintain_base(ppos)
	if p.is_dead():
		return
	var heat := Game.heat
	var hunted := Game.is_hunted()
	var focus: Vector3 = Game.last_known_pos if Game.alert_level != Game.Alert.HIDDEN else ppos
	# foot soldiers
	var soldiers := 0
	for sk in Game.SOLDIER_KINDS:
		soldiers += _count("military", ppos, 150.0, sk)
	var wanted := 8
	if hunted:
		wanted = 10 + int(heat * 4.0)
	elif Game.alert_level == Game.Alert.SEARCHING:
		wanted = 12
	if soldiers < wanted and not crowded():
		var squad := mini(4, wanted - soldiers)
		var min_d := 70.0 if hunted else 60.0
		var base: Vector3 = Game.city.random_street_point(focus, min_d, 120.0)
		for k in squad:
			var kind := "soldier"
			var roll := randf()
			if hunted and roll < 0.25 + heat * 0.04:
				kind = "rocket_soldier"
			elif hunted and heat >= 1.5 and roll < 0.45 + heat * 0.04:
				kind = "grenadier"
			elif hunted and heat >= 2.5 and roll < 0.6 + heat * 0.03:
				kind = "heavy_gunner"
			elif hunted and heat >= 2.0 and roll < 0.72 + heat * 0.03:
				kind = "riot"
			if heat >= 4.0 and randf() < 0.35:
				kind = "elite"
			var s := spawn_npc(kind, base + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
			s.patrol_center = base
	# snipers on the rooftops once the heat is up
	if hunted and heat >= 2.5 and _count("military", ppos, 200.0, "sniper") < 2 and randf() < 0.2:
		var roof: Vector3 = Game.city.random_roof_point(ppos, 50.0, 140.0)
		if roof.y > 8.0:
			spawn_npc("sniper", roof)
	# tanks
	var tanks := _count("military_vehicles", ppos, 220.0, "tank")
	var want_tanks := 0
	if hunted and heat >= 2.5:
		want_tanks = 1 if heat < 4.0 else 2
	if tanks < want_tanks:
		var cell: Vector2i = Game.city.nearest_intersection(Game.city.random_street_point(focus, 90.0, 150.0))
		var pos: Vector3 = Game.city.intersection_pos(cell)
		spawn_ground_vehicle("tank", pos, randf() * TAU)
		Game.feed("Armor moving in", Color(1, 0.45, 0.35))
	# gunships
	var helis := get_tree().get_nodes_in_group("helicopters").filter(func(h): return h.is_alive() and str(h.event_tag) == "").size()
	var want_helis := 0
	if hunted and heat >= 3.2:
		want_helis = 1 if heat < 4.8 else 2
	if helis < want_helis:
		var a := randf() * TAU
		spawn_helicopter(focus + Vector3(cos(a) * 150.0, 80.0, sin(a) * 150.0))
		Game.feed("Gunship inbound", Color(1, 0.45, 0.35))
	# airstrikes at maximum heat
	_airstrike_timer -= 2.0
	if hunted and heat >= 4.5 and _airstrike_timer <= 0.0 and Game.director:
		_airstrike_timer = 45.0
		Game.director.airstrike(Game.last_known_pos, true)
	# an ambient patrol tank somewhere in the city
	if (_ambient_tank == null or not is_instance_valid(_ambient_tank)) and randf() < 0.2:
		var far_cell: Vector2i = Game.city.nearest_intersection(Game.city.random_street_point(ppos, 120.0, 200.0))
		_ambient_tank = spawn_ground_vehicle("tank", Game.city.intersection_pos(far_cell), randf() * TAU, {"tag": "ambient"})
