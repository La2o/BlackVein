class_name PlayerPowers
extends Node
## Combat and powers for the player:
## arm forms (fists, claws, hammerfist, blade, whipfist, musclemass),
## shield and armor, thermal vision, grab and throw, consume and disguise,
## devastators, picked-up guns, vehicle hijacking, and three original powers:
## Tether (zip / yank), Focus (slow motion) and Biomass Decoy.

enum Form { FISTS, CLAWS, HAMMER, BLADE, WHIP, MUSCLE }
enum Defense { NONE, SHIELD, ARMOR }

const FORM_NAMES := ["Fists", "Claws", "Hammerfist", "Blade", "Whipfist", "Musclemass"]
const DEFENSE_NAMES := ["None", "Shield", "Armor"]
const FORM_SKILLS := ["", "claws", "hammer", "blade", "whip", "muscle_form"]
const DEFENSE_SKILLS := ["", "shield", "armor"]
const SPECIAL_NAMES := ["Uppercut", "Spike Line", "Ground Slam", "Whirlwind", "Whip Grab", "Thunderclap"]
const FORMS := {
	Form.FISTS: {"damage": 12.0, "range": 2.4, "arc": 75.0, "interval": 0.3, "combo": 3, "knock": 6.0, "finisher": 16.0, "vehicle": 0.6, "styles": [0, 0, 3], "sound": "punch", "kind": "melee"},
	Form.CLAWS: {"damage": 17.0, "range": 2.9, "arc": 110.0, "interval": 0.19, "combo": 4, "knock": 4.0, "finisher": 12.0, "vehicle": 0.9, "styles": [1, 1, 1, 2], "sound": "slash", "kind": "slash"},
	Form.HAMMER: {"damage": 46.0, "range": 3.2, "arc": 90.0, "interval": 0.6, "combo": 2, "knock": 18.0, "finisher": 26.0, "vehicle": 2.4, "styles": [2, 2], "sound": "heavy", "kind": "slam"},
	Form.BLADE: {"damage": 52.0, "range": 3.9, "arc": 140.0, "interval": 0.42, "combo": 3, "knock": 9.0, "finisher": 18.0, "vehicle": 3.0, "styles": [1, 1, 2], "sound": "slash", "kind": "blade"},
	Form.WHIP: {"damage": 30.0, "range": 17.0, "arc": 18.0, "interval": 0.5, "combo": 2, "knock": 12.0, "finisher": 22.0, "vehicle": 1.2, "styles": [1, 1], "sound": "slash", "kind": "slash"},
	Form.MUSCLE: {"damage": 28.0, "range": 2.6, "arc": 85.0, "interval": 0.38, "combo": 3, "knock": 26.0, "finisher": 42.0, "vehicle": 1.5, "styles": [0, 0, 3], "sound": "heavy", "kind": "melee"},
}
const DECOY_SCRIPT := preload("res://scripts/decoy.gd")
const PROJECTILE_SCRIPT := preload("res://scripts/projectile.gd")

var player: Player
var form: int = Form.FISTS
var defense: int = Defense.NONE
var thermal_on := false
var focus_on := false
var combo_index := 0
var combo_reset := 0.0
var attack_cooldown := 0.0
var attack_buffer := 0.0
var special_cooldown := 0.0
var tether_cooldown := 0.0
var decoy_cooldown := 0.0
var devastator_cooldown := 0.0
var violence_timer := 0.0
var held: Node3D = null
var held_kind := ""
var weapon := ""
var ammo := 0
var fire_cooldown := 0.0
var consuming: Node3D = null
var consume_timer := 0.0
var consume_lines: Array[MeshInstance3D] = []
var devastating := ""
var devastate_timer := 0.0
var pending_hijack: Node3D = null
var _right_hand := true


func _ready() -> void:
	player = get_parent() as Player


# ------------------------------------------------------------------ queries used by the player

func can_move() -> bool:
	return consuming == null and devastating == ""


func sprint_allowed() -> bool:
	return true


func speed_factor() -> float:
	var f := 1.0
	if held_kind == "car":
		f *= 0.65
	if defense == Defense.ARMOR:
		f *= 0.85
	if weapon != "":
		f *= 0.85
	return f


func is_transformed() -> bool:
	return form != Form.FISTS or defense != Defense.NONE or held != null or weapon != "" or devastating != ""


func is_armored() -> bool:
	return defense == Defense.ARMOR


func camera_distance_override(d: float) -> float:
	if held_kind == "car":
		return d + 2.5
	if weapon != "" and Input.is_action_pressed("special"):
		return 3.0
	return d


func modify_incoming(dmg: float, info: Dictionary) -> float:
	if devastating != "":
		return 0.0
	var kind: String = info["kind"]
	if defense == Defense.SHIELD:
		var src: Node3D = info["source"] as Node3D
		var front := true
		if src and is_instance_valid(src):
			var to_src := src.global_position - player.global_position
			to_src.y = 0
			front = to_src.length() < 0.1 or player.facing.dot(to_src.normalized()) > 0.2
		if front:
			Game.fx.sound("block", player.global_position, -4.0)
			Game.fx.burst_ring(player.global_position + player.facing * 0.8, Color(1, 0.3, 0.2, 0.6), 1.2)
			match kind:
				"bullet": return dmg * 0.05
				"explosion": return dmg * 0.35
				_: return dmg * 0.2
	if defense == Defense.ARMOR:
		dmg *= 0.45
	if consuming:
		dmg *= 0.6
	return dmg


