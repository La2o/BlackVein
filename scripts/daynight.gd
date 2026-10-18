extends Node
## Day and night cycle: moves the sun, changes sky, fog and light colors,
## and lights up windows and street lamps at night.
## One full day takes about 16 minutes.

@export var seconds_per_hour := 40.0
@export var start_hour := 16.0

var hour := 16.0
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial


func _ready() -> void:
	Game.daynight = self
	hour = start_hour


func setup(sun_light: DirectionalLight3D, environment: Environment) -> void:
	sun = sun_light
	env = environment
	sky_mat = env.sky.sky_material as ProceduralSkyMaterial
	_apply()


func is_night() -> bool:
	return hour < 5.5 or hour > 20.0


func time_text() -> String:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	return "%02d:%02d" % [h, m]


func _process(delta: float) -> void:
	hour = fmod(hour + delta / seconds_per_hour, 24.0)
	_apply()


func _apply() -> void:
	if sun == null:
		return
	# 0 at midnight, 1 at noon
	var day := clampf(sin((hour - 6.0) / 12.0 * PI), -1.0, 1.0)
	var light_amount := clampf(day * 1.6 + 0.15, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(day) * 3.0, 0.0, 1.0)
	var night := clampf(-day * 2.0 + 0.2, 0.0, 1.0)
	# sun travels east to west; at night the same light acts as moonlight
	var elevation := deg_to_rad(maxf(absf(day) * 62.0, 12.0))
	var azimuth := deg_to_rad((hour / 24.0) * 360.0 + 90.0)
	sun.rotation = Vector3(-elevation, azimuth, 0)
	var day_col := Color(1.0, 0.96, 0.9)
	var dusk_col := Color(1.0, 0.6, 0.35)
	var moon_col := Color(0.45, 0.55, 0.85)
	var col := day_col.lerp(dusk_col, dusk)
	if day < 0.0:
		col = dusk_col.lerp(moon_col, clampf(-day * 4.0, 0.0, 1.0))
	sun.light_color = col
	sun.light_energy = lerpf(0.3, 1.35, light_amount)
	sun.shadow_enabled = light_amount > 0.05 or day < -0.2
	if sky_mat:
		var top_day := Color(0.3, 0.45, 0.65)
		var top_dusk := Color(0.35, 0.3, 0.45)
		var top_night := Color(0.02, 0.03, 0.07)
		var hor_day := Color(0.75, 0.75, 0.72)
		var hor_dusk := Color(0.95, 0.55, 0.35)
		var hor_night := Color(0.06, 0.07, 0.12)
		var top := top_day.lerp(top_dusk, dusk)
		var hor := hor_day.lerp(hor_dusk, dusk)
		if day < 0.0:
			top = top_dusk.lerp(top_night, clampf(-day * 3.0, 0.0, 1.0))
			hor = hor_dusk.lerp(hor_night, clampf(-day * 3.0, 0.0, 1.0))
		sky_mat.sky_top_color = top
		sky_mat.sky_horizon_color = hor
		sky_mat.ground_horizon_color = hor
		sky_mat.ground_bottom_color = hor.darkened(0.6)
		env.fog_light_color = hor.lerp(Color(0.5, 0.5, 0.5), 0.2)
	# ambient: sky color by day, a cool moonlit blue at night so streets stay readable
	var amb_day: Color = sky_mat.sky_horizon_color.lerp(sky_mat.sky_top_color, 0.5) if sky_mat else Color(0.6, 0.6, 0.65)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = amb_day.lerp(Color(0.16, 0.19, 0.3), night).lerp(Color(0.62, 0.62, 0.66), light_amount * 0.4)
	env.ambient_light_energy = lerpf(1.1, 0.75, light_amount)
	env.background_energy_multiplier = lerpf(0.4, 1.0, light_amount)
	if Game.city:
		Game.city.set_night(night)
