extends Node3D
## Viral Caches: 60 clusters of glowing biomass hidden around the map, on skyscraper and house roofs,
## warehouses, barns, silos and in parks. Each gives XP and biomass; every 10 found is a skill point.
## Found caches are remembered in the save (Game.flags["caches"]).

const COUNT := 60
const PICKUP_RADIUS := 2.6

var caches: Array[Node3D] = []
var _mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _t := 0.0


func setup(city: City) -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.08, 0.01, 0.01)
	_mat.metallic = 0.3
	_mat.roughness = 0.3
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(1, 0.15, 0.08)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1, 0.15, 0.08)
	_core_mat.emission_energy_multiplier = 3.0
	var rng := RandomNumberGenerator.new()
	rng.seed = city.city_seed + 61
	var spots := _candidate_spots(city, rng)
	var found: Array = Game.flags.get("caches", [])
	for k in mini(COUNT, spots.size()):
		if found.has(k):
			continue
		_make_cache(k, spots[k])


## Rooftops of all kinds plus park lawns, spread out so no two are close together.
func _candidate_spots(city: City, rng: RandomNumberGenerator) -> Array[Vector3]:
	var pool: Array[Vector3] = []
	var h := city.city_half_size() - 6.0
	for b in city.buildings:
		var a: AABB = b["aabb"]
		var c := a.get_center()
		if absf(c.x) > h or absf(c.z) > h or city.in_base(c):
			continue
		var top: float = b["height"]
		pool.append(Vector3(c.x, top + 1.3, c.z))
	for cell in city.districts:
		var cc: Vector2i = cell
		if city.districts[cell] == City.District.PARK and cc.x >= 0 and cc.y >= 0 and cc.x < city.blocks and cc.y < city.blocks:
			var o := Vector3(city.x0 + city.street_width + cc.x * city.period + 8.0, 1.5, city.z0 + city.street_width + cc.y * city.period + 8.0)
			pool.append(o)
	# shuffle deterministically, then keep the ones far enough from the others
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var out: Array[Vector3] = []
	for p in pool:
		var ok := true
		for q in out:
			if Vector2(p.x - q.x, p.z - q.z).length() < 70.0:
				ok = false
				break
		if ok:
			out.append(p)
		if out.size() >= COUNT:
			break
	return out


func _make_cache(id: int, pos: Vector3) -> void:
	var n := Node3D.new()
	n.set_meta("id", id)
	add_child(n)
	n.global_position = pos
	var core := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.28
	s.height = 0.56
	core.mesh = s
	core.material_override = _core_mat
	n.add_child(core)
	for k in 3:
		var shell := MeshInstance3D.new()
		var ss := SphereMesh.new()
		ss.radius = 0.16
		ss.height = 0.32
		shell.mesh = ss
		shell.material_override = _mat
		shell.set_meta("orbit", k)
		n.add_child(shell)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.2, 0.1)
	light.light_energy = 1.4
	light.omni_range = 6.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true   # only nearby caches light up their surroundings
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	n.add_child(light)
	caches.append(n)


func found_count() -> int:
	return (Game.flags.get("caches", []) as Array).size()


func _process(delta: float) -> void:
	_t += delta
	var p := Game.player
	for n in caches:
		if not is_instance_valid(n):
			continue
		# a slow bob and three dark orbs circling the glowing core
		for c in n.get_children():
			if c.has_meta("orbit"):
				var a := _t * 2.0 + int(c.get_meta("orbit")) * TAU / 3.0
				(c as Node3D).position = Vector3(cos(a) * 0.45, sin(_t * 3.0 + a) * 0.15, sin(a) * 0.45)
		if p and not p.is_dead() and n.global_position.distance_to(p.global_position) < PICKUP_RADIUS:
			collect(n)
			break


func collect(n: Node3D) -> void:
	var id: int = n.get_meta("id")
	var found: Array = Game.flags.get("caches", [])
	if not found.has(id):
		found.append(id)
	Game.flags["caches"] = found
	Game.stat_max("caches", found.size())
	caches.erase(n)
	var at := n.global_position
	n.queue_free()
	var p := Game.player
	if p:
		p.biomass = p.max_biomass
	Game.add_xp(60, "Viral cache %d/%d" % [found.size(), COUNT])
	if found.size() % 10 == 0:
		Game.skill_points += 1
		Game.xp_changed.emit()
		Game.say("%d VIRAL CACHES  ·  +1 skill point" % found.size(), Color(0.7, 1, 0.6))
	Game.fx.sound("pickup", at, 2.0)
	Game.fx.burst_ring(at, Color(1, 0.15, 0.08, 0.7), 2.5)
