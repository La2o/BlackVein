class_name Person
extends Node3D
## A rigged, animated person built from the Quaternius Universal Base Characters (CC0) and played with
## the Universal Animation Library (CC0): same 65-bone skeleton, so every animation fits every body.
## Clothes are painted on by shaders/person.gdshader; each body vertex is tagged with what it is
## (shoes, trousers, shirt, sleeve) from the bone that moves it, once per body type.
##
## look keys: body "m"/"f", skin Color, hair "" / "buzzed" / "parted" / "long" / "buns" / "buzzed_f",
## beard bool, hair_color Color, shirt/pants/shoes Color, long_sleeves bool, camo bool, denim bool,
## shirtless bool, glow Color (veins), height float (1.0 = default).

const BODIES := {
	"m": "res://assets/characters/base/Superhero_Male_FullBody.gltf",
	"f": "res://assets/characters/base/Superhero_Female_FullBody.gltf",
}
const SKIN_TEX := {
	"m": "res://assets/characters/base/T_Superhero_Male_Ligh.png",
	"f": "res://assets/characters/base/T_Superhero_Female_Light_BaseColor.png",
}
const HAIR := {
	"buzzed": "Hair_Buzzed", "parted": "Hair_SimpleParted", "long": "Hair_Long",
	"buns": "Hair_Buns", "buzzed_f": "Hair_BuzzedFemale", "beard": "Hair_Beard",
}
const ANIMS := "res://assets/characters/animations/UAL1_Standard.glb"
const ANIMS_2 := "res://assets/characters/animations/UAL2_Standard.glb"   # parkour, sword combos, throws
const SHADER := preload("res://shaders/person.gdshader")
const OUTFIT_SHADER := preload("res://shaders/outfit.gdshader")
## Full outfits (Quaternius Modular Character Outfits, CC0) worn over just the base body's head.
const OUTFITS := {
	"ranger": "res://assets/characters/outfits/Male_Ranger.gltf",
}

## region per bone: shoes, trousers, shirt, short sleeve (upper arm), long sleeve (forearm)
const BONE_REGION := {
	"foot_l": "shoes", "foot_r": "shoes", "ball_l": "shoes", "ball_r": "shoes",
	"pelvis": "pants", "thigh_l": "pants", "thigh_r": "pants", "calf_l": "pants", "calf_r": "pants",
	"spine_01": "shirt", "spine_02": "shirt", "spine_03": "shirt", "clavicle_l": "shirt", "clavicle_r": "shirt",
	"upperarm_l": "shirt", "upperarm_r": "shirt", "lowerarm_l": "sleeve", "lowerarm_r": "sleeve",
}

static var _meshes := {}      # body -> ArrayMesh with region colours
static var _scenes := {}      # path -> PackedScene, held so Godot doesn't reload it for every person
static var _hair := {}        # hair file -> [{mesh, skin, material}] so each style is loaded once
static var _library: AnimationLibrary = null

## Walking and running cycles: the ground speed each covers at 1x (in body heights per second, so it
## scales with the person) and its phase relative to Walk (the shift that lines the thighs up). Measured
## with tests/anim_slip.gd -- calibrate. Playing a cycle at speed / (this * height) keeps the feet planted.
const CYCLES := {
	"Walk": [0.561, 0.0], "Walk_Formal": [0.561, 0.0], "Zombie_Walk_Fwd": [0.561, 0.12],
	"Jog_Fwd": [3.451, 0.91], "Sprint": [5.433, 0.89], "Crouch_Fwd": [0.449, 0.0], "Walk_Carry": [0.401, 0.02],
}
## Stances that ship as one-shots but are held for as long as you stand in them.
const LOOP_FIX := ["Sword_Idle", "Idle_Shield", "NinjaJump_Idle", "Slide"]
## The arms (from the collarbones down to the fingertips): the upper-body layer poses these fully,
## and straightens the upper spine most of the way (so a gun stays level while the legs sprint).
const ARM_ROOTS := ["clavicle_l", "clavicle_r"]
const UPPER_SPINE := {"spine_02": 0.5, "spine_03": 0.7}
static var _arm_tracks := {}   # animation -> [[bone index, rotation track index, weight], ...]
static var _all_tracks := {}   # animation -> [[bone index, track index, track type], ...]

