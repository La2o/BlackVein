extends Node
## Global game state, shared helpers and the event bus.
## Everything that several systems need (the player, the city, alert level,
## XP, skills, saving, damage helpers) lives here so scripts can find each other.

signal notify(text: String, color: Color)
signal event_feed(text: String, color: Color)
signal alert_changed(level: int)
signal xp_changed
signal level_up(new_level: int)
signal player_died
signal player_respawned

# Physics layers (as bit values)
const LAYER_WORLD := 1      # buildings, ground, rooftop props
const LAYER_PLAYER := 2
const LAYER_PROPS := 4      # cars, crates
const LAYER_NPC := 8        # people, infected, hunters
const LAYER_VEHICLE := 16   # tanks, trucks, helicopters
const LAYER_PICKUP := 32    # weapons, supply crates
const LAYER_HIVE := 64      # infection hives

const MASK_HITTABLE := LAYER_PROPS | LAYER_NPC | LAYER_VEHICLE | LAYER_HIVE

enum Alert { HIDDEN, SEARCHING, ALERT }

var player: Player
var city: City
var hud: CanvasLayer
var fx: Node3D
var world: Node3D
var military: Node
var director: Node
var daynight: Node

var alert_level: int = Alert.HIDDEN
var heat := 0.0                  # 0..5, how hard the military is pushing
var last_known_pos := Vector3.ZERO
var suspicion := 0.0             # 0..1 while hidden; full = alert
var time_since_seen := 999.0
var search_timer := 0.0

# ---- progression: XP -> levels -> skill points -> skills
var xp := 0                 # progress inside the current level
var total_xp := 0
var level := 1
var skill_points := 1
var skills := {}            # skill id -> rank
var flags := {}             # story/unlock flags, e.g. "artillery_codes"
var stats := {}             # counters: consumes, wall_runs, events, tanks, bosses...
var goal_index := 0
var _goal_timer := 0.0

## Starter goals that teach the game and pay XP. [stat or check, target, text, xp]
const GOALS := [
	["wall_runs", 1, "Sprint into a building to run up it", 40],
	["super_jumps", 1, "Hold jump to charge a super jump", 40],
	["consumes", 1, "Consume someone (F / LB)", 60],
	["level", 2, "Reach level 2", 50],
	["skills", 1, "Unlock a skill in the Skills menu (Tab / Back)", 60],
	["events", 1, "Complete a world event (follow the compass markers)", 120],
	["military_kills", 10, "Take down 10 soldiers", 120],
	["tanks", 1, "Destroy or hijack a tank", 150],
	["flag:artillery_codes", 1, "Raid the military base and consume its commander", 250],
	["level", 10, "Reach level 10", 300],
	["bosses", 1, "Defeat a boss (they appear from level 10)", 500],
	["level", 25, "Reach level 25", 800],
]
var play_time := 0.0
var autosave_timer := 45.0
const MAX_LEVEL := 50
const SAVE_PATH := "user://blackvein_save.json"

