extends StaticBody3D
## An infection hive: a pulsing mass of flesh that keeps spawning infected
## until it is destroyed.

const NPC := preload("res://scripts/npc.gd")

var hp := 900.0
var max_hp := 900.0
var event_tag := ""
var destroyed := false
var _spawn_timer := 2.0
var _children: Array[Node3D] = []
var _blobs: Array[MeshInstance3D] = []
var _t := 0.0
var _hum: AudioStreamPlayer3D
var _zone_mat: ShaderMaterial
var _zone: MeshInstance3D
var _age := 0.0
var _convert_timer := 8.0


func setup(extra := {}) -> void:
	event_tag = extra.get("tag", "")
	collision_layer = Game.LAYER_HIVE | Game.LAYER_WORLD
	reset_physics_interpolation()
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 3.2
	shape.shape = s
	shape.position = Vector3(0, 1.2, 0)
	add_child(shape)
	var flesh := StandardMaterial3D.new()
	flesh.albedo_color = Color(0.35, 0.05, 0.05)
	flesh.roughness = 0.3
	flesh.emission_enabled = true
	flesh.emission = Color(0.8, 0.05, 0.03)
	flesh.emission_energy_multiplier = 0.6
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.02, 0.02)
	dark.roughness = 0.4
	for k in 9:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := randf_range(1.2, 2.6) if k > 0 else 3.0
		sm.radius = r
		sm.height = r * 1.6
		mi.mesh = sm
		mi.material_override = flesh if k % 3 != 0 else dark
		var a := randf() * TAU
		mi.position = Vector3(cos(a) * randf_range(0.5, 3.0), r * 0.4, sin(a) * randf_range(0.5, 3.0)) if k > 0 else Vector3(0, 1.0, 0)
		add_child(mi)
		_blobs.append(mi)
	# tendrils on the ground
	for k in 10:
		var t := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.35, 0.2, randf_range(5.0, 11.0))
		t.mesh = b
		t.material_override = dark
		t.rotation.y = randf() * TAU
		t.position = Vector3(0, 0.1, 0) + Vector3(sin(t.rotation.y), 0, cos(t.rotation.y)) * b.size.z * 0.5
		add_child(t)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.15, 0.08)
	light.light_energy = 3.0
	light.omni_range = 16.0
	light.position = Vector3(0, 3, 0)
	add_child(light)
	# infected ground spreading around the hive
	var zone := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(70, 70)
	zone.mesh = plane
	_zone_mat = ShaderMaterial.new()
	_zone_mat.shader = preload("res://shaders/infection.gdshader")
	zone.material_override = _zone_mat
	zone.position = Vector3(0, 0.2, 0)
	zone.rotation.y = randf() * TAU
	zone.scale = Vector3(0.4, 1, 0.4)
	add_child(zone)
	_zone = zone
	add_to_group("hives")
	_hum = Game.fx.make_loop_player("hive")
	_hum.volume_db = -6.0
	add_child(_hum)


func is_alive() -> bool:
	return not destroyed


func take_hit(info: Dictionary) -> void:
	if destroyed:
		return
	var dmg: float = info["damage"]
	if info["kind"] in ["blade", "slash"]:
		dmg *= 1.3
	hp -= dmg
	Game.fx.splat(global_position + Vector3.UP * 2.0, Vector3.UP, Color(0.4, 0.03, 0.03), 8)
	if info["source"] == Game.player and randf() < 0.3:
		_spawn()
	if hp <= 0.0:
		_destroy(info["source"])


func _destroy(src: Node) -> void:
	destroyed = true
	if src == Game.player:
		Game.stat_add("hives")
	Game.explode(global_position + Vector3.UP * 1.5, 10.0, 60.0, self, 20.0)
	for k in 4:
		Game.fx.splat(global_position + Vector3.UP * 2.0, Vector3(randf() - 0.5, 1, randf() - 0.5), Color(0.4, 0.03, 0.03), 30)
	Game.fx.sound("roar", global_position, 6.0, 0.05)
	get_tree().call_group("event_listeners", "on_unit_removed", self, "destroyed")
	queue_free()


func _physics_process(delta: float) -> void:
	_t += delta
	_age += delta
	if _zone_mat:
		_zone_mat.set_shader_parameter("pulse", _t)
	# the infection spreads the longer the hive lives
	var spread := clampf(0.4 + _age / 200.0, 0.4, 1.6)
	if _zone:
		_zone.scale = Vector3(spread, 1, spread)
	_convert_timer -= delta
	if _convert_timer <= 0.0:
		_convert_timer = 10.0
		var radius := 35.0 * spread
		for c in get_tree().get_nodes_in_group("civilians"):
			var civ := c as Node3D
			if civ and civ.global_position.distance_to(global_position) < radius and randf() < 0.35:
				civ.set("_infected_killer", true)
				civ.take_hit(Game.hit_info(999.0, Vector3.UP * 2.0, self, "slash"))
				break
	for k in _blobs.size():
		var b := _blobs[k]
		var s := 1.0 + sin(_t * 2.5 + k * 1.3) * 0.06
		b.scale = Vector3(s, s * 0.95, s)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = 5.0
	var alive: Array[Node3D] = []
	for c in _children:
		if is_instance_valid(c) and c.is_alive():
			alive.append(c)
	_children = alive
	var p := Game.player
	if p and global_position.distance_to(p.global_position) < 180.0 and _children.size() < 9:
		_spawn()


func _spawn() -> void:
	var n := CharacterBody3D.new()
	n.set_script(NPC)
	get_parent().add_child(n)
	var a := randf() * TAU
	n.global_position = global_position + Vector3(cos(a), 0, sin(a)) * 5.0 + Vector3.UP * 0.5
	n.setup("infected", {"tag": event_tag})
	n.patrol_center = global_position
	_children.append(n)
	Game.fx.splat(n.global_position, Vector3.UP, Color(0.4, 0.03, 0.03), 10)
