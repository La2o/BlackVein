extends CharacterBody3D
## Biomass Decoy (original power): a glowing copy of the player that runs
## away, pulls enemy attention and fire, then explodes.

const HUMANOID := preload("res://scripts/humanoid.gd")

var dir := Vector3.FORWARD
var life := 8.0
var hp := 120.0
var model: Node3D
var _turn_timer := 0.0


func setup(direction: Vector3, outfit: Dictionary) -> void:
	dir = direction.normalized()
	collision_layer = Game.LAYER_NPC
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	add_child(shape)
	model = Node3D.new()
	model.set_script(HUMANOID)
	add_child(model)
	model.setup(outfit)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1, 0.15, 0.1, 0.35)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	model.set_tint(glow)
	add_to_group("decoys")
	add_to_group("warm")


func is_alive() -> bool:
	return hp > 0.0


func take_hit(info: Dictionary) -> void:
	if _popped:
		return
	hp -= float(info["damage"])
	if hp <= 0.0:
		_pop()


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_pop()
		return
	_turn_timer -= delta
	if is_on_wall() and _turn_timer <= 0.0:
		dir = dir.rotated(Vector3.UP, PI * 0.5 * (1.0 if randf() < 0.5 else -1.0))
		_turn_timer = 0.5
	velocity.x = dir.x * 10.0
	velocity.z = dir.z * 10.0
	velocity.y = -2.0 if is_on_floor() else velocity.y - 30.0 * delta
	move_and_slide()
	model.basis = Basis.looking_at(dir, Vector3.UP)
	model.animate(delta, 10.0, "run")


var _popped := false


func _pop() -> void:
	if _popped or not is_inside_tree():
		return
	_popped = true
	Game.explode(global_position, 7.0, 60.0, Game.player, 18.0)
	Game.fx.splat(global_position, Vector3.UP, Color(0.6, 0.05, 0.05), 30)
	queue_free()