func on_death() -> void:
	_cancel_consume()
	drop_held()
	_drop_weapon()
	if focus_on:
		_set_focus(false)
	devastating = ""


func on_heavy_landing(feet: Vector3, strength: float, dive: bool) -> void:
	if not dive:
		return
	violence_timer = 3.0
	match form:
		Form.CLAWS:
			for k in 10:
				var a := k * TAU / 10.0
				Game.fx.spike(feet + Vector3(cos(a), 0, sin(a)) * 4.0, 3.0, 0.05)
		Form.HAMMER:
			Game.damage_area(feet, 9.0 * strength + 4.0, 60.0 * player.damage_mult, 24.0, player, "slam", Game.MASK_HITTABLE)
			Game.fx.shockwave(feet, 14.0, Color(1, 0.4, 0.3, 0.7))
		Form.BLADE:
			for k in 12:
				var a := k * TAU / 12.0
				Game.fx.tendril_flash(feet + Vector3.UP * 0.6, feet + Vector3(cos(a), 0.2, sin(a)) * 7.0, 0.3, 0.12)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if player.state in [player.State.PILOT, player.State.DEAD] or get_tree().paused:
		return
	if event.is_action_pressed("form_next"):
		_cycle_form(1)
	elif event.is_action_pressed("form_prev"):
		_cycle_form(-1)
	for k in 6:
		if event.is_action_pressed("form_%d" % (k + 1)):
			set_form(k)


func form_unlocked(f: int) -> bool:
	return f == 0 or Game.has_skill(FORM_SKILLS[f])


func defense_unlocked(d: int) -> bool:
	return d == 0 or Game.has_skill(DEFENSE_SKILLS[d])


func _cycle_form(step: int) -> void:
	var f := form
	for k in FORM_NAMES.size():
		f = (f + step + FORM_NAMES.size()) % FORM_NAMES.size()
		if form_unlocked(f):
			set_form(f)
			return


func set_form(f: int, silent := false) -> void:
	if not form_unlocked(f):
		Game.locked_message(FORM_SKILLS[f])
		return
	if weapon != "":
		_drop_weapon()
	if f == form:
		return
	if silent:
		form = f
		player.model.set_form(f)
		return
	form = f
	player.model.set_form(f)
	combo_index = 0
	Game.fx.sound("consume", player.global_position, -12.0, 0.3)
	Game.fx.burst_ring(player.global_position, Color(0.9, 0.1, 0.05, 0.6), 1.5)
	Game.say(FORM_NAMES[f], Color(1, 0.55, 0.45))


func _physics_process(delta: float) -> void:
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	special_cooldown = maxf(0.0, special_cooldown - delta)
	tether_cooldown = maxf(0.0, tether_cooldown - delta)
	decoy_cooldown = maxf(0.0, decoy_cooldown - delta)
	devastator_cooldown = maxf(0.0, devastator_cooldown - delta)
	violence_timer = maxf(0.0, violence_timer - delta)
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	attack_buffer = maxf(0.0, attack_buffer - delta)
	combo_reset -= delta
	if combo_reset <= 0.0:
		combo_index = 0
	if focus_on:
		var real := delta / maxf(Engine.time_scale, 0.05)
		player.biomass -= 9.0 * real
		if player.biomass <= 0.5:
			player.biomass = 0.0
			_set_focus(false)

	if player.state == player.State.DEAD:
		return
	if player.state == player.State.PILOT:
		if Input.is_action_just_pressed("grab"):
			var v: Node = player.vehicle
			if v and is_instance_valid(v) and v.has_method("on_pilot_exit"):
				v.on_pilot_exit()
			player.exit_vehicle()
		return

	if pending_hijack:
		if not is_instance_valid(pending_hijack) or player.state != player.State.TETHER:
			pending_hijack = null
		else:
			player.tether_point = pending_hijack.global_position
			if pending_hijack.global_position.distance_to(player.global_position) < 7.5 and pending_hijack.can_hijack(player):
				_hijack(pending_hijack)
				pending_hijack = null
				return
	_update_held(delta)
	if consuming:
		_update_consume(delta)
		return
	if devastating != "":
		_update_devastator(delta)
		return

	var mod := Input.is_action_pressed("devastator_mod")
	if Input.is_action_just_pressed("devastator_spikes") or (mod and Input.is_action_just_pressed("attack")):
		if Game.has_skill("groundspike"):
			_start_devastator("spikes")
			return
		Game.locked_message("groundspike")
	if Input.is_action_just_pressed("devastator_tendrils") or (mod and Input.is_action_just_pressed("special")):
		if Game.has_skill("tendrils"):
			_start_devastator("tendrils")
			return
		Game.locked_message("tendrils")
	if Input.is_action_just_pressed("consume"):
		_try_consume()
	if Input.is_action_just_pressed("grab"):
		_grab_pressed()
	if Input.is_action_just_pressed("cycle_defense"):
		_cycle_defense()
	if Input.is_action_just_pressed("thermal"):
		if Game.has_skill("thermal"):
			set_thermal(not thermal_on)
		else:
			Game.locked_message("thermal")
	if Input.is_action_just_pressed("focus"):
		if Game.has_skill("focus"):
			_set_focus(not focus_on)
		else:
			Game.locked_message("focus")
	if Input.is_action_just_pressed("decoy"):
		if Game.has_skill("decoy"):
			_spawn_decoy()
		else:
			Game.locked_message("decoy")
	if Input.is_action_just_pressed("tether"):
		if Game.has_skill("tether"):
			_tether()
		else:
			Game.locked_message("tether")

	if weapon != "":
		_update_weapon()
		return
	if mod:
		return
	if Input.is_action_just_pressed("attack"):
		attack_buffer = 0.25
	if attack_buffer > 0.0 and attack_cooldown <= 0.0:
		attack_buffer = 0.0
		_attack_pressed()
	if Input.is_action_just_pressed("special") and special_cooldown <= 0.0:
		_special()


