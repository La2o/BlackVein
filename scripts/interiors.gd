extends Node3D
## Enterable buildings. Doors in the city lead to interiors that are generated
## on demand far below the streets (and removed when you leave):
##   - Research labs (3): scientists, guards, specimen tanks, a vault with an
##     Evolution Sample (+1 skill point) and a head scientist with a memory.
##   - Military bunker under the base: armory, barracks, intel terminal.
##   - Infected subway nest: tunnels, infected, hunters and a Hive Heart.
##   - Safehouse: rest (heal, save, skip time), wardrobe, trophy wall.
## Interiors are built on a grid of 4 m cells: rooms are rectangles of cells,
## walls go wherever a cell meets nothing or a different room (except doors).

const NPC := preload("res://scripts/npc.gd")
const PICKUP := preload("res://scripts/pickup.gd")
const HIVE := preload("res://scripts/hive.gd")
const HUMANOID := preload("res://scripts/humanoid.gd")

const CELL := 4.0
const H := 4.6
const DEPTH := -140.0

const TYPES := {
	"lab": {"name": "Origin Biotech Lab", "color": Color(0.3, 0.85, 1.0), "allowed": ["scientist", "soldier", "rocket_soldier", "elite", "commander"]},
	"bunker": {"name": "Military Bunker", "color": Color(1.0, 0.8, 0.2), "allowed": ["soldier", "rocket_soldier", "elite", "commander"]},
	"nest": {"name": "Subway Nest", "color": Color(1.0, 0.25, 0.15), "allowed": []},
	"safehouse": {"name": "Safehouse", "color": Color(0.4, 1.0, 0.5), "allowed": []},
}

const LAB_MEMORIES := [
	"Memory absorbed: the labs are funded by the same people running the quarantine.",
	"Memory absorbed: BLACKVEIN rewrites every cell it touches. They wanted soldiers who heal like you.",
	"Memory absorbed: Patient Zero was moved to a sealed lab under the city.",
]

var entrances: Array[Dictionary] = []   # {id, type, name, pos, normal, color}
var current: Dictionary = {}
var root: Node3D = null
var _return_pos := Vector3.ZERO
var _origin := Vector3.ZERO
var _cells := {}                        # Vector2i -> room name
var _rooms := {}                        # room name -> Rect2i
var _doors := {}                        # "a|b" keys for open edges
var _interactables: Array[Dictionary] = []
var _near: Dictionary = {}
var _allowed: Array = []
var _city: Node3D
var _mats := {}


func _ready() -> void:
	Game.interiors = self
	Game.player_respawned.connect(func():
		if root:
			_teardown())


func is_inside() -> bool:
	return root != null


func return_position() -> Vector3:
	return _return_pos


func restricted_for(pos: Vector3, disguise: String) -> bool:
	if root == null or pos.y > DEPTH + 30.0 or _allowed.is_empty():
		return false
	return not disguise in _allowed


# ------------------------------------------------------------------ city doors

## Called by main.gd after the city is built: picks the buildings with doors.
func setup(city: Node3D) -> void:
	_city = city
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var sp: Vector3 = city.spawn_point
	var mid: int = city.blocks / 2
	# research labs: three blocks spread across the city
	var candidates: Array[Vector2i] = []
	for i in city.blocks:
		for j in city.blocks:
			var cell := Vector2i(i, j)
			if cell == city.base_cell or cell == Vector2i(mid, mid - 1):
				continue
			candidates.append(cell)
	candidates.shuffle()
	var labs: Array[Vector2i] = []
	for c in candidates:
		var p := _block_center(c)
		if p.distance_to(sp) < 90.0:
			continue
		var ok := true
		for l in labs:
			if _block_center(l).distance_to(p) < 170.0:
				ok = false
		if ok:
			labs.append(c)
		if labs.size() == 3:
			break
	for k in labs.size():
		var door := _door_for_block(labs[k])
		if not door.is_empty():
			_add_entrance("lab%d" % k, "lab", door["pos"], door["normal"])
	# safehouse: the block next to where you start
	var home := _door_for_block(Vector2i(mid - 1, mid - 1))
	if not home.is_empty():
		_add_entrance("safehouse", "safehouse", home["pos"], home["normal"])
	# bunker: a door in the base's command building, facing the courtyard
	if city.base_rect.size != Vector2.ZERO:
		var bx: float = city.base_rect.position.x
		var cz: float = city.base_rect.position.y + city.block_size * 0.5
		_add_entrance("bunker", "bunker", Vector3(bx + 12.05, 0.15, cz), Vector3.RIGHT)
	# subway: stairs down on a sidewalk on the far side of the city
	var far_cell := Vector2i(clampi(mid + 2, 0, city.blocks - 1), clampi(mid + 2, 0, city.blocks - 1))
	var corner := _block_origin(far_cell)
	_add_entrance("nest", "nest", Vector3(corner.x + 6.0, 0.15, corner.z + 1.8), Vector3.FORWARD, true)


