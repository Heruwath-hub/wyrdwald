extends Node3D
## World map prototype: generates a continent from a seed and lets a party walk across it.
## Right click walks the party as far as today's AP allows. Left click selects an NPC settlement and
## shows its access area, left drag turns the camera, middle drag or WASD pans, the wheel zooms,
## Q/E turn, Space ends the day. Holding Shift previews a settlement at the hovered hex.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const CAMERA_PITCH := 58.0

var _world: WorldData
var _party: WorldParty
var _view := WorldView.new()
var _camera := Camera3D.new()
var _party_marker: Node3D
var _focus := Vector3.ZERO
var _yaw := 20.0
var _pitch := CAMERA_PITCH
var _distance := 26.0
var _hover := -1
var _walking := false
var _selected := -1
var _shift := false
var _claimed := {}
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragged := false

var _seed_edit := LineEdit.new()
var _start_pick := OptionButton.new()
var _season_pick := OptionButton.new()
var _overlay_pick := OptionButton.new()
var _weather_pick := OptionButton.new()
var _selection_label := Label.new()
var _status := Label.new()
var _hover_label := Label.new()
var _stats_label := Label.new()
var _end_day := Button.new()
var _start_ids: Array[String] = []


func _ready() -> void:
	_build_environment()
	add_child(_view)
	_camera.fov = 45.0
	_camera.far = 500.0
	add_child(_camera)
	_camera.make_current()
	_build_ui()
	_generate(_random_seed())


# ---------------------------------------------------------------- setup

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.12, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.74)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.9
	add_child(sun)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	layer.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	top.add_child(row)

	row.add_child(_label("Seed"))
	_seed_edit.placeholder_text = "blank = random"
	_seed_edit.custom_minimum_size.x = 140
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _on_new_world())
	row.add_child(_seed_edit)
	var new_btn := Button.new()
	new_btn.text = "New World"
	new_btn.pressed.connect(_on_new_world)
	row.add_child(new_btn)
	var random_btn := Button.new()
	random_btn.text = "Randomize Seed"
	random_btn.pressed.connect(func() -> void: _generate(_random_seed()))
	row.add_child(random_btn)

	row.add_child(_label("Start"))
	for b in _sorted_biomes(true):
		_start_pick.add_item(b.display_name)
		_start_ids.append(b.id)
	_start_pick.item_selected.connect(func(_i: int) -> void: _place_party())
	row.add_child(_start_pick)

	row.add_child(_label("Season"))
	for s in WorldParty.SEASONS:
		_season_pick.add_item(String(s).capitalize())
	_season_pick.item_selected.connect(_on_season)
	row.add_child(_season_pick)

	row.add_child(_label("Weather"))
	_weather_pick.add_item("Auto")
	for kind in WorldWeather.KINDS:
		_weather_pick.add_item(String(kind).capitalize())
	_weather_pick.item_selected.connect(_on_weather_pick)
	row.add_child(_weather_pick)

	row.add_child(_label("Overlay"))
	for name in ["Terrain", "Biome", "Danger", "AP cost", "Build sites"]:
		_overlay_pick.add_item(name)
	_overlay_pick.item_selected.connect(func(i: int) -> void: _view.set_overlay(i))
	row.add_child(_overlay_pick)

	_end_day.text = "End Day (Space)"
	_end_day.pressed.connect(_on_end_day)
	row.add_child(_end_day)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.pressed.connect(func() -> void:
		if ResourceLoader.exists(MENU_SCENE):
			get_tree().change_scene_to_file(MENU_SCENE))
	row.add_child(menu_btn)

	var left := PanelContainer.new()
	left.position = Vector2(8, 56)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(left)
	var col := VBoxContainer.new()
	left.add_child(col)
	_status.add_theme_font_size_override("font_size", 15)
	col.add_child(_status)
	_stats_label.add_theme_font_size_override("font_size", 12)
	col.add_child(_stats_label)

	var selection := PanelContainer.new()
	selection.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	selection.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	selection.position = Vector2(-8, 56)
	selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(selection)
	_selection_label.add_theme_font_size_override("font_size", 13)
	_selection_label.text = "Left click an NPC settlement to see its access area.\nRight click walks the party. Hold Shift over a hex to preview a settlement there."
	selection.add_child(_selection_label)

	var legend := PanelContainer.new()
	legend.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	legend.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend.position = Vector2(-8, -8)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(legend)
	var legend_col := VBoxContainer.new()
	legend.add_child(legend_col)
	for b in _sorted_biomes(false):
		legend_col.add_child(_legend_row(b.color, b.display_name))
	legend_col.add_child(_legend_row((ContentDB.get_terrain("river") as TerrainData).color, "River"))
	legend_col.add_child(_legend_row((ContentDB.get_terrain("lake") as TerrainData).color, "Lake"))
	legend_col.add_child(_legend_row((ContentDB.get_terrain("ocean") as TerrainData).color, "Ocean"))
	var legend_note := Label.new()
	legend_note.text = "Colour = biome, model = terrain\n(trees forest, mound hills, peaks mountain)"
	legend_note.add_theme_font_size_override("font_size", 11)
	legend_col.add_child(legend_note)

	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position = Vector2(8, -8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bottom)
	_hover_label.add_theme_font_size_override("font_size", 14)
	bottom.add_child(_hover_label)


