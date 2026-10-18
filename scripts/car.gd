extends RigidBody3D
## A car. It can be knocked around, picked up and thrown, it hurts whatever
## it slams into, and it explodes when it takes enough damage.

const COLORS := [
	Color(0.62, 0.08, 0.07), Color(0.1, 0.18, 0.4), Color(0.85, 0.85, 0.82), Color(0.08, 0.08, 0.09),
	Color(0.85, 0.65, 0.1), Color(0.25, 0.3, 0.27), Color(0.45, 0.47, 0.5), Color(0.15, 0.35, 0.45),
]

@export var color_index := 0
var hp := 110.0
var wrecked := false
var held := false
var thrown_by: Node = null
var _thrown_timer := 0.0
var _body_mesh: MeshInstance3D
var _cabin_mesh: MeshInstance3D
var _fire: CPUParticles3D
var _fire_timer := 0.0
var _impact_cooldown := 0.0

static var _shared := {}


func _ready() -> void:
	mass = 1100.0
	collision_layer = Game.LAYER_PROPS
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_PROPS | Game.LAYER_NPC | Game.LAYER_VEHICLE
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	add_to_group("cars")
	add_to_group("grabbable")
	linear_damp = 0.05
	angular_damp = 0.3
	_build()


static func _get_shared() -> Dictionary:
	if not _shared.is_empty():
		return _shared
	var body := BoxMesh.new()
	body.size = Vector3(1.9, 0.72, 4.3)
	var cabin := BoxMesh.new()
	cabin.size = Vector3(1.7, 0.6, 2.2)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.36
	wheel.bottom_radius = 0.36
	wheel.height = 0.28
	wheel.radial_segments = 12
	var light := BoxMesh.new()
	light.size = Vector3(0.4, 0.15, 0.05)
	var mats: Array[StandardMaterial3D] = []
	for c in COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = 0.55
		m.roughness = 0.32
		mats.append(m)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.07, 0.09, 0.12)
	glass.metallic = 0.8
	glass.roughness = 0.08
	var tire := StandardMaterial3D.new()
	tire.albedo_color = Color(0.05, 0.05, 0.05)
	tire.roughness = 0.9
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = Color(0.07, 0.06, 0.055)
	burnt.roughness = 1.0
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(1, 1, 0.9)
	head.emission_enabled = true
	head.emission = Color(1, 0.95, 0.8)
	head.emission_energy_multiplier = 1.5
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.8, 0.05, 0.05)
	tail.emission_enabled = true
	tail.emission = Color(1, 0.05, 0.03)
	tail.emission_energy_multiplier = 1.2
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.6, 4.3)
	_shared = {"body": body, "cabin": cabin, "wheel": wheel, "light": light, "mats": mats,
		"glass": glass, "tire": tire, "burnt": burnt, "head": head, "tail": tail, "shape": shape}
	return _shared


func _build() -> void:
	var s := _get_shared()
	var col := CollisionShape3D.new()
	col.shape = s["shape"]
	col.position = Vector3(0, 0.82, 0)
	add_child(col)
	_body_mesh = MeshInstance3D.new()
	_body_mesh.mesh = s["body"]
	_body_mesh.material_override = s["mats"][color_index % COLORS.size()]
	_body_mesh.position = Vector3(0, 0.62, 0)
	add_child(_body_mesh)
	_cabin_mesh = MeshInstance3D.new()
	_cabin_mesh.mesh = s["cabin"]
	_cabin_mesh.material_override = s["glass"]
	_cabin_mesh.position = Vector3(0, 1.28, 0.15)
	add_child(_cabin_mesh)
	for x in [-0.92, 0.92]:
		for z in [-1.35, 1.35]:
			var w := MeshInstance3D.new()
			w.mesh = s["wheel"]
			w.material_override = s["tire"]
			w.rotation.z = PI * 0.5
			w.position = Vector3(x, 0.36, z)
			add_child(w)
	for x in [-0.6, 0.6]:
		var h := MeshInstance3D.new()
		h.mesh = s["light"]
		h.material_override = s["head"]
		h.position = Vector3(x, 0.7, -2.16)
		add_child(h)
		var t := MeshInstance3D.new()
		t.mesh = s["light"]
		t.material_override = s["tail"]
		t.position = Vector3(x, 0.75, 2.16)
		add_child(t)


func _physics_process(delta: float) -> void:
	if _thrown_timer > 0.0:
		_thrown_timer -= delta
		if _thrown_timer <= 0.0:
			thrown_by = null
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	if _fire_timer > 0.0:
		_fire_timer -= delta
		if _fire_timer <= 0.0 and _fire:
			_fire.emitting = false
	if global_position.y < -50.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	var speed := linear_velocity.length()
	if speed < 9.0 or _impact_cooldown > 0.0:
		return
	_impact_cooldown = 0.15
	if body.has_method("take_hit") and body != thrown_by:
		var src: Node = thrown_by if thrown_by else self
		body.take_hit(Game.hit_info(speed * 3.2, linear_velocity * 0.7 + Vector3.UP * 4.0, src, "impact"))
	if speed > 18.0:
		take_hit(Game.hit_info((speed - 18.0) * 3.0, Vector3.ZERO, thrown_by, "impact"))
		if Game.fx:
			Game.fx.sound("crash", global_position, -2.0)


func take_hit(info: Dictionary) -> void:
	if held:
		return
	var dmg: float = info["damage"]
	if info["kind"] == "blade":
		dmg *= 2.0
	if info["kind"] == "explosion":
		dmg *= 1.5
	var force: Vector3 = info["force"]
	if force.length() > 0.1:
		sleeping = false
		apply_central_impulse(force * mass * 0.55)
		apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * mass * force.length() * 0.35)
	if info["source"] == Game.player:
		thrown_by = Game.player
		_thrown_timer = 2.0
	hp -= dmg
	if hp <= 0.0 and not wrecked:
		explode()


func explode() -> void:
	wrecked = true
	hp = 0.0
	_body_mesh.material_override = _get_shared()["burnt"]
	_cabin_mesh.material_override = _get_shared()["burnt"]
	sleeping = false
	apply_central_impulse(Vector3(randf_range(-2, 2), 9.0, randf_range(-2, 2)) * mass)
	apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * mass * 6.0)
	var src: Node = thrown_by if thrown_by else self
	Game.explode(global_position + Vector3.UP, 7.0, 70.0, src, 16.0)
	_start_fire()


func _start_fire() -> void:
	if _fire == null:
		_fire = Game.fx.make_fire() if Game.fx else null
		if _fire:
			add_child(_fire)
			_fire.position = Vector3(0, 1.0, 0)
	if _fire:
		_fire.emitting = true
	_fire_timer = 14.0


# ------------------------------------------------------------------ grabbing

func can_be_grabbed() -> bool:
	return not held


func on_grabbed(by: Node) -> void:
	held = true
	thrown_by = by
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0


func on_thrown(velocity: Vector3, by: Node) -> void:
	held = false
	freeze = false
	collision_layer = Game.LAYER_PROPS
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_PROPS | Game.LAYER_NPC | Game.LAYER_VEHICLE
	linear_velocity = velocity
	angular_velocity = Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3))
	thrown_by = by
	_thrown_timer = 4.0
	# don't immediately collide with the thrower
	add_collision_exception_with(by)
	get_tree().create_timer(0.4).timeout.connect(_end_exception.bind(by))


func _end_exception(by: Node) -> void:
	if is_instance_valid(by):
		remove_collision_exception_with(by)


func hold_offset() -> Vector3:
	return Vector3(0, 2.6, 0)
