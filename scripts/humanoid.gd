extends Node3D
## An animated person with sculpted, code-built body parts (see body_kit.gd).
## Used for civilians, soldiers, scientists, infected, hunters and the player.
## The node's origin is the body center; feet are 0.9 m below at scale 1.
##
## Rig (all Node3D pivots, rotated by animate()):
##   arm_l/arm_r (shoulders) > forearm_l/forearm_r (elbows) > hand_l/hand_r (wrists)
##   leg_l/leg_r (hips) > shin_l/shin_r (knees)
##   head, torso, coat (waist, flaps when running)

const BODY_SHADER := preload("res://shaders/body.gdshader")
const K := preload("res://scripts/body_kit.gd")

const UPPER_ARM := 0.29
const FOREARM := 0.26
const THIGH := 0.36
const SHIN := 0.30
const SHOULDER_Y := 0.465
const HIP_Y := -0.2
const HEAD_Y := 0.75

var torso: MeshInstance3D
var head: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var forearm_l: Node3D
var forearm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var head_gear: MeshInstance3D
var held_item: MeshInstance3D
var coat: Node3D
var all_meshes: Array[MeshInstance3D] = []
var body_material: ShaderMaterial

var cycle := 0.0
var swing_timer := 0.0
var swing_right := true
var swing_style := 0
var _thermal_on := false
## extra elbow / knee bend that other scripts can add for one frame (parkour poses)
var pose_override := {}

static var _mesh_cache := {}
static var _mat_cache := {}
static var _body_mats := {}
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


## The shared material for one outfit's colors.
static func body_mat(o: Dictionary) -> ShaderMaterial:
	var cols := [o["skin"], o["shirt"], o["pants"], o["shoes"], o["hair_color"], o["gear_color"], o["accent"], o["glow"]]
	var key := ""
	for c in cols:
		var cc: Color = c
		key += "%02x%02x%02x" % [int(cc.r * 40), int(cc.g * 40), int(cc.b * 40)]
	key += "c%d i%d" % [int(o["camo"]), int(o["infected"])]
	if _body_mats.has(key):
		return _body_mats[key]
	var m := ShaderMaterial.new()
	m.shader = BODY_SHADER
	var names := ["c_skin", "c_top", "c_bottom", "c_shoes", "c_hair", "c_gear", "c_accent", "c_glow"]
	for i in names.size():
		m.set_shader_parameter(names[i], cols[i])
	m.set_shader_parameter("camo", 1.0 if o["camo"] else 0.0)
	m.set_shader_parameter("infected", 1.0 if o["infected"] else 0.0)
	_body_mats[key] = m
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


## A sculpted part: builds the mesh once per shape and reuses it.
func _sculpt(parent: Node3D, key: String, build: Callable, pos := Vector3.ZERO) -> MeshInstance3D:
	var mesh: ArrayMesh
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key]
	else:
		var kit := K.new()
		build.call(kit)
		mesh = kit.commit()
		_mesh_cache[key] = mesh
	return _part(parent, mesh, body_material, pos)


# ------------------------------------------------------------------ outfit

## Fills in every outfit key with a sensible default so old saves and simple
## outfits still work. Keys: shirt, pants, skin, shoes, gear, gear_color, item, glow,
## bulk, coat, coat_color, body (m/f/h), top (tshirt/long/jacket/hoodie/tank),
## legwear (pants/shorts/skirt), hair (short/long/bun/ponytail/buzz/curly/bald),
## hair_color, beard, vest, vest_color, gloves, boots, glasses, belt, camo,
## infected, veins, glow_style (veins/tech/medals), badge.
static func complete(outfit: Dictionary) -> Dictionary:
	var o := outfit.duplicate()
	var gear: String = o.get("gear", "none")
	o["gear"] = gear
	o["shirt"] = o.get("shirt", Color(0.4, 0.4, 0.45))
	o["pants"] = o.get("pants", Color(0.2, 0.2, 0.25))
	o["skin"] = o.get("skin", Color(0.75, 0.58, 0.45))
	o["shoes"] = o.get("shoes", Color(0.08, 0.07, 0.07))
	o["gear_color"] = o.get("gear_color", Color(0.25, 0.3, 0.2))
	o["bulk"] = float(o.get("bulk", 1.0))
	o["body"] = o.get("body", "m")
	o["top"] = o.get("top", "long" if gear == "helmet" else "tshirt")
	o["legwear"] = o.get("legwear", "pants")
	if not o.has("hair"):
		o["hair"] = "short" if gear in ["hair", "cap", "officer", "beret"] else ("buzz" if gear == "helmet" else "bald")
	if not o.has("hair_color"):
		o["hair_color"] = o["gear_color"] if gear == "hair" else Color(0.1, 0.07, 0.05)
	o["coat"] = bool(o.get("coat", false))
	o["coat_color"] = o.get("coat_color", o["shirt"])
	o["vest"] = bool(o.get("vest", false))
	o["vest_color"] = o.get("vest_color", (o["shirt"] as Color).darkened(0.25))
	var accent: Color = o.get("accent", (o["shirt"] as Color).lightened(0.5))
	if o["coat"]:
		accent = o["coat_color"]
	elif o["vest"]:
		accent = o["vest_color"]
	o["accent"] = accent
	o["glow"] = o.get("glow", Color(1, 0.15, 0.1))
	o["has_glow"] = outfit.has("glow")
	if not o.has("glow_style"):
		if gear == "hood":
			o["glow_style"] = "eyes"
		elif gear == "helmet":
			o["glow_style"] = "tech"
		elif gear in ["cap", "officer"]:
			o["glow_style"] = "medals"
		else:
			o["glow_style"] = "veins"
	for flag in ["beard", "gloves", "boots", "glasses", "belt", "camo", "infected", "veins", "badge"]:
		o[flag] = bool(o.get(flag, false))
	o["item"] = o.get("item", "none")
	return o


