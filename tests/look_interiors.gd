extends Node
## Screenshots of every interior and a city door.
##   godot --path . res://tests/look_interiors.tscn -- shots=<folder>

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
	await _wait(0.5)
	var player: Player = Game.player
	Game.hud._title_timer = 0.0
	Game.director.set_process(false)
	Game.daynight.hour = 14.0
	var ints: Node = Game.interiors
	# a lab door from the street
	var lab: Dictionary = ints.entrance_by_id("lab0")
	var n: Vector3 = lab["normal"]
	player.respawn_in_place(Vector3(lab["pos"]) + n * 9.0 + Vector3.UP, atan2(n.x, n.z))
	player.pitch = 0.0
	await _wait(1.5)
	await _shot("door_lab")
	for e in ints.entrances:
		if e["id"] in ["lab1", "lab2"]:
			continue
		ints.enter(e)
		await _wait(1.2)
		player.pitch = -0.12
		await _wait(0.8)
		await _shot("interior_" + str(e["id"]))
		# look from the middle of the biggest room too
		var keys: Array = ints._cells.keys()
		player.respawn_in_place(ints._cell_pos(keys[keys.size() / 2]) + Vector3.UP, -PI * 0.5)
		await _wait(1.0)
		await _shot("interior_" + str(e["id"]) + "_2")
		ints.leave()
		await _wait(0.5)
	Game.hud.open_wardrobe()
	await _wait(0.3)
	await _shot("menu_wardrobe")
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
