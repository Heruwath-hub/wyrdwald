extends Control
## Playable combat prototype. The whole UI is built in code so layout lives in one place.
##
## Layout: the board fills the screen (enemy rows on top, yours below, Melee rows facing each other),
## your party sits at the bottom like a hand of cards, and a small side panel holds the round
## controls, the resolution order and the log.
##
## Flow: the sides take turns placing one card each (who starts is random). On your turn pick a
## character card, pick one of its attacks (shown right above the card), click a free slot in that
## character's lane, or pass. Cards that put something on the board (traps, totems, familiars,
## ground, cleanse) then ask for a target cell among the highlighted ones. Esc or a right click
## steps back one stage; nothing is committed until the final click. Placing a card on a visible
## trap needs a second click. Hover anything to read what it does.
## Resolve plays the round one card at a time, then Upkeep: fuses, fire and familiars.

const PLAYER_SIDE := 0
const ENEMY_SIDE := 1

const LANE_NAMES := ["Melee", "Ranged", "Magic"]
const PATTERN_NAMES := ["Single", "Lane", "Pierce", "Column", "All"]

const COLOR_EMPTY := Color(0.5, 0.5, 0.55)
const COLOR_PLAYER_CARD := Color(0.72, 0.84, 1.0)
const COLOR_ENEMY_CARD := Color(1.0, 0.82, 0.72)
const COLOR_PLACEABLE := Color(0.85, 0.85, 0.5)
const COLOR_DAMAGE := Color(1.0, 0.4, 0.4)
const COLOR_FRIENDLY_FIRE := Color(1.0, 0.65, 0.2)
const COLOR_HEAL := Color(0.5, 1.0, 0.6)
const COLOR_GUARD := Color(0.55, 0.75, 1.0)
const COLOR_AREA := Color(0.85, 0.6, 0.6)
const COLOR_SELECTED := Color(1.0, 0.95, 0.4)
const COLOR_DOWN := Color(0.32, 0.32, 0.32)
const COLOR_ENTITY_OWN := Color(0.62, 0.9, 0.72)
const COLOR_ENTITY_ENEMY := Color(0.95, 0.68, 0.78)
const COLOR_CORPSE := Color(0.42, 0.4, 0.42)
const GROUND_COLORS := {
	Enums.Ground.OIL: Color(0.62, 0.52, 0.3),
	Enums.Ground.GRASS: Color(0.6, 0.75, 0.4),
	Enums.Ground.FIRE: Color(1.0, 0.62, 0.3),
	Enums.Ground.WATER: Color(0.5, 0.7, 0.95),
	Enums.Ground.HAZE: Color(0.78, 0.78, 0.85),
	Enums.Ground.SPIKE_PIT: Color(0.85, 0.5, 0.8),
	Enums.Ground.TRIPWIRE: Color(0.85, 0.5, 0.8),
	Enums.Ground.SNARE: Color(0.85, 0.5, 0.8),
	Enums.Ground.FLAME_TRAP: Color(0.95, 0.55, 0.5),
}

## Seconds one card spends on screen at normal speed: aiming phase, then impact phase.
const AIM_TIME := 0.55
const IMPACT_TIME := 0.65


## Draws the attack arrows on top of the board.
class FxLayer extends Control:
	var arrows: Array = []  # [from: Vector2, to: Vector2, color: Color]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		for arrow in arrows:
			var from: Vector2 = arrow[0]
			var to: Vector2 = arrow[1]
			var color: Color = arrow[2]
			var direction := (to - from).normalized()
			var side := Vector2(-direction.y, direction.x)
			draw_line(from, to - direction * 10.0, color, 4.0)
			draw_colored_polygon(
				PackedVector2Array([to, to - direction * 20.0 + side * 10.0, to - direction * 20.0 - side * 10.0]), color
			)


var engine: CombatEngine
var rules := CombatSession.current()

var _cells: Dictionary = {}  # Vector3i -> Button
var _hand_buttons: Dictionary = {}  # unit id -> Button
var _hand_wrappers: Dictionary = {}  # unit id -> MarginContainer
var _selected_unit: CombatUnit = null
var _selected_attack: AttackData = null
var _hover_cell := Vector3i.ZERO
var _has_hover := false
var _game_over := false
var _resolved := false
var _playing := false
var _skip := false
var _enemy_acting := false
var _fast := false
var _fx_colors: Dictionary = {}  # Vector3i -> Color, set during playback
var _styles: Dictionary = {}  # Color -> [normal, hover] StyleBoxFlat
var _hp_override: Dictionary = {}  # unit id -> hp shown while an attack is still being aimed
var _pending_slot := -1  # slot the caster was placed in while the aim cell is still to be picked
var _confirm_slot := -1  # slot of a visible trap the player has been warned about
var _aim_cells: Array[Vector3i] = []
var _biome_name := ""

var _fx: FxLayer
var _round_label: Label
var _hint_label: Label
var _roster_label: Label
var _hand_box: HBoxContainer
var _attack_layer: Control
var _attack_row: HBoxContainer
var _queue_label: RichTextLabel
var _log_label: RichTextLabel
var _resolve_button: Button
var _skip_button: Button
var _pass_button: Button
var _rules_box: VBoxContainer


func _ready() -> void:
	_build_ui()
	_new_battle()


func _input(event: InputEvent) -> void:
	if _playing:
		return
	var back := event.is_action_pressed("ui_cancel")
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		back = true
	if back:
		_step_back()
		get_viewport().set_input_as_handled()