# ------------------------------------------------------------------ melee

func _aim_flat() -> Vector3:
	var d: Vector3 = player.aim_direction()
	d.y = 0.0
	if player.wish.length() > 0.3:
		d = d.normalized() * 0.4 + player.wish.normalized() * 0.6
	return d.normalized() if d.length() > 0.01 else player.facing


func _find_target(max_range: float, cone_deg: float, dir: Vector3, mask := Game.MASK_HITTABLE) -> Node3D:
	var space := player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = max_range
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), player.global_position)
	q.collision_mask = mask
	var best: Node3D = null
	var best_score := -INF
	var cos_limit := cos(deg_to_rad(cone_deg * 0.5))
	for r in space.intersect_shape(q, 48):
		var n := r["collider"] as Node3D
		if n == null or n == held or not n.has_method("take_hit"):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var to := n.global_position - player.global_position
		var flat := Vector3(to.x, 0, to.z)
		var dist := flat.length()
		if dist < 0.01:
			return n
		var c := flat.normalized().dot(dir)
		if c < cos_limit:
			continue
		var score := c * 2.0 - dist / max_range
		if n.is_in_group("cars"):
			score -= 0.6
		if score > best_score:
			best_score = score
			best = n
	return best


func _attack_pressed() -> void:
	if held:
		_throw_held()
		return
	if defense == Defense.SHIELD:
		_shield_bash()
		return
	var airborne: bool = player.state in [player.State.AIR, player.State.GLIDE, player.State.DASH]
	if airborne and Game.has_skill("dive"):
		var down := Game.raycast(player.global_position, player.global_position + Vector3.DOWN * 6.0, Game.LAYER_WORLD)
		if down.is_empty():
			var power := 1.0
			if form == Form.HAMMER:
				power = 1.6
			elif form == Form.MUSCLE:
				power = 1.3
			player.start_dive(power)
			Game.fx.sound("whoosh", player.global_position, 0.0)
			return
	if form == Form.WHIP:
		_whip_attack()
		return
	var data: Dictionary = FORMS[form]
	var dir := _aim_flat()
	var target := _find_target(data["range"] + 7.0, 80.0, dir)
	if target:
		var to := target.global_position - player.global_position
		to.y = 0
		dir = to.normalized()
		var dist := to.length()
		if dist > data["range"] * 0.85 and player.state == player.State.GROUND:
			# lunge to the target
			var lunge := clampf((dist - data["range"] * 0.6) * 7.0, 0.0, 34.0)
			player.velocity.x = dir.x * lunge
			player.velocity.z = dir.z * lunge
	player.face(dir, 0.35)
	var finisher := combo_index == int(data["combo"]) - 1
	var styles: Array = data["styles"]
	var style: int = styles[combo_index % styles.size()]
	_right_hand = not _right_hand if form != Form.BLADE else true
	player.model.swing(_right_hand, style, data["interval"] * 0.9)
	attack_cooldown = data["interval"] * (1.25 if finisher else 1.0)
	combo_index = (combo_index + 1) % int(data["combo"])
	combo_reset = 0.9
	violence_timer = 2.5
	player.conspicuous_timer = maxf(player.conspicuous_timer, 1.0 if form == Form.FISTS else 2.5)
	Game.fx.sound("whoosh", player.global_position, -10.0, 0.25)
	get_tree().create_timer(0.07, false).timeout.connect(_apply_melee.bind(form, finisher, style))


func _apply_melee(f: int, finisher: bool, style: int) -> void:
	if player.is_dead():
		return
	var data: Dictionary = FORMS[f]
	var reach: float = data["range"]
	var fwd: Vector3 = player.facing
	var center: Vector3 = player.global_position + fwd * reach * 0.5
	var space := player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = reach * 0.75 + 0.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), center)
	q.collision_mask = Game.MASK_HITTABLE
	var cos_limit := cos(deg_to_rad(float(data["arc"]) * 0.5))
	var hit_any := false
	var heavy := f in [Form.HAMMER, Form.MUSCLE] or finisher
	for r in space.intersect_shape(q, 32):
		var n := r["collider"] as Node3D
		if n == null or n == held or not n.has_method("take_hit"):
			continue
		var to := n.global_position - player.global_position
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() > 0.6 and flat.normalized().dot(fwd) < cos_limit:
			continue
		var dmg: float = data["damage"] * player.damage_mult * (1.6 if finisher else 1.0)
		if n.is_in_group("vehicles") or n.is_in_group("cars"):
			dmg *= data["vehicle"]
		var knock: float = data["finisher"] if finisher else data["knock"]
		var force := fwd * knock + Vector3.UP * knock * 0.35
		if style == 3:
			force = fwd * 3.0 + Vector3.UP * (14.0 + knock * 0.4)
		n.take_hit(Game.hit_info(dmg, force, player, data["kind"]))
		var col := Color(0.5, 0.02, 0.02)
		if n.is_in_group("vehicles") or n.is_in_group("cars"):
			col = Color(0.9, 0.7, 0.3)
		Game.fx.splat(n.global_position + Vector3.UP * 0.3, fwd + Vector3.UP * 0.5, col, 10)
		hit_any = true
	if f == Form.HAMMER:
		var impact := player.global_position + fwd * reach + Vector3.DOWN * 0.6
		Game.damage_area(impact, 3.5, 20.0 * player.damage_mult, 10.0, player, "slam", Game.MASK_HITTABLE)
		Game.fx.shockwave(impact, 4.0, Color(1, 0.8, 0.6, 0.6), 0.25)
		Game.fx.debris(impact, 6)
	if hit_any:
		Game.fx.sound(data["sound"], player.global_position, -2.0)
		Game.hit_stop(0.07 if heavy else 0.035)
		player.add_trauma(0.18 if heavy else 0.07)
		rumble(0.3 if heavy else 0.15, 0.6 if heavy else 0.2, 0.12)


