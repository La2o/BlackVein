class_name City
extends Node3D
## Builds the city at startup: streets, sidewalks, skyscrapers, rooftop props,
## street lamps, trees and parked cars. Also bakes the walking map for people
## and answers questions like "give me a random sidewalk spot near here".

const BUILDING_SHADER := preload("res://shaders/building.gdshader")
const ROAD_SHADER := preload("res://shaders/road.gdshader")
const TEX := "res://assets/textures/"   # CC0 photo textures, see assets/CREDITS.md
const CAR_SCRIPT := preload("res://scripts/car.gd")
const FIELD_SHADER := preload("res://shaders/field.gdshader")

## The map is a grid of blocks, each in a district: skyscrapers downtown, mid-rise brick and parks
## around it, then suburbs (south and west), industry (east, with the military base) and farmland
## (north). The ring of blocks outside the playable area matches its side.
enum District { DOWNTOWN, MIDTOWN, PARK, SUBURB, INDUSTRIAL, FARM }
const DISTRICT_NAMES := ["Downtown", "Midtown", "Park", "Suburbs", "Industrial", "Farmland"]

@export var blocks := 16
@export var block_size := 44.0
@export var street_width := 16.0
@export var backdrop_ring := 2
@export var city_seed := 2026
@export var car_count := 130

var period := 60.0
var x0 := 0.0
var z0 := 0.0
var base_cell := Vector2i(14, 9)   # set in build(): in the industrial east
var districts := {}               # Vector2i block -> District (playable blocks and the outer ring)
var _bgrid := {}                  # Vector2i cell -> building indices (spatial index for is_inside_building)
var base_rect := Rect2()          # the military base, in x/z
var base_points := {}             # named spots inside the base
var spawn_point := Vector3.ZERO
var spawn_yaw := 0.0
var buildings: Array[Dictionary] = []   # {aabb: AABB, height: float}
var building_mats: Array[ShaderMaterial] = []
var lamp_mat: StandardMaterial3D
var pool_mat: ShaderMaterial
var _night := 0.0
var _neon_mats: Array[StandardMaterial3D] = []
var _parapet_mat: StandardMaterial3D
var road_mat: ShaderMaterial
var nav_region: NavigationRegion3D
var nav_ready := false
var rng := RandomNumberGenerator.new()

var _sidewalk_mat: StandardMaterial3D
var _roof_mats: Array[StandardMaterial3D] = []
var _nav_source := NavigationMeshSourceGeometryData3D.new()

const AVENUE_NAMES := ["Harbor Ave", "1st Ave", "2nd Ave", "Lexon Ave", "Park Ave",
	"Madigan Ave", "Union Ave", "Broadline", "Riverside Ave", "West End Ave", "Pier Ave", "Canal Ave", "Bay Ave",
	"Foundry Ave", "Mill Ave", "Orchard Ave", "Kiln Ave", "Ridge Ave"]
const STREET_NAMES := ["Fulton St", "Grove St", "Chambers St", "Canal St", "Houston St",
	"Bleak St", "Spring St", "Delancy St", "Ash St", "Morrow St", "Pine St", "Wall St", "Beacon St",
	"Maple St", "Willow Ln", "Cedar Ln", "Birch Ln", "Meadow Rd"]


func build() -> void:
	rng.seed = city_seed
	period = block_size + street_width
	var total := blocks * period + street_width
	x0 = -total * 0.5
	z0 = -total * 0.5
	base_cell = Vector2i(blocks - 2, blocks / 2 + 1)
	_make_materials()
	_assign_districts()
	_build_ground(total)
	var mid := blocks / 2
	for i in range(-backdrop_ring, blocks + backdrop_ring):
		for j in range(-backdrop_ring, blocks + backdrop_ring):
			var bx := x0 + street_width + i * period
			var bz := z0 + street_width + j * period
			var cell := Vector2i(i, j)
			var dist: int = districts[cell]
			if i < 0 or j < 0 or i >= blocks or j >= blocks:
				_build_backdrop_block(bx, bz, dist)
			elif cell == base_cell:
				_build_base(bx, bz)
			else:
				match dist:
					District.SUBURB: _build_suburb(bx, bz)
					District.INDUSTRIAL: _build_industrial(bx, bz)
					District.FARM: _build_farm(bx, bz)
					District.PARK: _build_park(bx, bz)
					_: _build_block(i, j, bx, bz, i == mid and j == mid - 1)
	_build_street_lamps()
	_build_traffic_signals()
	_build_street_props()
	_build_trees()
	spawn_point = Vector3(street_x(mid), 1.2, street_z(mid))
	spawn_yaw = 0.0
	_place_cars()
	_flush_scatter()
	_index_buildings()
	_bake_navigation(total)


# ------------------------------------------------------------------ materials

func _make_materials() -> void:
	var palettes := [
		[Color(0.62, 0.6, 0.56), Color(0.15, 0.18, 0.22), 2.6, 0.58],
		[Color(0.5, 0.29, 0.22), Color(0.13, 0.14, 0.16), 2.3, 0.5],
		[Color(0.74, 0.67, 0.55), Color(0.15, 0.17, 0.2), 2.8, 0.55],
		[Color(0.18, 0.23, 0.29), Color(0.22, 0.32, 0.42), 1.5, 0.86],
		[Color(0.82, 0.81, 0.78), Color(0.17, 0.21, 0.26), 2.2, 0.6],
		[Color(0.34, 0.36, 0.39), Color(0.11, 0.13, 0.15), 3.0, 0.45],
		[Color(0.42, 0.47, 0.44), Color(0.2, 0.28, 0.3), 1.8, 0.78],
	]
	for p in palettes:
		var m := ShaderMaterial.new()
		m.shader = BUILDING_SHADER
		m.set_shader_parameter("wall_color", p[0])
		m.set_shader_parameter("glass_color", p[1])
		m.set_shader_parameter("window_width", p[2])
		m.set_shader_parameter("window_fill", p[3])
		for t in ["concrete", "brick", "plaster", "gravel", "siding", "metal", "barn"]:
			m.set_shader_parameter(t + "_col", load(TEX + t + "/color.jpg"))
			m.set_shader_parameter(t + "_nrm", load(TEX + t + "/normal.jpg"))
		building_mats.append(m)
	_grass_mat = _tex_mat("grass", Color(0.85, 0.95, 0.8), 4.0)
	_lot_mat = _tex_mat("concrete", Color(0.62, 0.62, 0.6), 4.0)
	_drive_mat = _tex_mat("concrete", Color(0.75, 0.74, 0.72), 3.0)
	for tint in [Color(0.55, 0.55, 0.6), Color(0.45, 0.5, 0.42), Color(0.5, 0.42, 0.38)]:
		_house_roofs.append(_tex_mat("roof_slate", tint, 2.0))
	for tint in [Color(1, 1, 1), Color(0.85, 0.75, 0.7)]:
		_house_roofs.append(_tex_mat("roof_tile", tint, 2.0))
	_field_mat = ShaderMaterial.new()
	_field_mat.shader = FIELD_SHADER
	for t in ["soil", "grass"]:
		_field_mat.set_shader_parameter(t + "_col", load(TEX + t + "/color.jpg"))
		_field_mat.set_shader_parameter(t + "_nrm", load(TEX + t + "/normal.jpg"))
	_sidewalk_mat = StandardMaterial3D.new()
	_sidewalk_mat.albedo_color = Color(0.9, 0.88, 0.85)
	_sidewalk_mat.albedo_texture = load(TEX + "paving/color.jpg")
	_sidewalk_mat.normal_enabled = true
	_sidewalk_mat.normal_texture = load(TEX + "paving/normal.jpg")
	_sidewalk_mat.roughness_texture = load(TEX + "paving/roughness.jpg")
	_sidewalk_mat.uv1_triplanar = true
	_sidewalk_mat.uv1_world_triplanar = true
	_sidewalk_mat.uv1_scale = Vector3.ONE / 2.5
	_sidewalk_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for c in [Color(0.35, 0.33, 0.3), Color(0.5, 0.47, 0.42), Color(0.27, 0.28, 0.3), Color(0.45, 0.3, 0.2)]:
		var rm := StandardMaterial3D.new()
		rm.albedo_color = c
		rm.roughness = 0.8
		_roof_mats.append(rm)
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1, 0.95, 0.8)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1, 0.85, 0.55)
	lamp_mat.emission_energy_multiplier = 0.2