## Crossfades are done here, not by the AnimationPlayer (its one speed_scale would also speed up or
## slow down the animation fading out, which jerks the legs when a walk turns into a run). The old
## animation keeps playing at its own rate underneath the new one until it has faded out; a change
## in the middle of a fade fades out from a still copy of the pose instead.
var _fade_from := ""           # the animation fading out ("" = a still pose, _fade_pose)
var _fade_pos := 0.0
var _fade_rate := 1.0
var _fade_time := 0.0
var _fade_len := 0.0
var _fade_pose: Array = []     # [rotation, position] per bone when fading out from a still pose

var height_m := 1.8            # this person's height in metres (set in setup)
var always_animate := false    # skip the distance level of detail (the player; animation tests)
## Upper-body layer: the arms take their pose from another animation while the legs keep walking or
## running (aiming a gun, carrying someone, holding a blade). Fades in and out.
var upper_anim := ""
var upper_time := -1.0         # a fixed moment of upper_anim, or -1 to play it through
var _upper_w := 0.0
var _upper_t := 0.0
## Aiming: the chest turns (up to 60 degrees) so the held `aim_item` points along `aim_dir` (world
## space; ZERO = off). The item is built pointing along its +Z.
var aim_dir := Vector3.ZERO
var aim_item: Node3D = null
## Both arms straight up (lifting a car over your head), 0..1, eased.
var arms_up := 0.0
var _arms_up_w := 0.0

var look := {}
var skeleton: Skeleton3D
var anim: AnimationPlayer
var body_mesh: MeshInstance3D
var body_mat: ShaderMaterial
var foot_offset := 0.0   # where the feet go relative to this node (NPC capsules are centred: -0.9)
var _current := ""


func setup(new_look: Dictionary) -> void:
	look = new_look
	for c in get_children():
		c.queue_free()
	var body: String = look.get("body", "m")
	var packed := _scene(BODIES[body])
	var root: Node3D = packed.instantiate()
	add_child(root)
	skeleton = root.get_node("Armature/Skeleton3D")
	for c in skeleton.get_children():
		var mi := c as MeshInstance3D
		if mi and str(mi.name).to_lower().begins_with("superhero"):
			body_mesh = mi
	var src_mat := body_mesh.mesh.surface_get_material(0) as StandardMaterial3D
	body_mesh.mesh = _region_mesh(body, body_mesh)
	body_mat = ShaderMaterial.new()
	body_mat.shader = SHADER
	body_mat.set_shader_parameter("skin_tex", _res(SKIN_TEX[body]))
	if src_mat:
		body_mat.set_shader_parameter("normal_tex", src_mat.normal_texture)
		body_mat.set_shader_parameter("rough_tex", src_mat.roughness_texture)
	body_mesh.material_override = body_mat
	apply_colors()
	var brows := skeleton.get_node_or_null("Eyebrows") as MeshInstance3D
	if brows:
		var bm := StandardMaterial3D.new()
		bm.albedo_color = (look.get("hair_color", Color(0.2, 0.14, 0.09)) as Color) * 0.8
		bm.roughness = 0.9
		brows.material_override = bm
	var hair: String = look.get("hair", "")
	if hair != "":
		_add_hair(HAIR[hair], look.get("hair_color", Color(0.2, 0.14, 0.09)))
	if look.get("beard", false):
		_add_hair(HAIR["beard"], look.get("hair_color", Color(0.2, 0.14, 0.09)))
	# every body is scaled to 1.8 m (times its height), feet on foot_offset
	var tall: float = body_mesh.mesh.get_aabb().size.y * skeleton.global_transform.basis.get_scale().y / maxf(root.scale.y, 0.0001)
	if look.has("outfit"):
		_wear_outfit(str(look["outfit"]), body, body_mesh)
	var h: float = look.get("height", 1.0)
	height_m = 1.8 * h
	root.scale = Vector3.ONE * (1.8 / maxf(tall, 0.1)) * h
	root.position.y = foot_offset
	root.rotation.y = PI   # the models face +Z; the game's forward is -Z
	anim = AnimationPlayer.new()
	root.add_child(anim)
	_current = ""   # a rebuilt body has a fresh player: whatever played before must start again
	anim.add_animation_library("", library())
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	play("Idle")


