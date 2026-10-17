extends CharacterBody3D
## Every person in the city: civilians, scientists, soldiers, rocket soldiers,
## elite strike-team soldiers, infected and hunters. One script with a small
## state machine; the "kind" decides stats, look and behavior.

const HUMANOID := preload("res://scripts/humanoid.gd")
const PROJECTILE := preload("res://scripts/projectile.gd")
const PICKUP := preload("res://scripts/pickup.gd")

enum S { IDLE, WANDER, FLEE, COWER, PATROL, SEARCH, ENGAGE, CHASE, LEAP, LAUNCHED, GRABBED, CONSUMED, DEAD }

const KINDS := {
	"civilian": {"hp": 30.0, "walk": 1.7, "run": 6.5, "faction": "civilian", "label": "a civilian"},
	"scientist": {"hp": 45.0, "walk": 1.6, "run": 6.0, "faction": "civilian", "label": "a scientist"},
	"soldier": {"hp": 55.0, "walk": 2.6, "run": 6.2, "faction": "military", "label": "a soldier", "weapon": "rifle"},
	"rocket_soldier": {"hp": 55.0, "walk": 2.6, "run": 6.0, "faction": "military", "label": "a rocket soldier", "weapon": "launcher"},
	"elite": {"hp": 150.0, "walk": 3.0, "run": 8.0, "faction": "military", "label": "a strike team soldier", "weapon": "rifle"},
	"infected": {"hp": 35.0, "walk": 2.0, "run": 7.2, "faction": "infected", "label": "an infected"},
	"hunter": {"hp": 480.0, "walk": 4.0, "run": 15.0, "faction": "infected", "label": "a hunter"},
}
const FIRST_NAMES := ["Dana", "Marcus", "Elena", "Victor", "Ruth", "Isaac", "Mara", "Owen", "Lena", "Samuel"]
const LAST_NAMES := ["Kessler", "Okafor", "Vance", "Moreau", "Hale", "Ibarra", "Lindqvist", "Brandt", "Castell"]

var kind := "civilian"
var faction := "civilian"
var hp := 30.0
var max_hp := 30.0
var walk_speed := 2.0
var run_speed := 6.0
var state: int = S.WANDER
var model: Node3D
var outfit: Dictionary = {}
var label := ""
var memory := ""
var scale_factor := 1.0
var patrol_center := Vector3.ZERO
var event_tag := ""        # lets world events track their units

var _path := PackedVector3Array()
var _path_index := 0
var _path_target := Vector3.INF
var _repath_timer := 0.0
var _think_timer := 0.0
var _state_timer := 0.0
var _target: Node3D = null
var _target_pos := Vector3.ZERO
var _move_goal := Vector3.ZERO
var _goal_speed := 0.0
var _flee_from := Vector3.ZERO
var _attack_cooldown := 0.0
var _burst_left := 0
var _burst_timer := 0.0
var _strafe := 1.0
var _strafe_timer := 0.0
var _airborne_time := 0.0
var _thrower: Node = null
var _dead_time := 0.0
var _hit_flash := 0.0
var _face_dir := Vector3.FORWARD
var _infected_killer := false
var _leap_cooldown := 0.0
var _scream_cooldown := 0.0
var _search_point := Vector3.INF
var _last_seen_player := 99.0
var _grabbed_by: Node = null
var _collision: CollisionShape3D

static var _flash_mat: StandardMaterial3D


func setup(k: String, extra := {}) -> void:
	kind = k
	var data: Dictionary = KINDS[k]
	faction = data["faction"]
	max_hp = data["hp"]
	hp = max_hp
	walk_speed = data["walk"]
	run_speed = data["run"]
	label = data["label"]
	event_tag = extra.get("tag", "")
	scale_factor = 1.7 if k == "hunter" else 1.0
	collision_layer = Game.LAYER_NPC
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_VEHICLE
	floor_snap_length = 0.4
	_collision = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35 * scale_factor
	cap.height = 1.8 * scale_factor
	_collision.shape = cap
	add_child(_collision)
	outfit = _make_outfit(k)
	if extra.has("outfit"):
		outfit = extra["outfit"]
	model = Node3D.new()
	model.set_script(HUMANOID)
	add_child(model)
	model.setup(outfit)
	model.scale = Vector3.ONE * scale_factor
	if k == "scientist":
		label = "Dr. %s %s" % [FIRST_NAMES[randi() % FIRST_NAMES.size()], LAST_NAMES[randi() % LAST_NAMES.size()]]
		memory = extra.get("memory", "Memory absorbed: the outbreak started in a lab under the city.")
	add_to_group("npcs")
	add_to_group("warm")
	add_to_group(faction)
	if faction == "civilian":
		add_to_group("civilians")
	if faction == "infected":
		add_to_group("infected")
	if faction == "military":
		add_to_group("military")
	if k == "hunter":
		add_to_group("hunters")
	patrol_center = global_position
	_think_timer = randf() * 0.4
	_strafe = 1.0 if randf() < 0.5 else -1.0
	match faction:
		"civilian": state = S.WANDER
		"military": state = S.PATROL
		"infected": state = S.WANDER
	if Game.player and Game.player.powers.thermal_on:
		model.set_thermal(true)


