extends Node3D
## Rockets, tank shells, helicopter missiles and grenades. Flies in a line (missiles and locked-on
## rockets steer toward their target) and explodes on contact. Grenades arc, bounce once and go off
## on a short fuse.

const STATS := {
	"rocket": {"radius": 5.0, "damage": 32.0, "speed_trail": 1.0, "color": Color(1, 0.6, 0.2)},
	"shell": {"radius": 6.5, "damage": 55.0, "speed_trail": 0.6, "color": Color(1, 0.8, 0.4)},
	"missile": {"radius": 5.0, "damage": 30.0, "speed_trail": 1.0, "color": Color(1, 0.5, 0.2)},
	"bomb": {"radius": 9.0, "damage": 80.0, "speed_trail": 0.5, "color": Color(1, 0.5, 0.2)},
	"grenade": {"radius": 5.5, "damage": 38.0, "speed_trail": 0.3, "color": Color(0.6, 1.0, 0.3)},
}
const GRENADE_GRAVITY := 22.0

var velocity := Vector3.ZERO
var source: Node = null
var kind := "rocket"
var target: Node3D = null
var life := 7.0
var gravity := 0.0
var _exclude: Array[RID] = []
var _bounces := 0


## Velocity that lobs a grenade from `from` to land on `to` after `time` seconds.
static func lob_velocity(from: Vector3, to: Vector3, time: float) -> Vector3:
	var v := (to - from) / time
	v.y += 0.5 * GRENADE_GRAVITY * time
	return v


func launch(pos: Vector3, vel: Vector3, src: Node, k: String, homing_target: Node3D = null) -> void:
	global_position = pos
	velocity = vel
	reset_physics_interpolation()
	source = src
	kind = k
	target = homing_target
	if kind == "bomb":
		gravity = 30.0
	elif kind == "grenade":
		gravity = GRENADE_GRAVITY
		life = 2.2
	if src is CollisionObject3D:
		_exclude.append((src as CollisionObject3D).get_rid())
	_build()
	reset_physics_interpolation()


func _build() -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.12 if kind != "bomb" else 0.35
	cap.height = 0.8 if kind != "bomb" else 1.6
	if kind == "grenade":
		cap.radius = 0.11
		cap.height = 0.3
	body.mesh = cap
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.27, 0.22)
	body.material_override = m
	body.rotation.x = PI * 0.5
	add_child(body)
	var glow := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.2
	s.height = 0.4
	glow.mesh = s
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = STATS[kind]["color"]
	glow.material_override = gm
	glow.position = Vector3(0, 0, 0.45)
	add_child(glow)
	var trail := CPUParticles3D.new()
	trail.amount = 30
	trail.lifetime = 0.8
	trail.local_coords = false
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	var tm := StandardMaterial3D.new()
	tm.vertex_color_use_as_albedo = true
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = tm
	trail.mesh = sm
	trail.gravity = Vector3(0, 0.5, 0)
	trail.initial_velocity_max = 0.5
	trail.scale_amount_min = 0.6
	trail.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.7, 0.3, 0.9))
	g.set_color(1, Color(0.4, 0.4, 0.4, 0.0))
	trail.color_ramp = g
	trail.position = Vector3(0, 0, 0.5)
	add_child(trail)
	_face()


func _face() -> void:
	if velocity.length() > 0.1:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT
		look_at(global_position + velocity, up)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_detonate(global_position)
		return
	if target and is_instance_valid(target) and kind in ["missile", "rocket"]:
		# a rocket fired with a lock turns hard enough to chase a gunship
		var want := (target.global_position - global_position).normalized() * velocity.length()
		velocity = velocity.move_toward(want, (18.0 if kind == "missile" else 45.0) * delta)
	velocity.y -= gravity * delta
	var next := global_position + velocity * delta
	var mask := Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.MASK_HITTABLE
	var hit := Game.raycast(global_position, next, mask, _exclude)
	if not hit.is_empty():
		var c := hit["collider"] as Node
		if kind == "grenade" and _bounces < 1 and not (c and c.has_method("take_hit")):
			# hit the ground or a wall: bounce once and keep the fuse burning
			_bounces += 1
			var n: Vector3 = hit["normal"]
			velocity = velocity.bounce(n) * 0.4
			global_position = (hit["position"] as Vector3) + n * 0.15
			Game.fx.sound("land", global_position, -14.0, 0.3)
			return
		_detonate(hit["position"])
		return
	global_position = next
	_face()


func _detonate(pos: Vector3) -> void:
	var st: Dictionary = STATS[kind]
	Game.explode(pos, st["radius"], st["damage"], source if is_instance_valid(source) else null, 18.0)
	queue_free()