func _whip_attack() -> void:
	var data: Dictionary = FORMS[Form.WHIP]
	var aim: Dictionary = player.aim_point(data["range"])
	var hand: Vector3 = player.global_position + Vector3.UP * 0.5 + player.facing * 0.4
	var end: Vector3 = aim["position"]
	var dir := (end - hand).normalized()
	var target := _find_target(data["range"], 30.0, Vector3(dir.x, 0, dir.z).normalized())
	if target:
		end = target.global_position
		dir = (end - hand).normalized()
	player.face(dir, 0.3)
	player.model.swing(true, 1, 0.3)
	attack_cooldown = data["interval"]
	violence_timer = 2.5
	player.conspicuous_timer = 2.5
	Game.fx.tendril_flash(hand, end, 0.22, 0.12)
	Game.fx.sound("tendril", player.global_position, -2.0)
	# hit everything along the lash
	var space := player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 1.4
	var hit_set := {}
	var steps := int(hand.distance_to(end) / 1.5) + 1
	for s in steps:
		var p := hand.lerp(end, float(s) / maxf(steps - 1, 1))
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis(), p)
		q.collision_mask = Game.MASK_HITTABLE
		for r in space.intersect_shape(q, 8):
			var n := r["collider"] as Node3D
			if n and not hit_set.has(n) and n.has_method("take_hit") and n != held:
				hit_set[n] = true
				var dmg: float = data["damage"] * player.damage_mult
				if n.is_in_group("vehicles"):
					dmg *= data["vehicle"]
				n.take_hit(Game.hit_info(dmg, dir * data["knock"] + Vector3.UP * 5.0, player, "slash"))
				Game.fx.splat(n.global_position, dir, Color(0.5, 0.02, 0.02), 8)
	if not hit_set.is_empty():
		Game.hit_stop(0.04)
		player.add_trauma(0.1)
		rumble(0.2, 0.3, 0.1)


func _shield_bash() -> void:
	var dir := _aim_flat()
	player.face(dir, 0.3)
	player.model.swing(false, 0, 0.3)
	attack_cooldown = 0.45
	violence_timer = 2.0
	Game.damage_area(player.global_position + dir * 1.8, 2.4, 10.0 * player.damage_mult, 22.0, player, "melee", Game.MASK_HITTABLE, 0.3)
	Game.fx.burst_ring(player.global_position + dir * 1.5, Color(1, 0.3, 0.2, 0.6), 2.0)
	Game.fx.sound("block", player.global_position, 0.0)


# ------------------------------------------------------------------ specials

func _special() -> void:
	if held:
		drop_held()
		return
	if defense == Defense.SHIELD:
		return
	var costs := [8.0, 14.0, 14.0, 12.0, 6.0, 14.0]
	var cost: float = costs[form]
	if player.biomass < cost:
		Game.say("Not enough biomass", Color(1, 0.5, 0.4))
		return
	player.biomass -= cost
	special_cooldown = 0.9
	violence_timer = 3.0
	player.conspicuous_timer = 3.0
	var dir := _aim_flat()
	player.face(dir, 0.4)
	var pos: Vector3 = player.global_position
	var dm: float = player.damage_mult
	match form:
		Form.FISTS:
			player.model.swing(true, 3, 0.35)
			Game.damage_area(pos + dir * 1.8, 2.5, 22.0 * dm, 18.0, player, "melee", Game.MASK_HITTABLE, 3.0)
			Game.fx.burst_ring(pos + dir * 1.5, Color(1, 0.8, 0.6, 0.6), 2.5)
			Game.fx.sound("heavy", pos, 0.0)
		Form.CLAWS:
			player.model.swing(true, 2, 0.35)
			Game.fx.sound("spike", pos, 2.0)
			for k in 15:
				var p := pos + dir * (2.0 + k * 1.5) + Vector3.DOWN * 0.9
				var delay := k * 0.035
				Game.fx.spike(p, 3.2, delay, 0.5)
				get_tree().create_timer(delay + 0.05, false).timeout.connect(func():
					Game.damage_area(p + Vector3.UP, 2.0, 40.0 * dm, 15.0, player, "slash", Game.MASK_HITTABLE, 2.0))
		Form.HAMMER:
			if player.state != player.State.GROUND:
				player.start_dive(1.8)
				return
			player.model.swing(true, 2, 0.4)
			player.lock(0.3, "crouch")
			get_tree().create_timer(0.18, false).timeout.connect(func():
				var c: Vector3 = player.global_position + Vector3.DOWN * 0.8
				Game.damage_area(c, 9.0, 70.0 * dm, 22.0, player, "slam", Game.MASK_HITTABLE)
				Game.fx.shockwave(c, 11.0, Color(1, 0.5, 0.35, 0.8))
				Game.fx.debris(c, 20)
				Game.fx.sound("land", c, 4.0)
				player.add_trauma(0.45)
				rumble(0.6, 1.0, 0.3)
				Game.hit_stop(0.06))
		Form.BLADE:
			Game.fx.sound("slash", pos, 2.0)
			for k in 3:
				get_tree().create_timer(k * 0.1, false).timeout.connect(func():
					player.model.swing(k % 2 == 0, 1, 0.12)
					Game.damage_area(player.global_position, 5.5, 30.0 * dm, 12.0, player, "blade", Game.MASK_HITTABLE, 0.4)
					var a := randf() * TAU
					Game.fx.tendril_flash(player.global_position + Vector3.UP * 0.3,
						player.global_position + Vector3(cos(a), 0.1, sin(a)) * 5.5, 0.12, 0.1))
			Game.hit_stop(0.04)
		Form.WHIP:
			_whip_grab()
		Form.MUSCLE:
			player.model.swing(true, 0, 0.3)
			player.model.swing(false, 0, 0.3)
			Game.fx.sound("heavy", pos, 4.0)
			Game.fx.shockwave(pos + dir * 3.0, 6.0, Color(1, 0.85, 0.7, 0.6), 0.3)
			for k in 4:
				var p := pos + dir * (2.5 + k * 3.0)
				Game.damage_area(p, 2.5 + k * 0.8, 40.0 * dm, 34.0, player, "melee", Game.MASK_HITTABLE, 0.35)
			player.add_trauma(0.3)
			rumble(0.5, 0.8, 0.2)