func _make_outfit(k: String) -> Dictionary:
	var skins := [Color(0.85, 0.68, 0.55), Color(0.62, 0.45, 0.33), Color(0.42, 0.29, 0.2), Color(0.95, 0.8, 0.68), Color(0.3, 0.2, 0.14)]
	var skin: Color = skins[randi() % skins.size()]
	match k:
		"soldier":
			return {"shirt": Color(0.3, 0.33, 0.22), "pants": Color(0.25, 0.27, 0.18), "skin": skin, "gear": "helmet", "item": "rifle"}
		"rocket_soldier":
			return {"shirt": Color(0.32, 0.32, 0.24), "pants": Color(0.24, 0.25, 0.18), "skin": skin, "gear": "helmet", "item": "launcher"}
		"elite":
			return {"shirt": Color(0.07, 0.07, 0.08), "pants": Color(0.09, 0.09, 0.1), "skin": skin, "gear": "helmet",
				"gear_color": Color(0.1, 0.1, 0.11), "item": "rifle", "glow": Color(0.2, 0.6, 1.0)}
		"scientist":
			return {"shirt": Color(0.92, 0.92, 0.9), "pants": Color(0.25, 0.27, 0.3), "skin": skin, "gear": "hair",
				"gear_color": Color(0.5, 0.5, 0.5)}
		"infected":
			var rag: Color = Color(randf_range(0.15, 0.35), randf_range(0.12, 0.3), randf_range(0.1, 0.25))
			return {"shirt": rag, "pants": rag.darkened(0.3), "skin": Color(0.45, 0.48, 0.38), "glow": Color(0.9, 0.12, 0.05)}
		"hunter":
			return {"shirt": Color(0.3, 0.08, 0.07), "pants": Color(0.22, 0.06, 0.05), "skin": Color(0.35, 0.1, 0.09),
				"glow": Color(1, 0.15, 0.05), "bulk": 1.5}
		_:
			var shirts := [Color(0.7, 0.2, 0.2), Color(0.2, 0.35, 0.6), Color(0.85, 0.8, 0.7), Color(0.25, 0.25, 0.28),
				Color(0.55, 0.45, 0.2), Color(0.3, 0.5, 0.35), Color(0.6, 0.3, 0.5), Color(0.9, 0.55, 0.2)]
			var pants := [Color(0.15, 0.17, 0.25), Color(0.3, 0.28, 0.25), Color(0.1, 0.1, 0.1), Color(0.45, 0.4, 0.32)]
			var gears := ["hair", "hair", "cap", "none"]
			return {"shirt": shirts[randi() % shirts.size()], "pants": pants[randi() % pants.size()], "skin": skin,
				"gear": gears[randi() % gears.size()], "gear_color": Color(randf() * 0.3, randf() * 0.25, randf() * 0.2)}


# ------------------------------------------------------------------ public API

func is_alive() -> bool:
	return state != S.DEAD and state != S.CONSUMED and hp > 0.0


func can_see_point(p: Vector3) -> bool:
	return Game.line_of_sight(global_position + Vector3.UP * 0.7 * scale_factor, p)


func can_be_grabbed() -> bool:
	if state in [S.GRABBED, S.CONSUMED]:
		return false
	if kind == "hunter":
		return hp < max_hp * 0.3 and state != S.DEAD
	return true


func can_be_consumed() -> bool:
	if state == S.CONSUMED or state == S.GRABBED and _grabbed_by != Game.player:
		return false
	if state == S.DEAD:
		return _dead_time < 8.0 and kind != "hunter"
	if kind == "hunter":
		return hp < max_hp * 0.3
	return true


func panic(from: Vector3) -> void:
	if faction != "civilian" or not is_alive() or state in [S.LAUNCHED, S.GRABBED]:
		return
	_flee_from = from
	if state != S.FLEE:
		state = S.FLEE
		_state_timer = randf_range(7.0, 12.0)
		_path_target = Vector3.INF
		if _scream_cooldown <= 0.0 and randf() < 0.35:
			Game.fx.sound("scream", global_position, -6.0, 0.25)
			_scream_cooldown = 6.0