func set_night(amount: float) -> void:
	_night = amount
	for m in building_mats:
		m.set_shader_parameter("night", amount)
	for m in _neon_mats:
		m.emission_energy_multiplier = lerpf(0.6, 3.5, amount)
	lamp_mat.emission_energy_multiplier = lerpf(0.2, 6.0, amount)
	if pool_mat:
		pool_mat.set_shader_parameter("strength", amount * 0.85)


# ------------------------------------------------------------------ geometry helpers

func _add_box(size: Vector3, center: Vector3, mat: Material, layer := Game.LAYER_WORLD,
		parent: Node = self, nav := false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	if nav:
		_nav_source.add_faces(mesh.get_faces(), Transform3D(Basis(), center))
	return body


func _add_cylinder(radius: float, height: float, center: Vector3, mat: Material, parent: Node = self) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body


func _build_ground(total: float) -> void:
	road_mat = ShaderMaterial.new()
	road_mat.shader = ROAD_SHADER
	road_mat.set_shader_parameter("period", period)
	road_mat.set_shader_parameter("street", street_width)
	road_mat.set_shader_parameter("origin", Vector2(x0, z0))
	road_mat.set_shader_parameter("asphalt_col", load(TEX + "asphalt/color.jpg"))
	road_mat.set_shader_parameter("asphalt_nrm", load(TEX + "asphalt/normal.jpg"))
	road_mat.set_shader_parameter("asphalt_rough", load(TEX + "asphalt/roughness.jpg"))
	road_mat.set_shader_parameter("district_map", _district_texture())
	road_mat.set_shader_parameter("ring", float(backdrop_ring))
	road_mat.set_shader_parameter("grass_col", load(TEX + "grass/color.jpg"))
	var size := total + backdrop_ring * period * 2.0
	_add_box(Vector3(size, 1.0, size), Vector3(0, -0.5, 0), road_mat)
	# open country beyond the edge of the map
	_add_box(Vector3(size + 3000.0, 1.0, size + 3000.0), Vector3(0, -0.52, 0), _grass_mat)
	# walking surface for the navigation bake (only the playable city)
	var half := total * 0.5 + 4.0
	var faces := PackedVector3Array([
		Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half),
		Vector3(-half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half),
	])
	_nav_source.add_faces(faces, Transform3D())


# ------------------------------------------------------------------ blocks

func _build_block(i: int, j: int, bx: float, bz: float, landmark: bool) -> void:
	var block := Node3D.new()
	block.name = "Block_%d_%d" % [i, j]
	add_child(block)
	_add_box(Vector3(block_size, 0.15, block_size), Vector3(bx + block_size * 0.5, 0.075, bz + block_size * 0.5),
		_sidewalk_mat, Game.LAYER_WORLD, block, true)
	var inset := 3.5
	var inner := block_size - inset * 2.0
	var ox := bx + inset
	var oz := bz + inset
	var lots: Array[Rect2] = []
	var pattern := 0 if landmark else rng.randi_range(0, 4)
	if districts.get(Vector2i(i, j), District.DOWNTOWN) == District.MIDTOWN:
		pattern = rng.randi_range(1, 4)   # midtown: more, smaller buildings
	match pattern:
		0:
			lots.append(Rect2(ox, oz, inner, inner))
		1:
			lots.append(Rect2(ox, oz, inner * 0.5, inner))
			lots.append(Rect2(ox + inner * 0.5, oz, inner * 0.5, inner))
		2:
			lots.append(Rect2(ox, oz, inner, inner * 0.5))
			lots.append(Rect2(ox, oz + inner * 0.5, inner, inner * 0.5))
		_:
			for a in 2:
				for b in 2:
					lots.append(Rect2(ox + a * inner * 0.5, oz + b * inner * 0.5, inner * 0.5, inner * 0.5))
	var center_dist := Vector2(bx + block_size * 0.5, bz + block_size * 0.5).length()
	var midtown: bool = districts.get(Vector2i(i, j), District.DOWNTOWN) == District.MIDTOWN
	var d := clampf(center_dist / (3.5 * period), 0.0, 1.0)
	if midtown:
		d = clampf((center_dist - 3.0 * period) / (3.0 * period), 0.0, 1.0)
	for lot in lots:
		var gap := 1.2
		var sx0 := gap + rng.randf_range(0.0, 2.0)
		var sx1 := gap + rng.randf_range(0.0, 2.0)
		var sz0 := gap + rng.randf_range(0.0, 2.0)
		var sz1 := gap + rng.randf_range(0.0, 2.0)
		if pattern == 0:
			sx0 = 0.5
			sx1 = 0.5
			sz0 = 0.5
			sz1 = 0.5
		var w := lot.size.x - sx0 - sx1
		var depth := lot.size.y - sz0 - sz1
		var h := rng.randf_range(0.35, 1.0) * lerpf(115.0, 40.0, d)
		if midtown:
			h = rng.randf_range(0.45, 1.0) * lerpf(45.0, 16.0, d)
		if landmark:
			h = 150.0
		h = maxf(10.5, roundf(h / 3.5) * 3.5)
		var cx := lot.position.x + sx0 + w * 0.5
		var cz := lot.position.y + sz0 + depth * 0.5
		_make_building(block, Vector3(w, h, depth), Vector3(cx, 0.15, cz), landmark, midtown)


func set_wetness(amount: float) -> void:
	road_mat.set_shader_parameter("wetness", amount)
	if _field_mat:
		_field_mat.set_shader_parameter("wetness", amount)
	for m in building_mats:
		m.set_shader_parameter("wetness", amount)


func _make_building(parent: Node, size: Vector3, base: Vector3, landmark: bool, brick := false) -> void:
	var mat_index := rng.randi_range(0, building_mats.size() - 1)
	if size.y > 75.0 and rng.randf() < 0.5:
		mat_index = 3
	if landmark:
		mat_index = 3
	var tint := rng.randf_range(-1.0, 1.0)
	var bseed := rng.randf()
	if brick and rng.randf() < 0.7:
		# the facade shader picks brick for this band of seeds (see building.gdshader)
		bseed = (rng.randf_range(0.45, 0.68) - 0.13 + float(rng.randi_range(0, 6))) / 7.31
	# tall towers step back once or twice as they rise (Manhattan-style setbacks)
	var tiers: Array[Vector3] = []   # [size per tier], stacked
	var min_side := minf(size.x, size.z)
	if size.y > 55.0 and min_side > 14.0 and not landmark and rng.randf() < 0.75:
		var lower := roundf(size.y * rng.randf_range(0.45, 0.65) / 3.5) * 3.5
		var inset := rng.randf_range(2.5, minf(5.0, min_side * 0.2))
		tiers.append(Vector3(size.x, lower, size.z))
		var upper := size.y - lower
		if upper > 40.0 and min_side - inset * 2.0 > 14.0 and rng.randf() < 0.5:
			var mid := roundf(upper * 0.55 / 3.5) * 3.5
			tiers.append(Vector3(size.x - inset * 2.0, mid, size.z - inset * 2.0))
			tiers.append(Vector3(size.x - inset * 3.6, upper - mid, size.z - inset * 3.6))
		else:
			tiers.append(Vector3(size.x - inset * 2.0, upper, size.z - inset * 2.0))
	elif landmark:
		tiers.append(Vector3(size.x, 60.0, size.z))
		tiers.append(Vector3(size.x - 8.0, 55.0, size.z - 8.0))
		tiers.append(Vector3(size.x - 16.0, size.y - 115.0, size.z - 16.0))
	else:
		tiers.append(size)
	var y := base.y
	for k in tiers.size():
		var t: Vector3 = tiers[k]
		var center := Vector3(base.x, y + t.y * 0.5, base.z)
		var body := _add_box(t, center, building_mats[mat_index], Game.LAYER_WORLD, parent, k == 0)
		body.add_to_group("buildings")
		var mi := body.get_child(1) as MeshInstance3D
		mi.set_instance_shader_parameter("tint", tint)
		mi.set_instance_shader_parameter("seed", bseed)
		var aabb := AABB(Vector3(base.x - t.x * 0.5, y, base.z - t.z * 0.5), t)
		buildings.append({"aabb": aabb, "height": y + t.y})
		_parapet(body, t, k == tiers.size() - 1)
		if k == tiers.size() - 1:
			_rooftop_props(parent, aabb, y + t.y, landmark)
		y += t.y
	# a glowing billboard on some mid-height rooftops
	if not landmark and size.y > 20.0 and size.y < 70.0 and tiers.size() == 1 and rng.randf() < 0.18:
		_billboard(parent, base, size)