func _whip_grab() -> void:
	var aim: Dictionary = player.aim_point(28.0)
	var target := aim["collider"] as Node3D
	var hand: Vector3 = player.global_position + Vector3.UP * 0.5
	var end: Vector3 = aim["position"]
	if target == null:
		target = _find_target(26.0, 25.0, _aim_flat(), Game.LAYER_NPC | Game.LAYER_PROPS | Game.LAYER_VEHICLE)
		if target:
			end = target.global_position
	Game.fx.tendril_flash(hand, end, 0.3, 0.12)
	Game.fx.sound("tendril", player.global_position, 0.0)
	player.model.swing(true, 1, 0.3)
	if target and target.is_in_group("hijackable"):
		pending_hijack = target
		player.start_tether(target.global_position)
		return
	if target and target.has_method("yank_to"):
		target.yank_to(player)
		get_tree().create_timer(0.35, false).timeout.connect(func():
			if is_instance_valid(target) and held == null and target.global_position.distance_to(player.global_position) < 5.0:
				_grab(target))
		return
	if target == null and aim["collider"] != null:
		player.start_tether(end)


# ------------------------------------------------------------------ tether (original power)

func _tether() -> void:
	if tether_cooldown > 0.0:
		return
	if player.biomass < 4.0:
		Game.say("Not enough biomass", Color(1, 0.5, 0.4))
		return
	var aim: Dictionary = player.aim_point(95.0)
	if aim["collider"] == null:
		return
	player.biomass -= 4.0
	tether_cooldown = 0.5
	var target := aim["collider"] as Node3D
	Game.fx.sound("tendril", player.global_position, 0.0)
	if target and target.has_method("yank_to") and not target.is_in_group("hijackable"):
		Game.fx.tendril_flash(player.global_position + Vector3.UP * 0.5, target.global_position, 0.3, 0.1)
		target.yank_to(player)
		return
	if target and target.is_in_group("hijackable"):
		pending_hijack = target
		player.start_tether(target.global_position)
		return
	var point: Vector3 = aim["position"]
	var normal: Vector3 = aim["normal"]
	player.start_tether(point + normal * 0.7)


# ------------------------------------------------------------------ grab / throw

func _grab_pressed() -> void:
	if held:
		_throw_held()
		return
	if weapon != "":
		_drop_weapon()
		return
	var pos: Vector3 = player.global_position
	# weapons on the ground
	var pickup := Game.nearest_in_group("pickups", pos, 2.8)
	if pickup and pickup.has_method("pick_up"):
		pickup.pick_up(player)
		return
	# hijack a vehicle
	var v := Game.nearest_in_group("hijackable", pos, 9.0, func(n): return n.has_method("can_hijack") and n.can_hijack(player))
	if v:
		_hijack(v)
		return
	var dir := _aim_flat()
	var npc := _find_target(3.4, 140.0, dir, Game.LAYER_NPC)
	if npc and npc.has_method("can_be_grabbed") and npc.can_be_grabbed():
		_grab(npc)
		return
	var car := Game.nearest_in_group("cars", pos, 4.5, func(n): return n.can_be_grabbed())
	if car:
		_grab(car)


func _hijack(v: Node3D) -> void:
	if player.tether_line:
		player.tether_line.visible = false
	v.hijack(player)
	player.enter_vehicle(v)
	violence_timer = 3.0
	Game.fx.sound("tendril", player.global_position, 0.0)
	var key := "RB" if Input.get_connected_joypads().size() > 0 else "E"
	Game.say("Hijacked! Press %s to jump out" % key, Color(1, 0.6, 0.4))