func _legend_row(color: Color, text: String) -> Control:
	var row := HBoxContainer.new()
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(16, 16)
	row.add_child(swatch)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	return row


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _sorted_biomes(only_start: bool) -> Array[BiomeData]:
	var list: Array[BiomeData] = []
	for b: BiomeData in ContentDB.biomes.values():
		if b.start_allowed or not only_start:
			list.append(b)
	list.sort_custom(func(a: BiomeData, b: BiomeData) -> bool:
		return a.tier < b.tier if a.tier != b.tier else a.id < b.id)
	return list


# ---------------------------------------------------------------- generation

func _random_seed() -> int:
	return (Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system() * 1000.0)) & 0x7FFFFFFF


func _parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t == "":
		return _random_seed()
	if t.is_valid_int():
		return int(t) & WorldHash.M
	return WorldHash.str_hash(t)


func _on_new_world() -> void:
	_generate(_parse_seed(_seed_edit.text))


func _generate(seed_value: int) -> void:
	_seed_edit.text = str(seed_value)
	var t0 := Time.get_ticks_msec()
	_world = WorldGenerator.new(ContentDB).generate(seed_value)
	var ms := Time.get_ticks_msec() - t0
	_view.build(_world, ContentDB)
	_claimed = WorldReach.npc_claimed(_world, 2)
	_shift = false
	_view.set_overlay(_overlay_pick.selected)
	_place_party()
	_status_extra = "Generated in %d ms" % ms
	_refresh_stats()
	_refresh_status()


var _status_extra := ""


func _place_party() -> void:
	if _world == null or _world.size() == 0:
		return
	var biome_id := _start_ids[maxi(0, _start_pick.selected)]
	var start: int = int(_world.starts.get(biome_id, -1))
	if start == -1:
		# No valid start recorded: use any walkable hex of that biome.
		for i in _world.biome_hexes(biome_id):
			if _world.passable(i):
				start = i
				break
	if start == -1:
		start = 0
	_party = WorldParty.new(start, WorldParty.SEASONS[maxi(0, _season_pick.selected)], _world.seed_value)
	_party.set_forced_weather(_forced_weather())
	_select(-1)
	if _party_marker != null:
		_party_marker.queue_free()
	_party_marker = _view.make_party_marker()
	_view.add_child(_party_marker)
	_party_marker.position = _view.top_of(start)
	_focus = _view.top_of(start)
	_hover = -1
	_view.clear_path()
	_refresh_status()
	_update_camera()


func _refresh_stats() -> void:
	var st := _world.stats
	var lines := PackedStringArray()
	lines.append("Hexes %d, generator %s, attempt %d" % [_world.size(), _world.version, _world.attempt + 1])
	var parts := PackedStringArray()
	for b in _sorted_biomes(false):
		parts.append("%s %d (%d settl.)" % [b.display_name, int(st.get("biome_area", {}).get(b.id, 0)), int(st.get("settlements", {}).get(b.id, 0))])
	lines.append("; ".join(parts))
	lines.append("Biome crossing about %d AP" % int(st.get("crossing_median_ap", 0)))
	if not _world.issues.is_empty():
		lines.append("NOT VALID: " + "; ".join(_world.issues))
	_stats_label.text = "\n".join(lines)


func _refresh_status() -> void:
	if _party == null:
		return
	_status.text = "Seed %s    Day %d, %s (day %d), %s    AP %d / %d    %s" % [
		_seed_edit.text, _party.day, _party.season().capitalize(), _party.day_in_season(),
		_party.weather.capitalize(), _party.ap_left, _party.daily_ap(), _status_extra]


