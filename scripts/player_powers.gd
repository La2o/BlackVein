class_name PlayerPowers
extends Node
## Combat and powers for the player:
## arm forms (fists, claws, hammerfist, blade, whipfist, musclemass),
## shield and armor, thermal vision, grab and throw, consume and disguise,
## devastators, picked-up guns, vehicle hijacking, and three original powers:
## Tether (zip / yank), Focus (slow motion) and Biomass Decoy.

enum Form { FISTS, CLAWS, HAMMER, BLADE, WHIP, MUSCLE, SPIKES }
enum Defense { NONE, SHIELD, ARMOR, WINGS, LIGHT }
enum Vision { NORMAL, THERMAL, NIGHT, PREDATOR }
enum Legs { NORMAL, RUNNER, LEAPER, CRAWLER, CRUSHER }
## Whole-body transformations, cycled with N / LB + D-pad Down. They drain biomass while worn.
enum Creature { NONE, BRUTE, STALKER, WRAITH }
const CREATURE_NAMES := ["Human", "Brute", "Stalker", "Wraith"]
const CREATURE_SKILLS := ["", "brute_form", "stalker_form", "wraith_form"]
const CREATURE_DRAIN := [0.0, 3.0, 2.5, 3.5]   # biomass per second

const FORM_NAMES := ["Fists", "Claws", "Hammerfist", "Blade", "Whipfist", "Musclemass", "Bone Spikes"]
const DEFENSE_NAMES := ["Normal body", "Shield", "Armor", "Wings", "Light Body"]
const FORM_SKILLS := ["", "claws", "hammer", "blade", "whip", "muscle_form", "spike_form"]
const DEFENSE_SKILLS := ["", "shield", "armor", "wings", "light_body"]
const VISION_NAMES := ["Normal sight", "Thermal Vision", "Night Vision", "Predator Sense"]
const VISION_SKILLS := ["", "thermal", "night_vision", "predator_sense"]
const LEG_NAMES := ["Normal legs", "Runner Legs", "Leaper Legs", "Crawler Legs", "Crusher Legs"]
const LEG_SKILLS := ["", "runner_legs", "leaper_legs", "crawler_legs", "crusher_legs"]
const SPECIAL_NAMES := ["Uppercut", "Spike Line", "Ground Slam", "Whirlwind", "Whip Grab", "Thunderclap", "Spike Storm"]
const FORMS := {
	Form.FISTS: {"damage": 12.0, "range": 2.4, "arc": 75.0, "interval": 0.3, "combo": 3, "knock": 6.0, "finisher": 16.0, "vehicle": 0.6, "styles": [0, 0, 3], "sound": "punch", "kind": "melee"},
	Form.CLAWS: {"damage": 17.0, "range": 2.9, "arc": 110.0, "interval": 0.19, "combo": 4, "knock": 4.0, "finisher": 12.0, "vehicle": 0.9, "styles": [1, 1, 1, 2], "sound": "slash", "kind": "slash"},
	Form.HAMMER: {"damage": 46.0, "range": 3.2, "arc": 90.0, "interval": 0.6, "combo": 2, "knock": 18.0, "finisher": 26.0, "vehicle": 2.4, "styles": [2, 2], "sound": "heavy", "kind": "slam"},
	Form.BLADE: {"damage": 52.0, "range": 3.9, "arc": 140.0, "interval": 0.42, "combo": 3, "knock": 9.0, "finisher": 18.0, "vehicle": 3.0, "styles": [1, 1, 2], "sound": "slash", "kind": "blade"},
	Form.WHIP: {"damage": 30.0, "range": 17.0, "arc": 18.0, "interval": 0.5, "combo": 2, "knock": 12.0, "finisher": 22.0, "vehicle": 1.2, "styles": [1, 1], "sound": "slash", "kind": "slash"},
	Form.MUSCLE: {"damage": 28.0, "range": 2.6, "arc": 85.0, "interval": 0.38, "combo": 3, "knock": 26.0, "finisher": 42.0, "vehicle": 1.5, "styles": [0, 0, 3], "sound": "heavy", "kind": "melee"},
	Form.SPIKES: {"damage": 20.0, "range": 90.0, "arc": 10.0, "interval": 0.22, "combo": 1, "knock": 7.0, "finisher": 7.0, "vehicle": 1.0, "styles": [0], "sound": "spike", "kind": "slash"},
}
const DECOY_SCRIPT := preload("res://scripts/decoy.gd")
const PROJECTILE_SCRIPT := preload("res://scripts/projectile.gd")
## Guns you can pick up, Prototype 1 style. auto = hold to fire; drop/armory = rounds you get.
const WEAPONS := {
	"rifle": {"name": "Assault rifle", "auto": true, "cooldown": 0.09, "drop": 90, "armory": 120},
	"launcher": {"name": "Rocket launcher", "auto": false, "cooldown": 0.9, "drop": 6, "armory": 10},
	"grenade": {"name": "Grenade launcher", "auto": false, "cooldown": 0.7, "drop": 8, "armory": 14},
	"mg": {"name": "Heavy machine gun", "auto": true, "cooldown": 0.055, "drop": 150, "armory": 250},
}
const LOCK_TIME := 0.5     # seconds of aiming at a vehicle to lock on
const LOCK_RANGE := 260.0

