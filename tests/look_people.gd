extends Node
## Close-up screenshots of every kind of person and the player.
##   godot --path . res://tests/look_people.tscn -- shots=<folder>

const MAIN := preload("res://scenes/main.tscn")
const HUMANOID := preload("res://scripts/humanoid.gd")
var dir := "user://shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			dir = a.substr(6)
	Game.delete_save()
	Game.reset_state()
	var main: Node3D = MAIN.instantiate()
	add_child(main)
	await _wait(0.5)
	Game.hud.visible = false
	Game.hud._title_timer = 0.0
	Game.director.set_process(false)
	Game.military.set_process(false)
	Game.daynight.hour = 13.0
	var p: Player = Game.player
	p.set_physics_process(false)
	for n in get_tree().get_nodes_in_group("npcs"):
		n.queue_free()
	var base := p.global_position + Vector3(0, 30, 0)
	# a stage floating above the street so nothing walks in front
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.36, 0.38)
	floor_mi.material_override = fm
	add_child(floor_mi)
	floor_mi.global_position = base + Vector3(0, -0.9, 0)
	var kinds := ["civilian", "civilian", "civilian", "civilian", "soldier", "elite", "commander", "scientist", "infected", "hunter", "patient_zero"]
	var models: Array = []
	seed(4)
	for i in kinds.size():
		var npc: Node3D = Game.military.spawn_npc(kinds[i], base + Vector3((i - kinds.size() * 0.5) * 1.1, 0, 0))
		npc.set_physics_process(false)
		npc.set_process(false)
		npc.global_position = base + Vector3((i - kinds.size() * 0.5) * 1.15, (npc.scale_factor - 1.0) * 0.9, 0)
		npc.rotation = Vector3.ZERO
		models.append(npc.model)
	# the player model, true form
	var pmodel: Node3D = p.model
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 40
	cam.global_position = base + Vector3(-0.5, 0.6, -9.0)
	cam.look_at(base + Vector3(-0.5, 0.1, 0))
	await _wait(0.6)
	await _shot("people_lineup")
	cam.global_position = base + Vector3(-4.0, 0.7, -2.6)
	cam.look_at(base + Vector3(-4.0, 0.45, 0))
	await _wait(0.3)
	await _shot("people_close_civilians")
	cam.global_position = base + Vector3(1.0, 0.75, -2.6)
	cam.look_at(base + Vector3(1.0, 0.45, 0))
	await _wait(0.3)
	await _shot("people_close_military")
	# faces
	cam.fov = 25
	cam.global_position = base + Vector3(-5.06, 0.85, -1.4)
	cam.look_at(base + Vector3(-5.06, 0.75, 0))
	await _wait(0.3)
	await _shot("people_face")
	# walking / running poses
	for i in models.size():
		var m: Node3D = models[i]
		for f in 30:
			m.animate(1.0 / 60.0, 3.0 if i % 2 == 0 else 9.0, "walk" if i % 2 == 0 else "run")
	cam.fov = 40
	cam.global_position = base + Vector3(-8.5, 0.6, -4.0)
	cam.look_at(base + Vector3(-0.5, 0.1, 0))
	await _wait(0.3)
	await _shot("people_moving")
	# player
	p.set_physics_process(false)
	pmodel.get_parent().global_position = base + Vector3(0, 0, 3.0)
	pmodel.get_parent().rotation = Vector3.ZERO
	cam.global_position = base + Vector3(0, 0.8, 0.4)
	cam.look_at(base + Vector3(0, 0.4, 3.0))
	await _wait(0.4)
	await _shot("player_close")
	Game.delete_save()
	get_tree().quit()


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot ", name)