## id: [name, description, category, cost per rank, min level, max rank, requires]
const SKILLS := {
	"glide": ["Glide", "Hold jump in the air to glide", "Movement", 1, 2, 1, ""],
	"air_dash": ["Air Dash", "Dash in mid-air", "Movement", 1, 2, 1, ""],
	"tether": ["Tether", "Zip to any surface, yank enemies to you, latch onto helicopters", "Movement", 2, 4, 1, ""],
	"wings": ["Tendril Wings", "While gliding, press jump to flap upward. More flaps per rank", "Movement", 2, 15, 3, "glide"],
	"agility": ["Agility", "+10% sprint and wall-run speed per rank", "Movement", 1, 1, 5, ""],
	"leap": ["Leap", "Higher super jumps and longer glides per rank", "Movement", 1, 1, 5, ""],
	"claws": ["Claws", "Lightning-fast slashes. Special: Spike Line", "Forms", 1, 2, 1, ""],
	"hammer": ["Hammerfist", "Huge, slow hits that crush vehicles. Special: Ground Slam", "Forms", 2, 5, 1, ""],
	"blade": ["Blade", "Long reach, cuts tanks apart. Special: Whirlwind", "Forms", 2, 7, 1, ""],
	"whip": ["Whipfist", "Lash enemies from far away. Special: Whip Grab", "Forms", 2, 9, 1, ""],
	"muscle_form": ["Musclemass", "Send people flying, throw farther. Special: Thunderclap", "Forms", 2, 11, 1, ""],
	"shield": ["Shield", "Block bullets and rockets from the front", "Defense", 2, 6, 1, ""],
	"armor": ["Armor", "Take less damage and ram through anything", "Defense", 2, 8, 1, ""],
	"thermal": ["Thermal Vision", "See warm bodies through smoke and darkness", "Abilities", 1, 3, 1, ""],
	"dive": ["Dive Bomb", "Attack in mid-air to slam down with a shockwave", "Abilities", 1, 3, 1, ""],
	"focus": ["Focus", "Slow down time (drains biomass)", "Abilities", 2, 10, 1, ""],
	"decoy": ["Biomass Decoy", "A clone that draws enemy fire, then explodes", "Abilities", 2, 12, 1, ""],
	"artillery": ["Artillery Strike", "While disguised as a soldier, call a barrage on where you aim. Needs codes from a base commander", "Abilities", 2, 8, 1, "flag:artillery_codes"],
	"groundspike": ["Groundspike", "Devastator: rings of spikes erupt around you", "Devastators", 3, 14, 1, ""],
	"tendrils": ["Tendril Barrage", "Devastator: tendrils skewer everything nearby", "Devastators", 3, 18, 1, "groundspike"],
	"vitality": ["Vitality", "+20% maximum health per rank", "Body", 1, 1, 5, ""],
	"biomass": ["Biomass", "+30 biomass capacity per rank", "Body", 1, 1, 5, ""],
	"muscle": ["Muscle", "+15% damage per rank", "Body", 1, 1, 5, ""],
	"regen": ["Regeneration", "Heal faster and to a higher level per rank", "Body", 1, 1, 5, ""],
}
const CATEGORIES := ["Movement", "Forms", "Defense", "Abilities", "Devastators", "Body"]

