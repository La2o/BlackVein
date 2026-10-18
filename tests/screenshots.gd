extends Node
## Captures a set of screenshots for checking how things look.
##   godot --path . res://tests/screenshots.tscn -- shots=<folder>

const MAIN := preload("res://scenes/main.tscn")

var main: Node3D
var player: Player
var dir := "user://shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			dir = a.substr(6)
	Game.use_test_storage()
	Game.delete_save()
	Game.reset_state()
	main = MAIN.instantiate()
	add_child(main)
	await _wait(0.6)
	player = Game.player
	Game.director.set_process(false)
	Game.hud._title_timer = 0.0
	Game.level = 20
	for id in Game.SKILLS:
		Game.skills[id] = Game.SKILLS[id][5]
	player.apply_upgrades()
	player.invuln_timer = 9999.0
	await _wait(1.0)

	# Leviathan
	var sp := Game.city.spawn_point
	Game.director.start_random_event("leviathan")
	var boss: Node3D = Game.boss
	boss.global_position = sp + Vector3(0, 3, -22)
	player.yaw = 0.0
	player.pitch = 0.05
	await _wait(1.2)
	await _shot("boss_leviathan")
	boss.queue_free()
	Game.director.active_events.clear()
	await _wait(0.3)

	# Juggernaut
	Game.director.start_random_event("juggernaut")
	var jug: Node3D = Game.boss
	jug.global_position = sp + Vector3(0, 0.3, -30)
	await _wait(1.0)
	await _shot("boss_juggernaut")
	jug.queue_free()
	Game.director.active_events.clear()

	# Patient Zero
	Game.director.start_random_event("origin")
	var pz: Node3D = Game.boss
	pz.global_position = sp + Vector3(0, 1, -12)
	pz.set_physics_process(false)
	player.powers.set_form(6)
	await _wait(1.0)
	await _shot("boss_patient_zero")
	pz.queue_free()
	Game.director.active_events.clear()
	player.powers.set_form(0)

	# outbreak hive with infected ground
	Game.director.start_random_event("outbreak")
	await _wait(0.3)
	var hive: Node3D = get_tree().get_nodes_in_group("hives")[0]
	hive.global_position = sp + Vector3(0, 0, -24)
	player.pitch = -0.35
	await _wait(1.0)
	await _shot("outbreak")
	hive.queue_free()
	Game.director.active_events.clear()
	player.pitch = 0.05

	# traffic and crowd
	for k in 8:
		Game.director._maintain_population()
		await _wait(0.1)
	await _wait(2.0)
	await _shot("street_life")

	# rainy night with thermal
	Game.daynight.hour = 22.5
	var wx: Node = Game.get_meta("weather")
	wx.set_weather(1)
	await _wait(3.0)
	await _shot("rain_night")
	player.powers.set_thermal(true)
	await _wait(0.6)
	await _shot("thermal")
	player.powers.set_thermal(false)
	wx.set_weather(0)
	Game.daynight.hour = 14.0

	# claws form close-up and combo
	player.powers.set_form(1)
	for k in 12:
		Game.register_hit()
	await _wait(0.5)
	await _shot("claws_combo")

	# menus
	Game.hud.open_evolve()
	await _wait(0.2)
	await _shot("menu_skills")
	Game.hud.close_evolve()
	Game.hud.open_settings()
	await _wait(0.2)
	await _shot("menu_settings")
	Game.hud.close_settings()
	Game.hud.toggle_pause(false)
	Game.hud.help_panel.visible = true
	await _wait(0.2)
	await _shot("menu_controls")
	Game.hud.help_panel.visible = false
	Game.stat_add("consumes")
	await _wait(1.0)
	Game.hud.toggle_pause(true)
	Game.hud.ach_panel.visible = true
	Game.hud._refresh_achievements()
	await _wait(0.2)
	await _shot("menu_pause_achievements")
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
