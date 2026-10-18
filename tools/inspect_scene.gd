extends SceneTree
## Prints a scene's node tree and its animation track paths.
##   godot --headless --path . --script res://tools/inspect_scene.gd -- res://path/to/scene.glb
func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var scene: Node = (load(path) as PackedScene).instantiate()
		print("== ", path)
		_dump(scene, 0)
		var ap := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			var names := ap.get_animation_list()
			print("animations: ", names.size(), "  root_node: ", ap.root_node)
			var a := ap.get_animation(names[1])
			for t in mini(a.get_track_count(), 4):
				print("  track ", a.track_get_path(t), "  type ", a.track_get_type(t))
		scene.free()
	quit()


func _dump(n: Node, depth: int) -> void:
	if depth > 4:
		return
	var extra := ""
	if n is Skeleton3D:
		extra = "  bones %d" % (n as Skeleton3D).get_bone_count()
	if n is MeshInstance3D:
		extra = "  surfaces %d" % (n as MeshInstance3D).mesh.get_surface_count()
	print("  ".repeat(depth), n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_dump(c, depth + 1)
