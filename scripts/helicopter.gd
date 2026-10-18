extends CharacterBody3D
## Military gunship. Circles its target, fires minigun bursts and homing
## missiles, avoids buildings. The player can hijack it and fly it:
## WASD to move, Space to climb, Shift to descend, click for missiles,
## right-click for the minigun. Jumping out lets it crash.

const PROJECTILE := preload("res://scripts/projectile.gd")

var hp := 420.0
var max_hp := 420.0
var destroyed := false
var falling := false
var pilot: Node = null
var event_tag := ""
var patrol_point := Vector3.ZERO
var parked := false

var _rotor: Node3D
var _tail_rotor: Node3D
var _orbit_angle := 0.0
var _orbit_dir := 1.0
var _think_timer := 0.0
var _target: Node3D = null
var _gun_timer := 2.0
var _burst := 0
var _missile_timer := 4.0
var _fall_timer := 0.0
var _sound: AudioStreamPlayer3D
var _parts: Array[MeshInstance3D] = []
var _smoke: CPUParticles3D
var _yaw := 0.0


func setup(extra := {}) -> void:
	event_tag = extra.get("tag", "")
	patrol_point = extra.get("patrol", global_position)
	collision_layer = Game.LAYER_VEHICLE
	collision_mask = Game.LAYER_WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.4, 7.0)
	shape.shape = box
	add_child(shape)
	_build_model()
	add_to_group("vehicles")
	add_to_group("military")
	add_to_group("military_vehicles")
	add_to_group("hijackable")
	add_to_group("helicopters")
	_sound = Game.fx.make_loop_player("helicopter")
	_sound.volume_db = -2.0
	add_child(_sound)
	_orbit_angle = randf() * TAU
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0


func _build_model() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.22, 0.25, 0.2)
	paint.roughness = 0.6
	paint.metallic = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.05)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.1, 0.15, 0.2)
	glass.metallic = 0.8
	glass.roughness = 0.1
	_part(BoxMesh, Vector3(2.2, 2.0, 4.2), Vector3(0, 0, 0.2), paint)
	_part(BoxMesh, Vector3(1.9, 1.3, 1.5), Vector3(0, 0.1, -2.4), glass)
	_part(BoxMesh, Vector3(0.6, 0.7, 5.0), Vector3(0, 0.4, 4.6), paint)
	_part(BoxMesh, Vector3(0.15, 1.6, 1.0), Vector3(0, 1.0, 6.9), paint)
	_part(BoxMesh, Vector3(0.12, 0.12, 4.0), Vector3(-1.1, -1.3, 0), dark)
	_part(BoxMesh, Vector3(0.12, 0.12, 4.0), Vector3(1.1, -1.3, 0), dark)
	_part(BoxMesh, Vector3(3.6, 0.15, 0.6), Vector3(0, -0.3, 0.2), paint)
	_part(BoxMesh, Vector3(0.35, 0.35, 1.4), Vector3(-1.8, -0.45, 0.0), dark)
	_part(BoxMesh, Vector3(0.35, 0.35, 1.4), Vector3(1.8, -0.45, 0.0), dark)
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 1.35, 0.2)
	add_child(_rotor)
	for k in 4:
		var blade := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.35, 0.05, 6.5)
		blade.mesh = b
		blade.material_override = dark
		blade.position = Vector3(0, 0, 0)
		blade.rotation.y = k * PI * 0.5
		blade.position = Vector3(sin(k * PI * 0.5), 0, cos(k * PI * 0.5)) * 3.2
		_rotor.add_child(blade)
	_tail_rotor = Node3D.new()
	_tail_rotor.position = Vector3(0.25, 1.0, 6.9)
	add_child(_tail_rotor)
	var tb := MeshInstance3D.new()
	var tbm := BoxMesh.new()
	tbm.size = Vector3(0.05, 2.0, 0.25)
	tb.mesh = tbm
	tb.material_override = dark
	_tail_rotor.add_child(tb)