func take_hit(info: Dictionary) -> void:
	if state in [S.CONSUMED]:
		return
	var dmg: float = info["damage"]
	var force: Vector3 = info["force"]
	var src: Node = info["source"]
	if state == S.GRABBED:
		return
	if state == S.DEAD:
		if force.length() > 3.0:
			velocity = force
			_airborne_time = 0.0
		return
	if kind == "elite" and info["kind"] == "bullet":
		dmg *= 0.6
	hp -= dmg
	_hit_flash = 0.12
	if src != null and is_instance_valid(src):
		if src == Game.player or src.is_in_group("decoys") or (src.has_method("is_player_controlled") and src.is_player_controlled()):
			_on_attacked_by_player()
		elif src is Node3D and faction != "civilian":
			var s3 := src as Node3D
			if s3.is_in_group("npcs") and s3.get("faction") != faction:
				_target = s3
		if src.is_in_group("infected") and faction == "civilian":
			_infected_killer = true
	var launch_threshold := 30.0 if kind == "hunter" else 7.0
	if force.length() > launch_threshold:
		_launch(force * (0.4 if kind == "hunter" else 1.0), src)
	else:
		velocity += force * 0.5
	if hp <= 0.0:
		_die(info)
	elif faction == "civilian":
		panic(global_position - force)


func _on_attacked_by_player() -> void:
	if faction == "military":
		Game.raise_alert(Game.player.global_position, "You attacked the military")
		Game.add_heat(0.12)
	elif faction == "civilian":
		Game.panic_at(global_position, 25.0)
	if faction == "infected" or faction == "military":
		_target = Game.player


func _launch(force: Vector3, src: Node) -> void:
	velocity = force
	state = S.LAUNCHED if hp > 0.0 else S.DEAD
	_airborne_time = 0.0
	_thrower = src
	if hp > 0.0:
		state = S.LAUNCHED


func yank_to(by: Node3D) -> void:
	if not is_alive() and state != S.DEAD:
		return
	var to := by.global_position - global_position
	var dist := to.length()
	velocity = to.normalized() * clampf(dist * 3.0, 12.0, 40.0) + Vector3.UP * minf(dist * 0.35, 9.0)
	if state != S.DEAD:
		state = S.LAUNCHED
	_airborne_time = 0.0
	_thrower = by
	if by == Game.player:
		_on_attacked_by_player()


func on_grabbed(by: Node) -> void:
	state = S.GRABBED
	_grabbed_by = by
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if by == Game.player:
		_on_attacked_by_player()
		if faction == "civilian" and _scream_cooldown <= 0.0:
			Game.fx.sound("scream", global_position, -2.0, 0.2)
			_scream_cooldown = 4.0


func on_thrown(vel: Vector3, by: Node) -> void:
	_grabbed_by = null
	collision_layer = Game.LAYER_NPC
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_VEHICLE
	if by is CollisionObject3D:
		add_collision_exception_with(by)
		get_tree().create_timer(0.3, false).timeout.connect(func():
			if is_instance_valid(self) and is_instance_valid(by):
				remove_collision_exception_with(by))
	velocity = vel
	_thrower = by
	_airborne_time = 0.0
	state = S.LAUNCHED if hp > 0.0 else S.DEAD
	global_basis = Basis()


func on_consume_start(_by: Node) -> void:
	state = S.CONSUMED
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO


func on_consume_cancel() -> void:
	scale = Vector3.ONE
	collision_layer = Game.LAYER_NPC
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_VEHICLE
	state = S.LAUNCHED
	velocity = Vector3.UP * 3.0


func on_consumed(_by: Node) -> Dictionary:
	var info := {"kind": kind, "outfit": outfit, "label": label, "memory": memory, "tag": event_tag}
	if faction == "military" and is_alive():
		Game.kills["military"] += 1
	get_tree().call_group("event_listeners", "on_unit_removed", self, "consumed")
	queue_free()
	return info


