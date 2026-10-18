extends Area3D
## A weapon lying on the ground (dropped by soldiers) or a supply cache.
## kind: "rifle", "launcher" or "supply".

var kind := "rifle"
var amount := 90
var life := 45.0
var _mesh: Node3D
var _t := 0.0


func setup(k: String, amt: int) -> void:
	kind = k
	amount = amt
	reset_physics_interpolation()
	collision_layer = Game.LAYER_PICKUP
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 1.0
	shape.shape = s
	add_child(shape)
	_mesh = Node3D.new()
	add_child(_mesh)
	var mi := MeshInstance3D.new()
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.1, 0.1, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1, 0.8, 0.3)
	glow.emission_energy_multiplier = 0.6
	match kind:
		"rifle":
			var b := BoxMesh.new()
			b.size = Vector3(0.08, 0.14, 0.9)
			mi.mesh = b
		"launcher":
			var c := CapsuleMesh.new()
			c.radius = 0.1
			c.height = 1.1
			mi.mesh = c
			mi.rotation.x = PI * 0.5
		"supply":
			var b2 := BoxMesh.new()
			b2.size = Vector3(1.4, 1.0, 1.4)
			mi.mesh = b2
			glow.albedo_color = Color(0.3, 0.35, 0.25)
			glow.emission = Color(0.4, 1.0, 0.5)
			life = 999.0
	mi.material_override = glow
	_mesh.add_child(mi)
	add_to_group("pickups")


func _process(delta: float) -> void:
	_t += delta
	life -= delta
	if _mesh:
		_mesh.rotation.y += delta * 1.5
		_mesh.position.y = 0.4 + sin(_t * 3.0) * 0.12
	if life <= 0.0:
		queue_free()
		return
	if kind == "supply" and Game.player and not Game.player.is_dead() \
			and Game.player.global_position.distance_to(global_position) < 2.8:
		pick_up(Game.player)


func pick_up(player: Node) -> void:
	if kind == "supply":
		player.heal(player.max_health)
		player.biomass = player.max_biomass
		Game.add_ep(amount, "Supply cache")
		Game.fx.sound("evolve", global_position, 0.0)
		get_tree().call_group("event_listeners", "on_supply_taken", self)
	else:
		player.powers.give_weapon(kind, amount)
	queue_free()
