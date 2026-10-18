extends Node3D
## A simple, animated person made from capsules and spheres.
## Used for civilians, soldiers, infected, hunters and (extended) the player.
## The node's origin is the body center; feet are 0.9 m below at scale 1.

var torso: MeshInstance3D
var head: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var head_gear: MeshInstance3D
var held_item: MeshInstance3D
var coat: Node3D
var all_meshes: Array[MeshInstance3D] = []

var cycle := 0.0
var swing_timer := 0.0
var swing_right := true
var swing_style := 0
var _thermal_on := false

static var _mesh_cache := {}
static var _mat_cache := {}
static var _thermal_mat: StandardMaterial3D


static func mat(color: Color, emission := 0.0, metallic := 0.0, roughness := 0.8) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), emission, metallic, roughness]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mat_cache[key] = m
	return m


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var key := "cap%.3f_%.3f" % [radius, height]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 10
	m.rings = 4
	_mesh_cache[key] = m
	return m


static func sphere(radius: float) -> SphereMesh:
	var key := "sph%.3f" % radius
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 12
	m.rings = 6
	_mesh_cache[key] = m
	return m


static func box(size: Vector3) -> BoxMesh:
	var key := "box%s" % [size]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := BoxMesh.new()
	m.size = size
	_mesh_cache[key] = m
	return m


