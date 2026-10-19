extends "res://scripts/person_model.gd"
## The player's body: a rigged Quaternius person (person_model.gd) in the hooded long-coat true form,
## disguises, arm transformations, body forms (shield, armor, wings, light) and leg forms.
## Pieces hang on the humanoid-style pivots (arm_l, forearm_r, hand_r, leg_l, shin_r, body) so they
## follow the animated bones; bulkier forms scale the bones themselves.

enum Form { FISTS, CLAWS, HAMMER, BLADE, WHIP, MUSCLE, SPIKES }
enum Defense { NONE, SHIELD, ARMOR, WINGS, LIGHT }   # same order as PlayerPowers.Defense
enum Legs { NORMAL, RUNNER, LEAPER, CRAWLER, CRUSHER }

const FLESH := Color(0.42, 0.04, 0.05)
## BLACKVEIN's own look: the hooded Ranger outfit (Quaternius, CC0) in black and blood red.
const DEFAULT_OUTFIT := {
	"shirt": Color(0.11, 0.115, 0.13), "pants": Color(0.17, 0.17, 0.19),
	"skin": Color(0.62, 0.48, 0.4), "gear": "none", "gear_color": Color(0.09, 0.09, 0.1),
	"glow": Color(1, 0.16, 0.1), "coat": false, "coat_color": Color(0.1, 0.1, 0.115),
	"veins": true, "top": "long", "boots": false, "gloves": false, "belt": false, "hair": "bald",
	"outfit": "ranger", "outfit_cloth": Color(0.22, 0.035, 0.04), "outfit_leather": Color(0.17, 0.16, 0.17),
}

var form: int = Form.FISTS
var defense: int = Defense.NONE
var outfit: Dictionary = DEFAULT_OUTFIT
var true_form := true
var _form_parts: Array[MeshInstance3D] = []
var _defense_parts: Array[MeshInstance3D] = []
var _whip_links: Array[MeshInstance3D] = []
var _t := 0.0
var _wing_pivots: Array[Node3D] = []
var wings_visible := false
var legs: int = Legs.NORMAL
var _leg_parts: Array[MeshInstance3D] = []
var _crawler: Array[Node3D] = []
var _flap := 0.0
var _wing_open := 0.0
var creature := 0                 # PlayerPowers.Creature
var _human_outfit: Dictionary = {}
var _human_true := true

## The creature forms' bodies (humanoid outfit keys, plus shirtless / scale_mult for person_model.gd).
const CREATURE_OUTFITS := [
	{},
	{"body": "m", "skin": Color(0.5, 0.16, 0.12), "pants": Color(0.12, 0.08, 0.07), "shoes": Color(0.2, 0.06, 0.05),
		"gear": "none", "hair": "bald", "infected": true, "glow": Color(1, 0.25, 0.08), "shirtless": true,
		"scale_mult": 1.35},
	{"body": "m", "skin": Color(0.17, 0.16, 0.19), "pants": Color(0.06, 0.06, 0.07), "shoes": Color(0.05, 0.05, 0.06),
		"gear": "none", "hair": "bald", "veins": true, "glow": Color(0.3, 0.9, 1.0), "shirtless": true, "scale_mult": 1.06},
	{"body": "m", "skin": Color(0.78, 0.76, 0.8), "pants": Color(0.25, 0.22, 0.24), "shoes": Color(0.2, 0.18, 0.2),
		"gear": "none", "hair": "bald", "veins": true, "glow": Color(0.85, 0.2, 1.0), "shirtless": true, "scale_mult": 1.0},
]


func build(new_outfit: Dictionary = {}) -> void:
	outfit = DEFAULT_OUTFIT if new_outfit.is_empty() else new_outfit
	true_form = new_outfit.is_empty()
	if creature != 0:
		# a disguise or outfit change while transformed applies when you turn back
		_human_outfit = outfit
		_human_true = true_form
		_build_body(CREATURE_OUTFITS[creature])
		return
	_build_body(outfit)


