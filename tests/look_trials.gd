extends Node
## Screenshots of a time trial: the start beacon and the rings over the rooftops.
##   godot --path . res://tests/look_trials.tscn -- shots=<folder>

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
	var tr: Node = Game.get_meta("races")
	var start: Vector3 = tr.starts[0]
	var first: Vector3 = tr.courses[0][0]
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var back := (start - first)
	back.y = 0.0
	back = back.normalized()
	cam.global_position = start + back * 26.0 + Vector3.UP * 14.0
	cam.look_at(start.lerp(first, 0.5) + Vector3.UP * 10.0)
	p.global_position = start + back * 6.0 + Vector3.UP * 1.0
	await _wait(1.0)
	await _shot("trial_beacon")
	tr.start_race(0)
	await _wait(0.5)
	var second: Vector3 = tr.courses[0][1]
	cam.global_position = first + (first - second).normalized() * 30.0 + Vector3.UP * 12.0
	cam.look_at(second)
	p.global_position = first + (first - second).normalized() * 8.0
	await _wait(0.8)
	await _shot("trial_rings")
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