var player: Player
var form: int = Form.FISTS
var defense: int = Defense.NONE
var thermal_on := false
var vision: int = Vision.NORMAL
var legs: int = Legs.NORMAL
var _crush_timer := 0.0
var _tint_timer := 0.0
var _defense_hold := 0.0
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
var creature: int = Creature.NONE
var weapon := ""
var ammo := 0
var fire_cooldown := 0.0
var lock_target: Node3D = null   # rocket launcher: the vehicle you've locked onto
var _lock_on: Node3D = null      # what the lock is building on
var _lock_t := 0.0
var consuming: Node3D = null
var consume_timer := 0.0
var consume_lines: Array[MeshInstance3D] = []
var devastating := ""
var devastate_timer := 0.0
var pending_hijack: Node3D = null
var artillery_cooldown := 0.0
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
	match creature:
		Creature.BRUTE: f *= 0.92
		Creature.STALKER: f *= 1.4
	if weapon == "mg":
		f *= 0.75   # a heavy machine gun weighs you down
	if defense == Defense.ARMOR:
		f *= 0.85
	elif defense == Defense.LIGHT:
		f *= LIGHT_SPEED
	match legs:
		Legs.RUNNER: f *= 1.35
		Legs.CRUSHER: f *= 0.95
	if weapon != "" and weapon != "mg":
		f *= 0.85
	return f


## Something nobody human would be doing: a body form showing, carrying a person or a car, a
## devastator, or a gun when you're not dressed as a soldier.
func looks_inhuman() -> bool:
	if form != Form.FISTS or defense != Defense.NONE or legs != Legs.NORMAL or devastating != "" or creature != Creature.NONE:
		return true
	if held != null:
		return true
	return weapon != "" and not str(player.disguise) in Game.MILITARY_DISGUISES


func is_transformed() -> bool:
	return form != Form.FISTS or defense != Defense.NONE or legs != Legs.NORMAL or held != null or weapon != "" or devastating != ""


## multiplies jump strength (leg forms, Light Body)
func jump_factor() -> float:
	var f := LIGHT_JUMP if defense == Defense.LIGHT else 1.0
	match creature:
		Creature.BRUTE: f *= 1.1
		Creature.STALKER: f *= 1.3
		Creature.WRAITH: f *= 1.15
	match legs:
		Legs.LEAPER: return f * 1.5
		Legs.RUNNER: return f * 1.1
	return f


## Light Body: a lean, stripped-down body built for running. Faster on the ground, up walls and
## in the air, higher jumps — but it takes more damage.
const LIGHT_SPEED := 1.25
const LIGHT_JUMP := 1.2
const LIGHT_DAMAGE := 1.3

func is_light() -> bool:
	return defense == Defense.LIGHT


func clings_to_walls() -> bool:
	return legs == Legs.CRAWLER or creature == Creature.STALKER


func unstoppable() -> bool:
	return legs == Legs.CRUSHER or defense == Defense.ARMOR or creature == Creature.BRUTE


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
	elif defense == Defense.LIGHT:
		dmg *= LIGHT_DAMAGE
	if creature == Creature.BRUTE:
		dmg *= 0.6
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
	for k in FORM_NAMES.size():
		if event.is_action_pressed("form_%d" % (k + 1)):
			set_form(k)


func form_unlocked(f: int) -> bool:
	return f == 0 or Game.has_skill(FORM_SKILLS[f])