## outfit keys: see complete()
func setup(outfit: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	all_meshes.clear()
	head_gear = null
	held_item = null
	coat = null
	var o := complete(outfit)
	body_material = body_mat(o)
	var bulk: float = o["bulk"]
	var sh := _shape(o["body"], bulk)
	var sw: float = sh["sw"]
	var ar: float = sh["ar"]
	var lr: float = sh["lr"]
	var hip: Vector2 = sh["hip"]

	# torso (with neck, belt, vest, coat top, pockets)
	var tkey := "torso|%s|%.2f|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [o["body"], bulk, o["top"], o["legwear"], o["vest"], o["coat"], o["belt"], o["badge"], o["has_glow"], o["glow_style"], o["veins"]]
	torso = _sculpt(self, tkey, func(kit): _build_torso(kit, o, sh))

	# head (face, hair, hats, glasses)
	var hkey := "head|%s|%.2f|%s|%s|%s|%s|%s|%s|%s|%s" % [o["body"], bulk, o["gear"], o["hair"], o["beard"], o["glasses"], o["has_glow"], o["glow_style"], o["infected"], o["veins"]]
	head = _sculpt(self, hkey, func(kit): _build_head(kit, o), Vector3(0, HEAD_Y, 0))
	if o["gear"] != "none" and o["gear"] != "hair":
		head_gear = head

	# arms
	var sleeve := _sleeve_slot(o)
	for side in [-1.0, 1.0]:
		var shoulder := _pivot(self, Vector3(side * (sw + 0.004), SHOULDER_Y, 0))
		var akey := "uarm|%.3f|%s|%s|%s|%.0f|%s" % [ar, o["top"], sleeve, o["veins"], side, o["vest"] and o["glow_style"] == "tech"]
		_sculpt(shoulder, akey, func(kit): _build_upper_arm(kit, o, ar, sleeve, side))
		var elbow := _pivot(shoulder, Vector3(0, -UPPER_ARM, 0))
		var fkey := "farm|%.3f|%s|%s|%s|%.0f" % [ar, o["top"], sleeve, o["veins"], side]
		_sculpt(elbow, fkey, func(kit): _build_forearm(kit, o, ar, sleeve, side))
		var wrist := _pivot(elbow, Vector3(0, -FOREARM, 0))
		var hkey2 := "hand|%.2f|%s|%.0f|%s" % [bulk, o["gloves"], side, o["infected"]]
		_sculpt(wrist, hkey2, func(kit): _build_hand(kit, o, bulk, side))
		if side < 0.0:
			arm_l = shoulder
			forearm_l = elbow
			hand_l = wrist
		else:
			arm_r = shoulder
			forearm_r = elbow
			hand_r = wrist

	# legs
	for side in [-1.0, 1.0]:
		var hip_p := _pivot(self, Vector3(side * hip.x * 0.5, HIP_Y, 0))
		var lkey := "thigh|%.3f|%s" % [lr, o["legwear"]]
		_sculpt(hip_p, lkey, func(kit): _build_thigh(kit, o, lr))
		var knee := _pivot(hip_p, Vector3(0, -THIGH, 0))
		var skey := "shin|%.3f|%s|%s|%s|%.2f" % [lr, o["legwear"], o["boots"], o["vest"], bulk]
		_sculpt(knee, skey, func(kit): _build_shin(kit, o, lr, bulk))
		if side < 0.0:
			leg_l = hip_p
			shin_l = knee
		else:
			leg_r = hip_p
			shin_r = knee

	# long coat tails that flap behind when running
	if o["coat"]:
		coat = _pivot(self, Vector3(0, -0.03, 0))
		var ckey := "coat|%s|%.2f" % [o["body"], bulk]
		_sculpt(coat, ckey, func(kit): _build_coat_skirt(kit, sh))

	# held weapons
	match o["item"]:
		"rifle":
			held_item = _sculpt(hand_r, "rifle", func(kit): _build_rifle(kit), Vector3(0, -0.05, 0))
		"launcher":
			held_item = _sculpt(hand_r, "launcher", func(kit): _build_launcher(kit), Vector3(0, -0.04, 0))
	# relaxed default pose
	forearm_l.rotation.x = 0.15
	forearm_r.rotation.x = 0.15


static func _shape(body: String, bulk: float) -> Dictionary:
	var d: Dictionary
	match body:
		"f":
			d = {"sw": 0.165, "chest": Vector2(0.165, 0.118), "waist": Vector2(0.125, 0.092), "hip": Vector2(0.183, 0.12),
				"ar": 0.042, "lr": 0.084, "belly": 0.0, "bust": 0.03}
		"h":
			d = {"sw": 0.2, "chest": Vector2(0.205, 0.15), "waist": Vector2(0.2, 0.165), "hip": Vector2(0.195, 0.14),
				"ar": 0.057, "lr": 0.094, "belly": 0.045, "bust": 0.0}
		_:
			d = {"sw": 0.188, "chest": Vector2(0.185, 0.125), "waist": Vector2(0.148, 0.105), "hip": Vector2(0.163, 0.112),
				"ar": 0.05, "lr": 0.082, "belly": 0.0, "bust": 0.0}
	d["sw"] = d["sw"] * bulk
	for k in ["chest", "waist", "hip"]:
		d[k] = d[k] * bulk
	d["ar"] = d["ar"] * bulk
	d["lr"] = d["lr"] * lerpf(1.0, bulk, 0.7)
	d["belly"] = d["belly"] * bulk
	return d


static func _sleeve_slot(o: Dictionary) -> int:
	if o["coat"]:
		return K.ACCENT
	if o["top"] == "tank":
		return K.SKIN
	return K.TOP


# ------------------------------------------------------------------ builders

func _build_torso(kit, o: Dictionary, sh: Dictionary) -> void:
	var R := K.ring
	var hip: Vector2 = sh["hip"]
	var waist: Vector2 = sh["waist"]
	var chest: Vector2 = sh["chest"]
	var sw: float = sh["sw"]
	var belly: float = sh["belly"]
	var bust: float = sh["bust"]
	var bulk: float = o["bulk"]
	var top_slot := K.TOP
	var low := K.BOTTOM
	var untucked: bool = o["top"] in ["tshirt", "hoodie", "jacket", "tank"] and not o["belt"]
	var rings: Array = [
		R.call(-0.235, hip.x * 0.42, hip.y * 0.6, low, 0.0, 0.8),
		R.call(-0.18, hip.x * 0.84, hip.y * 0.9, low, 0.0, 0.9),
		R.call(-0.13, hip.x * 0.96, hip.y * 0.98, low, 0.0, 0.9),
		R.call(-0.07, hip.x, hip.y * 1.02, low),
	]
	if untucked:
		rings.append(R.call(-0.075, hip.x * 1.06, hip.y * 1.1, top_slot, 0.0, 0.8))
		rings.append(R.call(0.0, lerpf(hip.x, waist.x, 0.4) * 1.05, lerpf(hip.y, waist.y, 0.4) * 1.08, top_slot, -belly * 0.6))
	else:
		rings.append(R.call(-0.015, hip.x * 0.99, hip.y * 1.01, K.DARK if o["belt"] else low))
		rings.append(R.call(0.025, lerpf(hip.x, waist.x, 0.4), lerpf(hip.y, waist.y, 0.4), top_slot, -belly * 0.6))
	rings.append_array([
		R.call(0.13, waist.x, waist.y, top_slot, -belly),
		R.call(0.25, lerpf(waist.x, chest.x, 0.6), lerpf(waist.y, chest.y, 0.6) + bust * 0.4, top_slot, -0.008 - belly * 0.5 - bust * 0.3),
		R.call(0.35, chest.x, chest.y + bust, top_slot, -0.015 - bust * 0.6),
		R.call(0.43, maxf(chest.x, sw * 0.96), chest.y * 0.96, top_slot, -0.01),
		R.call(0.49, sw * 0.95, chest.y * 0.8, top_slot, 0.005),
		R.call(0.535, 0.16 * bulk, 0.095 * bulk, top_slot, 0.01),
		R.call(0.575, 0.105, 0.078, top_slot, 0.012),
		R.call(0.6, 0.066, 0.062, top_slot, 0.012, 0.85),
	])
	kit.loft(rings, Transform3D.IDENTITY, 16)
	# neck
	kit.loft([R.call(0.53, 0.058, 0.056, K.SKIN, 0.012, 0.8), R.call(0.62, 0.054, 0.054, K.SKIN, 0.01), R.call(0.69, 0.05, 0.052, K.SKIN, 0.0, 0.75)], Transform3D.IDENTITY, 10, false)
	var front_z := -(chest.y + bust) - 0.015 - bust * 0.6
	if o["legwear"] == "skirt":
		kit.loft([R.call(-0.02, hip.x * 1.03, hip.y * 1.08, K.BOTTOM), R.call(-0.2, hip.x * 1.12, hip.y * 1.2, K.BOTTOM),
			R.call(-0.42, hip.x * 1.24, hip.y * 1.32, K.BOTTOM, 0.0, 0.8)], Transform3D.IDENTITY, 16, false, TAU, 0.0, true)
	match o["top"]:
		"hoodie":
			kit.ellipsoid(Vector3(0, 0.555, chest.y * 0.55), Vector3(0.12, 0.055, 0.07) * bulk, K.TOP, 0.85)
			kit.ellipsoid(Vector3(0, 0.06, -waist.y - belly - 0.004), Vector3(0.1, 0.048, 0.014) * bulk, K.TOP, 0.75)
			for s in [-1.0, 1.0]:
				kit.tube(Vector3(s * 0.035, 0.52, front_z + 0.03), Vector3(s * 0.04, 0.38, front_z - 0.005), 0.0045, 0.004, K.WHITE, 5)
		"jacket":
			# open front showing the shirt underneath, collar
			kit.box(Vector3(0, 0.27, front_z * 0.99), Vector3(0.06, 0.38, 0.01), K.ACCENT, Basis.IDENTITY, 0.9)
			for s in [-1.0, 1.0]:
				kit.box(Vector3(s * 0.055, 0.5, front_z * 0.75), Vector3(0.05, 0.12, 0.012), K.TOP, Basis.from_euler(Vector3(0.5, 0, s * 0.35)), 0.9)
		"long":
			kit.loft([R.call(0.545, 0.075, 0.068, K.TOP, 0.012), R.call(0.6, 0.066, 0.062, K.TOP, 0.012)], Transform3D.IDENTITY, 12, false)
	if o["belt"]:
		kit.box(Vector3(0, 0.005, -hip.y * 1.02 - 0.004), Vector3(0.045, 0.035, 0.012), K.METAL)
	if o["vest"]:
		var vr: Array = [
			R.call(-0.03, hip.x * 1.08, hip.y * 1.2, K.ACCENT, 0.0, 0.7),
			R.call(0.12, waist.x * 1.14, waist.y * 1.28, K.ACCENT, -belly),
			R.call(0.25, lerpf(waist.x, chest.x, 0.6) * 1.12, lerpf(waist.y, chest.y, 0.6) * 1.28, K.ACCENT, -0.008),
			R.call(0.37, chest.x * 1.1, chest.y * 1.3, K.ACCENT, -0.015),
			R.call(0.46, sw * 0.9, chest.y * 1.08, K.ACCENT, -0.005),
			R.call(0.52, 0.11 * bulk, 0.085 * bulk, K.ACCENT, 0.008, 0.8),
		]
		kit.loft(vr, Transform3D.IDENTITY, 14, true)
		var vz := -waist.y * 1.28 - 0.018
		for i in 3:
			kit.box(Vector3((i - 1) * 0.07 * bulk, 0.08, vz), Vector3(0.058, 0.075, 0.035) * bulk, K.ACCENT, Basis.IDENTITY, 0.8)
		kit.box(Vector3(-0.07 * bulk, 0.36, -chest.y * 1.3 - 0.01), Vector3(0.045, 0.07, 0.025), K.DARK, Basis.from_euler(Vector3(0, 0, 0.1)))
	if o["coat"]:
		var cr: Array = [
			R.call(-0.04, hip.x * 1.1, hip.y * 1.2, K.ACCENT),
			R.call(0.13, waist.x * 1.07, waist.y * 1.12, K.ACCENT, -belly),
			R.call(0.25, lerpf(waist.x, chest.x, 0.6) * 1.06, (lerpf(waist.y, chest.y, 0.6) + bust * 0.4) * 1.1, K.ACCENT, -0.008),
			R.call(0.35, chest.x * 1.06, (chest.y + bust) * 1.1, K.ACCENT, -0.015 - bust * 0.6),
			R.call(0.43, maxf(chest.x, sw * 0.96) * 1.05, chest.y * 1.06, K.ACCENT, -0.01),
			R.call(0.5, sw * 0.9, chest.y * 0.86, K.ACCENT, 0.005),
			R.call(0.55, 0.11 * bulk, 0.088 * bulk, K.ACCENT, 0.01),
			R.call(0.6, 0.085, 0.08, K.ACCENT, 0.015, 0.85),
		]
		kit.loft(cr, Transform3D.IDENTITY, 16, false, TAU - 0.5, 0.25, true)
	if o["badge"]:
		kit.box(Vector3(0.08, 0.33, front_z - 0.02), Vector3(0.04, 0.05, 0.006), K.WHITE)
	if o["has_glow"] or o["veins"]:
		match o["glow_style"]:
			"medals":
				for i in 3:
					kit.ellipsoid(Vector3(-0.06 - i * 0.025, 0.36, front_z - 0.004), Vector3(0.009, 0.013, 0.005), K.GLOW)
			"tech":
				kit.box(Vector3(0.0, 0.3, -chest.y * (1.3 if o["vest"] else 1.0) - 0.022), Vector3(0.12, 0.012, 0.006), K.GLOW)
				kit.box(Vector3(0.08, 0.2, -chest.y * (1.3 if o["vest"] else 1.0) - 0.02), Vector3(0.012, 0.12, 0.006), K.GLOW)
			_:
				_veins_on(kit, Vector3(0, 0.25, front_z + 0.004), 0.1, 4, 101)


## glowing veins as thin lines over a surface patch
func _veins_on(kit, center: Vector3, size: float, count: int, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in count:
		var p := center + Vector3(rng.randf_range(-size, size), rng.randf_range(-size, size) * 1.2, 0)
		var ang := rng.randf_range(-0.9, 0.9)
		var l := rng.randf_range(0.025, 0.05)
		kit.ellipsoid(p, Vector3(0.0032, l, 0.0025), K.GLOW, 1.0, Basis.from_euler(Vector3(0, 0, ang)), 3, 5)
		# a short branch
		var off := Basis.from_euler(Vector3(0, 0, ang)) * Vector3(0, l * 0.6, 0)
		kit.ellipsoid(p + off + Vector3(0.006, 0.006, 0), Vector3(0.0025, l * 0.5, 0.002), K.GLOW, 1.0, Basis.from_euler(Vector3(0, 0, ang + 0.7)), 3, 5)


func _build_head(kit, o: Dictionary) -> void:
	var R := K.ring
	var f := 0.94 if o["body"] == "f" else 1.0
	var rings: Array = [
		R.call(-0.125, 0.024 * f, 0.02, K.SKIN, -0.066),
		R.call(-0.112, 0.045 * f, 0.038, K.SKIN, -0.056),
		R.call(-0.08, 0.066 * f, 0.07, K.SKIN, -0.026),
		R.call(-0.04, 0.078 * f, 0.092, K.SKIN, -0.008),
		R.call(0.0, 0.085, 0.1, K.SKIN, 0.0),
		R.call(0.04, 0.088, 0.105, K.SKIN, 0.005),
		R.call(0.08, 0.082, 0.1, K.SKIN, 0.01),
		R.call(0.11, 0.065, 0.08, K.SKIN, 0.012),
		R.call(0.13, 0.036, 0.046, K.SKIN, 0.012),
		R.call(0.141, 0.0, 0.0, K.SKIN, 0.012),
	]
	kit.loft(rings, Transform3D.IDENTITY, 16, false)
	var hooded: bool = o["gear"] == "hood"
	var glow_eyes: bool = (hooded and o["has_glow"]) or o["infected"]
	for s in [-1.0, 1.0]:
		if glow_eyes:
			kit.ellipsoid(Vector3(s * 0.034, 0.018, -0.091), Vector3(0.016, 0.008, 0.011), K.GLOW, 1.0, Basis.IDENTITY, 4, 8)
		else:
			kit.ellipsoid(Vector3(s * 0.034, 0.018, -0.09), Vector3(0.016, 0.0105, 0.012), K.WHITE, 1.0, Basis.IDENTITY, 4, 8)
			kit.ellipsoid(Vector3(s * 0.034, 0.018, -0.1005), Vector3(0.0078, 0.0078, 0.003), K.DARK, 1.0, Basis.IDENTITY, 3, 8)
		# brows, ears
		kit.ellipsoid(Vector3(s * 0.035, 0.039, -0.096), Vector3(0.02, 0.0048, 0.007), K.HAIR, 1.0, Basis.from_euler(Vector3(0, 0, -s * 0.12)), 3, 6)
		kit.ellipsoid(Vector3(s * 0.088, 0.005, 0.012), Vector3(0.012, 0.029, 0.019), K.SKIN, 0.85, Basis.IDENTITY, 4, 8)
	# nose and lips
	kit.loft([R.call(0.03, 0.007, 0.006, K.SKIN, -0.098), R.call(0.0, 0.0105, 0.01, K.SKIN, -0.106),
		R.call(-0.025, 0.0155, 0.013, K.SKIN, -0.108), R.call(-0.037, 0.011, 0.008, K.SKIN, -0.103, 0.8)], Transform3D.IDENTITY, 8)
	if o["infected"]:
		kit.ellipsoid(Vector3(0, -0.062, -0.092), Vector3(0.024, 0.012, 0.01), K.DARK, 1.0, Basis.IDENTITY, 4, 8)
	else:
		kit.ellipsoid(Vector3(0, -0.061, -0.091), Vector3(0.022 * f, 0.0075, 0.009), K.LIPS, 1.0, Basis.IDENTITY, 4, 8)
	if o["infected"] and o["has_glow"]:
		for s in [-1.0, 1.0]:
			kit.ellipsoid(Vector3(s * 0.07, -0.03, -0.065), Vector3(0.004, 0.03, 0.004), K.GLOW, 1.0, Basis.from_euler(Vector3(0, s * 0.8, s * 0.4)), 3, 5)

	# hair
	var hc := Vector3(0, 0.02, 0.012)
	var hr := Vector3(0.098, 0.132, 0.12)
	var hair: String = o["hair"]
	var covered: bool = o["gear"] in ["helmet", "hood"]
	if not covered:
		match hair:
			"short", "curly", "bun", "ponytail":
				kit.shell(hc, hr, K.HAIR, 0.9, 1.9)
			"long":
				kit.shell(hc, hr, K.HAIR, 0.9, 2.3)
				kit.loft([R.call(-0.02, 0.088, 0.05, K.HAIR, 0.07), R.call(-0.12, 0.095, 0.04, K.HAIR, 0.085), R.call(-0.22, 0.08, 0.025, K.HAIR, 0.09, 0.8)], Transform3D.IDENTITY, 12)
			"buzz":
				kit.shell(hc, Vector3(0.094, 0.128, 0.116), K.HAIR, 1.0, 1.85, 1.0, false)
		match hair:
			"curly":
				var rng := RandomNumberGenerator.new()
				rng.seed = 7
				for i in 12:
					var th := rng.randf() * TAU
					var ph := rng.randf_range(0.1, 1.3)
					var d := Vector3(sin(ph) * sin(th), cos(ph), -sin(ph) * cos(th) * 0.8 + 0.15)
					kit.ellipsoid(hc + Vector3(d.x * hr.x, d.y * hr.y, d.z * hr.z), Vector3.ONE * 0.03, K.HAIR, 1.0, Basis.IDENTITY, 4, 6)
			"bun":
				kit.ellipsoid(Vector3(0, 0.1, 0.11), Vector3(0.045, 0.042, 0.045), K.HAIR, 1.0, Basis.IDENTITY, 5, 10)
			"ponytail":
				kit.tube(Vector3(0, 0.07, 0.12), Vector3(0, -0.13, 0.15), 0.03, 0.012, K.HAIR, 8)
	if o["beard"]:
		var br: Array = []
		for r in rings.slice(0, 5):
			br.append(R.call(r[0].y, r[1] * 1.08, r[2] * 1.07, K.HAIR, r[0].z))
		kit.loft(br, Transform3D.IDENTITY, 14, false, 3.4, -1.7)
		kit.ellipsoid(Vector3(0, -0.047, -0.098), Vector3(0.025, 0.006, 0.008), K.HAIR, 1.0, Basis.IDENTITY, 3, 8)
	if o["glasses"]:
		for s in [-1.0, 1.0]:
			kit.torus(Vector3(s * 0.034, 0.018, -0.107), 0.0165, 0.0022, K.DARK)
			kit.box(Vector3(s * 0.08, 0.02, -0.055), Vector3(0.003, 0.004, 0.1), K.DARK)
		kit.box(Vector3(0, 0.022, -0.108), Vector3(0.02, 0.003, 0.003), K.DARK)

	# hats
	match o["gear"]:
		"helmet":
			kit.shell(Vector3(0, 0.035, 0.012), Vector3(0.113, 0.136, 0.13), K.GEAR, 0.95, 1.72)
			for s in [-1.0, 1.0]:
				kit.tube(Vector3(s * 0.098, -0.005, 0.0), Vector3(s * 0.06, -0.11, -0.035), 0.005, 0.005, K.DARK, 5)
			if o["has_glow"] and o["glow_style"] == "tech":
				kit.ellipsoid(Vector3(0, 0.02, -0.098), Vector3(0.082, 0.02, 0.026), K.GLOW, 1.0, Basis.IDENTITY, 4, 12)
			else:
				for s in [-1.0, 1.0]:
					kit.ellipsoid(Vector3(s * 0.036, 0.105, -0.108), Vector3(0.024, 0.016, 0.013), K.DARK, 1.0, Basis.from_euler(Vector3(-0.6, 0, 0)), 4, 8)
		"cap":
			kit.shell(Vector3(0, 0.025, 0.012), Vector3(0.1, 0.13, 0.118), K.GEAR, 0.85, 1.35)
			kit.ellipsoid(Vector3(0, 0.075, -0.13), Vector3(0.075, 0.008, 0.06), K.GEAR, 0.9, Basis.from_euler(Vector3(-0.15, 0, 0)), 3, 12)
		"officer":
			kit.loft([R.call(0.05, 0.102, 0.118, K.DARK, 0.012), R.call(0.075, 0.106, 0.122, K.GEAR, 0.01),
				R.call(0.12, 0.118, 0.136, K.GEAR, 0.0), R.call(0.135, 0.11, 0.128, K.GEAR, 0.0)], Transform3D.IDENTITY, 16)
			kit.ellipsoid(Vector3(0, 0.052, -0.125), Vector3(0.072, 0.007, 0.05), K.DARK, 1.0, Basis.from_euler(Vector3(-0.2, 0, 0)), 3, 12)
			kit.ellipsoid(Vector3(0, 0.1, -0.135), Vector3(0.013, 0.015, 0.006), K.GLOW, 1.0, Basis.IDENTITY, 3, 8)
		"beret":
			kit.ellipsoid(Vector3(0.02, 0.1, 0.0), Vector3(0.11, 0.035, 0.12), K.GEAR, 0.9, Basis.from_euler(Vector3(0, 0, -0.25)), 5, 14)
		"hood":
			kit.shell(Vector3(0, 0.02, 0.03), Vector3(0.132, 0.168, 0.158), K.GEAR, 1.5, 2.75, 0.9)
			# peak over the forehead
			kit.ellipsoid(Vector3(0, 0.125, -0.1), Vector3(0.085, 0.03, 0.04), K.GEAR, 0.85, Basis.from_euler(Vector3(0.5, 0, 0)), 4, 10)
			kit.loft([R.call(-0.12, 0.11, 0.115, K.GEAR, 0.035), R.call(-0.18, 0.145, 0.13, K.GEAR, 0.03),
				R.call(-0.23, 0.17, 0.12, K.GEAR, 0.02, 0.85)], Transform3D.IDENTITY, 16, false, TAU - 1.3, 0.65, true)


func _build_upper_arm(kit, o: Dictionary, ar: float, sleeve: int, side: float) -> void:
	var R := K.ring
	kit.ellipsoid(Vector3(-side * 0.006, -0.02, 0), Vector3(ar * 1.22, ar * 1.3, ar * 1.2), sleeve, 1.0, Basis.IDENTITY, 6, 10)
	var rings: Array = [R.call(-0.02, ar * 1.16, ar * 1.16, sleeve)]
	if o["top"] == "tshirt" and sleeve == K.TOP:
		rings.append_array([R.call(-0.13, ar * 1.14, ar * 1.14, sleeve, -0.003), R.call(-0.14, ar * 1.18, ar * 1.18, sleeve, -0.003, 0.8),
			R.call(-0.142, ar * 1.06, ar * 1.06, K.SKIN, -0.003, 0.7)])
		sleeve = K.SKIN
	else:
		rings.append(R.call(-0.1, ar * 1.12, ar * 1.12, sleeve, -0.004))
	rings.append_array([R.call(-0.2, ar * 1.05, ar * 1.02, sleeve), R.call(-0.29, ar * 0.88, ar * 0.86, sleeve)])
	kit.loft(rings, Transform3D.IDENTITY, 10)
	if o["veins"]:
		_veins_on(kit, Vector3(side * ar * 0.3, -0.15, -ar * 1.08), 0.03, 2, 11 + int(side))
	if o["vest"] and o["glow_style"] == "tech":
		kit.ellipsoid(Vector3(side * 0.01, -0.01, 0), Vector3(ar * 1.7, ar * 1.2, ar * 1.6), K.ACCENT, 0.85, Basis.from_euler(Vector3(0, 0, side * 0.3)), 5, 10)


func _build_forearm(kit, o: Dictionary, ar: float, sleeve: int, side: float) -> void:
	var R := K.ring
	var long_sleeve: bool = sleeve != K.SKIN and o["top"] != "tshirt"
	var s := sleeve if long_sleeve else K.SKIN
	kit.ellipsoid(Vector3(0, 0.005, 0), Vector3.ONE * ar * 0.84, s, 1.0, Basis.IDENTITY, 5, 10)
	var rings: Array = [R.call(0.01, ar * 0.86, ar * 0.86, s), R.call(-0.06, ar * 1.0, ar * 0.97, s, 0.004),
		R.call(-0.16, ar * 0.82, ar * 0.78, s)]
	if long_sleeve:
		rings.append_array([R.call(-0.215, ar * 0.76, ar * 0.72, s), R.call(-0.22, ar * 0.8, ar * 0.76, s, 0.0, 0.8),
			R.call(-0.222, ar * 0.62, ar * 0.6, K.SKIN, 0.0, 0.7)])
	rings.append(R.call(-0.26, ar * 0.6, ar * 0.56, K.SKIN))
	kit.loft(rings, Transform3D.IDENTITY, 10)
	if o["veins"]:
		_veins_on(kit, Vector3(side * ar * 0.2, -0.12, -ar * 0.92), 0.03, 2, 21 + int(side))


func _build_hand(kit, o: Dictionary, bulk: float, side: float) -> void:
	var R := K.ring
	var slot := K.DARK if o["gloves"] else K.SKIN
	var b := bulk
	kit.loft([R.call(0.0, 0.016 * b, 0.025 * b, slot), R.call(-0.03, 0.018 * b, 0.035 * b, slot),
		R.call(-0.07, 0.017 * b, 0.039 * b, slot), R.call(-0.086, 0.014 * b, 0.035 * b, slot)], Transform3D.IDENTITY, 10)
	var lens := [0.058, 0.066, 0.062, 0.05]
	for i in 4:
		var z := (-0.027 + i * 0.018) * b
		var l: float = lens[i] * b
		var a := Vector3(0, -0.078 * b, z)
		var mid := a + Vector3(-side * 0.006, -l * 0.55, -0.002)
		var tip := a + Vector3(-side * 0.02, -l, -0.004)
		kit.tube(a, mid, 0.0085 * b, 0.0078 * b, slot, 6, 1.0, false)
		kit.tube(mid, tip, 0.0078 * b, 0.0068 * b, slot, 6)
		if o["infected"] and not o["gloves"]:
			kit.tube(tip, tip + Vector3(-side * 0.008, -0.02, 0) * b, 0.005, 0.001, K.DARK, 4)
	kit.tube(Vector3(-side * 0.008, -0.022, -0.03) * b, Vector3(-side * 0.022, -0.07, -0.045) * b, 0.0095 * b, 0.0075 * b, slot, 6)


func _build_thigh(kit, o: Dictionary, lr: float) -> void:
	var R := K.ring
	var slot := K.BOTTOM
	match o["legwear"]:
		"skirt":
			slot = K.SKIN
	var rings: Array = [R.call(0.05, lr * 1.0, lr * 1.0, slot), R.call(-0.04, lr * 1.08, lr * 1.05, slot),
		R.call(-0.16, lr * 1.02, lr * 1.0, slot, -0.008)]
	if o["legwear"] == "shorts":
		rings.append_array([R.call(-0.2, lr * 0.98, lr * 0.96, slot, -0.008), R.call(-0.205, lr * 1.04, lr * 1.02, slot, -0.008, 0.8),
			R.call(-0.207, lr * 0.94, lr * 0.92, K.SKIN, -0.008, 0.7)])
		slot = K.SKIN
	rings.append_array([R.call(-0.28, lr * 0.85, lr * 0.84, slot, -0.004), R.call(-0.36, lr * 0.74, lr * 0.74, slot)])
	kit.loft(rings, Transform3D.IDENTITY, 12)
	if o["legwear"] == "skirt":
		pass


func _build_shin(kit, o: Dictionary, lr: float, bulk: float) -> void:
	var R := K.ring
	var slot := K.SKIN if o["legwear"] in ["shorts", "skirt"] else K.BOTTOM
	kit.ellipsoid(Vector3(0, 0.0, -0.004), Vector3(lr * 0.72, lr * 0.8, lr * 0.74), slot, 1.0, Basis.IDENTITY, 5, 10)
	var rings: Array = [R.call(0.02, lr * 0.74, lr * 0.74, slot), R.call(-0.03, lr * 0.8, lr * 0.8, slot, 0.002),
		R.call(-0.1, lr * 0.82, lr * 0.84, slot, 0.012)]
	if o["boots"]:
		rings.append_array([R.call(-0.17, lr * 0.66, lr * 0.68, slot, 0.006), R.call(-0.172, lr * 0.74, lr * 0.76, K.SHOES, 0.006, 0.8),
			R.call(-0.24, lr * 0.6, lr * 0.62, K.SHOES), R.call(-0.29, lr * 0.56, lr * 0.58, K.SHOES)])
	else:
		rings.append_array([R.call(-0.2, lr * 0.6, lr * 0.62, slot, 0.004), R.call(-0.27, lr * 0.48, lr * 0.5, slot)])
	kit.loft(rings, Transform3D.IDENTITY, 12)
	if o["vest"]:
		kit.ellipsoid(Vector3(0, -0.01, -lr * 0.78), Vector3(0.045, 0.055, 0.026), K.GEAR, 0.9, Basis.IDENTITY, 4, 8)
	# shoe: lofted from heel to toe, then turned so it points forward
	var b := lerpf(1.0, bulk, 0.6)
	var shoe: Array = [
		R.call(-0.055 * b, 0.034 * b, 0.028, K.SHOES, 0.002),
		R.call(-0.035 * b, 0.044 * b, 0.044, K.SHOES, 0.016),
		R.call(0.03 * b, 0.047 * b, 0.038, K.SHOES, 0.004),
		R.call(0.1 * b, 0.045 * b, 0.028, K.SHOES, -0.008),
		R.call(0.145 * b, 0.035 * b, 0.02, K.SHOES, -0.012),
		R.call(0.162 * b, 0.014 * b, 0.011, K.SHOES, -0.014),
	]
	var xf := Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), Vector3(0, -0.305, 0.0))
	kit.loft(shoe, xf, 12)
	kit.ellipsoid(Vector3(0, -0.333, -0.05 * b), Vector3(0.046 * b, 0.009, 0.108 * b), K.DARK, 1.0, Basis.IDENTITY, 3, 12)


