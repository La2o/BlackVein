extends CharacterBody3D
## Tanks and military trucks. They drive along the street grid, tanks fire
## shells at the player and the infected, trucks drop off soldiers.
## The player can hijack a tank and drive it (WASD + mouse, click to fire).

const PROJECTILE := preload("res://scripts/projectile.gd")
const NPC := preload("res://scripts/npc.gd")

var kind := "tank"
var hp := 700.0
var max_hp := 700.0
var speed := 10.0
var heading := 0.0                 # yaw in radians
var destroyed := false
var pilot: Node = null
var abandoned := false
var event_tag := ""
var route: Array[Vector2i] = []    # convoy route (optional)
var deployed := false
var boss_name := ""
var _mg_timer := 2.0
var _mg_burst := 0

var _cell := Vector2i.ZERO
var _prev_cell := Vector2i(-99, -99)
var _next_cell := Vector2i.ZERO
var _turret: Node3D
var _barrel: Node3D
var _fire_timer := 2.0
var _think_timer := 0.0
var _target: Node3D = null
var _sees_player := false
var _hull_mats: Array[MeshInstance3D] = []
var _engine: AudioStreamPlayer3D
var _crush_timer := 0.0
var _wreck_timer := 0.0
var _fire: CPUParticles3D


func setup(k: String, extra := {}) -> void:
	kind = k
	event_tag = extra.get("tag", "")
	if extra.has("route"):
		route.assign(extra["route"])
	if kind == "tank":
		hp = 700.0
		speed = 9.0
	elif kind == "juggernaut":
		hp = 3600.0
		speed = 7.0
		boss_name = "JUGGERNAUT"
	else:
		hp = 260.0
		speed = 13.0
	max_hp = hp
	collision_layer = Game.LAYER_VEHICLE
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS
	floor_snap_length = 0.5
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.4, 2.4, 6.4) if kind == "tank" else Vector3(2.6, 2.8, 7.0)
	if kind == "juggernaut":
		box.size = Vector3(5.6, 4.0, 10.4)
	shape.shape = box
	shape.position = Vector3(0, box.size.y * 0.5, 0)
	add_child(shape)
	_build_model()
	add_to_group("vehicles")
	add_to_group("military")
	add_to_group("military_vehicles")
	if kind == "tank" or kind == "juggernaut":
		add_to_group("hijackable")
	heading = rotation.y
	rotation = Vector3.ZERO
	_cell = Game.city.nearest_intersection(global_position)
	_next_cell = _cell
	_engine = Game.fx.make_loop_player("helicopter")
	_engine.pitch_scale = 0.45
	_engine.volume_db = -14.0
	add_child(_engine)


func _build_model() -> void:
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.3, 0.33, 0.22)
	olive.roughness = 0.75
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.07)
	dark.roughness = 0.9
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	if kind == "juggernaut":
		olive.albedo_color = Color(0.12, 0.12, 0.13)
		olive.metallic = 0.5
		body.scale = Vector3.ONE * 1.65
	if kind == "tank" or kind == "juggernaut":
		_box(body, Vector3(3.2, 1.0, 6.0), Vector3(0, 1.0, 0), olive)
		_box(body, Vector3(0.7, 0.9, 6.4), Vector3(-1.55, 0.5, 0), dark)
		_box(body, Vector3(0.7, 0.9, 6.4), Vector3(1.55, 0.5, 0), dark)
		_turret = Node3D.new()
		_turret.position = Vector3(0, 1.75, 0.3)
		body.add_child(_turret)
		_box(_turret, Vector3(2.2, 0.85, 2.8), Vector3.ZERO, olive)
		_barrel = Node3D.new()
		_barrel.position = Vector3(0, 0.1, -1.3)
		_turret.add_child(_barrel)
		var b := _box(_barrel, Vector3(0.28, 0.28, 3.6), Vector3(0, 0, -1.8), dark)
		b.name = "Gun"
	else:
		_box(body, Vector3(2.5, 2.0, 2.2), Vector3(0, 1.5, -2.3), olive)
		_box(body, Vector3(2.3, 0.6, 1.0), Vector3(0, 2.0, -3.0), dark)
		_box(body, Vector3(2.6, 0.5, 4.6), Vector3(0, 0.9, 1.1), olive)
		var canvas := StandardMaterial3D.new()
		canvas.albedo_color = Color(0.36, 0.36, 0.27)
		_box(body, Vector3(2.6, 1.8, 4.6), Vector3(0, 2.05, 1.1), canvas)
		for z in [-2.3, 0.4, 2.4]:
			for x in [-1.15, 1.15]:
				var w := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.5
				cm.bottom_radius = 0.5
				cm.height = 0.35
				w.mesh = cm
				w.material_override = dark
				w.rotation.z = PI * 0.5
				w.position = Vector3(x, 0.5, z)
				body.add_child(w)


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	_hull_mats.append(mi)
	return mi