func _block_origin(c: Vector2i) -> Vector3:
	return Vector3(_city.x0 + _city.street_width + c.x * _city.period, 0, _city.z0 + _city.street_width + c.y * _city.period)


func _block_center(c: Vector2i) -> Vector3:
	return _block_origin(c) + Vector3(_city.block_size * 0.5, 0, _city.block_size * 0.5)


## Door position on the street-facing facade of a ground-floor building in a block.
func _door_for_block(c: Vector2i) -> Dictionary:
	var o := _block_origin(c)
	var bs: float = _city.block_size
	for b in _city.buildings:
		var a: AABB = b["aabb"]
		if absf(a.position.y - 0.15) > 0.05:
			continue
		var cen := a.get_center()
		if cen.x < o.x or cen.x > o.x + bs or cen.z < o.z or cen.z > o.z + bs:
			continue
		var faces := [
			[a.position.z - o.z, Vector3(cen.x, 0.15, a.position.z - 0.06), Vector3.FORWARD],
			[o.z + bs - a.end.z, Vector3(cen.x, 0.15, a.end.z + 0.06), Vector3.BACK],
			[a.position.x - o.x, Vector3(a.position.x - 0.06, 0.15, cen.z), Vector3.LEFT],
			[o.x + bs - a.end.x, Vector3(a.end.x + 0.06, 0.15, cen.z), Vector3.RIGHT],
		]
		faces.sort_custom(func(p, q): return p[0] < q[0])
		return {"pos": faces[0][1], "normal": faces[0][2]}
	return {}


func _add_entrance(id: String, type: String, pos: Vector3, normal: Vector3, stairs := false) -> void:
	var t: Dictionary = TYPES[type]
	var e := {"id": id, "type": type, "name": t["name"], "pos": pos, "normal": normal, "color": t["color"]}
	entrances.append(e)
	var col: Color = t["color"]
	var glow := StandardMaterial3D.new()
	glow.albedo_color = col
	glow.emission_enabled = true
	glow.emission = col
	glow.emission_energy_multiplier = 2.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.025)
	var holder := Node3D.new()
	holder.name = "Door_" + id
	_city.add_child(holder)
	holder.global_position = pos
	holder.basis = Basis.looking_at(-normal, Vector3.UP)   # local +Z = outward
	if stairs:
		# subway stairwell: dark opening in the pavement with railings
		_vis(holder, Vector3(3.0, 0.05, 4.5), Vector3(0, 0.03, 0), dark)
		for side in [-1.0, 1.0]:
			_vis(holder, Vector3(0.1, 1.0, 4.5), Vector3(side * 1.55, 0.5, 0), glow)
		_vis(holder, Vector3(3.2, 1.0, 0.1), Vector3(0, 0.5, -2.25), glow)
		var post := _vis(holder, Vector3(0.15, 3.2, 0.15), Vector3(1.9, 1.6, 2.2), dark)
		post.name = "Post"
		_sign(holder, "SUBWAY", Vector3(1.9, 3.5, 2.2), col)
	else:
		_vis(holder, Vector3(2.6, 3.3, 0.1), Vector3(0, 1.65, 0.02), dark)
		_vis(holder, Vector3(3.0, 0.18, 0.18), Vector3(0, 3.38, 0.08), glow)
		for side in [-1.0, 1.0]:
			_vis(holder, Vector3(0.18, 3.4, 0.18), Vector3(side * 1.4, 1.7, 0.08), glow)
		_sign(holder, str(t["name"]).to_upper(), Vector3(0, 4.1, 0.15), col)