## Esc or a right click undoes the latest stage of a placement.
func _step_back() -> void:
	if _pending_slot >= 0:
		_pending_slot = -1
		_aim_cells.clear()
	elif _confirm_slot >= 0:
		_confirm_slot = -1
	elif _selected_attack != null:
		_selected_attack = null
	else:
		_selected_unit = null
	_refresh_all()


# --- UI construction -------------------------------------------------------------------------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	add_child(margin)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	margin.add_child(main)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	main.add_child(left)

	_roster_label = Label.new()
	left.add_child(_roster_label)
	left.add_child(_build_board())

	_attack_layer = Control.new()
	_attack_layer.custom_minimum_size = Vector2(0, 76)
	left.add_child(_attack_layer)
	_attack_row = HBoxContainer.new()
	_attack_row.add_theme_constant_override("separation", 6)
	_attack_layer.add_child(_attack_row)

	_hand_box = HBoxContainer.new()
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.add_theme_constant_override("separation", 8)
	left.add_child(_hand_box)

	main.add_child(_build_side_panel())

	_fx = FxLayer.new()
	add_child(_fx)


func _build_board() -> VBoxContainer:
	var board := VBoxContainer.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.add_theme_constant_override("separation", 3)
	for lane in [Enums.Lane.MAGIC, Enums.Lane.RANGED, Enums.Lane.MELEE]:
		board.add_child(_build_row(ENEMY_SIDE, int(lane)))
	var divider := HSeparator.new()
	divider.custom_minimum_size = Vector2(0, 10)
	board.add_child(divider)
	for lane in [Enums.Lane.MELEE, Enums.Lane.RANGED, Enums.Lane.MAGIC]:
		board.add_child(_build_row(PLAYER_SIDE, int(lane)))
	return board


