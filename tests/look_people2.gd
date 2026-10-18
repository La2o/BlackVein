extends Node
## Screenshots of the rigged Quaternius people (scripts/person.gd) in a few outfits and animations.
##   godot --path . res://tests/look_people2.tscn -- shots=<folder>

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
	Game.hud.visible = false
	Game.hud._title_timer = 0.0
	Game.director.set_process(false)
	Game.military.set_process(false)
	Game.daynight.hour = 13.0
	var p: Player = Game.player
	p.set_physics_process(false)
	p.visible = false
	for n in get_tree().get_nodes_in_group("npcs"):
		n.queue_free()
	var base := p.global_position + Vector3(0, 30, 0)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.36, 0.38)
	floor_mi.material_override = fm
	add_child(floor_mi)
	floor_mi.global_position = base
	var looks := [
		{"body": "m", "skin": Color(1, 1, 1), "hair": "parted", "shirt": Color(0.2, 0.35, 0.6), "pants": Color(0.18, 0.22, 0.35), "denim": true, "long_sleeves": false, "anim": "Idle"},
		{"body": "f", "skin": Color(0.62, 0.47, 0.38), "hair": "long", "hair_color": Color(0.08, 0.06, 0.05), "shirt": Color(0.7, 0.2, 0.2), "pants": Color(0.12, 0.12, 0.14), "anim": "Walk"},
		{"body": "m", "skin": Color(0.85, 0.72, 0.6), "hair": "buzzed", "camo": true, "shirt": Color(0.3, 0.33, 0.22), "pants": Color(0.27, 0.29, 0.2), "shoes": Color(0.08, 0.07, 0.06), "anim": "Pistol_Idle"},
		{"body": "f", "skin": Color(1, 0.95, 0.9), "hair": "buns", "hair_color": Color(0.5, 0.25, 0.1), "shirt": Color(0.92, 0.92, 0.9), "pants": Color(0.3, 0.32, 0.38), "anim": "Idle_Talking"},
		{"body": "m", "skin": Color(0.55, 0.62, 0.5), "hair": "", "shirtless": true, "pants": Color(0.25, 0.22, 0.2), "glow": Color(1, 0.15, 0.05), "anim": "Jog_Fwd"},
		{"body": "m", "skin": Color(0.95, 0.85, 0.75), "hair": "buzzed", "beard": true, "shirt": Color(0.06, 0.06, 0.07), "pants": Color(0.07, 0.07, 0.08), "anim": "Sprint"},
	]
	for i in looks.size():
		var person := Person.new()
		add_child(person)
		person.global_position = base + Vector3((i - looks.size() * 0.5 + 0.5) * 1.3, 0, 0)
		person.setup(looks[i])
		person.play(looks[i]["anim"], 0.0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 38
	cam.global_position = base + Vector3(0, 1.3, -8.5)
	cam.look_at(base + Vector3(0, 0.95, 0))
	await _wait(1.0)
	await _shot("people2_lineup")
	cam.fov = 30
	cam.global_position = base + Vector3(-2.6, 1.55, -3.2)
	cam.look_at(base + Vector3(-2.6, 1.15, 0))
	await _wait(0.3)
	await _shot("people2_close")
	cam.global_position = base + Vector3(-4.0, 1.4, 4.0)
	cam.look_at(base + Vector3(-1.0, 0.9, 0))
	await _wait(0.3)
	await _shot("people2_back")
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
	print("shot ", shot_name)
