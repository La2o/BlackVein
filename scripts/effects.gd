extends Node3D
## Visual and sound effects: explosions, shockwaves, spikes, tendrils,
## tracers, blood, fire and smoke. Everything is built from simple shapes
## at runtime, so the project needs no art files.

const SOUND_NAMES := ["punch", "slash", "heavy", "explosion", "gunshot", "rocket", "land", "whoosh",
	"consume", "crash", "spike", "tendril", "alert", "ui", "dash", "tank_shot", "roar", "block",
	"jump", "glide", "scream", "helicopter", "hive", "pickup", "death", "evolve", "zap"]

var _sounds := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_index := 0
var _ui_player: AudioStreamPlayer
var _tracer_mesh := BoxMesh.new()
var _tracer_mat := StandardMaterial3D.new()
var _tendril_mat := StandardMaterial3D.new()
var _spike_mat := StandardMaterial3D.new()
var _sphere := SphereMesh.new()
var _cube := BoxMesh.new()


func _ready() -> void:
	Game.fx = self
	for n in SOUND_NAMES:
		var path := "res://sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			_sounds[n] = load(path)
	for k in 28:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 14.0
		p.max_distance = 260.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_ui_player = AudioStreamPlayer.new()
	add_child(_ui_player)
	_tracer_mesh.size = Vector3.ONE
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.85, 0.4)
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tendril_mat.albedo_color = Color(0.35, 0.02, 0.03)
	_tendril_mat.emission_enabled = true
	_tendril_mat.emission = Color(0.9, 0.08, 0.05)
	_tendril_mat.emission_energy_multiplier = 1.4
	_tendril_mat.roughness = 0.4
	_spike_mat.albedo_color = Color(0.25, 0.03, 0.04)
	_spike_mat.emission_enabled = true
	_spike_mat.emission = Color(0.7, 0.05, 0.04)
	_spike_mat.emission_energy_multiplier = 0.8
	_spike_mat.roughness = 0.35
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 10
	_sphere.rings = 6
	_cube.size = Vector3.ONE


# ------------------------------------------------------------------ sound

func sound(sound_name: String, pos: Vector3, volume_db := 0.0, pitch_spread := 0.12) -> void:
	if not _sounds.has(sound_name):
		return
	var p := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	p.stream = _sounds[sound_name]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(1.0 - pitch_spread, 1.0 + pitch_spread) * maxf(Engine.time_scale, 0.5)
	p.global_position = pos
	p.reset_physics_interpolation()
	p.play()


func sound_ui(sound_name: String, volume_db := -4.0) -> void:
	if not _sounds.has(sound_name):
		return
	_ui_player.stream = _sounds[sound_name]
	_ui_player.volume_db = volume_db
	_ui_player.play()