func apply_colors() -> void:
	body_mat.set_shader_parameter("skin_tint", look.get("skin", Color(1, 1, 1)))
	body_mat.set_shader_parameter("shirt_color", look.get("shirt", Color(0.3, 0.35, 0.45)))
	body_mat.set_shader_parameter("pants_color", look.get("pants", Color(0.2, 0.22, 0.3)))
	body_mat.set_shader_parameter("shoe_color", look.get("shoes", Color(0.1, 0.09, 0.08)))
	body_mat.set_shader_parameter("long_sleeves", 1.0 if look.get("long_sleeves", true) else 0.0)
	body_mat.set_shader_parameter("camo", 1.0 if look.get("camo", false) else 0.0)
	body_mat.set_shader_parameter("denim", 1.0 if look.get("denim", false) else 0.0)
	body_mat.set_shader_parameter("shirtless", 1.0 if look.get("shirtless", false) else 0.0)
	var glow: Color = look.get("glow", Color(0, 0, 0))
	body_mat.set_shader_parameter("glow_color", glow)
	body_mat.set_shader_parameter("glow", 1.0 if glow.v > 0.01 else 0.0)
	body_mat.set_shader_parameter("vein_amount", look.get("vein_amount", 1.0))


var _anim_acc := 0.0

## Animation level of detail: people far from the camera update their pose less often.
func _process(delta: float) -> void:
	if anim == null:
		return
	_anim_acc += delta
	var interval := 0.0
	var cam := get_viewport().get_camera_3d()
	if cam and not always_animate:
		var d := cam.global_position.distance_to(global_position)
		if d > 220.0:
			return
		interval = 0.0 if d < 40.0 else (1.0 / 15.0 if d < 90.0 else 1.0 / 6.0)
	if _anim_acc >= interval:
		anim.advance(_anim_acc)
		_post_pose(_anim_acc)
		_anim_acc = 0.0


## Plays a walking/running cycle at the rate that matches `ground_speed` (m/s), so the planted foot
## doesn't slide. Switching from another cycle carries the stride over (same foot, same moment) so
## the legs never scissor.
func play_cycle(anim_name: String, ground_speed: float, blend := 0.2, max_rate := 3.0) -> void:
	var c: Array = CYCLES[anim_name]
	var rate := clampf(ground_speed / (float(c[0]) * height_m), 0.3, max_rate)
	if anim_name == _current:
		anim.speed_scale = rate
		return
	var phase := -1.0
	if CYCLES.has(_current) and anim.current_animation != "" and anim.current_animation_length > 0.0:
		var old: Array = CYCLES[_current]
		phase = fposmod(anim.current_animation_position / anim.current_animation_length - float(old[1]), 1.0)
	_start_fade(blend)
	_current = anim_name
	anim.play(anim_name, 0.0)
	anim.speed_scale = rate
	if phase >= 0.0:
		anim.seek(fposmod(phase + float(c[1]), 1.0) * anim.current_animation_length)