## A low wall around the edge of a roof. Flush with the facade so wall running
## flows straight over it.
func _parapet(body: StaticBody3D, size: Vector3, top_tier: bool) -> void:
	if _parapet_mat == null:
		_parapet_mat = StandardMaterial3D.new()
		_parapet_mat.albedo_color = Color(0.32, 0.31, 0.3)
		_parapet_mat.roughness = 0.9
	var h := 0.9 if top_tier else 0.7
	var t := 0.35
	var top := size.y * 0.5
	var pieces := [
		[Vector3(size.x, h, t), Vector3(0, top + h * 0.5, size.z * 0.5 - t * 0.5)],
		[Vector3(size.x, h, t), Vector3(0, top + h * 0.5, -size.z * 0.5 + t * 0.5)],
		[Vector3(t, h, size.z - t * 2.0), Vector3(size.x * 0.5 - t * 0.5, top + h * 0.5, 0)],
		[Vector3(t, h, size.z - t * 2.0), Vector3(-size.x * 0.5 + t * 0.5, top + h * 0.5, 0)],
	]
	for pc in pieces:
		var mesh := BoxMesh.new()
		mesh.size = pc[0]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _parapet_mat
		mi.position = pc[1]
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = pc[0]
		cs.shape = box
		cs.position = pc[1]
		body.add_child(cs)


func _billboard(parent: Node, base: Vector3, size: Vector3) -> void:
	var colors := [Color(1, 0.2, 0.35), Color(0.2, 0.75, 1), Color(1, 0.75, 0.15), Color(0.5, 1, 0.4), Color(0.85, 0.3, 1)]
	var c: Color = colors[rng.randi_range(0, colors.size() - 1)]
	var neon := StandardMaterial3D.new()
	neon.albedo_color = c * 0.5
	neon.emission_enabled = true
	neon.emission = c
	neon.emission_energy_multiplier = 0.6
	_neon_mats.append(neon)
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.12, 0.12, 0.13)
	frame.metallic = 0.6
	var along_x := rng.randf() < 0.5
	var w := minf(size.x if along_x else size.z, 16.0) * 0.8
	var top := base.y + size.y
	var edge := (size.z * 0.5 - 1.5) * (1.0 if rng.randf() < 0.5 else -1.0)
	var pos := Vector3(base.x, top + 4.6, base.z + edge) if along_x else Vector3(base.x + edge, top + 4.6, base.z)
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(w, 4.5, 0.25) if along_x else Vector3(0.25, 4.5, w)
	panel.mesh = pm
	panel.material_override = neon
	panel.position = pos
	parent.add_child(panel)
	# simple stripes so it reads as an ad, not a lamp
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(w * 0.7, 0.5, 0.3) if along_x else Vector3(0.3, 0.5, w * 0.7)
	stripe.mesh = sm
	stripe.material_override = frame
	stripe.position = pos + Vector3(0, -0.9, 0)
	parent.add_child(stripe)
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.25, 3.0, 0.25)
		leg.mesh = lm
		leg.material_override = frame
		var off := Vector3(side * w * 0.4, 0, 0) if along_x else Vector3(0, 0, side * w * 0.4)
		leg.position = Vector3(pos.x, top + 1.3, pos.z) + off
		parent.add_child(leg)


func _rooftop_props(parent: Node, aabb: AABB, top: float, landmark: bool) -> void:
	var roof_mat: StandardMaterial3D = _roof_mats[rng.randi_range(0, _roof_mats.size() - 1)]
	var min_x := aabb.position.x + 3.0
	var max_x := aabb.end.x - 3.0
	var min_z := aabb.position.z + 3.0
	var max_z := aabb.end.z - 3.0
	if max_x <= min_x or max_z <= min_z:
		return
	# air conditioning units / stair housing
	for k in rng.randi_range(1, 3):
		var s := Vector3(rng.randf_range(1.6, 3.5), rng.randf_range(1.0, 2.2), rng.randf_range(1.6, 3.5))
		var p := Vector3(rng.randf_range(min_x, max_x), top + s.y * 0.5, rng.randf_range(min_z, max_z))
		_add_box(s, p, roof_mat, Game.LAYER_WORLD, parent)
	if aabb.size.y < 70.0 and minf(aabb.size.x, aabb.size.z) > 12.0 and rng.randf() < 0.4:
		# classic wooden water tower on stilts
		var p := Vector3(rng.randf_range(min_x + 1, max_x - 1), top, rng.randf_range(min_z + 1, max_z - 1))
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.4, 0.27, 0.17)
		wood.roughness = 0.9
		_add_box(Vector3(3.2, 3.0, 3.2), p + Vector3(0, 1.5, 0), roof_mat, Game.LAYER_WORLD, parent)
		_add_cylinder(2.3, 4.0, p + Vector3(0, 5.0, 0), wood, parent)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 2.5
		cm.height = 1.6
		cone.mesh = cm
		cone.material_override = wood
		cone.position = p + Vector3(0, 7.8, 0)
		parent.add_child(cone)
	if aabb.size.y > 85.0 or landmark:
		var p := Vector3((min_x + max_x) * 0.5, top, (min_z + max_z) * 0.5)
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.6, 0.6, 0.62)
		metal.metallic = 0.8
		metal.roughness = 0.4
		var mast_h := 22.0 if landmark else 10.0
		_add_cylinder(0.3, mast_h, p + Vector3(0, mast_h * 0.5, 0), metal, parent)
		var tip := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		tip.mesh = sm
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(1, 0.1, 0.05)
		red.emission_enabled = true
		red.emission = Color(1, 0.1, 0.05)
		red.emission_energy_multiplier = 4.0
		tip.material_override = red
		tip.position = p + Vector3(0, mast_h, 0)
		parent.add_child(tip)