func _part(_type, size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	_parts.append(mi)


# ------------------------------------------------------------------ API

func is_alive() -> bool:
	return not destroyed and not falling


func is_player_controlled() -> bool:
	return pilot != null


func can_see_point(p: Vector3) -> bool:
	return Game.line_of_sight(global_position + Vector3.DOWN * 1.5, p)


func camera_distance() -> float:
	return 15.0


func can_hijack(by: Node) -> bool:
	return is_alive() and pilot == null and (by as Node3D).global_position.distance_to(global_position) < 9.0


func hijack(by: Node) -> void:
	pilot = by
	remove_from_group("military")
	add_to_group("player_vehicle")
	_yaw = rotation.y
	Game.fx.splat(global_position, Vector3.UP, Color(0.5, 0.02, 0.02), 16)


func on_pilot_exit() -> void:
	pilot = null
	remove_from_group("player_vehicle")
	_start_fall(null)


func take_hit(info: Dictionary) -> void:
	if destroyed:
		return
	var dmg: float = info["damage"]
	match info["kind"]:
		"bullet": dmg *= 0.25
		"explosion": dmg *= 1.4
	var src: Node = info["source"]
	if src == Game.player and pilot == null:
		Game.raise_alert(Game.player.global_position, "You attacked a gunship")
		Game.add_heat(0.1)
	hp -= dmg
	parked = false
	if src == Game.player and dmg > 1.0:
		Game.register_hit()
	if hp <= 0.0 and not falling:
		_start_fall(src)


func _start_fall(src: Node) -> void:
	if falling:
		return
	falling = true
	_fall_timer = 6.0
	remove_from_group("military")
	remove_from_group("hijackable")
	remove_from_group("military_vehicles")
	_smoke = Game.fx.make_fire()
	add_child(_smoke)
	_smoke.emitting = true
	if pilot:
		var p := pilot
		pilot = null
		remove_from_group("player_vehicle")
		p.exit_vehicle(Vector3(0, 10, 0))
	if src == Game.player or (src and is_instance_valid(src) and src.has_method("is_player_controlled") and src.is_player_controlled()):
		Game.add_xp(100, "Gunship down")
		Game.add_heat(0.5)


func _crash() -> void:
	destroyed = true
	Game.explode(global_position, 10.0, 90.0, self, 22.0)
	Game.fx.debris(global_position, 30, Color(0.2, 0.22, 0.18))
	get_tree().call_group("event_listeners", "on_unit_removed", self, "destroyed")
	queue_free()


# ------------------------------------------------------------------ loop

func _physics_process(delta: float) -> void:
	if destroyed:
		return
	_rotor.rotation.y += delta * (28.0 if not falling else 14.0)
	_tail_rotor.rotation.x += delta * 40.0
	if falling:
		_fall_timer -= delta
		velocity.y -= 18.0 * delta
		velocity.x *= 0.99
		velocity.z *= 0.99
		rotation.y += delta * 4.0
		move_and_slide()
		if get_slide_collision_count() > 0 or _fall_timer <= 0.0 or global_position.y < 1.5:
			_crash()
		return
	if parked and pilot == null:
		_rotor.rotation.y -= delta * 26.0
		velocity = Vector3.ZERO
		return
	if pilot:
		parked = false
		_fly_piloted(delta)
	else:
		_think_timer -= delta
		if _think_timer <= 0.0:
			_think_timer = 0.4
			_think()
		_fly_ai(delta)
	move_and_slide()


func _think() -> void:
	var p := Game.player
	_target = null
	if p and not p.is_dead():
		var pp: Vector3 = p.global_position
		if p.vehicle and is_instance_valid(p.vehicle):
			pp = (p.vehicle as Node3D).global_position
		var d := global_position.distance_to(pp)
		if d < 140.0 and can_see_point(pp + Vector3.UP * 0.5):
			Game.report_sighting(pp, p.is_conspicuous(), global_position, 0.4)
			if Game.is_hunted():
				_target = p.vehicle if p.vehicle else p
	if _target == null:
		var h := Game.nearest_in_group("hunters", global_position, 120.0)
		if h and can_see_point(h.global_position):
			_target = h


func _ground_height_below(p: Vector3) -> float:
	var hit := Game.raycast(p + Vector3.UP * 5.0, p + Vector3.DOWN * 220.0, Game.LAYER_WORLD)
	return float(hit["position"].y) if not hit.is_empty() else 0.0


func _fly_ai(delta: float) -> void:
	var center := patrol_point
	if _target and is_instance_valid(_target):
		center = _target.global_position
	elif Game.alert_level != Game.Alert.HIDDEN:
		center = Game.last_known_pos
	_orbit_angle += delta * 0.35 * _orbit_dir
	var radius := 38.0
	var goal := center + Vector3(cos(_orbit_angle), 0, sin(_orbit_angle)) * radius
	var floor_h := maxf(_ground_height_below(goal), _ground_height_below(global_position))
	goal.y = maxf(floor_h + 22.0, center.y + 18.0)
	# avoid flying into buildings ahead
	var fwd := Vector3(velocity.x, 0, velocity.z)
	if fwd.length() > 1.0:
		var hit := Game.raycast(global_position, global_position + fwd.normalized() * 25.0, Game.LAYER_WORLD)
		if not hit.is_empty():
			goal.y = maxf(goal.y, global_position.y + 15.0)
	var to := goal - global_position
	var want := to.limit_length(24.0)
	velocity = velocity.move_toward(want, 14.0 * delta)
	var look_at_pos := center if _target else global_position + Vector3(velocity.x, 0, velocity.z)
	var flat := look_at_pos - global_position
	flat.y = 0
	if flat.length() > 1.0:
		var target_yaw := atan2(-flat.x, -flat.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 2.0 * delta)
	rotation.x = lerpf(rotation.x, -clampf(velocity.dot(-global_transform.basis.z) * 0.012, -0.3, 0.3), 3.0 * delta)
	if _target and is_instance_valid(_target):
		_shoot_ai(delta)


func _shoot_ai(delta: float) -> void:
	var tpos := _target.global_position
	_gun_timer -= delta
	_missile_timer -= delta
	if _gun_timer <= 0.0:
		if _burst <= 0:
			_burst = 8
		_fire_gun(tpos, 0.035, 4.0)
		_burst -= 1
		_gun_timer = 0.08 if _burst > 0 else randf_range(1.8, 2.8)
	if _missile_timer <= 0.0:
		_fire_missile(tpos, _target)
		_missile_timer = randf_range(5.0, 7.0)


func _fire_gun(at: Vector3, spread: float, dmg: float) -> void:
	var muzzle := global_position + Vector3.DOWN * 1.4 + (-global_transform.basis.z) * 2.5
	var dir := (at + Vector3.UP * randf_range(-0.3, 0.6) - muzzle).normalized()
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	var hit := Game.raycast(muzzle, muzzle + dir * 200.0, Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.MASK_HITTABLE, [get_rid()])
	var end := muzzle + dir * 200.0
	if not hit.is_empty():
		end = hit["position"]
		var c := hit["collider"] as Node
		if c and c.has_method("take_hit") and (pilot != null or not c.is_in_group("military")):
			c.take_hit(Game.hit_info(dmg, dir * 2.0, pilot if pilot else self, "bullet"))
		else:
			Game.fx.debris(end, 1)
	Game.fx.tracer(muzzle, end, Color(1.0, 0.85, 0.4), 0.07)
	Game.fx.sound("gunshot", muzzle, -2.0, 0.1)


func _fire_missile(at: Vector3, homing: Node3D) -> void:
	var muzzle := global_position + Vector3.DOWN * 0.6 + global_transform.basis.x * (1.8 if randf() < 0.5 else -1.8)
	var dir := (at - muzzle).normalized()
	var p := Node3D.new()
	p.set_script(PROJECTILE)
	get_parent().add_child(p)
	p.launch(muzzle, dir * 42.0, pilot if pilot else self, "missile", homing)
	Game.fx.sound("rocket", muzzle, 0.0)


func _fly_piloted(delta: float) -> void:
	var p := pilot
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_yaw: float = p.yaw
	var move := Vector3(raw.x, 0, raw.y).rotated(Vector3.UP, cam_yaw) * 30.0
	var vert := 0.0
	if Input.is_action_pressed("jump"):
		vert += 14.0
	if Input.is_action_pressed("sprint"):
		vert -= 14.0
	var want := Vector3(move.x, vert, move.z)
	velocity = velocity.move_toward(want, 25.0 * delta)
	rotation.y = lerp_angle(rotation.y, cam_yaw, 3.0 * delta)
	rotation.x = lerpf(rotation.x, -raw.y * 0.25, 4.0 * delta)
	rotation.z = lerpf(rotation.z, -raw.x * 0.25, 4.0 * delta)
	_missile_timer -= delta
	_gun_timer -= delta
	var aim: Dictionary = p.aim_point(300.0)
	if Input.is_action_just_pressed("attack") and _missile_timer <= 0.0:
		var target := aim["collider"] as Node3D
		_fire_missile(aim["position"], target if target and target.has_method("take_hit") else null)
		_missile_timer = 0.6
		p.conspicuous_timer = 4.0
	if Input.is_action_pressed("special") and _gun_timer <= 0.0:
		_fire_gun(aim["position"], 0.01, 9.0)
		_gun_timer = 0.07
		p.conspicuous_timer = 4.0