func defense_unlocked(d: int) -> bool:
	return d == 0 or Game.has_skill(DEFENSE_SKILLS[d])


func vision_unlocked(v: int) -> bool:
	return v == 0 or Game.has_skill(VISION_SKILLS[v])


func legs_unlocked(l: int) -> bool:
	return l == 0 or Game.has_skill(LEG_SKILLS[l])


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


## Next creature form you've learned, then back to human.
func _cycle_creature() -> void:
	var any := false
	for c in range(1, CREATURE_NAMES.size()):
		any = any or Game.has_skill(CREATURE_SKILLS[c])
	if not any:
		Game.locked_message("brute_form")
		return
	var c := creature
	for k in CREATURE_NAMES.size():
		c = (c + 1) % CREATURE_NAMES.size()
		if c == Creature.NONE or Game.has_skill(CREATURE_SKILLS[c]):
			break
	if c != Creature.NONE and player.biomass < 15.0:
		Game.say("Not enough biomass to transform", Color(1, 0.6, 0.5))
		return
	set_creature(c)


func set_creature(c: int, silent := false) -> void:
	if c != Creature.NONE and not Game.has_skill(CREATURE_SKILLS[c]):
		Game.locked_message(CREATURE_SKILLS[c])
		return
	creature = c
	player.model.set_creature(c)
	_attach_weapon_mesh()
	player.apply_upgrades()
	if silent:
		return
	Game.say(CREATURE_NAMES[c] if c != Creature.NONE else "Human form", Color(1, 0.45, 0.35))
	Game.fx.sound("evolve" if c != Creature.NONE else "consume", player.global_position, -2.0)
	Game.fx.burst_ring(player.global_position, Color(0.8, 0.08, 0.05, 0.7), 3.5)
	Game.fx.splat(player.global_position + Vector3.UP * 0.5, Vector3.UP, Color(0.45, 0.02, 0.02), 20)
	player.add_trauma(0.35)
	player.conspicuous_timer = maxf(player.conspicuous_timer, 3.0)


func _physics_process(delta: float) -> void:
	if creature != Creature.NONE and not player.is_dead():
		player.biomass -= CREATURE_DRAIN[creature] * delta
		if player.biomass <= 0.0:
			player.biomass = 0.0
			Game.say("Out of biomass: back to human form", Color(1, 0.6, 0.5))
			set_creature(Creature.NONE, true)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	special_cooldown = maxf(0.0, special_cooldown - delta)
	tether_cooldown = maxf(0.0, tether_cooldown - delta)
	decoy_cooldown = maxf(0.0, decoy_cooldown - delta)
	devastator_cooldown = maxf(0.0, devastator_cooldown - delta)
	artillery_cooldown = maxf(0.0, artillery_cooldown - delta)
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

	if Game.hud and Game.hud.wheel_open:
		# picking forms: no attacks or powers fire from the same buttons
		return
	var mod := Input.is_action_pressed("devastator_mod")
	if mod and Input.is_action_just_pressed("dash") and Game.hud:
		Game.hud.open_wardrobe()
		return
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
	if Input.is_action_just_pressed("artillery") or (mod and Input.is_action_just_pressed("grab")):
		_call_artillery()
	elif Input.is_action_just_pressed("consume"):
		_try_consume()
	if Input.is_action_just_pressed("grab") and not mod:
		_grab_pressed()
	# body form button: tap to cycle, hold to open the forms wheel
	if Input.is_action_pressed("cycle_defense"):
		_defense_hold += delta / maxf(Engine.time_scale, 0.05)
		if _defense_hold > 0.28 and Game.hud and not Game.hud.wheel_open:
			Game.hud.open_wheel()
	elif _defense_hold > 0.0:
		if _defense_hold <= 0.28:
			_cycle_defense()
		_defense_hold = 0.0
	if Input.is_action_just_pressed("forms_wheel") and Game.hud and not Game.hud.wheel_open:
		Game.hud.open_wheel()
	if Input.is_action_just_pressed("thermal"):
		_cycle_vision()
	_update_legs(delta)
	_tint_timer -= delta
	if _tint_timer <= 0.0 and vision == Vision.PREDATOR:
		_tint_timer = 0.5
		refresh_tints()
	if Input.is_action_just_pressed("focus"):
		if Game.has_skill("focus"):
			_set_focus(not focus_on)
		else:
			Game.locked_message("focus")
	if Input.is_action_just_pressed("creature_form") or (mod and Input.is_action_just_pressed("decoy")):
		_cycle_creature()
		return
	if Input.is_action_just_pressed("decoy") and not mod and held and held_kind == "npc":
		if Game.has_skill("bio_bomb"):
			_bio_bomb_held()
		else:
			Game.locked_message("bio_bomb")
	elif Input.is_action_just_pressed("decoy") and not mod:
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
		# up close, a fixed angle is too strict: also accept anyone in front within ~0.7 m of the aim line
		var ahead := flat.dot(dir)
		var lateral := (flat - dir * ahead).length()
		if c < cos_limit and not (ahead > 0.0 and lateral < 0.7):
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
	if form == Form.SPIKES:
		_spike_shot(player.aim_direction(), 0.0)
		attack_cooldown = FORMS[Form.SPIKES]["interval"]
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


