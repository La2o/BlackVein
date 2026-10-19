extends Node
## Screenshots of the player's animation while moving: carrying someone, lifting a car, running with
## a rifle and with the bio blade, sliding, and a jump from take-off to landing.
##   godot --path . res://tests/look_anim.tscn -- shots=<folder>

const MAIN := preload("res://scenes/main.tscn")
var dir := "user://shots"
var p: Player
var cam: Camera3D


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
	Game.hud.visible = false
	Game.director.set_process(false)
	Game.military.set_process(false)
	Game.daynight.hour = 13.0
	p = Game.player
	for id in Game.SKILLS:
		Game.skills[id] = Game.SKILLS[id][5]
	p.apply_upgrades()
	p.biomass = p.max_biomass
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	# a long straight street to run along
	var start: Vector3 = Game.city.spawn_point
	await _run_shot(start, "", "anim_0_run", 0.0)
	await _run_shot(start, "npc", "anim_1_carry_run", 0.0)
	await _run_shot(start, "car", "anim_2_car_walk", 0.0, false)
	p.powers.give_weapon("rifle", 200)
	await _run_shot(start, "", "anim_3_rifle_run", 0.0)
	p.powers._drop_weapon()
	p.powers.grow_bio("bio_blade")
	await _run_shot(start, "", "anim_4_blade_run", 0.0)
	p.powers._drop_weapon()
	# a jump: frames from take-off to landing
	p.respawn(start)
	p.yaw = 0.0
	await _wait(0.6)
	_side_cam()
	Input.action_press("jump")
	for k in 6:
		await _wait(0.12)
		if k == 1:
			Input.action_release("jump")
		_side_cam()
		await _shot("anim_5_jump_%d" % k)
	await _wait(0.6)
	_side_cam()
	await _shot("anim_5_jump_land")
	Game.delete_save()
	get_tree().quit()


## Runs (or walks) up the street for a moment, then a side-on picture of the stride.
func _run_shot(start: Vector3, carry: String, shot_name: String, _t: float, sprint := true) -> void:
	p.respawn(start)
	p.yaw = 0.0
	await _wait(0.3)
	if carry == "npc":
		var who: Node3D = Game.military.spawn_npc("civilian", p.global_position + p.facing * 1.5)
		await _wait(0.2)
		p.powers._grab(who)
	elif carry == "car":
		var cars := get_tree().get_nodes_in_group("cars")
		if not cars.is_empty():
			var car: Node3D = cars[0]
			car.global_position = p.global_position + p.facing * 2.5
			await _wait(0.2)
			p.powers._grab(car)
	Input.action_press("move_forward")
	if sprint:
		Input.action_press("sprint")
	await _wait(1.2)
	_side_cam()
	await _shot(shot_name)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	if p.powers.held:
		p.powers.drop_held()
	await _wait(0.4)


func _side_cam() -> void:
	var side: Vector3 = p.facing.cross(Vector3.UP).normalized()
	cam.global_position = p.global_position + side * 4.2 + Vector3.UP * 1.0 + p.facing * 0.6
	cam.look_at(p.global_position + Vector3.UP * 0.4)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		if cam and cam.is_current():
			_side_cam()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(shot_name + ".png"))