## After the animation has posed the body: the crossfade, the upper-body layer and the arms-up lift.
func _post_pose(delta: float) -> void:
	_apply_fade(delta)
	var want := 1.0 if upper_anim != "" else 0.0
	_upper_w = move_toward(_upper_w, want, delta * 6.0)
	_arms_up_w = move_toward(_arms_up_w, arms_up, delta * 5.0)
	if _upper_w > 0.001 and upper_anim != "" and anim.has_animation(upper_anim):
		var a := anim.get_animation(upper_anim)
		_upper_t += delta
		var t := upper_time if upper_time >= 0.0 else (fposmod(_upper_t, a.length) if a.loop_mode != Animation.LOOP_NONE else minf(_upper_t, a.length))
		var w := smoothstep(0.0, 1.0, _upper_w)
		for tr in _arm_tracks_for(upper_anim, a):
			var bone: int = tr[0]
			var q := a.rotation_track_interpolate(tr[1], t)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(q, w * float(tr[2])))
	elif _upper_w <= 0.001:
		_upper_t = 0.0
	if aim_dir != Vector3.ZERO and aim_item != null and is_instance_valid(aim_item):
		_aim_chest()
	if _arms_up_w > 0.001:
		var w2 := smoothstep(0.0, 1.0, _arms_up_w)
		for side in [["upperarm_l", "lowerarm_l", "hand_l", 1.0], ["upperarm_r", "lowerarm_r", "hand_r", -1.0]]:
			# skeleton space: +Y up, +Z the way the body faces, +X its left
			var up := Vector3(0.22 * float(side[3]), 1.0, 0.12).normalized()
			_aim_bone(side[0], side[1], up, w2)
			_aim_bone(side[1], side[2], up, w2)


## Turns the upper spine so the held item points along aim_dir, shared between two spine bones.
func _aim_chest() -> void:
	var hand := skeleton.find_bone("hand_r")
	if hand < 0:
		return
	var f := (_global_pose(hand) * aim_item.transform).basis.z.normalized()
	var want := (skeleton.global_transform.basis.inverse() * aim_dir).normalized()
	var angle := f.angle_to(want)
	if angle < 0.01:
		return
	var axis := f.cross(want).normalized()
	if axis.length() < 0.5:
		return
	angle = minf(angle, deg_to_rad(60.0))
	for part in [["spine_02", 0.4], ["spine_03", 0.6]]:
		var b := skeleton.find_bone(part[0])
		var parent := skeleton.get_bone_parent(b)
		var pg := _global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
		var bg := pg * skeleton.get_bone_pose(b)
		var new_global := Basis(Quaternion(axis, angle * float(part[1]))) * bg.basis
		skeleton.set_bone_pose_rotation(b, (pg.basis.inverse() * new_global).get_rotation_quaternion())


## Turns `bone` so the line from it to `child` points along `dir` (skeleton space), by `weight`.
func _aim_bone(bone_name: String, child_name: String, dir: Vector3, weight: float) -> void:
	var b := skeleton.find_bone(bone_name)
	var c := skeleton.find_bone(child_name)
	if b < 0 or c < 0:
		return
	var parent := skeleton.get_bone_parent(b)
	var pg := _global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var bg := pg * skeleton.get_bone_pose(b)
	var cg := bg * skeleton.get_bone_pose(c)
	var cur := (cg.origin - bg.origin).normalized()
	if cur.length() < 0.5:
		return
	var turn := Quaternion(cur, dir.normalized())
	var new_global := Basis(turn) * bg.basis
	var local := (pg.basis.inverse() * new_global).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(b, skeleton.get_bone_pose_rotation(b).slerp(local, weight))


## A bone's pose in skeleton space, from the local poses (fresh even mid-frame).
func _global_pose(b: int) -> Transform3D:
	var t := skeleton.get_bone_pose(b)
	var p := skeleton.get_bone_parent(b)
	while p >= 0:
		t = skeleton.get_bone_pose(p) * t
		p = skeleton.get_bone_parent(p)
	return t