# ------------------------------------------------------------------ API

func is_alive() -> bool:
	return not destroyed


func is_player_controlled() -> bool:
	return pilot != null


func can_see_point(p: Vector3) -> bool:
	return Game.line_of_sight(global_position + Vector3.UP * 2.6, p)


func camera_distance() -> float:
	return 13.0


func can_hijack(by: Node) -> bool:
	if kind == "juggernaut" and hp > max_hp * 0.25:
		return false
	return kind != "truck" and not destroyed and pilot == null and (by as Node3D).global_position.distance_to(global_position) < 9.0 + (4.0 if kind == "juggernaut" else 0.0)


func hijack(by: Node) -> void:
	pilot = by
	if by == Game.player:
		Game.stat_add("tanks")
	abandoned = false
	remove_from_group("military")
	add_to_group("player_vehicle")
	Game.fx.splat(global_position + Vector3.UP * 2.5, Vector3.UP, Color(0.5, 0.02, 0.02), 16)


func on_pilot_exit() -> void:
	pilot = null
	abandoned = true
	remove_from_group("player_vehicle")


func take_hit(info: Dictionary) -> void:
	if destroyed:
		return
	var dmg: float = info["damage"]
	match info["kind"]:
		"bullet": dmg *= 0.1
		"melee", "impact": dmg *= 0.6
		"explosion": dmg *= 1.3
	var src: Node = info["source"]
	if src == Game.player and pilot == null:
		Game.raise_alert(Game.player.global_position, "You attacked a military vehicle")
		Game.add_heat(0.1)
	hp -= dmg
	if src == Game.player and dmg > 1.0:
		Game.register_hit()
	Game.fx.debris(global_position + Vector3.UP * 2.0, 3, Color(0.3, 0.32, 0.22))
	if kind == "truck" and not deployed:
		_deploy_soldiers()
	if hp <= 0.0:
		_destroy(src)


func _destroy(src: Node) -> void:
	destroyed = true
	remove_from_group("military")
	remove_from_group("hijackable")
	remove_from_group("military_vehicles")
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = Color(0.07, 0.06, 0.05)
	for m in _hull_mats:
		m.material_override = burnt
	Game.explode(global_position + Vector3.UP * 1.5, 9.0, 80.0, self, 20.0)
	Game.fx.debris(global_position + Vector3.UP * 2.0, 20, Color(0.2, 0.2, 0.18))
	_fire = Game.fx.make_fire()
	add_child(_fire)
	_fire.position = Vector3(0, 2.0, 0)
	_fire.emitting = true
	if _turret:
		_turret.rotation.z = 0.4
		_turret.position += Vector3(0.5, 0.3, 0)
	_engine.stop()
	if pilot:
		var p := pilot
		on_pilot_exit()
		p.exit_vehicle(Vector3(0, 18, 0))
	if src == Game.player or (src and is_instance_valid(src) and src.has_method("is_player_controlled") and src.is_player_controlled()):
		if kind != "truck":
			Game.stat_add("tanks")
		var rewards := {"tank": 80, "truck": 35, "juggernaut": 900}
		var names := {"tank": "Tank", "truck": "Truck", "juggernaut": "JUGGERNAUT"}
		Game.add_xp(rewards[kind], "%s destroyed" % names[kind])
		Game.add_heat(0.4)
	get_tree().call_group("event_listeners", "on_unit_removed", self, "destroyed")
	_wreck_timer = 45.0


# ------------------------------------------------------------------ loop

func _physics_process(delta: float) -> void:
	if destroyed:
		_wreck_timer -= delta
		if _wreck_timer < 30.0 and _fire:
			_fire.emitting = false
		if _wreck_timer <= 0.0:
			queue_free()
		velocity = Vector3(0, velocity.y - 30.0 * delta, 0)
		move_and_slide()
		return
	_fire_timer -= delta
	if pilot:
		_drive_piloted(delta)
	elif abandoned:
		velocity.x = move_toward(velocity.x, 0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 10.0 * delta)
	else:
		_think_timer -= delta
		if _think_timer <= 0.0:
			_think_timer = 0.4
			_think()
		_drive_ai(delta)
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	else:
		velocity.y = -1.0
	var pre := velocity
	move_and_slide()
	rotation.y = heading
	_crush(pre, delta)


