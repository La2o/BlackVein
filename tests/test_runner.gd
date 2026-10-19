extends Node
## Automated gameplay checks. Run from the project folder with:
##   godot --headless --path . res://tests/test_runner.tscn
## It plays through movement, combat, powers, vehicles, events and saving,
## prints PASS/FAIL for each check, and quits with exit code 0 if all pass.
## Add "-- shots=<folder>" (without --headless) to also save screenshots.

const MAIN := preload("res://scenes/main.tscn")

var main: Node3D
var player: Player
var results: Array[String] = []
var failures := 0
var shots_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			shots_dir = a.substr(6)
	Game.use_test_storage()
	Game.delete_save()
	Game.reset_state()
	main = MAIN.instantiate()
	add_child(main)
	await _wait(0.5)
	player = Game.player
	await _run_all()
	print("\n==== RESULTS ====")
	for r in results:
		print(r)
	print("%d checks, %d failed" % [results.size(), failures])
	Game.delete_save()
	get_tree().quit(1 if failures > 0 else 0)


func check(name: String, ok: bool, detail := "") -> void:
	var line := ("PASS  " if ok else "FAIL  ") + name + ("  (" + detail + ")" if detail != "" else "")
	results.append(line)
	print(line)
	if not ok:
		failures += 1


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _release_all() -> void:
	for a in ["sprint", "move_forward", "move_back", "move_left", "move_right", "jump", "attack", "special", "grab",
			"consume", "dash", "tether", "focus", "decoy", "devastator_spikes", "devastator_tendrils", "cycle_defense"]:
		Input.action_release(a)


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _shot(name: String) -> void:
	if shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir.path_join(name + ".png"))


func _teleport(p: Vector3, yaw := 0.0) -> void:
	player.respawn(p)
	player.yaw = yaw
	player.invuln_timer = 0.0
	await _wait(0.1)


func _clear_units() -> void:
	for n in main.get_node("Units").get_children():
		n.queue_free()
	await get_tree().process_frame


func _give_all_skills() -> void:
	Game.level = 30
	for id in Game.SKILLS:
		Game.skills[id] = Game.SKILLS[id][5]
	player.apply_upgrades()


