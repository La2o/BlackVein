extends Node3D
## Starts the game: builds the city, places the player, wires the systems
## together and loads the save file if there is one.

@onready var city: Node3D = $City
@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var military: Node = $Military
@onready var director: Node = $Director
@onready var daynight: Node = $DayNight
@onready var weather: Node = $Weather
@onready var sun: DirectionalLight3D = $Sun
@onready var world_env: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	Game.world = self
	Game.city = city
	Game.alert_level = Game.Alert.HIDDEN
	Game.heat = 0.0
	Engine.time_scale = 1.0
	var units := Node3D.new()
	units.name = "Units"
	add_child(units)
	military.units_parent = units
	director.units_parent = units
	city.build()
	Person.warm_up()
	var interiors := Node3D.new()
	interiors.name = "Interiors"
	interiors.set_script(load("res://scripts/interiors.gd"))
	add_child(interiors)
	interiors.setup(city)
	player.set_spawn(city.spawn_point, city.spawn_yaw)
	daynight.setup(sun, world_env.environment)
	weather.setup(world_env.environment)
	Settings.apply()
	hud.player = player
	if Game.has_save():
		Game.load_game()
	else:
		Game.say("Sprint into a wall to run up it", Color(1, 0.85, 0.7))
		get_tree().create_timer(6.0, false).timeout.connect(func():
			Game.feed("Tip: kill, consume and finish events to earn XP and unlock powers", Color(1, 0.85, 0.6)))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		get_tree().create_timer(2.0, false).timeout.connect(Game.feed.bind("Controller ready: " + Input.get_joy_name(pads[0]), Color(0.6, 0.9, 1)))
