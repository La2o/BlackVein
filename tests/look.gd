extends Node
## Quick visual check: a few views of the city at different times and weather.
##   godot --path . res://tests/look.tscn -- shots=<folder>

const MAIN := preload("res://scenes/main.tscn")
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
	var player: Player = Game.player
	Game.hud._title_timer = 0.0
	Game.hud.root.visible = false
	Game.director.set_process(false)
	var sp: Vector3 = Game.city.spawn_point
	for k in 6:
		Game.director._maintain_population()
		await _wait(0.1)
	Game.daynight.hour = 15.0
	player.yaw = 0.0
	player.pitch = 0.05
	await _wait(1.5)
	await _shot("look_street_day")
	# up high looking over the city
	player.respawn(Game.city.random_roof_point(sp, 0.0, 80.0) + Vector3(0, 1, 0))
	player.yaw = 0.6
	player.pitch = -0.25
	await _wait(1.5)
	await _shot("look_rooftop")
	Game.daynight.hour = 18.6
	await _wait(1.0)
	await _shot("look_sunset")
	player.respawn(sp)
	player.yaw = 0.0
	player.pitch = 0.05
	var wx: Node = Game.get_meta("weather")
	wx.set_weather(1)
	wx._wet = 1.0
	Game.daynight.cloud_dark = 0.75
	Game.daynight.cloud_cover = 0.9
	Game.daynight.hour = 13.0
	await _wait(1.5)
	await _shot("look_rain")
	Game.daynight.hour = 23.0
	await _wait(1.0)
	await _shot("look_rain_night")
	wx.set_weather(0)
	wx._wet = 0.0
	Game.city.set_wetness(0.0)
	Game.daynight.cloud_dark = 0.0
	Game.daynight.cloud_cover = 0.45
	await _wait(1.0)
	await _shot("look_night")
	# close-up of people
	Game.daynight.hour = 14.0
	var civ: Node3D = Game.military.spawn_npc("civilian", sp + Vector3(0, 0, -3.5))
	var sol: Node3D = Game.military.spawn_npc("soldier", sp + Vector3(1.4, 0, -4.0))
	civ.set_physics_process(false)
	sol.set_physics_process(false)
	civ.model.rotation.y = PI
	sol.model.rotation.y = PI
	player.pitch = -0.1
	await _wait(1.0)
	await _shot("look_people")
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
