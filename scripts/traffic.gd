extends CharacterBody3D
## A civilian car driving the streets. It follows the lanes, brakes for things
## in front of it, speeds away from danger, and turns into a regular physics
## car (that can be thrown and blown up) the moment something hits it.

const CAR_SCRIPT := preload("res://scripts/car.gd")

var color_index := 0
var speed := 11.0
var heading := 0.0
var _cell := Vector2i.ZERO
var _prev_cell := Vector2i(-99, -99)
var _next_cell := Vector2i.ZERO
var _brake_timer := 0.0
var _panic_timer := 0.0
var _converted := false


func setup(start_cell: Vector2i, next_cell: Vector2i) -> void:
	color_index = randi() % 8
	collision_layer = Game.LAYER_PROPS
	collision_mask = Game.LAYER_WORLD | Game.LAYER_VEHICLE
	var shared: Dictionary = CAR_SCRIPT._get_shared()
	var col := CollisionShape3D.new()
	col.shape = shared["shape"]
	col.position = Vector3(0, 0.82, 0)
	add_child(col)
	var body := MeshInstance3D.new()
	body.mesh = shared["body"]
	body.material_override = shared["mats"][color_index]
	body.position = Vector3(0, 0.62, 0)
	add_child(body)
	var cabin := MeshInstance3D.new()
	cabin.mesh = shared["cabin"]
	cabin.material_override = shared["glass"]
	cabin.position = Vector3(0, 1.28, 0.15)
	add_child(cabin)
	for x in [-0.92, 0.92]:
		for z in [-1.35, 1.35]:
			var w := MeshInstance3D.new()
			w.mesh = shared["wheel"]
			w.material_override = shared["tire"]
			w.rotation.z = PI * 0.5
			w.position = Vector3(x, 0.36, z)
			add_child(w)
	for x in [-0.6, 0.6]:
		var h := MeshInstance3D.new()
		h.mesh = shared["light"]
		h.material_override = shared["head"]
		h.position = Vector3(x, 0.7, -2.16)
		add_child(h)
		var t := MeshInstance3D.new()
		t.mesh = shared["light"]
		t.material_override = shared["tail"]
		t.position = Vector3(x, 0.75, 2.16)
		add_child(t)
	_cell = start_cell
	_next_cell = next_cell
	_prev_cell = start_cell
	var to: Vector3 = Game.city.intersection_pos(next_cell) - Game.city.intersection_pos(start_cell)
	heading = atan2(-to.x, -to.z)
	rotation.y = heading
	speed = randf_range(9.0, 13.0)
	add_to_group("traffic")


func is_alive() -> bool:
	return not _converted


func take_hit(info: Dictionary) -> void:
	var c := convert_to_physics()
	if c:
		c.take_hit(info)


func panic(_from: Vector3) -> void:
	_panic_timer = 8.0


## Swap this driving car for a normal physics car at the same spot.
func convert_to_physics() -> RigidBody3D:
	if _converted:
		return null
	_converted = true
	var car: RigidBody3D = Game.city.spawn_car_at(global_position, heading, color_index)
	car.linear_velocity = Vector3.FORWARD.rotated(Vector3.UP, heading) * velocity.length()
	queue_free()
	return car


func _physics_process(delta: float) -> void:
	if _converted:
		return
	_panic_timer -= delta
	var goal_pos: Vector3 = Game.city.intersection_pos(_next_cell)
	var seg: Vector3 = goal_pos - Game.city.intersection_pos(_prev_cell if _prev_cell != _next_cell else _cell)
	seg.y = 0.0
	var lane := Vector3.ZERO
	if seg.length() > 1.0:
		lane = seg.normalized().cross(Vector3.UP) * 3.0
	var to := goal_pos + lane - global_position
	to.y = 0.0
	if to.length() < 4.0:
		_choose_next()
	var want := atan2(-to.x, -to.z)
	var diff := wrapf(want - heading, -PI, PI)
	heading += clampf(diff, -1.8 * delta, 1.8 * delta)
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, heading)
	# brake for anything in front
	var ahead := Game.raycast(global_position + Vector3.UP * 0.8 + fwd * 2.4, global_position + Vector3.UP * 0.8 + fwd * 9.0,
		Game.LAYER_PLAYER | Game.LAYER_NPC | Game.LAYER_PROPS | Game.LAYER_VEHICLE, [get_rid()])
	var target_speed := speed * (1.7 if _panic_timer > 0.0 else 1.0) * clampf(1.0 - absf(diff) / PI * 1.6, 0.3, 1.0)
	if not ahead.is_empty() and _panic_timer <= 0.0:
		target_speed = 0.0
	var cur := Vector3(velocity.x, 0, velocity.z).length()
	cur = move_toward(cur, target_speed, (14.0 if target_speed < cur else 6.0) * delta)
	velocity.x = fwd.x * cur
	velocity.z = fwd.z * cur
	velocity.y = -1.0 if is_on_floor() else velocity.y - 30.0 * delta
	move_and_slide()
	rotation.y = heading
	# panicked drivers plough through people
	if _panic_timer > 0.0 and cur > 6.0:
		for i in get_slide_collision_count():
			var c := get_slide_collision(i).get_collider() as Node
			if c and c.has_method("take_hit") and c != self:
				c.take_hit(Game.hit_info(cur * 3.0, fwd * cur + Vector3.UP * 4.0, self, "impact"))
	if Game.player and global_position.distance_to(Game.player.global_position) > 230.0:
		queue_free()


func _choose_next() -> void:
	_prev_cell = _cell
	_cell = _next_cell
	var options: Array[Vector2i] = []
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = _cell + o
		if c.x < 0 or c.y < 0 or c.x > Game.city.blocks or c.y > Game.city.blocks or c == _prev_cell:
			continue
		options.append(c)
	if options.is_empty():
		_next_cell = _prev_cell
	else:
		# prefer going straight
		var straight := _cell + (_cell - _prev_cell)
		if straight in options and randf() < 0.6:
			_next_cell = straight
		else:
			_next_cell = options[randi() % options.size()]