func _build_coat_skirt(kit, sh: Dictionary) -> void:
	var R := K.ring
	var hip: Vector2 = sh["hip"]
	kit.loft([R.call(0.0, hip.x * 1.1, hip.y * 1.22, K.ACCENT), R.call(-0.25, hip.x * 1.26, hip.y * 1.36, K.ACCENT, 0.01),
		R.call(-0.57, hip.x * 1.42, hip.y * 1.5, K.ACCENT, 0.02, 0.85)], Transform3D.IDENTITY, 16, false, TAU - 0.6, 0.3, true)


## rifle in the right hand: barrel along -Y (points forward when the arm is raised)
func _build_rifle(kit) -> void:
	kit.box(Vector3(0, -0.12, -0.035), Vector3(0.045, 0.42, 0.085), K.DARK)              # receiver
	kit.box(Vector3(0, 0.17, -0.02), Vector3(0.04, 0.2, 0.09), K.DARK, Basis.from_euler(Vector3(-0.08, 0, 0)))  # stock
	kit.box(Vector3(0, 0.0, 0.03), Vector3(0.035, 0.05, 0.09), K.DARK, Basis.from_euler(Vector3(0.3, 0, 0)))   # grip
	kit.box(Vector3(0, -0.13, 0.05), Vector3(0.032, 0.06, 0.13), K.METAL, Basis.from_euler(Vector3(-0.25, 0, 0)))  # magazine
	kit.box(Vector3(0, -0.4, -0.035), Vector3(0.05, 0.16, 0.06), K.METAL)                # handguard
	kit.tube(Vector3(0, -0.47, -0.04), Vector3(0, -0.68, -0.04), 0.011, 0.011, K.METAL, 6)
	kit.box(Vector3(0, -0.13, -0.098), Vector3(0.03, 0.14, 0.035), K.METAL)              # scope
	kit.tube(Vector3(0, -0.06, -0.1), Vector3(0, -0.2, -0.1), 0.017, 0.017, K.DARK, 8)


