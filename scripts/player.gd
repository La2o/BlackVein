class_name Player
extends CharacterBody3D
## The player: super-speed running, wall running, charged super jumps,
## double jump, gliding, air dashes, tether zips, dive bombs and heavy landings.
## Health, biomass, disguise and the camera live here too; combat and powers
## are in the Powers child node (player_powers.gd).
## Every number that changes the feel is listed in the Inspector.

signal health_changed(value: float, max_value: float)
signal died

enum State { GROUND, AIR, WALL, GLIDE, DASH, TETHER, DIVE, LOCKED, PILOT, DEAD }
const STATE_NAMES := ["Ground", "Air", "Wall run", "Glide", "Dash", "Tether", "Dive", "Busy", "Driving", "Dead"]

@export_group("Running")
@export var walk_speed := 7.5
@export var sprint_speed := 26.0
@export var ground_accel := 70.0
@export var ground_decel := 55.0
@export var air_accel := 18.0

@export_group("Jumping")
@export var gravity := 38.0
## Jumping is instant and keeps all your speed. Keep holding jump to keep rising:
## a tap is a hop, a full hold is a ~30 m super jump (more when running).
@export var jump_velocity := 13.0
@export var run_jump_velocity := 16.0
@export var jump_boost_accel := 95.0
@export var jump_boost_time := 0.42
@export var double_jump_velocity := 20.0
@export var double_jump_boost := 6.0
@export var max_fall_speed := 75.0

@export_group("Wall running")
@export var wall_run_speed := 22.0
@export var wall_accel := 140.0
@export var wall_stick := 4.0
@export var wall_jump_push := 16.0
@export var wall_jump_up := 14.0
@export var ledge_vault_up := 11.0
@export var ledge_vault_forward := 6.5

@export_group("Glide")
@export var glide_fall_speed := 3.5
@export var glide_speed := 22.0
@export var glide_turn := 3.0

@export_group("Air dash")
@export var dash_speed := 40.0
@export var dash_time := 0.2
@export var dash_cooldown := 0.35

@export_group("Landing")
@export var heavy_landing_speed := 28.0
@export var shockwave_radius := 11.0
@export var shockwave_force := 16.0

@export_group("Camera")
@export var mouse_sensitivity := 0.0025
@export var stick_sensitivity := 3.2
@export var camera_height := 1.85
@export var camera_distance := 6.0
@export var base_fov := 72.0
@export var max_fov := 96.0

const CAPSULE_RADIUS := 0.4

var state: int = State.AIR
var wish := Vector3.ZERO
var sprinting := false
var charging := false      # true while a held jump is still pushing you up (HUD bar)
var charge := 0.0
var boost_timer := 0.0
var boost_held := 0.0
var _super_done := false
var _takeoff := Vector3.ZERO
var double_jump_ready := true
var flaps_left := 0
var _glide_accum := 0.0
var dash_ready := true
var air_press := false
var wall_normal := Vector3.ZERO
var wall_dir := Vector3.UP
var wall_cooldown := 0.0
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_dir := Vector3.FORWARD
var coyote := 0.0
var fall_speed_before_move := 0.0
var pre_move_velocity := Vector3.ZERO
var spawn_point := Vector3(0, 2, 0)
var spawn_yaw := 0.0
var yaw := 0.0
var pitch := -0.15
var trauma := 0.0
var facing := Vector3.FORWARD
var face_override_timer := 0.0
var face_override := Vector3.FORWARD
var tether_point := Vector3.ZERO
var tether_timer := 0.0
var tether_line: MeshInstance3D
var lock_timer := 0.0
var lock_mode := "idle"
var dive_power := 1.0
var vehicle: Node = null
var dead_timer := 0.0
var invuln_timer := 0.0

# Stats
var max_health := 100.0
var health := 100.0
var max_biomass := 100.0
var biomass := 60.0
var regen_cap := 0.75
var regen_rate := 6.0
var time_since_damage := 99.0
var conspicuous_timer := 0.0   # did something no human could (dash, tether, dive, smash...)
var parkour_timer := 0.0       # vaulted, flipped or ran up a wall: fine in a fitting disguise
var disguise := "civilian"
var damage_mult := 1.0
var speed_mult := 1.0
var jump_mult := 1.0
var hits_taken_recent := 0.0

# acrobatics (visual only): flips, rolls, vaults, landing poses
var trick := ""
var _trick_t := 0.0
var _trick_len := 0.0
var _trick_dir := 1.0
var _hero_t := 0.0
var _base_q := Quaternion.IDENTITY
var _bank := 0.0
var _last_facing := Vector3.FORWARD
var _vault_cd := 0.0
var _charge_fx_t := 0.0
var coiling := false   # showing the charge-jump coil this frame
var _vault_t := 0.0       # time left in the current vault arc (plus a little landing grace)
var _vault_speed := 0.0   # running speed the vault keeps
const VAULT_MAX_HEIGHT := 1.8

@onready var visual: Node3D = $Visual
@onready var model: Node3D = $Visual/Model
@onready var powers: PlayerPowers = $Powers
@onready var pivot: Node3D = $CameraPivot
@onready var pitch_node: Node3D = $CameraPivot/CameraPitch
@onready var spring: SpringArm3D = $CameraPivot/CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/CameraPitch/SpringArm3D/Camera3D
@onready var collision: CollisionShape3D = $Collision


func _ready() -> void:
	Game.player = self
	add_to_group("player")
	model.build()
	spring.add_excluded_object(get_rid())
	pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	pivot.global_position = global_position + Vector3.UP * camera_height
	apply_upgrades()


func set_spawn(p: Vector3, y: float) -> void:
	spawn_point = p
	spawn_yaw = y
	respawn(p)


func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	yaw = spawn_yaw
	pitch = -0.15
	facing = Vector3.FORWARD.rotated(Vector3.UP, yaw)
	state = State.AIR
	charging = false
	double_jump_ready = true
	dash_ready = true
	air_press = false
	boost_timer = 0.0
	flaps_left = max_flaps()
	trick = ""
	_hero_t = 0.0
	health = max_health
	biomass = maxf(biomass, max_biomass * 0.6)
	visual.visible = true
	collision.disabled = false
	vehicle = null
	invuln_timer = 2.0
	model.rotation = Vector3.ZERO
	pivot.global_position = global_position + Vector3.UP * camera_height
	reset_physics_interpolation()
	health_changed.emit(health, max_health)


## Move the player somewhere (doors, interiors) without healing or resetting anything.
func respawn_in_place(at: Vector3, new_yaw: float) -> void:
	global_position = at
	velocity = Vector3.ZERO
	yaw = new_yaw
	facing = Vector3.FORWARD.rotated(Vector3.UP, new_yaw)
	if state != State.DEAD:
		state = State.AIR
	reset_physics_interpolation()
	pivot.global_position = at + Vector3.UP * camera_height