var kills := {"military": 0, "infected": 0, "civilian": 0}
var combo := 0
var combo_timer := 0.0
var best_combo := 0
var boss: Node3D = null          # set while a boss fight is running (HUD shows its health)
var npc_count := 0               # updated every second; spawners back off when the city is crowded
const NPC_CAP := 130
var hit_stop_timer := 0.0
var focus_active := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	get_tree().set_auto_accept_quit(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()


func reset_state() -> void:
	alert_level = Alert.HIDDEN
	heat = 0.0
	suspicion = 0.0
	time_since_seen = 999.0
	xp = 0
	total_xp = 0
	level = 1
	skill_points = 1
	skills = {}
	flags = {}
	stats = {}
	goal_index = 0
	play_time = 0.0
	best_combo = 0
	kills = {"military": 0, "infected": 0, "civilian": 0}


func _process(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	if hit_stop_timer > 0.0:
		hit_stop_timer -= real_delta
		if hit_stop_timer <= 0.0:
			_apply_time_scale()
	if get_tree().paused:
		return
	play_time += real_delta
	_goal_timer -= real_delta
	if _goal_timer <= 0.0:
		_goal_timer = 0.5
		_check_goal()
		npc_count = get_tree().get_nodes_in_group("npcs").size()
	if combo > 0:
		combo_timer -= real_delta
		if combo_timer <= 0.0:
			_end_combo()
	autosave_timer -= real_delta
	if autosave_timer <= 0.0:
		save_game()
		autosave_timer = 45.0
	_update_alert(real_delta)


# ---------------------------------------------------------------- time

func hit_stop(duration: float) -> void:
	if hit_stop_timer > 0.0:
		return
	hit_stop_timer = duration
	Engine.time_scale = 0.05


func set_focus(on: bool) -> void:
	focus_active = on
	_apply_time_scale()


func _apply_time_scale() -> void:
	if hit_stop_timer > 0.0:
		return
	Engine.time_scale = 0.35 if focus_active else 1.0


# ---------------------------------------------------------------- notifications

func say(text: String, color := Color.WHITE) -> void:
	notify.emit(text, color)


func feed(text: String, color := Color(1, 0.85, 0.6)) -> void:
	event_feed.emit(text, color)


# ---------------------------------------------------------------- stats and goals

func stat_add(key: String, amount := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


func stat(key: String) -> int:
	return int(stats.get(key, 0))


func _goal_progress(g: Array) -> int:
	var key: String = g[0]
	if key == "level":
		return level
	if key == "skills":
		return skills.size()
	if key == "military_kills":
		return int(kills.get("military", 0))
	if key.begins_with("flag:"):
		return 1 if flags.get(key.substr(5), false) else 0
	return stat(key)


func current_goal_text() -> String:
	if goal_index >= GOALS.size():
		return ""
	var g: Array = GOALS[goal_index]
	var target: int = g[1]
	var prog := mini(_goal_progress(g), target)
	var count := "  (%d/%d)" % [prog, target] if target > 1 and g[0] != "level" else ""
	return "%s%s  ·  +%d XP" % [g[2], count, int(g[3])]


func _check_goal() -> void:
	if goal_index >= GOALS.size() or player == null:
		return
	var g: Array = GOALS[goal_index]
	if _goal_progress(g) >= int(g[1]):
		goal_index += 1
		feed("Goal complete: " + str(g[2]), Color(1, 0.9, 0.5))
		add_xp(int(g[3]), "Goal")
		if fx:
			fx.sound_ui("pickup", 0.0)


# ---------------------------------------------------------------- combos

const COMBO_RANKS := [[60, "SAVAGE"], [40, "S"], [25, "A"], [15, "B"], [8, "C"], [0, "D"]]


## Called whenever the player lands a hit. Long chains of hits pay bonus XP.
func register_hit() -> void:
	combo += 1
	combo_timer = 2.6
	best_combo = maxi(best_combo, combo)


func combo_rank() -> String:
	for r in COMBO_RANKS:
		if combo >= int(r[0]):
			return r[1]
	return "D"


func _end_combo() -> void:
	if combo >= 8:
		add_xp(int(combo * 1.5), "%s combo  x%d" % [combo_rank(), combo])
	combo = 0


# ---------------------------------------------------------------- progression

func xp_to_next(lvl: int) -> int:
	return int(100.0 + 55.0 * pow(float(lvl - 1), 1.45))


func points_for_level(lvl: int) -> int:
	return 2 if lvl % 5 == 0 else 1


func add_xp(amount: int, reason := "") -> void:
	if amount <= 0:
		return
	total_xp += amount
	xp += amount
	if reason != "":
		feed("+%d XP  %s" % [amount, reason], Color(0.7, 1.0, 0.6))
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		var pts := points_for_level(level)
		skill_points += pts
		say("LEVEL %d  ·  +%d skill point%s" % [level, pts, "s" if pts > 1 else ""], Color(1, 0.85, 0.3))
		if fx:
			fx.sound_ui("evolve", 0.0)
		level_up.emit(level)
		save_game()
	xp_changed.emit()


## Old name kept so every reward call site works.
func add_ep(amount: int, reason := "") -> void:
	add_xp(amount, reason)


func has_skill(id: String) -> bool:
	return int(skills.get(id, 0)) > 0


func skill_rank(id: String) -> int:
	return int(skills.get(id, 0))


## Empty string when the skill can be bought, otherwise the reason it can't.
func skill_block_reason(id: String) -> String:
	var s: Array = SKILLS[id]
	if skill_rank(id) >= int(s[5]):
		return "Maxed"
	if level < int(s[4]):
		return "Needs level %d" % int(s[4])
	var req: String = s[6]
	if req.begins_with("flag:"):
		if not flags.get(req.substr(5), false):
			return "Consume a base commander"
	elif req != "" and not has_skill(req):
		return "Needs " + SKILLS[req][0]
	if skill_points < int(s[3]):
		return "Needs %d point%s" % [int(s[3]), "s" if int(s[3]) > 1 else ""]
	return ""


func unlock_skill(id: String) -> bool:
	if skill_block_reason(id) != "":
		return false
	skill_points -= int(SKILLS[id][3])
	skills[id] = skill_rank(id) + 1
	if player and player.has_method("apply_upgrades"):
		player.apply_upgrades()
	var s: Array = SKILLS[id]
	if int(s[5]) > 1:
		say("%s rank %d" % [s[0], skill_rank(id)], Color(0.7, 1, 0.6))
	else:
		say("Unlocked: %s" % s[0], Color(0.7, 1, 0.6))
	save_game()
	return true


func locked_message(id: String) -> void:
	var s: Array = SKILLS[id]
	say("%s is locked  ·  unlock it in Skills (level %d)" % [s[0], int(s[4])], Color(1, 0.6, 0.5))


# ---------------------------------------------------------------- saving

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(announce := false) -> void:
	if player == null or not is_instance_valid(player) or player.is_dead():
		return
	var pw: Node = player.powers
	var data := {
		"version": 1,
		"level": level, "xp": xp, "total_xp": total_xp, "skill_points": skill_points,
		"skills": skills, "kills": kills, "play_time": play_time, "flags": flags, "best_combo": best_combo,
		"stats": stats, "goal_index": goal_index,
		"hour": daynight.hour if daynight else 16.0,
		"player": {
			"pos": [player.global_position.x, player.global_position.y, player.global_position.z],
			"health": player.health, "biomass": player.biomass, "disguise": player.disguise,
			"form": pw.form, "defense": pw.defense,
		},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	autosave_timer = 45.0
	if announce:
		say("Game saved", Color(0.8, 0.9, 1))


func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	total_xp = int(d.get("total_xp", 0))
	skill_points = int(d.get("skill_points", 1))
	skills = {}
	var saved_skills: Dictionary = d.get("skills", {})
	for k in saved_skills:
		if SKILLS.has(k):
			skills[k] = int(saved_skills[k])
	var saved_kills: Dictionary = d.get("kills", {})
	for k in saved_kills:
		kills[k] = int(saved_kills[k])
	play_time = float(d.get("play_time", 0.0))
	flags = d.get("flags", {})
	stats = d.get("stats", {})
	goal_index = int(d.get("goal_index", 0))
	best_combo = int(d.get("best_combo", 0))
	if daynight:
		daynight.hour = float(d.get("hour", 16.0))
	var pd: Dictionary = d.get("player", {})
	if player:
		player.apply_upgrades()
		var pos: Array = pd.get("pos", [])
		if pos.size() == 3:
			var p := Vector3(pos[0], pos[1], pos[2])
			if city and city.is_inside_building(p, 0.2):
				p = city.random_roof_point(p, 0.0, 200.0)
			player.respawn(p + Vector3.UP * 0.5)
		player.health = clampf(float(pd.get("health", player.max_health)), 20.0, player.max_health)
		player.biomass = float(pd.get("biomass", 60.0))
		player.health_changed.emit(player.health, player.max_health)
		var pw: Node = player.powers
		var form_i := int(pd.get("form", 0))
		if pw.form_unlocked(form_i):
			pw.set_form(form_i, true)
		var def_i := int(pd.get("defense", 0))
		if pw.defense_unlocked(def_i):
			pw.defense = def_i
			player.model.set_defense(def_i)
	xp_changed.emit()
	say("Welcome back  ·  Level %d" % level, Color(1, 0.85, 0.6))
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func new_game() -> void:
	delete_save()
	reset_state()
	get_tree().paused = false
	Engine.time_scale = 1.0
	focus_active = false
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- alert system

## Called by soldiers, tanks and helicopters when they can see the player.
func report_sighting(pos: Vector3, conspicuous: bool, observer_pos: Vector3, delta: float, thermal := false) -> void:
	if alert_level == Alert.HIDDEN:
		if not conspicuous and not thermal:
			return
		var dist := observer_pos.distance_to(pos)
		var rate := lerpf(2.5, 0.5, clampf(dist / 70.0, 0.0, 1.0))
		if thermal:
			rate *= 2.0
		elif player and str(player.disguise) in ["soldier", "rocket_soldier", "elite"]:
			rate *= 0.5
		suspicion += rate * delta
		if suspicion >= 1.0:
			raise_alert(pos, "Spotted by the military")
		return
	# Already searching or alerted: any sighting keeps them on you.
	if alert_level == Alert.SEARCHING and not conspicuous and not thermal:
		# A calm, disguised player can slip past searching units.
		return
	if alert_level == Alert.SEARCHING:
		set_alert(Alert.ALERT)
		say("They found you", Color(1, 0.3, 0.25))
	last_known_pos = pos
	time_since_seen = 0.0


## Instantly go to full alert (attacking soldiers, being seen consuming, etc.)
func raise_alert(pos: Vector3, reason := "") -> void:
	last_known_pos = pos
	time_since_seen = 0.0
	suspicion = 1.0
	if alert_level != Alert.ALERT:
		set_alert(Alert.ALERT)
		heat = maxf(heat, 1.0)
		if reason != "":
			say(reason, Color(1, 0.3, 0.25))


## Low-level players face a gentler military; it grows with you.
func max_heat() -> float:
	return clampf(1.6 + level * 0.3, 1.6, 5.0)


func add_heat(amount: float) -> void:
	if alert_level == Alert.ALERT:
		var before := int(heat)
		heat = minf(max_heat(), heat + amount)
		if int(heat) > before:
			feed("Military response increased", Color(1, 0.45, 0.35))


func set_alert(level: int) -> void:
	if level == alert_level:
		return
	alert_level = level
	if level == Alert.HIDDEN:
		suspicion = 0.0
	if level == Alert.SEARCHING:
		search_timer = 22.0
	alert_changed.emit(level)


## Changing disguise while nobody is looking makes the military lose you.
func disguise_changed_unseen() -> void:
	if alert_level != Alert.HIDDEN and time_since_seen > 0.6:
		set_alert(Alert.HIDDEN)
		heat = maxf(0.0, heat - 1.5)
		say("Disguise changed. They lost you.", Color(0.6, 0.9, 1))


func _update_alert(delta: float) -> void:
	time_since_seen += delta
	match alert_level:
		Alert.HIDDEN:
			suspicion = maxf(0.0, suspicion - delta * 0.35)
			heat = maxf(0.0, heat - delta * 0.05)
		Alert.ALERT:
			if time_since_seen > 9.0:
				set_alert(Alert.SEARCHING)
				say("Out of sight. They're searching for you.", Color(1, 0.85, 0.3))
		Alert.SEARCHING:
			search_timer -= delta
			if search_timer <= 0.0:
				set_alert(Alert.HIDDEN)
				say("They gave up the search", Color(0.6, 0.9, 1))


func is_hunted() -> bool:
	return alert_level == Alert.ALERT


# ---------------------------------------------------------------- damage helpers

## Builds a hit description passed to take_hit() on anything damageable.
func hit_info(damage: float, force: Vector3, source: Node, kind := "melee") -> Dictionary:
	return {"damage": damage, "force": force, "source": source, "kind": kind}


## Damage and push everything in a sphere. Used by explosions, slams and devastators.
func damage_area(center: Vector3, radius: float, damage: float, force: float, source: Node,
		kind := "explosion", mask := MASK_HITTABLE | LAYER_PLAYER, up_bias := 0.6) -> int:
	var space := get_viewport().get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), center)
	q.collision_mask = mask
	q.collide_with_areas = false
	var results := space.intersect_shape(q, 64)
	var hit_count := 0
	var seen := {}
	for r in results:
		var body: Object = r["collider"]
		if body == null or seen.has(body) or body == source:
			continue
		seen[body] = true
		var node := body as Node3D
		if node == null:
			continue
		var off := node.global_position - center
		var dist := off.length()
		var falloff := 1.0 - clampf(dist / radius, 0.0, 1.0) * 0.7
		var dir := Vector3(off.x, 0, off.z)
		if dir.length() < 0.01:
			dir = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		dir = (dir.normalized() + Vector3.UP * up_bias).normalized()
		if node.has_method("take_hit"):
			node.take_hit(hit_info(damage * falloff, dir * force * falloff, source, kind))
			hit_count += 1
		elif node is RigidBody3D:
			var rb := node as RigidBody3D
			rb.apply_central_impulse(dir * force * falloff * rb.mass * 0.6)
	return hit_count


## Full explosion: visuals, sound, damage, camera shake and panic.
func explode(center: Vector3, radius: float, damage: float, source: Node = null, force := 22.0) -> void:
	if fx:
		fx.explosion(center, radius)
	damage_area(center, radius, damage, force, source, "explosion")
	if player and player.has_method("add_trauma"):
		var d := player.global_position.distance_to(center)
		player.add_trauma(clampf(1.0 - d / (radius * 6.0), 0.0, 0.8))
	panic_at(center, radius * 5.0)


## Tell nearby civilians to run.
func panic_at(center: Vector3, radius: float) -> void:
	for g in ["civilians", "traffic"]:
		for n in get_tree().get_nodes_in_group(g):
			var c := n as Node3D
			if c and c.global_position.distance_to(center) < radius and c.has_method("panic"):
				c.panic(center)


# ---------------------------------------------------------------- queries

func raycast(from: Vector3, to: Vector3, mask: int, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return get_viewport().get_world_3d().direct_space_state.intersect_ray(q)


## True if nothing solid (buildings) is between the two points.
func line_of_sight(from: Vector3, to: Vector3) -> bool:
	return raycast(from, to, LAYER_WORLD).is_empty()


func units_in_group(group: String) -> Array:
	return get_tree().get_nodes_in_group(group)


func nearest_in_group(group: String, pos: Vector3, max_dist := INF, filter := Callable()) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group(group):
		var node := n as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if filter.is_valid() and not filter.call(node):
			continue
		var d := node.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = node
	return best