func _build_launcher(kit) -> void:
	kit.tube(Vector3(0, 0.45, -0.07), Vector3(0, -0.65, -0.07), 0.065, 0.065, K.GEAR, 12)
	kit.tube(Vector3(0, -0.65, -0.07), Vector3(0, -0.7, -0.07), 0.065, 0.08, K.DARK, 12)
	kit.box(Vector3(0, -0.02, 0.02), Vector3(0.035, 0.05, 0.1), K.DARK, Basis.from_euler(Vector3(0.3, 0, 0)))
	kit.box(Vector3(0.0, -0.25, -0.15), Vector3(0.03, 0.1, 0.04), K.DARK)
	kit.ellipsoid(Vector3(0, -0.72, -0.07), Vector3(0.045, 0.05, 0.045), K.METAL, 1.0, Basis.IDENTITY, 4, 8)


# ------------------------------------------------------------------ animation

func swing(right := true, style := 0, duration := 0.22) -> void:
	swing_timer = duration
	swing_right = right
	swing_style = style
	set_meta("swing_duration", duration)


## mode: idle, walk, run, aim, flail, dead, grabbed, air, glide, crouch, cower
func animate(delta: float, speed: float, mode: String) -> void:
	if arm_l == null:
		return
	var k := 1.0 - exp(-14.0 * delta)
	var la := Vector3.ZERO
	var ra := Vector3.ZERO
	var ll := Vector3.ZERO
	var rl := Vector3.ZERO
	var lf := 0.15     # elbows (positive bends the forearm forward)
	var rf := 0.15
	var lk := 0.0      # knees (negative bends the shin back)
	var rk := 0.0
	match mode:
		"walk", "run":
			cycle += delta * clampf(speed, 2.0, 30.0) * (0.9 if mode == "run" else 1.4)
			var amp := clampf(speed / 8.0, 0.35, 1.0) * (1.1 if mode == "run" else 0.6)
			var s := sin(cycle)
			var c := cos(cycle)
			ll = Vector3(s * amp, 0, 0)
			rl = Vector3(-s * amp, 0, 0)
			la = Vector3(-s * amp * 0.9, 0, -0.08)
			ra = Vector3(s * amp * 0.9, 0, 0.08)
			# knees fold while the leg swings forward, elbows bend more when running
			lk = -maxf(0.0, c) * amp * (1.6 if mode == "run" else 0.9) - 0.08
			rk = -maxf(0.0, -c) * amp * (1.6 if mode == "run" else 0.9) - 0.08
			lf = 0.35 + (1.1 if mode == "run" else 0.2) + maxf(0.0, s) * 0.3
			rf = 0.35 + (1.1 if mode == "run" else 0.2) + maxf(0.0, -s) * 0.3
			if mode == "run":
				la.x -= 0.3
				ra.x -= 0.3
		"aim":
			ra = Vector3(1.45, 0, 0.0)
			la = Vector3(1.3, 0, 0.45)
			rf = 0.1
			lf = 0.45
			cycle += delta * speed * 1.4
			var s2 := sin(cycle) * clampf(speed / 6.0, 0.0, 0.7)
			ll = Vector3(s2, 0, 0)
			rl = Vector3(-s2, 0, 0)
			lk = -maxf(0.0, cos(cycle)) * absf(s2) * 1.2
			rk = -maxf(0.0, -cos(cycle)) * absf(s2) * 1.2
		"flail":
			cycle += delta * 18.0
			la = Vector3(sin(cycle) * 1.2, 0, -1.2)
			ra = Vector3(cos(cycle) * 1.2, 0, 1.2)
			ll = Vector3(sin(cycle * 1.3) * 0.8, 0, -0.3)
			rl = Vector3(cos(cycle * 1.3) * 0.8, 0, 0.3)
			lf = 0.8 + sin(cycle * 1.7) * 0.6
			rf = 0.8 + cos(cycle * 1.7) * 0.6
			lk = -0.6 - sin(cycle) * 0.5
			rk = -0.6 - cos(cycle) * 0.5
		"grabbed":
			cycle += delta * 22.0
			la = Vector3(2.6 + sin(cycle) * 0.3, 0, -0.3)
			ra = Vector3(2.6 + cos(cycle) * 0.3, 0, 0.3)
			ll = Vector3(sin(cycle * 1.1) * 0.6, 0, 0)
			rl = Vector3(-sin(cycle * 1.1) * 0.6, 0, 0)
			lf = 1.0
			rf = 1.0
			lk = -0.5 - sin(cycle) * 0.4
			rk = -0.5 + sin(cycle) * 0.4
		"dead":
			la = Vector3(0.2, 0, -1.4)
			ra = Vector3(-0.3, 0, 1.3)
			ll = Vector3(0.1, 0, -0.2)
			rl = Vector3(-0.1, 0, 0.15)
			lf = 0.4
			rf = 0.1
			lk = -0.3
			rk = -0.05
		"air":
			la = Vector3(-0.6, 0, -0.7)
			ra = Vector3(-0.6, 0, 0.7)
			ll = Vector3(0.9, 0, 0)
			rl = Vector3(-0.2, 0, 0)
			lf = 0.9
			rf = 0.9
			lk = -1.4
			rk = -0.5
		"glide":
			la = Vector3(0, 0, -1.45)
			ra = Vector3(0, 0, 1.45)
			ll = Vector3(-0.1, 0, -0.12)
			rl = Vector3(0.1, 0, 0.12)
			lf = 0.1
			rf = 0.1
			lk = -0.3
			rk = -0.2
		"crouch":
			la = Vector3(-0.4, 0, -0.3)
			ra = Vector3(-0.4, 0, 0.3)
			ll = Vector3(1.2, 0, 0)
			rl = Vector3(1.2, 0, 0)
			lk = -1.9
			rk = -1.9
			lf = 0.6
			rf = 0.6
		"cower":
			la = Vector3(2.4, 0, 0.6)
			ra = Vector3(2.4, 0, -0.6)
			ll = Vector3(0.6, 0, 0)
			rl = Vector3(0.6, 0, 0)
			lf = 2.0
			rf = 2.0
			lk = -1.0
			rk = -1.0
		_:
			cycle += delta
			la = Vector3(sin(cycle * 1.5) * 0.04, 0, -0.08)
			ra = Vector3(-sin(cycle * 1.5) * 0.04, 0, 0.08)
			lk = -0.04
			rk = -0.04
	# poses set by other scripts this frame (parkour), applied before attacks
	if not pose_override.is_empty():
		la = pose_override.get("la", la)
		ra = pose_override.get("ra", ra)
		ll = pose_override.get("ll", ll)
		rl = pose_override.get("rl", rl)
		lf = pose_override.get("lf", lf)
		rf = pose_override.get("rf", rf)
		lk = pose_override.get("lk", lk)
		rk = pose_override.get("rk", rk)
		k = 1.0 - exp(-float(pose_override.get("speed", 14.0)) * delta)
		pose_override = {}
	if swing_timer > 0.0:
		swing_timer -= delta
		var dur: float = get_meta("swing_duration", 0.22)
		var t := 1.0 - clampf(swing_timer / dur, 0.0, 1.0)
		var arc := sin(t * PI)
		var pose: Vector3
		var fore := 0.2
		match swing_style:
			0:
				pose = Vector3(1.6 * arc + 0.2, 0, 0)                 # straight punch
				fore = (1.0 - arc) * 1.5
			1:
				pose = Vector3(1.2, lerpf(-1.4, 1.4, t), 0.6 * arc)  # horizontal slash
				fore = 0.25
			2:
				pose = Vector3(lerpf(3.0, -0.2, t), 0, 0)             # overhead smash
				fore = lerpf(1.2, 0.1, t)
			3:
				pose = Vector3(lerpf(-0.5, 2.8, t), 0, 0)             # uppercut
				fore = lerpf(1.6, 0.6, t)
			_:
				pose = Vector3(1.5 * arc, 0, 0)
		k = 1.0 - exp(-40.0 * delta)
		if swing_right:
			ra = pose
			rf = fore
			# the other arm pulls back for balance
			la = Vector3(-0.4 * arc, 0, -0.15)
			lf = 1.2
		else:
			la = Vector3(pose.x, -pose.y, -pose.z)
			lf = fore
			ra = Vector3(-0.4 * arc, 0, 0.15)
			rf = 1.2
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
	forearm_l.rotation.x = lerpf(forearm_l.rotation.x, lf, k)
	forearm_r.rotation.x = lerpf(forearm_r.rotation.x, rf, k)
	shin_l.rotation.x = lerpf(shin_l.rotation.x, lk, k)
	shin_r.rotation.x = lerpf(shin_r.rotation.x, rk, k)


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