func _think() -> void:
	var p := Game.player
	_sees_player = false
	_target = null
	if p and not p.is_dead():
		var pp: Vector3 = p.global_position
		if p.vehicle and is_instance_valid(p.vehicle):
			pp = (p.vehicle as Node3D).global_position
		var d := global_position.distance_to(pp)
		if d < 110.0 and can_see_point(pp + Vector3.UP * 0.5):
			_sees_player = true
			Game.report_sighting(pp, p.is_conspicuous(), global_position, 0.4)
			if Game.is_hunted():
				_target = p.vehicle if p.vehicle else p
	if kind == "juggernaut" and p and not p.is_dead():
		var dj := global_position.distance_to(p.global_position)
		if dj < 170.0:
			_target = p.vehicle if p.vehicle else p
			if not Game.is_hunted() and _sees_player:
				Game.raise_alert(p.global_position, "The Juggernaut has found you")
	if _target == null and kind != "truck":
		var h := Game.nearest_in_group("hunters", global_position, 80.0)
		if h == null:
			h = Game.nearest_in_group("infected", global_position, 50.0)
		if h and can_see_point(h.global_position):
			_target = h
	if kind == "truck" and not deployed and Game.is_hunted() and _sees_player and global_position.distance_to(p.global_position) < 50.0:
		_deploy_soldiers()


func _drive_ai(delta: float) -> void:
	var stop := false
	if _target and is_instance_valid(_target):
		var d := global_position.distance_to(_target.global_position)
		if kind != "truck" and d < (40.0 if kind == "juggernaut" else 55.0):
			stop = true
		_aim_turret(_target.global_position, delta)
		if kind == "tank" and _fire_timer <= 0.0 and d < 110.0:
			_fire_shell(_target.global_position + Vector3.UP * 0.5, _target)
			_fire_timer = randf_range(3.2, 4.5)
		elif kind == "juggernaut" and d < 140.0 and can_see_point(_target.global_position + Vector3.UP):
			if _fire_timer <= 0.0:
				for k in 3:
					var spread := Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)) * (k * 0.8)
					_fire_shell(_target.global_position + Vector3.UP * 0.5 + spread, _target)
				_fire_timer = 4.5 if hp > max_hp * 0.4 else 3.0
			_mg_timer -= delta
			if _mg_timer <= 0.0:
				if _mg_burst <= 0:
					_mg_burst = 12
				_machine_gun(_target.global_position)
				_mg_burst -= 1
				_mg_timer = 0.09 if _mg_burst > 0 else 1.8
	elif _turret:
		_turret.rotation.y = lerp_angle(_turret.rotation.y, 0.0, delta)
	if kind == "truck" and deployed:
		stop = true
	var goal_pos := Game.city.intersection_pos(_next_cell)
	var seg := goal_pos - Game.city.intersection_pos(_prev_cell if _prev_cell.x > -50 else _cell)
	seg.y = 0
	var lane := Vector3.ZERO
	if seg.length() > 1.0:
		lane = seg.normalized().cross(Vector3.UP) * 3.6
	var to := goal_pos + lane - global_position
	to.y = 0
	if to.length() < 5.0:
		_choose_next()
	var want := atan2(-to.x, -to.z)
	var diff := wrapf(want - heading, -PI, PI)
	heading += clampf(diff, -1.4 * delta, 1.4 * delta)
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, heading)
	var target_speed := 0.0 if stop else speed * clampf(1.0 - absf(diff) / PI * 1.5, 0.25, 1.0)
	var cur := Vector3(velocity.x, 0, velocity.z).length()
	cur = move_toward(cur, target_speed, 8.0 * delta)
	velocity.x = fwd.x * cur
	velocity.z = fwd.z * cur


func _choose_next() -> void:
	_prev_cell = _cell
	_cell = _next_cell
	if not route.is_empty():
		_next_cell = route.pop_front()
		return
	var options: Array[Vector2i] = []
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = _cell + o
		if c.x < 0 or c.y < 0 or c.x > Game.city.blocks or c.y > Game.city.blocks:
			continue
		if c == _prev_cell:
			continue
		options.append(c)
	if options.is_empty():
		_next_cell = _prev_cell
		return
	var hunting := event_tag.begins_with("hunt")
	if Game.alert_level != Game.Alert.HIDDEN or hunting:
		var goal_pos: Vector3 = Game.player.global_position if hunting else Game.last_known_pos
		var goal := Game.city.nearest_intersection(goal_pos)
		options.sort_custom(func(a, b): return (a - goal).length_squared() < (b - goal).length_squared())
		_next_cell = options[0] if randf() < 0.85 else options[randi() % options.size()]
	else:
		_next_cell = options[randi() % options.size()]


func _aim_turret(at: Vector3, delta: float) -> void:
	if _turret == null:
		return
	var local := to_local(at)
	var want := atan2(-local.x, -local.z)
	_turret.rotation.y = lerp_angle(_turret.rotation.y, want, 3.0 * delta)