func _build_base(bx: float, bz: float) -> void:
	var base := Node3D.new()
	base.name = "MilitaryBase"
	add_child(base)
	base_rect = Rect2(bx, bz, block_size, block_size)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.4, 0.41, 0.38)
	concrete.roughness = 0.95
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.26, 0.3, 0.2)
	green.roughness = 0.85
	var stripes := StandardMaterial3D.new()
	stripes.albedo_color = Color(0.85, 0.7, 0.1)
	_add_box(Vector3(block_size, 0.15, block_size), Vector3(bx + block_size * 0.5, 0.075, bz + block_size * 0.5), concrete, Game.LAYER_WORLD, base, true)
	var h := 4.0
	var t := 0.6
	var c := Vector3(bx + block_size * 0.5, 0, bz + block_size * 0.5)
	# perimeter walls with a gate on the east side
	_add_box(Vector3(block_size, h, t), Vector3(c.x, h * 0.5, bz + 0.3), green, Game.LAYER_WORLD, base, true)
	_add_box(Vector3(block_size, h, t), Vector3(c.x, h * 0.5, bz + block_size - 0.3), green, Game.LAYER_WORLD, base, true)
	_add_box(Vector3(t, h, block_size), Vector3(bx + 0.3, h * 0.5, c.z), green, Game.LAYER_WORLD, base, true)
	var gate := 10.0
	var seg := (block_size - gate) * 0.5
	_add_box(Vector3(t, h, seg), Vector3(bx + block_size - 0.3, h * 0.5, bz + seg * 0.5), green, Game.LAYER_WORLD, base, true)
	_add_box(Vector3(t, h, seg), Vector3(bx + block_size - 0.3, h * 0.5, bz + block_size - seg * 0.5), green, Game.LAYER_WORLD, base, true)
	_add_box(Vector3(0.3, 0.3, gate), Vector3(bx + block_size - 0.3, 2.2, c.z), stripes, 0, base)
	# barracks and a command building
	_add_box(Vector3(14, 4.5, 7), Vector3(bx + 10, 2.25, bz + 8), green, Game.LAYER_WORLD, base, true)
	_add_box(Vector3(14, 4.5, 7), Vector3(bx + 10, 2.25, bz + block_size - 8), green, Game.LAYER_WORLD, base, true)
	_add_box(Vector3(8, 7.0, 8), Vector3(bx + 8, 3.5, c.z), concrete, Game.LAYER_WORLD, base, true)
	# watchtowers in the corners
	for corner in [Vector2(3, 3), Vector2(block_size - 3, 3), Vector2(3, block_size - 3), Vector2(block_size - 3, block_size - 3)]:
		var p := Vector3(bx + corner.x, 0, bz + corner.y)
		for o in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			_add_box(Vector3(0.25, 9, 0.25), p + Vector3(o.x * 1.3, 4.5, o.y * 1.3), green, Game.LAYER_WORLD, base)
		_add_box(Vector3(3.6, 0.4, 3.6), p + Vector3(0, 9.2, 0), green, Game.LAYER_WORLD, base)
		_add_box(Vector3(3.6, 1.0, 0.15), p + Vector3(0, 9.9, 1.75), green, Game.LAYER_WORLD, base)
	# helipad
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 6.0
	cm.bottom_radius = 6.0
	cm.height = 0.05
	pad.mesh = cm
	pad.material_override = stripes
	pad.position = Vector3(c.x + 8, 0.18, c.z)
	base.add_child(pad)
	# sandbag lines
	for k in 4:
		_add_box(Vector3(5, 1.1, 1.2), Vector3(bx + 26 + (k % 2) * 6, 0.7, bz + 14 + k * 5), green, Game.LAYER_WORLD, base, true)
	base_points = {
		"center": c + Vector3(4, 0.3, 0),
		"helipad": Vector3(c.x + 8, 0.3, c.z),
		"command": Vector3(bx + 14, 0.3, c.z),
		"gate": Vector3(bx + block_size + 3, 0.3, c.z),
		"tank": Vector3(bx + 24, 0.3, bz + block_size - 10),
	}
	buildings.append({"aabb": AABB(Vector3(bx + 3, 0, bz + 4.5), Vector3(14, 4.5, 7)), "height": 4.5})
	buildings.append({"aabb": AABB(Vector3(bx + 3, 0, bz + block_size - 11.5), Vector3(14, 4.5, 7)), "height": 4.5})
	buildings.append({"aabb": AABB(Vector3(bx + 4, 0, c.z - 4), Vector3(8, 7, 8)), "height": 7.0})


func in_base(p: Vector3) -> bool:
	return base_rect.has_point(Vector2(p.x, p.z))


func random_base_point() -> Vector3:
	for k in 20:
		var p := Vector3(randf_range(base_rect.position.x + 4, base_rect.end.x - 4), 0.3, randf_range(base_rect.position.y + 4, base_rect.end.y - 4))
		if not is_inside_building(p, 1.0):
			return p
	return base_points.get("center", spawn_point)


func _build_backdrop_block(bx: float, bz: float, dist: int) -> void:
	match dist:
		District.FARM:
			_field(bx, bz, false)
			if rng.randf() < 0.5:
				_tree_line(Vector3(bx, 0, bz + block_size * rng.randf()), Vector3(1, 0, 0), block_size)
			return
		District.SUBURB:
			_house_row(self, bx, bz, true)
			return
		District.INDUSTRIAL:
			_warehouse(self, Rect2(bx + 3, bz + 3, block_size - 6, block_size - 6))
			return
	var h := maxf(14.0, roundf(rng.randf_range(20.0, 75.0) / 3.5) * 3.5)
	var w := block_size - rng.randf_range(4.0, 10.0)
	var dd := block_size - rng.randf_range(4.0, 10.0)
	var mat: ShaderMaterial = building_mats[rng.randi_range(0, building_mats.size() - 1)]
	var c := Vector3(bx + block_size * 0.5, h * 0.5, bz + block_size * 0.5)
	var body := _add_box(Vector3(w, h, dd), c, mat)
	body.add_to_group("buildings")
	buildings.append({"aabb": AABB(c - Vector3(w, h, dd) * 0.5, Vector3(w, h, dd)), "height": h})


# ------------------------------------------------------------------ street dressing

