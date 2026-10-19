class_name PersonModel
extends Person
## Drop-in replacement for humanoid.gd on NPCs: takes the same outfit dictionaries (humanoid.complete)
## and answers the same calls (animate, swing, set_tint, set_thermal, torso, hand_l/hand_r, held_item),
## but it's a rigged Quaternius person playing real animations.
## Gear (helmets, caps, hoods, vests, belts, coat tails, guns) is placed in skeleton space relative to
## each bone's rest pose, so it sits right on any body.

const HUMANOID := preload("res://scripts/humanoid.gd")
const K := preload("res://scripts/body_kit.gd")
const HAIR_MAP := {"short": "parted", "buzz": "buzzed", "curly": "buzzed", "long": "long", "bun": "buns",
	"ponytail": "long", "bald": ""}
const SKIN_REF := Color(0.93, 0.76, 0.64)   # roughly the colour of the light skin texture

var torso: MeshInstance3D
var all_meshes: Array[MeshInstance3D] = []
var held_item: Node3D
var head_gear: Node3D
var chest: Node3D
## Body-part pivots in the old humanoid.gd convention (down the limb is -Y, forward is -Z, metres),
## riding on the bones, so code written for humanoid.gd can hang pieces on them.
var arm_l: Node3D
var arm_r: Node3D
var forearm_l: Node3D
var forearm_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var body: Node3D          # the model's own frame (as `self` was), carried by the spine
var body_material: ShaderMaterial
var pose_override := {}   # accepted for compatibility; see player_model.gd
## The limb pivots cost a bone attachment each, updated every frame: only the player needs them.
var needs_pivots := false
static var _sculpt_cache := {}
var swing_timer := 0.0
var _thermal_on := false
var _thermal_mat: StandardMaterial3D
var _oneshot_t := 0.0
var _dead := false
var _unit := 1.0      # skeleton units per metre


## Same signature as humanoid.setup(outfit).
func setup(outfit: Dictionary) -> void:
	var o: Dictionary = HUMANOID.complete(outfit)
	var sex := "f" if o["body"] == "f" else "m"
	var gear: String = o["gear"]
	var hair: String = HAIR_MAP.get(str(o["hair"]), "parted")
	if sex == "f" and hair == "buzzed":
		hair = "buzzed_f"
	if gear in ["helmet", "hood"]:
		hair = ""
	elif gear in ["cap", "officer", "beret"]:
		hair = "buzzed" if sex == "m" else "buzzed_f"   # short hair under a cap
	var skin: Color = o["skin"]
	var new_look := {
		"body": sex, "hair": hair, "hair_color": o["hair_color"], "beard": o["beard"] and sex == "m",
		"skin": Color(skin.r / SKIN_REF.r, skin.g / SKIN_REF.g, skin.b / SKIN_REF.b),
		"shirt": o["coat_color"] if o["coat"] else o["shirt"], "pants": o["pants"], "shoes": o["shoes"],
		"long_sleeves": o["top"] != "tshirt" or o["coat"], "camo": o["camo"],
		"denim": not o["camo"] and (o["pants"] as Color).b > (o["pants"] as Color).r,
		"height": (1.04 if sex == "m" else 0.97) * (1.0 + (float(o["bulk"]) - 1.0) * 0.3),
	}
	if o.get("shirtless", false):
		new_look["shirtless"] = true
	new_look["height"] = float(new_look["height"]) * float(o.get("scale_mult", 1.0))
	if o["infected"] or o["veins"] or (o["has_glow"] and o["glow_style"] == "veins"):
		new_look["glow"] = o["glow"]
		new_look["vein_amount"] = 1.0 if o["infected"] else 0.4   # BLACKVEIN shows only a few
	super.setup(new_look)
	torso = body_mesh
	body_material = HUMANOID.body_mat(o)
	_unit = 1.0 / maxf(skeleton.global_transform.basis.get_scale().y, 0.0001)
	chest = bone_attach("spine_03")
	if needs_pivots:
		arm_l = _limb_pivot("upperarm_l")
		arm_r = _limb_pivot("upperarm_r")
		forearm_l = _limb_pivot("lowerarm_l")
		forearm_r = _limb_pivot("lowerarm_r")
		hand_l = _limb_pivot("hand_l")
		hand_r = _limb_pivot("hand_r")
		leg_l = _limb_pivot("thigh_l")
		leg_r = _limb_pivot("thigh_r")
		shin_l = _limb_pivot("calf_l")
		shin_r = _limb_pivot("calf_r")
		body = _frame_pivot("spine_02", Transform3D.IDENTITY)
	_build_gear(o)
	for c in skeleton.get_children():
		if c is MeshInstance3D:
			all_meshes.append(c)