func apply_upgrades() -> void:
	var ratio := health / maxf(max_health, 1.0)
	# levels make you a little tougher by themselves; skills do the rest
	var lvl_bonus := Game.level_bonus()
	max_health = 100.0 * (1.0 + 0.2 * Game.skill_rank("vitality") + lvl_bonus)
	health = max_health * ratio
	max_biomass = 100.0 + 30.0 * Game.skill_rank("biomass")
	damage_mult = 1.0 + 0.15 * Game.skill_rank("muscle") + lvl_bonus
	# creature forms change the whole body
	match powers.creature:
		PlayerPowers.Creature.BRUTE:
			damage_mult *= 1.6
			max_health *= 1.5
		PlayerPowers.Creature.STALKER:
			damage_mult *= 1.15
		PlayerPowers.Creature.WRAITH:
			damage_mult *= 0.85
			max_health *= 0.85
	health = minf(health, max_health)
	speed_mult = 1.0 + 0.1 * Game.skill_rank("agility")
	jump_mult = 1.0 + 0.1 * Game.skill_rank("leap")
	regen_cap = 0.7 + 0.06 * Game.skill_rank("regen")
	regen_rate = 6.0 + 3.0 * Game.skill_rank("regen")
	health_changed.emit(health, max_health)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * Settings.mouse_sensitivity
		var inv := -1.0 if Settings.invert_y else 1.0
		yaw -= event.relative.x * sens
		pitch -= event.relative.y * sens * inv
		pitch = clampf(pitch, -1.35, 0.95)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	var look := Vector2(Input.get_axis("look_left", "look_right"), Input.get_axis("look_up", "look_down"))
	if Game.hud and Game.hud.wheel_open:
		look = Vector2.ZERO
	var ss := stick_sensitivity * Settings.stick_sensitivity
	var inv := -1.0 if Settings.invert_y else 1.0
	yaw -= look.x * ss * real
	pitch = clampf(pitch - look.y * ss * 0.7 * real * inv, -1.35, 0.95)
	_update_camera(real)


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	wish = Vector3(raw.x, 0, raw.y).rotated(Vector3.UP, yaw)
	sprinting = Input.is_action_pressed("sprint")
	if powers.has_method("sprint_allowed") and not powers.sprint_allowed():
		sprinting = false
	wall_cooldown = maxf(0.0, wall_cooldown - delta)
	dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)
	conspicuous_timer = maxf(0.0, conspicuous_timer - delta)
	parkour_timer = maxf(0.0, parkour_timer - delta)
	face_override_timer = maxf(0.0, face_override_timer - delta)
	invuln_timer = maxf(0.0, invuln_timer - delta)
	hits_taken_recent = maxf(0.0, hits_taken_recent - delta * 0.5)
	_update_stats(delta)

	if state != State.DEAD and state != State.PILOT:
		if Input.is_action_just_pressed("respawn"):
			respawn(Game.city.random_roof_point(global_position, 0.0, 200.0))
			return
		var floor_limit := -60.0
		if Game.interiors and Game.interiors.is_inside():
			floor_limit = Game.interiors.DEPTH - 25.0
		if global_position.y < floor_limit:
			if Game.interiors and Game.interiors.is_inside():
				Game.interiors.leave()
			else:
				respawn(spawn_point)
			return

	match state:
		State.GROUND: _state_ground(delta)
		State.AIR: _state_air(delta)
		State.WALL: _state_wall(delta)
		State.GLIDE: _state_glide(delta)
		State.DASH: _state_dash(delta)
		State.TETHER: _state_tether(delta)
		State.DIVE: _state_dive(delta)
		State.LOCKED: _state_locked(delta)
		State.PILOT: _state_pilot(delta)
		State.DEAD: _state_dead(delta)

	if state == State.PILOT:
		return
	fall_speed_before_move = -velocity.y
	pre_move_velocity = velocity
	var comp := 1.0
	if Game.focus_active and Game.hit_stop_timer <= 0.0:
		comp = 1.0 / 0.35 * 0.7
	velocity *= comp
	move_and_slide()
	velocity /= comp
	_push_props()
	if state == State.GROUND:
		_step_up(delta)
	if _vault_t > 0.0:
		_vault_assist(delta)
	_check_landing()
	_update_visual(delta)


func _update_stats(delta: float) -> void:
	if state == State.DEAD:
		return
	if global_position.y > 100.0 and is_on_floor():
		Game.stat_max("max_height", int(global_position.y))
	if state == State.GLIDE:
		_glide_accum += delta
		if _glide_accum >= 1.0:
			_glide_accum -= 1.0
			Game.stat_add("glide_seconds")
	time_since_damage += delta
	if time_since_damage > 4.0 and health < max_health * regen_cap:
		health = minf(max_health * regen_cap, health + regen_rate * delta)
		health_changed.emit(health, max_health)
	biomass = minf(max_biomass, biomass + 1.2 * delta)


# ------------------------------------------------------------------ states