## The rotation tracks of `a` that drive the arms, looked up once per animation.
func _arm_tracks_for(anim_name: String, a: Animation) -> Array:
	if _arm_tracks.has(anim_name):
		return _arm_tracks[anim_name]
	var arm_bones := {}
	for root_name in ARM_ROOTS:
		var r := skeleton.find_bone(root_name)
		if r < 0:
			continue
		var stack := [r]
		while not stack.is_empty():
			var b: int = stack.pop_back()
			arm_bones[skeleton.get_bone_name(b)] = b
			for ch in skeleton.get_bone_children(b):
				stack.append(ch)
	var out := []
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var bone_name := str(a.track_get_path(i).get_concatenated_subnames())
		if arm_bones.has(bone_name):
			out.append([arm_bones[bone_name], i, 1.0])
		elif UPPER_SPINE.has(bone_name):
			out.append([skeleton.find_bone(bone_name), i, UPPER_SPINE[bone_name]])
	_arm_tracks[anim_name] = out
	return out


## Crossfades to an animation from the library (no-op if it's already playing).
func play(anim_name: String, blend := 0.2, speed := 1.0) -> void:
	if anim_name == _current:
		anim.speed_scale = speed
		return
	_start_fade(blend)
	_current = anim_name
	anim.play(anim_name, 0.0)
	anim.speed_scale = speed


## Begins fading out of whatever the body is doing now, over `blend` seconds.
func _start_fade(blend: float) -> void:
	_fade_len = 0.0
	if blend <= 0.0 or skeleton == null or anim.current_animation == "":
		return
	if _fade_time < _fade_len_prev:
		# already mid-fade: fade from the pose as it is right now
		_fade_from = ""
		_fade_pose.clear()
		for b in skeleton.get_bone_count():
			_fade_pose.append([skeleton.get_bone_pose_rotation(b), skeleton.get_bone_pose_position(b)])
	else:
		_fade_from = anim.current_animation
		_fade_pos = anim.current_animation_position
		_fade_rate = anim.speed_scale
	_fade_time = 0.0
	_fade_len = blend
	_fade_len_prev = blend


var _fade_len_prev := 0.0


## Mixes the fading-out animation (or still pose) over the pose the new animation just set.
func _apply_fade(delta: float) -> void:
	if _fade_len <= 0.0 or _fade_time >= _fade_len:
		return
	_fade_time += delta
	var w := 1.0 - smoothstep(0.0, 1.0, clampf(_fade_time / _fade_len, 0.0, 1.0))
	if w <= 0.0:
		return
	if _fade_from == "":
		for b in mini(_fade_pose.size(), skeleton.get_bone_count()):
			var p: Array = _fade_pose[b]
			skeleton.set_bone_pose_rotation(b, skeleton.get_bone_pose_rotation(b).slerp(p[0], w))
			skeleton.set_bone_pose_position(b, skeleton.get_bone_pose_position(b).lerp(p[1], w))
		return
	if not anim.has_animation(_fade_from):
		return
	var a := anim.get_animation(_fade_from)
	_fade_pos += delta * _fade_rate
	var t := fposmod(_fade_pos, a.length) if a.loop_mode != Animation.LOOP_NONE else minf(_fade_pos, a.length)
	for tr in _tracks_for(_fade_from, a):
		var bone: int = tr[0]
		if tr[2] == Animation.TYPE_ROTATION_3D:
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(a.rotation_track_interpolate(tr[1], t), w))
		else:
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone).lerp(a.position_track_interpolate(tr[1], t), w))


## Every bone rotation and position track of `a`, looked up once per animation.
func _tracks_for(anim_name: String, a: Animation) -> Array:
	if _all_tracks.has(anim_name):
		return _all_tracks[anim_name]
	var out := []
	for i in a.get_track_count():
		var ty := a.track_get_type(i)
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D:
			continue
		var b := skeleton.find_bone(str(a.track_get_path(i).get_concatenated_subnames()))
		if b >= 0:
			out.append([b, i, ty])
	_all_tracks[anim_name] = out
	return out