func _vis(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _sign(parent: Node3D, text: String, pos: Vector3, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.01
	l.outline_size = 12
	l.modulate = col
	l.position = pos
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ interaction

func _process(_delta: float) -> void:
	var p: Player = Game.player
	if p == null:
		return
	if root and p.global_position.y > DEPTH + 60.0 and not p.is_dead():
		# you left some other way (unstuck / respawn)
		_teardown()
	_near = {}
	if p.is_dead() or p.vehicle:
		return
	var pos := p.global_position
	if root:
		for it in _interactables:
			if Vector2(pos.x - it["pos"].x, pos.z - it["pos"].z).length() < 2.6 and absf(pos.y - it["pos"].y) < 3.0:
				_near = it
				return
	else:
		for e in entrances:
			var ep: Vector3 = e["pos"]
			if Vector2(pos.x - ep.x, pos.z - ep.z).length() < 3.2 and pos.y < 4.0:
				_near = {"text": "enter " + str(e["name"]), "call": enter.bind(e)}
				return


func prompt() -> String:
	return str(_near.get("text", ""))


## Called by the grab button. Returns true if it opened a door or used something.
func try_interact() -> bool:
	if _near.is_empty():
		return false
	var c: Callable = _near["call"]
	_near = {}
	c.call()
	return true


func entrance_by_id(id: String) -> Dictionary:
	for e in entrances:
		if e["id"] == id:
			return e
	return {}


# ------------------------------------------------------------------ entering / leaving

func enter(e: Dictionary) -> void:
	if root:
		return
	current = e
	_return_pos = Vector3(e["pos"]) + Vector3(e["normal"]) * 3.0 + Vector3.UP * 1.0
	_allowed = TYPES[e["type"]]["allowed"]
	_origin = Vector3(e["pos"].x, DEPTH, e["pos"].z)
	root = Node3D.new()
	root.name = "Interior"
	add_child(root)
	_interactables.clear()
	match e["type"]:
		"lab": _build_lab(e)
		"bunker": _build_bunker(e)
		"nest": _build_nest(e)
		"safehouse": _build_safehouse(e)
	var allies := get_tree().get_nodes_in_group("allies").filter(func(a): return a.global_position.distance_to(Game.player.global_position) < 45.0)
	Game.player.respawn_in_place(_entry_pos() + Vector3.UP * 1.0, -PI * 0.5)
	for a in allies:
		a.global_position = _entry_pos() + Vector3(randf_range(1, 3), 0.6, randf_range(-2, 2))
		a.reset_physics_interpolation()
	Game.say(str(e["name"]).to_upper(), e["color"])
	Game.fx.sound("whoosh", Game.player.global_position, -4.0)
	if not _allowed.is_empty() and not str(Game.player.disguise) in _allowed:
		Game.feed("Restricted area. You'll be noticed without the right disguise.", Color(1, 0.7, 0.4))
	Game.stat_add("interiors")


func leave() -> void:
	if root == null:
		return
	var allies := get_tree().get_nodes_in_group("allies").filter(func(a): return a.global_position.y < DEPTH + 30.0)
	var back := _return_pos
	var e := current
	_teardown()
	Game.player.respawn_in_place(back, atan2(-float(e["normal"].x), -float(e["normal"].z)))
	for a in allies:
		if is_instance_valid(a):
			a.global_position = back + Vector3(randf_range(-3, 3), 0.2, randf_range(-3, 3))
			a.reset_physics_interpolation()
	Game.fx.sound("whoosh", back, -4.0)


func _teardown() -> void:
	if root:
		root.queue_free()
	root = null
	current = {}
	_cells.clear()
	_rooms.clear()
	_doors.clear()
	_interactables.clear()
	_allowed = []
	_near = {}


# ------------------------------------------------------------------ grid builder

func _cell_pos(c: Vector2i) -> Vector3:
	return _origin + Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)


func _room_center(name: String) -> Vector3:
	var r: Rect2i = _rooms[name]
	return _origin + Vector3((r.position.x + r.size.x * 0.5) * CELL, 0.0, (r.position.y + r.size.y * 0.5) * CELL)


func _room_points(name: String) -> Array:
	var r: Rect2i = _rooms[name]
	var out := []
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			out.append(_cell_pos(Vector2i(x, y)) + Vector3.UP * 0.3)
	return out


func _random_in(name: String) -> Vector3:
	var pts := _room_points(name)
	return pts[randi() % pts.size()]


## A random walkable point inside the current interior (used by allies).
func random_floor_point() -> Vector3:
	var keys := _cells.keys()
	if keys.is_empty():
		return _return_pos
	return _cell_pos(keys[randi() % keys.size()]) + Vector3.UP * 0.4


func _entry_pos() -> Vector3:
	return _cell_pos(_entry_cell)


var _entry_cell := Vector2i.ZERO


func _door_key(a: Vector2i, b: Vector2i) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var t := a
		a = b
		b = t
	return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]