func _build_street_lamps() -> void:
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.12
	pole_mesh.height = 7.0
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.15, 0.16, 0.17)
	pole_mat.metallic = 0.6
	pole_mesh.material = pole_mat
	var bulb_mesh := BoxMesh.new()
	bulb_mesh.size = Vector3(0.5, 0.18, 1.2)
	bulb_mesh.material = lamp_mat
	var poles: Array[Transform3D] = []
	var bulbs: Array[Transform3D] = []
	for i in range(blocks):
		for j in range(blocks):
			if districts[Vector2i(i, j)] == District.FARM:
				continue   # no street lights out in the fields
			var bx := x0 + street_width + i * period
			var bz := z0 + street_width + j * period
			for corner in [Vector2(0.6, 0.6), Vector2(block_size - 0.6, 0.6), Vector2(0.6, block_size - 0.6), Vector2(block_size - 0.6, block_size - 0.6)]:
				var p := Vector3(bx + corner.x, 3.5, bz + corner.y)
				poles.append(Transform3D(Basis(), p))
				var out := Vector3(signf(corner.x - block_size * 0.5), 0, 0) * 0.8
				bulbs.append(Transform3D(Basis(), p + Vector3(0, 3.4, 0) + out))
	_multimesh(pole_mesh, poles)
	_multimesh(bulb_mesh, bulbs)
	# fake pools of light under the lamps (fade in at night)
	var pool := PlaneMesh.new()
	pool.size = Vector2(15, 15)
	pool_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 0.0;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, 0.0, d);
	ALBEDO = vec3(1.0, 0.72, 0.4) * a * a * strength;
}
"""
	pool_mat.shader = sh
	pool.material = pool_mat
	var pools: Array[Transform3D] = []
	for b in bulbs:
		pools.append(Transform3D(Basis(), Vector3(b.origin.x, 0.17, b.origin.z)))
	_multimesh(pool, pools)


var _signal_mats: Array[StandardMaterial3D] = []   # [x-axis light, z-axis light]
var _signal_timer := 0.0
var _signal_phase := 0


## Traffic signals on two corners of every intersection. Lights alternate
## between the two directions every 12 seconds.
func _build_traffic_signals() -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.09
	pole.bottom_radius = 0.11
	pole.height = 5.2
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.12)
	dark.metallic = 0.5
	pole.material = dark
	var arm := BoxMesh.new()
	arm.size = Vector3(0.12, 0.12, 4.0)
	arm.material = dark
	var housing := BoxMesh.new()
	housing.size = Vector3(0.45, 1.2, 0.4)
	housing.material = dark
	for k in 2:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.1, 0.1)
		m.emission_enabled = true
		m.emission_energy_multiplier = 2.5
		_signal_mats.append(m)
	var lamp_x := BoxMesh.new()
	lamp_x.size = Vector3(0.3, 0.3, 0.42)
	lamp_x.material = _signal_mats[0]
	var lamp_z := BoxMesh.new()
	lamp_z.size = Vector3(0.3, 0.3, 0.42)
	lamp_z.material = _signal_mats[1]
	var poles: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	var housings: Array[Transform3D] = []
	var lamps_x: Array[Transform3D] = []
	var lamps_z: Array[Transform3D] = []
	var hs := street_width * 0.5 + 0.8
	for i in range(blocks + 1):
		for j in range(blocks + 1):
			var c := Vector3(street_x(i), 0, street_z(j))
			if not _is_urban_corner(i, j):
				continue
			if Vector2i(i, j) == base_cell or Vector2i(i, j) == base_cell + Vector2i(1, 0) \
					or Vector2i(i, j) == base_cell + Vector2i(0, 1) or Vector2i(i, j) == base_cell + Vector2i(1, 1):
				continue
			# corner A faces traffic along Z, corner B faces traffic along X
			for corner in [[Vector3(-hs, 0, -hs - 2.0), 0.0, true], [Vector3(hs, 0, hs + 2.0), PI, false]]:
				var p: Vector3 = c + corner[0]
				var yaw: float = corner[1]
				var basis := Basis(Vector3.UP, yaw)
				poles.append(Transform3D(Basis(), p + Vector3(0, 2.6, 0)))
				var arm_dir := basis * Vector3(0, 0, 1)
				if not corner[2]:
					arm_dir = basis * Vector3(1, 0, 0)
				var arm_basis := Basis.looking_at(arm_dir, Vector3.UP)
				arms.append(Transform3D(arm_basis, p + Vector3(0, 5.1, 0) + arm_dir * 2.0))
				var head := p + Vector3(0, 4.5, 0) + arm_dir * 3.6
				housings.append(Transform3D(Basis(), head))
				var lamp := Transform3D(Basis(), head + Vector3(0, 0.25, 0))
				if corner[2]:
					lamps_z.append(lamp)
				else:
					lamps_x.append(lamp)
	_multimesh(pole, poles)
	_multimesh(arm, arms)
	_multimesh(housing, housings)
	_multimesh(lamp_x, lamps_x)
	_multimesh(lamp_z, lamps_z)
	_update_signals()


func _update_signals() -> void:
	var green := Color(0.2, 1.0, 0.4)
	var red := Color(1.0, 0.15, 0.1)
	_signal_mats[0].emission = green if _signal_phase == 0 else red
	_signal_mats[1].emission = red if _signal_phase == 0 else green


func _process(delta: float) -> void:
	if _signal_mats.is_empty():
		return
	_signal_timer += delta
	if _signal_timer > 12.0:
		_signal_timer = 0.0
		_signal_phase = 1 - _signal_phase
		_update_signals()


## Fire hydrants, benches and trash cans along the sidewalks.
func _build_street_props() -> void:
	var hydrant := CylinderMesh.new()
	hydrant.top_radius = 0.16
	hydrant.bottom_radius = 0.2
	hydrant.height = 0.75
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.7, 0.08, 0.06)
	red.roughness = 0.6
	hydrant.material = red
	var bin := CylinderMesh.new()
	bin.top_radius = 0.3
	bin.bottom_radius = 0.26
	bin.height = 0.95
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.15, 0.25, 0.18)
	green.metallic = 0.4
	bin.material = green
	var bench := BoxMesh.new()
	bench.size = Vector3(1.8, 0.45, 0.6)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.24, 0.15)
	bench.material = wood
	var hyd: Array[Transform3D] = []
	var bins: Array[Transform3D] = []
	var benches: Array[Transform3D] = []
	for i in range(blocks):
		for j in range(blocks):
			if Vector2i(i, j) == base_cell or districts[Vector2i(i, j)] in [District.FARM, District.PARK]:
				continue
			var bx := x0 + street_width + i * period
			var bz := z0 + street_width + j * period
			for side in 4:
				var t := rng.randf_range(6.0, block_size - 6.0)
				var p: Vector3
				var yaw := 0.0
				match side:
					0: p = Vector3(bx + t, 0.15, bz + 0.6)
					1: p = Vector3(bx + t, 0.15, bz + block_size - 0.6)
					2:
						p = Vector3(bx + 0.6, 0.15, bz + t)
						yaw = PI * 0.5
					_:
						p = Vector3(bx + block_size - 0.6, 0.15, bz + t)
						yaw = PI * 0.5
				var r := rng.randf()
				if r < 0.3:
					hyd.append(Transform3D(Basis(), p + Vector3(0, 0.37, 0)))
				elif r < 0.6:
					bins.append(Transform3D(Basis(), p + Vector3(0, 0.47, 0)))
				elif r < 0.8:
					benches.append(Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0.22, 0)))
	_multimesh(hydrant, hyd)
	_multimesh(bin, bins)
	_multimesh(bench, benches)


func _build_trees() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.18
	trunk.height = 3.0
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.3, 0.22, 0.15)
	trunk.material = bark
	var crown := SphereMesh.new()
	crown.radius = 1.6
	crown.height = 2.8
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.25, 0.38, 0.18)
	leaf.roughness = 0.9
	crown.material = leaf
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	for i in range(blocks):
		for j in range(blocks):
			if not districts[Vector2i(i, j)] in [District.DOWNTOWN, District.MIDTOWN, District.INDUSTRIAL]:
				continue   # the other districts plant their own trees
			if rng.randf() < 0.45:
				continue
			var bx := x0 + street_width + i * period
			var bz := z0 + street_width + j * period
			var side := rng.randi_range(0, 3)
			for k in range(4):
				var t := (k + 1) / 5.0 * block_size
				var p: Vector3
				match side:
					0: p = Vector3(bx + t, 0, bz + 1.4)
					1: p = Vector3(bx + t, 0, bz + block_size - 1.4)
					2: p = Vector3(bx + 1.4, 0, bz + t)
					_: p = Vector3(bx + block_size - 1.4, 0, bz + t)
				var sc := rng.randf_range(0.85, 1.2)
				trunks.append(Transform3D(Basis().scaled(Vector3.ONE * sc), p + Vector3(0, 1.65 * sc, 0)))
				crowns.append(Transform3D(Basis().scaled(Vector3.ONE * sc), p + Vector3(0, 4.0 * sc, 0)))
	for t in _scatter_trees:
		var sc: float = t.basis.get_scale().x
		trunks.append(Transform3D(Basis().scaled(Vector3.ONE * sc), t.origin + Vector3(0, 1.65 * sc, 0)))
		crowns.append(Transform3D(Basis().scaled(Vector3.ONE * sc), t.origin + Vector3(0, 4.0 * sc, 0)))
	_multimesh(trunk, trunks, 600.0)
	_multimesh(crown, crowns, 600.0)


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], fade_at := 0.0) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if fade_at > 0.0:
		mmi.visibility_range_end = fade_at   # small props vanish in the distance
		mmi.visibility_range_end_margin = 30.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)


func _place_cars() -> void:
	var cars := Node3D.new()
	cars.name = "Cars"
	add_child(cars)
	var placed: Array[Vector3] = []
	# a few right in front of the start so the first landing has something to throw around
	for p in [Vector3(2.4, 0, -20), Vector3(-5.4, 0, -27), Vector3(5.4, 0, -34), Vector3(-2.4, 0, -42)]:
		_spawn_car(cars, spawn_point * Vector3(1, 0, 1) + p, false)
		placed.append(spawn_point * Vector3(1, 0, 1) + p)
	var tries := 0
	while placed.size() < car_count and tries < car_count * 20:
		tries += 1
		var along_x := rng.randf() < 0.5
		var s_idx := rng.randi_range(0, blocks)
		var b_idx := rng.randi_range(0, blocks - 1)
		var line := street_x(s_idx) if not along_x else street_z(s_idx)
		var t := x0 + street_width + b_idx * period + rng.randf_range(4.0, block_size - 4.0)
		var lanes := [-5.4, -2.4, 2.4, 5.4]
		var lane: float = lanes[rng.randi_range(0, 3)]
		var pos := Vector3(t, 0, line + lane) if along_x else Vector3(line + lane, 0, t)
		if pos.distance_to(spawn_point * Vector3(1, 0, 1)) < 10.0:
			continue
		if district_at(pos) == District.FARM and rng.randf() < 0.85:
			continue   # country roads stay quiet
		var ok := true
		for q in placed:
			if q.distance_to(pos) < 6.0:
				ok = false
				break
		if not ok:
			continue
		placed.append(pos)
		_spawn_car(cars, pos, along_x)


func _spawn_car(parent: Node, pos: Vector3, along_x: bool) -> RigidBody3D:
	var car := RigidBody3D.new()
	car.set_script(CAR_SCRIPT)
	car.position = pos + Vector3(0, 0.05, 0)
	car.rotation.y = (PI * 0.5 if along_x else 0.0) + rng.randf_range(-0.06, 0.06) + (PI if rng.randf() < 0.5 else 0.0)
	car.set("color_index", rng.randi_range(0, 7))
	parent.add_child(car)
	return car


func spawn_car_at(pos: Vector3, yaw: float, color := -1) -> RigidBody3D:
	var parent := get_node_or_null("Cars")
	if parent == null:
		parent = self
	var car := RigidBody3D.new()
	car.set_script(CAR_SCRIPT)
	car.position = pos
	car.rotation.y = yaw
	car.set("color_index", color if color >= 0 else rng.randi_range(0, 7))
	parent.add_child(car)
	return car


# ------------------------------------------------------------------ navigation

func _bake_navigation(total: float) -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.5
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nm.region_min_size = 4.0
	var half := total * 0.5 + 4.0
	nm.filter_baking_aabb = AABB(Vector3(-half, -1.0, -half), Vector3(half * 2.0, 4.0, half * 2.0))
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, nm.cell_height)
	var t0 := Time.get_ticks_msec()
	NavigationServer3D.bake_from_source_geometry_data(nm, _nav_source)
	nav_region = NavigationRegion3D.new()
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	nav_ready = true
	print("Navigation baked in %d ms (%d polygons)" % [Time.get_ticks_msec() - t0, nm.get_polygon_count()])


func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not nav_ready:
		return PackedVector3Array([to])
	var map := get_world_3d().navigation_map
	return NavigationServer3D.map_get_path(map, from, to, true)


func closest_nav_point(p: Vector3) -> Vector3:
	if not nav_ready:
		return p
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)


# ------------------------------------------------------------------ queries

func street_x(i: int) -> float:
	return x0 + i * period + street_width * 0.5


func street_z(j: int) -> float:
	return z0 + j * period + street_width * 0.5


func city_half_size() -> float:
	return (blocks * period + street_width) * 0.5


func intersection_pos(cell: Vector2i) -> Vector3:
	return Vector3(street_x(cell.x), 0, street_z(cell.y))


func nearest_intersection(p: Vector3) -> Vector2i:
	var i := clampi(roundi((p.x - x0 - street_width * 0.5) / period), 0, blocks)
	var j := clampi(roundi((p.z - z0 - street_width * 0.5) / period), 0, blocks)
	return Vector2i(i, j)


func is_inside_building(p: Vector3, margin := 0.5) -> bool:
	var key := Vector2i(floori(p.x / period), floori(p.z / period))
	if not _bgrid.has(key):
		return false
	for idx in _bgrid[key]:
		var a: AABB = buildings[idx]["aabb"]
		if p.x > a.position.x - margin and p.x < a.end.x + margin and p.z > a.position.z - margin \
				and p.z < a.end.z + margin and p.y < a.end.y + 0.5 and p.y > a.position.y - 1.0:
			return true
	return false


func street_name_at(p: Vector3) -> String:
	var cell := nearest_intersection(p)
	var dx := absf(p.x - street_x(cell.x))
	var dz := absf(p.z - street_z(cell.y))
	if dx < dz:
		return AVENUE_NAMES[cell.x % AVENUE_NAMES.size()]
	return STREET_NAMES[cell.y % STREET_NAMES.size()]


func location_name(p: Vector3) -> String:
	var cell := nearest_intersection(p)
	return "%s & %s" % [AVENUE_NAMES[cell.x % AVENUE_NAMES.size()], STREET_NAMES[cell.y % STREET_NAMES.size()]]


func random_sidewalk_point(near: Vector3, min_d: float, max_d: float) -> Vector3:
	for attempt in 30:
		var ang := randf() * TAU
		var dist := randf_range(min_d, max_d)
		var guess := near + Vector3(cos(ang), 0, sin(ang)) * dist
		var i := clampi(int(floor((guess.x - x0 - street_width) / period)), 0, blocks - 1)
		var j := clampi(int(floor((guess.z - z0 - street_width) / period)), 0, blocks - 1)
		var bx := x0 + street_width + i * period
		var bz := z0 + street_width + j * period
		var t := randf_range(1.0, block_size - 1.0)
		var off := randf_range(0.8, 2.6)
		var p: Vector3
		match randi() % 4:
			0: p = Vector3(bx + t, 0.2, bz + off)
			1: p = Vector3(bx + t, 0.2, bz + block_size - off)
			2: p = Vector3(bx + off, 0.2, bz + t)
			_: p = Vector3(bx + block_size - off, 0.2, bz + t)
		var d := p.distance_to(near)
		if d >= min_d * 0.8 and d <= max_d * 1.3 and not is_inside_building(p, 0.6) and not in_base(p):
			return p
	# fallback: snap to the street, never to the height of whatever "near" is (a rooftop!)
	return closest_nav_point(Vector3(near.x + randf_range(-5, 5), 0.2, near.z + randf_range(-5, 5)))


func random_street_point(near: Vector3, min_d: float, max_d: float) -> Vector3:
	for attempt in 30:
		var ang := randf() * TAU
		var guess := near + Vector3(cos(ang), 0, sin(ang)) * randf_range(min_d, max_d)
		var cell := nearest_intersection(guess)
		var p: Vector3
		if randf() < 0.5:
			p = Vector3(street_x(cell.x) + randf_range(-6, 6), 0.2, guess.z)
		else:
			p = Vector3(guess.x, 0.2, street_z(cell.y) + randf_range(-6, 6))
		var h := city_half_size() - 2.0
		p.x = clampf(p.x, -h, h)
		p.z = clampf(p.z, -h, h)
		var d := p.distance_to(near)
		if d >= min_d * 0.7 and d <= max_d * 1.4 and not is_inside_building(p, 0.5):
			return p
	return closest_nav_point(near)


func random_roof_point(near: Vector3, min_d := 0.0, max_d := 99999.0) -> Vector3:
	var candidates: Array[Vector3] = []
	var h := city_half_size()
	for b in buildings:
		var a: AABB = b["aabb"]
		var c := a.get_center()
		if absf(c.x) > h or absf(c.z) > h:
			continue
		var top := Vector3(a.position.x + 1.6, a.end.y + 1.2, a.position.z + 1.6)
		var d := Vector2(top.x - near.x, top.z - near.z).length()
		if d >= min_d and d <= max_d:
			candidates.append(top)
	if candidates.is_empty():
		return spawn_point + Vector3(0, 60, 0)
	return candidates[randi() % candidates.size()]


# ------------------------------------------------------------------ districts

var _grass_mat: StandardMaterial3D
var _lot_mat: StandardMaterial3D
var _drive_mat: StandardMaterial3D
var _house_roofs: Array[StandardMaterial3D] = []
var _field_mat: ShaderMaterial
var _plain_mats := {}
# small things gathered while building, drawn at the end as one multimesh each
var _scatter_trees: Array[Transform3D] = []
var _scatter := {}   # name -> {mesh, xforms}


func _tex_mat(tex: String, tint: Color, metres: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = load(TEX + tex + "/color.jpg")
	m.normal_enabled = true
	m.normal_texture = load(TEX + tex + "/normal.jpg")
	m.roughness_texture = load(TEX + tex + "/roughness.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / metres
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _plain(col: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [col.to_html(), rough, metal]
	if not _plain_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.metallic = metal
		_plain_mats[key] = m
	return _plain_mats[key]


func _district_rule(i: int, j: int) -> int:
	var c := (blocks - 1) * 0.5
	var dx := i - c
	var dz := j - c
	var r := maxf(absf(dx), absf(dz))
	if r < 3.0:
		return District.DOWNTOWN
	if r < 5.0:
		return District.MIDTOWN
	if dz <= -5.0:
		return District.FARM
	if dx >= 5.0:
		return District.INDUSTRIAL
	return District.SUBURB


func _assign_districts() -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = city_seed + 7
	var mid := blocks / 2
	for i in range(-backdrop_ring, blocks + backdrop_ring):
		for j in range(-backdrop_ring, blocks + backdrop_ring):
			var d := _district_rule(i, j)
			# a few midtown blocks are parks (never the ones you start next to)
			if d == District.MIDTOWN and prng.randf() < 0.14 and absi(i - mid) + absi(j - mid) > 4:
				d = District.PARK
			districts[Vector2i(i, j)] = d
	districts[base_cell] = District.INDUSTRIAL


func district_at(p: Vector3) -> int:
	var i := floori((p.x - x0 - street_width) / period)
	var j := floori((p.z - z0 - street_width) / period)
	return districts.get(Vector2i(i, j), District.FARM)


func district_name_at(p: Vector3) -> String:
	return DISTRICT_NAMES[district_at(p)]


## One pixel per block (including the outer ring): the road shader reads it to switch to country
## roads in farmland and quieter streets in the suburbs.
func _district_texture() -> ImageTexture:
	var n := blocks + backdrop_ring * 2
	var img := Image.create(n, n, false, Image.FORMAT_R8)
	for i in n:
		for j in n:
			var d: int = districts.get(Vector2i(i - backdrop_ring, j - backdrop_ring), District.FARM)
			img.set_pixel(i, j, Color(d / 8.0, 0, 0))
	return ImageTexture.create_from_image(img)


## Traffic lights only where the city is: downtown, midtown, parks and industry.
func _is_urban_corner(i: int, j: int) -> bool:
	for c in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
		if districts.get(c, District.FARM) in [District.DOWNTOWN, District.MIDTOWN, District.PARK, District.INDUSTRIAL]:
			return true
	return false


func _scatter_add(key: String, mesh: Mesh, xf: Transform3D) -> void:
	if not _scatter.has(key):
		_scatter[key] = {"mesh": mesh, "xforms": [] as Array[Transform3D]}
	(_scatter[key]["xforms"] as Array[Transform3D]).append(xf)


func _flush_scatter() -> void:
	for key in _scatter:
		_multimesh(_scatter[key]["mesh"], _scatter[key]["xforms"], 260.0)
	_scatter.clear()


## A box-shaped building in the suburbs, industry or on a farm, drawn by building.gdshader `style`.
func _small_building(parent: Node, size: Vector3, centre: Vector3, style: float, paint: Color) -> StaticBody3D:
	var body := _add_box(size, centre + Vector3(0, size.y * 0.5, 0), building_mats[0], Game.LAYER_WORLD, parent, true)
	body.add_to_group("buildings")
	var mi := body.get_child(1) as MeshInstance3D
	mi.set_instance_shader_parameter("style", style)
	mi.set_instance_shader_parameter("paint", paint)
	mi.set_instance_shader_parameter("seed", rng.randf())
	mi.set_instance_shader_parameter("tint", rng.randf_range(-0.5, 0.5))
	var aabb := AABB(centre - Vector3(size.x, 0, size.z) * 0.5, size)
	buildings.append({"aabb": aabb, "height": centre.y + size.y})
	return body


## A gable roof you can stand on, ridge along the longer side.
func _gable_roof(parent: Node, size: Vector3, top_centre: Vector3, rise: float, mat: Material) -> void:
	var along_x := size.x >= size.z
	var prism := PrismMesh.new()
	prism.size = Vector3((size.z if along_x else size.x) + 0.8, rise, (size.x if along_x else size.z) + 0.8)
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	body.position = top_centre + Vector3(0, rise * 0.5, 0)
	if along_x:
		body.rotation.y = PI * 0.5
	var shape := CollisionShape3D.new()
	shape.shape = prism.create_convex_shape()
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.mesh = prism
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	buildings[buildings.size() - 1]["height"] = top_centre.y + rise


const PAINTS := [Color(0.95, 0.93, 0.86), Color(0.82, 0.88, 0.92), Color(0.93, 0.85, 0.7), Color(0.78, 0.85, 0.74),
	Color(0.9, 0.78, 0.74), Color(0.7, 0.72, 0.75), Color(0.98, 0.95, 0.75), Color(0.6, 0.66, 0.72)]


## Suburbs: two rows of houses facing the streets, lawns, driveways, back-yard fences and trees.
func _build_suburb(bx: float, bz: float) -> void:
	var block := Node3D.new()
	add_child(block)
	_add_box(Vector3(block_size, 0.15, block_size), Vector3(bx + block_size * 0.5, 0.075, bz + block_size * 0.5),
		_sidewalk_mat, Game.LAYER_WORLD, block, true)
	var lawn := block_size - 4.4
	_add_box(Vector3(lawn, 0.04, lawn), Vector3(bx + block_size * 0.5, 0.17, bz + block_size * 0.5), _grass_mat,
		Game.LAYER_WORLD, block, true)
	_house_row(block, bx, bz, false)
	_house_row(block, bx, bz, true, true)
	# a fence down the middle between the back yards
	var fence := BoxMesh.new()
	fence.size = Vector3(1.0, 1.1, 0.06)
	fence.material = _plain(Color(0.92, 0.91, 0.87))
	var mz := bz + block_size * 0.5
	for k in 18:
		var x := bx + 3.0 + k * (block_size - 6.0) / 18.0
		_scatter_add("fence", fence, Transform3D(Basis().scaled(Vector3((block_size - 6.0) / 18.0, 1, 1)), Vector3(x + 1.0, 0.75, mz)))


## A row of three houses along one side of a block, set back behind front lawns.
func _house_row(parent: Node, bx: float, bz: float, far_side: bool, with_cars := false) -> void:
	var inner := block_size - 4.4
	var lot_w := inner / 3.0
	for k in 3:
		var w := rng.randf_range(8.5, 11.0)
		var d := rng.randf_range(7.5, 9.5)
		var floors := 1 if rng.randf() < 0.45 else 2
		var h := 3.1 * floors + 0.3
		var setback := rng.randf_range(5.0, 6.5)
		var cx := bx + 2.2 + (k + 0.5) * lot_w + rng.randf_range(-0.8, 0.8)
		var cz := bz + 2.2 + setback + d * 0.5
		if far_side:
			cz = bz + block_size - 2.2 - setback - d * 0.5
		var paint: Color = PAINTS[rng.randi_range(0, PAINTS.size() - 1)]
		_small_building(parent, Vector3(w, h, d), Vector3(cx, 0.19, cz), 1.0, paint)
		_gable_roof(parent, Vector3(w, h, d), Vector3(cx, 0.19 + h, cz), rng.randf_range(2.2, 3.2),
			_house_roofs[rng.randi_range(0, _house_roofs.size() - 1)])
		# a driveway beside the house, out to the street
		var dx := cx + (w * 0.5 + 1.8) * (1.0 if rng.randf() < 0.5 else -1.0)
		var drive_len := setback + d + 2.2
		var drive_c := Vector3(dx, 0.2, (bz + drive_len * 0.5) if not far_side else (bz + block_size - drive_len * 0.5))
		var drive := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(3.0, 0.03, drive_len)
		drive.mesh = dm
		drive.material_override = _drive_mat
		drive.position = drive_c
		parent.add_child(drive)
		if with_cars and rng.randf() < 0.4:
			spawn_car_at(Vector3(dx, 0.3, drive_c.z), 0.0 if rng.randf() < 0.5 else PI)
		# a garden tree behind the house
		var tz := cz + (d * 0.5 + rng.randf_range(3.0, 6.0)) * (1.0 if not far_side else -1.0)
		_scatter_trees.append(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)),
			Vector3(cx + rng.randf_range(-3, 3), 0.19, tz)))


## Industry: concrete lots with warehouses, stacked shipping containers, tanks and chimneys.
func _build_industrial(bx: float, bz: float) -> void:
	var block := Node3D.new()
	add_child(block)
	_add_box(Vector3(block_size, 0.15, block_size), Vector3(bx + block_size * 0.5, 0.075, bz + block_size * 0.5),
		_lot_mat, Game.LAYER_WORLD, block, true)
	var split := rng.randf() < 0.45
	if split:
		_warehouse(block, Rect2(bx + 3, bz + 3, block_size - 6, block_size * 0.5 - 4))
	else:
		_warehouse(block, Rect2(bx + 3, bz + 3, block_size * 0.62, block_size - 6))
	# the yard: containers and tanks
	var yard := Rect2(bx + 4, bz + block_size * 0.5 + 2, block_size - 8, block_size * 0.5 - 6) if split \
		else Rect2(bx + block_size * 0.62 + 5, bz + 4, block_size * 0.38 - 9, block_size - 8)
	var colours := [Color(0.65, 0.18, 0.12), Color(0.15, 0.3, 0.55), Color(0.2, 0.45, 0.25), Color(0.85, 0.5, 0.1),
		Color(0.5, 0.5, 0.52)]
	var stacks := rng.randi_range(2, 4)
	for k in stacks:
		var along_x := yard.size.x > yard.size.y
		var c := Vector3(yard.position.x + rng.randf_range(3.5, yard.size.x - 3.5), 0.15,
			yard.position.y + rng.randf_range(3.5, yard.size.y - 3.5))
		var size := Vector3(6.1, 2.6, 2.44) if along_x else Vector3(2.44, 2.6, 6.1)
		for level in rng.randi_range(1, 3):
			var box := _add_box(size, c + Vector3(0, 1.3 + level * 2.6, 0), _plain(colours[rng.randi_range(0, 4)], 0.6, 0.4),
				Game.LAYER_WORLD, block, level == 0)
			box.add_to_group("buildings")
		buildings.append({"aabb": AABB(c - Vector3(size.x, 0, size.z) * 0.5, Vector3(size.x, 2.6, size.z)), "height": 2.75})
	if rng.randf() < 0.5:
		var tc := Vector3(yard.get_center().x, 0.15, yard.get_center().y)
		_add_cylinder(3.2, 7.5, tc + Vector3(0, 3.75, 0), _plain(Color(0.75, 0.76, 0.78), 0.35, 0.7), block)
		buildings.append({"aabb": AABB(tc - Vector3(3.2, 0, 3.2), Vector3(6.4, 7.5, 6.4)), "height": 7.65})


func _warehouse(parent: Node, lot: Rect2) -> void:
	var h := rng.randf_range(8.0, 12.0)
	var size := Vector3(lot.size.x, h, lot.size.y)
	var centre := Vector3(lot.get_center().x, 0.15, lot.get_center().y)
	var paints := [Color(0.75, 0.76, 0.78), Color(0.55, 0.62, 0.72), Color(0.78, 0.72, 0.6), Color(0.5, 0.58, 0.5),
		Color(0.72, 0.45, 0.35)]
	_small_building(parent, size, centre, 2.0, paints[rng.randi_range(0, paints.size() - 1)])
	if rng.randf() < 0.35:
		# a brick chimney
		var cp := centre + Vector3(size.x * 0.3, 0, -size.z * 0.3)
		_add_cylinder(1.1, h + 14.0, cp + Vector3(0, (h + 14.0) * 0.5, 0), _plain(Color(0.45, 0.22, 0.16)), parent)


## Farmland: a crop field with fences, and now and then a farmyard with a barn, silo and hay bales.
func _build_farm(bx: float, bz: float) -> void:
	_field(bx, bz, true)
	var yard := rng.randf() < 0.3
	if yard:
		var c := Vector3(bx + rng.randf_range(12, block_size - 12), 0.15, bz + rng.randf_range(12, block_size - 12))
		var size := Vector3(12.0, 6.5, 18.0) if rng.randf() < 0.5 else Vector3(18.0, 6.5, 12.0)
		_small_building(self, size, c, 3.0, Color(1, 1, 1))
		_gable_roof(self, size, c + Vector3(0, size.y, 0), 4.0, _plain(Color(0.25, 0.25, 0.27), 0.6, 0.5))
		var sc := c + Vector3(size.x * 0.5 + 4.5, 0, 0)
		_add_cylinder(2.6, 15.0, sc + Vector3(0, 7.5, 0), _plain(Color(0.78, 0.79, 0.8), 0.35, 0.7), self)
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 2.6
		sm.height = 2.6
		sm.is_hemisphere = true
		dome.mesh = sm
		dome.material_override = _plain(Color(0.78, 0.79, 0.8), 0.35, 0.7)
		dome.position = sc + Vector3(0, 15.0, 0)
		add_child(dome)
		buildings.append({"aabb": AABB(sc - Vector3(2.6, 0, 2.6), Vector3(5.2, 17.6, 5.2)), "height": 17.6})
	# hay bales lying in the field
	var bale := CylinderMesh.new()
	bale.top_radius = 0.75
	bale.bottom_radius = 0.75
	bale.height = 1.3
	bale.material = _plain(Color(0.82, 0.68, 0.36), 0.95)
	if rng.randf() < 0.5:
		for k in rng.randi_range(3, 8):
			var p := Vector3(bx + rng.randf_range(4, block_size - 4), 0.9, bz + rng.randf_range(4, block_size - 4))
			_scatter_add("bale", bale, Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, rng.randf() * PI), p))
	# a fence round the field: posts and two rails
	var post := BoxMesh.new()
	post.size = Vector3(0.15, 1.2, 0.15)
	post.material = _plain(Color(0.38, 0.27, 0.18))
	var rail := BoxMesh.new()
	rail.size = Vector3(3.0, 0.08, 0.06)
	rail.material = _plain(Color(0.45, 0.33, 0.22))
	var inset := 1.2
	var corners := [Vector3(bx + inset, 0, bz + inset), Vector3(bx + block_size - inset, 0, bz + inset),
		Vector3(bx + block_size - inset, 0, bz + block_size - inset), Vector3(bx + inset, 0, bz + block_size - inset)]
	for side in 4:
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[(side + 1) % 4]
		var n := int((a.distance_to(b)) / 3.0)
		var dir := (b - a).normalized()
		var yaw := atan2(-dir.z, dir.x)
		for k in n:
			if side == 0 and k == n / 2:
				continue   # a gate gap
			var pp := a + dir * (k * 3.0)
			_scatter_add("post", post, Transform3D(Basis(), pp + Vector3(0, 0.75, 0)))
			for ry in [0.55, 1.0]:
				_scatter_add("rail", rail, Transform3D(Basis(Vector3.UP, yaw), pp + dir * 1.5 + Vector3(0, ry + 0.15, 0)))
	if rng.randf() < 0.35:
		_tree_line(Vector3(bx, 0, bz + block_size - 3.0), Vector3(1, 0, 0), block_size)


func _field(bx: float, bz: float, nav: bool) -> void:
	var body := _add_box(Vector3(block_size, 0.15, block_size), Vector3(bx + block_size * 0.5, 0.075, bz + block_size * 0.5),
		_field_mat, Game.LAYER_WORLD, self, nav)
	var mi := body.get_child(1) as MeshInstance3D
	mi.set_instance_shader_parameter("kind", float(rng.randi_range(0, 3)))
	mi.set_instance_shader_parameter("rows_x", 1.0 if rng.randf() < 0.5 else 0.0)


func _tree_line(from: Vector3, dir: Vector3, length: float) -> void:
	var n := int(length / 5.0)
	for k in n:
		var p := from + dir * (k * 5.0 + rng.randf_range(0, 2.5)) + Vector3(rng.randf_range(-1, 1), 0.15, rng.randf_range(-1, 1))
		_scatter_trees.append(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.9, 1.5)), p))


## A park: lawn, crossing paths, trees, benches and a fountain in the middle.
func _build_park(bx: float, bz: float) -> void:
	var block := Node3D.new()
	add_child(block)
	var c := Vector3(bx + block_size * 0.5, 0, bz + block_size * 0.5)
	_add_box(Vector3(block_size, 0.15, block_size), c + Vector3(0, 0.075, 0), _sidewalk_mat, Game.LAYER_WORLD, block, true)
	var lawn := block_size - 4.0
	_add_box(Vector3(lawn, 0.04, lawn), c + Vector3(0, 0.17, 0), _grass_mat, Game.LAYER_WORLD, block, true)
	for along_x in [true, false]:
		var path := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(lawn, 0.03, 3.2) if along_x else Vector3(3.2, 0.03, lawn)
		path.mesh = pm
		path.material_override = _sidewalk_mat
		path.position = c + Vector3(0, 0.2, 0)
		block.add_child(path)
	_add_cylinder(4.0, 0.7, c + Vector3(0, 0.5, 0), _plain(Color(0.6, 0.6, 0.58)), block)
	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 3.6
	wm.bottom_radius = 3.6
	wm.height = 0.05
	water.mesh = wm
	water.material_override = _plain(Color(0.2, 0.35, 0.45), 0.05, 0.3)
	water.position = c + Vector3(0, 0.87, 0)
	block.add_child(water)
	_add_cylinder(0.5, 2.5, c + Vector3(0, 1.6, 0), _plain(Color(0.6, 0.6, 0.58)), block)
	for k in 26:
		var p := Vector3(bx + rng.randf_range(4, block_size - 4), 0.19, bz + rng.randf_range(4, block_size - 4))
		if absf(p.x - c.x) < 3.5 or absf(p.z - c.z) < 3.5:
			continue   # keep the paths clear
		_scatter_trees.append(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.9, 1.4)), p))


## Buckets every building by the grid cells it covers, so is_inside_building() only checks neighbours.
func _index_buildings() -> void:
	_bgrid.clear()
	for idx in buildings.size():
		var a: AABB = buildings[idx]["aabb"]
		var m := 1.0
		for i in range(floori((a.position.x - m) / period), floori((a.end.x + m) / period) + 1):
			for j in range(floori((a.position.z - m) / period), floori((a.end.z + m) / period) + 1):
				var key := Vector2i(i, j)
				if not _bgrid.has(key):
					_bgrid[key] = []
				_bgrid[key].append(idx)
