extends Node3D
## A toxic cloud left by the Spore Launcher. Hurts everyone inside who isn't infected (or your ally),
## and the people it kills rise again as infected.

const RADIUS := 6.0
const LIFE := 6.0
const TICK := 0.5
const DAMAGE := 9.0

var source: Node = null
var _t := 0.0
var _tick := 0.0
var _victims: Array = []   # people the cloud has hurt: if they die, they rise


func setup(pos: Vector3, src: Node) -> void:
	global_position = pos
	source = src
	var p := CPUParticles3D.new()
	p.amount = 70
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = RADIUS * 0.7
	p.gravity = Vector3(0, 0.25, 0)
	p.initial_velocity_max = 0.6
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	p.mesh = sm
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.85, 0.15, 0.0))
	g.add_point(0.3, Color(0.5, 0.8, 0.12, 0.35))
	g.set_color(1, Color(0.3, 0.45, 0.1, 0.0))
	p.color_ramp = g
	add_child(p)
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 1.0, 0.2)
	light.light_energy = 1.5
	light.omni_range = RADIUS * 1.6
	light.position.y = 1.0
	add_child(light)


func _physics_process(delta: float) -> void:
	_t += delta
	_tick -= delta
	if _tick <= 0.0 and _t < LIFE:
		_tick = TICK
		var src: Node = source if is_instance_valid(source) else null
		for n in get_tree().get_nodes_in_group("npcs"):
			var npc := n as Node3D
			if npc == null or not npc.has_method("take_hit") or not npc.call("is_alive"):
				continue
			if npc.get("faction") == "infected" or npc.get("is_ally") == true:
				continue
			if npc.global_position.distance_to(global_position) > RADIUS:
				continue
			npc.take_hit(Game.hit_info(DAMAGE * (float(src.get("damage_mult")) if src is Player else 1.0), Vector3.ZERO, src, "slash"))
			if not _victims.has(npc):
				_victims.append(npc)
	# the dead rise
	for v in _victims.duplicate():
		if not is_instance_valid(v):
			_victims.erase(v)
		elif not v.call("is_alive") and v.get("kind") in ["civilian", "soldier", "scientist", "rocket_soldier", "grenadier", "riot", "sniper", "heavy_gunner"]:
			_victims.erase(v)
			v.get_tree().create_timer(1.2, false).timeout.connect(v._rise_infected)
			Game.stat_add("spore_risen")
	if _t > LIFE + 2.5:
		queue_free()