func _die(info: Dictionary) -> void:
	if state == S.DEAD:
		return
	var was_launched := state == S.LAUNCHED
	state = S.DEAD
	hp = 0.0
	_dead_time = 0.0
	remove_from_group(faction)
	remove_from_group("civilians")
	remove_from_group("military")
	remove_from_group("infected")
	remove_from_group("hunters")
	remove_from_group("warm")
	var src: Node = info["source"]
	var by_player: bool = src == Game.player or (src != null and is_instance_valid(src) and src.has_method("is_player_controlled") and src.is_player_controlled())
	if by_player:
		match faction:
			"military":
				Game.kills["military"] += 1
				Game.add_heat(0.18)
				Game.add_xp(30 if kind == "elite" else (14 if kind == "rocket_soldier" else 12))
			"infected":
				Game.kills["infected"] += 1
				Game.add_xp(150 if kind == "hunter" else 5)
				if kind == "hunter":
					Game.feed("Hunter killed", Color(0.7, 1, 0.6))
			"civilian":
				Game.kills["civilian"] += 1
	Game.fx.splat(global_position + Vector3.UP * 0.4, Vector3.UP, Color(0.5, 0.02, 0.02) if faction != "infected" else Color(0.35, 0.05, 0.03), 18)
	if kind in ["soldier", "rocket_soldier", "elite"] and randf() < 0.4:
		_drop_weapon()
	if kind == "hunter":
		Game.fx.sound("roar", global_position, 2.0, 0.3)
	if faction == "civilian":
		Game.panic_at(global_position, 20.0)
	if not was_launched:
		velocity = (info["force"] as Vector3) * 0.5
	get_tree().call_group("event_listeners", "on_unit_removed", self, "killed")
	if _infected_killer and kind == "civilian":
		get_tree().create_timer(4.0, false).timeout.connect(_rise_infected)


func _drop_weapon() -> void:
	var p := Area3D.new()
	p.set_script(PICKUP)
	get_parent().add_child(p)
	p.global_position = global_position + Vector3(0, -0.5, 0)
	var weapon: String = KINDS[kind].get("weapon", "rifle")
	p.setup(weapon, 90 if weapon == "rifle" else 6)
	if model.held_item:
		model.held_item.visible = false


func _rise_infected() -> void:
	if not is_instance_valid(self) or state != S.DEAD:
		return
	var n := CharacterBody3D.new()
	n.set_script(load("res://scripts/npc.gd"))
	get_parent().add_child(n)
	n.global_position = global_position + Vector3.UP * 0.3
	n.setup("infected")
	Game.fx.splat(global_position, Vector3.UP, Color(0.35, 0.05, 0.03), 14)
	queue_free()


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if model == null:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_leap_cooldown = maxf(0.0, _leap_cooldown - delta)
	_scream_cooldown = maxf(0.0, _scream_cooldown - delta)
	_state_timer -= delta
	_last_seen_player += delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
	match state:
		S.GRABBED:
			model.animate(delta, 0.0, "grabbed")
			return
		S.CONSUMED:
			model.animate(delta, 0.0, "grabbed")
			return
		S.DEAD:
			_dead_physics(delta)
			return
		S.LAUNCHED, S.LEAP:
			_launched_physics(delta)
			return
	# Far away from the player: think rarely, keep it cheap.
	var far := Game.player != null and global_position.distance_squared_to(Game.player.global_position) > 160.0 * 160.0
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = (1.2 if far else 0.3) + randf() * 0.1
		_think()
	_act(delta)
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	else:
		velocity.y = -1.0
	move_and_slide()
	_animate(delta)


func _dead_physics(delta: float) -> void:
	_dead_time += delta
	velocity.y -= 30.0 * delta
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0, 25.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 25.0 * delta)
	move_and_slide()
	var k := 1.0 - exp(-8.0 * delta)
	var target_basis := Basis.looking_at(_face_dir, Vector3.UP).rotated(Basis.looking_at(_face_dir, Vector3.UP).x, 1.45)
	model.basis = Basis(model.basis.get_rotation_quaternion().slerp(target_basis.get_rotation_quaternion(), k)).scaled(Vector3.ONE * scale_factor)
	model.position = model.position.lerp(Vector3(0, -0.65 * scale_factor, 0), k)
	model.animate(delta, 0.0, "dead")
	if _dead_time > 1.5 and collision_layer != 0:
		collision_layer = 0
	if _dead_time > 30.0 or global_position.y < -40.0:
		queue_free()


