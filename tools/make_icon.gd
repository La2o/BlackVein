extends SceneTree
## Renders icon.svg to a 256 px PNG (then convert to icon.ico for the Windows build):
##   godot --headless --path . --script res://tools/make_icon.gd
##   python3 -c "from PIL import Image; Image.open('icon_256.png').save('icon.ico', sizes=[(16,16),(32,32),(48,48),(256,256)])"

func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	var img := Image.new()
	img.load_svg_from_string(svg, 2.0)
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://icon_256.png")
	print("icon ", img.get_size())
	quit()