func _state_ground(delta: float) -> void:
	if not is_on_floor():
		coyote += delta
		velocity.y -= gravity * delta
		if coyote > 0.12:
			state = State.AIR
			return
	else:
		coyote = 0.0
		velocity.y = -1.0
	var target_speed := (sprint_speed * speed_mult) if sprinting else walk_speed
	target_speed *= powers.speed_factor() if powers.has_method("speed_factor") else 1.0
	var hv := Vector3(velocity.x, 0, velocity.z)
	var target := wish * target_speed
	var rate := ground_accel if wish.length() > 0.1 else ground_decel
	if hv.length() > target_speed + 1.0:
		rate = ground_decel * 0.6
	hv = hv.move_toward(target, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.z

	if Input.is_action_just_pressed("jump") and powers.can_move():
		_ground_jump()
		return
	if (Input.is_action_just_pressed("dash") and not Input.is_action_pressed("devastator_mod")) and dash_cooldown_timer <= 0.0 and powers.can_move():
		_start_dash()
		return
	# low obstacles are vaulted before they can count as a wall to run up
	if sprinting and _try_vault(delta):
		return
	if (sprinting or powers.clings_to_walls()) and wall_cooldown <= 0.0:
		var n := _wall_ahead(wish)
		if n != Vector3.ZERO:
			_enter_wall(n)
			return


## Sprinting at something low (a car, bench, low wall) hops over it in one smooth arc without
## slowing down: the obstacle is spotted well ahead, its height measured and the hop sized to clear it.
func _try_vault(delta: float) -> bool:
	_vault_cd -= delta
	var hv := Vector3(velocity.x, 0, velocity.z)
	var speed := hv.length()
	if _vault_cd > 0.0 or speed < 9.0 or not is_on_floor():
		return false
	var d := hv / speed
	var feet := global_position + Vector3.DOWN * 0.9
	var reach := CAPSULE_RADIUS + 0.3 + speed * 0.22
	var mask := Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_VEHICLE
	var ex: Array[RID] = [get_rid()]
	var low_from := feet + Vector3.UP * 0.35
	var low := Game.raycast(low_from, low_from + d * reach, mask, ex)
	if low.is_empty():
		return false
	var ln: Vector3 = low["normal"]
	if ln.y > 0.6:
		return false   # a ramp: just run up it
	var face: Vector3 = low["position"]
	var probe := face + d * 0.35
	var top_ray := Game.raycast(Vector3(probe.x, feet.y + VAULT_MAX_HEIGHT + 0.6, probe.z),
		Vector3(probe.x, feet.y + 0.3, probe.z), mask, ex)
	if top_ray.is_empty():
		return false   # taller than a vault (or the ray started inside it)
	var top_pos: Vector3 = top_ray["position"]
	var top := top_pos.y - feet.y
	if top > VAULT_MAX_HEIGHT:
		return false
	var dist := Vector2(face.x - feet.x, face.z - feet.z).length()
	var high_from := feet + Vector3.UP * (top + 1.1)
	if not Game.raycast(high_from, high_from + d * (dist + 1.5), mask, ex).is_empty():
		return false   # no room for the body above it
	# lowest arc that is above the obstacle's top when we reach its face
	var clear := top + 0.3
	var tf := maxf(dist / speed, 0.08)
	var vy := maxf(clear / tf + gravity * tf * 0.5, sqrt(2.0 * gravity * clear))
	vy = minf(vy, 16.0)
	_vault_cd = 0.4
	_vault_speed = speed
	_vault_t = 2.0 * vy / gravity + 0.15
	velocity.y = vy
	state = State.AIR
	coyote = 0.0
	double_jump_ready = true
	start_trick("vault", 2.0 * vy / gravity, 1.0 if randf() < 0.5 else -1.0)
	# the hands-on-the-obstacle climb-over (Universal Animation Library 2), timed to the hop
	var hop := 2.0 * vy / gravity
	model.oneshot("ClimbUp_1m", clampf(0.67 / maxf(hop, 0.05), 0.9, 2.6), 0.06)
	Game.fx.sound("whoosh", global_position, -8.0)
	Game.stat_add("vaults")
	parkour_timer = maxf(parkour_timer, 1.0)
	return true


## Curbs and other low steps: the capsule meets their edge at a wall-like angle and would stop
## dead, so when running is blocked by something no taller than STEP_HEIGHT, step up onto it.
const STEP_HEIGHT := 0.45

func _step_up(delta: float) -> void:
	if not is_on_wall():
		return
	var hv := Vector3(pre_move_velocity.x, 0, pre_move_velocity.z)
	if hv.length() < 1.0:
		return
	var move := hv * delta
	if move.length() < 0.05:
		move = hv.normalized() * 0.05
	var up := Vector3.UP * STEP_HEIGHT
	var t := global_transform
	if test_move(t, up):
		return   # something overhead
	t.origin += up
	if test_move(t, move):
		return   # still blocked when lifted: a real wall
	t.origin += move
	var hit := KinematicCollision3D.new()
	if not test_move(t, -up - Vector3.UP * 0.05, hit):
		return   # nothing to stand on (a ledge, not a step)
	if hit.get_normal().y < 0.7:
		return
	global_position = t.origin + hit.get_travel()
	velocity.x = hv.x
	velocity.z = hv.z


## Keeps a vault flowing: if the arc clips the obstacle's edge, slide up over it at full
## speed instead of stopping against it.
func _vault_assist(delta: float) -> void:
	_vault_t -= delta
	if state != State.AIR:
		_vault_t = 0.0
		return
	if not is_on_wall():
		return
	var dir := Vector3(pre_move_velocity.x, 0, pre_move_velocity.z)
	if dir.length() < 1.0 or Vector3(velocity.x, 0, velocity.z).length() > _vault_speed * 0.9:
		return
	dir = dir.normalized()
	global_position.y += 0.2
	velocity.x = dir.x * _vault_speed
	velocity.z = dir.z * _vault_speed
	velocity.y = maxf(velocity.y, 3.0)


func _ground_jump() -> void:
	var hspeed := Vector3(velocity.x, 0, velocity.z).length()
	var running := hspeed > walk_speed * 1.3
	# horizontal velocity is left untouched: jumping never slows you down
	velocity.y = (run_jump_velocity if running else jump_velocity) * sqrt(jump_mult) * powers.jump_factor()
	if running and powers.legs == PlayerPowers.Legs.RUNNER:
		velocity.x *= 1.15
		velocity.z *= 1.15
	state = State.AIR
	air_press = false
	double_jump_ready = true
	dash_ready = true
	boost_timer = jump_boost_time
	boost_held = 0.0
	_super_done = false
	_takeoff = global_position + Vector3.DOWN * 0.9
	model.scale = Vector3(0.8, 1.25, 0.8)
	if running:
		Game.fx.debris(_takeoff + Vector3.UP * 0.1, 5, Color(0.5, 0.48, 0.45))
	Game.fx.sound("jump", global_position, -6.0)


## While jump stays held right after take-off, keep pushing upward.
func _jump_boost(delta: float) -> void:
	if boost_timer <= 0.0:
		charging = false
		return
	if not Input.is_action_pressed("jump"):
		boost_timer = 0.0
		charging = false
		return
	boost_timer -= delta
	boost_held += delta
	velocity.y += jump_boost_accel * jump_mult * powers.jump_factor() * delta
	charging = true
	charge = clampf(boost_held / jump_boost_time, 0.0, 1.0)
	# energy gathering into the body while the jump charges
	_charge_fx_t -= delta
	if _charge_fx_t <= 0.0 and not _super_done:
		_charge_fx_t = 0.045
		var a := randf() * TAU
		var r := lerpf(1.6, 0.9, charge)
		var from := global_position + Vector3(cos(a) * r, randf_range(-0.9, 0.6), sin(a) * r)
		Game.fx.tendril_flash(from, global_position + Vector3.DOWN * 0.2, 0.1, lerpf(0.03, 0.07, charge))
	if not _super_done and boost_held > jump_boost_time * 0.6:
		_super_done = true
		model.oneshot("NinjaJump_Start", 1.8)
		Game.stat_add("super_jumps")
		trauma = minf(1.0, trauma + 0.25)
		parkour_timer = 2.0
		Game.fx.shockwave(_takeoff, 4.0, Color(1, 0.9, 0.8, 0.6), 0.3)
		Game.fx.debris(_takeoff + Vector3.UP * 0.1, 10)
		Game.fx.sound("land", _takeoff, -4.0)


func _state_air(delta: float) -> void:
	_jump_boost(delta)
	velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)
	_air_steer(delta)
	if Input.is_action_just_pressed("jump"):
		air_press = true
		if double_jump_ready:
			_double_jump()
	if air_press and Input.is_action_pressed("jump") and velocity.y < 0.0 and Game.has_skill("glide"):
		state = State.GLIDE
		Game.fx.sound("glide", global_position, -10.0)
		return
	_air_common()