func _launched_physics(delta: float) -> void:
	_airborne_time += delta
	velocity.y -= 30.0 * delta
	var pre := velocity
	move_and_slide()
	# spin while flying
	if state == S.LAUNCHED:
		model.rotate_object_local(Vector3.RIGHT, delta * clampf(pre.length() * 0.5, 2.0, 14.0))
		model.animate(delta, 0.0, "flail")
	else:
		model.animate(delta, 0.0, "air")
	# hit other people while flying fast
	if pre.length() > 12.0 and state == S.LAUNCHED:
		for n in get_tree().get_nodes_in_group("npcs"):
			var o := n as Node3D
			if o != self and o.has_method("take_hit") and o.global_position.distance_squared_to(global_position) < 2.0 and o.call("is_alive"):
				o.take_hit(Game.hit_info(pre.length() * 1.2, pre * 0.6, _thrower, "impact"))
				take_hit(Game.hit_info(pre.length() * 0.5, Vector3.ZERO, _thrower, "impact"))
				velocity *= 0.6
				break
	if get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			var n := c.get_normal()
			if absf(n.y) < 0.5 and pre.length() > 14.0:
				var dmg := (pre.length() - 14.0) * 3.0
				take_hit(Game.hit_info(dmg, Vector3.ZERO, _thrower, "impact"))
				Game.fx.splat(global_position, n, Color(0.5, 0.02, 0.02), 10)
				velocity = velocity.bounce(n) * 0.3
				break
	if is_on_floor() and _airborne_time > 0.1:
		var impact := -pre.y
		if state == S.LEAP:
			_land_from_leap()
			return
		if impact > 12.0 and hp > 0.0:
			take_hit(Game.hit_info((impact - 12.0) * 2.5, Vector3.ZERO, _thrower, "impact"))
		if state == S.DEAD:
			return
		model.basis = Basis().scaled(Vector3.ONE * scale_factor)
		state = S.FLEE if faction == "civilian" else (S.ENGAGE if faction == "military" else S.CHASE)
		_state_timer = 8.0
		_flee_from = global_position - pre
		velocity = Vector3.ZERO
	if global_position.y < -40.0:
		queue_free()


# ------------------------------------------------------------------ thinking

func _think() -> void:
	match faction:
		"civilian": _think_civilian()
		"military": _think_military()
		"infected": _think_infected()


func _think_civilian() -> void:
	var p := Game.player
	if state == S.FLEE:
		if _state_timer <= 0.0:
			state = S.WANDER
			_path_target = Vector3.INF
		return
	# danger nearby?
	var inf := Game.nearest_in_group("infected", global_position, 16.0)
	if inf:
		panic(inf.global_position)
		return
	if p and not p.is_dead():
		var d := global_position.distance_to(p.global_position)
		if d < 14.0 and p.is_conspicuous() and (p.powers.violence_timer > 0.0 or p.powers.is_transformed()):
			panic(p.global_position)
			return
	if state == S.WANDER and (_state_timer <= 0.0 or _path_target == Vector3.INF):
		if randf() < 0.25:
			state = S.IDLE
			_state_timer = randf_range(2.0, 6.0)
		else:
			_move_goal = Game.city.random_sidewalk_point(global_position, 10.0, 45.0)
			_state_timer = 25.0
			_path_target = Vector3.INF
	elif state == S.IDLE and _state_timer <= 0.0:
		state = S.WANDER
		_state_timer = 0.0


func _player_target_pos() -> Vector3:
	var p := Game.player
	if p.vehicle and is_instance_valid(p.vehicle):
		return (p.vehicle as Node3D).global_position + Vector3.UP
	return p.global_position


