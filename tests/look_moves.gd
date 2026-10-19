extends Node
## Screenshots of parkour poses, body-part forms and the forms wheel.
##   godot --path . res://tests/look_moves.tscn -- shots=<folder>

const MAIN := preload("res://scenes/main.tscn")
var dir := "user://shots"
var p: Player
var cam: Camera3D
var base: Vector3


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			dir = a.substr(6)
	Game.use_test_storage()
	Game.delete_save()
	Game.reset_state()
	var main: Node3D = MAIN.instantiate()
	add_child(main)
	await _wait(0.5)
	Game.hud._title_timer = 0.0
	Game.director.set_process(false)
	Game.military.set_process(false)
	Game.daynight.hour = 13.0
	Game.level = 30
	for id in Game.SKILLS:
		Game.skills[id] = Game.SKILLS[id][5]
	p = Game.player
	p.apply_upgrades()
	for n in get_tree().get_nodes_in_group("npcs"):
		n.queue_free()
	base = p.global_position + Vector3(0, 40, 0)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.36, 0.38)
	floor_mi.material_override = fm
	add_child(floor_mi)
	floor_mi.global_position = base + Vector3(0, -0.9, 0)
	p.set_physics_process(false)
	p.global_position = base
	p.facing = Vector3.FORWARD
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 45
	_side_view()
	Game.hud.visible = false
	await _pose("ninja_run", Player.State.GROUND, Vector3(0, 0, -26), "", 0.0, 0.7)
	await _pose("frontflip", Player.State.AIR, Vector3(0, 4, -12), "frontflip", 0.2, 0.0)
	await _pose("corkscrew", Player.State.AIR, Vector3(0, 4, -12), "corkscrew", 0.3, 0.0)
	await _pose("vault", Player.State.AIR, Vector3(0, 3, -20), "vault", 0.22, 0.0)
	await _pose("skydive", Player.State.AIR, Vector3(0, -40, -3), "", 0.0, 0.6)
	p._hero_t = 0.5
	await _pose("hero_landing", Player.State.GROUND, Vector3.ZERO, "", 0.0, 0.15)
	p._hero_t = 0.0
	p.powers.set_defense(PlayerPowers.Defense.WINGS, true)
	await _pose("wings_folded", Player.State.GROUND, Vector3.ZERO, "", 0.0, 0.5)
	_back_view()
	await _pose("wings_glide", Player.State.GLIDE, Vector3(0, -2, -30), "", 0.0, 0.8)
	p.powers.set_defense(PlayerPowers.Defense.NONE, true)
	_side_view()
	for l in [1, 2, 3, 4]:
		p.powers.set_legs(l, true)
		await _pose("legs_%d" % l, Player.State.GROUND, Vector3.ZERO, "", 0.0, 0.4)
	p.powers.set_legs(0, true)
	Game.hud.visible = true
	cam.current = false
	p.camera.current = true
	Input.action_press("forms_wheel")
	Game.hud.open_wheel()
	await _wait(0.3)
	Game.hud.wheel._cursor = Vector2(120, 60)
	await _wait(0.3)
	await _shot("forms_wheel")
	Input.action_release("forms_wheel")
	Game.delete_save()
	get_tree().quit()


func _side_view() -> void:
	cam.global_position = base + Vector3(4.2, 0.4, 0)
	cam.look_at(base + Vector3(0, 0.0, 0))


func _back_view() -> void:
	cam.global_position = base + Vector3(0.0, 1.6, 4.5)
	cam.look_at(base + Vector3(0, 0.3, 0))


func _pose(name: String, st: int, vel: Vector3, trick_name: String, trick_time: float, run_for: float) -> void:
	p.state = st
	p.velocity = vel
	if vel.length() > 0.5 and Vector3(vel.x, 0, vel.z).length() > 0.5:
		p.facing = Vector3(vel.x, 0, vel.z).normalized()
	p._super_done = false
	if trick_name != "":
		p.start_trick(trick_name, 0.52, 1.0)
	if trick_name == "vault":
		p.model.oneshot("ClimbUp_1m", 1.3, 0.0)
	var dt := 1.0 / 60.0
	var t := 0.0
	var until := maxf(run_for, trick_time)
	while t < until:
		p._update_visual(dt)
		t += dt
	await _wait(0.15)
	await _shot("move_" + name)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.05)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot ", name)