## Whole-body change: becomes the creature (keeping arm, body and leg forms), or back to the
## human body you had before.
func set_creature(c: int) -> void:
	if c == creature:
		return
	if creature == 0:
		_human_outfit = outfit
		_human_true = true_form
	creature = c
	if c == 0:
		outfit = _human_outfit if not _human_outfit.is_empty() else DEFAULT_OUTFIT
		true_form = _human_true
		_build_body(outfit)
	else:
		_build_body(CREATURE_OUTFITS[c])


func _build_body(look_outfit: Dictionary) -> void:
	_form_parts.clear()
	_defense_parts.clear()
	_whip_links.clear()
	# a disguise copies the outfit, not the victim's prop gun: only weapons you pick up are shown
	var worn := look_outfit.duplicate()
	worn["item"] = "none"
	foot_offset = -0.9
	needs_pivots = true
	setup(worn)
	_wing_pivots.clear()
	_crawler.clear()
	_leg_parts.clear()
	_apply_form()
	_apply_defense()
	_apply_legs()
	_apply_creature()


var _creature_parts: Array[MeshInstance3D] = []

## Bone spikes, claws and glowing eyes for the creature forms; bulk comes from scaling bones.
func _apply_creature() -> void:
	_clear(_creature_parts)
	if creature == 0 or arm_l == null:
		return
	var bone := mat(Color(0.86, 0.8, 0.7), 0.0, 0.0, 0.45)
	var dark := mat(Color(0.06, 0.02, 0.02), 0.0, 0.3, 0.25)
	match creature:
		1:   # Brute: spikes down the back and on the shoulders, huge claws, bulging arms and chest
			for b in ["upperarm_l", "upperarm_r"]:
				set_bone_scale(b, Vector3(1.5, 1.05, 1.5))
			for b in ["lowerarm_l", "lowerarm_r"]:
				set_bone_scale(b, Vector3(1.4, 1.0, 1.4))
			set_bone_scale("spine_03", Vector3(1.25, 1.1, 1.25))
			for i in 6:
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.06
				cone.height = 0.42 - i * 0.04
				var spike := MeshInstance3D.new()
				spike.mesh = cone
				spike.material_override = bone
				attach_to_body("spine_03" if i < 3 else "spine_01", spike,
					Vector3((i % 2) * 0.13 - 0.065, 0.14 - (i % 3) * 0.1, -0.17), Vector3(-0.9, 0, 0))
				_creature_parts.append(spike)
			for arm in [arm_l, arm_r]:
				var sc := CylinderMesh.new()
				sc.top_radius = 0.0
				sc.bottom_radius = 0.05
				sc.height = 0.3
				_add(_creature_parts, arm, sc, bone, Vector3(0, 0.02, 0.0), Vector3(0, 0, 0))
			for hand in [hand_l, hand_r]:
				for i in 3:
					_add(_creature_parts, hand, box(Vector3(0.03, 0.3, 0.05)), dark, Vector3((i - 1) * 0.055, -0.17, -0.07), Vector3(0.7, 0, (i - 1) * 0.15))
		2:   # Stalker: long thin claws and two glowing eyes
			for hand in [hand_l, hand_r]:
				for i in 2:
					_add(_creature_parts, hand, box(Vector3(0.015, 0.5, 0.03)), dark, Vector3((i - 0.5) * 0.05, -0.26, -0.03), Vector3(0.2, 0, (i - 0.5) * 0.12))
		3:   # Wraith: bony claws; the wings stay open (see animate)
			for hand in [hand_l, hand_r]:
				for i in 3:
					_add(_creature_parts, hand, box(Vector3(0.012, 0.3, 0.025)), bone, Vector3((i - 1) * 0.04, -0.17, -0.02), Vector3(0.2, 0, (i - 1) * 0.12))
	if creature in [2, 3]:
		var eye := mat(Color(0.3, 0.9, 1.0) if creature == 2 else Color(0.85, 0.3, 1.0), 4.0)
		for side in [-1.0, 1.0]:
			var e := MeshInstance3D.new()
			e.mesh = sphere(0.016)
			e.material_override = eye
			attach_to_body("Head", e, Vector3(side * 0.033, 0.075, 0.085))
			_creature_parts.append(e)