# ---------------------------------------------------------------- actions

func _forced_weather() -> String:
	var k := _weather_pick.selected
	return "" if k <= 0 else String(WorldWeather.KINDS[k - 1])


func _on_weather_pick(_i: int) -> void:
	if _party == null:
		return
	_party.set_forced_weather(_forced_weather())
	_update_hover_path()
	_refresh_status()


func _on_season(i: int) -> void:
	_party.set_season(WorldParty.SEASONS[i])
	_refresh_status()


func _on_end_day() -> void:
	if _walking or _party == null:
		return
	_party.end_day()
	_season_pick.select(_party.season_index)
	_update_hover_path()
	_refresh_status()


func _walk_to(target: int) -> void:
	if _walking or _party == null or target == _party.hex:
		return
	var route := _party.plan(_world, target)
	if route.size() < 2:
		return
	var moved := _party.move_along(_world, route)
	if moved.is_empty():
		return
	_walking = true
	_view.clear_path()
	var tween := create_tween()
	for h in moved:
		tween.tween_property(_party_marker, "position", _view.top_of(h), 0.12)
	tween.finished.connect(func() -> void:
		_walking = false
		_update_hover_path()
		_refresh_status())
	_refresh_status()


# ---------------------------------------------------------------- input and camera

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if _pressed and motion.position.distance_to(_press_pos) > 6.0:
				_dragged = true
			if _dragged:
				_yaw -= motion.relative.x * 0.3
				_pitch = clampf(_pitch + motion.relative.y * 0.25, 20.0, 85.0)
				_update_camera()
		elif motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_pan(Vector2(-motion.relative.x, -motion.relative.y) * _distance * 0.0022)
		else:
			_set_hover(_pick(motion.position))
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pressed = true
				_dragged = false
				_press_pos = button.position
			else:
				if _pressed and not _dragged:
					_select(_settlement_at(_pick(button.position)))
				_pressed = false
			return
		if not button.pressed:
			return
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance = clampf(_distance * 0.9, 4.0, 120.0)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = clampf(_distance * 1.1, 4.0, 120.0)
				_update_camera()
			MOUSE_BUTTON_RIGHT:
				var h := _pick(button.position)
				if h >= 0:
					_walk_to(h)
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_SPACE:
			_on_end_day()


## The settlement on hex `h`, or -1.
func _settlement_at(h: int) -> int:
	return h if h >= 0 and _world.settlements.has(h) else -1


## Selects an NPC settlement and shows the hexes it can reach (its 2 rings).
func _select(h: int) -> void:
	_selected = h
	_view.show_range(h, 2)
	if h < 0:
		_selection_label.text = "Left click an NPC settlement to see its access area.\nRight click walks the party. Hold Shift over a hex to preview a settlement there."
		return
	var info: Dictionary = _world.settlements[h]
	var race: RaceData = ContentDB.get_race(str(info.get("race", "")))
	var lines := PackedStringArray()
	lines.append("NPC settlement %s" % str(info["id"]))
	lines.append("Race: %s    Biome: %s" % [race.display_name if race != null else "unknown", ContentDB.get_biome(str(info["biome"])).display_name])
	lines.append("Access area: 2 rings, 19 hexes")
	var reach := WorldReach.summarize(_world, ContentDB, h, 2)
	lines.append("Food (%d slots, fresh water counts as food): %s" % [reach["food_slots"], WorldReach.describe(_world, ContentDB, h, 2, "food")])
	lines.append("Materials (%d, what it can sell): %s" % [reach["material"], WorldReach.describe(_world, ContentDB, h, 2, "material")])
	_selection_label.text = "\n".join(lines)


func _process(delta: float) -> void:
	var shift := Input.is_key_pressed(KEY_SHIFT)
	if shift != _shift:
		_shift = shift
		_update_preview()
		_hover_label.text = _describe(_hover)
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): move.y -= 1
	if Input.is_key_pressed(KEY_S): move.y += 1
	if Input.is_key_pressed(KEY_A): move.x -= 1
	if Input.is_key_pressed(KEY_D): move.x += 1
	if move != Vector2.ZERO:
		_pan(move.normalized() * delta * _distance * 0.9)
	var turn := 0.0
	if Input.is_key_pressed(KEY_Q): turn -= 1
	if Input.is_key_pressed(KEY_E): turn += 1
	if turn != 0.0:
		_yaw += turn * delta * 90.0
		_update_camera()