func bone_attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	return ba


func _add_hair(file: String, col: Color) -> void:
	if not _hair.has(file):
		var parts: Array = []
		var scene: Node = _scene("res://assets/characters/hair/%s.gltf" % file).instantiate()
		for c in scene.get_node("Armature/Skeleton3D").get_children():
			var src := c as MeshInstance3D
			if src:
				parts.append({"mesh": src.mesh, "skin": src.skin, "material": src.mesh.surface_get_material(0)})
		scene.free()
		_hair[file] = parts
	for part in _hair[file]:
		var mi := MeshInstance3D.new()
		mi.mesh = part["mesh"]
		mi.skin = part["skin"]
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		var m: Material = part["material"]
		if m is StandardMaterial3D:
			var hm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			hm.albedo_color = col * 2.2
			mi.material_override = hm


## Does the slow one-time work (clothing regions per body, the animation library) up front, so the
## first person to spawn doesn't cause a hitch. main.gd calls it while the city is built.
static func warm_up() -> void:
	library()
	for b in BODIES:
		_scene(BODIES[b])
	for body in BODIES:
		if _meshes.has(body):
			continue
		var scene: Node = _scene(BODIES[body]).instantiate()
		for c in scene.get_node("Armature/Skeleton3D").get_children():
			if c is MeshInstance3D and str(c.name).to_lower().begins_with("superhero"):
				_region_mesh(body, c)
		scene.free()


## Resources are only cached while something references them: keep these alive, or every spawn
## reads the whole character file from disk again (~60 ms each).
static func _scene(path: String) -> PackedScene:
	return _res(path) as PackedScene


static func _res(path: String) -> Resource:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


static func library() -> AnimationLibrary:
	if _library == null:
		var scene: Node = _scene(ANIMS).instantiate()
		var ap := scene.get_node("AnimationPlayer") as AnimationPlayer
		_library = ap.get_animation_library("")   # Godot already loops the "_Loop" ones and drops the suffix
		scene.free()
		# the second library rides on the same skeleton: add whatever the first one lacks
		var scene2: Node = _scene(ANIMS_2).instantiate()
		var lib2 := (scene2.get_node("AnimationPlayer") as AnimationPlayer).get_animation_library("")
		for a in lib2.get_animation_list():
			if not _library.has_animation(a) and a != "A_TPose":
				_library.add_animation(a, lib2.get_animation(a))
		scene2.free()
		for a in LOOP_FIX:
			if _library.has_animation(a):
				_library.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	return _library


## Swaps the body for the head alone and puts the outfit's meshes on our skeleton (same rig, so they
## follow every animation), recoloured by outfit.gdshader.
func _wear_outfit(outfit_id: String, body: String, mi: MeshInstance3D) -> void:
	mi.mesh = _head_mesh(body, mi)
	var src: Node = _scene(OUTFITS[outfit_id]).instantiate()
	var parts: Array[Node] = src.find_children("*", "MeshInstance3D", true, false)
	for n in parts:
		var part := n as MeshInstance3D
		var mat := part.mesh.surface_get_material(0) as StandardMaterial3D
		var skin_set := mat != null and mat.albedo_texture != null and mat.albedo_texture.resource_path.contains("Regular")
		var sm := ShaderMaterial.new()
		sm.shader = OUTFIT_SHADER
		if mat:
			sm.set_shader_parameter("albedo_tex", mat.albedo_texture)
			sm.set_shader_parameter("normal_tex", mat.normal_texture)
			sm.set_shader_parameter("orm_tex", mat.roughness_texture if skin_set else mat.metallic_texture)
		sm.set_shader_parameter("roughness_only", skin_set)
		if skin_set:
			var skin: Color = look.get("skin", Color(1, 1, 1))
			var skin_ref := Color(0.85, 0.66, 0.55)   # the base character's light skin, so hands match the face
			sm.set_shader_parameter("cloth_tint", Color(skin_ref.r * skin.r, skin_ref.g * skin.g, skin_ref.b * skin.b) * 0.55)
			sm.set_shader_parameter("leather_tint", Color(skin_ref.r * skin.r, skin_ref.g * skin.g, skin_ref.b * skin.b) * 0.55)
		else:
			sm.set_shader_parameter("cloth_tint", look.get("outfit_cloth", Color(0.16, 0.03, 0.035)))
			sm.set_shader_parameter("leather_tint", look.get("outfit_leather", Color(0.13, 0.12, 0.13)))
			var glow: Color = look.get("glow", Color(0, 0, 0))
			sm.set_shader_parameter("glow_color", glow)
			sm.set_shader_parameter("glow", 0.45 if glow.v > 0.01 else 0.0)
		var skin_res := part.skin
		part.owner = null
		part.get_parent().remove_child(part)
		skeleton.add_child(part)
		part.skin = skin_res
		part.skeleton = NodePath("..")
		part.material_override = sm
		part.transform = Transform3D.IDENTITY
	src.free()