func set_form(f: int) -> void:
	form = f
	_apply_form()


func set_defense(d: int) -> void:
	defense = d
	_apply_defense()


func set_legs(l: int) -> void:
	legs = l
	_apply_legs()


func flap() -> void:
	_flap = 0.45


func _clear(list: Array[MeshInstance3D]) -> void:
	for n in list:
		all_meshes.erase(n)
		if is_instance_valid(n):
			n.queue_free()
	list.clear()


func _add(list: Array[MeshInstance3D], parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := _part(parent, mesh, material, pos)
	mi.rotation = rot
	mi.scale = scl
	list.append(mi)
	return mi


func _apply_form() -> void:
	if arm_l == null:
		return
	_clear(_form_parts)
	_whip_links.clear()
	for b in ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"]:
		set_bone_scale(b, Vector3.ONE)
	var flesh := mat(FLESH, 0.5, 0.0, 0.35)
	var dark := mat(Color(0.07, 0.02, 0.02), 0.0, 0.3, 0.25)
	var glow := mat(Color(1, 0.12, 0.06), 2.5)
	match form:
		Form.CLAWS:
			for hand in [hand_l, hand_r]:
				for i in 3:
					var x := (i - 1) * 0.05
					_add(_form_parts, hand, box(Vector3(0.022, 0.6, 0.05)), dark, Vector3(x, -0.28, -0.03), Vector3(0.18, 0, (i - 1) * 0.12))
				_add(_form_parts, hand, sphere(0.1), flesh, Vector3(0, 0.02, 0))
		Form.HAMMER:
			for hand in [hand_l, hand_r]:
				_add(_form_parts, hand, sphere(0.27), flesh, Vector3(0, -0.12, 0))
				for k in 4:
					var a := k * TAU / 4.0
					_add(_form_parts, hand, box(Vector3(0.1, 0.2, 0.1)), dark, Vector3(cos(a) * 0.22, -0.18, sin(a) * 0.22), Vector3(0.5, a, 0.3))
			for b in ["upperarm_l", "upperarm_r"]:
				set_bone_scale(b, Vector3(1.35, 1.0, 1.35))
		Form.BLADE:
			_add(_form_parts, forearm_r, capsule(0.075, 0.42), flesh, Vector3(0, -0.12, 0))
			_add(_form_parts, hand_r, box(Vector3(0.05, 1.8, 0.26)), dark, Vector3(0, -0.92, 0))
			_add(_form_parts, hand_r, box(Vector3(0.06, 1.7, 0.03)), glow, Vector3(0, -0.92, -0.13))
		Form.WHIP:
			_add(_form_parts, forearm_r, capsule(0.07, 0.4), flesh, Vector3(0, -0.1, 0))
			var parent: Node3D = hand_r
			for k in 9:
				var link := _add(_form_parts, parent, sphere(0.09 - k * 0.006), flesh if k % 2 == 0 else dark, Vector3(0, -0.16, 0))
				_whip_links.append(link)
				parent = link
		Form.SPIKES:
			var bone := mat(Color(0.88, 0.84, 0.74), 0.0, 0.0, 0.5)
			_add(_form_parts, forearm_r, capsule(0.085, 0.4), flesh, Vector3(0, -0.12, 0))
			for k in 5:
				var a := k * TAU / 5.0
				_add(_form_parts, forearm_r, box(Vector3(0.035, 0.3, 0.035)), bone, Vector3(cos(a) * 0.08, -0.18, sin(a) * 0.08), Vector3(0.2 * cos(a), 0, 0.2 * sin(a)))
			_add(_form_parts, hand_r, capsule(0.06, 0.35), bone, Vector3(0, -0.15, 0))
		Form.MUSCLE:
			for b in ["upperarm_l", "upperarm_r"]:
				set_bone_scale(b, Vector3(1.6, 1.08, 1.6))
			for b in ["lowerarm_l", "lowerarm_r"]:
				set_bone_scale(b, Vector3(1.3, 1.0, 1.3))
			for arm in [arm_l, arm_r]:
				_add(_form_parts, arm, box(Vector3(0.025, 0.26, 0.025)), glow, Vector3(0.04, -0.15, -0.065), Vector3(0, 0, 0.2))
				_add(_form_parts, arm, sphere(0.13), flesh, Vector3(0, -0.05, 0))


func _apply_defense() -> void:
	if arm_l == null:
		return
	_clear(_defense_parts)
	var rock := mat(Color(0.1, 0.07, 0.07), 0.0, 0.3, 0.55)
	var glow := mat(Color(1, 0.12, 0.06), 2.0)
	match defense:
		Defense.SHIELD:
			var disc := CylinderMesh.new()
			disc.top_radius = 0.72
			disc.bottom_radius = 0.6
			disc.height = 0.09
			disc.radial_segments = 6
			_add(_defense_parts, forearm_l, disc, rock, Vector3(0, -0.24, 0))
			var rim := CylinderMesh.new()
			rim.top_radius = 0.2
			rim.bottom_radius = 0.2
			rim.height = 0.12
			rim.radial_segments = 6
			_add(_defense_parts, forearm_l, rim, glow, Vector3(0, -0.29, 0))
		Defense.ARMOR:
			_add(_defense_parts, body, capsule(0.27, 0.95), rock, Vector3(0, 0.17, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.8))
			for arm in [arm_l, arm_r]:
				_add(_defense_parts, arm, capsule(0.08, 0.36), rock, Vector3(0, -0.14, 0))
				_add(_defense_parts, arm, box(Vector3(0.12, 0.2, 0.12)), rock, Vector3(0, 0.03, 0), Vector3(0, 0, 0.6 * signf(arm.position.x)))
			for fa in [forearm_l, forearm_r]:
				_add(_defense_parts, fa, capsule(0.07, 0.32), rock, Vector3(0, -0.13, 0))
			for leg in [leg_l, leg_r]:
				_add(_defense_parts, leg, capsule(0.11, 0.42), rock, Vector3(0, -0.17, 0))
			for sh in [shin_l, shin_r]:
				_add(_defense_parts, sh, capsule(0.085, 0.34), rock, Vector3(0, -0.14, 0))
			_add(_defense_parts, body, box(Vector3(0.04, 0.4, 0.02)), glow, Vector3(0, 0.25, -0.22))
		Defense.LIGHT:
			# a lean runner's body: glowing sinew lines down every limb and two swept-back fins
			for limb in [arm_l, arm_r, forearm_l, forearm_r, leg_l, leg_r, shin_l, shin_r]:
				_add(_defense_parts, limb, box(Vector3(0.022, 0.3, 0.022)), glow, Vector3(0, -0.14, -0.075))
			for side in [-1.0, 1.0]:
				_add(_defense_parts, body, box(Vector3(0.025, 0.36, 0.14)), rock, Vector3(side * 0.12, 0.3, 0.17),
					Vector3(0.55, 0, side * 0.3))


## Flesh-and-bone wings on the back, built once per outfit.
func _ensure_wings() -> void:
	if not _wing_pivots.is_empty() and is_instance_valid(_wing_pivots[0]):
		return
	_wing_pivots.clear()
	for side in [-1.0, 1.0]:
		var piv := _pivot(body, Vector3(side * 0.07, 0.42, 0.13))
		_sculpt(piv, "wing|%.0f" % side, func(kit): _build_wing(kit, side))
		_wing_pivots.append(piv)


func _build_wing(kit, side: float) -> void:
	var root := Vector3.ZERO
	var elbow := Vector3(side * 0.5, 0.28, 0.06)
	var wrist := Vector3(side * 1.0, 0.36, 0.12)
	var tips := [Vector3(side * 1.85, 0.12, 0.26), Vector3(side * 1.7, -0.36, 0.26), Vector3(side * 1.25, -0.72, 0.22)]
	var base := Vector3(side * 0.12, -0.5, 0.06)
	kit.tube(root, elbow, 0.05, 0.04, K.WHITE, 8)
	kit.tube(elbow, wrist, 0.04, 0.032, K.WHITE, 8)
	kit.ellipsoid(elbow, Vector3.ONE * 0.05, K.WHITE, 1.0, Basis.IDENTITY, 4, 8)
	kit.ellipsoid(wrist, Vector3.ONE * 0.042, K.WHITE, 1.0, Basis.IDENTITY, 4, 8)
	for t in tips:
		kit.tube(wrist, t, 0.025, 0.008, K.WHITE, 6)
	kit.tube(wrist, wrist + Vector3(side * 0.04, 0.2, -0.02), 0.022, 0.002, K.DARK, 5)
	# membrane with a scalloped trailing edge
	var edge := [elbow, wrist, tips[0], tips[1], tips[2], base]
	kit.tri(root, elbow, base, K.FLESH, 0.8)
	kit.tri(elbow, wrist, base, K.FLESH, 0.9)
	for i in range(2, 5):
		var a: Vector3 = edge[i - 1] if i > 2 else wrist
		var b: Vector3 = edge[i]
		var c: Vector3 = edge[i + 1]
		var sag: Vector3 = (b + c) * 0.5 + Vector3(-side * 0.12, 0.08, 0)
		kit.tri(wrist, b, sag, K.FLESH)
		kit.tri(wrist, sag, c, K.FLESH)
		if a != wrist:
			pass
	kit.tri(wrist, tips[2], base, K.FLESH, 0.85)
	# glowing veins across the membrane
	for t in tips:
		kit.tube(wrist.lerp(t, 0.15) + Vector3(0, 0, 0.01), wrist.lerp(t, 0.75) + Vector3(0, -0.1, 0.01), 0.006, 0.003, K.GLOW, 4)


func _apply_legs() -> void:
	if leg_l == null:
		return
	for n in _leg_parts:
		all_meshes.erase(n)
		if is_instance_valid(n):
			n.queue_free()
	_leg_parts.clear()
	for c in _crawler:
		if is_instance_valid(c):
			c.queue_free()
	_crawler.clear()
	for b in ["calf_l", "calf_r", "thigh_l", "thigh_r"]:
		set_bone_scale(b, Vector3.ONE)
	var flesh := mat(FLESH, 0.5, 0.0, 0.35)
	var dark := mat(Color(0.07, 0.02, 0.02), 0.0, 0.3, 0.25)
	var glow := mat(Color(1, 0.12, 0.06), 2.5)
	match legs:
		Legs.RUNNER:
			for sh in [shin_l, shin_r]:
				_add(_leg_parts, sh, capsule(0.05, 0.32), flesh, Vector3(0, -0.13, 0.06), Vector3(0.35, 0, 0))
				_add(_leg_parts, sh, box(Vector3(0.015, 0.22, 0.015)), glow, Vector3(0, -0.12, -0.06), Vector3(-0.1, 0, 0))
				for k in 3:
					_add(_leg_parts, sh, box(Vector3(0.022, 0.025, 0.1)), dark, Vector3((k - 1) * 0.035, -0.325, -0.21), Vector3(0.3, (k - 1) * 0.2, 0))
				_add(_leg_parts, sh, box(Vector3(0.02, 0.1, 0.02)), dark, Vector3(0, -0.28, 0.08), Vector3(-0.7, 0, 0))
		Legs.LEAPER:
			var coil := TorusMesh.new()
			coil.inner_radius = 0.06
			coil.outer_radius = 0.09
			coil.rings = 12
			coil.ring_segments = 6
			for sh in [shin_l, shin_r]:
				for k in 4:
					_add(_leg_parts, sh, coil, flesh if k % 2 == 0 else dark, Vector3(0, -0.04 - k * 0.06, 0), Vector3(0.12, 0, 0))
				_add(_leg_parts, sh, sphere(0.05), glow, Vector3(0, 0.0, -0.05))
			for lg in [leg_l, leg_r]:
				for k in 2:
					_add(_leg_parts, lg, coil, dark, Vector3(0, -0.12 - k * 0.1, 0), Vector3(0, 0, 0), Vector3.ONE * 1.2)
		Legs.CRAWLER:
			for side in [-1.0, 1.0]:
				for j in 2:
					var anchor := _pivot(body, Vector3(side * 0.12, -0.02 - j * 0.08, 0.1))
					anchor.rotation = Vector3(-0.3 - j * 0.55, 0, side * 1.75)
					anchor.set_meta("base_x", anchor.rotation.x)
					_add(_leg_parts, anchor, capsule(0.035, 0.5), flesh, Vector3(0, -0.22, 0))
					var knee := _pivot(anchor, Vector3(0, -0.45, 0))
					knee.rotation = Vector3(0, 0, -side * 1.45)
					_add(_leg_parts, knee, capsule(0.026, 0.85), dark, Vector3(0, -0.4, 0))
					_add(_leg_parts, knee, box(Vector3(0.012, 0.3, 0.012)), glow, Vector3(0, -0.35, -0.026))
					_crawler.append(anchor)
		Legs.CRUSHER:
			var rock := mat(Color(0.1, 0.07, 0.07), 0.0, 0.3, 0.55)
			for b in ["calf_l", "calf_r"]:
				set_bone_scale(b, Vector3(1.35, 1.0, 1.35))
			for sh in [shin_l, shin_r]:
				var hoof := CylinderMesh.new()
				hoof.top_radius = 0.07
				hoof.bottom_radius = 0.1
				hoof.height = 0.12
				hoof.radial_segments = 8
				_add(_leg_parts, sh, hoof, dark, Vector3(0, -0.29, -0.03))
				_add(_leg_parts, sh, box(Vector3(0.1, 0.2, 0.04)), rock, Vector3(0, -0.12, -0.07), Vector3(-0.05, 0, 0))
				var spike := CylinderMesh.new()
				spike.top_radius = 0.0
				spike.bottom_radius = 0.035
				spike.height = 0.16
				_add(_leg_parts, sh, spike, rock, Vector3(0, 0.02, -0.08), Vector3(-1.2, 0, 0))
				_add(_leg_parts, sh, box(Vector3(0.012, 0.16, 0.012)), glow, Vector3(0.03, -0.12, -0.092))
			for b in ["thigh_l", "thigh_r"]:
				set_bone_scale(b, Vector3(1.2, 1.0, 1.2))


## Trick poses from player.gd mapped to the closest animation (the whole-body flips, leans and tilts
## are still done by player.gd on top).
func _pose_anim(pose: Dictionary) -> String:
	if pose == Player.POSE_TUCK or pose == Player.POSE_COIL or pose == Player.POSE_HERO:
		return "Crouch_Idle"   # tucked for flips and rolls, coiled for a charge, crouched on a hero landing
	if pose == Player.POSE_NINJA:
		return "Sprint"
	if pose == Player.POSE_SKYDIVE:
		return "Swim_Idle"     # arms and legs spread
	return "Jump"   # rocket, long jump, vault


var vertical_speed := 0.0   # set by player.gd every frame, for take-off and landing
var _was_air := false
var _air_time := 0.0


## The player's own locomotion (people in the street use person_model.gd's): walk, jog and sprint
## matched to your real speed, a take-off when you leave the ground, a landing when you touch down,
## arms spread when gliding.
func _player_locomotion(delta: float, speed: float, mode: String) -> void:
	swing_timer = maxf(0.0, swing_timer - delta)
	var airborne := mode in ["air", "glide"]
	if airborne:
		_air_time += delta
	if _was_air and not airborne and _air_time > 0.35 and speed < 6.0 and mode != "dead":
		# touched down without running on: a short landing
		_current = ""
		play("Jump_Land", 0.08, 1.3)
		_oneshot_t = 0.3
	if not airborne:
		_air_time = 0.0
	if _was_air != airborne and airborne and vertical_speed > 3.0 and _oneshot_t <= 0.0:
		_current = ""
		play("Jump_Start", 0.06, 1.8)
		_oneshot_t = 0.16
	_was_air = airborne
	if _oneshot_t > 0.0:
		_oneshot_t -= delta
		return
	match mode:
		"idle":
			play("Idle", 0.25)
		"walk", "run":
			if speed < 3.0:
				play("Walk", 0.25, clampf(speed / 1.4, 0.7, 1.6))
			elif speed < 9.5:
				play("Jog_Fwd", 0.2, clampf(speed / 3.6, 0.8, 2.3))
			else:
				play("Sprint", 0.15, clampf(speed / 6.5, 1.0, 3.2))
		"air":
			play("Jump", 0.18)
		"glide":
			play("Swim_Idle", 0.3, 0.6)
		_:
			super.animate(delta, speed, mode)


var hold_anim := ""   # stance for a grown bio weapon (Sword_Idle, Pistol_Idle)


func animate(delta: float, speed: float, mode: String) -> void:
	var armed := hold_anim != "" or (hand_r != null and hand_r.get_children().any(func(c): return c.has_meta("weapon")))
	if creature == 2 and pose_override.is_empty() and _oneshot_t <= 0.0 and mode in ["idle", "walk"]:
		# the Stalker prowls low
		play("Crouch_Fwd" if mode == "walk" else "Crouch_Idle", 0.2, clampf(speed / 1.6, 0.7, 2.0))
		pose_override = {}
	elif not pose_override.is_empty() and _oneshot_t <= 0.0:
		play(_pose_anim(pose_override), 0.12, 1.4 if pose_override == Player.POSE_NINJA else 1.0)
		swing_timer = maxf(0.0, swing_timer - delta)
	elif armed and mode in ["idle", "walk"] and _oneshot_t <= 0.0:
		play(hold_anim if hold_anim != "" else "Pistol_Idle", 0.2)
	else:
		_player_locomotion(delta, speed, mode)
	pose_override = {}
	_t += delta
	var wing_form := defense == Defense.WINGS or creature == 3
	var show := wing_form or (wings_visible and (mode == "glide" or _flap > 0.0))
	if show or not _wing_pivots.is_empty():
		_ensure_wings()
		var open_target := 0.0
		if mode == "glide":
			open_target = 1.0
		elif mode == "air":
			open_target = 0.35
		_wing_open = lerpf(_wing_open, open_target, 1.0 - exp(-7.0 * delta))
		_flap = maxf(0.0, _flap - delta)
		var stroke := sin(_flap / 0.45 * TAU) * 0.9 if _flap > 0.0 else sin(_t * 2.2) * 0.05 * _wing_open
		for i in _wing_pivots.size():
			var wp := _wing_pivots[i]
			if not is_instance_valid(wp):
				continue
			wp.visible = show
			var side := -1.0 if i == 0 else 1.0
			var fold := 1.0 - maxf(_wing_open, 1.0 if _flap > 0.0 else 0.0)
			wp.rotation = Vector3(0.15 * fold, -side * 1.25 * fold, -side * (1.15 * fold - stroke))
	for i in _crawler.size():
		var c := _crawler[i]
		if is_instance_valid(c):
			c.rotation.x = float(c.get_meta("base_x", 0.0)) + sin(_t * 6.0 + i * 1.7) * 0.18 * clampf(speed / 8.0, 0.2, 1.0)
	if form == Form.WHIP and not _whip_links.is_empty():
		for i in _whip_links.size():
			var link := _whip_links[i]
			if is_instance_valid(link):
				link.rotation = Vector3(sin(_t * 3.0 + i * 0.6) * 0.15, 0, cos(_t * 2.3 + i * 0.5) * 0.12)