func _pan(amount: Vector2) -> void:
	var yaw := deg_to_rad(_yaw)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	_focus += right * amount.x + forward * -amount.y
	_update_camera()


func _update_camera() -> void:
	var yaw := deg_to_rad(_yaw)
	var pitch := deg_to_rad(_pitch)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * _distance
	_camera.position = _focus + offset
	_camera.look_at(_focus, Vector3.UP)


## Hex under a screen position, or -1.
func _pick(screen: Vector2) -> int:
	if _world == null:
		return -1
	var origin := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	var h := -1
	var plane_y := 0.3
	for pass_index in 2:
		if absf(dir.y) < 0.0001:
			return -1
		var t := (plane_y - origin.y) / dir.y
		if t < 0.0:
			return -1
		h = _view.hex_at_point(origin + dir * t)
		if h == -1:
			return -1
		plane_y = _view.top_of(h).y
	return h


## While Shift is held: the reach of every NPC settlement in blue and a settlement's reach around
## the hovered hex (yellow, orange where an NPC settlement reaches as well).
func _update_preview() -> void:
	if _world == null:
		return
	_view.show_npc_reach(_shift)
	_view.show_preview(_hover if _shift else -1, 2, _claimed)


func _set_hover(h: int) -> void:
	if h == _hover:
		return
	_hover = h
	_view.show_highlight(h)
	_update_preview()
	_update_hover_path()
	_hover_label.text = _describe(h)


func _update_hover_path() -> void:
	if _party == null or _hover < 0 or _walking or _hover == _party.hex or not _world.passable(_hover):
		_view.clear_path()
		return
	var route := _party.plan(_world, _hover)
	if route.size() < 2:
		_view.clear_path()
		return
	_view.show_path(route, _party.affordable_steps(_world, route))
	_hover_label.text = _describe(_hover)


# ---------------------------------------------------------------- hex description

func _describe(h: int) -> String:
	if h < 0 or _world == null:
		return ""
	var lines := PackedStringArray()
	var terrain: TerrainData = ContentDB.get_terrain(_world.terrain[h])
	var biome: BiomeData = ContentDB.get_biome(_world.biome[h])
	var ap_text := "impassable" if _world.ap[h] < 0 else "%d AP" % _world.ap[h]
	lines.append("%s, %s (%s)   hex %d,%d" % [terrain.display_name, biome.display_name, ap_text, _world.coords[h].x, _world.coords[h].y])
	lines.append("Danger %d-%d in this biome" % [biome.danger_floor, biome.danger_cap])
	if _world.node[h] != "":
		lines.append("Node: " + ContentDB.get_node_data(_world.node[h]).display_name)
	if _world.location[h] != "":
		lines.append("Location: %s (danger %d)" % [ContentDB.get_location(_world.location[h]).display_name, _world.location_danger[h]])
	if _world.settlements.has(h):
		var s: Dictionary = _world.settlements[h]
		lines.append("NPC settlement (%s)" % str(s.get("race", "")))
	if _party != null and _hover == h and h != _party.hex and _world.passable(h):
		var route := _party.plan(_world, h)
		if route.size() > 1:
			var cost := WorldPathing.path_cost(_world, route)
			var steps := _party.affordable_steps(_world, route)
			lines.append("Path: %d AP, %d steps; %d of them reachable today" % [cost, route.size() - 1, steps])
		else:
			lines.append("Not reachable")
	if _shift:
		var info := WorldReach.build_info(_world, ContentDB, WorldParams.new(), h, _claimed)
		lines.append("Player settlement here: %s" % ("possible, score %.1f" % info["score"] if info["ok"] else "not possible (%s)" % info["reason"]))
		lines.append("  free slots: food %d, fresh water %d, materials %d; kinds: food %d, materials %d; shared with NPC reach: food %d, materials %d" % [
				info["food"], info["water"], info["material"], info["kinds_food"], info["kinds_material"], info["shared_food"], info["shared_material"]])
	lines.append("Camp reach (1 ring): " + _reach_text(h, 1))
	lines.append("Settlement reach (2 rings): " + _reach_text(h, 2))
	return "\n".join(lines)


func _reach_text(h: int, rings: int) -> String:
	var parts := PackedStringArray()
	for category in ["food", "material"]:
		var text := WorldReach.describe(_world, ContentDB, h, rings, category)
		if text != "none":
			parts.append(text)
	return "nothing" if parts.is_empty() else ", ".join(parts)
