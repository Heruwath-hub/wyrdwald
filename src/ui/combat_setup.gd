extends Control
## Battle setup: pick a difficulty and the combat rules, then press Start. The choices are stored in
## CombatSession, which the combat screen reads when it builds the battle.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const COMBAT_SCENE := "res://scenes/combat/combat_screen.tscn"

const TIER_BLURBS := [
	"A short skirmish to learn on: a smaller party with a few skills each.",
	"The full party of five with four skills each, against a larger enemy squad.",
	"Every skill, and the enemy fields a Witch as well. Mistakes are punished.",
]

var _rules: CombatRules
var _tier_buttons: Array[Button] = []
var _tier_info: Label


func _ready() -> void:
	_rules = CombatSession.current()
	if not CombatSession.configured:
		_rules.difficulty = 0
	var content := $Center/Panel/Content as VBoxContainer
	MenuStyle.panel($Center/Panel as PanelContainer)
	content.add_child(_title("Battle Setup", 44))
	content.add_child(_heading("Difficulty"))
	content.add_child(_build_tier_row())
	_tier_info = Label.new()
	_tier_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tier_info.custom_minimum_size = Vector2(1000, 0)
	_tier_info.add_theme_color_override("font_color", MenuStyle.MUTED)
	_tier_info.add_theme_font_size_override("font_size", 16)
	content.add_child(_tier_info)
	content.add_child(_heading("Rules"))
	content.add_child(_build_rules_grid())
	content.add_child(_build_button_row())
	_show_tier(_rules.difficulty)


func _title(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", MenuStyle.TEXT)
	return label


func _heading(text: String) -> Label:
	var label := _title(text, 24)
	label.add_theme_color_override("font_color", MenuStyle.BORDER_HOVER)
	return label


func _build_tier_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	for tier in BattleSetup.TIER_NAMES.size():
		var button := Button.new()
		button.text = BattleSetup.TIER_NAMES[tier]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = tier == _rules.difficulty
		button.custom_minimum_size = Vector2(200, 52)
		MenuStyle.button(button, 22)
		button.pressed.connect(_on_tier_chosen.bind(tier))
		row.add_child(button)
		_tier_buttons.append(button)
	return row


func _on_tier_chosen(tier: int) -> void:
	_rules.difficulty = tier
	_show_tier(tier)


func _show_tier(tier: int) -> void:
	var entry: Dictionary = BattleSetup.TIERS[tier]
	var lines: Array[String] = [TIER_BLURBS[tier]]
	lines.append("Your party: %s." % _squad(entry["player"]))
	lines.append("Enemies: %s." % _squad(entry["enemy"]))
	var cards: int = entry["enemy_cards"]
	var enemy_cards := "all of its cards" if cards < 0 else "up to %d cards" % cards
	var extras: Array[String] = ["The enemy plays %s each round" % enemy_cards]
	if entry["enemy_initiative"] != 0:
		extras.append("its cards resolve later in the round")
	if entry["enemy_awareness"] < 1.0:
		extras.append("it reads your placed cards %d%% of the time" % roundi(entry["enemy_awareness"] * 100.0))
	if entry["last_stand"]:
		extras.append("your fallen characters' cards still resolve")
	lines.append("; ".join(extras) + ".")
	_tier_info.text = "\n".join(lines)


func _squad(team: Array) -> String:
	var names: Array[String] = []
	for member in team:
		var class_data: ClassData = ContentDB.get_class_data(member["class"])
		var title: String = class_data.display_name if class_data != null else member["class"]
		names.append("%s (%s)" % [member["name"], title])
	return ", ".join(names)


func _build_rules_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)

	var biome := OptionButton.new()
	biome.add_item("Random", 0)
	biome.add_item("Bare ground", 1)
	biome.add_item("Plainlands (grass)", 2)
	biome.add_item("Wetlands (water)", 3)
	biome.select(_rules.biome + 1)
	biome.item_selected.connect(func(index: int) -> void: _rules.biome = index - 1)
	_add_row(grid, "Battlefield", biome)

	var first := OptionButton.new()
	first.add_item("Random", 0)
	first.add_item("You", 1)
	first.add_item("Enemy", 2)
	first.select(_rules.first_side + 1)
	first.item_selected.connect(func(index: int) -> void: _rules.first_side = index - 1)
	_add_row(grid, "Who places first", first)

	_add_row(grid, "Cards per round", _spin(1, 12, _rules.cards_per_round, func(v: float) -> void: _rules.cards_per_round = int(v)))
	_add_row(grid, "Max cards per character", _spin(1, 4, _rules.max_cards_per_character, func(v: float) -> void: _rules.max_cards_per_character = int(v)))
	_add_row(grid, "Extra card initiative penalty", _spin(0, 12, _rules.extra_card_penalty, func(v: float) -> void: _rules.extra_card_penalty = int(v)))
	_add_row(grid, "Pierce depth (enemy lanes)", _spin(1, 3, _rules.pierce_enemy_lanes, func(v: float) -> void: _rules.pierce_enemy_lanes = int(v)))
	_add_row(grid, "Friendly fire", _check(_rules.friendly_fire, func(on: bool) -> void: _rules.friendly_fire = on))
	_add_row(grid, "Cancel card if caster dies", _check(_rules.cancel_on_caster_death, func(on: bool) -> void: _rules.cancel_on_caster_death = on))
	_add_row(grid, "Limit lane reach per card", _check(_rules.restrict_lanes, func(on: bool) -> void: _rules.restrict_lanes = on))
	return grid


func _add_row(grid: GridContainer, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MenuStyle.TEXT)
	label.custom_minimum_size = Vector2(250, 0)
	grid.add_child(label)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 190.0)
	grid.add_child(control)


func _spin(min_value: int, max_value: int, value: int, on_change: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.value = value
	spin.value_changed.connect(on_change)
	return spin


func _check(value: bool, on_change: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.button_pressed = value
	check.toggled.connect(on_change)
	return check


func _build_button_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var spacer_top := Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 8)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	var reset := Button.new()
	reset.text = "Reset Rules"
	reset.pressed.connect(_on_reset_pressed)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var start := Button.new()
	start.text = "Start Battle"
	start.pressed.connect(_on_start_pressed)
	for button: Button in [back, reset, start]:
		button.custom_minimum_size = Vector2(220, 60)
		MenuStyle.button(button, 24)
	row.add_child(back)
	row.add_child(reset)
	row.add_child(spacer)
	row.add_child(start)
	start.grab_focus.call_deferred()
	return row


func _on_reset_pressed() -> void:
	CombatSession.reset()
	CombatSession.configured = true
	get_tree().reload_current_scene()


func _on_start_pressed() -> void:
	CombatSession.configured = true
	get_tree().change_scene_to_file(COMBAT_SCENE)
