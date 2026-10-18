extends Node
## Music: crossfades between the ambient, combat and boss loops depending on
## what is happening.

const TRACKS := ["ambient", "combat", "boss"]

var _players := {}
var _current := "ambient"
var _combat_hold := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for t in TRACKS:
		var path := "res://music/%s.wav" % t
		var p := AudioStreamPlayer.new()
		if ResourceLoader.exists(path):
			p.stream = load(path)   # loops via its .import settings
		p.volume_db = -80.0
		add_child(p)
		_players[t] = p
	if _players["ambient"].stream:
		_players["ambient"].play()


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	var want := "ambient"
	var p := Game.player
	if p:
		if p.time_since_damage < 1.0 or Game.combo > 2 or Game.is_hunted():
			_combat_hold = 8.0
		_combat_hold -= real
		if _combat_hold > 0.0:
			want = "combat"
		var b := Game.boss
		if b and is_instance_valid(b) and b.has_method("is_alive") and b.is_alive() and b.global_position.distance_to(p.global_position) < 220.0:
			want = "boss"
	_current = want
	var master := Settings.music_volume
	for t in TRACKS:
		var pl: AudioStreamPlayer = _players[t]
		if pl.stream == null:
			continue
		var target := linear_to_db(maxf(master * (1.0 if t == _current else 0.0), 0.0001))
		pl.volume_db = move_toward(pl.volume_db, target, real * (40.0 if t == _current else 25.0))
		if t == _current and not pl.playing:
			pl.play()
		elif t != _current and pl.playing and pl.volume_db <= -79.0:
			pl.stop()