func make_loop_player(sound_name: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	if _sounds.has(sound_name):
		p.stream = _sounds[sound_name]   # looping is set in the .import file
	p.unit_size = 20.0
	p.max_distance = 300.0
	p.autoplay = true
	return p


# ------------------------------------------------------------------ helpers

func _auto_free(node: Node, after: float) -> void:
	# connecting to the node's own method means the timer forgets it if it's freed early
	get_tree().create_timer(after, false).timeout.connect(node.queue_free)


func _unshaded(color: Color, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


func _particles(amount: int, life: float, mesh: Mesh, color_from: Color, color_to: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	var m: Mesh = mesh.duplicate()
	(m as PrimitiveMesh).material = mat
	p.mesh = m
	var g := Gradient.new()
	g.set_color(0, color_from)
	g.set_color(1, color_to)
	p.color_ramp = g
	return p


## Places a unit box so it stretches from a to b.
func orient_line(node: Node3D, a: Vector3, b: Vector3, width: float) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.01:
		node.visible = false
		return
	node.visible = true
	var up := Vector3.UP
	if absf(dir.normalized().y) > 0.98:
		up = Vector3.RIGHT
	var basis := Basis.looking_at(dir, up).scaled(Vector3(width, width, length))
	node.global_transform = Transform3D(basis, (a + b) * 0.5)
	node.reset_physics_interpolation()


# ------------------------------------------------------------------ effects

func shockwave(pos: Vector3, radius: float, color := Color(1.0, 0.85, 0.7, 0.8), life := 0.45) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	torus.rings = 40
	torus.ring_segments = 6
	mi.mesh = torus
	var mat := _unshaded(color)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.2
	mi.reset_physics_interpolation()
	mi.scale = Vector3(0.5, 0.3, 0.5)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(radius, 0.5, radius), life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	_auto_free(mi, life + 0.05)
	# dust ring
	var dust := _particles(int(clampf(radius * 3.0, 10, 50)), 1.0, _sphere, Color(0.55, 0.5, 0.45, 0.7), Color(0.5, 0.48, 0.45, 0.0))
	dust.direction = Vector3(1, 0.2, 0)
	dust.spread = 180.0
	dust.flatness = 0.9
	dust.initial_velocity_min = radius * 0.8
	dust.initial_velocity_max = radius * 1.6
	dust.damping_min = radius * 0.8
	dust.damping_max = radius * 1.2
	dust.gravity = Vector3(0, 1, 0)
	dust.scale_amount_min = 0.8
	dust.scale_amount_max = 2.2
	add_child(dust)
	dust.global_position = pos + Vector3.UP * 0.3
	dust.reset_physics_interpolation()
	dust.emitting = true
	_auto_free(dust, 1.2)


func explosion(pos: Vector3, radius: float) -> void:
	var ball := MeshInstance3D.new()
	ball.mesh = _sphere
	var mat := _unshaded(Color(1.0, 0.5, 0.15, 0.9), true)
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = pos
	ball.reset_physics_interpolation()
	ball.scale = Vector3.ONE * 0.5
	var tw := ball.create_tween().set_parallel()
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 1.4, 0.22).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color", Color(0.3, 0.08, 0.02, 0.0), 0.4).set_delay(0.05)
	_auto_free(ball, 0.6)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.6, 0.3)
	light.light_energy = 12.0
	light.omni_range = radius * 5.0
	add_child(light)
	light.global_position = pos + Vector3.UP
	light.reset_physics_interpolation()
	light.create_tween().tween_property(light, "light_energy", 0.0, 0.45)
	_auto_free(light, 0.5)
	var smoke := _particles(18, 2.6, _sphere, Color(0.25, 0.22, 0.2, 0.8), Color(0.3, 0.3, 0.3, 0.0))
	smoke.direction = Vector3.UP
	smoke.spread = 60.0
	smoke.initial_velocity_min = 3.0
	smoke.initial_velocity_max = 9.0
	smoke.gravity = Vector3(0, 2.0, 0)
	smoke.damping_min = 2.0
	smoke.damping_max = 3.0
	smoke.scale_amount_min = radius * 0.5
	smoke.scale_amount_max = radius * 1.0
	add_child(smoke)
	smoke.global_position = pos
	smoke.reset_physics_interpolation()
	smoke.emitting = true
	_auto_free(smoke, 2.8)
	var sparks := _particles(24, 1.1, _cube, Color(1, 0.8, 0.3, 1), Color(0.3, 0.1, 0.05, 0.0))
	sparks.direction = Vector3.UP
	sparks.spread = 80.0
	sparks.initial_velocity_min = 8.0
	sparks.initial_velocity_max = 22.0
	sparks.scale_amount_min = 0.12
	sparks.scale_amount_max = 0.35
	add_child(sparks)
	sparks.global_position = pos
	sparks.reset_physics_interpolation()
	sparks.emitting = true
	_auto_free(sparks, 1.3)
	shockwave(pos, radius * 1.6, Color(1, 0.7, 0.4, 0.6), 0.35)
	sound("explosion", pos, 4.0)


func splat(pos: Vector3, dir: Vector3, color := Color(0.55, 0.02, 0.02), amount := 14) -> void:
	var p := _particles(amount, 0.7, _sphere, color, Color(color.r * 0.5, 0, 0, 0))
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.spread = 45.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.25
	add_child(p)
	p.global_position = pos
	p.reset_physics_interpolation()
	p.emitting = true
	_auto_free(p, 0.9)


func debris(pos: Vector3, amount := 12, color := Color(0.45, 0.43, 0.4)) -> void:
	var p := _particles(amount, 1.4, _cube, color, Color(color.r, color.g, color.b, 0.0))
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 13.0
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.6
	add_child(p)
	p.global_position = pos
	p.reset_physics_interpolation()
	p.emitting = true
	_auto_free(p, 1.6)


func tracer(from: Vector3, to: Vector3, color := Color(1.0, 0.85, 0.4), width := 0.05) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	var mat := _tracer_mat
	if color != Color(1.0, 0.85, 0.4):
		mat = _unshaded(color)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	orient_line(mi, from, to, width)
	_auto_free(mi, 0.06)


func make_tendril(width := 0.14) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	mi.material_override = _tendril_mat
	mi.set_meta("width", width)
	add_child(mi)
	return mi


## A tendril that lashes from a to b and fades out.
func tendril_flash(a: Vector3, b: Vector3, life := 0.25, width := 0.16) -> void:
	var mi := make_tendril(width)
	orient_line(mi, a, b, width)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.01, 0.01, mi.scale.z), life).set_ease(Tween.EASE_IN)
	_auto_free(mi, life + 0.05)


