extends Node
## Animation quality meter.
##   godot --headless --fixed-fps 60 --path . res://tests/anim_slip.tscn                 foot slide + gait switches
##   godot --headless --fixed-fps 60 --path . res://tests/anim_slip.tscn -- calibrate    natural speed of each cycle
## Foot slide: moves a person at a steady speed while it animates and measures how fast the planted
## foot slides over the ground (0 = it sticks). Pops: speeds up from standing to a sprint and back,
## looking for single frames where the legs jump (1x = smooth).
## test_runner.gd uses measure() and ramp() too.

const PLAYER_MODEL := preload("res://scripts/player_model.gd")


func _ready() -> void:
	if get_tree().current_scene != self:
		return   # used as a helper by test_runner.gd
	Game.use_test_storage()
	if "calibrate" in OS.get_cmdline_user_args():
		await _calibrate()
		get_tree().quit()
		return
	var npc := PersonModel.new()
	npc.foot_offset = -0.9
	add_child(npc)
	npc.setup({"body": "m"})
	for v in [1.0, 1.6, 2.4, 3.5, 5.0]:
		var r: Dictionary = await measure(npc, v, "walk" if v < 2.0 else "run")
		print("SLIP npc    %4.1f m/s  %-8s slide %.2f m/s (%.0f%%)" % [v, r["anim"], r["slip"], r["slip"] / v * 100.0])
	var pm: Node3D = Node3D.new()
	pm.set_script(PLAYER_MODEL)
	add_child(pm)
	pm.build()
	for v in [1.5, 2.8, 4.0, 6.0, 7.5, 9.0, 12.0, 18.0, 26.0]:
		var r: Dictionary = await measure(pm, v, "walk" if v < 8.0 else "run")
		print("SLIP player %4.1f m/s  %-8s slide %.2f m/s (%.0f%%)" % [v, r["anim"], r["slip"], r["slip"] / v * 100.0])
	var pop: Dictionary = await ramp(pm, true)
	print("RAMP worst switch x%.2f (%s)" % [pop["ratio"], pop["at"]])
	get_tree().quit()


## For each cycle: the playback rate where the foot sticks at 4 m/s, i.e. its natural ground speed.
func _calibrate() -> void:
	var npc := PersonModel.new()
	npc.foot_offset = -0.9
	add_child(npc)
	npc.setup({"body": "m"})
	print("CAL body height %.3f m" % npc.height_m)
	for a in ["Walk", "Jog_Fwd", "Sprint", "Crouch_Fwd", "Walk_Carry", "Zombie_Walk_Fwd", "Walk_Formal"]:
		var best := 0.0
		var best_slip := INF
		var rate := 0.25
		while rate < 6.0:
			var r: Dictionary = await measure(npc, 4.0, "", a, rate)
			if r["n"] > 10 and r["slip"] < best_slip:
				best_slip = r["slip"]
				best = rate
			rate *= 1.06
		print("CAL %-16s natural %.2f m/s = %.3f body heights/s (slide left %.2f)" % [a, 4.0 / best, 4.0 / best / npc.height_m, best_slip])


## Runs `model` forward at `speed` for a while and returns {slip, anim, n}: how fast the point of the
## foot touching the ground slides (median, m/s), the animation that was playing, and the samples.
func measure(model: Node3D, speed: float, mode: String, anim_name := "", rate := 1.0) -> Dictionary:
	var sk: Skeleton3D = model.skeleton
	# heels and toes: whichever is lowest is the point touching the ground
	var points := []
	for bn in ["foot_l", "ball_l", "foot_r", "ball_r"]:
		points.append(sk.find_bone(bn))
	model.global_position = Vector3.ZERO
	var dt := 1.0 / 60.0
	for i in 40:   # settle into the cycle first
		model.global_position += Vector3.FORWARD * speed * dt
		_step(model, dt, speed, mode, anim_name, rate)
		await get_tree().process_frame
	var hist: Array = []
	var lowest := INF
	for i in 180:
		model.global_position += Vector3.FORWARD * speed * dt
		_step(model, dt, speed, mode, anim_name, rate)
		await get_tree().process_frame
		var now := []
		for b in points:
			var p: Vector3 = sk.global_transform * _gpose(sk, b).origin
			now.append(p)
			lowest = minf(lowest, p.y)
		hist.append(now)
	var slides: Array[float] = []
	for i in range(1, hist.size()):
		var k := 0
		for j in 4:
			if (hist[i][j] as Vector3).y < (hist[i][k] as Vector3).y:
				k = j
		var cur: Vector3 = hist[i][k]
		var before: Vector3 = hist[i - 1][k]
		if cur.y < lowest + 0.025:
			slides.append(Vector2(cur.x - before.x, cur.z - before.z).length() / dt)
	slides.sort()
	var med: float = slides[slides.size() / 2] if slides.size() > 0 else speed
	return {"slip": med, "anim": str(model.get("_current")), "n": slides.size()}


## Speeds up from standing to a flat-out sprint and back down, and looks for pops: a frame where the
## legs move far more than in the frames around it (1x = smooth). Returns {ratio, at} for the worst.
func ramp(model: Node3D, verbose := false) -> Dictionary:
	var sk: Skeleton3D = model.skeleton
	var bones := []
	for bn in ["thigh_l", "thigh_r", "calf_l", "calf_r"]:
		bones.append(sk.find_bone(bn))
	var dt := 1.0 / 60.0
	var prev := {}
	var frames: Array = []   # [animation, biggest leg change this frame, speed]
	var t := 0.0
	while t < 10.0:
		var v := 26.0 * (t / 5.0 if t < 5.0 else (10.0 - t) / 5.0)
		model.global_position += Vector3.FORWARD * v * dt
		model.animate(dt, v, "idle" if v < 0.8 else ("walk" if v < 8.0 else "run"))
		await get_tree().process_frame
		var big := 0.0
		for b in bones:
			var q := sk.get_bone_pose_rotation(b)
			if prev.has(b):
				big = maxf(big, rad_to_deg((prev[b] as Quaternion).angle_to(q)))
			prev[b] = q
		frames.append([str(model.get("_current")), big, v])
		t += dt
	# a pop is one frame that moves far more than the frames around it
	var worst := 0.0
	var at := ""
	for i in range(4, frames.size() - 4):
		var around: Array[float] = []
		for k in range(i - 3, i + 4):
			if k != i:
				around.append(frames[k][1])
		around.sort()
		var ratio: float = frames[i][1] / maxf(around[around.size() / 2], 1.0)
		if frames[i][0] != frames[i - 1][0] and verbose:
			var seq := []
			for k in range(i - 3, i + 4):
				seq.append("%.0f" % frames[k][1])
			print("RAMP %s -> %s at %.1f m/s: spike x%.2f  frames %s" % [frames[i - 1][0], frames[i][0], frames[i][2], ratio, " ".join(seq)])
		if ratio > worst:
			worst = ratio
			at = "%s at %.1f m/s" % [frames[i][0], frames[i][2]]
	return {"ratio": worst, "at": at}


func _step(model: Node3D, dt: float, speed: float, mode: String, anim_name: String, rate: float) -> void:
	if anim_name != "":
		model.play(anim_name, 0.0, rate)
	else:
		model.animate(dt, speed, mode)


static func _gpose(sk: Skeleton3D, b: int) -> Transform3D:
	var t := sk.get_bone_pose(b)
	var p := sk.get_bone_parent(b)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return t