func _grab(target: Node3D) -> void:
	if held or target == null or not is_instance_valid(target):
		return
	held = target
	held_kind = "car" if target.is_in_group("cars") else "npc"
	target.on_grabbed(player)
	violence_timer = 2.0
	player.conspicuous_timer = 2.0
	Game.fx.sound("punch", player.global_position, -6.0)
	if held_kind == "car":
		player.model.swing(true, 2, 0.3)


func _update_held(_delta: float) -> void:
	if held == null:
		return
	if not is_instance_valid(held):
		held = null
		held_kind = ""
		return
	var f: Vector3 = player.facing
	if held_kind == "car":
		var t := Transform3D(Basis.looking_at(f.cross(Vector3.UP), Vector3.UP), player.global_position + held.hold_offset())
		held.global_transform = t
		player.model.arm_l.rotation = Vector3(3.0, 0, -0.3)
		player.model.arm_r.rotation = Vector3(3.0, 0, 0.3)
	else:
		held.global_position = player.global_position + f * 0.85 + Vector3.UP * 0.25
		held.global_basis = Basis.looking_at(-f, Vector3.UP)
		player.model.arm_r.rotation = Vector3(1.4, 0, 0.1)


func _throw_held() -> void:
	if held == null:
		return
	var target := held
	var muscle := form == Form.MUSCLE
	var speed := 30.0 if held_kind == "car" else 38.0
	if muscle:
		speed *= 1.45
	var aim: Dictionary = player.aim_point(250.0, Game.LAYER_WORLD | Game.LAYER_NPC | Game.LAYER_VEHICLE)
	var from := target.global_position
	var dir: Vector3 = (Vector3(aim["position"]) - from).normalized()
	dir = (dir + Vector3.UP * 0.06).normalized()
	held = null
	held_kind = ""
	player.face(dir, 0.3)
	player.model.swing(true, 0, 0.3)
	target.on_thrown(dir * speed + player.velocity * 0.5, player)
	violence_timer = 3.0
	player.conspicuous_timer = 3.0
	Game.fx.sound("whoosh", player.global_position, 2.0)
	rumble(0.2, 0.5, 0.15)


func drop_held() -> void:
	if held and is_instance_valid(held):
		held.on_thrown(player.facing * 2.0 + Vector3.UP * 2.0, player)
	held = null
	held_kind = ""


# ------------------------------------------------------------------ consume

func _try_consume() -> void:
	var target: Node3D = null
	if held and held_kind == "npc" and held.has_method("can_be_consumed") and held.can_be_consumed():
		target = held
		held = null
		held_kind = ""
	else:
		target = Game.nearest_in_group("npcs", player.global_position, 3.4, func(n): return n.has_method("can_be_consumed") and n.can_be_consumed())
	if target == null:
		return
	consuming = target
	consume_timer = 0.85
	target.on_consume_start(player)
	player.lock(0.9, "grabbed")
	player.face(target.global_position - player.global_position, 1.0)
	Game.fx.sound("consume", player.global_position, 2.0)
	violence_timer = 3.0
	for k in 5:
		consume_lines.append(Game.fx.make_tendril(0.07))


func _update_consume(delta: float) -> void:
	if not is_instance_valid(consuming):
		_cancel_consume()
		return
	consume_timer -= delta
	var t := 1.0 - consume_timer / 0.85
	var center: Vector3 = player.global_position + player.facing * 0.9 + Vector3.UP * 0.2
	consuming.global_position = consuming.global_position.lerp(center, 0.3)
	consuming.scale = Vector3.ONE * clampf(1.0 - t * 0.85, 0.15, 1.0)
	for k in consume_lines.size():
		var a := k * TAU / consume_lines.size() + t * 8.0
		var from: Vector3 = player.global_position + Vector3(cos(a) * 0.5, 0.4 + sin(a * 1.3) * 0.3, sin(a) * 0.5)
		Game.fx.orient_line(consume_lines[k], from, consuming.global_position + Vector3(0, sin(a) * 0.4, 0), 0.07 * (1.0 - t * 0.5))
	if consume_timer <= 0.0:
		_finish_consume()


func _finish_consume() -> void:
	var target := consuming
	consuming = null
	_clear_consume_lines()
	var info: Dictionary = target.on_consumed(player)
	var kind: String = info.get("kind", "civilian")
	var heal_amt := player.max_health * 0.35
	var bio := 30.0
	var ep := 8
	match kind:
		"soldier", "rocket_soldier":
			ep = 20
		"elite":
			ep = 50
			bio = 50.0
		"scientist":
			ep = 300 if str(info.get("tag", "")) != "" else 40
			bio = 100.0
		"infected":
			ep = 4
			heal_amt = player.max_health * 0.15
		"hunter":
			ep = 150
			heal_amt = player.max_health
			bio = 100.0
	player.heal(heal_amt)
	player.biomass = minf(player.max_biomass, player.biomass + bio)
	Game.add_ep(ep, "Consumed " + str(info.get("label", kind)))
	Game.fx.splat(player.global_position + player.facing * 0.8, Vector3.UP, Color(0.45, 0.02, 0.02), 24)
	Game.fx.burst_ring(player.global_position, Color(0.8, 0.05, 0.05, 0.7), 2.5)
	player.add_trauma(0.15)
	rumble(0.4, 0.4, 0.25)
	var witnessed := _witnessed(player.global_position)
	if info.has("outfit") and kind != "infected" and kind != "hunter":
		player.disguise = kind
		player.model.build(info["outfit"])
		player.model.set_form(form)
		player.model.set_defense(defense)
		if thermal_on:
			player.model.set_thermal(false)
	if witnessed:
		Game.raise_alert(player.global_position, "Someone saw you consume")
	else:
		Game.disguise_changed_unseen()
	if info.get("memory", "") != "":
		Game.say(info["memory"], Color(0.8, 0.9, 1.0))


