extends Node
## Frame-time profiler: the real game in a window, world fully active, the player sprinting
## through the streets with the military after them. Prints fps, the worst frames and where time goes.
##   godot --path . res://tests/profile.tscn -- seconds=40 [old=1]   (old=1: code-built NPCs, for A/B)

const MAIN := preload("res://scenes/main.tscn")
var seconds := 40.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seconds="):
			seconds = float(a.substr(8))
		if a == "old=1":
			NPC_SCRIPT.use_old_models = true
	Game.use_test_storage()
	Game.delete_save()
	Game.reset_state()
	var main: Node3D = MAIN.instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	var p: Player = Game.player
	p.invuln_timer = 9999.0
	Game.hud._title_timer = 0.0
	var frames: Array[float] = []
	var proc: Array[float] = []
	var phys: Array[float] = []
	var spikes := []
	var t := 0.0
	var last_npcs := get_tree().get_nodes_in_group("npcs").size()
	var alerted := false
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		p.invuln_timer = 9999.0
		if p.is_dead():
			continue
		# run down the streets, turning now and then, jumping sometimes
		Input.action_press("move_forward")
		Input.action_press("sprint")
		if int(t * 10.0) % 60 == 0:
			p.yaw += 0.03
		if not alerted and t > 10.0:
			alerted = true
			Game.raise_alert(p.global_position, "profile")
		frames.append(dt * 1000.0)
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		var npcs := get_tree().get_nodes_in_group("npcs").size()
		if dt > 0.033:
			spikes.append("%.0f ms at %.1f s, npcs %d (+%d)" % [dt * 1000.0, t, npcs, npcs - last_npcs])
		last_npcs = npcs
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var sorted := frames.duplicate()
	sorted.sort()
	var avg := 0.0
	for f in frames:
		avg += f
	avg /= maxf(frames.size(), 1)
	var p99: float = sorted[int(sorted.size() * 0.99)]
	var over33 := frames.filter(func(f): return f > 33.0).size()
	var over50 := frames.filter(func(f): return f > 50.0).size()
	var pavg := 0.0
	var phavg := 0.0
	for i in proc.size():
		pavg += proc[i]
		phavg += phys[i]
	pavg /= maxf(proc.size(), 1)
	phavg /= maxf(phys.size(), 1)
	print("PROFILE %s: avg %.1f fps (%.1f ms), worst 1%% %.1f ms, frames >33ms %d, >50ms %d of %d" % [
		"old people" if NPC_SCRIPT.use_old_models else "new people", 1000.0 / avg, avg, p99, over33, over50, frames.size()])
	print("PROFILE time: process %.1f ms, physics %.1f ms, draw calls %d, nodes %d, npcs %d" % [pavg, phavg,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		get_tree().get_nodes_in_group("npcs").size()])
	for s in spikes.slice(0, 12):
		print("PROFILE spike: ", s)
	Game.delete_save()
	get_tree().quit()


const NPC_SCRIPT := preload("res://scripts/npc.gd")
