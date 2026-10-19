extends Node
## Screenshots of the bio weapons in BLACKVEIN's hand.
##   godot --path . res://tests/look_bio.tscn -- shots=<folder>

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
	for n in get_tree().get_nodes_in_group("npcs"):
		n.queue_free()
	await _wait(0.3)
	var base: Vector3 = Game.city.spawn_point
	for id in ["bio_blade", "bio_gun", "bone_javelin", "spore_launcher"]:
		Game.skills[id] = 1
	p.biomass = p.max_biomass
	p.respawn(base)
	p.yaw = 0.0
	var cam := Camera3D.new()
	add_child(cam)
	await _wait(0.5)
	var shots := [["bio_blade", "Sword_Regular_A", 0.18], ["bio_blade", "Sword_Regular_C", 0.5], ["bio_gun", "", 0.0], ["javelin", "OverhandThrow", 0.35], ["spore", "", 0.0]]
	var i := 0
	for sh in shots:
		p.powers.grow_bio(sh[0])
		p.biomass = p.max_biomass
		var side := p.global_transform.basis.x
		cam.make_current()
		cam.global_position = p.global_position + side * 2.6 - p.facing * 1.2 + Vector3.UP * 1.2
		cam.look_at(p.global_position + Vector3.UP * 0.6 + p.facing * 0.6)
		await _wait(0.4)
		if sh[1] != "":
			p.model.oneshot(sh[1], 1.0)
			await _wait(sh[2])
		await _shot("bio_%d_%s" % [i, sh[0]])
		i += 1
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