## Only the head (and neck) of a base body: the rest is under the outfit.
static func _head_mesh(body: String, mi: MeshInstance3D) -> ArrayMesh:
	var key := body + "_head"
	if _meshes.has(key):
		return _meshes[key]
	var full: ArrayMesh = mi.mesh
	var arrays := full.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(verts.size(), 1)
	var keep_bones := {}
	for i in mi.skin.get_bind_count():
		var bn := str(mi.skin.get_bind_name(i))
		if bn == "":
			bn = mi.get_node(mi.skeleton).get_bone_name(mi.skin.get_bind_bone(i))
		if bn in ["Head", "neck_01"]:
			keep_bones[i] = true
	var keep := PackedByteArray()
	keep.resize(verts.size())
	for v in verts.size():
		var best := 0
		var best_w := -1.0
		for k in per:
			if weights[v * per + k] > best_w:
				best_w = weights[v * per + k]
				best = bones[v * per + k]
		keep[v] = 1 if keep_bones.has(best) else 0
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out_idx := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if keep[idx[t]] == 1 and keep[idx[t + 1]] == 1 and keep[idx[t + 2]] == 1:
			out_idx.append(idx[t])
			out_idx.append(idx[t + 1])
			out_idx.append(idx[t + 2])
	arrays[Mesh.ARRAY_INDEX] = out_idx
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	_meshes[key] = out
	return out


## The body mesh with every vertex coloured by the clothing region of its strongest bone.
static func _region_mesh(body: String, mi: MeshInstance3D) -> ArrayMesh:
	if _meshes.has(body):
		return _meshes[body]
	var src := mi.mesh
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(verts.size(), 1)
	var bind_names: Array[String] = []
	for i in mi.skin.get_bind_count():
		var bn := str(mi.skin.get_bind_name(i))
		if bn == "":
			bn = mi.get_node(mi.skeleton).get_bone_name(mi.skin.get_bind_bone(i))
		bind_names.append(bn)
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for v in verts.size():
		var best := 0
		var best_w := -1.0
		for k in per:
			if weights[v * per + k] > best_w:
				best_w = weights[v * per + k]
				best = bones[v * per + k]
		var region: String = BONE_REGION.get(bind_names[best] if best < bind_names.size() else "", "")
		match region:
			"shoes": colors[v] = Color(0, 0, 1, 0)
			"pants": colors[v] = Color(1, 0, 0, 0)
			"shirt": colors[v] = Color(0, 1, 0, 0)
			"sleeve": colors[v] = Color(0, 0, 0, 1)
			_: colors[v] = Color(0, 0, 0, 0)
	arrays[Mesh.ARRAY_COLOR] = colors
	for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[c] = null   # extra glTF vertex data the shader doesn't use
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	_meshes[body] = out
	return out