func _material(key: String, col: Color, rough := 0.85, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


## Builds floor, ceiling, walls, lights and the navigation mesh for a layout.
## rooms: {name: Rect2i}; doors: [[Vector2i, Vector2i], ...]; theme: colors.
func _build_grid(size: Vector2i, rooms: Dictionary, doors: Array, entry: Vector2i, theme: Dictionary) -> void:
	_rooms = rooms
	_entry_cell = entry
	for name in rooms:
		var r: Rect2i = rooms[name]
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				_cells[Vector2i(x, y)] = name
	for d in doors:
		_doors[_door_key(d[0], d[1])] = true
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	root.add_child(body)
	var wall_mat: Material = _material("wall_" + str(theme["name"]), theme["wall"], 0.9)
	var floor_mat: Material = _material("floor_" + str(theme["name"]), theme["floor"], theme.get("floor_rough", 0.7))
	var ceil_mat: Material = _material("ceil_" + str(theme["name"]), theme["ceiling"], 0.95)
	var nav := NavigationMeshSourceGeometryData3D.new()
	var total := Vector3(size.x * CELL, 0, size.y * CELL)
	_box(body, Vector3(total.x + 2, 1.0, total.z + 2), _origin + Vector3(total.x * 0.5, -0.5, total.z * 0.5), floor_mat)
	_box(body, Vector3(total.x + 2, 1.0, total.z + 2), _origin + Vector3(total.x * 0.5, H + 0.5, total.z * 0.5), ceil_mat)
	var walls: Array[Transform3D] = []
	for c in _cells:
		nav.add_faces(PackedVector3Array([
			_cell_pos(c) + Vector3(-CELL * 0.5, 0, -CELL * 0.5), _cell_pos(c) + Vector3(CELL * 0.5, 0, -CELL * 0.5), _cell_pos(c) + Vector3(CELL * 0.5, 0, CELL * 0.5),
			_cell_pos(c) + Vector3(-CELL * 0.5, 0, -CELL * 0.5), _cell_pos(c) + Vector3(CELL * 0.5, 0, CELL * 0.5), _cell_pos(c) + Vector3(-CELL * 0.5, 0, CELL * 0.5),
		]), Transform3D())
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			var wall := false
			if not _cells.has(n):
				wall = true
			elif _cells[n] != _cells[c] and not _doors.has(_door_key(c, n)) and (c.x < n.x or c.y < n.y):
				wall = true
			if not wall:
				continue
			var sz := Vector3(0.4, H, CELL + 0.4) if d.x != 0 else Vector3(CELL + 0.4, H, 0.4)
			var center := _cell_pos(c) + Vector3(d.x, 0, d.y) * CELL * 0.5 + Vector3.UP * H * 0.5
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = sz
			cs.shape = bs
			cs.position = center
			body.add_child(cs)
			walls.append(Transform3D(Basis().scaled(sz), center))
			var bm := BoxMesh.new()
			bm.size = sz
			nav.add_faces(bm.get_faces(), Transform3D(Basis(), center))
	var unit := BoxMesh.new()
	unit.material = wall_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = unit
	mm.instance_count = walls.size()
	for k in walls.size():
		mm.set_instance_transform(k, walls[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	root.add_child(mmi)
	# a light in every room
	for name in rooms:
		var r: Rect2i = rooms[name]
		var l := OmniLight3D.new()
		l.light_color = theme["light"]
		l.light_energy = theme.get("light_energy", 1.6)
		l.omni_range = maxf(r.size.x, r.size.y) * CELL * 0.9 + 4.0
		l.shadow_enabled = false
		root.add_child(l)
		l.global_position = _room_center(name) + Vector3.UP * (H - 0.7)
		_box(root, Vector3(1.6, 0.08, 0.5), l.global_position + Vector3.UP * 0.62, _material("lamp_" + str(theme["name"]), theme["light"], 0.5, 0.0, 3.0), false)
	# exit door on the entry cell's outer wall
	var exit_pos := _cell_pos(entry) + Vector3(-CELL * 0.5 + 0.25, 0, 0)
	var glow := _material("exit", Color(0.4, 1.0, 0.5), 0.5, 0.0, 2.5)
	_box(root, Vector3(0.1, 3.3, 2.6), exit_pos + Vector3(0, 1.65, 0), _material("dark", Color(0.02, 0.02, 0.025)), false)
	_box(root, Vector3(0.15, 0.15, 3.0), exit_pos + Vector3(0.05, 3.4, 0), glow, false)
	var exit_sign := _sign(root, "EXIT", exit_pos + Vector3(0.2, 3.9, 0), Color(0.4, 1.0, 0.5))
	exit_sign.rotation.y = PI * 0.5
	_interact(exit_pos + Vector3(0.8, 0, 0), "leave", leave)
	# navigation for people inside
	var nm := NavigationMesh.new()
	nm.cell_size = 0.5
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.filter_baking_aabb = AABB(_origin + Vector3(-2, -1, -2), Vector3(total.x + 4, 4, total.z + 4))
	NavigationServer3D.bake_from_source_geometry_data(nm, nav)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nm
	root.add_child(region)


func _box(parent: Node, size: Vector3, center: Vector3, mat: Material, collide := true) -> Node3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = Game.LAYER_WORLD
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		sb.add_child(mi)
		parent.add_child(sb)
		sb.global_position = center
		return sb
	parent.add_child(mi)
	mi.global_position = center
	return mi


func _cyl(parent: Node, radius: float, height: float, center: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	mi.mesh = c
	mi.material_override = mat
	parent.add_child(mi)
	mi.global_position = center
	return mi


func _interact(pos: Vector3, text: String, call: Callable) -> void:
	_interactables.append({"pos": pos, "text": text, "call": call})


func _spawn(kind: String, pos: Vector3, points: Array, extra := {}) -> CharacterBody3D:
	var n := CharacterBody3D.new()
	n.set_script(NPC)
	root.add_child(n)
	n.global_position = pos + Vector3.UP * 0.6
	extra["tag"] = "interior"
	n.setup(kind, extra)
	n.patrol_center = pos
	n.patrol_points = points
	return n


# ------------------------------------------------------------------ layouts

## Shared floor plan for labs and the bunker: an entry hall, a long corridor,
## three big rooms, a small vault and an office.
func _plan_facility(theme: Dictionary) -> void:
	var rooms := {
		"hall": Rect2i(0, 3, 3, 4),
		"corridor": Rect2i(3, 4, 11, 2),
		"room_a": Rect2i(3, 0, 5, 4),
		"room_b": Rect2i(8, 0, 6, 4),
		"room_c": Rect2i(3, 6, 5, 4),
		"vault": Rect2i(8, 6, 3, 4),
		"office": Rect2i(11, 6, 3, 4),
	}
	var doors := [
		[Vector2i(2, 4), Vector2i(3, 4)], [Vector2i(2, 5), Vector2i(3, 5)],
		[Vector2i(5, 3), Vector2i(5, 4)], [Vector2i(10, 3), Vector2i(10, 4)],
		[Vector2i(5, 6), Vector2i(5, 5)], [Vector2i(9, 6), Vector2i(9, 5)], [Vector2i(12, 6), Vector2i(12, 5)],
	]
	_build_grid(Vector2i(14, 10), rooms, doors, Vector2i(0, 4), theme)


func _build_lab(e: Dictionary) -> void:
	_plan_facility({"name": "lab", "wall": Color(0.85, 0.87, 0.9), "floor": Color(0.62, 0.65, 0.68), "floor_rough": 0.35,
		"ceiling": Color(0.9, 0.9, 0.92), "light": Color(0.85, 0.95, 1.0), "light_energy": 1.8})
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.4, 1.0, 0.7, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = Color(0.2, 0.9, 0.5)
	glass.emission_energy_multiplier = 0.8
	var steel := _material("steel", Color(0.55, 0.57, 0.6), 0.35, 0.7)
	var screen := _material("screen", Color(0.2, 0.7, 1.0), 0.3, 0.0, 2.0)
	var body := _material("specimen", Color(0.35, 0.05, 0.05), 0.4)
	for room in ["room_a", "room_b", "room_c"]:
		var r: Rect2i = _rooms[room]
		var c := _room_center(room)
		# lab benches with computers
		for k in 2:
			var z := c.z + (k - 0.5) * 5.0
			_box(root, Vector3(r.size.x * CELL * 0.55, 0.95, 1.1), Vector3(c.x, 0.475, z), steel)
			_box(root, Vector3(0.9, 0.6, 0.08), Vector3(c.x - 1.2, 1.3, z), screen, false)
			_box(root, Vector3(0.9, 0.6, 0.08), Vector3(c.x + 1.4, 1.3, z), screen, false)
		# specimen tanks along the far wall
		var wall_z := _origin.z + r.position.y * CELL + 1.2
		if room == "room_c":
			wall_z = _origin.z + r.end.y * CELL - 1.2
		for k in r.size.x - 1:
			var x := _origin.x + (r.position.x + k + 1) * CELL
			_cyl(root, 0.75, 3.0, Vector3(x, 1.6, wall_z), glass)
			_cyl(root, 0.85, 0.25, Vector3(x, 0.12, wall_z), steel)
			var specimen := MeshInstance3D.new()
			specimen.mesh = HUMANOID.capsule(0.25, 1.4)
			specimen.material_override = body
			root.add_child(specimen)
			specimen.global_position = Vector3(x, 1.6, wall_z)
		for k in 2:
			_spawn("scientist", _random_in(room), _room_points(room))
	# guards
	var guard_pts := _room_points("corridor") + _room_points("hall")
	for k in 3:
		_spawn("soldier", _random_in("corridor"), guard_pts)
	_spawn("elite", _random_in("room_b"), _room_points("room_b") + _room_points("corridor"))
	# vault: the Evolution Sample
	var vc := _room_center("vault")
	_box(root, Vector3(1.2, 1.0, 1.2), vc + Vector3.UP * 0.5, steel)
	if not Game.flags.get("sample_" + str(e["id"]), false):
		var s := Area3D.new()
		s.set_script(PICKUP)
		root.add_child(s)
		s.global_position = vc + Vector3.UP * 1.0
		s.setup("sample", 1)
		s.set_meta("flag", "sample_" + str(e["id"]))
	_spawn("soldier", vc + Vector3(2, 0, 2), _room_points("vault"))
	# office: the head scientist and their memory
	var oc := _room_center("office")
	_box(root, Vector3(2.4, 0.9, 1.0), oc + Vector3(0, 0.45, -2.0), _material("wood", Color(0.35, 0.22, 0.14), 0.6))
	var mem_flag := "lab_mem_" + str(e["id"])
	var idx := entrances.find(e) % LAB_MEMORIES.size()
	var head := _spawn("scientist", oc, _room_points("office"),
		{"memory": "" if Game.flags.get(mem_flag, false) else LAB_MEMORIES[idx]})
	head.label = "Head scientist"
	head.set_meta("memory_flag", mem_flag)


func _build_bunker(_e: Dictionary) -> void:
	_plan_facility({"name": "bunker", "wall": Color(0.36, 0.39, 0.33), "floor": Color(0.3, 0.3, 0.29), "floor_rough": 0.8,
		"ceiling": Color(0.25, 0.26, 0.24), "light": Color(1.0, 0.85, 0.6), "light_energy": 1.5})
	var olive := _material("olive", Color(0.3, 0.33, 0.22), 0.7)
	var steel := _material("steel", Color(0.55, 0.57, 0.6), 0.35, 0.7)
	var screen := _material("screen_red", Color(1.0, 0.3, 0.2), 0.3, 0.0, 2.0)
	# armory: weapon racks and pickups
	var ac := _room_center("room_a")
	for k in 3:
		_box(root, Vector3(3.0, 2.2, 0.6), ac + Vector3((k - 1) * 4.5, 1.1, -6.5), olive)
	for k in 2:
		var p := Area3D.new()
		p.set_script(PICKUP)
		root.add_child(p)
		p.global_position = ac + Vector3((k - 0.5) * 4.0, 0.2, 0)
		p.setup("rifle" if k == 0 else "launcher", 120 if k == 0 else 10)
	# barracks: bunks
	var bc := _room_center("room_b")
	for k in 4:
		_box(root, Vector3(2.2, 0.6, 1.0), bc + Vector3((k - 1.5) * 4.5, 0.3, -5.5), olive)
		_box(root, Vector3(2.2, 0.3, 1.0), bc + Vector3((k - 1.5) * 4.5, 1.6, -5.5), olive)
	# intel room: screens and the terminal
	var ic := _room_center("room_c")
	for k in 3:
		_box(root, Vector3(2.6, 1.6, 0.1), ic + Vector3((k - 1) * 3.0, 2.0, 7.7), screen, false)
	_box(root, Vector3(2.0, 1.0, 1.0), ic + Vector3(0, 0.5, 4.5), steel)
	_interact(ic + Vector3(0, 0, 3.2), "download the intel", _download_intel)
	# holding cells
	var vc := _room_center("vault")
	for k in 5:
		_box(root, Vector3(0.08, H, 0.08), vc + Vector3((k - 2) * 1.0, H * 0.5, -3.5), steel)
	_spawn("civilian", vc + Vector3(0, 0, -5.5), [vc + Vector3(0, 0.3, -5.5)])
	# garrison
	var all_pts := _room_points("corridor") + _room_points("hall") + _room_points("room_a") + _room_points("room_b")
	for k in 5:
		_spawn("soldier", _random_in(["corridor", "room_a", "room_b", "hall"][k % 4]), all_pts)
	_spawn("rocket_soldier", _random_in("room_a"), _room_points("room_a"))
	_spawn("elite", _random_in("room_c"), _room_points("room_c"))
	_spawn("elite", _random_in("office"), _room_points("office") + _room_points("corridor"))


func _download_intel() -> void:
	if Game.flags.get("bunker_intel", false):
		Game.say("Nothing new on the terminal", Color(0.8, 0.8, 0.8))
		return
	Game.flags["bunker_intel"] = true
	if not Game.flags.get("artillery_codes", false):
		Game.flags["artillery_codes"] = true
		Game.feed("Intel: artillery codes downloaded. Artillery Strike can now be unlocked in Skills.", Color(1, 0.85, 0.4))
	Game.add_xp(250, "Military intel")
	Game.say("INTEL DOWNLOADED", Color(1, 0.85, 0.4))
	Game.fx.sound_ui("evolve", -2.0)
	if not str(Game.player.disguise) in Game.MILITARY_DISGUISES:
		Game.raise_alert(Game.player.global_position, "Security breach in the bunker!")


func _build_nest(_e: Dictionary) -> void:
	var rooms := {
		"stairs": Rect2i(0, 3, 2, 2),
		"station": Rect2i(2, 0, 12, 8),
		"heart": Rect2i(14, 1, 4, 6),
	}
	var doors := [
		[Vector2i(1, 3), Vector2i(2, 3)], [Vector2i(1, 4), Vector2i(2, 4)],
		[Vector2i(13, 3), Vector2i(14, 3)], [Vector2i(13, 4), Vector2i(14, 4)],
	]
	_build_grid(Vector2i(18, 8), rooms, doors, Vector2i(0, 3),
		{"name": "nest", "wall": Color(0.22, 0.16, 0.15), "floor": Color(0.18, 0.15, 0.14), "ceiling": Color(0.12, 0.1, 0.1),
		"light": Color(1.0, 0.35, 0.25), "light_energy": 1.4})
	var tile := _material("tile", Color(0.75, 0.72, 0.62), 0.5)
	var flesh := _material("flesh", Color(0.4, 0.05, 0.05), 0.35, 0.0, 0.4)
	var sc := _room_center("station")
	# platform edge, tracks and pillars
	_box(root, Vector3(12 * CELL, 0.5, 0.4), sc + Vector3(0, 0.25, -4.0), tile)
	for k in 2:
		_box(root, Vector3(12 * CELL, 0.12, 0.15), sc + Vector3(0, 0.06, -9.0 - k * 1.5), _material("rail", Color(0.4, 0.38, 0.35), 0.4, 0.8), false)
	for k in 5:
		_box(root, Vector3(0.7, H, 0.7), sc + Vector3((k - 2) * 9.0, H * 0.5, 2.0), tile)
	_sign(root, "CANAL ST", sc + Vector3(0, 3.4, 15.7), Color(0.9, 0.85, 0.7)).rotation.y = PI
	# flesh growing over everything
	for k in 14:
		var blob := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var rr := randf_range(0.6, 1.6)
		sm.radius = rr
		sm.height = rr * 1.4
		blob.mesh = sm
		blob.material_override = flesh
		root.add_child(blob)
		blob.global_position = _random_in("station") + Vector3(randf_range(-1.5, 1.5), -0.3, randf_range(-1.5, 1.5))
	# hives in the station, the Heart in its own chamber
	for k in 2:
		var hv := StaticBody3D.new()
		hv.set_script(HIVE)
		root.add_child(hv)
		hv.global_position = sc + Vector3((k - 0.5) * 22.0, 0, 6.0)
		hv.setup({"tag": "interior"})
	var heart := StaticBody3D.new()
	heart.set_script(HIVE)
	root.add_child(heart)
	heart.global_position = _room_center("heart")
	heart.setup({"tag": "interior"})
	heart.hp = 2600.0
	heart.max_hp = 2600.0
	heart.set_meta("heart", true)
	heart.tree_exiting.connect(_on_heart_destroyed.bind(heart))
	var pts := _room_points("station")
	for k in 10:
		_spawn("infected", _random_in("station"), pts)
	_spawn("hunter", _room_center("heart") + Vector3(-3, 0, 0), _room_points("heart"))
	if Game.level >= 10:
		_spawn("hunter", _random_in("station"), pts)


func _on_heart_destroyed(heart: Node) -> void:
	if not is_instance_valid(heart) or not heart.destroyed:
		return
	Game.stat_add("hive_hearts")
	Game.add_xp(450, "Hive Heart destroyed")
	Game.say("THE HIVE HEART IS DEAD", Color(1, 0.6, 0.3))
	if not Game.flags.get("sample_nest", false):
		Game.flags["sample_nest"] = true
		Game.skill_points += 1
		Game.feed("You absorbed a mutation from the Heart: +1 skill point", Color(0.7, 1, 0.6))
		Game.xp_changed.emit()


func _build_safehouse(_e: Dictionary) -> void:
	var rooms := {"living": Rect2i(0, 0, 4, 4), "bedroom": Rect2i(4, 0, 3, 4)}
	_build_grid(Vector2i(7, 4), rooms, [[Vector2i(3, 1), Vector2i(4, 1)], [Vector2i(3, 2), Vector2i(4, 2)]], Vector2i(0, 2),
		{"name": "safehouse", "wall": Color(0.55, 0.38, 0.3), "floor": Color(0.42, 0.3, 0.2), "floor_rough": 0.6,
		"ceiling": Color(0.75, 0.72, 0.68), "light": Color(1.0, 0.8, 0.55), "light_energy": 1.4})
	var wood := _material("wood", Color(0.35, 0.22, 0.14), 0.6)
	var fabric := _material("fabric", Color(0.5, 0.1, 0.1), 0.9)
	var lc := _room_center("living")
	_box(root, Vector3(3.0, 0.8, 1.2), lc + Vector3(0, 0.4, 5.0), fabric)                 # couch
	_box(root, Vector3(2.4, 1.3, 0.12), lc + Vector3(0, 1.4, -7.6), _material("tv", Color(0.1, 0.4, 0.6), 0.2, 0.0, 1.2), false)
	_box(root, Vector3(1.6, 2.4, 0.8), lc + Vector3(6.5, 1.2, -7.0), wood)                 # wardrobe
	_interact(lc + Vector3(6.5, 0, -5.4), "open your wardrobe", func(): Game.hud.open_wardrobe())
	var bc := _room_center("bedroom")
	_box(root, Vector3(2.2, 0.6, 3.2), bc + Vector3(0, 0.3, -4.5), fabric)                # bed
	_interact(bc + Vector3(0, 0, -2.2), "rest (heal, save, let 8 hours pass)", _rest)
	# trophy wall
	var mins := int(Game.play_time / 60.0)
	var txt := "LEVEL %d\nSoldiers %d   Infected %d\nConsumed %d   Allies branded %d\nEvents %d   Bosses %d\nDisguises %d   Played %dh %02dm" % [
		Game.level, int(Game.kills.get("military", 0)), int(Game.kills.get("infected", 0)), Game.stat("consumes"),
		Game.stat("brands"), Game.stat("events"), Game.stat("bosses"), Game.disguises.size(), mins / 60, mins % 60]
	var board := _sign(root, txt, lc + Vector3(-7.6, 2.4, 0), Color(1, 0.85, 0.6))
	board.font_size = 40
	board.rotation.y = PI * 0.5


func _rest() -> void:
	if Game.is_hunted():
		Game.say("You can't rest while they're hunting you", Color(1, 0.6, 0.5))
		return
	var p: Player = Game.player
	p.heal(p.max_health)
	p.biomass = p.max_biomass
	Game.set_alert(Game.Alert.HIDDEN)
	Game.heat = 0.0
	if Game.daynight:
		Game.daynight.hour = fmod(Game.daynight.hour + 8.0, 24.0)
	Game.save_game(true)
	Game.say("You rest. It's now %s." % (Game.daynight.time_text() if Game.daynight else ""), Color(0.8, 0.9, 1))
	Game.fx.sound_ui("evolve", -6.0)


# ------------------------------------------------------------------ map support

## World-space rectangles of the interior's floor cells (for the minimap).
func map_cells() -> Array:
	var out := []
	for c in _cells:
		out.append(Rect2(_origin.x + c.x * CELL, _origin.z + c.y * CELL, CELL, CELL))
	return out