func _part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	all_meshes.append(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## outfit keys: shirt, pants, skin, gear ("none","helmet","cap","hood","beret"),
## item ("none","rifle","launcher"), glow (Color, optional), bulk (float)
func setup(outfit: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	all_meshes.clear()
	var shirt: Color = outfit.get("shirt", Color(0.4, 0.4, 0.45))
	var pants: Color = outfit.get("pants", Color(0.2, 0.2, 0.25))
	var skin: Color = outfit.get("skin", Color(0.75, 0.58, 0.45))
	var bulk: float = outfit.get("bulk", 1.0)
	var shirt_m := mat(shirt)
	var pants_m := mat(pants)
	var skin_m := mat(skin)
	torso = _part(self, capsule(0.28 * bulk, 1.0), shirt_m, Vector3(0, 0.15, 0))
	head = _part(self, sphere(0.19), skin_m, Vector3(0, 0.78, 0))
	arm_l = _pivot(self, Vector3(-0.36 * bulk, 0.52, 0))
	arm_r = _pivot(self, Vector3(0.36 * bulk, 0.52, 0))
	_part(arm_l, capsule(0.085 * bulk, 0.72), shirt_m, Vector3(0, -0.32, 0))
	_part(arm_r, capsule(0.085 * bulk, 0.72), shirt_m, Vector3(0, -0.32, 0))
	_part(arm_l, sphere(0.075 * bulk), skin_m, Vector3(0, -0.66, 0))
	_part(arm_r, sphere(0.075 * bulk), skin_m, Vector3(0, -0.66, 0))
	hand_l = _pivot(arm_l, Vector3(0, -0.68, 0))
	hand_r = _pivot(arm_r, Vector3(0, -0.68, 0))
	leg_l = _pivot(self, Vector3(-0.13, -0.24, 0))
	leg_r = _pivot(self, Vector3(0.13, -0.24, 0))
	_part(leg_l, capsule(0.105, 0.72), pants_m, Vector3(0, -0.31, 0))
	_part(leg_r, capsule(0.105, 0.72), pants_m, Vector3(0, -0.31, 0))
	# body shape details: broader flatter chest, hips, neck, shoulders, shoes, eyes
	torso.scale = Vector3(1.12, 1.0, 0.8)
	var hips := _part(self, sphere(0.2 * bulk), pants_m, Vector3(0, -0.22, 0))
	hips.scale = Vector3(1.25, 0.7, 0.85)
	_part(self, capsule(0.07, 0.2), skin_m, Vector3(0, 0.62, 0))
	_part(arm_l, sphere(0.11 * bulk), shirt_m, Vector3(0, 0.0, 0))
	_part(arm_r, sphere(0.11 * bulk), shirt_m, Vector3(0, 0.0, 0))
	var shoe_m := mat(outfit.get("shoes", Color(0.08, 0.07, 0.07)), 0.0, 0.0, 0.6)
	_part(leg_l, box(Vector3(0.15, 0.1, 0.3)), shoe_m, Vector3(0, -0.66, -0.05))
	_part(leg_r, box(Vector3(0.15, 0.1, 0.3)), shoe_m, Vector3(0, -0.66, -0.05))
	if outfit.get("gear", "none") != "hood":
		var eye_m := mat(Color(0.05, 0.04, 0.04), 0.0, 0.0, 0.3)
		_part(head, sphere(0.024), eye_m, Vector3(-0.065, 0.03, -0.168))
		_part(head, sphere(0.024), eye_m, Vector3(0.065, 0.03, -0.168))
	var gear: String = outfit.get("gear", "none")
	match gear:
		"helmet":
			head_gear = _part(head, sphere(0.215), mat(outfit.get("gear_color", Color(0.25, 0.3, 0.2))), Vector3(0, 0.05, 0))
			head_gear.scale = Vector3(1, 0.75, 1.05)
			_part(head, box(Vector3(0.28, 0.07, 0.04)), mat(Color(0.05, 0.05, 0.05), 0.0, 0.8, 0.2), Vector3(0, 0.0, -0.18))
		"cap":
			head_gear = _part(head, sphere(0.2), mat(outfit.get("gear_color", Color(0.15, 0.2, 0.4))), Vector3(0, 0.07, 0))
			head_gear.scale = Vector3(1, 0.6, 1)
			_part(head, box(Vector3(0.22, 0.03, 0.14)), mat(outfit.get("gear_color", Color(0.15, 0.2, 0.4))), Vector3(0, 0.08, -0.2))
		"hood":
			head_gear = _part(head, sphere(0.235), mat(outfit.get("gear_color", shirt)), Vector3(0, 0.03, 0.03))
			var glow: Color = outfit.get("glow", Color(1, 0.15, 0.1))
			_part(head, box(Vector3(0.24, 0.045, 0.05)), mat(glow, 3.0), Vector3(0, 0.0, -0.2))
		"hair":
			head_gear = _part(head, sphere(0.2), mat(outfit.get("gear_color", Color(0.15, 0.1, 0.06))), Vector3(0, 0.05, 0.03))
			head_gear.scale = Vector3(1.02, 0.85, 1.02)
	var item: String = outfit.get("item", "none")
	match item:
		"rifle":
			held_item = _part(hand_r, box(Vector3(0.07, 0.12, 0.85)), mat(Color(0.08, 0.08, 0.08), 0.0, 0.6, 0.4), Vector3(0, -0.05, -0.3))
		"launcher":
			held_item = _part(hand_r, capsule(0.09, 1.1), mat(Color(0.2, 0.25, 0.15)), Vector3(0, 0.0, -0.1))
			held_item.rotation.x = PI * 0.5
	coat = null
	if outfit.get("coat", false):
		# long coat tails that flap behind when running
		coat = _pivot(torso, Vector3(0, -0.3, 0.12))
		var coat_m := mat(outfit.get("coat_color", shirt))
		_part(coat, box(Vector3(0.24, 0.75, 0.05)), coat_m, Vector3(-0.13, -0.36, 0.08))
		_part(coat, box(Vector3(0.24, 0.75, 0.05)), coat_m, Vector3(0.13, -0.36, 0.08))
	if outfit.has("glow") and gear != "hood":
		var g: Color = outfit["glow"]
		_part(torso, box(Vector3(0.05, 0.5, 0.02)), mat(g, 2.5), Vector3(0.12, 0.05, -0.27 * bulk))
		_part(torso, box(Vector3(0.05, 0.35, 0.02)), mat(g, 2.5), Vector3(-0.1, -0.1, -0.27 * bulk))


func swing(right := true, style := 0, duration := 0.22) -> void:
	swing_timer = duration
	swing_right = right
	swing_style = style
	set_meta("swing_duration", duration)


## mode: idle, walk, run, aim, flail, dead, grabbed, air, crouch
func animate(delta: float, speed: float, mode: String) -> void:
	if arm_l == null:
		return
	var k := 1.0 - exp(-14.0 * delta)
	var la := Vector3.ZERO
	var ra := Vector3.ZERO
	var ll := Vector3.ZERO
	var rl := Vector3.ZERO
	match mode:
		"walk", "run":
			cycle += delta * clampf(speed, 2.0, 30.0) * (0.9 if mode == "run" else 1.4)
			var amp := clampf(speed / 8.0, 0.35, 1.0) * (1.1 if mode == "run" else 0.6)
			var s := sin(cycle)
			ll = Vector3(s * amp, 0, 0)
			rl = Vector3(-s * amp, 0, 0)
			la = Vector3(-s * amp * 0.9, 0, -0.08)
			ra = Vector3(s * amp * 0.9, 0, 0.08)
			if mode == "run":
				la.x -= 0.3
				ra.x -= 0.3
		"aim":
			ra = Vector3(1.45, 0, 0.0)
			la = Vector3(1.3, 0, 0.45)
			cycle += delta * speed * 1.4
			var s2 := sin(cycle) * clampf(speed / 6.0, 0.0, 0.7)
			ll = Vector3(s2, 0, 0)
			rl = Vector3(-s2, 0, 0)
		"flail":
			cycle += delta * 18.0
			la = Vector3(sin(cycle) * 1.2, 0, -1.2)
			ra = Vector3(cos(cycle) * 1.2, 0, 1.2)
			ll = Vector3(sin(cycle * 1.3) * 0.8, 0, -0.3)
			rl = Vector3(cos(cycle * 1.3) * 0.8, 0, 0.3)
		"grabbed":
			cycle += delta * 22.0
			la = Vector3(2.6 + sin(cycle) * 0.3, 0, -0.3)
			ra = Vector3(2.6 + cos(cycle) * 0.3, 0, 0.3)
			ll = Vector3(sin(cycle * 1.1) * 0.6, 0, 0)
			rl = Vector3(-sin(cycle * 1.1) * 0.6, 0, 0)
		"dead":
			la = Vector3(0.2, 0, -1.4)
			ra = Vector3(-0.3, 0, 1.3)
			ll = Vector3(0.1, 0, -0.2)
			rl = Vector3(-0.1, 0, 0.15)
		"air":
			la = Vector3(-0.6, 0, -0.7)
			ra = Vector3(-0.6, 0, 0.7)
			ll = Vector3(0.8, 0, 0)
			rl = Vector3(-0.2, 0, 0)
		"glide":
			la = Vector3(0, 0, -1.45)
			ra = Vector3(0, 0, 1.45)
			ll = Vector3(-0.1, 0, -0.12)
			rl = Vector3(0.1, 0, 0.12)
		"crouch":
			la = Vector3(-0.4, 0, -0.3)
			ra = Vector3(-0.4, 0, 0.3)
			ll = Vector3(0.9, 0, 0)
			rl = Vector3(0.9, 0, 0)
		"cower":
			la = Vector3(2.4, 0, 0.6)
			ra = Vector3(2.4, 0, -0.6)
			ll = Vector3(0.6, 0, 0)
			rl = Vector3(0.6, 0, 0)
		_:
			cycle += delta
			la = Vector3(sin(cycle * 1.5) * 0.04, 0, -0.08)
			ra = Vector3(-sin(cycle * 1.5) * 0.04, 0, 0.08)
	if swing_timer > 0.0:
		swing_timer -= delta
		var dur: float = get_meta("swing_duration", 0.22)
		var t := 1.0 - clampf(swing_timer / dur, 0.0, 1.0)
		var arc := sin(t * PI)
		var pose: Vector3
		match swing_style:
			0: pose = Vector3(1.6 * arc + 0.2, 0, 0)                 # straight punch
			1: pose = Vector3(1.2, lerpf(-1.4, 1.4, t), 0.6 * arc)  # horizontal slash
			2: pose = Vector3(lerpf(3.0, -0.2, t), 0, 0)             # overhead smash
			3: pose = Vector3(lerpf(-0.5, 2.8, t), 0, 0)             # uppercut
			_: pose = Vector3(1.5 * arc, 0, 0)
		if swing_right:
			ra = pose
			k = 1.0 - exp(-40.0 * delta)
		else:
			la = Vector3(pose.x, -pose.y, -pose.z)
			k = 1.0 - exp(-40.0 * delta)
	if coat:
		var flap := clampf(speed / 18.0, 0.0, 1.0)
		# negative x swings the tails backwards
		var target_x := -(flap * 0.9 + sin(cycle * 2.0) * 0.08 * flap)
		if mode == "glide" or mode == "air":
			target_x = -1.1
		coat.rotation.x = lerpf(coat.rotation.x, target_x, 1.0 - exp(-8.0 * delta))
	arm_l.rotation = arm_l.rotation.lerp(la, k)
	arm_r.rotation = arm_r.rotation.lerp(ra, k)
	leg_l.rotation = leg_l.rotation.lerp(ll, k)
	leg_r.rotation = leg_r.rotation.lerp(rl, k)


func set_thermal(on: bool) -> void:
	if on == _thermal_on:
		return
	_thermal_on = on
	if _thermal_mat == null:
		_thermal_mat = StandardMaterial3D.new()
		_thermal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_thermal_mat.albedo_color = Color(1.0, 0.25, 0.1)
	for m in all_meshes:
		if is_instance_valid(m):
			m.material_overlay = _thermal_mat if on else null


func set_tint(material: Material) -> void:
	for m in all_meshes:
		if is_instance_valid(m):
			m.material_overlay = material