func _run_all() -> void:
	# ---------------- boot
	check("city built", Game.city.buildings.size() > 100, "%d buildings" % Game.city.buildings.size())
	var kinds := {}
	for c in Game.city.districts:
		kinds[Game.city.districts[c]] = true
	check("the map has every kind of district", kinds.size() == City.District.size(), str(kinds.keys()))
	check("farmland north, industry east, suburbs south", Game.city.district_at(Vector3(0, 0, -400)) == City.District.FARM
		and Game.city.district_at(Vector3(400, 0, 0)) == City.District.INDUSTRIAL
		and Game.city.district_at(Vector3(0, 0, 400)) == City.District.SUBURB
		and Game.city.district_at(Game.city.spawn_point) == City.District.DOWNTOWN)
	check("navigation ready", Game.city.nav_ready)
	# the navigation map is built in the background; on the big map that takes a moment
	var path := PackedVector3Array()
	var waited := 0.0
	while waited < 5.0:
		path = Game.city.nav_path(Game.city.spawn_point, Game.city.spawn_point + Vector3(120, 0, 60))
		if path.size() > 2:
			break
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	check("nav path around blocks", path.size() > 2, "%d points after %.1f s" % [path.size(), waited])
	await _wait(1.5)
	check("player landed at spawn", player.state == Player.State.GROUND, "state %s" % Player.STATE_NAMES[player.state])
	await _shot("01_spawn")
	# keep the director quiet during scripted checks
	Game.director.set_process(false)
	Game.military.set_process(false)
	await _clear_units()

	# ---------------- wall run up a building
	var target := {}
	var start := Vector3.ZERO
	var best := INF
	for b in Game.city.buildings:
		var a: AABB = b["aabb"]
		if a.size.y < 25.0 or a.size.y > 60.0 or absf(a.get_center().x) > 200.0 or absf(a.get_center().z) > 200.0:
			continue
		var s0 := Vector3(a.position.x - 5.0, 1.2, a.get_center().z)
		if Game.city.is_inside_building(s0, 1.0):
			continue
		var hit := Game.raycast(s0, s0 + Vector3(8, 0, 0), Game.LAYER_WORLD)
		if hit.is_empty() or absf(float(hit["position"].x) - a.position.x) > 0.2:
			continue
		var d := a.get_center().distance_to(Game.city.spawn_point)
		if d < best:
			best = d
			target = b
			start = s0
	var aabb: AABB = target["aabb"]
	await _teleport(start, -PI * 0.5)   # yaw -90 deg looks toward +X
	await _wait(0.4)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	var max_y := 0.0
	var saw_wall := false
	var t := 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		max_y = maxf(max_y, player.global_position.y)
		if player.state == Player.State.GROUND and saw_wall and player.global_position.y > float(target["height"]) - 2.0:
			break
		if player.state == Player.State.WALL:
			saw_wall = true
			if t > 1.0 and t < 1.1:
				await _shot("02_wallrun")
	_release_all()
	await _wait(1.0)
	var roof: float = target["height"]
	check("wall run starts", saw_wall)
	check("climbed to the roof", max_y > roof - 1.0, "max %.1f roof %.1f" % [max_y, roof])
	check("standing on the roof", absf(player.global_position.y - (roof + 0.9)) < 3.5 and player.state == Player.State.GROUND,
		"y %.1f state %s" % [player.global_position.y, Player.STATE_NAMES[player.state]])
	await _shot("03_roof")

	# ---------------- super jump
	await _teleport(Game.city.spawn_point)
	await _wait(0.8)
	var y0 := player.global_position.y
	Input.action_press("jump")
	var coil_pose := false
	var squash := INF
	for f in 14:
		await get_tree().physics_frame
		if player.charging:
			coil_pose = coil_pose or player.coiling
			squash = minf(squash, player.model.scale.y)
	check("holding jump plays the charge-up coil", coil_pose and squash < 0.97, "pose %s, squash %.2f" % [coil_pose, squash])
	await _wait(0.52)
	Input.action_release("jump")
	max_y = 0.0
	t = 0.0
	while t < 2.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		max_y = maxf(max_y, player.global_position.y)
	check("charged super jump is high", max_y - y0 > 20.0, "%.1f m" % (max_y - y0))
	await _wait(1.5)

	# ---------------- running jump keeps speed
	await _teleport(Game.city.spawn_point, PI * 0.5)
	await _wait(0.5)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _wait(1.2)
	var run_speed := Vector3(player.velocity.x, 0, player.velocity.z).length()
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var left_ground := player.state == Player.State.AIR
	await _wait(0.15)
	var air_speed := Vector3(player.velocity.x, 0, player.velocity.z).length()
	_release_all()
	check("jump while running leaves the ground instantly", left_ground)
	check("jump while running keeps your speed", air_speed >= run_speed * 0.95, "%.1f -> %.1f m/s" % [run_speed, air_speed])
	await _wait(3.0)

	# ---------------- sprinting over a low wall is one seamless vault
	await _teleport(Game.city.spawn_point, PI * 0.5)
	await _wait(0.5)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _wait(1.0)
	var run_dir := Vector3(player.velocity.x, 0, player.velocity.z).normalized()
	var feet_y := player.global_position.y - 0.9
	var block := StaticBody3D.new()
	block.collision_layer = Game.LAYER_WORLD
	var block_shape := CollisionShape3D.new()
	var block_box := BoxShape3D.new()
	block_box.size = Vector3(4.0, 1.3, 2.5)
	block_shape.shape = block_box
	block.add_child(block_shape)
	main.add_child(block)
	var block_at := player.global_position + run_dir * 16.0
	block.global_position = Vector3(block_at.x, feet_y + 0.65, block_at.z)
	block.look_at(block.global_position + run_dir, Vector3.UP)
	var vaults0 := int(Game.stats.get("vaults", 0))
	var min_speed := INF
	var went_wall := false
	t = 0.0
	while t < 1.6:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		min_speed = minf(min_speed, Vector3(player.velocity.x, 0, player.velocity.z).length())
		went_wall = went_wall or player.state == Player.State.WALL
	var past := (player.global_position - block.global_position).dot(run_dir)
	_release_all()
	block.queue_free()
	check("sprinting at a low wall vaults it", int(Game.stats.get("vaults", 0)) > vaults0 and past > 2.0 and not went_wall,
		"%.1f m past, wall %s" % [past, went_wall])
	check("vaulting never slows the run", min_speed > player.sprint_speed * 0.85, "slowest %.1f m/s" % min_speed)
	await _wait(1.0)

	# ---------------- running onto a curb (side streets) never stops you
	for walk in [false, true]:
		await _teleport(Game.city.spawn_point, PI * 0.5)
		await _wait(0.5)
		if not walk:
			Input.action_press("sprint")
		Input.action_press("move_forward")
		await _wait(1.0)
		var cdir := Vector3(player.velocity.x, 0, player.velocity.z).normalized()
		var speed0 := Vector3(player.velocity.x, 0, player.velocity.z).length()
		var cfeet := player.global_position.y - 0.9
		var curb := StaticBody3D.new()
		curb.collision_layer = Game.LAYER_WORLD
		var curb_shape := CollisionShape3D.new()
		var curb_box := BoxShape3D.new()
		curb_box.size = Vector3(30.0, 0.15, 30.0)
		curb_shape.shape = curb_box
		curb.add_child(curb_shape)
		main.add_child(curb)
		var curb_at := player.global_position + cdir * (4.0 + speed0 * 0.3 + 15.0)
		curb.global_position = Vector3(curb_at.x, cfeet + 0.075, curb_at.z)
		curb.look_at(curb.global_position + cdir.rotated(Vector3.UP, 0.5), Vector3.UP)   # met at an angle
		var slowest := INF
		t = 0.0
		while t < 1.2:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			slowest = minf(slowest, Vector3(player.velocity.x, 0, player.velocity.z).length())
		var on_top := player.global_position.y - 0.9 > cfeet + 0.1 and player.state == Player.State.GROUND
		_release_all()
		curb.queue_free()
		check("%s onto a curb keeps going" % ("walking" if walk else "sprinting"), on_top and slowest > speed0 * 0.8,
			"slowest %.1f of %.1f m/s, on top %s" % [slowest, speed0, on_top])
		await _wait(0.5)

	# ---------------- controller works on any device id
	var joy := InputEventJoypadMotion.new()
	joy.device = 3
	joy.axis = JOY_AXIS_LEFT_Y
	joy.axis_value = -1.0
	Input.parse_input_event(joy)
	await get_tree().physics_frame
	check("controller stick moves you (any device)", Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.5)
	joy.axis_value = 0.0
	Input.parse_input_event(joy)
	await get_tree().physics_frame

	# ---------------- tap jump is small
	y0 = player.global_position.y
	await _tap("jump")
	max_y = 0.0
	t = 0.0
	while t < 1.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		max_y = maxf(max_y, player.global_position.y)
	check("tap jump is a normal hop", max_y - y0 > 1.0 and max_y - y0 < 5.0, "%.1f m" % (max_y - y0))
	await _wait(0.8)

	# ---------------- glide is locked until unlocked
	await _teleport(Game.city.spawn_point + Vector3(0, 60, 0))
	await _tap("jump")
	Input.action_press("jump")
	await _wait(1.2)
	check("glide locked at level 1", player.state != Player.State.GLIDE)
	_release_all()
	_give_all_skills()
	await _teleport(Game.city.spawn_point + Vector3(0, 60, 0))
	await _tap("jump")
	Input.action_press("jump")
	await _wait(1.5)
	check("glide works after unlocking", player.state == Player.State.GLIDE and player.velocity.y > -6.0,
		"state %s vy %.1f" % [Player.STATE_NAMES[player.state], player.velocity.y])
	await _shot("04_glide")
	_release_all()

	# ---------------- acrobatics
	await _teleport(Game.city.spawn_point + Vector3(0, 30, 0))
	await _tap("jump")
	await _wait(0.1)
	await _tap("jump")
	check("double jump does a flip", player.trick in ["frontflip", "corkscrew", "sideflip"], player.trick)
	_release_all()
	await _teleport(Game.city.spawn_point + Vector3(0, 45, 0))
	var saw_hero := false
	for i in 240:
		await get_tree().physics_frame
		if player._hero_t > 0.0:
			saw_hero = true
			break
	check("big landing strikes a superhero pose", saw_hero)
	await _wait(0.8)

	# ---------------- body-part forms
	var pw := player.powers
	pw.set_legs(PlayerPowers.Legs.RUNNER)
	check("runner legs sprint faster", pw.speed_factor() > 1.3 and not player.model._leg_parts.is_empty())
	await _teleport(Game.city.spawn_point)
	await _wait(0.4)
	var peaks := []
	for l in [PlayerPowers.Legs.NORMAL, PlayerPowers.Legs.LEAPER]:
		pw.set_legs(l)
		await _wait(0.3)
		var jy0 := player.global_position.y
		await _tap("jump")
		var peak := jy0
		for i in 120:
			await get_tree().physics_frame
			peak = maxf(peak, player.global_position.y)
		peaks.append(peak - jy0)
		await _wait(0.6)
	check("leaper legs jump much higher", peaks[1] > peaks[0] * 1.6, "%.1f m vs %.1f m" % [peaks[1], peaks[0]])
	pw.set_legs(PlayerPowers.Legs.CRAWLER)
	await _teleport(start, -PI * 0.5)
	await _wait(0.3)
	Input.action_press("move_forward")
	await _wait(1.2)
	Input.action_release("move_forward")
	var on_wall := player.state == Player.State.WALL
	await _wait(1.0)
	check("crawler legs climb without sprinting and cling", on_wall and player.state == Player.State.WALL,
		"state %s" % Player.STATE_NAMES[player.state])
	_release_all()
	pw.set_legs(PlayerPowers.Legs.CRUSHER)
	check("crusher legs can't be knocked back", pw.unstoppable())
	pw.set_legs(PlayerPowers.Legs.NORMAL)
	pw.set_defense(PlayerPowers.Defense.WINGS)
	await _teleport(Game.city.spawn_point + Vector3(0, 70, 0))
	await _tap("jump")
	Input.action_press("jump")
	Input.action_press("move_forward")
	await _wait(2.0)
	var gspeed := Vector2(player.velocity.x, player.velocity.z).length()
	check("wings body form glides fast", player.state == Player.State.GLIDE and gspeed > player.glide_speed * 1.2,
		"%.1f m/s" % gspeed)
	check("wings are on your back", player.model._wing_pivots.size() == 2 and player.model._wing_pivots[0].visible)
	await _shot("04b_wings")
	_release_all()
	pw.set_defense(PlayerPowers.Defense.NONE)
	await _wait(3.0)

	# ---------------- creature forms: whole-body transformations
	Game.skills.erase("brute_form")
	pw.set_creature(PlayerPowers.Creature.BRUTE, true)
	check("creature forms are locked until learned", pw.creature == PlayerPowers.Creature.NONE)
	for cid in ["brute_form", "stalker_form", "wraith_form"]:
		Game.skills[cid] = 1
	player.biomass = player.max_biomass
	var human_hp := player.max_health
	var human_dmg := player.damage_mult
	var human_h: float = player.model.skeleton.get_parent().get_parent().scale.y
	await _tap("creature_form")
	check("N turns you into the Brute", pw.creature == PlayerPowers.Creature.BRUTE, PlayerPowers.CREATURE_NAMES[pw.creature])
	var brute_h: float = player.model.skeleton.get_parent().get_parent().scale.y
	check("a rebuilt body keeps animating", player.model.anim.is_playing(), player.model.anim.current_animation)
	check("the Brute is huge, hits harder and has more health", brute_h > human_h * 1.2
		and player.damage_mult > human_dmg * 1.4 and player.max_health > human_hp * 1.3 and pw.unstoppable(),
		"size %.2f->%.2f, damage %.2f->%.2f, health %.0f->%.0f" % [human_h, brute_h, human_dmg, player.damage_mult, human_hp, player.max_health])
	check("a creature always stands out", player.is_conspicuous())
	await _tap("creature_form")
	check("the Stalker is fast and clings to walls", pw.creature == PlayerPowers.Creature.STALKER
		and pw.speed_factor() > 1.3 and pw.clings_to_walls())
	await _tap("creature_form")
	check("the Wraith flies", pw.creature == PlayerPowers.Creature.WRAITH and player.max_flaps() > 100)
	await _tap("creature_form")
	check("and back to human", pw.creature == PlayerPowers.Creature.NONE and absf(player.max_health - human_hp) < 1.0)
	pw.set_creature(PlayerPowers.Creature.BRUTE, true)
	player.biomass = 0.5
	await _wait(0.5)
	check("running out of biomass turns you back", pw.creature == PlayerPowers.Creature.NONE)
	player.biomass = player.max_biomass

	# ---------------- Light Body: faster running and jumping, more damage taken
	Game.skills.erase("light_body")
	pw.set_defense(PlayerPowers.Defense.LIGHT, true)
	check("Light Body is locked until learned", pw.defense != PlayerPowers.Defense.LIGHT)
	Game.skills["light_body"] = 1
	var base_speed := pw.speed_factor()
	var base_jump := pw.jump_factor()
	var base_dmg := pw.modify_incoming(10.0, Game.hit_info(10.0, Vector3.ZERO, null, "bullet"))
	pw.set_defense(PlayerPowers.Defense.LIGHT, true)
	check("Light Body runs faster", pw.speed_factor() > base_speed * 1.2, "%.2f -> %.2f" % [base_speed, pw.speed_factor()])
	check("Light Body jumps higher", pw.jump_factor() > base_jump * 1.15, "%.2f -> %.2f" % [base_jump, pw.jump_factor()])
	check("Light Body takes more damage",
		pw.modify_incoming(10.0, Game.hit_info(10.0, Vector3.ZERO, null, "bullet")) > base_dmg * 1.2)
	await _teleport(Game.city.spawn_point, PI * 0.5)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _wait(1.2)
	var light_run := Vector3(player.velocity.x, 0, player.velocity.z).length()
	_release_all()
	check("Light Body sprint is faster in play", light_run > player.sprint_speed * 1.15, "%.1f m/s" % light_run)
	pw.set_defense(PlayerPowers.Defense.NONE, true)
	await _wait(1.0)
	await _clear_units()
	await _teleport(Game.city.spawn_point)
	var watcher: Node3D = Game.military.spawn_npc("soldier", player.global_position + Vector3(0, 0, -6))
	await _wait(0.2)
	pw.set_vision(PlayerPowers.Vision.PREDATOR)
	var over := watcher.model.torso.material_overlay as StandardMaterial3D
	check("predator sense shows soldiers through walls", over != null and over.no_depth_test)
	pw.set_vision(PlayerPowers.Vision.NIGHT)
	check("night vision", Game.hud._night_target == 1.0 and watcher.model.torso.material_overlay == null)
	pw.set_vision(PlayerPowers.Vision.NORMAL)
	await _clear_units()

	# ---------------- forms wheel, used like a player: hold the button, point, let go
	Input.action_press("forms_wheel")
	for f in 10:
		await get_tree().physics_frame
		if Game.hud.wheel_open:
			break
	check("forms wheel opens in slow motion", Game.hud.wheel_open and Engine.time_scale < 0.2,
		"time %.2f open %s paused %s menu %s hitstop %.2f dead %s" % [Engine.time_scale, Game.hud.wheel_open,
		get_tree().paused, Game.hud._any_menu_open(), Game.hit_stop_timer, player.is_dead()])
	var wh: Control = Game.hud.wheel
	for i in wh.entries.size():
		if wh.entries[i]["part"] == "legs" and wh.entries[i]["index"] == PlayerPowers.Legs.LEAPER:
			var a: float = wh._start_angle() + (i + 0.5) * wh._step()
			wh._cursor = Vector2(cos(a), sin(a)) * 150.0   # what a mouse or stick does
	await get_tree().process_frame
	Input.action_release("forms_wheel")
	for f in 120:
		await get_tree().process_frame
		if not Game.hud.wheel_open:
			break
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("forms wheel switches forms", pw.legs == PlayerPowers.Legs.LEAPER and not Game.hud.wheel_open and Engine.time_scale > 0.9,
		"legs %d open %s time %.2f hitstop %.2f focus %s" % [pw.legs, Game.hud.wheel_open, Engine.time_scale, Game.hit_stop_timer, Game.focus_active])
	pw.set_legs(PlayerPowers.Legs.NORMAL)

	# ---------------- heavy landing shoves cars
	await _clear_units()
	var car: Node3D = Game.nearest_in_group("cars", Game.city.spawn_point, 60.0)
	var car_pos := car.global_position
	await _teleport(car_pos + Vector3(4, 45, 0))
	await _wait(3.0)
	check("heavy landing sends cars flying", car.global_position.distance_to(car_pos) > 1.0,
		"moved %.1f m" % car.global_position.distance_to(car_pos))

	# ---------------- fighting soldiers raises the alert and gives XP
	await _clear_units()
	await _wait(1.5)
	Game.set_alert(Game.Alert.HIDDEN)
	await _teleport(Game.city.spawn_point)
	await _wait(0.5)
	var xp_before := Game.total_xp
	var soldier: Node3D = Game.military.spawn_npc("soldier", player.global_position + Vector3(0, 0, -2.2))
	await _wait(0.3)
	for k in 12:
		if not is_instance_valid(soldier) or not soldier.is_alive():
			break
		player.yaw = atan2(-(soldier.global_position - player.global_position).x, -(soldier.global_position - player.global_position).z)
		await _tap("attack")
		await _wait(0.35)
	check("punching kills a soldier", not is_instance_valid(soldier) or not soldier.is_alive())
	check("attacking the military raises the alert", Game.alert_level == Game.Alert.ALERT)
	check("kills give XP", Game.total_xp > xp_before, "%d XP" % (Game.total_xp - xp_before))

	# ---------------- consume steals a disguise
	await _clear_units()
	player.powers.violence_timer = 0.0
	player.conspicuous_timer = 0.0
	var civ: Node3D = Game.military.spawn_npc("civilian", player.global_position + Vector3(0, 0, -1.5))
	await _wait(0.1)
	player.health = 30.0
	await _tap("consume")
	await _wait(1.3)
	check("consume finishes", not is_instance_valid(civ))
	check("consume heals", player.health > 45.0, "hp %.0f" % player.health)
	check("consume gives a disguise", player.disguise == "civilian")
	await _wait(0.5)

	# ---------------- Dominate: brand an ally
	await _clear_units()
	Game.set_alert(Game.Alert.HIDDEN)
	Game.skills["dominate"] = 1
	player.biomass = player.max_biomass
	var recruit: Node3D = Game.military.spawn_npc("soldier", player.global_position + Vector3(0, 0, -1.6))
	await _wait(0.2)
	await _tap("grab")
	await _wait(0.2)
	check("grab a soldier to brand", player.powers.held == recruit)
	await _tap("special")
	await _wait(1.2)
	check("branding makes an ally", is_instance_valid(recruit) and recruit.is_ally and recruit.is_in_group("allies"))
	var hp_ally: float = recruit.hp
	await _tap("attack")
	await _wait(0.5)
	check("you can't hurt your allies", recruit.hp >= hp_ally)
	var foe: Node3D = Game.military.spawn_npc("infected", player.global_position + Vector3(12, 0, 0))
	await _wait(6.0)
	check("allies fight the infected", not is_instance_valid(foe) or not foe.is_alive() or foe.hp < foe.max_hp)
	player.global_position += Vector3(40, 0, 0)
	await _wait(6.0)
	check("allies follow you", recruit.global_position.distance_to(player.global_position) < 30.0,
		"%.0f m away" % recruit.global_position.distance_to(player.global_position))
	await _clear_units()
	Game.set_alert(Game.Alert.HIDDEN)

	# ---------------- Bio-Bomb: plant one in someone you hold, throw them, they burst
	Game.skills["decoy"] = 1
	Game.skills["bio_bomb"] = 1
	player.biomass = player.max_biomass
	player.yaw = 0.0
	var bomb: Node3D = Game.military.spawn_npc("civilian", player.global_position + Vector3(0, 0, -1.6))
	var bystanders: Array = []
	for k in 3:
		bystanders.append(Game.military.spawn_npc("soldier", player.global_position + Vector3(k * 1.5 - 1.5, 0, -11)))
	await _wait(0.2)
	await _tap("grab")
	await _wait(0.2)
	for b in bystanders:
		b.set_physics_process(false)   # keep them standing in a group
	await _tap("decoy")
	check("decoy while holding someone plants a bio-bomb", is_instance_valid(bomb) and bomb.bio_bomb_timer > 0.0)
	player.powers.drop_held()   # drop them among the soldiers
	await get_tree().physics_frame
	bomb.global_position = bystanders[1].global_position + Vector3(0, 1.5, 1.0)
	bomb.on_thrown(Vector3(0, -6, 0), player)   # as if thrown at them: bursts on impact
	var bomb_at: Vector3 = bomb.global_position
	while is_instance_valid(bomb):
		bomb_at = bomb.global_position
		await get_tree().physics_frame
	await _wait(0.3)
	var hurt := 0
	for b in bystanders:
		if not is_instance_valid(b) or b.hp < b.max_hp:
			hurt += 1
	var where := ""
	for b in bystanders:
		where += (" %.1f/%.0f" % [b.global_position.distance_to(bomb_at), b.hp]) if is_instance_valid(b) else " gone"
	check("the bio-bomb bursts and hurts everyone near it", not is_instance_valid(bomb) and hurt >= 2, "%d hurt:%s" % [hurt, where])
	await _clear_units()
	Game.set_alert(Game.Alert.HIDDEN)
	player.health = player.max_health

	# ---------------- bio weapons: grown from biomass with K
	for bid in ["bio_blade", "bio_gun", "bone_javelin", "spore_launcher"]:
		Game.skills.erase(bid)
	await _tap("bio_weapon")
	check("bio weapons are locked until learned", player.powers.weapon == "")
	for bid in ["bio_blade", "bio_gun", "bone_javelin", "spore_launcher"]:
		Game.skills[bid] = 1
	check("the second animation library is loaded", player.model.anim.has_animation("Sword_Regular_A")
		and player.model.anim.has_animation("OverhandThrow") and player.model.anim.has_animation("Sprint"))
	player.biomass = player.max_biomass
	player.yaw = 0.0
	await _tap("bio_weapon")
	check("K grows a Bio Blade from biomass", player.powers.weapon == "bio_blade" and player.biomass < player.max_biomass,
		"weapon '%s'" % player.powers.weapon)
	var slab: Node3D = Game.military.spawn_npc("heavy_gunner", player.global_position + player.facing * 2.2)
	slab.set_physics_process(false)
	await _wait(0.2)
	var slab_hp: float = slab.hp
	for k in 3:
		player.powers.fire_cooldown = 0.0
		await _tap("attack")
		await _wait(0.15)
	check("the blade's three-hit combo cuts deep", not is_instance_valid(slab) or slab.hp < slab_hp - 100.0,
		"hp %.0f -> %.0f" % [slab_hp, slab.hp if is_instance_valid(slab) else -1.0])
	await _clear_units()
	await _tap("bio_weapon")
	check("then a Bio Gun", player.powers.weapon == "bio_gun")
	var target_g: Node3D = Game.military.spawn_npc("heavy_gunner", player.global_position + player.facing * 8.0)
	target_g.set_physics_process(false)
	await _wait(0.2)
	var bm0 := player.biomass
	var gun_hp: float = target_g.hp
	player.aim_override = target_g.global_position + Vector3.UP * 0.4
	Input.action_press("attack")
	await _wait(0.8)
	Input.action_release("attack")
	player.aim_override = Vector3.INF
	check("the Bio Gun fires bone spines and costs biomass", (not is_instance_valid(target_g) or target_g.hp < gun_hp)
		and player.biomass < bm0, "hp %.0f, biomass %.0f -> %.0f" % [target_g.hp if is_instance_valid(target_g) else -1.0, bm0, player.biomass])
	await _clear_units()
	await _tap("bio_weapon")
	check("then Bone Javelins", player.powers.weapon == "javelin")
	var row: Array = []
	for k in 3:
		var r: Node3D = Game.military.spawn_npc("soldier", player.global_position + player.facing * (6.0 + k * 3.0))
		r.set_physics_process(false)
		row.append(r)
	await _wait(0.2)
	player.aim_override = row[2].global_position + Vector3.UP * 0.2
	player.powers.fire_cooldown = 0.0
	await _tap("attack")
	await _wait(0.6)
	player.aim_override = Vector3.INF
	var skewered := 0
	for r in row:
		if not is_instance_valid(r) or r.hp < r.max_hp:
			skewered += 1
	check("a bone javelin skewers through a line of soldiers", skewered >= 2, "%d hit" % skewered)
	await _clear_units()
	await _tap("bio_weapon")
	check("then the Spore Launcher", player.powers.weapon == "spore")
	var crowd: Array = []
	for k in 3:
		var c: Node3D = Game.military.spawn_npc("civilian", player.global_position + player.facing * 14.0 + Vector3(k - 1.0, 0, 0))
		c.set_physics_process(false)
		crowd.append(c)
	await _wait(0.2)
	player.aim_override = crowd[1].global_position
	player.powers.fire_cooldown = 0.0
	await _tap("attack")
	player.aim_override = Vector3.INF
	await _wait(5.0)
	var gassed := 0
	for c in crowd:
		if not is_instance_valid(c) or c.hp < c.max_hp:
			gassed += 1
	var risen := 0
	for n in main.get_node("Units").get_children():
		if n.get("kind") == "infected":
			risen += 1
	check("spore clouds poison everyone inside and the dead rise as infected", gassed >= 2 and risen >= 1,
		"%d gassed, %d risen" % [gassed, risen])
	await _tap("bio_weapon")
	check("K again puts the bio weapons away", player.powers.weapon == "")
	await _clear_units()
	player.biomass = player.max_biomass

	# ---------------- arm forms and specials
	for f in PlayerPowers.FORM_NAMES.size():
		player.powers.set_form(f)
		await _wait(0.1)
		check("form %s equips" % PlayerPowers.FORM_NAMES[f], player.powers.form == f)
		var dummy: Node3D = Game.military.spawn_npc("infected", player.global_position + Vector3(0, 0, -2.0))
		player.yaw = 0.0
		await _wait(0.2)
		var hp0: float = dummy.hp
		player.powers.attack_cooldown = 0.0
		player.powers.special_cooldown = 0.0
		await _tap("attack")
		await _wait(0.6)
		if is_instance_valid(dummy) and dummy.hp >= hp0:
			await _tap("attack")
			await _wait(0.6)
		check("form %s hits" % PlayerPowers.FORM_NAMES[f], not is_instance_valid(dummy) or dummy.hp < hp0)
		player.biomass = player.max_biomass
		await _tap("special")
		await _wait(0.9)
		if is_instance_valid(dummy):
			dummy.queue_free()
	await _shot("05_forms")
	player.powers.set_form(0)

	# ---------------- grab and throw a car
	await _clear_units()
	car = Game.nearest_in_group("cars", player.global_position, 200.0, func(n): return not n.wrecked)
	await _teleport(car.global_position + Vector3(3.0, 1.0, 0))
	await _wait(0.6)
	await _tap("grab")
	await _wait(0.3)
	check("grab a car", player.powers.held == car, str(player.powers.held))
	await _tap("grab")
	await _wait(0.1)
	check("throw the car", (car as RigidBody3D).linear_velocity.length() > 12.0, "%.1f m/s" % (car as RigidBody3D).linear_velocity.length())
	await _wait(1.5)

	# ---------------- devastators
	await _teleport(Game.city.spawn_point)
	await _wait(0.5)
	var victims: Array = []
	for k in 6:
		var a := k * TAU / 6.0
		victims.append(Game.military.spawn_npc("infected", player.global_position + Vector3(cos(a), 0, sin(a)) * 7.0))
	await _wait(0.2)
	player.biomass = player.max_biomass
	await _tap("devastator_spikes")
	await _wait(1.6)
	var dead := victims.filter(func(v): return not is_instance_valid(v) or not v.is_alive()).size()
	check("groundspike devastator kills a crowd", dead >= 5, "%d/6" % dead)
	await _shot("06_devastator")
	await _wait(1.0)
	victims.clear()
	for k in 6:
		var a := k * TAU / 6.0
		victims.append(Game.military.spawn_npc("soldier", player.global_position + Vector3(cos(a), 0, sin(a)) * 14.0))
	await _wait(0.4)
	player.biomass = player.max_biomass
	await _tap("devastator_tendrils")
	await _wait(1.6)
	dead = victims.filter(func(v): return not is_instance_valid(v) or not v.is_alive()).size()
	check("tendril barrage kills a squad", dead >= 5, "%d/6" % dead)

	# ---------------- tether
	await _clear_units()
	await _teleport(start, -PI * 0.5)
	await _wait(0.5)
	player.pitch = 0.35
	await _wait(0.1)
	var before_pos := player.global_position
	await _tap("tether")
	await _wait(0.8)
	check("tether zips toward the aim point", player.global_position.distance_to(before_pos) > 3.0 or player.state == Player.State.TETHER,
		"moved %.1f" % player.global_position.distance_to(before_pos))
	player.pitch = -0.15
	await _wait(1.5)

	# ---------------- decoy and focus
	await _teleport(Game.city.spawn_point)
	await _wait(0.4)
	player.biomass = player.max_biomass
	await _tap("decoy")
	await _wait(0.2)
	check("decoy spawns", get_tree().get_nodes_in_group("decoys").size() > 0)
	await _tap("focus")
	await _wait(0.2)
	check("focus slows time", Engine.time_scale < 0.5, "time scale %.2f" % Engine.time_scale)
	await _tap("focus")
	await _wait(0.2)
	check("focus turns off", Engine.time_scale > 0.9)
	await _wait(9.0)

	# ---------------- tank hijack
	await _clear_units()
	Game.set_alert(Game.Alert.HIDDEN)
	var cell: Vector2i = Game.city.nearest_intersection(Game.city.spawn_point)
	var tank: Node3D = Game.military.spawn_ground_vehicle("tank", Game.city.intersection_pos(cell) + Vector3(0, 0, -25), 0.0, {"tag": "test"})
	await _wait(0.5)
	await _teleport(tank.global_position + Vector3(4, 1, 0))
	await _wait(0.4)
	await _tap("grab")
	await _wait(0.3)
	check("hijack a tank", player.state == Player.State.PILOT and player.vehicle == tank)
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	var shells_before := main.get_node("Units").get_child_count()
	await _tap("attack")
	await _wait(0.1)
	check("tank drives and fires", (tank as CharacterBody3D).velocity.length() > 1.0 or main.get_node("Units").get_child_count() > shells_before)
	await _shot("07_tank")
	await _tap("grab")
	await _wait(0.5)
	check("jump out of the tank", player.state != Player.State.PILOT)
	await _wait(1.5)

	# ---------------- helicopter hijack
	var heli: Node3D = Game.military.spawn_helicopter(Game.city.spawn_point + Vector3(0, 40, 0), {"tag": "test"})
	await _wait(0.3)
	await _teleport(heli.global_position + Vector3(4, 0, 0))
	await _tap("grab")
	await _wait(0.3)
	check("hijack a gunship", player.state == Player.State.PILOT and player.vehicle == heli)
	var hy := heli.global_position.y
	Input.action_press("jump")
	await _wait(1.0)
	Input.action_release("jump")
	check("fly the gunship up", heli.global_position.y > hy + 3.0, "%.1f -> %.1f" % [hy, heli.global_position.y])
	await _shot("08_heli")
	await _tap("grab")
	await _wait(0.3)
	check("bail out of the gunship", player.state != Player.State.PILOT)
	await _wait(6.0)
	check("abandoned gunship crashes", not is_instance_valid(heli))

	# ---------------- military AI shoots when hunted
	await _clear_units()
	await _teleport(Game.city.spawn_point)
	await _wait(0.5)
	Game.raise_alert(player.global_position, "test")
	var hp_start := player.health
	for k in 4:
		Game.military.spawn_npc("soldier", player.global_position + Vector3(randf_range(-5, 5), 0, -20))
	await _wait(5.0)
	check("soldiers shoot a hunted player", player.health < hp_start or player.is_dead(), "hp %.0f -> %.0f" % [hp_start, player.health])
	await _clear_units()
	Game.set_alert(Game.Alert.HIDDEN)
	player.heal(999)

	# ---------------- infected attack civilians
	var c2: Node3D = Game.military.spawn_npc("civilian", player.global_position + Vector3(30, 0, 0))
	var z2: Node3D = Game.military.spawn_npc("infected", player.global_position + Vector3(33, 0, 0))
	await _wait(5.0)
	check("infected attack civilians", not is_instance_valid(c2) or not c2.is_alive() or c2.hp < c2.max_hp)
	await _clear_units()

	# ---------------- world events
	Game.director.set_process(true)
	Game.military.set_process(true)
	for type in Game.director.EVENT_TYPES:
		Game.director.active_events.clear()
		Game.director.start_random_event(type)
		await _wait(1.0)
		var e_ok: bool = Game.director.active_events.size() > 0 or type == "airstrike"
		check("event %s starts" % type, e_ok)
		await _wait(2.0)
	await _shot("09_events")
	Game.director.active_events.clear()
	await _clear_units()

	# ---------------- music: three CC0 tracks that loop
	var music_node: Node = main.get_node("Music")
	var tracks_ok := true
	for tname in ["ambient", "combat", "boss"]:
		var st: AudioStream = music_node._players[tname].stream
		var loops := false
		if st is AudioStreamOggVorbis or st is AudioStreamMP3:
			loops = st.loop
		elif st is AudioStreamWAV:
			loops = (st as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
		tracks_ok = tracks_ok and st != null and loops
	check("music tracks load and loop", tracks_ok)

	# ---------------- bosses
	Game.level = 20
	for boss_type in ["leviathan", "juggernaut"]:
		Game.director.active_events.clear()
		Game.director.start_random_event(boss_type)
		await _wait(1.0)
		var be: Array = Game.director.active_events.filter(func(e): return e["type"] == boss_type)
		check("boss %s spawns" % boss_type, be.size() == 1 and is_instance_valid(be[0]["data"].get("boss")))
		if be.size() == 1:
			var boss = be[0]["data"]["boss"]
			boss.take_hit(Game.hit_info(99999.0, Vector3.ZERO, player, "explosion"))
			await _wait(1.0)
			check("boss %s can be defeated" % boss_type, Game.director.active_events.filter(func(e): return e["type"] == boss_type).is_empty())
	# Patient Zero finale
	Game.stats["memory_log"] = ["a", "b", "c", "d", "e"]
	Game.level = 20
	check("finale unlocks with 5 memories", Game.director.origin_ready())
	Game.director.active_events.clear()
	Game.director.start_random_event("origin")
	await _wait(1.0)
	var pz = Game.boss
	check("Patient Zero spawns", is_instance_valid(pz) and pz.kind == "patient_zero")
	await _teleport(pz.global_position + Vector3(14, 0.5, 0))
	var hp_pz := player.health
	player.invuln_timer = 0.0
	await _wait(6.0)
	check("Patient Zero fights back", player.health < hp_pz or player.is_dead(), "hp %.0f -> %.0f" % [hp_pz, player.health])
	if is_instance_valid(pz):
		pz.take_hit(Game.hit_info(99999.0, Vector3.ZERO, player, "explosion"))
	await _wait(1.0)
	check("defeating Patient Zero completes the story", Game.flags.get("origin_done", false))
	if player.is_dead():
		await _wait(5.0)
	player.heal(9999)
	Game.stats["memory_log"] = []
	await _clear_units()
	Game.director.active_events.clear()

	# Rooftop race
	Game.director.active_events.clear()
	Game.director.start_random_event("race")
	await _wait(0.3)
	var race: Array = Game.director.active_events.filter(func(e): return e["type"] == "race")
	check("rooftop race starts", race.size() == 1)
	if race.size() == 1:
		var pts: Array = race[0]["data"]["points"]
		for pt in pts:
			player.global_position = pt
			player.velocity = Vector3.ZERO
			await _wait(0.15)
		await _wait(0.3)
		check("rooftop race can be won", Game.director.active_events.filter(func(e): return e["type"] == "race").is_empty() and Game.stat("races") >= 1)
	await _clear_units()

	# ---------------- traffic
	Game.director._maintain_population()
	for k in 6:
		Game.director._maintain_population()
		await _wait(0.2)
	var traffic := get_tree().get_nodes_in_group("traffic")
	check("traffic spawns", traffic.size() > 0, "%d cars" % traffic.size())
	if traffic.size() > 0:
		# any car moving counts: one may be waiting at a red light
		var tc: Node3D = traffic[0]
		var starts := traffic.map(func(c): return (c as Node3D).global_position)
		await _wait(2.0)
		var moved := 0
		for k in traffic.size():
			var c = traffic[k]
			if not is_instance_valid(c) or (c as Node3D).global_position.distance_to(starts[k]) > 2.0:
				moved += 1
		check("traffic drives", moved > 0, "%d of %d moved" % [moved, traffic.size()])
		if is_instance_valid(tc):
			tc.take_hit(Game.hit_info(10.0, Vector3(0, 5, 10), player, "melee"))
			await _wait(0.2)
			check("hit traffic turns into a physics car", not is_instance_valid(tc))

	# ---------------- military base
	Game.military.set_process(true)
	Game.set_alert(Game.Alert.HIDDEN)
	var base_center: Vector3 = Game.city.base_points["center"]
	await _teleport(Game.city.base_points["gate"] + Vector3(130, 0, 0), PI * 0.5)
	var base_alarmed := false   # if the base spots you, its gunship rightly takes off
	t = 0.0
	while t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		base_alarmed = base_alarmed or Game.is_hunted()
	var garrison := get_tree().get_nodes_in_group("military").filter(func(u): return str(u.get("event_tag")) == "base")
	check("military base is garrisoned", garrison.size() >= 4, "%d units" % garrison.size())
	var commander = null
	for u in garrison:
		if u.get("kind") == "commander":
			commander = u
	check("base has a commander", commander != null)
	var base_helis := get_tree().get_nodes_in_group("helicopters").filter(func(h): return str(h.get("event_tag")) == "base")
	var heli_parked := base_helis.any(func(h): return h.get("parked") == true)
	check("gunship parked on the helipad", base_helis.size() > 0 and (heli_parked or base_alarmed),
		"%d base gunships, parked %s, base alarmed %s" % [base_helis.size(), heli_parked, base_alarmed])
	if commander and is_instance_valid(commander):
		await _teleport(Game.city.spawn_point)
		commander.global_position = player.global_position + Vector3(0, 0.3, -1.4)
		# nobody else (a passer-by, a fresh body) may be closer than the commander
		for n in get_tree().get_nodes_in_group("npcs"):
			if n != commander and (n as Node3D).global_position.distance_to(player.global_position) < 6.0:
				n.queue_free()
		await get_tree().physics_frame
		var near: Node3D = Game.nearest_in_group("npcs", player.global_position, 3.4, func(n): return n.can_be_consumed())
		check("commander is the one in reach", near == commander, str(near.get("kind")) if near else "nobody")
		await _tap("consume")
		await _wait(1.3)
		check("consuming the commander gives artillery codes", Game.flags.get("artillery_codes", false))
		check("commander gives a soldier disguise", player.disguise == "commander", player.disguise)
		check("a soldier disguise has no prop gun in your hand", player.model.held_item == null)
		Game.level = 20
		Game.skill_points = 5
		Game.skills.erase("artillery")
		check("artillery skill unlocks", Game.unlock_skill("artillery"))
		await _tap("artillery")
		await _wait(0.2)
		check("artillery can be called", player.powers.artillery_cooldown > 0.0)
		player.powers.give_weapon("rifle", 30)
		player.powers._wardrobe_cd = 0.0
		var rebuilt := player.powers.wear_disguise(0)
		await get_tree().process_frame
		var gun_shown: bool = player.model.hand_r.get_children().any(func(c): return c.has_meta("weapon") and not c.is_queued_for_deletion())
		check("a picked-up gun stays visible after changing body", rebuilt and gun_shown, "rebuilt %s" % rebuilt)
		player.powers._drop_weapon()
	await _wait(5.0)
	await _clear_units()
	Game.set_alert(Game.Alert.HIDDEN)

	# ---------------- stealth: parkour in a fitting disguise is fine; flying, powers and bases aren't
	await _teleport(Game.city.spawn_point, PI * 0.5)
	var real_disguise: String = player.disguise
	player.disguise = "soldier"
	player.parkour_timer = 2.0
	check("parkour in a fitting disguise blends in", not player.is_conspicuous(), player.stand_out_reason())
	player.parkour_timer = 0.0
	player.state = Player.State.GLIDE
	check("flying always stands out", player.is_conspicuous() and player.stand_out_reason() == "flying")
	player.state = Player.State.GROUND
	player.conspicuous_timer = 0.0
	pw.set_form(PlayerPowers.Form.CLAWS)
	check("visible powers stand out", player.is_conspicuous() and player.stand_out_reason() == "powers showing")
	pw.set_form(PlayerPowers.Form.FISTS)
	var base_mid: Vector3 = Game.city.base_points["center"]
	check("bases are restricted areas", Game.in_restricted_area(base_mid) and not Game.in_restricted_area(Game.city.spawn_point))
	await _teleport(base_mid + Vector3.UP)
	player.parkour_timer = 2.0
	check("parkour inside a base stands out, even in uniform", player.is_conspicuous()
		and player.stand_out_reason() == "running around a restricted area", player.stand_out_reason())
	player.parkour_timer = 0.0
	check("walking calmly in uniform inside a base blends in", not player.is_conspicuous(), player.stand_out_reason())
	# a soldier watches you sprint past in disguise and doesn't care
	await _teleport(Game.city.spawn_point, PI * 0.5)
	await _clear_units()
	Game.set_alert(Game.Alert.HIDDEN)
	Game.suspicion = 0.0
	var watcher2: Node3D = Game.military.spawn_npc("soldier", player.global_position + Vector3(-6, 0, 8))
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _wait(2.0)
	_release_all()
	check("sprinting past a soldier in disguise raises no suspicion", Game.alert_level == Game.Alert.HIDDEN
		and Game.suspicion < 0.1, "suspicion %.2f" % Game.suspicion)
	# the stealth meter: a soldier who sees you glide notices you, gets a "?" and the eye fills
	watcher2.global_position = player.global_position + Vector3(0, 0, -10)
	player.state = Player.State.GLIDE
	var watched := false
	t = 0.0
	while t < 2.0:
		player.conspicuous_timer = 1.0
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		watched = watched or (watcher2.noticing and watcher2._marker != null and watcher2._marker.visible)
	player.state = Player.State.GROUND
	var meter: Control = Game.hud.stealth_meter
	check("stealth meter: soldiers who notice you get a marker and the eye fills",
		watched and Game.suspicion > 0.05 and meter.state() in ["NOTICED", "SPOTTED"],
		"noticing %s, suspicion %.2f, meter %s" % [watched, Game.suspicion, meter.state()])
	Game.set_alert(Game.Alert.HIDDEN)
	watcher2.queue_free()
	player.disguise = real_disguise
	# stealth consume: nobody sees it, you get a bonus
	await _clear_units()
	var quiet0 := Game.stat("stealth_consumes")
	var lone: Node3D = Game.military.spawn_npc("civilian", player.global_position + Vector3(0, 0.3, -1.4))
	player.yaw = 0.0
	await get_tree().physics_frame
	await _tap("consume")
	await _wait(1.3)
	check("unseen consume counts as a stealth consume", Game.stat("stealth_consumes") > quiet0 and Game.alert_level == Game.Alert.HIDDEN)
	if is_instance_valid(lone):
		lone.queue_free()

	# ---------------- guns, Prototype 1 style
	await _clear_units()
	Game.set_alert(Game.Alert.HIDDEN)
	await _teleport(Game.city.spawn_point, 0.0)
	player.invuln_timer = 60.0
	for wk in ["soldier", "rocket_soldier", "grenadier", "heavy_gunner"]:
		var gunman = Game.military.spawn_npc(wk, player.global_position + Vector3(randf_range(-3, 3), 0, -8))
		gunman._drop_weapon()
	await get_tree().process_frame
	var dropped := get_tree().get_nodes_in_group("pickups").map(func(pk): return str(pk.get("kind")))
	check("soldiers drop rifles, rocket and grenade launchers, machine guns",
		["rifle", "launcher", "grenade", "mg"].all(func(k): return dropped.has(k)), str(dropped))
	for pk in get_tree().get_nodes_in_group("pickups"):
		pk.queue_free()
	await _clear_units()
	var proj_script := preload("res://scripts/projectile.gd")
	var find_proj := func(k: String) -> Node:
		for c in player.get_parent().get_children():
			if c.get_script() == proj_script and c.kind == k and c.source == player:
				return c
		return null
	pw.give_weapon("grenade", 8)
	player.yaw = 0.0
	player.pitch = -0.15
	await get_tree().physics_frame
	await _tap("attack")
	var nade: Node = find_proj.call("grenade")
	check("grenade launcher lobs a grenade", nade != null and pw.ammo == 7 and nade.gravity > 0.0, "ammo %d" % pw.ammo)
	await _wait(2.6)
	check("grenades go off", nade == null or not is_instance_valid(nade))
	pw.give_weapon("mg", 150)
	check("heavy machine gun weighs you down", pw.speed_factor() < 0.8, "%.2f" % pw.speed_factor())
	Input.action_press("attack")
	await _wait(0.5)
	_release_all()
	check("heavy machine gun fires fast", 150 - pw.ammo >= 6, "%d rounds in 0.5 s" % (150 - pw.ammo))
	pw._drop_weapon()
	# rocket launcher locks onto vehicles
	pw.give_weapon("launcher", 6)
	var lock_tank = Game.military.spawn_ground_vehicle("tank", player.global_position + Vector3(0, 0.3, -45), 0.0)
	lock_tank.abandoned = true
	await _wait(0.2)
	var to_tank: Vector3 = lock_tank.global_position - player.global_position
	player.yaw = atan2(-to_tank.x, -to_tank.z)   # look straight at it
	player.pitch = -0.02
	await _wait(0.1)
	Input.action_press("special")
	await _wait(0.9)
	check("holding aim on a tank locks on", pw.lock_target == lock_tank, "weapon %s, locking on %s, tank alive %s, state %s" % [pw.weapon, pw._lock_on, is_instance_valid(lock_tank), Player.STATE_NAMES[player.state]])
	Input.action_press("attack")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_release_all()
	var homing: Node = find_proj.call("rocket")
	check("locked rockets home in", homing != null and homing.target == lock_tank)
	await _wait(1.5)
	check("the locked rocket hits the tank", not is_instance_valid(lock_tank) or lock_tank.hp < 700.0)
	pw._drop_weapon()
	if is_instance_valid(lock_tank):
		lock_tank.queue_free()
	# the new soldiers fight with their own weapons
	await _clear_units()
	Game.set_alert(Game.Alert.HIDDEN)
	var gren = Game.military.spawn_npc("grenadier", player.global_position + Vector3(0, 0, -22))
	var heavy = Game.military.spawn_npc("heavy_gunner", player.global_position + Vector3(6, 0, -14))
	Game.raise_alert(player.global_position, "")
	var saw_grenade := false
	t = 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not is_instance_valid(gren):
			break
		for c in gren.get_parent().get_children():   # soldiers' shots live next to them
			if c.get_script() == proj_script and c.kind == "grenade" and c.source == gren:
				saw_grenade = true
	check("grenadiers lob grenades", saw_grenade)
	check("heavy gunners are tough", heavy.max_hp > 100.0)
	await _clear_units()
	# riot troopers block hits from the front; a big hit smashes the shield
	var riot = Game.military.spawn_npc("riot", player.global_position + Vector3(0, 0, -4))
	await _wait(0.2)
	riot._face_dir = (player.global_position - riot.global_position).normalized()
	var riot_hp: float = riot.hp
	riot.take_hit(Game.hit_info(20.0, Vector3.ZERO, player, "melee"))
	check("a riot shield blocks frontal hits", riot._shield != null and riot_hp - riot.hp < 4.0, "lost %.1f" % (riot_hp - riot.hp))
	riot.take_hit(Game.hit_info(60.0, Vector3.ZERO, player, "melee"))
	check("a big hit smashes the riot shield", riot._shield == null)
	# snipers paint you with a laser before they fire
	Game.raise_alert(player.global_position, "")
	var sniper = Game.military.spawn_npc("sniper", player.global_position + Vector3(0, 0, -30))
	var lasered := false
	t = 0.0
	while t < 3.0 and is_instance_valid(sniper):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		lasered = lasered or (sniper._laser != null and sniper._laser.visible)
	check("snipers aim a red laser at you", lasered)
	var brute = Game.military.spawn_npc("brute", player.global_position + Vector3(0, 0, -40))
	check("brute infected are big and tough", brute.scale_factor > 1.3 and brute.max_hp > 250.0 and brute.is_in_group("hunters"))
	await _clear_units()
	Game.set_alert(Game.Alert.HIDDEN)
	player.invuln_timer = 0.0

	# ---------------- each level makes you a little tougher, right away
	var hp_before := player.max_health
	var lvl_before := Game.level
	Game.add_xp(Game.xp_to_next(Game.level) - Game.xp + 1, "test")
	check("levelling up raises max health at once", Game.level == lvl_before + 1 and player.max_health > hp_before,
		"level %d->%d, health %.0f->%.0f" % [lvl_before, Game.level, hp_before, player.max_health])

	# ---------------- disguise wardrobe
	await _clear_units()
	Game.set_alert(Game.Alert.HIDDEN)
	Game.disguises = []
	for k in ["soldier", "scientist", "civilian"]:
		var npc: Node3D = Game.military.spawn_npc(k, player.global_position + Vector3(0, 0, -1.5))
		await _wait(0.1)
		player.yaw = 0.0
		await _tap("consume")
		await _wait(1.3)
	check("consumed identities go to the wardrobe", Game.disguises.size() == 3, "%d" % Game.disguises.size())
	check("wearing a wardrobe disguise", player.powers.wear_disguise(0) and player.disguise == "soldier")
	player.powers.wear_disguise(-1)
	check("back to your true form", player.model.true_form and player.disguise == "civilian")
	player.powers.wear_disguise(1)
	Game.save_game()
	Game.disguises = []
	Game.load_game()
	check("wardrobe saves and loads", Game.disguises.size() == 3 and Game.disguises[1]["outfit"].get("shirt") is Color)
	check("current disguise survives a reload", player.disguise == "scientist" and not player.model.true_form)
	Game.hud.open_wardrobe()
	await get_tree().process_frame
	check("wardrobe menu opens", Game.hud.wardrobe_panel.visible)
	Game.hud.close_wardrobe()
	await _wait(0.3)

	# ---------------- enterable buildings
	var ints: Node = Game.interiors
	check("doors placed in the city", ints.entrances.size() >= 6, "%d doors" % ints.entrances.size())
	for e in ints.entrances:
		ints.enter(e)
		await _wait(1.5)
		var inside_ok: bool = ints.is_inside() and player.global_position.y < -100.0 and player.global_position.y > ints.DEPTH - 2.0
		check("enter %s" % e["id"], inside_ok, "y %.1f" % player.global_position.y)
		var npcs: Array = ints.root.get_children().filter(func(n): return n is CharacterBody3D and n.has_method("is_alive"))
		var fallen: Array = npcs.filter(func(n): return n.global_position.y < ints.DEPTH - 5.0)
		check("%s people stay on the floor" % e["id"], fallen.is_empty(), "%d people, %d fell" % [npcs.size(), fallen.size()])
		var keys: Array = ints._cells.keys()
		var far: Vector3 = ints._cell_pos(keys[keys.size() - 1])
		var ipath: PackedVector3Array = Game.city.nav_path(ints._entry_pos(), far)
		check("%s has walkable paths" % e["id"], ipath.size() >= 2 and ipath[ipath.size() - 1].distance_to(far) < 3.0, "%d pts" % ipath.size())
		if e["id"] == "lab0":
			player.powers.wear_disguise(-1)
			check("lab is restricted without a disguise", Game.is_trespassing(player.global_position))
			player.powers.wear_disguise(1)
			check("scientist disguise gets you into the lab", not Game.is_trespassing(player.global_position))
			var sample = ints.root.get_children().filter(func(n): return n is Area3D and n.get("kind") == "sample")
			check("lab has an Evolution Sample", sample.size() == 1)
			if sample.size() == 1:
				var sp0 := Game.skill_points
				player.respawn_in_place(sample[0].global_position, 0.0)
				await _wait(0.5)
				check("sample gives a skill point", Game.skill_points >= sp0 + 1)
			await _shot("13_lab")
		if e["id"] == "safehouse":
			await _shot("14_safehouse")
		if e["id"] == "nest":
			await _shot("15_nest")
		player.respawn_in_place(ints._entry_pos() + Vector3.UP, -PI * 0.5)
		await _wait(0.3)
		check("%s exit prompt" % e["id"], ints.prompt() == "leave")
		await _tap("grab")
		await _wait(0.5)
		check("leave %s" % e["id"], not ints.is_inside() and player.global_position.y > -5.0, "y %.1f" % player.global_position.y)
		Game.set_alert(Game.Alert.HIDDEN)
		player.heal(9999)
	await _clear_units()

	# ---------------- menus work with a controller (any device number)
	Game.hud.toggle_pause(true)
	await get_tree().process_frame
	var f0 := get_viewport().gui_get_focus_owner()
	var pad_ev := InputEventJoypadButton.new()
	pad_ev.device = 2
	pad_ev.button_index = JOY_BUTTON_DPAD_DOWN
	pad_ev.pressed = true
	Input.parse_input_event(pad_ev)
	await get_tree().process_frame
	pad_ev = pad_ev.duplicate()
	pad_ev.pressed = false
	Input.parse_input_event(pad_ev)
	await get_tree().process_frame
	var f1 := get_viewport().gui_get_focus_owner()
	check("controller D-pad moves through menus", f0 != null and f1 != null and f0 != f1)
	var bev := InputEventJoypadButton.new()
	bev.device = 2
	bev.button_index = JOY_BUTTON_B
	bev.pressed = true
	Input.parse_input_event(bev)
	await get_tree().process_frame
	bev = bev.duplicate()
	bev.pressed = false
	Input.parse_input_event(bev)
	await get_tree().process_frame
	check("controller B closes the menu", not Game.hud.pause_menu.visible and not get_tree().paused)
	await _wait(0.5)

	# ---------------- nobody spawns on rooftops
	var roof_y := 0.0
	for k in 200:
		var rp: Vector3 = Game.city.random_sidewalk_point(Vector3(0, 60, 0), 50.0, 125.0)
		roof_y = maxf(roof_y, rp.y)
	check("new people always spawn at street level", roof_y < 1.5, "highest %.1f" % roof_y)

	# ---------------- combo, weather, settings
	Game.combo = 0
	for k in 10:
		Game.register_hit()
	check("combo counts hits", Game.combo == 10 and Game.combo_rank() == "C", "x%d %s" % [Game.combo, Game.combo_rank()])
	var wx: Node = Game.get_meta("weather")
	wx.set_weather(1)
	await _wait(1.0)
	check("rain starts", wx._rain.emitting)
	await _shot("12_rain")
	wx.set_weather(0)
	Settings.mouse_sensitivity = 1.7
	Settings.save_settings()
	Settings.mouse_sensitivity = 1.0
	Settings.load_settings()
	check("settings save and load", absf(Settings.mouse_sensitivity - 1.7) < 0.01)
	Settings.mouse_sensitivity = 1.0
	Settings.save_settings()
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_K
	Settings.bind("consume", ev)
	check("keys can be rebound", Settings.key_name("consume") == "K", Settings.key_name("consume"))
	Settings.reset_bindings()
	check("keys reset to defaults", Settings.key_name("consume") == "F", Settings.key_name("consume"))
	check("build number shows bottom right", Game.hud.version_label.visible
		and Game.hud.version_label.text == "v" + str(ProjectSettings.get_setting("application/config/version"))
		and Game.hud.version_label.get_global_rect().end.x > get_viewport().get_visible_rect().size.x - 40.0,
		Game.hud.version_label.text)
	# the "what's new" popup can be clicked right away and closes back into the game
	Settings.last_seen_version = "0.0.1"
	Game.hud._maybe_show_whats_new()
	await get_tree().process_frame
	var popup_ok := Game.hud.whats_new_panel != null and get_tree().paused
	if not DisplayServer.get_name() == "headless":
		popup_ok = popup_ok and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	var focused := get_viewport().gui_get_focus_owner()
	check("what's new popup is clickable at once", popup_ok and focused is Button, str(focused))
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await get_tree().process_frame
	await get_tree().process_frame
	check("Esc closes the popup back into the game", Game.hud.whats_new_panel == null and not get_tree().paused
		and not Game.hud.pause_menu.visible)
	Game.skills["wings"] = 3
	await _teleport(Game.city.spawn_point + Vector3(0, 50, 0))
	await _tap("jump")
	Input.action_press("jump")
	await _wait(1.0)
	player.flaps_left = 3
	var gy := player.global_position.y
	Input.action_release("jump")
	await get_tree().physics_frame
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _wait(0.3)
	check("tendril wings flap upward", player.global_position.y > gy or player.flaps_left < 3, "flaps left %d" % player.flaps_left)
	Input.action_release("jump")
	await _wait(3.0)

	# ---------------- day and night
	Game.daynight.hour = 23.0
	await _wait(0.3)
	check("night time", Game.daynight.is_night())
	await _shot("10_night")
	Game.daynight.hour = 13.0

	# ---------------- levels and skills
	if player.is_dead():
		await _wait(5.0)
	player.heal(9999)
	Game.reset_state()
	player.apply_upgrades()
	Game.add_xp(5000, "test")
	check("XP levels you up", Game.level > 5, "level %d" % Game.level)
	check("levels give skill points", Game.skill_points >= Game.level - 1, "%d points" % Game.skill_points)
	check("claws can be unlocked", Game.unlock_skill("claws"))
	check("tendrils need groundspike first", Game.skill_block_reason("tendrils") != "")

	# ---------------- starter goals
	var gi := Game.goal_index
	Game.goal_index = 0
	Game.stat_add("wall_runs")
	await _wait(0.8)
	check("goals complete and advance", Game.goal_index >= 1, "goal %d" % Game.goal_index)
	Game.goal_index = maxi(gi, Game.goal_index)

	# ---------------- ragdolls: people go limp when they die
	var victim: Node3D = Game.military.spawn_npc("civilian", player.global_position + Vector3(0, 0, -5))
	await _wait(0.2)
	victim.take_hit(Game.hit_info(999.0, Vector3(0, 4, -8), null, "melee"))
	await _wait(0.6)
	check("people go limp (ragdoll) when they die", is_instance_valid(victim) and victim.model.ragdolling
		and victim.model.skeleton.get_child_count() > 0,
		"valid %s" % is_instance_valid(victim) if not is_instance_valid(victim) else "ragdoll %s, state %d, hp %.0f, model %d" % [victim.model.ragdolling, victim.state, victim.hp, victim.model.get_instance_id()])

	# ---------------- time trials (fixed rooftop courses)
	var races: Node = Game.get_meta("races")
	check("4 time trials with courses over the roofs", races.starts.size() == 4 and races.courses[0].size() >= 6,
		"%d races, %d rings" % [races.starts.size(), races.courses[0].size() if races.courses.size() > 0 else 0])
	player.velocity = Vector3.ZERO
	player.global_position = races.starts[0] + Vector3.UP * 1.0
	await _wait(0.3)
	check("walking into a beacon starts a time trial", races.active == 0)
	await _wait(3.2)
	for ring in races.courses[0]:
		player.global_position = ring
		player.velocity = Vector3.ZERO
		await _wait(0.15)
	check("flying through every ring finishes it and saves a best time", races.active == -1 and races.best_time(0) > 0.0,
		"best %.2f" % races.best_time(0))

	# ---------------- viral caches (collectibles)
	var cache_node: Node = Game.get_meta("collectibles")
	check("60 viral caches are hidden around the map", cache_node.caches.size() + cache_node.found_count() == 60,
		"%d left, %d found" % [cache_node.caches.size(), cache_node.found_count()])
	Game.flags["caches"] = [900, 901, 902, 903, 904, 905, 906, 907, 908]   # nine already found
	var sp_before := Game.skill_points
	var first: Node3D = cache_node.caches[0]
	await _teleport(first.global_position + Vector3(0, -0.5, 0))
	await _wait(0.2)
	check("touching a cache collects it, the tenth gives a skill point",
		not is_instance_valid(first) and cache_node.found_count() == 10 and Game.skill_points == sp_before + 1,
		"found %d, skill points %d->%d" % [cache_node.found_count(), sp_before, Game.skill_points])
	await _teleport(Game.city.spawn_point)

	# ---------------- achievements
	Game.stat_add("consumes")
	await _wait(1.2)
	check("achievements unlock", Game.has_achievement("first_taste"))

	# ---------------- save and load
	var lvl := Game.level
	Game.save_game()
	check("save file written", Game.has_save())
	Game.level = 1
	Game.skills = {}
	Game.load_game()
	check("save file restores level", Game.level == lvl, "level %d" % Game.level)
	check("save file restores skills", Game.has_skill("claws"))

	# ---------------- free play stress test
	Game.director._event_timer = 1.0
	await _teleport(Game.city.spawn_point)
	Game.raise_alert(player.global_position, "stress")
	Game.heat = 5.0
	Game.level = 30
	player.invuln_timer = 999.0
	await _wait(25.0)
	var units := main.get_node("Units").get_child_count()
	check("free play keeps running", units > 10, "%d units, fps %d" % [units, Engine.get_frames_per_second()])
	await _shot("11_chaos")
