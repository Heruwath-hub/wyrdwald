extends SceneTree
## Renders the world map to PNG files (needs a display, e.g. xvfb-run, no --headless).
## godot --path . --script tests/shot_world.gd -- <seed> <out_dir>

var _scene: Node
var _frame := 0
var _out := "/tmp"
var _step := 0
var _seed_text := "7"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := args[0] if args.size() > 0 else "7"
	_out = args[1] if args.size() > 1 else "/tmp"
	root.size = Vector2i(1400, 850)
	_scene = (load("res://scenes/world/world_map.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_seed_text = seed_text

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_scene._seed_edit.text = _seed_text
		_scene._on_new_world()
	elif _frame == 6:
		_scene._distance = 112.0
		_scene._pitch = 80.0
		_scene._focus = Vector3.ZERO
		_scene._update_camera()
	elif _frame == 14:
		_save("terrain")
		_scene._overlay_pick.select(1)
		_scene._view.set_overlay(1)
	elif _frame == 22:
		_save("biome")
		_scene._overlay_pick.select(4)
		_scene._view.set_overlay(4)
	elif _frame == 30:
		_save("build")
		var s0: int = _scene._world.settlements.keys()[0]
		_scene._distance = 22.0
		_scene._pitch = 70.0
		_scene._focus = _scene._view.top_of(s0)
		_scene._update_camera()
	elif _frame == 34:
		_save("buildclose")
		_scene._overlay_pick.select(0)
		_scene._view.set_overlay(0)
		var site: int = _scene._world.settlements.keys()[0]
		var near := site
		for h in _scene._world.disc_indices(site, 5):
			if HexGrid.distance(_scene._world.coords[h], _scene._world.coords[site]) == 4 and _scene._world.passable(h):
				near = h
		_scene.set_process(false)
		_scene._shift = true
		_scene._set_hover(near)
		_scene._update_preview()
		_scene._distance = 16.0
		_scene._pitch = 55.0
		_scene._focus = _scene._view.top_of(site) + Vector3(0, 0, 2)
		_scene._update_camera()
	elif _frame == 44:
		_save("shift")
		_scene._shift = false
		_scene._update_preview()
		_scene._select(_scene._world.settlements.keys()[0])
		_scene._distance = 9.0
		_scene._pitch = 50.0
		_scene._focus = _scene._view.top_of(_scene._party.hex)
		_scene._update_camera()
	elif _frame == 52:
		_save("close")
		quit(0)
	return false

func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/world_%s.png" % [_out, name])
