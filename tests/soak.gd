extends Node
## Soak test: lets the whole game run with a bot pressing random buttons
## for a few minutes to shake out rare runtime errors.
##   godot --headless --path . res://tests/soak.tscn -- seconds=180

const MAIN := preload("res://scenes/main.tscn")
const ACTIONS := ["attack", "special", "grab", "consume", "dash", "tether", "decoy", "devastator_spikes",
	"devastator_tendrils", "cycle_defense", "form_next", "jump", "artillery", "thermal"]

var main: Node3D
var player: Player
var seconds := 180.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seconds="):
			seconds = float(a.substr(8))
	Game.use_test_storage()
	Game.delete_save()
	Game.reset_state()
	main = MAIN.instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	player = Game.player
	Game.level = 25
	Game.skill_points = 0
	for id in Game.SKILLS:
		Game.skills[id] = Game.SKILLS[id][5]
	Game.flags["artillery_codes"] = true
	player.apply_upgrades()
	Game.director._event_timer = 2.0
	var t := 0.0
	var next_event := 20.0
	var types: Array = Game.director.EVENT_TYPES.keys()
	var k := 0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		player.invuln_timer = 1.0
		player.biomass = player.max_biomass
		if player.is_dead():
			continue
		# wander and mash buttons
		if randf() < 0.02:
			player.yaw += randf_range(-1.5, 1.5)
		Input.action_press("move_forward")
		if randf() < 0.01:
			Input.action_press("sprint")
		if randf() < 0.01:
			Input.action_release("sprint")
		if randf() < 0.05:
			var a: String = ACTIONS[randi() % ACTIONS.size()]
			Input.action_press(a)
			get_tree().create_timer(0.05).timeout.connect(func(): Input.action_release(a))
		if t > next_event:
			next_event += 20.0
			Game.director.start_random_event(types[k % types.size()])
			k += 1
		if randf() < 0.002:
			Game.daynight.hour = randf() * 24.0
	print("SOAK DONE: %.0f s, %d units, level %d, fps %d" % [t, main.get_node("Units").get_child_count(), Game.level, Engine.get_frames_per_second()])
	Game.delete_save()
	get_tree().quit()