## Puts `node` on a bone, at a spot given in metres relative to that bone's rest position
## (character space: +Y up, +Z forward), so it follows the bone from then on.
func attach_to_body(bone: String, node: Node3D, offset: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Node3D:
	var idx := skeleton.find_bone(bone)
	var ba := bone_attach(bone)
	ba.add_child(node)
	var rest := skeleton.get_bone_global_rest(idx)
	var want := Transform3D(Basis.from_euler(rot).scaled(scl * _unit), rest.origin + offset * _unit)
	node.transform = rest.affine_inverse() * want
	if node is MeshInstance3D:
		all_meshes.append(node)
	return node


## A node on `bone` whose frame, at rest, is `want` given in this model's own coordinates.
func _frame_pivot(bone: String, want: Transform3D) -> Node3D:
	var idx := skeleton.find_bone(bone)
	var ba := bone_attach(bone)
	var piv := Node3D.new()
	ba.add_child(piv)
	var bone_rest_global := skeleton.global_transform * skeleton.get_bone_global_rest(idx)
	piv.transform = bone_rest_global.affine_inverse() * global_transform * want
	return piv


## A limb pivot like humanoid.gd's: at the joint, -Y running down the limb, -Z facing forward.
func _limb_pivot(bone: String) -> Node3D:
	var idx := skeleton.find_bone(bone)
	var to_self := global_transform.affine_inverse() * skeleton.global_transform
	var rest := skeleton.get_bone_global_rest(idx)
	var origin := to_self * rest.origin
	var along := (to_self.basis * rest.basis.y).normalized()   # bones point down +Y
	var y := -along
	var z := Vector3(0, 0, 1) - y * y.z
	if z.length() < 0.2:
		z = Vector3(0, 1, 0) - y * y.y
	z = z.normalized()
	return _frame_pivot(bone, Transform3D(Basis(y.cross(z), y, z), origin))


## Scales a bone's pose (animations here never key scale, so it sticks): bulkier arms or legs.
func set_bone_scale(bone: String, scl: Vector3) -> void:
	var idx := skeleton.find_bone(bone)
	if idx >= 0:
		skeleton.set_bone_pose_scale(idx, scl)


# humanoid.gd helpers, so code written for it keeps working
static func mat(color: Color, emission := 0.0, metallic := 0.0, roughness := 0.8) -> StandardMaterial3D:
	return HUMANOID.mat(color, emission, metallic, roughness)


static func box(size: Vector3) -> BoxMesh:
	return HUMANOID.box(size)


static func sphere(radius: float) -> SphereMesh:
	return HUMANOID.sphere(radius)


static func capsule(radius: float, height: float) -> CapsuleMesh:
	return HUMANOID.capsule(radius, height)


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


func _sculpt(parent: Node3D, key: String, build_fn: Callable, pos := Vector3.ZERO) -> MeshInstance3D:
	var mesh: ArrayMesh
	if _sculpt_cache.has(key):
		mesh = _sculpt_cache[key]
	else:
		var kit := K.new()
		build_fn.call(kit)
		mesh = kit.commit()
		_sculpt_cache[key] = mesh
	return _part(parent, mesh, body_material, pos)


func _piece(mesh: Mesh, color: Color, rough := 0.8, metal := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = HUMANOID.mat(color, 0.0, metal, rough)
	return mi


func _build_gear(o: Dictionary) -> void:
	var gc: Color = o["gear_color"]
	var dark := Color(0.08, 0.075, 0.07)
	# a belt hides the waist seam between the painted shirt and trousers
	var belt := CylinderMesh.new()
	belt.top_radius = 0.165 if look["body"] == "m" else 0.15
	belt.bottom_radius = belt.top_radius
	belt.height = 0.055
	attach_to_body("pelvis", _piece(belt, dark if not o["camo"] else gc.darkened(0.3), 0.6), Vector3(0, 0.1, 0))
	match str(o["gear"]):
		"helmet":
			var h := SphereMesh.new()
			h.radius = 0.13
			h.height = 0.13
			h.is_hemisphere = true
			head_gear = attach_to_body("Head", _piece(h, gc, 0.7), Vector3(0, 0.1, 0.025), Vector3.ZERO, Vector3(1.0, 1.05, 1.12))
		"cap", "officer", "beret":
			var c := CylinderMesh.new()
			c.top_radius = 0.108 if o["gear"] != "beret" else 0.12
			c.bottom_radius = 0.112
			c.height = 0.1 if o["gear"] != "beret" else 0.05
			head_gear = attach_to_body("Head", _piece(c, gc, 0.8), Vector3(0, 0.175, 0.02), Vector3(-0.08, 0, 0))
			if o["gear"] != "beret":
				var brim := BoxMesh.new()
				brim.size = Vector3(0.17, 0.012, 0.09)
				attach_to_body("Head", _piece(brim, gc.darkened(0.2)), Vector3(0, 0.13, 0.13))
		"hood":
			# a shell over the top and back of the head, open at the face
			var hood := SphereMesh.new()
			hood.radius = 0.135
			hood.height = 0.135
			hood.is_hemisphere = true
			# dome tipped up and back: covers the crown, back and sides, face left open
			head_gear = attach_to_body("Head", _piece(hood, o["coat_color"] if o["coat"] else o["shirt"], 0.9),
				Vector3(0, 0.075, -0.02), Vector3(-0.62, 0, 0), Vector3(1.1, 1.38, 1.22))
	if o["vest"]:
		var v := BoxMesh.new()
		v.size = Vector3(0.33, 0.3, 0.23)
		attach_to_body("spine_03", _piece(v, o["vest_color"], 0.85), Vector3(0, -0.02, 0.0))
	if o["coat"]:
		# the back of a long coat, hanging from the hips to the knees
		var back := BoxMesh.new()
		back.size = Vector3(0.36, 0.6, 0.03)
		attach_to_body("pelvis", _piece(back, o["coat_color"], 0.85), Vector3(0, -0.22, -0.13), Vector3(0.1, 0, 0))
	match str(o["item"]):
		"rifle":
			var r := BoxMesh.new()
			r.size = Vector3(0.06, 0.11, 0.8)
			held_item = _hold(_piece(r, Color(0.08, 0.08, 0.08), 0.4, 0.6), 0.22)
		"launcher":
			var l := CylinderMesh.new()
			l.top_radius = 0.07
			l.bottom_radius = 0.07
			l.height = 1.0
			held_item = _hold(_piece(l, Color(0.2, 0.25, 0.15)), 0.1, Vector3(PI * 0.5, 0, 0))


## Puts a gun in the right hand so it points straight ahead in the aiming animation: the hand's pose
## is read from that animation once, and the gun is fixed to the hand relative to it.
func _hold(gun: Node3D, forward: float, rot := Vector3.ZERO) -> Node3D:
	return hold_item(gun, "Pistol_Idle", Vector3(0, 0.02, forward), rot)


## Fixes `item` to the right hand so that, in the pose `ref_anim` starts with, it sits at `offset`
## from the hand (model space, metres, +Z forward) turned by `rot`. Then it follows the hand.
func hold_item(gun: Node3D, ref_anim: String, offset: Vector3, rot := Vector3.ZERO) -> Node3D:
	play(ref_anim, 0.0)
	anim.seek(0.0, true)
	var idx := skeleton.find_bone("hand_r")
	var hand_pose := skeleton.get_bone_global_pose(idx)
	var want := Transform3D(Basis.from_euler(rot).scaled(Vector3.ONE * _unit),
		hand_pose.origin + offset * _unit)
	var ba := bone_attach("hand_r")
	ba.add_child(gun)
	gun.transform = hand_pose.affine_inverse() * want
	if gun is MeshInstance3D:
		all_meshes.append(gun)
	play("Idle", 0.0)
	_oneshot_t = 0.0   # the reference pose cut off whatever was playing
	return gun


func swing(right := true, style := 0, duration := 0.22) -> void:
	swing_timer = duration
	# 0 punch, 1 slash, 2 heavy blow, 3 big swing, 4 gunshot
	var anim_name := "Punch_Cross" if right else "Punch_Jab"
	match style:
		1, 3: anim_name = "Sword_Attack"
		4: anim_name = "Pistol_Shoot"
	_current = ""
	play(anim_name, 0.05)
	anim.seek(0.0, true)
	_oneshot_t = minf(anim.current_animation_length, maxf(duration, 0.35))


## Play a whole animation once (it holds off the locomotion until it ends).
func oneshot(anim_name: String, speed := 1.0, blend := 0.06) -> void:
	if anim == null or ragdolling or not anim.has_animation(anim_name):
		return
	_current = ""
	play(anim_name, blend, speed)
	anim.seek(0.0, true)
	_oneshot_t = anim.current_animation_length / maxf(speed, 0.01)


## mode: idle, walk, run, aim, flail, dead, grabbed, air, glide, crouch, cower (as in humanoid.gd)
func animate(delta: float, speed: float, mode: String) -> void:
	if anim == null or ragdolling:
		return
	swing_timer = maxf(0.0, swing_timer - delta)
	if mode != "dead":
		_dead = false
	if _oneshot_t > 0.0:
		_oneshot_t -= delta
		if mode in ["idle", "walk", "run", "aim"]:
			return
	match mode:
		"walk":
			play("Walk", 0.25, clampf(speed / 1.4, 0.6, 2.2))
		"run":
			if speed > 5.0:
				play("Sprint", 0.2, clampf(speed / 6.5, 0.7, 2.0))
			else:
				play("Jog_Fwd", 0.2, clampf(speed / 3.5, 0.7, 2.0))
		"aim":
			play("Pistol_Idle", 0.25)
		"cower", "crouch":
			play("Crouch_Idle", 0.3)
		"grabbed":
			play("Hit_Chest", 0.15)
		"flail", "air", "glide":
			play("Jump", 0.2)
		"dead":
			if not _dead:
				_dead = true
				play("Death01", 0.15)
		_:
			play("Idle", 0.3)


func plays_death() -> bool:
	return true


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


# ------------------------------------------------------------------ ragdoll

## Bones that get a physics body when someone goes limp: [bone, child bone it reaches to, radius]
const RAGDOLL_BONES := [
	["pelvis", "spine_02", 0.13], ["spine_02", "neck_01", 0.14], ["Head", "", 0.11],
	["upperarm_l", "lowerarm_l", 0.06], ["lowerarm_l", "hand_l", 0.05],
	["upperarm_r", "lowerarm_r", 0.06], ["lowerarm_r", "hand_r", 0.05],
	["thigh_l", "calf_l", 0.08], ["calf_l", "foot_l", 0.065],
	["thigh_r", "calf_r", 0.08], ["calf_r", "foot_r", 0.065],
]
static var _active_ragdolls: Array = []   # oldest first; only a few simulate at once
const MAX_RAGDOLLS := 10

var ragdolling := false


## Goes limp: the skeleton is handed to jointed physics bodies, pushed by `impulse`.
func ragdoll(impulse: Vector3) -> void:
	if ragdolling or skeleton == null:
		return
	ragdolling = true
	_oneshot_t = 0.0
	anim.stop()
	anim.active = false
	var sim := PhysicalBoneSimulator3D.new()
	skeleton.add_child(sim)
	var unit := 1.0 / maxf(skeleton.global_transform.basis.get_scale().y, 0.0001)
	for spec in RAGDOLL_BONES:
		var idx := skeleton.find_bone(spec[0])
		if idx < 0:
			continue
		var pose := skeleton.get_bone_global_pose(idx)
		var length := 0.22 * unit
		if spec[1] != "":
			var child := skeleton.find_bone(spec[1])
			if child >= 0:
				length = pose.origin.distance_to(skeleton.get_bone_global_pose(child).origin)
		var pb := PhysicalBone3D.new()
		pb.bone_name = spec[0]
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE if spec[0] in ["Head", "upperarm_l", "upperarm_r", "thigh_l", "thigh_r"] \
			else PhysicalBone3D.JOINT_TYPE_PIN
		pb.collision_layer = 0
		pb.collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_VEHICLE
		pb.mass = 4.0
		pb.linear_damp = 0.4
		pb.angular_damp = 2.0
		# the body sits halfway down the bone; the joint is at the bone's start
		pb.body_offset = Transform3D(Basis(), Vector3(0, -length * 0.5, 0))
		pb.joint_offset = Transform3D(Basis(), Vector3(0, length * 0.5, 0))
		var shape := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = float(spec[2]) * unit
		cap.height = maxf(length, cap.radius * 2.0 + 0.01)
		shape.shape = cap
		pb.add_child(shape)
		sim.add_child(pb)
		pb.transform = pose * pb.body_offset.affine_inverse()
	sim.physical_bones_start_simulation()
	for pb in sim.get_children():
		if pb is PhysicalBone3D:
			var share := 1.0 if (pb as PhysicalBone3D).bone_name in ["pelvis", "spine_02"] else 0.35
			(pb as PhysicalBone3D).apply_central_impulse(impulse * share)
	_active_ragdolls.append(sim)
	while _active_ragdolls.size() > MAX_RAGDOLLS:
		var old = _active_ragdolls.pop_front()
		if is_instance_valid(old):
			(old as PhysicalBoneSimulator3D).physical_bones_stop_simulation()