func _build_row(side: int, lane: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = "%s\n%s" % ["Enemy" if side == ENEMY_SIDE else "You", LANE_NAMES[lane]]
	header.custom_minimum_size = Vector2(62, 0)
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(header)

	for slot in Enums.SLOTS_PER_LANE:
		var key := Vector3i(side, lane, slot)
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(90, 40)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cell.clip_text = true
		cell.add_theme_font_size_override("font_size", 15)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
			cell.add_theme_color_override(state, Color(0.06, 0.06, 0.1))
		cell.pressed.connect(_on_cell_pressed.bind(key))
		cell.mouse_entered.connect(_on_cell_hovered.bind(key))
		cell.mouse_exited.connect(_on_cell_unhovered)
		row.add_child(cell)
		_cells[key] = cell
	return row


func _build_side_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	panel.add_theme_constant_override("separation", 6)

	_round_label = Label.new()
	panel.add_child(_round_label)

	_resolve_button = Button.new()
	_resolve_button.custom_minimum_size = Vector2(0, 40)
	_resolve_button.pressed.connect(_on_resolve_pressed)
	panel.add_child(_resolve_button)

	_pass_button = Button.new()
	_pass_button.text = "Pass (done placing)"
	_pass_button.pressed.connect(_on_pass_pressed)
	panel.add_child(_pass_button)

	_skip_button = Button.new()
	_skip_button.text = "Skip animation"
	_skip_button.pressed.connect(func() -> void: _skip = true)
	panel.add_child(_skip_button)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(0, 110)
	panel.add_child(_hint_label)

	_queue_label = RichTextLabel.new()
	_queue_label.bbcode_enabled = true
	_queue_label.custom_minimum_size = Vector2(0, 150)
	panel.add_child(_queue_label)

	_log_label = RichTextLabel.new()
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.scroll_following = true
	_log_label.add_theme_font_size_override("normal_font_size", 12)
	panel.add_child(_log_label)

	var rules_toggle := Button.new()
	rules_toggle.text = "Rules"
	rules_toggle.toggle_mode = true
	rules_toggle.toggled.connect(func(open: bool) -> void: _rules_box.visible = open)
	panel.add_child(rules_toggle)
	_rules_box = _build_rules_box()
	_rules_box.visible = false
	panel.add_child(_rules_box)

	var restart := Button.new()
	restart.text = "New Battle"
	restart.pressed.connect(_new_battle)
	panel.add_child(restart)

	var back := Button.new()
	back.text = "Battle Setup"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/ui/combat_setup.tscn"))
	panel.add_child(back)
	return panel


func _build_rules_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	var start_row := HBoxContainer.new()
	var start_label := Label.new()
	start_label.text = "Who places first"
	start_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_row.add_child(start_label)
	var start_option := OptionButton.new()
	start_option.add_item("Random", 0)
	start_option.add_item("You", 1)
	start_option.add_item("Enemy", 2)
	start_option.select(rules.first_side + 1)
	start_option.item_selected.connect(func(index: int) -> void: rules.first_side = index - 1)
	start_row.add_child(start_option)
	box.add_child(start_row)
	var tier_row := HBoxContainer.new()
	var tier_label := Label.new()
	tier_label.text = "Difficulty (next battle)"
	tier_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tier_row.add_child(tier_label)
	var tier_option := OptionButton.new()
	for index in BattleSetup.TIER_NAMES.size():
		tier_option.add_item(BattleSetup.TIER_NAMES[index], index)
	tier_option.select(rules.difficulty)
	tier_option.item_selected.connect(func(index: int) -> void: rules.difficulty = index)
	tier_row.add_child(tier_option)
	box.add_child(tier_row)

	var biome_row := HBoxContainer.new()
	var biome_label := Label.new()
	biome_label.text = "Biome (next battle)"
	biome_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	biome_row.add_child(biome_label)
	var biome_option := OptionButton.new()
	biome_option.add_item("Random", 0)
	biome_option.add_item("Bare ground", 1)
	biome_option.add_item("Plainlands", 2)
	biome_option.add_item("Wetlands", 3)
	biome_option.select(rules.biome + 1)
	biome_option.item_selected.connect(func(index: int) -> void: rules.biome = index - 1)
	biome_row.add_child(biome_option)
	box.add_child(biome_row)
	box.add_child(_toggle("Friendly fire", rules.friendly_fire, _on_friendly_fire_toggled))
	box.add_child(_toggle("Cancel card if caster dies", rules.cancel_on_caster_death, _on_cancel_toggled))
	box.add_child(_toggle("Fast playback", false, func(value: bool) -> void: _fast = value))
	box.add_child(_spin("Pierce enemy lanes", 1, 3, rules.pierce_enemy_lanes, _on_pierce_changed))
	box.add_child(_spin("Cards per round", 1, 12, rules.cards_per_round, _on_budget_changed))
	box.add_child(_spin("Max cards per character", 1, 4, rules.max_cards_per_character, _on_cards_changed))
	box.add_child(_spin("Extra card initiative penalty", 0, 12, rules.extra_card_penalty, _on_penalty_changed))
	var note := Label.new()
	note.text = "Placement rules apply from the next round."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	return box


func _toggle(text: String, value: bool, handler: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = value
	box.toggled.connect(handler)
	return box


func _spin(text: String, low: int, high: int, value: int, handler: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = 1
	spin.value = value
	spin.value_changed.connect(handler)
	row.add_child(spin)
	return row


# --- Battle flow ----------------------------------------------------------------------------

func _new_battle() -> void:
	if _playing or _enemy_acting:
		return
	engine = CombatEngine.new(rules)
	BattleSetup.setup_tier(engine, rules.difficulty, ContentDB)
	_biome_name = BiomeSetup.name_of(BiomeSetup.apply(engine, rules.biome, engine.rng))
	_game_over = false
	_resolved = false
	_clear_selection()
	_log_label.clear()
	_log_label.add_text("Difficulty: %s. Battlefield: %s.\n" % [BattleSetup.TIER_NAMES[rules.difficulty], _biome_name])
	_build_hand()
	_start_round()


func _start_round() -> void:
	_skip = false
	engine.begin_round()
	_log_label.add_text("--- Round %d: %s place first ---\n" % [engine.round_number, "you" if engine.starting_side == PLAYER_SIDE else "the enemy"])
	_refresh_all()
	await _run_enemy_turns()


## The enemy plays its turns one at a time, with a short pause so each card is noticed.
func _run_enemy_turns() -> void:
	while engine.current_side == ENEMY_SIDE and not _game_over:
		_enemy_acting = true
		_refresh_all()
		await _wait(0.6)
		var card := SimpleAI.play_turn(engine, ENEMY_SIDE)
		if card == null:
			_log_label.add_text("The enemy passes.\n")
		else:
			_fx_colors[card.cell()] = COLOR_SELECTED
			if card.has_aim():
				for cell in engine.card_cells(card):
					_fx_colors[cell] = COLOR_AREA
				_fx_colors[card.aim] = COLOR_SELECTED
			_log_placement_events()
			_refresh_all()
			await _wait(0.8 if card.has_aim() else 0.5)
			_fx_colors.clear()
	_enemy_acting = false
	_refresh_all()


func _build_hand() -> void:
	for child in _hand_box.get_children():
		child.queue_free()
	_hand_buttons.clear()
	_hand_wrappers.clear()
	for unit in engine.board.living_units(PLAYER_SIDE):
		var wrapper := MarginContainer.new()
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 92)
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(_on_hand_pressed.bind(unit))
		wrapper.add_child(button)
		_hand_box.add_child(wrapper)
		_hand_buttons[unit.id] = button
		_hand_wrappers[unit.id] = wrapper


func _clear_selection() -> void:
	_selected_unit = null
	_selected_attack = null
	_pending_slot = -1
	_confirm_slot = -1
	_aim_cells.clear()


func _log_placement_events() -> void:
	for event in engine.take_events():
		_log_label.add_text(event["text"] + "\n")


func _on_pass_pressed() -> void:
	if not _can_act():
		return
	engine.pass_turn(PLAYER_SIDE)
	_log_label.add_text("You pass.\n")
	_clear_selection()
	_refresh_all()
	_run_enemy_turns()


func _on_resolve_pressed() -> void:
	if _playing or _game_over or _enemy_acting:
		return
	if _resolved:
		_resolved = false
		_start_round()
		return
	if not engine.placement_done():
		return
	_clear_selection()
	_play_resolution()


func _play_resolution() -> void:
	_playing = true
	_skip = false
	_log_label.add_text("--- Resolving round %d ---\n" % engine.round_number)
	engine.begin_resolution()
	_refresh_all()
	while engine.has_pending():
		_hp_override.clear()
		for unit in engine.board.units:
			_hp_override[unit.id] = unit.hp
		_refresh_queue()
		var step := engine.resolve_next()
		if step.is_empty():
			break
		await _play_step(step)

	# Upkeep: fuses tick, fire spreads and burns, familiars act, things expire.
	_hp_override.clear()
	for unit in engine.board.units:
		_hp_override[unit.id] = unit.hp
	var upkeep := engine.run_upkeep()
	if not upkeep.is_empty():
		_log_label.add_text("--- Upkeep ---\n")
	for step in upkeep:
		await _play_step(step)
	_hp_override.clear()
	_fx_colors.clear()
	_playing = false
	_resolved = true

	var result := engine.winner()
	if result != CombatEngine.NO_WINNER:
		_game_over = true
		match result:
			PLAYER_SIDE:
				_log_label.add_text("You win.\n")
			ENEMY_SIDE:
				_log_label.add_text("You lose.\n")
			_:
				_log_label.add_text("Everyone fell. Draw.\n")
	_refresh_all()


## Two phases per card: aim (caster lit, footprint tinted, arrows drawn), then impact (numbers, flashes).
func _play_step(step: Dictionary) -> void:
	var card: PlacedCard = step["card"]
	var origin: Vector3i = step.get("origin", Enums.NO_CELL)
	var caster_side := card.caster.side if card != null else -1
	var upkeep := card == null
	for event in step["events"]:
		_log_label.add_text(event["text"] + "\n")

	_fx_colors.clear()
	for cell in step["cells"]:
		_fx_colors[cell] = _area_color(step)
	if origin != Enums.NO_CELL:
		_fx_colors[origin] = COLOR_SELECTED
	_fx.arrows.clear()
	if origin != Enums.NO_CELL:
		for hit in step["hits"]:
			_fx.arrows.append([_center_of(origin), _center_of(hit["cell"]), _hit_color(hit, caster_side)])
	_fx.queue_redraw()
	_refresh_cells()
	await _wait(AIM_TIME)

	if not upkeep:
		_hp_override.clear()
	_fx_colors.clear()
	if origin != Enums.NO_CELL:
		_fx_colors[origin] = COLOR_SELECTED
	var popup_cell := origin if origin != Enums.NO_CELL else Enums.NO_CELL
	match step["kind"]:
		"cancelled":
			_popup("Snared" if card != null and card.snared else "Cancelled", popup_cell, COLOR_DOWN)
		"miss":
			_popup("No target", popup_cell, COLOR_DOWN)
		"guard":
			_popup("Guard %d" % card.attack.guard, popup_cell, COLOR_GUARD)
		"quicken":
			_popup("+%d initiative" % card.attack.quicken, popup_cell, COLOR_GUARD)
		"detonate":
			_popup("BOOM", popup_cell, GROUND_COLORS[Enums.Ground.FIRE])
		"fuse":
			var tile := engine.board.ground_at(popup_cell)
			if tile != null:
				_popup("Fuse %d" % tile.turns_left, popup_cell, GROUND_COLORS[Enums.Ground.FLAME_TRAP])
		"ground":
			for cell in step["cells"]:
				var laid := engine.board.ground_kind(cell)
				if laid != Enums.Ground.NONE:
					_popup(GroundRules.display_name(laid), cell, GROUND_COLORS.get(laid, COLOR_AREA))
		"cleanse":
			for cell in step["cells"]:
				_popup("Cleared", cell, COLOR_HEAL)
	for hit in step["hits"]:
		var cell: Vector3i = hit["cell"]
		var color := _hit_color(hit, caster_side)
		_fx_colors[cell] = color
		match hit["type"]:
			"damage":
				var text := "-%d" % hit["amount"]
				if hit["blocked"] > 0:
					text += " (%d blocked)" % hit["blocked"]
				if hit["delayed"] > 0:
					text += " delay %d" % hit["delayed"]
				_popup(text, cell, color)
				if upkeep and hit["unit"] is CombatUnit:
					var unit: CombatUnit = hit["unit"]
					_hp_override[unit.id] = maxi(0, _hp_override.get(unit.id, unit.hp) - hit["amount"])
			"block":
				_popup("Blocked %d" % hit["blocked"], cell, COLOR_GUARD)
			"heal":
				_popup("+%d" % hit["amount"], cell, color)
			"guard":
				if cell != origin:
					_popup("Covered", cell, color)
	_fx.arrows.clear()
	_fx.queue_redraw()
	_refresh_cells()
	_refresh_pool_only()
	await _wait(IMPACT_TIME)
	_fx_colors.clear()


## Tint of the cells a step covers while it is being aimed.
func _area_color(step: Dictionary) -> Color:
	var card: PlacedCard = step["card"]
	match step["kind"]:
		"ground":
			return GROUND_COLORS.get(card.attack.ground, COLOR_AREA)
		"cleanse":
			return COLOR_HEAL
		"quicken":
			return COLOR_GUARD
		"fuse", "detonate", "spread", "burn":
			return GROUND_COLORS[Enums.Ground.FIRE]
	return COLOR_AREA


func _hit_color(hit: Dictionary, caster_side: int) -> Color:
	match hit["type"]:
		"heal":
			return COLOR_HEAL
		"guard", "block":
			return COLOR_GUARD
	return COLOR_FRIENDLY_FIRE if hit["unit"].side == caster_side else COLOR_DAMAGE


func _wait(seconds: float) -> void:
	var factor := 0.0 if _skip else (0.4 if _fast else 1.0)
	if seconds * factor <= 0.0:
		return
	await get_tree().create_timer(seconds * factor).timeout


func _center_of(key: Vector3i) -> Vector2:
	var cell: Button = _cells[key]
	return cell.get_global_rect().get_center() - _fx.global_position


func _popup(text: String, key: Vector3i, color: Color) -> void:
	if _skip or key == Enums.NO_CELL or not _cells.has(key):
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(label)
	label.position = _center_of(key) - Vector2(30, 14)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 46.0, IMPACT_TIME * (0.4 if _fast else 1.0) * 1.2)
	tween.tween_property(label, "modulate:a", 0.0, IMPACT_TIME * (0.4 if _fast else 1.0) * 1.4)
	tween.chain().tween_callback(label.queue_free)


# --- Input handlers -------------------------------------------------------------------------

func _can_act() -> bool:
	return not _game_over and not _resolved and not _playing and not _enemy_acting and engine.current_side == PLAYER_SIDE


func _on_hand_pressed(unit: CombatUnit) -> void:
	if not _can_act() or not engine.can_place_more(unit):
		return
	_selected_unit = unit
	_selected_attack = null
	_pending_slot = -1
	_confirm_slot = -1
	_aim_cells.clear()
	_refresh_all()


func _on_attack_pressed(attack: AttackData) -> void:
	_selected_attack = attack
	_pending_slot = -1
	_confirm_slot = -1
	_aim_cells.clear()
	_refresh_all()


func _on_cell_pressed(key: Vector3i) -> void:
	if not _can_act():
		return
	if _selected_unit == null or _selected_attack == null:
		_hint_label.text = "Pick a character, then an attack, then a free slot in its lane."
		return
	if _pending_slot >= 0:
		_commit(_pending_slot, key)
		return
	if key.x != PLAYER_SIDE or key.y != _selected_unit.lane:
		_hint_label.text = "%s must be placed in your %s lane." % [_selected_unit.display_name, LANE_NAMES[_selected_unit.lane]]
		return
	if not engine.board.is_slot_free(key.x, key.y, key.z):
		_hint_label.text = "That slot is taken."
		return
	# A visible enemy trap in the slot needs a second click to confirm.
	if engine.trap_kind_for(_selected_unit, key.z) != Enums.Ground.NONE and _confirm_slot != key.z:
		_confirm_slot = key.z
		_refresh_all()
		return
	if engine.needs_aim(_selected_attack):
		var reachable := engine.aim_cells(_selected_unit, _selected_attack, key.z)
		if reachable.is_empty():
			_hint_label.text = "Nothing to aim %s at from that slot." % _selected_attack.display_name
			return
		_pending_slot = key.z
		_aim_cells = reachable
		_refresh_all()
		return
	_commit(key.z, Enums.NO_CELL)


func _commit(slot: int, aim: Vector3i) -> void:
	var error := engine.place_card(_selected_unit, _selected_attack, slot, aim)
	if error != "":
		_hint_label.text = error
		return
	_log_placement_events()
	_clear_selection()
	_refresh_all()
	_run_enemy_turns()


func _on_cell_hovered(key: Vector3i) -> void:
	_hover_cell = key
	_has_hover = true
	if not _playing:
		_refresh_cells()
		_refresh_hint()


func _on_cell_unhovered() -> void:
	_has_hover = false
	if not _playing:
		_refresh_cells()
		_refresh_hint()


func _on_cancel_toggled(value: bool) -> void:
	rules.cancel_on_caster_death = value


func _on_friendly_fire_toggled(value: bool) -> void:
	rules.friendly_fire = value
	_refresh_all()


func _on_pierce_changed(value: float) -> void:
	rules.pierce_enemy_lanes = int(value)
	_refresh_all()


func _on_budget_changed(value: float) -> void:
	rules.cards_per_round = int(value)


func _on_cards_changed(value: float) -> void:
	rules.max_cards_per_character = int(value)


func _on_penalty_changed(value: float) -> void:
	rules.extra_card_penalty = int(value)


# --- Refresh --------------------------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_round_label()
	_refresh_roster()
	_refresh_cells()
	_refresh_hand()
	_refresh_attack_row()
	_refresh_queue()
	_refresh_hint()
	_refresh_buttons()


func _refresh_pool_only() -> void:
	_refresh_hand()


func _shown_hp(unit: CombatUnit) -> int:
	return _hp_override.get(unit.id, unit.hp)


func _refresh_round_label() -> void:
	var status := "your turn"
	if _game_over:
		status = "battle over"
	elif _playing:
		status = "resolving"
	elif _resolved:
		status = "resolved"
	elif engine.placement_done():
		status = "ready to resolve"
	elif engine.current_side == ENEMY_SIDE or _enemy_acting:
		status = "enemy placing"
	_round_label.text = "Round %d - %s - %s\nCards left: you %d, enemy %d" % [
		engine.round_number, status, _biome_name, engine.cards_left(PLAYER_SIDE), engine.cards_left(ENEMY_SIDE)
	]


func _refresh_roster() -> void:
	var parts: PackedStringArray = []
	for unit in engine.board.units:
		if unit.side == ENEMY_SIDE:
			var state := "%d/%d" % [_shown_hp(unit), unit.max_hp] if _shown_hp(unit) > 0 else "down"
			parts.append("%s (%s) %s" % [unit.display_name, unit.class_data.display_name, state])
	_roster_label.text = "Enemies: " + "   |   ".join(parts)


func _refresh_cells() -> void:
	var footprint := _preview_footprint()
	var hazard := {} if _playing else engine.upkeep_hazard()
	for key in _cells:
		var cell: Button = _cells[key]
		var card := engine.board.card_at(key.x, key.y, key.z)
		var entity := engine.board.entity_at(key.x, key.y, key.z)
		var tile := engine.board.ground_at(key)
		cell.text = _cell_text(key, card, entity, tile, hazard)
		_apply_cell_style(cell, _cell_color(key, card, entity, tile, footprint))


## Board cells are tinted with flat boxes (a modulate would only darken the dark theme).
func _apply_cell_style(cell: Button, color: Color) -> void:
	if not _styles.has(color):
		var box := StyleBoxFlat.new()
		box.bg_color = color.darkened(0.1)
		box.set_corner_radius_all(4)
		box.set_border_width_all(1)
		box.border_color = color.lightened(0.2)
		var hover := box.duplicate() as StyleBoxFlat
		hover.bg_color = color.lightened(0.15)
		_styles[color] = [box, hover]
	var boxes: Array = _styles[color]
	cell.add_theme_stylebox_override("normal", boxes[0])
	cell.add_theme_stylebox_override("pressed", boxes[0])
	cell.add_theme_stylebox_override("disabled", boxes[0])
	cell.add_theme_stylebox_override("focus", boxes[0])
	cell.add_theme_stylebox_override("hover", boxes[1])


func _cell_text(key: Vector3i, card: PlacedCard, entity: CombatEntity, tile: GroundTile, hazard: Dictionary) -> String:
	var lines: PackedStringArray = []
	if card != null:
		var caster := card.caster
		var hp := _shown_hp(caster)
		if hp <= 0:
			lines.append("%s (down)" % caster.display_name)
			lines.append(card.attack.display_name)
		else:
			lines.append("%s %d/%d" % [caster.display_name, hp, caster.max_hp])
			if card.snared:
				lines.append("%s  SNARED" % card.attack.display_name)
			elif card.deployed:
				lines.append("%s  (set)" % card.attack.display_name)
			else:
				lines.append("%s  i%d" % [card.attack.display_name, card.initiative])
			if caster.side == PLAYER_SIDE and not _playing and not _resolved:
				var incoming := _incoming_damage(caster)
				if incoming > 0:
					lines.append("Threat -%d" % incoming)
	elif entity != null:
		if entity.kind == Enums.EntityKind.CORPSE:
			lines.append("Corpse")
			lines.append("%d round(s)" % maxi(entity.turns_left - (0 if _resolved else 1), 0))
		else:
			lines.append("%s %d/%d" % [entity.display_name, entity.hp, entity.max_hp])
			if entity.turns_left >= 0:
				lines.append("%d round(s) left" % entity.turns_left)
			elif entity.owner != null:
				lines.append("%s's familiar" % entity.owner.display_name)
	elif _pending_slot >= 0 and _selected_unit != null and key == Vector3i(PLAYER_SIDE, _selected_unit.lane, _pending_slot):
		lines.append(_selected_unit.display_name)
		lines.append("placing...")
	if tile != null:
		var label := GroundRules.display_name(tile.kind)
		if tile.kind == Enums.Ground.FLAME_TRAP:
			label += " fuse %d" % tile.turns_left
		elif tile.turns_left >= 0:
			label += " (%d)" % tile.turns_left
		lines.append("[%s]" % label)
	if hazard.has(key):
		lines.append("burns at Upkeep")
	return "\n".join(lines)


## Damage the enemy's placed cards currently aim at this character (ignores order and guards).
func _incoming_damage(unit: CombatUnit) -> int:
	var cells: Array[Vector3i] = []
	for card in engine.board.cards_of(unit):
		cells.append(card.cell())
	var total := 0
	for card in engine.board.cards.values():
		if card.caster.side == unit.side or not card.caster.is_alive() or card.deployed:
			continue
		if card.attack.guard > 0 or card.attack.target_side == Enums.TargetSide.ALLY or card.attack.is_aimed():
			continue
		for target in engine.card_cells(card):
			if cells.has(target):
				total += engine.effective_power(card.attack, card.cell())
				break
	return total


func _cell_color(key: Vector3i, card: PlacedCard, entity: CombatEntity, tile: GroundTile, footprint: Dictionary) -> Color:
	if _fx_colors.has(key):
		return _fx_colors[key]
	if footprint.has(key):
		return footprint[key]
	var ground_color: Color = GROUND_COLORS.get(tile.kind, COLOR_EMPTY) if tile != null else COLOR_EMPTY
	var base := COLOR_EMPTY
	if card != null:
		base = COLOR_DOWN if _shown_hp(card.caster) <= 0 else (COLOR_PLAYER_CARD if key.x == PLAYER_SIDE else COLOR_ENEMY_CARD)
	elif entity != null:
		if entity.kind == Enums.EntityKind.CORPSE:
			base = COLOR_CORPSE
		else:
			base = COLOR_ENTITY_OWN if (entity.owner != null and entity.owner.side == PLAYER_SIDE) else COLOR_ENTITY_ENEMY
	elif _selected_unit != null and _selected_attack != null and _pending_slot < 0 and key.x == PLAYER_SIDE and key.y == _selected_unit.lane:
		base = COLOR_PLACEABLE if engine.board.is_slot_free(key.x, key.y, key.z) else COLOR_EMPTY
		if tile != null and base == COLOR_PLACEABLE:
			return base.lerp(ground_color, 0.35)
	if tile != null:
		return ground_color if base == COLOR_EMPTY else base.lerp(ground_color, 0.45)
	return base


## Cell -> colour for whatever the cursor is previewing: an armed placement, or an enemy card
## (so its threat is readable before you commit).
func _preview_footprint() -> Dictionary:
	if _playing or _resolved or not _has_hover:
		return {}
	if _pending_slot >= 0 and _selected_unit != null and _selected_attack != null:
		var colors := {}
		for cell in _aim_cells:
			colors[cell] = COLOR_PLACEABLE
		if _aim_cells.has(_hover_cell):
			if _selected_attack.picks_lane():
				var lane_cells := engine.preview_cells(_selected_unit, _selected_attack, _pending_slot, _hover_cell)
				colors.merge(_color_cells(_selected_unit.side, _selected_attack, lane_cells), true)
			else:
				var tint := _aim_tint(_selected_attack)
				for cell in CombatBoard.shape_cells(_hover_cell, _selected_attack.shape):
					colors[cell] = tint
		colors[Vector3i(PLAYER_SIDE, _selected_unit.lane, _pending_slot)] = COLOR_SELECTED
		return colors
	if _selected_unit != null and _selected_attack != null:
		var hover := _hover_cell
		if engine.needs_aim(_selected_attack):
			return {}
		if hover.x != PLAYER_SIDE or hover.y != _selected_unit.lane or not engine.board.is_slot_free(hover.x, hover.y, hover.z):
			return {}
		# The previewed card stands on the board so Single attacks and guards aim around it.
		var ghost := PlacedCard.new()
		ghost.caster = _selected_unit
		ghost.attack = _selected_attack
		ghost.slot = hover.z
		engine.board.cards[hover] = ghost
		var cells := engine.preview_cells(_selected_unit, _selected_attack, hover.z)
		var colors := _color_cells(_selected_unit.side, _selected_attack, cells)
		engine.board.cards.erase(hover)
		colors[hover] = COLOR_SELECTED
		return colors
	var card := engine.board.card_at(_hover_cell.x, _hover_cell.y, _hover_cell.z)
	if card != null and card.caster.is_alive():
		var colors := _color_cells(card.caster.side, card.attack, engine.card_cells(card))
		colors[card.cell()] = COLOR_SELECTED
		return colors
	return {}


func _color_cells(caster_side: int, attack: AttackData, cells: Array[Vector3i]) -> Dictionary:
	var colors := {}
	if attack.is_aimed():
		for cell in cells:
			colors[cell] = _aim_tint(attack)
		return colors
	for cell in cells:
		var target: Variant = engine.board.target_at(cell.x, cell.y, cell.z)
		if attack.guard > 0:
			colors[cell] = COLOR_GUARD
		elif target == null:
			colors[cell] = COLOR_AREA
		elif attack.target_side == Enums.TargetSide.ALLY:
			colors[cell] = COLOR_HEAL
		elif target.side == caster_side:
			colors[cell] = COLOR_FRIENDLY_FIRE if rules.friendly_fire else COLOR_AREA
		else:
			colors[cell] = COLOR_DAMAGE
	return colors


## Colour of the cells an aimed card will cover.
func _aim_tint(attack: AttackData) -> Color:
	if not attack.clears.is_empty():
		return COLOR_HEAL
	if attack.ground != Enums.Ground.NONE:
		return GROUND_COLORS.get(attack.ground, COLOR_AREA)
	if attack.entity != Enums.EntityKind.NONE:
		return COLOR_ENTITY_OWN if attack.aim_side == Enums.AimSide.OWN else COLOR_ENTITY_ENEMY
	return COLOR_AREA


## One line saying what an aimed card does, for its button.
func _aimed_effect_text(attack: AttackData) -> String:
	if attack.entity != Enums.EntityKind.NONE:
		return "Set %s" % EntityRules.display_name(attack.entity)
	if not attack.clears.is_empty():
		var names: Array[String] = []
		for kind in attack.clears:
			names.append(GroundRules.display_name(kind))
		return "Clears " + ", ".join(names)
	var text := GroundRules.display_name(attack.ground)
	if GroundRules.is_trap(attack.ground):
		return "Trap: %s" % text
	if attack.shape == Enums.Shape.CROSS:
		text += " (cross)"
	if attack.power > 0:
		text = "Dmg %d + %s" % [attack.power, text]
	return text


func _refresh_hand() -> void:
	for unit in engine.board.units:
		if unit.side != PLAYER_SIDE or not _hand_buttons.has(unit.id):
			continue
		var button: Button = _hand_buttons[unit.id]
		var wrapper: MarginContainer = _hand_wrappers[unit.id]
		var hp := _shown_hp(unit)
		var status := "%d/%d cards" % [engine.cards_placed(unit), rules.max_cards_per_character]
		if hp <= 0:
			status = "down"
		button.text = "%s\n%s - %s\nHP %d/%d\n%s" % [
			unit.display_name, unit.class_data.display_name, LANE_NAMES[unit.lane], maxi(hp, 0), unit.max_hp, status
		]
		button.disabled = hp <= 0 or not _can_act() or not engine.can_place_more(unit)
		button.modulate = COLOR_SELECTED if unit == _selected_unit else Color(1, 1, 1)
		wrapper.add_theme_constant_override("margin_top", 0 if unit == _selected_unit else 14)


## Attack buttons float right above the selected character's card.
func _refresh_attack_row() -> void:
	for child in _attack_row.get_children():
		child.queue_free()
	if _selected_unit == null or _playing:
		return
	for attack in _selected_unit.attacks:
		var button := Button.new()
		button.custom_minimum_size = Vector2(112, 64)
		button.add_theme_font_size_override("font_size", 12)
		var effect := ""
		var pattern: String = ""
		if attack.is_aimed():
			effect = _aimed_effect_text(attack)
			pattern = "Set" if attack.is_set() else "Aimed"
		elif attack.quicken > 0:
			effect = "+%d initiative" % attack.quicken
			pattern = "Allies"
		else:
			effect = "Block %d" % attack.guard if attack.guard > 0 else ("Heal %d" % attack.power if attack.target_side == Enums.TargetSide.ALLY else "Dmg %d" % attack.power)
			if attack.delay > 0:
				effect += " Delay %d" % attack.delay
			pattern = "Guard" if attack.guard > 0 else (PATTERN_NAMES[attack.pattern] + " (pick)" if attack.picks_lane() else PATTERN_NAMES[attack.pattern])
		var initiative := engine.next_initiative(_selected_unit, attack)
		button.text = "%s\n%s - %s\n%s" % [attack.display_name, pattern, effect, "Init %d" % initiative if not attack.is_set() else "Set at once"]
		button.tooltip_text = attack.description
		if (attack.picks_lane() and attack.target_side == Enums.TargetSide.ENEMY) or (attack.is_aimed() and attack.aim_side != Enums.AimSide.OWN):
			button.tooltip_text += "\nReaches %s." % CombatEngine.lane_reach_summary(attack)
		button.disabled = engine.attack_used(_selected_unit, attack) or (attack.is_aimed() and not _can_aim_anywhere(_selected_unit, attack))
		button.modulate = COLOR_SELECTED if attack == _selected_attack else Color(1, 1, 1)
		button.pressed.connect(_on_attack_pressed.bind(attack))
		_attack_row.add_child(button)
	_attack_row.reset_size()
	_position_attack_row.call_deferred()


func _can_aim_anywhere(unit: CombatUnit, attack: AttackData) -> bool:
	for slot in engine.free_slots(unit):
		if not engine.aim_cells(unit, attack, slot).is_empty():
			return true
	return false


func _position_attack_row() -> void:
	if _selected_unit == null or not _hand_buttons.has(_selected_unit.id):
		return
	await get_tree().process_frame
	if _selected_unit == null or not _hand_buttons.has(_selected_unit.id):
		return
	_attack_row.reset_size()
	var card: Button = _hand_buttons[_selected_unit.id]
	var center := card.get_global_rect().get_center().x - _attack_layer.get_global_rect().position.x
	var x := clampf(center - _attack_row.size.x * 0.5, 0.0, maxf(0.0, _attack_layer.size.x - _attack_row.size.x))
	_attack_row.position = Vector2(x, 6)


func _refresh_queue() -> void:
	var text := "[b]Order[/b]\n"
	var index := 1
	var cards := engine.pending_cards() if engine.resolving else engine.ordered_cards()
	for card in cards:
		var color := "#8fbcff" if card.caster.side == PLAYER_SIDE else "#ffab8a"
		text += "%d. [color=%s]%s[/color] %s (i%d)\n" % [
			index, color, card.caster.display_name, card.attack.display_name, card.initiative
		]
		index += 1
	_queue_label.text = text


func _refresh_hint() -> void:
	var text := _base_hint()
	var info := _hover_info()
	if info != "":
		text += "\n" + info
	_hint_label.text = text


func _base_hint() -> String:
	if _playing:
		return "Resolving..."
	if _game_over:
		return "Press New Battle to play again."
	if _resolved:
		return "Round resolved. Press Next Round when ready."
	if engine.placement_done():
		return "Both sides are done placing. Press Resolve Round."
	if _enemy_acting or engine.current_side == ENEMY_SIDE:
		return "The enemy is placing a card..."
	if _selected_unit == null:
		return "Your turn: pick a character card, or pass to stop placing. Hover anything to read it."
	if _selected_attack == null:
		return "%s (%s lane): pick an attack." % [_selected_unit.display_name, LANE_NAMES[_selected_unit.lane]]
	if _pending_slot >= 0:
		if _selected_attack.picks_lane():
			return "%s: pick a lane (%s). Esc or right click steps back." % [_selected_attack.display_name, _lane_reach_summary(_selected_unit, _selected_attack)]
		return "%s: pick a highlighted cell to aim at. Esc or right click steps back." % _selected_attack.display_name
	if _confirm_slot >= 0:
		var trap := engine.trap_kind_for(_selected_unit, _confirm_slot)
		return "WARNING: a %s waits in that slot. %s Click the slot again to place anyway, or pick another." % [
			GroundRules.display_name(trap), GroundRules.describe(trap)
		]
	return "%s: %s Click a free slot in your %s lane." % [
		_selected_attack.display_name, _selected_attack.description, LANE_NAMES[_selected_unit.lane]
	]


## "enemy Melee or Ranged lane" style text for the lanes a lane attack can be pointed at.
func _lane_reach_summary(unit: CombatUnit, attack: AttackData) -> String:
	var names: Array[String] = []
	for choice in engine.lane_choices(unit, attack):
		names.append(LANE_NAMES[choice.y])
	return ("your " if attack.target_side == Enums.TargetSide.ALLY else "enemy ") + " or ".join(names)


## What the hovered cell holds: ground, entity and card, in words.
func _hover_info() -> String:
	if not _has_hover or _playing or not _cells.has(_hover_cell):
		return ""
	var parts: PackedStringArray = []
	var tile := engine.board.ground_at(_hover_cell)
	if tile != null:
		parts.append("%s: %s" % [GroundRules.display_name(tile.kind), GroundRules.describe(tile.kind)])
	var entity := engine.board.entity_at(_hover_cell.x, _hover_cell.y, _hover_cell.z)
	if entity != null:
		parts.append("%s: %s" % [entity.display_name, EntityRules.describe(entity.kind)])
	var card := engine.board.card_at(_hover_cell.x, _hover_cell.y, _hover_cell.z)
	if card != null and _selected_unit == null:
		parts.append("%s: %s" % [card.attack.display_name, card.attack.description])
	var aura := engine.aura_percent(_hover_cell)
	if aura != 0:
		parts.append("Totem aura: cards here deal %+d%%." % aura)
	return "\n".join(parts)


func _refresh_buttons() -> void:
	_skip_button.visible = _playing
	_pass_button.visible = not _playing and not _resolved and not _game_over
	_pass_button.disabled = not _can_act()
	if _game_over and not _playing:
		_resolve_button.text = "Battle over"
		_resolve_button.disabled = true
	elif _playing:
		_resolve_button.text = "Resolving..."
		_resolve_button.disabled = true
	elif _resolved:
		_resolve_button.text = "Next Round"
		_resolve_button.disabled = _enemy_acting
	else:
		_resolve_button.text = "Resolve Round"
		_resolve_button.disabled = not engine.placement_done() or _enemy_acting