## Bone Spikes form: fire a bone spike from the forearm. Pierces up to 3 targets.
func _spike_shot(dir: Vector3, spread: float) -> void:
	var aim: Dictionary = player.aim_point(120.0)
	var muzzle: Vector3 = player.global_position + Vector3.UP * 0.5 + player.facing * 0.7
	var d: Vector3 = (Vector3(aim["position"]) - muzzle).normalized() if spread == 0.0 else dir
	if spread == 0.0:
		# light aim assist: snap to an enemy close to the crosshair
		var flat := Vector3(d.x, 0, d.z).normalized()
		var assist := _find_target(45.0, 18.0, flat, Game.LAYER_NPC | Game.LAYER_VEHICLE | Game.LAYER_HIVE)
		if assist:
			d = (assist.global_position + Vector3.UP * 0.3 - muzzle).normalized()
	d = (d + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	player.face(d, 0.4)
	player.model.swing(true, 0, 0.15)
	violence_timer = 2.5
	player.conspicuous_timer = 2.5
	# trace from the chest so enemies standing right on top of you still get hit
	var from: Vector3 = player.global_position + Vector3.UP * 0.5
	var end := from + d * 120.0
	var exclude: Array[RID] = [player.get_rid()]
	var pierced := 0
	while pierced < 3:
		var hit := Game.raycast(from, end, Game.LAYER_WORLD | Game.MASK_HITTABLE, exclude)
		if hit.is_empty():
			break
		var c := hit["collider"] as Node
		var p: Vector3 = hit["position"]
		if c and c.has_method("take_hit"):
			var dmg: float = FORMS[Form.SPIKES]["damage"] * player.damage_mult
			c.take_hit(Game.hit_info(dmg, d * 7.0 + Vector3.UP * 2.0, player, "slash"))
			Game.fx.splat(p, -d, Color(0.5, 0.02, 0.02), 6)
			pierced += 1
			if c is CollisionObject3D:
				exclude.append((c as CollisionObject3D).get_rid())
			from = p
		elif c is CollisionObject3D and ((c as CollisionObject3D).collision_layer & Game.LAYER_WORLD) == 0:
			# something loose that can't be hurt: fly past it
			exclude.append((c as CollisionObject3D).get_rid())
			from = p
		else:
			end = p
			Game.fx.debris(p, 3, Color(0.85, 0.8, 0.7))
			break
	Game.fx.tracer(muzzle, end, Color(0.95, 0.9, 0.8), 0.06)
	Game.fx.sound("spike", muzzle, -6.0, 0.2)


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
		if held_kind == "npc" and Game.has_skill("dominate"):
			_brand_held()
		else:
			drop_held()
		return
	if defense == Defense.SHIELD:
		return
	var costs := [8.0, 14.0, 14.0, 12.0, 6.0, 14.0, 16.0]
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
		Form.SPIKES:
			var aimd: Vector3 = player.aim_direction()
			for k in 9:
				var off := (k - 4) * 0.07
				_spike_shot(aimd.rotated(Vector3.UP, off), 0.03)
			player.add_trauma(0.25)
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
		get_tree().create_timer(0.35, false).timeout.connect(_grab_if_close.bind(target))
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
	if not held and Game.interiors and Game.interiors.try_interact():
		return
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
	var moving := Game.nearest_in_group("traffic", pos, 4.5)
	if moving and (car == null or moving.global_position.distance_to(pos) < car.global_position.distance_to(pos)):
		car = moving.convert_to_physics()
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


func _grab_if_close(target) -> void:
	if is_instance_valid(target) and held == null and target.global_position.distance_to(player.global_position) < 5.0:
		_grab(target)


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


# ------------------------------------------------------------------ disguise wardrobe

var _wardrobe_cd := 0.0


## Put on a disguise from the wardrobe. index -1 = your true form.
func wear_disguise(index: int) -> bool:
	if consuming or player.state in [player.State.PILOT, player.State.DEAD]:
		return false
	var kind := "civilian"
	var outfit: Dictionary = {}
	var label := "your true form"
	if index >= 0:
		if index >= Game.disguises.size():
			return false
		var d: Dictionary = Game.disguises[index]
		kind = d["kind"]
		outfit = d["outfit"]
		label = d["label"]
	var witnessed := _witnessed(player.global_position)
	player.disguise = kind
	player.model.build(outfit)
	player.model.set_form(form)
	player.model.set_defense(defense)
	_attach_weapon_mesh()   # rebuilding the body dropped the gun mesh
	if thermal_on:
		player.model.set_thermal(false)
	Game.fx.burst_ring(player.global_position, Color(0.8, 0.1, 0.06, 0.7), 2.2)
	Game.fx.sound("consume", player.global_position, -6.0, 0.3)
	if witnessed:
		Game.raise_alert(player.global_position, "They saw you change shape!")
	else:
		Game.disguise_changed_unseen()
		Game.say("Now disguised as %s" % label, Color(0.8, 0.9, 1))
	return true


# ------------------------------------------------------------------ dominate (allies)

func max_allies() -> int:
	return Game.skill_rank("dominate") * 2


func ally_count() -> int:
	return get_tree().get_nodes_in_group("allies").size()


## Bio-Bomb: the person you're holding swells with biomass and bursts 1.6 s later. Throw them first.
func _bio_bomb_held() -> void:
	var target := held
	if target == null or not is_instance_valid(target) or not target.has_method("arm_bio_bomb"):
		return
	if target.bio_bomb_timer >= 0.0:
		return
	if player.biomass < 25.0:
		Game.say("A bio-bomb needs 25 biomass", Color(1, 0.6, 0.5))
		return
	player.biomass -= 25.0
	violence_timer = 2.0
	player.conspicuous_timer = 2.0
	target.arm_bio_bomb(player)
	Game.fx.sound("consume", player.global_position, 0.0, 0.5)
	Game.stat_add("bio_bombs")


func _brand_held() -> void:
	var target := held
	if target == null or not is_instance_valid(target) or not target.has_method("can_be_branded") or not target.can_be_branded():
		Game.say("You can't brand that one", Color(1, 0.6, 0.5))
		return
	if ally_count() >= max_allies():
		Game.say("Too many allies (%d/%d). Rank up Dominate for more" % [ally_count(), max_allies()], Color(1, 0.6, 0.5))
		return
	if player.biomass < 30.0:
		Game.say("Branding needs 30 biomass", Color(1, 0.6, 0.5))
		return
	player.biomass -= 30.0
	player.lock(0.75, "grabbed")
	violence_timer = 2.0
	Game.fx.sound("consume", player.global_position, 0.0, 0.3)
	for k in 6:
		var a := k * TAU / 6.0
		Game.fx.tendril_flash(player.global_position + Vector3(cos(a) * 0.6, 0.6, sin(a) * 0.6), target.global_position + Vector3.UP * 0.4, 0.6, 0.06)
	get_tree().create_timer(0.7, false).timeout.connect(_finish_brand.bind(target))


func _finish_brand(target) -> void:
	if not is_instance_valid(target) or held != target:
		return
	held = null
	held_kind = ""
	target.on_thrown(player.facing * 1.5 + Vector3.UP * 2.0, player)
	target.make_ally()
	Game.fx.burst_ring(target.global_position, Color(1, 0.12, 0.06, 0.8), 3.0)
	Game.fx.sound("evolve", target.global_position, -4.0)
	Game.stat_add("brands")
	Game.stat_max("max_allies", ally_count())
	Game.add_xp(15, "Branded " + str(target.label))
	Game.say("%s is yours  (%d/%d allies)" % [str(target.label).capitalize(), ally_count(), max_allies()], Color(1, 0.4, 0.3))
	if _witnessed(player.global_position):
		Game.raise_alert(player.global_position, "Someone saw you brand a soldier" if target.kind in Game.SOLDIER_KINDS else "")


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
	Game.stat_add("consumes")
	var kind: String = info.get("kind", "civilian")
	var heal_amt := player.max_health * 0.35
	var bio := 30.0
	var ep := 8
	match kind:
		"soldier", "rocket_soldier", "grenadier":
			ep = 20
		"heavy_gunner":
			ep = 35
			bio = 45.0
		"elite":
			ep = 50
			bio = 50.0
		"commander":
			ep = 250
			bio = 100.0
			if not Game.flags.get("artillery_codes", false):
				Game.flags["artillery_codes"] = true
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
	var witnessed := _witnessed(player.global_position)
	if witnessed:
		Game.add_ep(ep, "Consumed " + str(info.get("label", kind)))
	else:
		# Prototype 2 style: nobody saw it, so nobody knows
		Game.stat_add("stealth_consumes")
		Game.add_ep(int(ep * 1.5), "Stealth consume: " + str(info.get("label", kind)))
	Game.fx.splat(player.global_position + player.facing * 0.8, Vector3.UP, Color(0.45, 0.02, 0.02), 24)
	Game.fx.burst_ring(player.global_position, Color(0.8, 0.05, 0.05, 0.7), 2.5)
	player.add_trauma(0.15)
	rumble(0.4, 0.4, 0.25)
	if info.has("outfit") and kind != "infected" and kind != "hunter":
		player.disguise = kind
		player.model.build(info["outfit"])
		Game.add_disguise(kind, str(info.get("label", kind)), info["outfit"])
		player.model.set_form(form)
		player.model.set_defense(defense)
		_attach_weapon_mesh()   # rebuilding the body dropped the gun mesh
		if thermal_on:
			player.model.set_thermal(false)
	if witnessed:
		Game.raise_alert(player.global_position, "Someone saw you consume")
	else:
		Game.disguise_changed_unseen()
	if str(info.get("memory_flag", "")) != "":
		Game.flags[info["memory_flag"]] = true
	if info.get("memory", "") != "":
		Game.say(info["memory"], Color(0.8, 0.9, 1.0))
		Game.stat_add("memories")
		var mem_list: Array = Game.stats.get("memory_log", [])
		if not mem_list.has(info["memory"]):
			mem_list.append(info["memory"])
		Game.stats["memory_log"] = mem_list


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
	var n := DEFENSE_NAMES.size()
	var any := false
	for d in range(1, n):
		any = any or defense_unlocked(d)
	if not any:
		Game.locked_message("shield")
		return
	var d := defense
	for k in n:
		d = (d + 1) % n
		if defense_unlocked(d):
			break
	set_defense(d)


func set_defense(d: int, silent := false) -> void:
	if not defense_unlocked(d):
		Game.locked_message(DEFENSE_SKILLS[d])
		return
	defense = d
	player.model.set_defense(d)
	if silent:
		return
	Game.say(DEFENSE_NAMES[d], Color(1, 0.7, 0.5))
	Game.fx.sound("block", player.global_position, -6.0)
	Game.fx.burst_ring(player.global_position, Color(0.7, 0.2, 0.9, 0.5), 1.6)


func _cycle_vision() -> void:
	var n := VISION_NAMES.size()
	var any := false
	for v in range(1, n):
		any = any or vision_unlocked(v)
	if not any:
		Game.locked_message("thermal")
		return
	var v := vision
	for k in n:
		v = (v + 1) % n
		if vision_unlocked(v):
			break
	set_vision(v)


func set_vision(v: int, silent := false) -> void:
	if not vision_unlocked(v):
		Game.locked_message(VISION_SKILLS[v])
		return
	vision = v
	thermal_on = v == Vision.THERMAL
	for nd in get_tree().get_nodes_in_group("warm"):
		if nd.has_method("set_thermal"):
			nd.set_thermal(thermal_on)
	refresh_tints()
	if Game.hud and Game.hud.has_method("set_vision"):
		Game.hud.set_vision(v)
	if not silent:
		Game.say(VISION_NAMES[v], Color(0.6, 0.85, 1.0))
		Game.fx.sound_ui("zap")


## old name kept for tests and saves
func set_thermal(on: bool) -> void:
	set_vision(Vision.THERMAL if on else Vision.NORMAL, true)
	Game.fx.sound_ui("zap")


## Predator Sense outlines people through walls; everyone else goes back to normal.
func refresh_tints() -> void:
	for nd in get_tree().get_nodes_in_group("npcs"):
		if nd.has_method("refresh_tint"):
			nd.refresh_tint()


func set_legs(l: int, silent := false) -> void:
	if not legs_unlocked(l):
		Game.locked_message(LEG_SKILLS[l])
		return
	legs = l
	player.model.set_legs(l)
	player.apply_upgrades()
	if silent:
		return
	Game.say(LEG_NAMES[l], Color(0.6, 1.0, 0.6))
	Game.fx.sound("consume", player.global_position, -12.0, 0.3)
	Game.fx.burst_ring(player.global_position + Vector3.DOWN * 0.7, Color(0.3, 0.9, 0.3, 0.5), 1.6)


## Crusher legs: sprinting plows through people and cars.
func _update_legs(delta: float) -> void:
	if legs != Legs.CRUSHER:
		return
	_crush_timer -= delta
	var hv := Vector3(player.velocity.x, 0, player.velocity.z)
	if _crush_timer > 0.0 or hv.length() < 15.0 or player.state != player.State.GROUND:
		return
	_crush_timer = 0.15
	var front := player.global_position + hv.normalized() * 1.3
	var hits := Game.damage_area(front, 1.8, 30.0 * player.damage_mult, 18.0, player, "impact", Game.MASK_HITTABLE)
	if hits > 0:
		player.add_trauma(0.15)
		Game.fx.debris(front, 4)
		violence_timer = 2.0


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


# ------------------------------------------------------------------ artillery

func _call_artillery() -> void:
	if not Game.has_skill("artillery"):
		Game.locked_message("artillery")
		return
	if not str(player.disguise) in Game.MILITARY_DISGUISES:
		Game.say("You need a military disguise to call artillery", Color(1, 0.6, 0.5))
		return
	if artillery_cooldown > 0.0:
		Game.say("Artillery ready in %d s" % int(ceil(artillery_cooldown)), Color(1, 0.7, 0.5))
		return
	var aim: Dictionary = player.aim_point(300.0, Game.LAYER_WORLD)
	var target: Vector3 = aim["position"]
	artillery_cooldown = 30.0
	Game.say("Artillery inbound", Color(1, 0.8, 0.4))
	Game.fx.smoke_column(target, Color(1.0, 0.15, 0.1, 0.8), 6.0)
	Game.fx.sound_ui("alert", -6.0)
	get_tree().create_timer(4.0, false).timeout.connect(func():
		if Game.director:
			Game.director._drop_bombs(target))


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
	Game.say("Picked up a %s" % str(WEAPONS[kind]["name"]).to_lower(), Color(1, 0.85, 0.5))
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
	elif weapon == "mg":
		mi.mesh = player.model.box(Vector3(0.14, 0.2, 1.25))
		mi.material_override = player.model.mat(Color(0.1, 0.1, 0.09), 0.0, 0.7, 0.35)
		mi.position = Vector3(0, -0.06, -0.4)
	elif weapon == "grenade":
		mi.mesh = player.model.capsule(0.12, 0.75)
		mi.material_override = player.model.mat(Color(0.28, 0.3, 0.2), 0.0, 0.4, 0.5)
		mi.rotation.x = PI * 0.5
		mi.position = Vector3(0, -0.05, -0.2)
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
	lock_target = null
	_lock_on = null
	_attach_weapon_mesh()


func _update_weapon() -> void:
	var w: Dictionary = WEAPONS[weapon]
	var firing := Input.is_action_pressed("attack") if w["auto"] else Input.is_action_just_pressed("attack")
	player.model.arm_r.rotation = Vector3(1.45, 0, 0)
	player.model.arm_l.rotation = Vector3(1.3, 0, -0.45)
	if weapon == "launcher":
		_update_lock()
	if not firing or fire_cooldown > 0.0:
		return
	var aim: Dictionary = player.aim_point(220.0)
	var muzzle: Vector3 = player.global_position + Vector3.UP * 0.55 + player.facing * 0.9
	var dir: Vector3 = (Vector3(aim["position"]) - muzzle).normalized()
	player.face(dir, 0.5)
	violence_timer = 3.0
	player.conspicuous_timer = 3.0
	fire_cooldown = w["cooldown"]
	match weapon:
		"rifle":
			_fire_hitscan(muzzle, dir, 0.012, 10.0, 0.04)
		"mg":
			_fire_hitscan(muzzle, dir, 0.02, 16.0, 0.07)
		"launcher":
			var p := Node3D.new()
			p.set_script(PROJECTILE_SCRIPT)
			player.get_parent().add_child(p)
			var locked := lock_target if lock_target and is_instance_valid(lock_target) else null
			if locked:
				dir = (dir + Vector3.UP * 0.25).normalized()   # loft it a little; it steers in
			p.launch(muzzle, dir * 55.0, player, "rocket", locked)
			Game.fx.sound("rocket", muzzle, 0.0)
			player.add_trauma(0.15)
		"grenade":
			var land: Vector3 = aim["position"]
			var dist := muzzle.distance_to(land)
			if dist > 70.0:
				land = muzzle + dir * 70.0
				dist = 70.0
			var g := Node3D.new()
			g.set_script(PROJECTILE_SCRIPT)
			player.get_parent().add_child(g)
			g.launch(muzzle, PROJECTILE_SCRIPT.lob_velocity(muzzle, land, clampf(dist / 30.0, 0.35, 1.4)), player, "grenade")
			Game.fx.sound("whoosh", muzzle, -2.0)
			player.add_trauma(0.08)
	rumble(0.15, 0.2, 0.06)
	ammo -= 1
	if ammo <= 0:
		Game.say("Out of ammo", Color(1, 0.7, 0.5))
		_drop_weapon()


func _fire_hitscan(muzzle: Vector3, dir: Vector3, spread: float, damage: float, kick: float) -> void:
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	var hit := Game.raycast(muzzle, muzzle + dir * 220.0, Game.LAYER_WORLD | Game.MASK_HITTABLE, [player.get_rid()])
	var end := muzzle + dir * 220.0
	if not hit.is_empty():
		end = hit["position"]
		var c := hit["collider"] as Node
		if c and c.has_method("take_hit"):
			c.take_hit(Game.hit_info(damage * player.damage_mult, dir * 3.0, player, "bullet"))
			Game.fx.splat(end, -dir, Color(0.5, 0.02, 0.02), 4)
		else:
			Game.fx.debris(end, 2)
	Game.fx.tracer(muzzle, end)
	Game.fx.flash_light(muzzle, Color(1, 0.8, 0.4), 3.0, 6.0, 0.05)
	Game.fx.sound("gunshot", muzzle, -4.0 if weapon == "rifle" else -1.0)
	player.add_trauma(kick)


## Rocket launcher lock-on (Prototype 1): hold Aim on a tank or gunship and the rockets home in.
func _update_lock() -> void:
	if not Input.is_action_pressed("special"):
		lock_target = null
		_lock_on = null
		_lock_t = 0.0
		return
	var cam_pos: Vector3 = player.camera.global_position
	var look: Vector3 = player.aim_direction()
	var best: Node3D = null
	var best_ang := deg_to_rad(7.0)
	for v in get_tree().get_nodes_in_group("vehicles"):   # tanks, trucks and gunships
		var n := v as Node3D
		if n == null or n == player.vehicle or (n.has_method("is_alive") and not n.is_alive()):
			continue
		var to := n.global_position - cam_pos
		if to.length() > LOCK_RANGE:
			continue
		var ang := look.angle_to(to)
		if ang < best_ang and Game.line_of_sight(cam_pos, n.global_position + Vector3.UP):
			best_ang = ang
			best = n
	if best != _lock_on:
		_lock_on = best
		_lock_t = 0.0
		if lock_target != best:
			lock_target = null
	if best == null:
		return
	_lock_t += get_physics_process_delta_time()
	if lock_target == null and _lock_t >= LOCK_TIME:
		lock_target = best
		Game.fx.sound_ui("zap", -6.0)


# ------------------------------------------------------------------ controller rumble

func rumble(weak: float, strong: float, duration: float) -> void:
	if not Settings.rumble:
		return
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, clampf(weak, 0, 1), clampf(strong, 0, 1), duration)
