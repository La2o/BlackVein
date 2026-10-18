extends CharacterBody3D
## Every person in the city: civilians, scientists, soldiers, rocket soldiers,
## elite strike-team soldiers, infected and hunters. One script with a small
## state machine; the "kind" decides stats, look and behavior.

const HUMANOID := preload("res://scripts/humanoid.gd")
const PROJECTILE := preload("res://scripts/projectile.gd")
const PICKUP := preload("res://scripts/pickup.gd")

enum S { IDLE, WANDER, FLEE, COWER, PATROL, SEARCH, ENGAGE, CHASE, LEAP, LAUNCHED, GRABBED, CONSUMED, DEAD, FOLLOW }

const KINDS := {
	"civilian": {"hp": 30.0, "walk": 1.7, "run": 6.5, "faction": "civilian", "label": "a civilian"},
	"scientist": {"hp": 45.0, "walk": 1.6, "run": 6.0, "faction": "civilian", "label": "a scientist"},
	"soldier": {"hp": 55.0, "walk": 2.6, "run": 6.2, "faction": "military", "label": "a soldier", "weapon": "rifle"},
	"rocket_soldier": {"hp": 55.0, "walk": 2.6, "run": 6.0, "faction": "military", "label": "a rocket soldier", "weapon": "launcher"},
	"grenadier": {"hp": 60.0, "walk": 2.5, "run": 6.0, "faction": "military", "label": "a grenadier", "weapon": "grenade", "xp": 16},
	"heavy_gunner": {"hp": 130.0, "walk": 2.0, "run": 4.6, "faction": "military", "label": "a heavy gunner", "weapon": "mg", "xp": 24},
	"elite": {"hp": 150.0, "walk": 3.0, "run": 8.0, "faction": "military", "label": "a strike team soldier", "weapon": "rifle"},
	"commander": {"hp": 220.0, "walk": 2.2, "run": 6.0, "faction": "military", "label": "the base commander", "weapon": "rifle"},
	"infected": {"hp": 35.0, "walk": 2.0, "run": 7.2, "faction": "infected", "label": "an infected"},
	"hunter": {"hp": 480.0, "walk": 4.0, "run": 15.0, "faction": "infected", "label": "a hunter"},
	"leviathan": {"hp": 4200.0, "walk": 5.0, "run": 12.5, "faction": "infected", "label": "the Leviathan"},
	"patient_zero": {"hp": 6500.0, "walk": 6.0, "run": 19.0, "faction": "infected", "label": "Patient Zero"},
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
var boss_name := ""
var is_ally := false               # branded by the player's Dominate power
var patrol_points: Array = []      # if set (indoors), wander/patrol only between these spots
var _brand_mark: MeshInstance3D
var _ally_teleport_cd := 0.0
var _ally_far_time := 0.0
static var _brand_mat: StandardMaterial3D
var in_base := false
var _pound_cooldown := 6.0
var _adds_cooldown := 15.0
var _dash_cooldown := 3.0
var _volley_cooldown := 6.0
var _dash_time := 0.0
var _pz_phase := 0

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
	reset_physics_interpolation()
	faction = data["faction"]
	max_hp = data["hp"]
	hp = max_hp
	walk_speed = data["walk"]
	run_speed = data["run"]
	label = data["label"]
	event_tag = extra.get("tag", "")
	scale_factor = 1.7 if k == "hunter" else (3.2 if k == "leviathan" else 1.0)
	if k == "leviathan":
		boss_name = "THE LEVIATHAN"
	if k == "patient_zero":
		scale_factor = 1.15
		boss_name = "PATIENT ZERO"
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
	if k == "hunter" or k == "leviathan":
		var spike_mat: Material = HUMANOID.mat(Color(0.12, 0.02, 0.02), 0.0, 0.2, 0.3)
		for i in 5:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.07
			cone.height = 0.45 - i * 0.04
			var sp := MeshInstance3D.new()
			sp.mesh = cone
			sp.material_override = spike_mat
			sp.position = Vector3((i % 2) * 0.12 - 0.06, 0.66 - i * 0.16, 0.19)
			sp.rotation.x = 0.9
			model.torso.add_child(sp)
			model.all_meshes.append(sp)
		for side in [-1.0, 1.0]:
			var claw := MeshInstance3D.new()
			claw.mesh = HUMANOID.box(Vector3(0.03, 0.45, 0.06))
			claw.material_override = spike_mat
			claw.position = Vector3(0, -0.2, -0.05)
			(model.hand_l if side < 0 else model.hand_r).add_child(claw)
			model.all_meshes.append(claw)
	if k == "commander":
		label = "Colonel %s" % LAST_NAMES[randi() % LAST_NAMES.size()]
		memory = "Memory absorbed: artillery codes. Disguised as a soldier, you can now call in strikes (unlock in Skills)."
	if k == "patient_zero":
		var blue: Material = HUMANOID.mat(Color(0.3, 0.75, 1.0), 2.5)
		for hand in [model.hand_l, model.hand_r]:
			for i in 3:
				var claw := MeshInstance3D.new()
				claw.mesh = HUMANOID.box(Vector3(0.02, 0.55, 0.05))
				claw.material_override = blue
				claw.position = Vector3((i - 1) * 0.05, -0.27, -0.03)
				claw.rotation = Vector3(0.18, 0, (i - 1) * 0.12)
				hand.add_child(claw)
				model.all_meshes.append(claw)
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
	if k == "hunter" or k == "leviathan":
		add_to_group("hunters")
	patrol_center = global_position
	_think_timer = randf() * 0.4
	_strafe = 1.0 if randf() < 0.5 else -1.0
	match faction:
		"civilian": state = S.WANDER
		"military": state = S.PATROL
		"infected": state = S.WANDER
	refresh_tint()


static var _sense_mats := {}


## The overlay a person shows when not flashing from a hit: ally brand, Predator Sense
## outline (seen through walls) or thermal glow.
func refresh_tint() -> void:
	if model == null or has_meta("flashing"):
		return
	var pw: PlayerPowers = Game.player.powers if Game.player else null
	var m: Material = null
	if is_ally:
		m = _brand_mat
	elif pw and pw.vision == PlayerPowers.Vision.PREDATOR and is_alive():
		var col := Color(0.4, 0.8, 1.0, 0.18)
		if faction == "military":
			col = Color(1.0, 0.15, 0.1, 0.55)
		elif faction == "infected":
			col = Color(1.0, 0.55, 0.05, 0.5)
		if memory != "" or boss_name != "" or event_tag != "":
			col = Color(1.0, 0.85, 0.2, 0.7)
		var key := col.to_html()
		if not _sense_mats.has(key):
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.no_depth_test = true
			sm.albedo_color = col
			sm.render_priority = 10
			_sense_mats[key] = sm
		m = _sense_mats[key]
	model._thermal_on = false
	model.set_tint(m)
	if pw and pw.thermal_on and m == null:
		model.set_thermal(true)


func _make_outfit(k: String) -> Dictionary:
	var skins := [Color(0.85, 0.68, 0.55), Color(0.62, 0.45, 0.33), Color(0.42, 0.29, 0.2), Color(0.95, 0.8, 0.68),
		Color(0.3, 0.2, 0.14), Color(0.76, 0.6, 0.47), Color(0.55, 0.38, 0.27)]
	var skin: Color = skins[randi() % skins.size()]
	var hair_cols := [Color(0.06, 0.05, 0.04), Color(0.18, 0.11, 0.06), Color(0.32, 0.2, 0.1), Color(0.6, 0.45, 0.25),
		Color(0.5, 0.18, 0.08), Color(0.55, 0.55, 0.55), Color(0.1, 0.08, 0.07)]
	var hair_col: Color = hair_cols[randi() % hair_cols.size()]
	var r := randf()
	var body := "f" if r < 0.42 else ("h" if r < 0.55 else "m")
	var hair := _pick(["short", "short", "buzz", "bald", "curly"]) if body != "f" else _pick(["long", "long", "bun", "ponytail", "curly", "short"])
	var person := {"skin": skin, "body": body, "hair": hair, "hair_color": hair_col,
		"beard": body != "f" and randf() < 0.3, "glasses": randf() < 0.12}
	match k:
		"grenadier":
			# soldier kit with a tan vest full of grenades
			person.merge({"shirt": Color(0.36, 0.33, 0.24), "pants": Color(0.3, 0.28, 0.2), "gear": "helmet",
				"gear_color": Color(0.32, 0.3, 0.2), "item": "rifle", "top": "long", "vest": true,
				"vest_color": Color(0.45, 0.38, 0.22), "gloves": true, "boots": true, "belt": true,
				"shoes": Color(0.12, 0.1, 0.08), "body": "m", "beard": false, "glasses": false}, true)
			return person
		"heavy_gunner":
			# big, armoured, slow: a dark heavy vest and a bulky frame
			person.merge({"shirt": Color(0.2, 0.22, 0.17), "pants": Color(0.18, 0.2, 0.15), "gear": "helmet",
				"gear_color": Color(0.14, 0.15, 0.12), "item": "rifle", "top": "long", "vest": true,
				"vest_color": Color(0.1, 0.11, 0.09), "gloves": true, "boots": true, "belt": true, "bulk": 1.35,
				"shoes": Color(0.1, 0.09, 0.07), "body": "m", "beard": randf() < 0.4, "glasses": false}, true)
			return person
		"soldier", "rocket_soldier":
			person.merge({"shirt": Color(0.3, 0.33, 0.22), "pants": Color(0.27, 0.29, 0.2), "gear": "helmet",
				"gear_color": Color(0.24, 0.28, 0.19), "item": "rifle" if k == "soldier" else "launcher",
				"top": "long", "camo": true, "vest": true, "vest_color": Color(0.2, 0.23, 0.15), "gloves": true,
				"boots": true, "belt": true, "shoes": Color(0.12, 0.1, 0.08), "body": "f" if randf() < 0.2 else "m",
				"beard": false, "glasses": false}, true)
			return person
		"elite":
			person.merge({"shirt": Color(0.07, 0.07, 0.08), "pants": Color(0.09, 0.09, 0.1), "gear": "helmet",
				"gear_color": Color(0.1, 0.1, 0.11), "item": "rifle", "glow": Color(0.2, 0.6, 1.0), "glow_style": "tech",
				"top": "long", "vest": true, "vest_color": Color(0.13, 0.13, 0.15), "gloves": true, "boots": true,
				"belt": true, "body": "m", "beard": false, "glasses": false}, true)
			return person
		"commander":
			person.merge({"shirt": Color(0.22, 0.25, 0.17), "pants": Color(0.18, 0.2, 0.14), "gear": "officer",
				"gear_color": Color(0.2, 0.22, 0.15), "item": "rifle", "glow": Color(1, 0.8, 0.2), "glow_style": "medals",
				"top": "long", "boots": true, "belt": true, "gloves": true, "body": "m", "hair": "short",
				"hair_color": Color(0.5, 0.5, 0.5), "glasses": false}, true)
			return person
		"scientist":
			var shirts := [Color(0.62, 0.72, 0.85), Color(0.85, 0.85, 0.82), Color(0.55, 0.62, 0.55), Color(0.8, 0.7, 0.75)]
			person.merge({"shirt": shirts[randi() % shirts.size()], "pants": Color(0.25, 0.27, 0.3), "gear": "none",
				"top": "long", "coat": true, "coat_color": Color(0.93, 0.94, 0.95), "glasses": randf() < 0.6,
				"badge": true, "belt": true, "shoes": Color(0.15, 0.1, 0.07)}, true)
			return person
		"infected":
			var rag: Color = Color(randf_range(0.15, 0.35), randf_range(0.12, 0.3), randf_range(0.1, 0.25))
			person.merge({"shirt": rag, "pants": rag.darkened(0.3), "skin": Color(0.45, 0.48, 0.38),
				"glow": Color(0.9, 0.12, 0.05), "glow_style": "veins", "infected": true, "top": _pick(["tshirt", "long", "tank"]),
				"glasses": false, "gear": "none"}, true)
			return person
		"hunter":
			return {"shirt": Color(0.3, 0.08, 0.07), "pants": Color(0.22, 0.06, 0.05), "skin": Color(0.35, 0.1, 0.09),
				"glow": Color(1, 0.15, 0.05), "bulk": 1.5, "infected": true, "top": "tank", "veins": true, "hair": "bald", "body": "m"}
		"leviathan":
			return {"shirt": Color(0.12, 0.03, 0.03), "pants": Color(0.1, 0.02, 0.02), "skin": Color(0.2, 0.04, 0.04),
				"glow": Color(1, 0.35, 0.05), "bulk": 1.9, "infected": true, "top": "tank", "veins": true, "hair": "bald", "body": "h"}
		"patient_zero":
			return {"shirt": Color(0.85, 0.86, 0.88), "pants": Color(0.2, 0.21, 0.24), "skin": Color(0.7, 0.72, 0.75),
				"gear": "hood", "gear_color": Color(0.9, 0.9, 0.92), "glow": Color(0.2, 0.7, 1.0), "coat": true,
				"coat_color": Color(0.88, 0.89, 0.91), "veins": true, "top": "long", "boots": true}
		_:
			var shirts := [Color(0.7, 0.2, 0.2), Color(0.2, 0.35, 0.6), Color(0.85, 0.8, 0.7), Color(0.25, 0.25, 0.28),
				Color(0.55, 0.45, 0.2), Color(0.3, 0.5, 0.35), Color(0.6, 0.3, 0.5), Color(0.9, 0.55, 0.2),
				Color(0.12, 0.13, 0.16), Color(0.75, 0.75, 0.78), Color(0.35, 0.22, 0.15)]
			var pants := [Color(0.15, 0.17, 0.25), Color(0.3, 0.28, 0.25), Color(0.1, 0.1, 0.1), Color(0.45, 0.4, 0.32),
				Color(0.22, 0.3, 0.45), Color(0.5, 0.48, 0.45)]
			var shoes := [Color(0.08, 0.07, 0.07), Color(0.85, 0.85, 0.85), Color(0.3, 0.18, 0.1), Color(0.15, 0.2, 0.35)]
			var leg := "pants"
			if body == "f" and randf() < 0.3:
				leg = "skirt"
			elif randf() < 0.15:
				leg = "shorts"
			person.merge({"shirt": shirts[randi() % shirts.size()], "pants": pants[randi() % pants.size()],
				"shoes": shoes[randi() % shoes.size()], "accent": shirts[randi() % shirts.size()],
				"top": _pick(["tshirt", "tshirt", "long", "jacket", "hoodie", "tank"]), "legwear": leg,
				"gear": "cap" if randf() < 0.15 else "none", "gear_color": shirts[randi() % shirts.size()],
				"belt": randf() < 0.3}, true)
			return person


func _pick(options: Array) -> String:
	return str(options[randi() % options.size()])


# ------------------------------------------------------------------ public API

func is_alive() -> bool:
	return state != S.DEAD and state != S.CONSUMED and hp > 0.0


func can_see_point(p: Vector3) -> bool:
	return Game.line_of_sight(global_position + Vector3.UP * 0.7 * scale_factor, p)


func can_be_grabbed() -> bool:
	if state in [S.GRABBED, S.CONSUMED] or is_ally:
		return false
	if kind == "hunter":
		return hp < max_hp * 0.3 and state != S.DEAD
	if kind == "leviathan" or kind == "patient_zero":
		return false
	return true


func can_be_consumed() -> bool:
	if state == S.CONSUMED or state == S.GRABBED and _grabbed_by != Game.player:
		return false
	if state == S.DEAD:
		return _dead_time < 8.0 and kind != "hunter" and kind != "leviathan"
	if kind == "hunter":
		return hp < max_hp * 0.3
	if kind == "leviathan" or kind == "patient_zero":
		return hp < max_hp * 0.08
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
	if is_ally and (src == Game.player or (src != null and is_instance_valid(src) and (src.get("is_ally") == true or src.is_in_group("decoys")))):
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
	if src == Game.player and dmg > 1.0:
		Game.register_hit()
		Game.fx.damage_number(global_position, dmg, dmg >= 50.0)
	elif src != null and is_instance_valid(src) and src.get("is_ally") == true and dmg > 1.0:
		Game.fx.damage_number(global_position, dmg, false)
	if src != null and is_instance_valid(src):
		if src == Game.player or src.is_in_group("decoys") or (src.has_method("is_player_controlled") and src.is_player_controlled()):
			_on_attacked_by_player()
		elif src is Node3D and faction != "civilian":
			var s3 := src as Node3D
			if s3.is_in_group("npcs") and s3.get("faction") != faction:
				_target = s3
		if src.is_in_group("infected") and faction == "civilian":
			_infected_killer = true
	var launch_threshold := 30.0 if kind == "hunter" else (999.0 if kind in ["leviathan", "patient_zero"] else 7.0)
	if kind in ["leviathan", "patient_zero"] and info["kind"] == "bullet":
		hp += dmg * 0.5
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
		get_tree().create_timer(0.3, false).timeout.connect(_end_exception.bind(by))
	velocity = vel
	_thrower = by
	_airborne_time = 0.0
	state = S.LAUNCHED if hp > 0.0 else S.DEAD
	global_basis = Basis()


func _end_exception(by) -> void:
	if is_instance_valid(by):
		remove_collision_exception_with(by)


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
	var info := {"kind": kind, "outfit": outfit, "label": label, "memory": memory, "tag": event_tag,
		"memory_flag": str(get_meta("memory_flag", ""))}
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
	var by_ally: bool = src != null and is_instance_valid(src) and src.get("is_ally") == true
	var by_player: bool = src == Game.player or by_ally or (src != null and is_instance_valid(src) and src.has_method("is_player_controlled") and src.is_player_controlled())
	if is_ally:
		by_player = false
		Game.feed("Your ally %s fell" % label.replace("a ", "").replace("an ", ""), Color(1, 0.5, 0.4))
		remove_from_group("allies")
	if by_player:
		match faction:
			"military":
				Game.kills["military"] += 1
				Game.add_heat(0.18)
				Game.add_xp(int(KINDS[kind].get("xp", 30 if kind == "elite" else (14 if kind == "rocket_soldier" else 12))))
			"infected":
				Game.kills["infected"] += 1
				Game.add_xp(150 if kind == "hunter" else (900 if kind == "leviathan" else (2000 if kind == "patient_zero" else 5)))
				if kind == "patient_zero":
					Game.stat_add("patient_zero")
				if kind == "leviathan":
					Game.say("THE LEVIATHAN IS DEAD", Color(1, 0.85, 0.3))
					Game.stat_add("leviathan")
				if kind == "hunter":
					Game.feed("Hunter killed", Color(0.7, 1, 0.6))
			"civilian":
				Game.kills["civilian"] += 1
	Game.fx.splat(global_position + Vector3.UP * 0.4, Vector3.UP, Color(0.5, 0.02, 0.02) if faction != "infected" else Color(0.35, 0.05, 0.03), 18)
	if kind in Game.SOLDIER_KINDS and randf() < 0.4:
		_drop_weapon()
	if kind == "hunter" or kind == "leviathan":
		Game.fx.sound("roar", global_position, 2.0 if kind == "hunter" else 8.0, 0.3)
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
	p.setup(weapon, PlayerPowers.WEAPONS[weapon]["drop"])
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

var _roof_time := 0.0


## People who end up stranded on a rooftop (thrown, blasted, knocked off a
## building edge) get cleaned up once you're not around to see it.
func _check_stranded(delta: float) -> void:
	if global_position.y < 3.0 or global_position.y < -50.0 or is_ally or kind in ["hunter", "leviathan", "patient_zero"] \
			or event_tag != "" or not is_on_floor():
		_roof_time = 0.0
		return
	_roof_time += delta
	if _roof_time > 4.0 and Game.player and global_position.distance_to(Game.player.global_position) > 45.0:
		queue_free()


func _physics_process(delta: float) -> void:
	_check_stranded(delta)
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
	var limit := 30.0 if Game.npc_count < 90 else 10.0
	if _dead_time > limit or Game.fell_out(global_position):
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
	if Game.fell_out(global_position):
		queue_free()


# ------------------------------------------------------------------ thinking

func _think() -> void:
	match faction:
		"civilian": _think_civilian()
		"military": _think_military()
		"infected": _think_infected()
		"ally": _think_ally()


# ------------------------------------------------------------------ allies (Dominate power)

## Can the player brand this person as an ally?
func can_be_branded() -> bool:
	if is_ally or state in [S.DEAD, S.CONSUMED] or hp <= 0.0:
		return false
	return not kind in ["leviathan", "patient_zero", "commander"]


func make_ally() -> void:
	is_ally = true
	for g in ["civilians", "military", "infected", "hunters"]:
		remove_from_group(g)
	faction = "ally"
	add_to_group("allies")
	event_tag = ""
	in_base = false
	hp = max_hp
	_target = null
	state = S.FOLLOW
	_path_target = Vector3.INF
	if kind == "civilian" or kind == "scientist":
		# a branded civilian becomes a brawler
		walk_speed = 3.0
		run_speed = 8.0
		max_hp = 80.0
		hp = max_hp
	if _brand_mat == null:
		_brand_mat = StandardMaterial3D.new()
		_brand_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_brand_mat.albedo_color = Color(1, 0.1, 0.05, 0.22)
		_brand_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	model.set_tint(_brand_mat)
	# glowing brand ring floating over the head
	_brand_mark = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.17
	t.outer_radius = 0.23
	t.rings = 16
	t.ring_segments = 6
	_brand_mark.mesh = t
	_brand_mark.material_override = HUMANOID.mat(Color(1, 0.12, 0.06), 4.0)
	_brand_mark.position = Vector3(0, 1.15, 0)
	model.add_child(_brand_mark)


func _think_ally() -> void:
	var p := Game.player
	if p == null:
		return
	var me := global_position
	var ppos: Vector3 = p.global_position
	var dist_p := Vector2(me.x - ppos.x, me.z - ppos.z).length()
	# can't follow up walls: catch up when the player is far away
	_ally_teleport_cd -= 0.3
	_ally_far_time = _ally_far_time + 0.3 if dist_p > 30.0 else 0.0
	if (dist_p > 85.0 or _ally_far_time > 4.0) and _ally_teleport_cd <= 0.0 and not p.is_dead():
		_ally_far_time = 0.0
		_ally_teleport_cd = 4.0
		var spot: Vector3 = Game.interiors.random_floor_point() if Game.interiors and Game.interiors.is_inside() \
			else Game.city.random_sidewalk_point(ppos, 10.0, 22.0)
		global_position = spot + Vector3.UP * 0.6
		reset_physics_interpolation()
		Game.fx.burst_ring(spot, Color(1, 0.15, 0.08, 0.6), 2.0)
		_path_target = Vector3.INF
		return
	# pick a fight: infected always, the military when they're hunting you
	var best: Node3D = null
	var best_d := 35.0
	var groups := ["infected"]
	if Game.alert_level != Game.Alert.HIDDEN:
		groups.append("military")
	for g in groups:
		var n := Game.nearest_in_group(g, me, best_d)
		if n and n.global_position.distance_to(ppos) < 55.0:
			var d := me.distance_to(n.global_position)
			if d < best_d and (d < 10.0 or can_see_point(n.global_position + Vector3.UP * 0.5)):
				best = n
				best_d = d
	if _target and is_instance_valid(_target) and _target.has_method("is_alive") and _target.is_alive() \
			and me.distance_to(_target.global_position) < 40.0 and best == null:
		best = _target
	_target = best
	if _target:
		if KINDS[kind].has("weapon"):
			if state != S.ENGAGE:
				state = S.ENGAGE
				_burst_timer = randf_range(0.2, 0.6)
		else:
			state = S.CHASE
		return
	state = S.FOLLOW


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
			_move_goal = patrol_points.pick_random() if not patrol_points.is_empty() else Game.city.random_sidewalk_point(global_position, 10.0, 45.0)
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
		var sight := 85.0
		var wx: Node = Game.get_meta("weather", null)
		if wx and wx.is_bad_weather() and kind != "elite":
			sight = 45.0
		if d < sight and can_see_point(pp + Vector3.UP * 0.3):
			sees_player = true
			_last_seen_player = 0.0
			var violent: bool = p.powers.violence_timer > 0.0 or (p.vehicle != null and p.conspicuous_timer > 0.0)
			if violent and d < 60.0 and p.vehicle == null:
				Game.raise_alert(pp, "The military saw you attack")
			elif violent and p.vehicle != null and d < 70.0:
				Game.raise_alert(pp, "They spotted the hijacked vehicle")
			if p.vehicle == null:
				var trespass: bool = Game.is_trespassing(pp)
				Game.report_sighting(pp, p.is_conspicuous() or trespass, me, 0.3, thermal)
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
	if Game.alert_level != Game.Alert.HIDDEN:
		var al := Game.nearest_in_group("allies", me, 50.0)
		if al and me.distance_to(al.global_position) * 0.9 < best and can_see_point(al.global_position + Vector3.UP * 0.5):
			new_target = al
			best = me.distance_to(al.global_position) * 0.9
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
	if Game.alert_level != Game.Alert.HIDDEN and me.distance_to(Game.last_known_pos) < (90.0 if in_base else 220.0):
		if state != S.SEARCH or _search_point == Vector3.INF:
			state = S.SEARCH
			var lk := Game.last_known_pos
			_search_point = Vector3(lk.x + randf_range(-14, 14), lk.y, lk.z + randf_range(-14, 14))
			_path_target = Vector3.INF
		elif me.distance_to(_search_point) < 3.0:
			var lk2 := Game.last_known_pos
			_search_point = Vector3(lk2.x + randf_range(-20, 20), lk2.y, lk2.z + randf_range(-20, 20))
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
			if not patrol_points.is_empty():
				_move_goal = patrol_points.pick_random()
			else:
				_move_goal = Game.city.random_base_point() if in_base else Game.city.random_street_point(patrol_center, 5.0, 35.0)
			_path_target = Vector3.INF


func _think_infected() -> void:
	var me := global_position
	var best: Node3D = null
	var hunterish := kind in ["hunter", "leviathan", "patient_zero"]
	var best_d := 34.0 if not hunterish else 70.0
	var p := Game.player
	if p and not p.is_dead() and p.vehicle == null:
		var d := me.distance_to(p.global_position)
		if d < best_d and (d < 12.0 or can_see_point(p.global_position)):
			best = p
			best_d = d * (0.6 if hunterish else 1.0)
	for g in ["civilians", "military", "decoys", "allies"]:
		var n := Game.nearest_in_group(g, me, best_d)
		if n:
			var d := me.distance_to(n.global_position)
			if d < best_d:
				best = n
				best_d = d
	if (kind == "leviathan" or kind == "patient_zero") and p and not p.is_dead():
		best = p
	if best == null and hunterish and p and not p.is_dead():
		# hunters always hunt the player when a hunter event is running
		if me.distance_to(p.global_position) < 160.0:
			best = p
	if best != null and best != _target and hunterish and _scream_cooldown <= 0.0:
		Game.fx.sound("roar", me, 0.0, 0.2)
		_scream_cooldown = 8.0
	_target = best
	if _target:
		state = S.CHASE
	elif state == S.CHASE or (state == S.WANDER and (_path_target == Vector3.INF or me.distance_to(_move_goal) < 2.0)):
		state = S.WANDER
		_move_goal = patrol_points.pick_random() if not patrol_points.is_empty() else Game.city.random_street_point(patrol_center, 3.0, 25.0)
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
		S.FOLLOW:
			var p := Game.player
			if p == null:
				_stop(delta)
				return
			var slot := float(get_instance_id() % 8) / 8.0 * TAU
			var goal: Vector3 = p.global_position + Vector3(cos(slot), 0, sin(slot)) * 4.5
			goal.y = global_position.y
			var d := Vector2(goal.x - global_position.x, goal.z - global_position.z).length()
			if d > 3.0:
				# branded allies sprint hard to keep up with you
				_go(goal, run_speed * (1.7 if d > 20.0 else 1.0) if d > 10.0 else walk_speed * 1.6, delta)
			else:
				_stop(delta)


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
		state = S.FOLLOW if is_ally else S.PATROL
		_path_target = Vector3.INF
		return
	var tpos := _player_target_pos() if _target == Game.player else _target.global_position
	var to := tpos - global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	# rockets and grenades keep their distance; heavy gunners wade in
	var ideal_min := 10.0
	var ideal_max := 28.0
	match kind:
		"rocket_soldier": ideal_min = 20.0; ideal_max = 40.0
		"grenadier": ideal_min = 16.0; ideal_max = 34.0
		"heavy_gunner": ideal_min = 6.0; ideal_max = 20.0
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
	if kind == "grenadier":
		_lob_grenade(tpos)
		_burst_timer = randf_range(2.6, 4.0)
		return
	var heavy := kind == "heavy_gunner"
	if _burst_left <= 0:
		_burst_left = randi_range(10, 16) if heavy else randi_range(3, 5)
	_fire_bullet(tpos, dist)
	_burst_left -= 1
	if heavy:
		_burst_timer = 0.07 if _burst_left > 0 else randf_range(1.6, 2.4)
	else:
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
			var is_friend: bool = c.is_in_group("military") if not is_ally else (c == Game.player or c.is_in_group("allies"))
			if not is_friend:
				var dmg := 5.0 if kind == "elite" else (4.0 if kind == "heavy_gunner" else 3.2)
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


## An arcing grenade that lands near the target (a bit short or long, so you can dodge it).
func _lob_grenade(tpos: Vector3) -> void:
	var muzzle := global_position + Vector3.UP * 0.8 + _face_dir * 0.6
	var land := tpos + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
	var p := Node3D.new()
	p.set_script(PROJECTILE)
	get_parent().add_child(p)
	p.launch(muzzle, PROJECTILE.lob_velocity(muzzle, land, 1.1), self, "grenade")
	Game.fx.sound("whoosh", muzzle, -4.0)
	model.swing(true, 4, 0.2)
	Game.panic_at(global_position, 26.0)


func _act_chase(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or (_target.has_method("is_alive") and not _target.is_alive()) \
			or (_target == Game.player and Game.player.is_dead()):
		_target = null
		state = S.FOLLOW if is_ally else S.WANDER
		_path_target = Vector3.INF
		return
	var tpos := _target.global_position
	var to := tpos - global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	_face_dir = flat.normalized() if dist > 0.01 else _face_dir
	var reach := 1.7 * scale_factor
	if kind == "leviathan":
		_boss_moves(delta, dist)
	elif kind == "patient_zero":
		if _pz_moves(delta, dist, tpos):
			return
	if kind in ["hunter", "leviathan", "patient_zero"] and _leap_cooldown <= 0.0 and is_on_floor():
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
	if kind == "leviathan":
		_attack_cooldown = 1.6
	model.swing(randf() < 0.5, 1 if kind != "infected" else 0, 0.3)
	var dmg := 8.0
	var force := _face_dir * 3.0
	if kind == "hunter":
		dmg = 22.0
		force = _face_dir * 18.0 + Vector3.UP * 6.0
	elif kind == "leviathan":
		dmg = 40.0
		force = _face_dir * 30.0 + Vector3.UP * 12.0
	elif kind == "patient_zero":
		dmg = 20.0
		force = _face_dir * 20.0 + Vector3.UP * 6.0
		_attack_cooldown = 0.9
	get_tree().create_timer(0.15, false).timeout.connect(_melee_hit.bind(t, dmg, force))


func _melee_hit(t, dmg: float, force: Vector3) -> void:
	if is_instance_valid(t) and is_alive() and t.global_position.distance_to(global_position) < 2.6 * scale_factor:
		t.take_hit(Game.hit_info(dmg, force, self, "melee"))
		Game.fx.splat(t.global_position + Vector3.UP * 0.4, _face_dir, Color(0.5, 0.02, 0.02), 6)
		Game.fx.sound("punch" if kind == "infected" else "slash", t.global_position, -4.0)


func _boss_moves(delta: float, dist: float) -> void:
	_pound_cooldown -= delta
	_adds_cooldown -= delta
	var enraged := hp < max_hp * 0.4
	if enraged and run_speed < 16.0:
		run_speed = 16.0
		Game.say("THE LEVIATHAN IS ENRAGED", Color(1, 0.3, 0.2))
	if _pound_cooldown <= 0.0 and dist < 16.0 and is_on_floor():
		_pound_cooldown = 4.0 if enraged else 7.0
		model.swing(true, 2, 0.5)
		model.swing(false, 2, 0.5)
		Game.fx.sound("roar", global_position, 4.0, 0.1)
		get_tree().create_timer(0.55, false).timeout.connect(_pound_impact)
	if _adds_cooldown <= 0.0:
		_spawn_brood(enraged)


## Patient Zero: dashes, tendril volleys, spike rings and phases. Returns true while dashing.
func _pz_moves(delta: float, dist: float, tpos: Vector3) -> bool:
	_dash_cooldown -= delta
	_volley_cooldown -= delta
	_pound_cooldown -= delta
	var ratio := hp / max_hp
	if _pz_phase == 0 and ratio < 0.5:
		_pz_phase = 1
		Game.say("PATIENT ZERO EVOLVES", Color(0.4, 0.8, 1))
		for k in 2:
			var n := CharacterBody3D.new()
			n.set_script(load("res://scripts/npc.gd"))
			get_parent().add_child(n)
			n.global_position = global_position + Vector3(randf_range(-8, 8), 1.0, randf_range(-8, 8))
			n.setup("hunter", {"tag": event_tag})
	if _pz_phase == 1 and ratio < 0.25:
		_pz_phase = 2
		run_speed = 26.0
		Game.say("PATIENT ZERO IS DESPERATE", Color(0.4, 0.8, 1))
	if _dash_time > 0.0:
		_dash_time -= delta
		if _dash_time <= 0.0 or dist < 2.0:
			_dash_time = 0.0
			velocity.x *= 0.2
			velocity.z *= 0.2
			Game.damage_area(global_position, 3.5, 22.0, 18.0, self, "slash", Game.LAYER_PLAYER | Game.LAYER_PROPS)
			Game.fx.tendril_flash(global_position, global_position + _face_dir * 4.0, 0.2, 0.15)
		return true
	if _dash_cooldown <= 0.0 and dist > 6.0 and dist < 34.0 and is_on_floor():
		_dash_cooldown = randf_range(2.5, 4.5) / (1.0 + _pz_phase * 0.4)
		var d := (tpos - global_position)
		d.y = 0
		velocity = d.normalized() * 48.0
		_dash_time = minf(d.length() / 48.0, 0.6)
		Game.fx.sound("dash", global_position, 2.0)
		Game.fx.burst_ring(global_position, Color(0.3, 0.7, 1.0, 0.7), 2.5)
		return true
	if _volley_cooldown <= 0.0 and dist < 45.0 and can_see_point(tpos):
		_volley_cooldown = 7.0 - _pz_phase * 1.5
		_tendril_volley(tpos)
	if _pound_cooldown <= 0.0 and dist < 12.0:
		_pound_cooldown = 9.0 - _pz_phase * 2.0
		var feet := global_position + Vector3.DOWN * 0.9 * scale_factor
		for ring in 3:
			for k in 12:
				var a := k * TAU / 12.0 + ring * 0.25
				Game.fx.spike(feet + Vector3(cos(a), 0, sin(a)) * (3.0 + ring * 3.5), 3.5, ring * 0.08, 0.6)
		get_tree().create_timer(0.15, false).timeout.connect(_pz_spike_damage.bind(feet))
	return false


func _pz_spike_damage(feet: Vector3) -> void:
	if is_alive():
		Game.damage_area(feet + Vector3.UP, 12.0, 32.0, 22.0, self, "slash", Game.LAYER_PLAYER | Game.LAYER_PROPS | Game.LAYER_NPC, 1.5)


func _tendril_volley(at: Vector3) -> void:
	# telegraph: blue markers, then tendrils strike where you were standing
	for k in 4:
		var p := at + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		Game.fx.burst_ring(p + Vector3.DOWN * 0.8, Color(0.3, 0.7, 1.0, 0.8), 2.0)
		get_tree().create_timer(0.7, false).timeout.connect(_volley_strike.bind(p))
	Game.fx.sound("tendril", global_position, 2.0)


func _volley_strike(p: Vector3) -> void:
	if not is_alive():
		return
	Game.fx.tendril_flash(global_position + Vector3.UP * 1.2, p, 0.3, 0.18)
	Game.damage_area(p, 2.4, 18.0, 12.0, self, "slash", Game.LAYER_PLAYER | Game.LAYER_PROPS | Game.LAYER_NPC)


func _pound_impact() -> void:
	if not is_alive():
		return
	var feet := global_position + Vector3.DOWN * 0.9 * scale_factor
	Game.damage_area(feet + Vector3.UP, 14.0, 45.0, 26.0, self, "slam", Game.LAYER_PLAYER | Game.LAYER_PROPS | Game.LAYER_NPC)
	Game.fx.shockwave(feet, 16.0, Color(1, 0.3, 0.15, 0.8), 0.5)
	Game.fx.debris(feet, 24)
	Game.fx.sound("land", feet, 8.0)
	for k in 10:
		var a := k * TAU / 10.0
		Game.fx.spike(feet + Vector3(cos(a), 0, sin(a)) * 9.0, 5.0, 0.05, 0.6)
	if Game.player:
		Game.player.add_trauma(clampf(1.0 - Game.player.global_position.distance_to(feet) / 40.0, 0.0, 0.8))


func _spawn_brood(enraged: bool) -> void:
	_adds_cooldown = 18.0
	for k in 4:
		var n := CharacterBody3D.new()
		n.set_script(load("res://scripts/npc.gd"))
		get_parent().add_child(n)
		var a := randf() * TAU
		n.global_position = global_position + Vector3(cos(a), 0, sin(a)) * 6.0 + Vector3.UP * 0.5
		n.setup("hunter" if k == 0 and enraged else "infected", {"tag": event_tag})
	Game.feed("The Leviathan calls its brood", Color(1, 0.4, 0.2))


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
	Game.fx.shockwave(global_position + Vector3.DOWN * 0.85 * scale_factor, 5.0 * scale_factor * 0.6, Color(0.8, 0.3, 0.2, 0.6), 0.3)
	Game.fx.sound("land", global_position, 0.0)
	var p := Game.player
	for n in get_tree().get_nodes_in_group("npcs") + [p]:
		var o := n as Node3D
		if o == null or o == self or not is_instance_valid(o) or (o.is_in_group("infected")):
			continue
		if o.global_position.distance_to(global_position) < 2.6 * scale_factor:
			var dir := (o.global_position - global_position).normalized()
			o.take_hit(Game.hit_info(25.0 * (scale_factor / 1.7), dir * 16.0 + Vector3.UP * 8.0, self, "melee"))


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
		refresh_tint()