func spike(pos: Vector3, height := 3.5, delay := 0.0, hold := 0.7) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = height * 0.16
	cm.height = height
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _spike_mat
	add_child(mi)
	mi.global_position = pos + Vector3(0, -height * 0.5, 0)
	mi.reset_physics_interpolation()
	mi.rotation = Vector3(randf_range(-0.25, 0.25), randf() * TAU, randf_range(-0.25, 0.25))
	mi.visible = delay <= 0.0
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func(): mi.visible = true)
	tw.tween_property(mi, "global_position:y", pos.y + height * 0.42, 0.09).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(mi, "global_position:y", pos.y - height * 0.6, 0.35).set_ease(Tween.EASE_IN)
	_auto_free(mi, delay + hold + 0.5)


func make_fire() -> CPUParticles3D:
	var p := _particles(26, 1.0, _sphere, Color(1.0, 0.6, 0.15, 0.9), Color(0.2, 0.18, 0.17, 0.0))
	p.one_shot = false
	p.explosiveness = 0.0
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, 2.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.7, 0.2, 1.4)
	var mat: StandardMaterial3D = (p.mesh as PrimitiveMesh).material
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return p


func smoke_column(pos: Vector3, color: Color, duration: float) -> CPUParticles3D:
	var p := _particles(40, 3.0, _sphere, color, Color(color.r, color.g, color.b, 0.0))
	p.one_shot = false
	p.explosiveness = 0.0
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0.5, 1.0, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	var mat: StandardMaterial3D = (p.mesh as PrimitiveMesh).material
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(p)
	p.global_position = pos
	p.reset_physics_interpolation()
	p.emitting = true
	get_tree().create_timer(duration, false).timeout.connect(p.set.bind("emitting", false))
	_auto_free(p, duration + 3.2)
	return p


func burst_ring(pos: Vector3, color: Color, radius := 2.0) -> void:
	shockwave(pos, radius, color, 0.3)


func damage_number(pos: Vector3, amount: float, big := false) -> void:
	if not Settings.damage_numbers or amount < 1.0:
		return
	var l := Label3D.new()
	l.text = str(int(round(amount)))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0015
	l.font_size = 40 if big else 28
	l.outline_size = 10
	l.modulate = Color(1, 0.85, 0.3) if big else Color(1, 1, 1)
	add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.4, 0.4), 1.2, randf_range(-0.4, 0.4))
	l.reset_physics_interpolation()
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "global_position:y", l.global_position.y + 1.5, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.2)
	_auto_free(l, 0.75)


func flash_light(pos: Vector3, color: Color, energy := 6.0, range_m := 12.0, life := 0.2) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	add_child(light)
	light.global_position = pos
	light.reset_physics_interpolation()
	light.create_tween().tween_property(light, "light_energy", 0.0, life)
	_auto_free(light, life + 0.05)