func _witnessed(pos: Vector3) -> bool:
	for s in get_tree().get_nodes_in_group("military"):
		var n := s as Node3D
		if n == null or not n.has_method("can_see_point"):
			continue
		if n.global_position.distance_to(pos) < 45.0 and n.can_see_point(pos + Vector3.UP * 0.5):
			return true
	return false


func _cancel_consume() -> void:
	if consuming and is_instance_valid(consuming) and consuming.has_method("on_consume_cancel"):
		consuming.on_consume_cancel()
	consuming = null
	_clear_consume_lines()


func _clear_consume_lines() -> void:
	for l in consume_lines:
		if is_instance_valid(l):
			l.queue_free()
	consume_lines.clear()


# ------------------------------------------------------------------ defense, vision, focus, decoy

func _cycle_defense() -> void:
	if not defense_unlocked(1) and not defense_unlocked(2):
		Game.locked_message("shield")
		return
	for k in 3:
		defense = (defense + 1) % 3
		if defense_unlocked(defense):
			break
	player.model.set_defense(defense)
	Game.say("Defense: " + DEFENSE_NAMES[defense], Color(1, 0.7, 0.5))
	Game.fx.sound("block", player.global_position, -6.0)


func set_thermal(on: bool) -> void:
	thermal_on = on
	for n in get_tree().get_nodes_in_group("warm"):
		if n.has_method("set_thermal"):
			n.set_thermal(on)
	if Game.hud and Game.hud.has_method("set_thermal"):
		Game.hud.set_thermal(on)
	Game.fx.sound_ui("zap")


func _set_focus(on: bool) -> void:
	if on and player.biomass < 10.0:
		Game.say("Not enough biomass", Color(1, 0.5, 0.4))
		return
	focus_on = on
	Game.set_focus(on)
	if Game.hud and Game.hud.has_method("set_focus"):
		Game.hud.set_focus(on)
	Game.fx.sound_ui("zap", -2.0)


func _spawn_decoy() -> void:
	if decoy_cooldown > 0.0:
		return
	if player.biomass < 25.0:
		Game.say("Not enough biomass", Color(1, 0.5, 0.4))
		return
	player.biomass -= 25.0
	decoy_cooldown = 6.0
	var d := CharacterBody3D.new()
	d.set_script(DECOY_SCRIPT)
	player.get_parent().add_child(d)
	d.global_position = player.global_position + player.facing * 1.5 + Vector3.UP * 0.2
	d.setup(_aim_flat(), player.model.outfit)
	Game.say("Decoy released", Color(1, 0.6, 0.5))
	Game.fx.burst_ring(player.global_position, Color(1, 0.2, 0.1, 0.6), 3.0)
	Game.fx.sound("consume", player.global_position, 0.0)


# ------------------------------------------------------------------ devastators

func _start_devastator(kind: String) -> void:
	if devastator_cooldown > 0.0:
		return
	var cost := 50.0 if kind == "spikes" else 80.0
	if player.biomass < cost:
		Game.say("Devastator needs %d biomass" % int(cost), Color(1, 0.5, 0.4))
		return
	player.biomass -= cost
	devastating = kind
	devastate_timer = 0.55
	devastator_cooldown = 2.5
	player.lock(0.75, "float")
	player.velocity = Vector3.UP * 4.0
	violence_timer = 4.0
	player.conspicuous_timer = 4.0
	Game.fx.sound("roar", player.global_position, 0.0, 0.05)
	Game.fx.burst_ring(player.global_position, Color(1, 0.1, 0.05, 0.8), 3.0)
	rumble(0.3, 0.3, 0.5)


