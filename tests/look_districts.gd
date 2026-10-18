extends Node
## Screenshots of every district from the air and from the street.
##   godot --path . res://tests/look_districts.tscn -- shots=<folder>

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
	Game.daynight.hour = 14.0
	Game.player.set_physics_process(false)
	var city: City = Game.city
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.far = 1500.0
	# block centres for one block of each district
	var picks := {}
	for c in city.districts:
		var cell: Vector2i = c
		if cell.x < 1 or cell.y < 1 or cell.x >= city.blocks - 1 or cell.y >= city.blocks - 1:
			continue
		var d: int = city.districts[cell]
		if not picks.has(d) or randf() < 0.15:
			picks[d] = cell
	for d in picks:
		var cell: Vector2i = picks[d]
		var o := Vector3(city.x0 + city.street_width + cell.x * city.period, 0, city.z0 + city.street_width + cell.y * city.period)
		var centre := o + Vector3(city.block_size * 0.5, 0, city.block_size * 0.5)
		var name: String = City.DISTRICT_NAMES[d].to_lower()
		cam.fov = 60
		cam.global_position = centre + Vector3(-45, 35, -45)
		cam.look_at(centre)
		await _wait(0.8)
		await _shot("district_%s_air" % name)
		cam.global_position = Vector3(o.x - city.street_width * 0.5, 1.7, centre.z - 30)
		cam.look_at(Vector3(o.x - city.street_width * 0.5, 1.5, centre.z + 30))
		await _wait(0.5)
		await _shot("district_%s_street" % name)
	cam.fov = 55
	cam.global_position = Vector3(0, 260, 620)
	cam.look_at(Vector3(0, 0, 0))
	await _wait(1.0)
	await _shot("district_overview")
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
