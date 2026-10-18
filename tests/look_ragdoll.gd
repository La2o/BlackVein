extends Node
## Screenshots of people going limp (ragdolls) after a hit.
##   godot --path . res://tests/look_ragdoll.tscn -- shots=<folder>

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
	var people := []
	for k in 6:
		var npc: Node3D = Game.military.spawn_npc("soldier" if k % 2 == 0 else "civilian", base + Vector3((k - 2.5) * 2.2, 1.0, 0))
		people.append(npc)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.global_position = base + Vector3(0, 2.2, 8.5)
	cam.look_at(base + Vector3(0, 0.5, 0))
	await _wait(0.8)
	await _shot("ragdoll_0_standing")
	for k in people.size():
		var npc: Node3D = people[k]
		npc.take_hit(Game.hit_info(999.0, Vector3(randf_range(-4, 4), 5.0, -9.0), p, "melee"))
	await _wait(0.25)
	await _shot("ragdoll_1_hit")
	await _wait(2.0)
	await _shot("ragdoll_2_down")
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