func _update_devastator(delta: float) -> void:
	devastate_timer -= delta
	if devastate_timer > 0.0:
		player.model.scale = Vector3.ONE * (1.0 + (0.55 - devastate_timer) * 0.4)
		return
	var kind := devastating
	devastating = ""
	var pos: Vector3 = player.global_position
	var ground := Game.raycast(pos, pos + Vector3.DOWN * 30.0, Game.LAYER_WORLD)
	var feet: Vector3 = ground["position"] if not ground.is_empty() else pos + Vector3.DOWN
	var dm: float = player.damage_mult
	player.add_trauma(0.8)
	rumble(1.0, 1.0, 0.5)
	Game.hit_stop(0.08)
	if kind == "spikes":
		Game.fx.sound("spike", pos, 6.0)
		for ring in 4:
			var r := 3.0 + ring * 4.0
			var count := 8 + ring * 6
			for k in count:
				var a := k * TAU / count + ring * 0.3
				Game.fx.spike(feet + Vector3(cos(a), 0, sin(a)) * r, 4.0 + ring * 0.8, ring * 0.07, 0.9)
		Game.damage_area(feet + Vector3.UP, 17.0, 160.0 * dm, 26.0, player, "slash", Game.MASK_HITTABLE, 1.4)
		Game.fx.shockwave(feet, 18.0, Color(0.9, 0.1, 0.05, 0.8), 0.6)
	else:
		Game.fx.sound("tendril", pos, 6.0)
		var targets: Array[Node3D] = []
		var space := player.get_world_3d().direct_space_state
		var shape := SphereShape3D.new()
		shape.radius = 34.0
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis(), pos)
		q.collision_mask = Game.LAYER_NPC | Game.LAYER_VEHICLE | Game.LAYER_HIVE | Game.LAYER_PROPS
		for r in space.intersect_shape(q, 64):
			var n := r["collider"] as Node3D
			if n and n.has_method("take_hit") and not targets.has(n) and Game.line_of_sight(pos, n.global_position + Vector3.UP * 0.5):
				targets.append(n)
		targets.sort_custom(func(a, b): return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
		for k in mini(targets.size(), 26):
			var n := targets[k]
			var dmg := 230.0 * dm
			if n.is_in_group("vehicles"):
				dmg = 420.0 * dm
			var away := (n.global_position - pos).normalized()
			Game.fx.tendril_flash(pos, n.global_position, 0.4, 0.16)
			n.take_hit(Game.hit_info(dmg, away * 24.0 + Vector3.UP * 8.0, player, "slash"))
			Game.fx.splat(n.global_position, away, Color(0.5, 0.02, 0.02), 12)
		for k in 12:
			var a := k * TAU / 12.0
			Game.fx.tendril_flash(pos, pos + Vector3(cos(a), randf_range(-0.5, 0.8), sin(a)) * 18.0, 0.35, 0.14)
		Game.fx.shockwave(feet, 20.0, Color(0.9, 0.1, 0.05, 0.8), 0.6)
	Game.panic_at(pos, 80.0)


# ------------------------------------------------------------------ guns

func give_weapon(kind: String, rounds: int) -> void:
	if held:
		drop_held()
	weapon = kind
	ammo = rounds
	_attach_weapon_mesh()
	Game.say("Picked up %s" % ("assault rifle" if kind == "rifle" else "rocket launcher"), Color(1, 0.85, 0.5))
	Game.fx.sound("pickup", player.global_position, 0.0)


func _attach_weapon_mesh() -> void:
	var hand: Node3D = player.model.hand_r
	for c in hand.get_children():
		if c.has_meta("weapon"):
			c.queue_free()
	if weapon == "":
		return
	var mi := MeshInstance3D.new()
	mi.set_meta("weapon", true)
	if weapon == "rifle":
		mi.mesh = player.model.box(Vector3(0.07, 0.12, 0.85))
		mi.material_override = player.model.mat(Color(0.08, 0.08, 0.08), 0.0, 0.6, 0.4)
		mi.position = Vector3(0, -0.05, -0.3)
	else:
		mi.mesh = player.model.capsule(0.09, 1.1)
		mi.material_override = player.model.mat(Color(0.2, 0.25, 0.15))
		mi.rotation.x = PI * 0.5
	hand.add_child(mi)


func _drop_weapon() -> void:
	if weapon == "":
		return
	weapon = ""
	ammo = 0
	_attach_weapon_mesh()


func _update_weapon() -> void:
	var firing := Input.is_action_pressed("attack") if weapon == "rifle" else Input.is_action_just_pressed("attack")
	player.model.arm_r.rotation = Vector3(1.45, 0, 0)
	player.model.arm_l.rotation = Vector3(1.3, 0, -0.45)
	if not firing or fire_cooldown > 0.0:
		return
	var aim: Dictionary = player.aim_point(220.0)
	var muzzle: Vector3 = player.global_position + Vector3.UP * 0.55 + player.facing * 0.9
	var dir: Vector3 = (Vector3(aim["position"]) - muzzle).normalized()
	player.face(dir, 0.5)
	violence_timer = 3.0
	player.conspicuous_timer = 3.0
	if weapon == "rifle":
		fire_cooldown = 0.09
		dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.012).normalized()
		var hit := Game.raycast(muzzle, muzzle + dir * 220.0, Game.LAYER_WORLD | Game.MASK_HITTABLE, [player.get_rid()])
		var end := muzzle + dir * 220.0
		if not hit.is_empty():
			end = hit["position"]
			var c := hit["collider"] as Node
			if c and c.has_method("take_hit"):
				c.take_hit(Game.hit_info(10.0 * player.damage_mult, dir * 3.0, player, "bullet"))
				Game.fx.splat(end, -dir, Color(0.5, 0.02, 0.02), 4)
			else:
				Game.fx.debris(end, 2)
		Game.fx.tracer(muzzle, end)
		Game.fx.flash_light(muzzle, Color(1, 0.8, 0.4), 3.0, 6.0, 0.05)
		Game.fx.sound("gunshot", muzzle, -4.0)
		player.add_trauma(0.04)
	else:
		fire_cooldown = 0.9
		var p := Node3D.new()
		p.set_script(PROJECTILE_SCRIPT)
		player.get_parent().add_child(p)
		p.launch(muzzle, dir * 55.0, player, "rocket")
		Game.fx.sound("rocket", muzzle, 0.0)
		player.add_trauma(0.15)
	rumble(0.15, 0.2, 0.06)
	ammo -= 1
	if ammo <= 0:
		Game.say("Out of ammo", Color(1, 0.7, 0.5))
		_drop_weapon()


# ------------------------------------------------------------------ controller rumble

func rumble(weak: float, strong: float, duration: float) -> void:
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, clampf(weak, 0, 1), clampf(strong, 0, 1), duration)