func _air_steer(delta: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	if wish.length() > 0.1:
		var keep := maxf(hv.length(), walk_speed * 1.2)
		hv = hv.move_toward(wish * keep, air_accel * (1.6 if powers.is_light() else 1.0) * delta)
		velocity.x = hv.x
		velocity.z = hv.z


func _air_common() -> void:
	if (Input.is_action_just_pressed("dash") and not Input.is_action_pressed("devastator_mod")) and dash_ready and dash_cooldown_timer <= 0.0 and powers.can_move():
		if Game.has_skill("air_dash"):
			_start_dash()
			return
		Game.locked_message("air_dash")
	if (sprinting or powers.clings_to_walls()) and wall_cooldown <= 0.0:
		var dir := wish
		if dir.length() < 0.3:
			dir = Vector3(velocity.x, 0, velocity.z).normalized()
		var n := _wall_ahead(dir)
		if n != Vector3.ZERO:
			_enter_wall(n)


func _double_jump() -> void:
	boost_timer = 0.0
	charging = false
	velocity.y = maxf(velocity.y, double_jump_velocity * sqrt(jump_mult) * (1.0 + (powers.jump_factor() - 1.0) * 0.5))
	if wish.length() > 0.1:
		velocity += wish * double_jump_boost
	double_jump_ready = false
	# a flip: sideways input does a side flip, otherwise a front flip or a corkscrew
	var right := Basis.looking_at(facing, Vector3.UP).x
	var side := wish.dot(right)
	if absf(side) > 0.6:
		start_trick("sideflip", 0.5, signf(side))
	else:
		start_trick("frontflip" if randf() < 0.6 else "corkscrew", 0.52)
	model.scale = Vector3(0.8, 1.25, 0.8)
	Game.fx.burst_ring(global_position + Vector3.DOWN * 0.8, Color(1, 0.3, 0.2, 0.6), 2.5)
	Game.fx.sound("jump", global_position, -4.0)
	parkour_timer = maxf(parkour_timer, 1.0)


func _state_glide(delta: float) -> void:
	conspicuous_timer = maxf(conspicuous_timer, 1.5)   # nobody forgets seeing a man fly
	if Input.is_action_just_pressed("jump") and flaps_left > 0:
		flaps_left -= 1
		velocity.y = 14.0 * (1.3 if powers.defense == PlayerPowers.Defense.WINGS or powers.creature == PlayerPowers.Creature.WRAITH else 1.0)
		model.flap()
		model.scale = Vector3(1.3, 0.8, 1.3)
		Game.fx.burst_ring(global_position, Color(0.8, 0.1, 0.06, 0.6), 3.0)
		Game.fx.sound("whoosh", global_position, 0.0)
		return
	if not Input.is_action_pressed("jump"):
		state = State.AIR
		return
	var hv := Vector3(velocity.x, 0, velocity.z)
	var speed := hv.length()
	var dir := hv.normalized() if speed > 0.5 else facing
	var target_dir := wish.normalized() if wish.length() > 0.1 else dir
	var ang := dir.signed_angle_to(target_dir, Vector3.UP)
	dir = dir.rotated(Vector3.UP, clampf(ang, -glide_turn * delta, glide_turn * delta))
	var wing_form := powers.defense == PlayerPowers.Defense.WINGS or powers.creature == PlayerPowers.Creature.WRAITH
	var gs := glide_speed * jump_mult * (1.55 if wing_form else 1.0)
	if speed < gs:
		speed = move_toward(speed, gs, 14.0 * delta)
	else:
		speed = move_toward(speed, gs, 5.0 * delta)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = move_toward(velocity.y, -glide_fall_speed / jump_mult * (0.6 if wing_form else 1.0), gravity * 1.3 * delta)
	_air_common()


func max_flaps() -> int:
	if powers.creature == PlayerPowers.Creature.WRAITH:
		return 999   # the Wraith really flies
	return Game.skill_rank("wings") + (3 if powers.defense == PlayerPowers.Defense.WINGS else 0)


func _start_dash() -> void:
	boost_timer = 0.0
	charging = false
	dash_dir = wish.normalized() if wish.length() > 0.1 else Vector3.FORWARD.rotated(Vector3.UP, yaw)
	dash_timer = dash_time
	dash_cooldown_timer = dash_cooldown
	if state != State.GROUND:
		dash_ready = false
	if state != State.GROUND and state != State.DASH:
		start_trick("barrel", dash_time + 0.15, 1.0 if randf() < 0.5 else -1.0)
	# a dash along the street is parkour; one through the air is flying
	if state == State.GROUND:
		parkour_timer = maxf(parkour_timer, 1.5)
	else:
		conspicuous_timer = maxf(conspicuous_timer, 1.5)
	state = State.DASH
	trauma = minf(1.0, trauma + 0.12)
	Game.fx.sound("dash", global_position, -4.0)
	Game.fx.burst_ring(global_position, Color(1, 0.4, 0.3, 0.5), 1.8)


func _state_dash(delta: float) -> void:
	dash_timer -= delta
	velocity = dash_dir * dash_speed * speed_mult
	velocity.y = -1.0 if is_on_floor() else 0.0
	if sprinting and wall_cooldown <= 0.0:
		var n := _wall_ahead(dash_dir)
		if n != Vector3.ZERO:
			_enter_wall(n)
			return
	if dash_timer <= 0.0:
		var exit_speed := sprint_speed * speed_mult if sprinting else walk_speed * 1.6
		velocity = dash_dir * exit_speed
		state = State.GROUND if is_on_floor() else State.AIR


# ------------------------------------------------------------------ wall running

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return Game.raycast(from, to, Game.LAYER_WORLD)


func _wall_ahead(dir: Vector3) -> Vector3:
	if dir.length() < 0.3:
		return Vector3.ZERO
	var d := Vector3(dir.x, 0, dir.z).normalized()
	var from := global_position + Vector3.UP * 0.3
	var hit := _ray(from, from + d * (CAPSULE_RADIUS + 0.5))
	if hit.is_empty():
		return Vector3.ZERO
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.3:
		return Vector3.ZERO
	var nh := Vector3(n.x, 0, n.z).normalized()
	if d.dot(-nh) < 0.55:
		return Vector3.ZERO
	return nh


func _enter_wall(n: Vector3) -> void:
	state = State.WALL
	boost_timer = 0.0
	charging = false
	flaps_left = max_flaps()
	Game.stat_add("wall_runs")
	wall_normal = n
	charging = false
	double_jump_ready = true
	dash_ready = true
	air_press = false
	var hspeed := Vector3(velocity.x, 0, velocity.z).length()
	velocity = Vector3.UP * maxf(velocity.y, minf(hspeed, wall_run_speed)) - n * 2.0
	parkour_timer = maxf(parkour_timer, 2.0)


func _state_wall(delta: float) -> void:
	var center := global_position + Vector3.UP * 0.2
	var hit := _ray(center, center - wall_normal * (CAPSULE_RADIUS + 0.6))
	if hit.is_empty():
		_leave_wall_edge()
		return
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.3:
		_leave_wall_edge()
		return
	wall_normal = Vector3(n.x, 0, n.z).normalized()
	var cling := powers.clings_to_walls()
	if not sprinting and not cling:
		_detach(2.5)
		return
	var into := wish.dot(-wall_normal)
	if cling and wish.length() < 0.2:
		# Crawler legs: hang on the wall
		velocity = velocity.move_toward(-wall_normal * 1.5, wall_accel * delta)
		if Input.is_action_just_pressed("jump"):
			_wall_jump()
		return
	if wish.length() < 0.2 or into < -0.4:
		_detach(5.0)
		return
	var side := wish + wall_normal * into
	# switch onto a wall we run into sideways (inside corners)
	if side.length() > 0.3:
		var side_hit := _ray(center, center + side.normalized() * (CAPSULE_RADIUS + 0.45))
		if not side_hit.is_empty():
			var sn: Vector3 = side_hit["normal"]
			if absf(sn.y) < 0.3:
				wall_normal = Vector3(sn.x, 0, sn.z).normalized()
				return
	var dir := Vector3.UP * maxf(into, 0.0) + side
	if dir.length() > 1.0:
		dir = dir.normalized()
	if dir.length() > 0.05:
		wall_dir = dir.normalized()
	var light := PlayerPowers.LIGHT_SPEED if powers.is_light() else 1.0
	var target := dir * wall_run_speed * speed_mult * light * (1.25 if cling else 1.0) - wall_normal * wall_stick
	velocity = velocity.move_toward(target, wall_accel * delta)
	parkour_timer = maxf(parkour_timer, 1.0)
	if Input.is_action_just_pressed("jump"):
		_wall_jump()
	elif (Input.is_action_just_pressed("dash") and not Input.is_action_pressed("devastator_mod")) and powers.can_move() and Game.has_skill("air_dash"):
		dash_ready = true
		state = State.AIR
		wall_cooldown = 0.3
		_start_dash()


func _leave_wall_edge() -> void:
	state = State.AIR
	wall_cooldown = 0.25
	if velocity.y > 4.0:
		velocity = Vector3.UP * ledge_vault_up - wall_normal * ledge_vault_forward
		model.scale = Vector3(0.85, 1.2, 0.85)
		facing = -wall_normal
		start_trick("frontflip", 0.45)


func _detach(push: float) -> void:
	state = State.AIR
	wall_cooldown = 0.35
	velocity += wall_normal * push
	velocity.y = minf(velocity.y, 6.0)


func _wall_jump() -> void:
	var along := velocity - wall_normal * velocity.dot(wall_normal)
	along.y = 0.0
	velocity = wall_normal * wall_jump_push + Vector3.UP * wall_jump_up + along * 0.5
	state = State.AIR
	wall_cooldown = 0.3
	air_press = true
	double_jump_ready = true
	facing = wall_normal
	model.scale = Vector3(0.8, 1.25, 0.8)
	Game.fx.sound("jump", global_position, -5.0)
	start_trick("backflip", 0.55)


# ------------------------------------------------------------------ special movement

func start_tether(point: Vector3) -> void:
	tether_point = point
	tether_timer = 0.0
	state = State.TETHER
	charging = false
	double_jump_ready = true
	dash_ready = true
	if tether_line == null or not is_instance_valid(tether_line):
		tether_line = Game.fx.make_tendril(0.1)
	tether_line.visible = true
	conspicuous_timer = 2.0


func _state_tether(delta: float) -> void:
	tether_timer += delta
	var to := tether_point - global_position
	var dist := to.length()
	velocity = to.normalized() * minf(62.0, 20.0 + tether_timer * 120.0)
	if tether_line:
		Game.fx.orient_line(tether_line, global_position + Vector3.UP * 0.4, tether_point, 0.1)
	var stuck := tether_timer > 0.35 and get_real_velocity().length() < 4.0
	if dist < 2.2 or tether_timer > 2.5 or stuck:
		_end_tether()
		if is_on_wall() and sprinting:
			_enter_wall(get_wall_normal() * Vector3(1, 0, 1))


func _end_tether() -> void:
	state = State.AIR
	velocity = velocity * 0.45 + Vector3.UP * 7.0
	if tether_line:
		tether_line.visible = false


func start_dive(power: float) -> void:
	dive_power = power
	state = State.DIVE
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	velocity = fwd * 10.0 + Vector3.DOWN * 70.0
	conspicuous_timer = 2.0


func _state_dive(_delta: float) -> void:
	velocity.y = -75.0
	if is_on_floor():
		state = State.GROUND


## Freeze movement briefly (consuming, devastators). mode is the pose.
func lock(duration: float, mode := "idle") -> void:
	lock_timer = duration
	lock_mode = mode
	state = State.LOCKED
	charging = false


func _state_locked(delta: float) -> void:
	lock_timer -= delta
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, 60.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if lock_mode == "float":
		velocity.y = move_toward(velocity.y, 1.0, 40.0 * delta)
	elif not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -1.0
	if lock_timer <= 0.0:
		state = State.GROUND if is_on_floor() else State.AIR


# ------------------------------------------------------------------ vehicles

func enter_vehicle(v: Node) -> void:
	vehicle = v
	state = State.PILOT
	charging = false
	visual.visible = false
	collision.disabled = true
	velocity = Vector3.ZERO


func exit_vehicle(launch := Vector3(0, 12, 0)) -> void:
	if vehicle == null:
		return
	var v := vehicle as Node3D
	vehicle = null
	visual.visible = true
	collision.disabled = false
	global_position = v.global_position + Vector3.UP * 3.5
	velocity = launch
	state = State.AIR
	invuln_timer = 1.0
	reset_physics_interpolation()


func _state_pilot(_delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		exit_vehicle()
		return
	global_position = (vehicle as Node3D).global_position + Vector3.UP * 1.0


# ------------------------------------------------------------------ health

func take_hit(info: Dictionary) -> void:
	if state == State.DEAD or invuln_timer > 0.0:
		return
	var src: Node = info["source"]
	if src != null and is_instance_valid(src) and src.get("is_ally") == true:
		return
	if state == State.PILOT and vehicle and is_instance_valid(vehicle):
		vehicle.take_hit(info)
		return
	var dmg: float = info["damage"]
	dmg = powers.modify_incoming(dmg, info)
	if dmg <= 0.0:
		return
	health -= dmg
	time_since_damage = 0.0
	hits_taken_recent += dmg / 25.0
	health_changed.emit(health, max_health)
	if Game.hud and Game.hud.has_method("flash_damage"):
		Game.hud.flash_damage(clampf(dmg / 30.0, 0.15, 1.0))
	var force: Vector3 = info["force"]
	if force.length() > 9.0 and not powers.unstoppable() and state in [State.GROUND, State.AIR, State.GLIDE]:
		velocity += force * 0.6
		if state == State.GROUND and force.y > 3.0:
			state = State.AIR
	if health <= 0.0:
		die()


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)


func die() -> void:
	if state == State.DEAD:
		return
	if vehicle:
		exit_vehicle()
	health = 0.0
	state = State.DEAD
	dead_timer = 4.5
	charging = false
	powers.on_death()
	Game.fx.splat(global_position, Vector3.UP, Color(0.5, 0.02, 0.02), 30)
	Game.fx.sound("death", global_position, 0.0)
	died.emit()
	Game.player_died.emit()


func _state_dead(delta: float) -> void:
	dead_timer -= delta
	velocity.x = move_toward(velocity.x, 0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0, 20.0 * delta)
	velocity.y -= gravity * delta
	if dead_timer <= 0.0:
		var away := Game.last_known_pos if Game.is_hunted() else global_position
		var p: Vector3 = Game.city.random_roof_point(away, 120.0, 260.0)
		Game.set_alert(Game.Alert.HIDDEN)
		Game.heat = 0.0
		respawn(p)
		Game.player_respawned.emit()


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


## Would a soldier who sees you right now find you suspicious?
## Parkour is fine in a disguise that fits where you are. Flying, visible powers, carrying people or
## cars and smashing things never are, and inside a base or lab any running around gives you away.
func is_conspicuous() -> bool:
	if conspicuous_timer > 0.0:
		return true
	if is_flying():
		return true
	if powers.looks_inhuman():
		return true
	return is_doing_parkour() and Game.in_restricted_area(global_position)


## Why soldiers would notice you right now ("" = you blend in). Shown on the HUD near soldiers.
func stand_out_reason() -> String:
	if Game.is_trespassing(global_position):
		return "you don't belong here"
	if is_flying() or (conspicuous_timer > 0.0 and state != State.GROUND):
		return "flying"
	if powers.held != null:
		return "carrying something"
	if powers.looks_inhuman():
		return "powers showing"
	if conspicuous_timer > 0.0:
		return "making a scene"
	if is_doing_parkour() and Game.in_restricted_area(global_position):
		return "running around a restricted area"
	return ""


## Gliding, wing flaps, air dashes, tether zips and dive bombs.
func is_flying() -> bool:
	if state in [State.GLIDE, State.TETHER, State.DIVE]:
		return true
	return state == State.DASH and not is_on_floor()


func is_doing_parkour() -> bool:
	if parkour_timer > 0.0 or state in [State.WALL, State.DASH]:
		return true
	if state == State.AIR and absf(velocity.y) > 14.0:
		return true
	return Vector3(velocity.x, 0, velocity.z).length() > walk_speed * 1.35


func is_dead() -> bool:
	return state == State.DEAD


func eye_position() -> Vector3:
	return global_position + Vector3.UP * 0.7


## Where the center of the screen points (for throwing, tether and guns).
var aim_override := Vector3.INF   # tests: aim at a fixed point instead of the screen centre


func aim_point(max_dist := 200.0, mask := Game.LAYER_WORLD | Game.MASK_HITTABLE) -> Dictionary:
	if aim_override != Vector3.INF:
		return {"position": aim_override, "collider": null, "normal": Vector3.UP}
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	# start the ray at the player's depth so we don't hit things behind them
	var skip := maxf(0.0, (global_position - from).dot(dir) - 0.5)
	from += dir * skip
	var hit := Game.raycast(from, from + dir * max_dist, mask, [get_rid()])
	if hit.is_empty():
		return {"position": from + dir * max_dist, "collider": null, "normal": Vector3.UP}
	return hit


func aim_direction() -> Vector3:
	return -camera.global_transform.basis.z


func face(dir: Vector3, duration := 0.3) -> void:
	var d := Vector3(dir.x, 0, dir.z)
	if d.length() < 0.01:
		return
	face_override = d.normalized()
	face_override_timer = duration


# ------------------------------------------------------------------ physics helpers

func _push_props() -> void:
	var pre_h := Vector3(pre_move_velocity.x, 0, pre_move_velocity.z)
	var pre_speed := pre_h.length()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var collider := c.get_collider()
		var n := c.get_normal()
		if absf(n.y) > 0.5:
			continue
		if collider is RigidBody3D:
			var rb := collider as RigidBody3D
			if pre_speed < 8.0:
				continue
			var mult := 1.4 if powers.is_armored() else 0.6
			rb.sleeping = false
			rb.apply_central_impulse((-n * pre_speed * 0.5 + Vector3.UP * pre_speed * 0.2) * rb.mass * mult)
			if rb.has_method("take_hit"):
				rb.take_hit(Game.hit_info(pre_speed * 0.6, Vector3.ZERO, self, "impact"))
			velocity.x = pre_h.x * 0.8
			velocity.z = pre_h.z * 0.8
		elif collider is CharacterBody3D and collider.has_method("take_hit") and pre_speed > 14.0:
			# super-speed body check
			var dmg := pre_speed * (1.6 if powers.is_armored() else 0.7)
			collider.take_hit(Game.hit_info(dmg, pre_h.normalized() * pre_speed * 0.9 + Vector3.UP * 6.0, self, "impact"))
			velocity.x = pre_h.x * 0.9
			velocity.z = pre_h.z * 0.9


func _check_landing() -> void:
	if not is_on_floor() or velocity.y > 0.1:
		return
	if state in [State.AIR, State.GLIDE, State.DIVE, State.TETHER]:
		var impact := fall_speed_before_move
		var was_dive := state == State.DIVE
		var from_vault := _vault_t > 0.0 and state == State.AIR
		_vault_t = 0.0
		if state == State.TETHER and tether_line:
			tether_line.visible = false
		state = State.GROUND
		double_jump_ready = true
		dash_ready = true
		air_press = false
		flaps_left = max_flaps()
		var stomp_at := heavy_landing_speed
		if powers.legs in [PlayerPowers.Legs.LEAPER, PlayerPowers.Legs.CRUSHER]:
			stomp_at = 16.0
		var moving_on := sprinting and wish.length() > 0.3
		if from_vault:
			return   # a vault lands straight back into the run: no roll, no squash
		if impact > 16.0 and moving_on and not was_dive:
			start_trick("roll", 0.5)
			Game.fx.debris(global_position + Vector3.DOWN * 0.8, 6, Color(0.5, 0.48, 0.45))
		elif (was_dive or impact > stomp_at) and not moving_on:
			_hero_t = 0.55
		if was_dive:
			_heavy_landing(maxf(impact, 60.0), true)
		elif impact > stomp_at:
			_heavy_landing(impact * (1.25 if powers.legs == PlayerPowers.Legs.CRUSHER else 1.0), false)
		elif impact > 8.0 and trick != "roll":
			model.scale = Vector3(1.2, 0.8, 1.2)


func _heavy_landing(impact: float, dive: bool) -> void:
	var strength := clampf((impact - heavy_landing_speed) / 30.0 + 0.4, 0.4, 1.0)
	trauma = minf(1.0, trauma + 0.45 * strength + 0.15)
	model.scale = Vector3(1.45, 0.55, 1.45)
	var feet := global_position + Vector3.DOWN * 0.9
	var radius := shockwave_radius * strength + 3.0
	var force := shockwave_force * strength
	var damage := 25.0 * strength
	if dive:
		radius *= 1.3 * dive_power
		force *= 1.5
		damage = 70.0 * dive_power
	damage *= damage_mult
	Game.fx.shockwave(feet, radius)
	Game.fx.debris(feet + Vector3.UP * 0.2, int(10 + strength * 14))
	Game.fx.sound("land", global_position, 2.0 * strength)
	Game.damage_area(feet + Vector3.UP * 0.5, radius, damage, force, self, "slam", Game.MASK_HITTABLE)
	Game.panic_at(feet, radius * 3.0)
	conspicuous_timer = 3.0
	# land running if you're still holding a direction; otherwise the impact slows you
	if not (sprinting and wish.length() > 0.3):
		var hv := Vector3(velocity.x, 0, velocity.z) * 0.55
		velocity.x = hv.x
		velocity.z = hv.z
	powers.on_heavy_landing(feet, strength, dive)


# ------------------------------------------------------------------ visuals and camera

func start_trick(kind: String, length: float, dir := 1.0) -> void:
	trick = kind
	_trick_t = 0.0
	_trick_len = length
	_trick_dir = dir
	if kind in ["frontflip", "backflip", "corkscrew", "sideflip"]:
		Game.fx.sound("whoosh", global_position, -10.0, 0.25)


const POSE_TUCK := {"la": Vector3(1.9, 0, -0.35), "ra": Vector3(1.9, 0, 0.35), "lf": 1.6, "rf": 1.6,
	"ll": Vector3(1.8, 0, -0.1), "rl": Vector3(1.8, 0, 0.1), "lk": -2.3, "rk": -2.3, "speed": 28.0}
const POSE_HERO := {"ll": Vector3(1.6, 0, -0.15), "lk": -2.2, "rl": Vector3(-0.35, 0, 0.12), "rk": -2.1,
	"ra": Vector3(0.5, 0, 0.18), "rf": 0.0, "la": Vector3(-0.6, 0, -0.9), "lf": 0.7, "speed": 30.0}
## charging a held jump: knees pulled up, arms swept down and back, coiled to spring
const POSE_COIL := {"la": Vector3(-0.95, 0, -0.3), "ra": Vector3(-0.95, 0, 0.3), "lf": 0.7, "rf": 0.7,
	"ll": Vector3(1.35, 0, -0.14), "rl": Vector3(1.2, 0, 0.14), "lk": -2.0, "rk": -1.8, "speed": 22.0}
const POSE_ROCKET := {"la": Vector3(-0.55, 0, -0.35), "ra": Vector3(-0.55, 0, 0.35), "lf": 0.1, "rf": 0.1,
	"ll": Vector3(0.15, 0, 0), "rl": Vector3(-0.1, 0, 0), "lk": -0.15, "rk": -0.6}
const POSE_SKYDIVE := {"la": Vector3(0.5, 0, -1.5), "ra": Vector3(0.5, 0, 1.5), "lf": 0.5, "rf": 0.5,
	"ll": Vector3(-0.4, 0, -0.18), "rl": Vector3(-0.4, 0, 0.18), "lk": -0.8, "rk": -0.8, "speed": 6.0}
const POSE_LONGJUMP := {"ll": Vector3(1.1, 0, 0), "lk": -0.4, "rl": Vector3(-0.7, 0, 0), "rk": -1.3,
	"la": Vector3(-1.0, 0, -0.45), "ra": Vector3(1.1, 0, 0.3), "lf": 0.4, "rf": 0.6}
const POSE_NINJA := {"la": Vector3(-1.05, 0, -0.3), "ra": Vector3(-1.05, 0, 0.3), "lf": 0.25, "rf": 0.25}


func _update_visual(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var hspeed := hv.length()
	var target_basis: Basis
	var target_offset := Vector3.ZERO
	var mode := "idle"
	var pose := {}
	var extra := Basis.IDENTITY
	if state == State.WALL:
		var up_v := wall_normal if absf(wall_dir.dot(wall_normal)) < 0.95 else Vector3.UP
		target_basis = Basis.looking_at(wall_dir, up_v)
		target_offset = wall_normal * 0.45
		mode = "run"
		# lean back off the wall a little when running straight up it
		if wall_dir.y > 0.7:
			target_basis = target_basis.rotated(target_basis.x, 0.12)
	else:
		if face_override_timer > 0.0:
			facing = face_override
		elif hspeed > 1.0 and state != State.LOCKED:
			facing = hv.normalized()
		target_basis = Basis.looking_at(facing, Vector3.UP)
		match state:
			State.GLIDE:
				target_basis = target_basis.rotated(target_basis.x, -1.25)
				mode = "glide"
			State.DASH:
				# on the ground a dash is a slide (the animation gets low by itself); in the air, a dive
				if is_on_floor():
					mode = "slide"
				else:
					target_basis = target_basis.rotated(target_basis.x, -1.3)
					mode = "glide"
			State.DIVE:
				target_basis = target_basis.rotated(target_basis.x, -0.4)
				mode = "crouch"
			State.TETHER:
				target_basis = target_basis.rotated(target_basis.x, -0.5)
				mode = "air"
			State.AIR:
				mode = "air"
				if charging and not _super_done:
					pose = POSE_COIL
					target_basis = target_basis.rotated(target_basis.x, 0.3 * charge)
				elif _super_done and velocity.y > 6.0:
					pose = POSE_ROCKET
				elif velocity.y < -24.0:
					pose = POSE_SKYDIVE
					target_basis = target_basis.rotated(target_basis.x, -0.75)
				elif hspeed > 16.0 and velocity.y > -6.0:
					pose = POSE_LONGJUMP
					target_basis = target_basis.rotated(target_basis.x, -0.2)
			State.LOCKED:
				mode = lock_mode if lock_mode != "float" else "glide"
			State.DEAD:
				target_basis = target_basis.rotated(target_basis.x, 1.4)
				target_offset = Vector3.DOWN * 0.6
				mode = "dead"
			_:
				if hspeed > walk_speed * 1.3:
					mode = "run"
					# the faster you go, the harder you lean in
					var lean := lerpf(0.28, 0.5, clampf((hspeed - 14.0) / 14.0, 0.0, 1.0))
					if model.hold_anim != "" or model.carrying != "":
						lean *= 0.35   # stay upright with a gun, a blade or someone in your arms
					target_basis = target_basis.rotated(target_basis.x, -lean)
					if hspeed > 23.0:
						pose = POSE_NINJA
				elif hspeed > 0.8:
					mode = "walk"
	# bank into turns
	var turn := _last_facing.signed_angle_to(facing, Vector3.UP) / maxf(real, 0.001)
	_last_facing = facing
	var bank_target := 0.0
	if state in [State.GROUND, State.GLIDE, State.AIR] and hspeed > 10.0:
		bank_target = clampf(-turn * 0.09 * clampf(hspeed / 20.0, 0.5, 1.5), -0.55, 0.55)
	_bank = lerpf(_bank, bank_target, 1.0 - exp(-6.0 * real))
	# tricks override the pose and add a spin on top of the base orientation
	if trick != "":
		_trick_t += real
		var t := clampf(_trick_t / _trick_len, 0.0, 1.0)
		var e := t * t * (3.0 - 2.0 * t)
		match trick:
			"frontflip":
				extra = Basis(Vector3.RIGHT, -TAU * e)
				pose = POSE_TUCK
			"backflip":
				extra = Basis(Vector3.RIGHT, TAU * e)
				pose = POSE_TUCK
			"corkscrew":
				extra = Basis(Vector3.UP, TAU * e * _trick_dir) * Basis(Vector3.RIGHT, -TAU * e)
				pose = POSE_TUCK
			"sideflip":
				extra = Basis(Vector3.BACK, TAU * e * _trick_dir)
				pose = POSE_TUCK
			"barrel":
				extra = Basis(Vector3.BACK, TAU * e * _trick_dir)
				pose = {"la": Vector3(3.0, 0, -0.2), "ra": Vector3(-0.3, 0, 0.3), "lf": 0.0, "rf": 0.3,
					"ll": Vector3(-0.2, 0, -0.1), "rl": Vector3(-0.2, 0, 0.1), "lk": -0.3, "rk": -0.5}
			"roll":
				extra = Basis(Vector3.RIGHT, -TAU * e)
				target_offset += Vector3.DOWN * 0.45 * sin(PI * t)
				pose = POSE_TUCK
			"vault":
				pass   # the climb-over animation does the whole move (see _try_vault)
		if t >= 1.0 or (trick != "roll" and state in [State.WALL, State.DEAD, State.PILOT]):
			trick = ""
		elif trick != "roll" and trick != "vault" and is_on_floor() and _trick_t > 0.12:
			trick = ""
	if _hero_t > 0.0:
		_hero_t -= real
		var ht := clampf(_hero_t / 0.55, 0.0, 1.0)
		pose = POSE_HERO
		extra = Basis(Vector3.RIGHT, -0.55 * minf(1.0, ht * 3.0))
		target_offset += Vector3.DOWN * 0.42 * minf(1.0, ht * 3.0)
		if hspeed > 6.0 or state != State.GROUND:
			_hero_t = 0.0
	var k := 1.0 - exp(-14.0 * delta)
	_base_q = _base_q.slerp(target_basis.get_rotation_quaternion(), k)
	visual.basis = Basis(_base_q) * Basis(Vector3.BACK, _bank) * extra
	visual.position = visual.position.lerp(target_offset, 1.0 - exp(-20.0 * delta))
	var scale_target := Vector3.ONE
	coiling = pose == POSE_COIL
	if charging and not _super_done:
		# squash down as the charge builds, released into a stretch at the super jump
		scale_target = Vector3(1.0 + 0.14 * charge, 1.0 - 0.2 * charge, 1.0 + 0.14 * charge)
	var scale_rate := 30.0 if charging and not _super_done else 10.0
	model.scale = model.scale.lerp(scale_target, 1.0 - exp(-scale_rate * delta))
	var anim_speed := hspeed if state != State.WALL else velocity.length()
	model.wings_visible = Game.has_skill("wings")
	if not pose.is_empty():
		model.pose_override = pose
	model.vertical_speed = velocity.y
	model.animate(delta, anim_speed, mode)


func _update_camera(delta: float) -> void:
	var target: Vector3
	var dist := camera_distance
	if state == State.PILOT and vehicle and is_instance_valid(vehicle):
		target = (vehicle as Node3D).get_global_transform_interpolated().origin + Vector3.UP * 2.5
		dist = vehicle.camera_distance() if vehicle.has_method("camera_distance") else 12.0
	else:
		target = get_global_transform_interpolated().origin + Vector3.UP * camera_height
		if powers.has_method("camera_distance_override"):
			dist = powers.camera_distance_override(dist)
	pivot.global_position = pivot.global_position.lerp(target, 1.0 - exp(-18.0 * delta))
	pivot.rotation = Vector3(0, yaw, 0)
	pitch_node.rotation = Vector3(pitch, 0, 0)
	spring.spring_length = lerpf(spring.spring_length, dist, 1.0 - exp(-6.0 * delta))
	var speed := velocity.length()
	var t := clampf((speed - walk_speed) / (dash_speed - walk_speed), 0.0, 1.0)
	var fov0 := Settings.fov
	camera.fov = lerpf(camera.fov, lerpf(fov0, fov0 + (max_fov - base_fov), t), 1.0 - exp(-4.0 * delta))
	trauma = maxf(0.0, trauma - delta * 1.3)
	var s := trauma * trauma * Settings.camera_shake
	var roll_target := -_bank * 0.25
	if state == State.WALL and absf(wall_dir.y) < 0.6:
		roll_target = clampf(wall_normal.dot(pivot.global_transform.basis.x), -1.0, 1.0) * 0.12
	camera.rotation.z = lerpf(camera.rotation.z, roll_target, 1.0 - exp(-5.0 * delta))
	camera.h_offset = randf_range(-1.0, 1.0) * 0.45 * s
	camera.v_offset = randf_range(-1.0, 1.0) * 0.45 * s