func _think_military() -> void:
	var p := Game.player
	var me := global_position
	var thermal := kind == "elite"
	var sees_player := false
	if p and not p.is_dead():
		var pp := _player_target_pos()
		var d := me.distance_to(pp)
		if d < 85.0 and can_see_point(pp + Vector3.UP * 0.3):
			sees_player = true
			_last_seen_player = 0.0
			var violent: bool = p.powers.violence_timer > 0.0 or (p.vehicle != null and p.conspicuous_timer > 0.0)
			if violent and d < 60.0 and p.vehicle == null:
				Game.raise_alert(pp, "The military saw you attack")
			elif violent and p.vehicle != null and d < 70.0:
				Game.raise_alert(pp, "They spotted the hijacked vehicle")
			if p.vehicle == null:
				Game.report_sighting(pp, p.is_conspicuous(), me, 0.3, thermal)
			elif Game.is_hunted():
				Game.report_sighting(pp, true, me, 0.3, thermal)
	# choose a target
	var new_target: Node3D = null
	var best := INF
	if Game.is_hunted() and sees_player:
		new_target = p
		best = me.distance_to(p.global_position) * 0.8
	for dcy in get_tree().get_nodes_in_group("decoys"):
		var dn := dcy as Node3D
		var dd := me.distance_to(dn.global_position)
		if dd < 60.0 and dd * 0.5 < best and can_see_point(dn.global_position + Vector3.UP * 0.5):
			new_target = dn
			best = dd * 0.5
	var inf := Game.nearest_in_group("infected", me, 45.0)
	if inf and me.distance_to(inf.global_position) < best and can_see_point(inf.global_position + Vector3.UP * 0.5):
		new_target = inf
		best = me.distance_to(inf.global_position)
	if _target and is_instance_valid(_target) and _target != p and _target.has_method("is_alive") and _target.is_alive() \
			and me.distance_to(_target.global_position) < 50.0 and new_target == null:
		new_target = _target
	_target = new_target
	if _target:
		if state != S.ENGAGE:
			state = S.ENGAGE
			_burst_timer = randf_range(0.3, 0.9)
		return
	if Game.alert_level != Game.Alert.HIDDEN and me.distance_to(Game.last_known_pos) < 220.0:
		if state != S.SEARCH or _search_point == Vector3.INF:
			state = S.SEARCH
			var lk := Game.last_known_pos
			_search_point = Vector3(lk.x + randf_range(-14, 14), 0.2, lk.z + randf_range(-14, 14))
			_path_target = Vector3.INF
		elif me.distance_to(_search_point) < 3.0:
			var lk2 := Game.last_known_pos
			_search_point = Vector3(lk2.x + randf_range(-20, 20), 0.2, lk2.z + randf_range(-20, 20))
			_path_target = Vector3.INF
		return
	_search_point = Vector3.INF
	if state != S.PATROL and state != S.IDLE:
		state = S.PATROL
		_path_target = Vector3.INF
	if state == S.IDLE and _state_timer <= 0.0:
		state = S.PATROL
		_path_target = Vector3.INF
	if state == S.PATROL and (_path_target == Vector3.INF or me.distance_to(_move_goal) < 2.5):
		if randf() < 0.3 and _path_target != Vector3.INF:
			state = S.IDLE
			_state_timer = randf_range(2.0, 5.0)
		else:
			_move_goal = Game.city.random_street_point(patrol_center, 5.0, 35.0)
			_path_target = Vector3.INF


func _think_infected() -> void:
	var me := global_position
	var best: Node3D = null
	var best_d := 34.0 if kind != "hunter" else 70.0
	var p := Game.player
	if p and not p.is_dead() and p.vehicle == null:
		var d := me.distance_to(p.global_position)
		if d < best_d and (d < 12.0 or can_see_point(p.global_position)):
			best = p
			best_d = d * (0.6 if kind == "hunter" else 1.0)
	for g in ["civilians", "military", "decoys"]:
		var n := Game.nearest_in_group(g, me, best_d)
		if n:
			var d := me.distance_to(n.global_position)
			if d < best_d:
				best = n
				best_d = d
	if best == null and kind == "hunter" and p and not p.is_dead():
		# hunters always hunt the player when a hunter event is running
		if me.distance_to(p.global_position) < 160.0:
			best = p
	if best != null and best != _target and kind == "hunter" and _scream_cooldown <= 0.0:
		Game.fx.sound("roar", me, 0.0, 0.2)
		_scream_cooldown = 8.0
	_target = best
	if _target:
		state = S.CHASE
	elif state == S.CHASE or (state == S.WANDER and (_path_target == Vector3.INF or me.distance_to(_move_goal) < 2.0)):
		state = S.WANDER
		_move_goal = Game.city.random_street_point(patrol_center, 3.0, 25.0)
		_path_target = Vector3.INF


# ------------------------------------------------------------------ acting

func _act(delta: float) -> void:
	match state:
		S.IDLE, S.COWER:
			_stop(delta)
		S.WANDER:
			_go(_move_goal, walk_speed * (1.0 if faction != "infected" else 1.2), delta)
		S.PATROL:
			_go(_move_goal, walk_speed, delta)
		S.SEARCH:
			_go(_search_point, run_speed * 0.8, delta)
		S.FLEE:
			var away := global_position - _flee_from
			away.y = 0
			if away.length() < 0.1:
				away = Vector3(randf() - 0.5, 0, randf() - 0.5)
			if _path_target == Vector3.INF or global_position.distance_to(_move_goal) < 3.0:
				_move_goal = global_position + away.normalized() * 35.0
				_move_goal = Game.city.closest_nav_point(_move_goal)
				_path_target = Vector3.INF
			_go(_move_goal, run_speed, delta)
		S.ENGAGE:
			_act_engage(delta)
		S.CHASE:
			_act_chase(delta)


