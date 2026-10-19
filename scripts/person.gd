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
	if cam:
		var d := cam.global_position.distance_to(global_position)
		if d > 220.0:
			return
		interval = 0.0 if d < 40.0 else (1.0 / 15.0 if d < 90.0 else 1.0 / 6.0)
	if _anim_acc >= interval:
		anim.advance(_anim_acc)
		_anim_acc = 0.0


## Crossfades to an animation from the library (no-op if it's already playing).
func play(anim_name: String, blend := 0.2, speed := 1.0) -> void:
	if anim_name == _current:
		anim.speed_scale = speed
		return
	_current = anim_name
	anim.play(anim_name, blend)
	anim.speed_scale = speed


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