func _fire_shell(at: Vector3, homing: Node3D = null) -> void:
	if _barrel == null:
		return
	var muzzle: Vector3 = _barrel.global_position + (-_barrel.global_transform.basis.z).normalized() * (3.8 if kind != "juggernaut" else 6.3)
	var dir := (at - muzzle).normalized()
	var p := Node3D.new()
	p.set_script(PROJECTILE)
	get_parent().add_child(p)
	p.launch(muzzle, dir * 70.0, self, "shell")
	Game.fx.flash_light(muzzle, Color(1, 0.7, 0.4), 8.0, 15.0, 0.15)
	Game.fx.smoke_column(muzzle, Color(0.5, 0.48, 0.45, 0.6), 0.2)
	Game.fx.sound("tank_shot", muzzle, 4.0)
	if pilot:
		pilot.add_trauma(0.3)
	elif Game.player and Game.player.global_position.distance_to(global_position) < 60.0:
		Game.player.add_trauma(0.15)
	Game.panic_at(global_position, 50.0)


func _machine_gun(at: Vector3) -> void:
	var muzzle := global_position + Vector3.UP * 4.2
	var dir := (at + Vector3.UP * randf_range(-0.3, 0.6) - muzzle).normalized()
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.04).normalized()
	var hit := Game.raycast(muzzle, muzzle + dir * 150.0, Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_NPC | Game.LAYER_PROPS, [get_rid()])
	var end := muzzle + dir * 150.0
	if not hit.is_empty():
		end = hit["position"]
		var c := hit["collider"] as Node
		if c and c.has_method("take_hit") and not c.is_in_group("military"):
			c.take_hit(Game.hit_info(4.0, dir * 2.0, self, "bullet"))
	Game.fx.tracer(muzzle, end, Color(1.0, 0.85, 0.4), 0.07)
	Game.fx.sound("gunshot", muzzle, -2.0, 0.1)


func _drive_piloted(delta: float) -> void:
	var p := pilot
	var throttle := Input.get_axis("move_back", "move_forward")
	var steer := Input.get_axis("move_right", "move_left")
	heading += steer * 1.5 * delta * (1.0 if throttle >= -0.1 else -1.0)
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, heading)
	var cur := Vector3(velocity.x, 0, velocity.z).dot(fwd)
	var top := 17.0 if Input.is_action_pressed("sprint") else 12.0
	cur = move_toward(cur, throttle * top, 14.0 * delta)
	velocity.x = fwd.x * cur
	velocity.z = fwd.z * cur
	var aim: Dictionary = p.aim_point(300.0)
	_aim_turret(aim["position"], delta * 2.0)
	if Input.is_action_just_pressed("attack") and _fire_timer <= 0.0:
		_fire_shell(aim["position"])
		_fire_timer = 1.2
		p.conspicuous_timer = 4.0


func _crush(pre: Vector3, delta: float) -> void:
	var hv := Vector3(pre.x, 0, pre.z)
	var spd := hv.length()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb and spd > 2.0:
			rb.sleeping = false
			rb.apply_central_impulse((-c.get_normal() * spd + Vector3.UP * 2.0) * rb.mass * 0.4)
			if rb.has_method("take_hit") and spd > 6.0:
				rb.take_hit(Game.hit_info(spd * 1.5, Vector3.ZERO, self if pilot == null else pilot, "impact"))
	_crush_timer -= delta
	if spd < 4.0 or _crush_timer > 0.0:
		return
	_crush_timer = 0.15
	var front := global_position + hv.normalized() * 3.2 + Vector3.UP
	for n in get_tree().get_nodes_in_group("npcs"):
		var o := n as Node3D
		if o and o.global_position.distance_to(front) < 2.6 and o.has_method("take_hit") and o.call("is_alive"):
			var src: Node = pilot if pilot else self
			if pilot == null and o.is_in_group("military"):
				continue
			o.take_hit(Game.hit_info(spd * 6.0, hv.normalized() * spd * 0.8 + Vector3.UP * 6.0, src, "impact"))


func _deploy_soldiers() -> void:
	deployed = true
	var back := global_position + Vector3.BACK.rotated(Vector3.UP, heading) * 4.5
	for k in 4:
		var s := CharacterBody3D.new()
		s.set_script(NPC)
		get_parent().add_child(s)
		s.global_position = back + Vector3(randf_range(-2, 2), 0.5, randf_range(-1, 1))
		s.setup("rocket_soldier" if k == 0 else "soldier", {"tag": event_tag})
		s.patrol_center = global_position
	Game.feed("Soldiers deploying from a truck", Color(1, 0.6, 0.4))
