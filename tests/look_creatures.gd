extends Node
## Screenshots of the creature forms and the stealth meter.
##   godot --path . res://tests/look_creatures.tscn -- shots=<folder>

const MAIN := preload("res://scenes/main.tscn")
var dir := "user://shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			dir = a.substr(6)
	Game.use_test_storage()
	Game.delete_save()
	Game.reset_state()
	var main: Node3D = MAIN.instantiate()
	add_child(main)
	await _wait(1.0)
	Game.hud._title_timer = 0.0
	Game.director.set_process(false)
	Game.daynight.hour = 15.0
	var p: Player = Game.player
	p.invuln_timer = 9999.0
	for id in Game.SKILLS:
		Game.skills[id] = Game.SKILLS[id][5]
	Game.level = 25
	p.apply_upgrades()
	for n in get_tree().get_nodes_in_group("npcs"):
		n.queue_free()
	await _wait(0.3)
	var pw: PlayerPowers = p.powers
	var cam := Camera3D.new()
	add_child(cam)
	for c in [1, 2, 3]:
		pw.set_creature(c, true)
		p.biomass = p.max_biomass
		await _wait(0.4)
		p.camera.clear_current(false)
		cam.make_current()
		Game.hud.visible = false
		var at: Vector3 = p.global_position
		var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		cam.global_position = at + fwd * 4.2 + Vector3(0.6, 0.6 + (0.4 if c == 1 else 0.0), 0)
		cam.look_at(at + Vector3(0, 0.25 + (0.3 if c == 1 else 0.0), 0))
		await _wait(0.4)
		await _shot("creature_%s" % PlayerPowers.CREATURE_NAMES[c].to_lower())
	pw.set_creature(0, true)
	# the stealth meter: soldiers watching you glide
	cam.clear_current(false)
	p.camera.make_current()
	Game.hud.visible = true
	for k in 3:
		Game.military.spawn_npc("soldier", p.global_position + Vector3(-8 + k * 8, 0, -14))
	p.global_position += Vector3(0, 6, 0)
	p.state = Player.State.GLIDE
	var t := 0.0
	while t < 1.6:
		p.conspicuous_timer = 1.0
		p.state = Player.State.GLIDE
		p.velocity = Vector3.ZERO
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	await _shot("stealth_meter")
	Game.delete_save()
	get_tree().quit()


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(shot_name + ".png"))
