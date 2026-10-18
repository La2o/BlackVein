extends Node
## Screenshots of the newer enemies: riot trooper, sniper, brute infected.
##   godot --path . res://tests/look_enemies.tscn -- shots=<folder>

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
	Game.hud.visible = false
	Game.director.set_process(false)
	Game.military.set_process(false)
	Game.daynight.hour = 14.0
	var p: Player = Game.player
	p.set_physics_process(false)
	for n in get_tree().get_nodes_in_group("npcs"):
		n.queue_free()
	await _wait(0.3)
	var base: Vector3 = Game.city.spawn_point + Vector3(0, -0.3, -12)
	var kinds := ["riot", "sniper", "brute", "soldier"]
	for k in kinds.size():
		var npc: Node3D = Game.military.spawn_npc(kinds[k], base + Vector3((k - 1.5) * 2.6, 1.0, 0))
		npc.set_physics_process(false)
		npc._face_dir = Vector3.BACK
		npc.rotation.y = 0.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.global_position = base + Vector3(0.5, 1.8, -7.0)
	cam.look_at(base + Vector3(0, 1.1, 0))
	await _wait(1.0)
	await _shot("enemies")
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