func _go(goal: Vector3, speed: float, delta: float) -> void:
	_repath_timer -= delta
	if _path_target == Vector3.INF or _path_target.distance_to(goal) > 3.0 or _repath_timer <= 0.0:
		_path = Game.city.nav_path(global_position, goal)
		_path_index = 0
		_path_target = goal
		_repath_timer = 1.5 + randf()
	var next := goal
	while _path_index < _path.size():
		var p := _path[_path_index]
		if Vector2(p.x - global_position.x, p.z - global_position.z).length() < 0.8:
			_path_index += 1
		else:
			next = p
			break
	var to := next - global_position
	to.y = 0.0
	if to.length() < 0.4:
		_stop(delta)
		return
	var v := to.normalized() * speed
	velocity.x = move_toward(velocity.x, v.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, v.z, 30.0 * delta)


func _stop(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)


func _act_engage(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or (_target.has_method("is_alive") and not _target.is_alive()) \
			or (_target == Game.player and Game.player.is_dead()):
		_target = null
		state = S.PATROL
		_path_target = Vector3.INF
		return
	var tpos := _player_target_pos() if _target == Game.player else _target.global_position
	var to := tpos - global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	var ideal_min := 20.0 if kind == "rocket_soldier" else 10.0
	var ideal_max := 40.0 if kind == "rocket_soldier" else 28.0
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.5, 3.0)
		_strafe = -_strafe if randf() < 0.6 else _strafe
	var dir := flat.normalized() if dist > 0.01 else Vector3.FORWARD
	var side := dir.cross(Vector3.UP) * _strafe
	var move := side * 0.6
	if dist > ideal_max:
		_go(tpos, run_speed, delta)
	else:
		if dist < ideal_min:
			move -= dir
		var v := move.normalized() * walk_speed * 1.1 if move.length() > 0.01 else Vector3.ZERO
		velocity.x = move_toward(velocity.x, v.x, 20.0 * delta)
		velocity.z = move_toward(velocity.z, v.z, 20.0 * delta)
	_face_dir = dir
	if dist > 75.0:
		return
	# shooting
	_burst_timer -= delta
	if _burst_timer > 0.0:
		return
	if not can_see_point(tpos + Vector3.UP * 0.3):
		_burst_timer = 0.4
		return
	if kind == "rocket_soldier":
		_fire_rocket(tpos)
		_burst_timer = randf_range(3.5, 5.0)
		return
	if _burst_left <= 0:
		_burst_left = randi_range(3, 5)
	_fire_bullet(tpos, dist)
	_burst_left -= 1
	_burst_timer = 0.11 if _burst_left > 0 else randf_range(0.9, 1.7)


func _fire_bullet(tpos: Vector3, dist: float) -> void:
	var muzzle := global_position + Vector3.UP * 0.55 + _face_dir * 0.7
	var target_speed := 0.0
	if _target is CharacterBody3D:
		target_speed = (_target as CharacterBody3D).velocity.length()
	var spread := 0.025 + dist * 0.0012 + target_speed * 0.004
	if _target == Game.player and Game.player.powers.defense == 1:
		spread *= 0.8
	var aim := tpos + Vector3.UP * randf_range(-0.3, 0.5)
	var dir := (aim - muzzle).normalized()
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	var mask := Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_NPC | Game.LAYER_VEHICLE | Game.LAYER_PROPS
	var hit := Game.raycast(muzzle, muzzle + dir * 120.0, mask, [get_rid()])
	var end := muzzle + dir * 120.0
	if not hit.is_empty():
		end = hit["position"]
		var c := hit["collider"] as Node
		if c and c.has_method("take_hit"):
			var is_friend := c.is_in_group("military")
			if not is_friend:
				var dmg := 5.0 if kind == "elite" else 3.2
				c.take_hit(Game.hit_info(dmg, dir * 1.5, self, "bullet"))
	Game.fx.tracer(muzzle, end)
	Game.fx.sound("gunshot", muzzle, -8.0, 0.2)
	model.swing(true, 4, 0.08)
	Game.panic_at(global_position, 22.0)


func _fire_rocket(tpos: Vector3) -> void:
	var muzzle := global_position + Vector3.UP * 0.7 + _face_dir * 0.8
	var lead := Vector3.ZERO
	if _target is CharacterBody3D:
		lead = (_target as CharacterBody3D).velocity * clampf(muzzle.distance_to(tpos) / 40.0, 0.0, 1.0) * 0.6
	var dir := (tpos + lead - muzzle).normalized()
	var p := Node3D.new()
	p.set_script(PROJECTILE)
	get_parent().add_child(p)
	p.launch(muzzle, dir * 40.0, self, "rocket")
	Game.fx.sound("rocket", muzzle, -2.0)
	Game.panic_at(global_position, 30.0)


