extends "res://scripts/humanoid.gd"
## The player's body: hooded default look, disguises, arm transformations,
## shield and armor.

enum Form { FISTS, CLAWS, HAMMER, BLADE, WHIP, MUSCLE }
enum Defense { NONE, SHIELD, ARMOR }

const FLESH := Color(0.42, 0.04, 0.05)
const DEFAULT_OUTFIT := {
	"shirt": Color(0.11, 0.115, 0.13), "pants": Color(0.17, 0.17, 0.19),
	"skin": Color(0.62, 0.48, 0.4), "gear": "hood", "gear_color": Color(0.09, 0.09, 0.1),
	"glow": Color(1, 0.16, 0.1),
}

var form: int = Form.FISTS
var defense: int = Defense.NONE
var outfit: Dictionary = DEFAULT_OUTFIT
var _form_parts: Array[MeshInstance3D] = []
var _defense_parts: Array[MeshInstance3D] = []
var _whip_links: Array[MeshInstance3D] = []
var _t := 0.0


func build(new_outfit: Dictionary = {}) -> void:
	outfit = DEFAULT_OUTFIT if new_outfit.is_empty() else new_outfit
	_form_parts.clear()
	_defense_parts.clear()
	_whip_links.clear()
	setup(outfit)
	_apply_form()
	_apply_defense()


func set_form(f: int) -> void:
	form = f
	_apply_form()


func set_defense(d: int) -> void:
	defense = d
	_apply_defense()


func _clear(list: Array[MeshInstance3D]) -> void:
	for n in list:
		all_meshes.erase(n)
		if is_instance_valid(n):
			n.queue_free()
	list.clear()


func _add(list: Array[MeshInstance3D], parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := _part(parent, mesh, material, pos)
	mi.rotation = rot
	mi.scale = scl
	list.append(mi)
	return mi


func _apply_form() -> void:
	if arm_l == null:
		return
	_clear(_form_parts)
	_whip_links.clear()
	arm_l.scale = Vector3.ONE
	arm_r.scale = Vector3.ONE
	var flesh := mat(FLESH, 0.5, 0.0, 0.35)
	var dark := mat(Color(0.07, 0.02, 0.02), 0.0, 0.3, 0.25)
	var glow := mat(Color(1, 0.12, 0.06), 2.5)
	match form:
		Form.CLAWS:
			for hand in [hand_l, hand_r]:
				for i in 3:
					var x := (i - 1) * 0.05
					_add(_form_parts, hand, box(Vector3(0.022, 0.6, 0.05)), dark, Vector3(x, -0.28, -0.03), Vector3(0.18, 0, (i - 1) * 0.12))
				_add(_form_parts, hand, sphere(0.1), flesh, Vector3(0, 0.02, 0))
		Form.HAMMER:
			for hand in [hand_l, hand_r]:
				_add(_form_parts, hand, sphere(0.27), flesh, Vector3(0, -0.12, 0))
				for k in 4:
					var a := k * TAU / 4.0
					_add(_form_parts, hand, box(Vector3(0.1, 0.2, 0.1)), dark, Vector3(cos(a) * 0.22, -0.18, sin(a) * 0.22), Vector3(0.5, a, 0.3))
			arm_l.scale = Vector3(1.35, 1.0, 1.35)
			arm_r.scale = Vector3(1.35, 1.0, 1.35)
		Form.BLADE:
			_add(_form_parts, arm_r, capsule(0.12, 0.6), flesh, Vector3(0, -0.45, 0))
			_add(_form_parts, hand_r, box(Vector3(0.05, 1.8, 0.26)), dark, Vector3(0, -0.92, 0))
			_add(_form_parts, hand_r, box(Vector3(0.06, 1.7, 0.03)), glow, Vector3(0, -0.92, -0.13))
		Form.WHIP:
			_add(_form_parts, arm_r, capsule(0.11, 0.65), flesh, Vector3(0, -0.4, 0))
			var parent: Node3D = hand_r
			for k in 9:
				var link := _add(_form_parts, parent, sphere(0.09 - k * 0.006), flesh if k % 2 == 0 else dark, Vector3(0, -0.16, 0))
				_whip_links.append(link)
				parent = link
		Form.MUSCLE:
			arm_l.scale = Vector3(1.75, 1.12, 1.75)
			arm_r.scale = Vector3(1.75, 1.12, 1.75)
			for arm in [arm_l, arm_r]:
				_add(_form_parts, arm, box(Vector3(0.03, 0.5, 0.03)), glow, Vector3(0.06, -0.3, -0.07), Vector3(0, 0, 0.2))
				_add(_form_parts, arm, sphere(0.13), flesh, Vector3(0, -0.05, 0))


func _apply_defense() -> void:
	if arm_l == null:
		return
	_clear(_defense_parts)
	var rock := mat(Color(0.1, 0.07, 0.07), 0.0, 0.3, 0.55)
	var glow := mat(Color(1, 0.12, 0.06), 2.0)
	match defense:
		Defense.SHIELD:
			var disc := CylinderMesh.new()
			disc.top_radius = 0.72
			disc.bottom_radius = 0.6
			disc.height = 0.09
			disc.radial_segments = 6
			_add(_defense_parts, arm_l, disc, rock, Vector3(0, -0.55, 0))
			var rim := CylinderMesh.new()
			rim.top_radius = 0.2
			rim.bottom_radius = 0.2
			rim.height = 0.12
			rim.radial_segments = 6
			_add(_defense_parts, arm_l, rim, glow, Vector3(0, -0.6, 0))
		Defense.ARMOR:
			_add(_defense_parts, self, capsule(0.33, 1.05), rock, Vector3(0, 0.17, 0))
			for arm in [arm_l, arm_r]:
				_add(_defense_parts, arm, capsule(0.12, 0.7), rock, Vector3(0, -0.32, 0))
				_add(_defense_parts, arm, box(Vector3(0.1, 0.25, 0.1)), rock, Vector3(0, 0.05, 0), Vector3(0, 0, 0.6 * signf(arm.position.x)))
			for leg in [leg_l, leg_r]:
				_add(_defense_parts, leg, capsule(0.135, 0.72), rock, Vector3(0, -0.31, 0))
			_add(_defense_parts, torso, box(Vector3(0.04, 0.4, 0.02)), glow, Vector3(0, 0.1, -0.33))


func animate(delta: float, speed: float, mode: String) -> void:
	super(delta, speed, mode)
	_t += delta
	if defense == Defense.SHIELD and mode in ["idle", "walk", "run", "air"] and swing_timer <= 0.0:
		var k := 1.0 - exp(-16.0 * delta)
		arm_l.rotation = arm_l.rotation.lerp(Vector3(1.5, 0.35, 0.15), k)
	if form == Form.WHIP and not _whip_links.is_empty():
		for i in _whip_links.size():
			var link := _whip_links[i]
			if is_instance_valid(link):
				link.rotation = Vector3(sin(_t * 3.0 + i * 0.6) * 0.15, 0, cos(_t * 2.3 + i * 0.5) * 0.12)