func _act_chase(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or (_target.has_method("is_alive") and not _target.is_alive()) \
			or (_target == Game.player and Game.player.is_dead()):
		_target = null
		state = S.WANDER
		_path_target = Vector3.INF
		return
	var tpos := _target.global_position
	var to := tpos - global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	_face_dir = flat.normalized() if dist > 0.01 else _face_dir
	var reach := 1.7 * scale_factor
	if kind == "hunter" and _leap_cooldown <= 0.0 and is_on_floor():
		var height := to.y
		if (dist > 6.0 and dist < 24.0) or (height > 5.0 and dist < 40.0):
			_leap_at(tpos)
			return
	if dist > reach:
		_go(tpos, run_speed, delta)
	else:
		_stop(delta)
		if _attack_cooldown <= 0.0:
			_melee(_target)


func _melee(t: Node3D) -> void:
	_attack_cooldown = 1.1 if kind != "hunter" else 1.4
	model.swing(randf() < 0.5, 1 if kind == "hunter" else 0, 0.3)
	var dmg := 8.0
	var force := _face_dir * 3.0
	if kind == "hunter":
		dmg = 22.0
		force = _face_dir * 18.0 + Vector3.UP * 6.0
	get_tree().create_timer(0.15, false).timeout.connect(func():
		if is_instance_valid(t) and is_instance_valid(self) and is_alive() and t.global_position.distance_to(global_position) < 2.6 * scale_factor:
			t.take_hit(Game.hit_info(dmg, force, self, "melee"))
			Game.fx.splat(t.global_position + Vector3.UP * 0.4, _face_dir, Color(0.5, 0.02, 0.02), 6)
			Game.fx.sound("slash" if kind == "hunter" else "punch", t.global_position, -4.0))


func _leap_at(tpos: Vector3) -> void:
	var to := tpos - global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	var t := clampf(dist / 22.0, 0.5, 1.6)
	var g := 30.0
	var vy := (to.y + 0.5 * g * t * t) / t
	velocity = flat / t + Vector3.UP * vy
	state = S.LEAP
	_airborne_time = 0.0
	_leap_cooldown = randf_range(3.0, 5.0)
	Game.fx.sound("roar", global_position, -2.0, 0.3)


func _land_from_leap() -> void:
	state = S.CHASE
	Game.fx.shockwave(global_position + Vector3.DOWN * 1.4, 5.0, Color(0.8, 0.3, 0.2, 0.6), 0.3)
	Game.fx.sound("land", global_position, 0.0)
	var p := Game.player
	for n in get_tree().get_nodes_in_group("npcs") + [p]:
		var o := n as Node3D
		if o == null or o == self or not is_instance_valid(o) or (o.is_in_group("infected")):
			continue
		if o.global_position.distance_to(global_position) < 4.5:
			var dir := (o.global_position - global_position).normalized()
			o.take_hit(Game.hit_info(25.0, dir * 16.0 + Vector3.UP * 8.0, self, "melee"))


# ------------------------------------------------------------------ animation

func _animate(delta: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	var spd := hv.length()
	if state in [S.ENGAGE, S.CHASE] and _target:
		pass
	elif spd > 0.3:
		_face_dir = hv.normalized()
	var k := 1.0 - exp(-10.0 * delta)
	var tb := Basis.looking_at(_face_dir, Vector3.UP)
	model.basis = Basis(model.basis.get_rotation_quaternion().slerp(tb.get_rotation_quaternion(), k)).scaled(Vector3.ONE * scale_factor)
	model.position = model.position.lerp(Vector3.ZERO, k)
	var mode := "idle"
	if state == S.ENGAGE and faction == "military":
		mode = "aim"
	elif state == S.COWER:
		mode = "cower"
	elif spd > walk_speed * 1.4:
		mode = "run"
	elif spd > 0.3:
		mode = "walk"
	model.animate(delta, spd, mode)
	if _hit_flash > 0.0:
		if _flash_mat == null:
			_flash_mat = StandardMaterial3D.new()
			_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_flash_mat.albedo_color = Color(1, 1, 1, 0.6)
			_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		model.set_tint(_flash_mat)
		set_meta("flashing", true)
	elif has_meta("flashing"):
		remove_meta("flashing")
		model.set_tint(null)
		model._thermal_on = false
		if Game.player and Game.player.powers.thermal_on:
			model.set_thermal(true)
