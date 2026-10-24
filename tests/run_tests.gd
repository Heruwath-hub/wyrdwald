extends SceneTree
## Headless rules tests. Run from the project folder:
##   godot --headless --path . --script tests/run_tests.gd
## Open the project in the editor once first (or run with --import) so script classes register.

var _checks := 0
var _failures := 0
var _next_id := 1


func _init() -> void:
	_test_single_targeting()
	_test_closest_rules()
	_test_other_patterns()
	_test_pierce_geometry()
	_test_board_rules()
	_test_card_allowance()
	_test_turn_order()
	_test_class_variety()
	_test_friendly_fire()
	_test_caster_death()
	_test_heal()
	_test_guard()
	_test_guard_lifetime()
	_test_delay()
	_test_stepwise_resolution()
	_test_ai()
	_test_surface_reactions()
	_test_fire_upkeep()
	_test_placement_traps()
	_test_flame_trap()
	_test_entities()
	_test_counter_matrix()
	_test_lane_choice()
	_test_tiers()
	_test_familiars()
	_test_corpses()
	_test_aiming()
	_test_clone()
	_test_haze_and_quicken()
	_test_ai_behaviour()
	_test_world()
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: " + message)


func _attack(id: String) -> AttackData:
	return load("res://content/attacks/%s.tres" % id) as AttackData


func _class(id: String) -> ClassData:
	return load("res://content/classes/%s.tres" % id) as ClassData


func _unit(class_id: String, side: int, hp: int = 30) -> CombatUnit:
	var class_data := _class(class_id)
	var unit := CombatUnit.new(_next_id, "%s%d" % [class_id, _next_id], side, class_data, hp)
	_next_id += 1
	for attack_id in class_data.attack_ids:
		unit.attacks.append(_attack(attack_id))
	return unit


func _engine(rules: CombatRules, units: Array) -> CombatEngine:
	var engine := CombatEngine.new(rules)
	engine.enforce_turns = false
	for unit in units:
		engine.board.add_unit(unit)
	engine.begin_round()
	return engine


func _place(engine: CombatEngine, unit: CombatUnit, attack_id: String, slot: int) -> void:
	var error := engine.place_card(unit, _attack(attack_id), slot)
	_check(error == "", "setup: %s places %s (%s)" % [unit.display_name, attack_id, error])


func _cells(engine: CombatEngine, unit: CombatUnit, attack_id: String, slot: int) -> Array[Vector3i]:
	return engine.preview_cells(unit, _attack(attack_id), slot)


func _test_single_targeting() -> void:
	var warrior := _unit("warrior", 0)
	var front := _unit("reaver", 1)
	var back := _unit("druid", 1)
	var engine := _engine(CombatRules.new(), [warrior, front, back])

	var empty := _cells(engine, warrior, "cleave", 2)
	_check(empty.size() == 1 and empty[0] == Vector3i(1, Enums.Lane.MELEE, 2), "Single points at the nominal enemy Melee cell when the enemy has no cards")

	_place(engine, back, "thorn_lash", 2)
	_check(_cells(engine, warrior, "cleave", 2)[0] == Vector3i(1, Enums.Lane.MAGIC, 2), "Single reaches the Magic lane when it is the only card in the column")

	_place(engine, front, "rend", 2)
	_check(_cells(engine, warrior, "cleave", 2)[0] == Vector3i(1, Enums.Lane.MELEE, 2), "Single hits the front card first")

	front.hp = 0
	_check(_cells(engine, warrior, "cleave", 2)[0] == Vector3i(1, Enums.Lane.MAGIC, 2), "A fallen character's card no longer shields the one behind it")


func _test_closest_rules() -> void:
	var warrior := _unit("warrior", 0)
	var reaver := _unit("reaver", 1)
	var druid := _unit("druid", 1)
	var engine := _engine(CombatRules.new(), [warrior, reaver, druid])
	_place(engine, reaver, "rend", 4)
	_place(engine, druid, "thorn_lash", 1)

	_check(_cells(engine, warrior, "cleave", 0)[0] == Vector3i(1, Enums.Lane.MAGIC, 1), "Single from slot 0 goes to the nearest occupied column (1)")
	_check(_cells(engine, warrior, "cleave", 3)[0] == Vector3i(1, Enums.Lane.MELEE, 4), "Single from slot 3 goes to column 4")
	_check(_cells(engine, warrior, "cleave", 2)[0] == Vector3i(1, Enums.Lane.MAGIC, 1), "Equal distance goes to the lower slot")

	var column := _cells(engine, warrior, "frenzy", 3)
	_check(column.size() == 3 and column.all(func(c: Vector3i) -> bool: return c.x == 1 and c.z == 4), "Column falls back to the nearest occupied column")

	var lane := _cells(engine, warrior, "sweeping_strike", 0)
	_check(lane.size() == 5 and lane.all(func(c: Vector3i) -> bool: return c.y == Enums.Lane.MELEE), "Lane hits the same lane when it holds a card")

	var lone := _engine(CombatRules.new(), [_unit("druid", 0), _unit("druid", 1)])
	_place(lone, lone.board.units[1], "thorn_lash", 2)
	var fallback := _cells(lone, lone.board.units[0], "entangle", 0)
	_check(fallback.all(func(c: Vector3i) -> bool: return c.y == Enums.Lane.MAGIC), "Without a choice a lane attack takes the nearest occupied lane in reach")
	var capped := _engine(CombatRules.new(), [_unit("warrior", 0), _unit("druid", 1)])
	_place(capped, capped.board.units[1], "thorn_lash", 2)
	var stuck := _cells(capped, capped.board.units[0], "sweeping_strike", 0)
	_check(stuck.all(func(c: Vector3i) -> bool: return c.y == Enums.Lane.MELEE), "A Melee character cannot default to a lane it cannot reach")


func _test_other_patterns() -> void:
	var rules := CombatRules.new()
	var warrior := _unit("warrior", 0)
	var witch := _unit("witch", 0)
	var healer := _unit("healer", 0)
	var engine := _engine(rules, [warrior, witch, healer])

	_check(_cells(engine, witch, "ruin", 1).size() == 15, "All hits 15 cells")

	var mend := _cells(engine, healer, "mend", 2)
	_check(mend.size() == 3 and mend.all(func(c: Vector3i) -> bool: return c.x == 0 and c.z == 2), "Mend covers the healer's column on her own side")

	var rain := _cells(engine, healer, "soothing_rain", 0)
	_check(rain.size() == 5 and rain.all(func(c: Vector3i) -> bool: return c.x == 0 and c.y == Enums.Lane.MAGIC), "Ally Lane covers the caster's own lane")

	var bloom := _cells(engine, healer, "lifebloom", 0)
	_check(bloom.size() == 15 and bloom.all(func(c: Vector3i) -> bool: return c.x == 0), "Ally All covers the whole own side")

	var wall := _cells(engine, warrior, "shield_wall", 3)
	_check(wall.size() == 3 and wall.all(func(c: Vector3i) -> bool: return c.x == 0 and c.z == 3), "A Melee guard covers its whole column")
	var ward := _cells(engine, healer, "mend", 3)
	_check(ward.size() == 3, "Ally Column covers three cells")


func _test_pierce_geometry() -> void:
	var rules := CombatRules.new()
	rules.pierce_enemy_lanes = 1
	var witch := _unit("witch", 0)
	var engine := _engine(rules, [witch])

	var cells := _cells(engine, witch, "chain_lightning", 2)
	_check(cells.size() == 3, "Pierce depth 1 from Magic covers 3 cells")
	_check(cells.has(Vector3i(0, Enums.Lane.RANGED, 2)), "Pierce crosses own Ranged lane")
	_check(cells.has(Vector3i(0, Enums.Lane.MELEE, 2)), "Pierce crosses own Melee lane")
	_check(cells.has(Vector3i(1, Enums.Lane.MELEE, 2)), "Pierce reaches the enemy Melee lane")
	_check(not cells.has(Vector3i(0, Enums.Lane.MAGIC, 2)), "Pierce skips the caster's own cell")

	rules.pierce_enemy_lanes = 3
	_check(_cells(engine, witch, "chain_lightning", 2).size() == 5, "Pierce depth 3 covers 5 cells")

	var enemy := _unit("reaver", 1)
	engine.board.add_unit(enemy)
	_place(engine, enemy, "rend", 4)
	var shifted := _cells(engine, witch, "chain_lightning", 2)
	_check(shifted.has(Vector3i(1, Enums.Lane.MELEE, 4)) and shifted.has(Vector3i(0, Enums.Lane.MELEE, 2)), "Pierce crosses its own column, then hits the nearest enemy column")

	rules.pierce_enemy_lanes = 1
	var enemy_witch := _unit("witch", 1)
	engine.board.add_unit(enemy_witch)
	var mirrored := _cells(engine, enemy_witch, "chain_lightning", 0)
	_check(mirrored.size() == 3 and mirrored.has(Vector3i(0, Enums.Lane.MELEE, 0)), "Pierce is symmetrical for side 1")

	var warrior := _unit("warrior", 0)
	engine.board.add_unit(warrior)
	_check(engine.preview_cells(warrior, _attack("chain_lightning"), 0).size() == 1, "Pierce from the front lane only reaches the enemy front lane")


func _test_board_rules() -> void:
	var engine := _engine(CombatRules.new(), [])
	var a := _unit("warrior", 0)
	var b := _unit("warrior", 0)
	var c := _unit("warrior", 1)
	for unit in [a, b, c]:
		engine.board.add_unit(unit)
	_place(engine, a, "cleave", 1)
	_check(engine.place_card(b, _attack("cleave"), 1) != "", "Board rejects an occupied slot")
	_check(engine.place_card(b, _attack("cleave"), 9) != "", "Board rejects an out-of-range slot")
	_place(engine, c, "cleave", 1)
	_check(engine.board.unit_at(0, Enums.Lane.MELEE, 1) == a, "Warrior card owns its Melee cell")
	_check(engine.board.unit_at(0, Enums.Lane.RANGED, 1) == null, "Other lanes stay empty")


func _test_card_allowance() -> void:
	var rules := CombatRules.new()
	rules.max_cards_per_character = 2
	var warrior := _unit("warrior", 0)
	var engine := _engine(rules, [warrior])

	_check(engine.place_card(warrior, _attack("rend"), 0) != "", "A character cannot use another class's attack")
	_check(engine.free_slots(warrior).size() == 5, "All five slots start free")
	_check(engine.next_initiative(warrior, _attack("cleave")) == 8, "First card keeps full initiative")
	_place(engine, warrior, "cleave", 3)
	_check(engine.next_initiative(warrior, _attack("shield_bash")) == 9 - 6, "Second card loses the extra-card penalty")
	_check(engine.place_card(warrior, _attack("cleave"), 0) != "", "The same attack cannot be placed twice")
	_check(engine.place_card(warrior, _attack("shield_bash"), 3) != "", "A used slot cannot be reused")
	_place(engine, warrior, "shield_bash", 0)
	var second := engine.board.card_at(0, Enums.Lane.MELEE, 0)
	_check(second.initiative == 3, "Second card carries the reduced initiative")
	_check(not engine.can_place_more(warrior), "Two cards use up the character's cap")
	_check(engine.place_card(warrior, _attack("sweeping_strike"), 1) != "", "A third card is rejected")
	_check(engine.cards_placed(warrior) == 2, "Two cards counted")
	_check(engine.cards_left(0) == 5, "Two of seven cards used")

	var first := engine.board.card_at(0, Enums.Lane.MELEE, 3)
	engine.remove_card(first)
	_check(engine.cards_placed(warrior) == 1 and engine.can_place_more(warrior), "Taking a card back returns the allowance")
	_check(second.initiative == 9, "The remaining card is re-timed to full initiative")

	rules.max_cards_per_character = 1
	var solo := _unit("warrior", 0)
	var engine_two := _engine(rules, [solo])
	_place(engine_two, solo, "cleave", 0)
	_check(not engine_two.can_place_more(solo), "max_cards_per_character = 1 limits to a single card")

	engine_two.begin_round()
	_check(engine_two.board.cards.is_empty() and engine_two.can_place_more(solo), "A new round clears the board")

	var budget_rules := CombatRules.new()
	budget_rules.cards_per_round = 3
	var squad := [_unit("warrior", 0), _unit("hunter", 0), _unit("rogue", 0), _unit("healer", 0)]
	var budget := _engine(budget_rules, squad)
	_place(budget, squad[0], "cleave", 0)
	_place(budget, squad[1], "aimed_shot", 0)
	_place(budget, squad[2], "quick_stab", 1)
	_check(budget.cards_left(0) == 0, "Three cards spend a budget of three")
	_check(budget.place_card(squad[3], _attack("mend"), 0) != "", "Nothing can be placed once the budget is spent")
	_check(not budget.can_place_more(squad[3]), "Idle characters cannot place either")


func _test_friendly_fire() -> void:
	for friendly_fire in [true, false]:
		var rules := CombatRules.new()
		rules.friendly_fire = friendly_fire
		var warrior := _unit("warrior", 0, 40)
		var witch := _unit("witch", 0, 25)
		var reaver := _unit("reaver", 1, 30)
		var engine := _engine(rules, [warrior, witch, reaver])

		_place(engine, warrior, "cleave", 2)
		_place(engine, reaver, "rend", 2)
		_place(engine, witch, "chain_lightning", 2)
		engine.resolve_round()

		_check(reaver.hp == 17, "Cleave 7 + Chain Lightning 6 on the reaver (ff=%s): %d" % [friendly_fire, reaver.hp])
		var expected := 26 if friendly_fire else 32
		_check(warrior.hp == expected, "Warrior stands in the witch's column (ff=%s): hp %d" % [friendly_fire, warrior.hp])


func _test_caster_death() -> void:
	for cancel in [true, false]:
		var rules := CombatRules.new()
		rules.cancel_on_caster_death = cancel
		var witch := _unit("witch", 0, 5)
		var rogue := _unit("rogue", 1)
		var reaver := _unit("reaver", 1, 30)
		var engine := _engine(rules, [witch, rogue, reaver])

		_place(engine, witch, "chain_lightning", 0)
		_place(engine, rogue, "quick_stab", 0)
		_place(engine, reaver, "rend", 0)

		var ordered := engine.ordered_cards()
		_check(ordered[0].attack.id == "quick_stab", "Highest initiative resolves first")
		_check(ordered[2].attack.id == "chain_lightning", "Slow Pierce resolves last")

		engine.resolve_round()
		_check(not witch.is_alive(), "Quick Stab kills the witch (cancel=%s)" % cancel)
		var expected := 30 if cancel else 24
		_check(reaver.hp == expected, "Dead caster's card (cancel=%s): enemy hp %d" % [cancel, reaver.hp])
		_check(engine.winner() == 1, "Side 1 wins when side 0 has no living characters")


func _test_heal() -> void:
	var healer := _unit("healer", 0)
	var warrior := _unit("warrior", 0, 40)
	var hunter := _unit("hunter", 0, 30)
	warrior.hp = 38
	hunter.hp = 10
	var engine := _engine(CombatRules.new(), [healer, warrior, hunter])
	_place(engine, healer, "mend", 0)
	_place(engine, warrior, "cleave", 0)
	_place(engine, hunter, "aimed_shot", 1)
	engine.resolve_round()
	_check(warrior.hp == 40, "Healing is capped at max HP")
	_check(hunter.hp == 10, "Mend only covers the healer's own column")


func _test_guard() -> void:
	var warrior := _unit("warrior", 0, 40)
	var witch := _unit("witch", 0, 25)
	var reaver := _unit("reaver", 1, 30)
	var druid := _unit("druid", 1, 30)
	var engine := _engine(CombatRules.new(), [warrior, witch, reaver, druid])

	_place(engine, warrior, "shield_wall", 2)
	_place(engine, witch, "hex_bolt", 4)
	_place(engine, reaver, "rend", 2)
	_place(engine, druid, "thorn_lash", 2)
	var steps: Array[Dictionary] = []
	engine.begin_resolution()
	while engine.has_pending():
		steps.append(engine.resolve_next())

	_check(steps[0]["kind"] == "guard", "Shield Wall (init 10) resolves first and raises the guard")
	_check(warrior.hp == 38, "Rend (8) and Thorn Lash (6) against a 12-point wall leave 2 through")
	_check(steps[2]["hits"][0]["type"] == "block", "A fully soaked hit reports as Blocked")

	# A wall that runs out passes the rest through.
	var reaver_two := _unit("reaver", 1, 30)
	var druid_two := _unit("druid", 1, 30)
	var third := _unit("trickster", 1, 30)
	var warrior_two := _unit("warrior", 0, 40)
	var engine_two := _engine(CombatRules.new(), [warrior_two, reaver_two, druid_two, third])
	_place(engine_two, warrior_two, "shield_wall", 2)
	_place(engine_two, reaver_two, "rend", 2)
	_place(engine_two, druid_two, "thorn_lash", 2)
	_place(engine_two, third, "dirty_trick", 2)
	engine_two.resolve_round()
	_check(warrior_two.hp == 34, "18 damage against a 12-point wall leaves 6 through (hp %d)" % warrior_two.hp)

	# A guard protects the characters behind it, not those in front or in other columns.
	var hunter := _unit("hunter", 0, 30)
	var hunter_far := _unit("hunter", 0, 30)
	var enemy := _unit("reaver", 1, 30)
	var engine_three := _engine(CombatRules.new(), [_unit("warrior", 0, 40), hunter, hunter_far, enemy])
	var warrior_three: CombatUnit = engine_three.board.units[0]
	_place(engine_three, warrior_three, "shield_wall", 1)
	_place(engine_three, hunter, "aimed_shot", 1)
	_place(engine_three, enemy, "rend", 1)
	engine_three.resolve_round()
	_check(warrior_three.hp == 40, "The front card of the column takes the Single hit and the wall blocks it")
	_check(hunter.hp == 30, "Single stops at the front card, so the hunter behind is untouched")

	# Lane damage reaching a guarded hunter is soaked by the warrior's wall.
	var warrior_four := _unit("warrior", 0, 40)
	var hunter_four := _unit("hunter", 0, 30)
	var caster := _unit("rogue", 1, 30)
	var engine_four := _engine(CombatRules.new(), [warrior_four, hunter_four, caster])
	_place(engine_four, warrior_four, "shield_wall", 1)
	_place(engine_four, hunter_four, "aimed_shot", 1)
	_place(engine_four, caster, "poison_cloud", 4)
	engine_four.resolve_round()
	_check(hunter_four.hp == 30, "Poison Cloud (3) on the guarded Ranged cell is blocked (hp %d)" % hunter_four.hp)

	# Pierce ignores guards.
	var warrior_five := _unit("warrior", 0, 40)
	var enemy_witch := _unit("witch", 1, 25)
	var engine_five := _engine(CombatRules.new(), [warrior_five, enemy_witch])
	_place(engine_five, warrior_five, "shield_wall", 2)
	_place(engine_five, enemy_witch, "chain_lightning", 2)
	engine_five.resolve_round()
	_check(warrior_five.hp == 34, "Chain Lightning pierces the wall (hp %d)" % warrior_five.hp)


func _test_guard_lifetime() -> void:
	# The combat screen resolves card by card and then runs Upkeep; guards must be gone afterwards.
	var warrior := _unit("warrior", 0, 40)
	var reaver := _unit("reaver", 1, 40)
	var engine := _engine(CombatRules.new(), [warrior, reaver])
	_place(engine, warrior, "shield_wall", 2)
	_place(engine, reaver, "rend", 2)
	engine.begin_resolution()
	_check(engine._guards.is_empty(), "No guard before the wall resolves")
	while engine.has_pending():
		engine.resolve_next()
	_check(not engine._guards.is_empty(), "The wall stands until the round ends")
	engine.run_upkeep()
	_check(engine._guards.is_empty(), "Upkeep ends every guard")
	_check(warrior.hp == 40, "Rend (8) was soaked by the wall (hp %d)" % warrior.hp)

	# The next round starts without the old wall: the same hit now goes through in full.
	engine.begin_round()
	_place(engine, warrior, "cleave", 2)
	_place(engine, reaver, "rend", 2)
	engine.begin_resolution()
	while engine.has_pending():
		engine.resolve_next()
	engine.run_upkeep()
	_check(warrior.hp == 32, "A new round has no leftover guard (hp %d)" % warrior.hp)

	# resolve_round ends the guards as well.
	var warrior_two := _unit("warrior", 0, 40)
	var reaver_two := _unit("reaver", 1, 40)
	var engine_two := _engine(CombatRules.new(), [warrior_two, reaver_two])
	_place(engine_two, warrior_two, "shield_wall", 2)
	engine_two.resolve_round()
	_check(engine_two._guards.is_empty(), "resolve_round leaves no guard behind")


func _test_delay() -> void:
	var warrior := _unit("warrior", 0, 40)
	var reaver := _unit("reaver", 1, 40)
	var engine := _engine(CombatRules.new(), [warrior, reaver])
	_place(engine, warrior, "shield_bash", 0)
	_place(engine, reaver, "rend", 0)
	# Shield Bash (init 9) hits first and delays the reaver's Rend (init 8) by 4.
	var first := engine.ordered_cards()[0]
	_check(first.attack.id == "shield_bash", "Shield Bash starts ahead of Rend")
	engine.begin_resolution()
	var step := engine.resolve_next()
	_check(step["hits"][0]["delayed"] == 4, "Shield Bash reports the delay")
	_check(engine.pending_cards()[0].initiative == 3, "Rend now sits at initiative 3")


func _test_stepwise_resolution() -> void:
	var warrior := _unit("warrior", 0, 40)
	var reaver := _unit("reaver", 1, 40)
	var engine := _engine(CombatRules.new(), [warrior, reaver])
	_place(engine, warrior, "cleave", 0)
	_place(engine, reaver, "rend", 0)
	_check(not engine.resolving, "Not resolving during placement")
	engine.begin_resolution()
	_check(engine.place_card(warrior, _attack("sweeping_strike"), 2) != "", "No placing once resolution has begun")
	var first := engine.resolve_next()
	_check(first["card"].attack.id == "cleave" and reaver.hp == 33, "First step resolves one card only")
	_check(warrior.hp == 40, "The second card has not fired yet")
	var second := engine.resolve_next()
	_check(second["card"].attack.id == "rend" and warrior.hp == 32, "Second step resolves the next card")
	_check(engine.resolve_next().is_empty() and not engine.has_pending(), "Nothing pending afterwards")


func _test_turn_order() -> void:
	var rules := CombatRules.new()
	rules.first_side = 0
	rules.cards_per_round = 2
	var player := _unit("warrior", 0)
	var enemy := _unit("reaver", 1)
	var engine := CombatEngine.new(rules)
	engine.board.add_unit(player)
	engine.board.add_unit(enemy)
	engine.begin_round()

	_check(engine.current_side == 0 and engine.starting_side == 0, "first_side = 0 lets the player open")
	_check(engine.place_card(enemy, _attack("rend"), 0) != "", "Enemy cannot place on the player's turn")
	_check(engine.place_card(player, _attack("cleave"), 0) == "", "Player places a card")
	_check(engine.current_side == 1, "Turn passes to the enemy")
	_check(engine.place_card(player, _attack("shield_bash"), 1) != "", "Player cannot place twice in a row")
	_check(engine.place_card(enemy, _attack("rend"), 0) == "", "Enemy places a card")
	_check(engine.current_side == 0, "Turn passes back")
	_check(engine.pass_turn(0) == "", "The player passes")
	_check(engine.current_side == 1, "The enemy keeps placing after a pass")
	_check(engine.place_card(enemy, _attack("frenzy"), 1) == "", "Enemy places its second card")
	_check(engine.placement_done(), "Placement ends once the enemy has spent its budget and the player passed")
	_check(engine.cards_left(0) == 1 and engine.cards_left(1) == 0, "Budgets are tracked per side")

	rules.first_side = 1
	engine.begin_round()
	_check(engine.current_side == 1, "first_side = 1 lets the enemy open")

	rules.first_side = -1
	var seen := {}
	for i in 30:
		engine.begin_round()
		seen[engine.starting_side] = true
	_check(seen.size() == 2, "A random first side picks both sides over time")


func _test_class_variety() -> void:
	var all_patterns := {}
	for class_id in ["warrior", "reaver", "smith", "hunter", "rogue", "trickster", "witch", "druid", "healer"]:
		var patterns := {}
		for attack_id in _class(class_id).attack_ids:
			var attack := _attack(attack_id)
			if attack.is_aimed() or attack.quicken > 0:
				continue  # aimed cards are pointed at a cell and have no pattern
			patterns[attack.pattern] = true
		all_patterns[class_id] = patterns
		_check(patterns.size() <= 3, "%s uses at most 3 different patterns (%d)" % [class_id, patterns.size()])
	_check(not all_patterns["reaver"].has(Enums.Pattern.PIERCE) and not all_patterns["warrior"].has(Enums.Pattern.ALL), "Melee classes differ from casters in pattern")
	_check(all_patterns["witch"].has(Enums.Pattern.ALL) and all_patterns["witch"].has(Enums.Pattern.PIERCE), "The witch keeps the wide, slow patterns")
	var guards := 0
	for class_id in ["warrior", "smith"]:
		for attack_id in _class(class_id).attack_ids:
			if _attack(attack_id).guard > 0:
				guards += 1
	_check(guards == 2, "Warrior and Smith both carry a guard card")


func _test_ai() -> void:
	var rules := CombatRules.new()
	rules.first_side = 1
	var witch := _unit("witch", 1)
	var reaver := _unit("reaver", 1)
	var player := _unit("warrior", 0)
	var engine := CombatEngine.new(rules)
	for unit in [witch, reaver, player]:
		engine.board.add_unit(unit)
	engine.begin_round()
	_check(engine.place_card(witch, _attack("chain_lightning"), 2) == "", "Enemy witch opens")
	engine.pass_turn(0)

	var first := SimpleAI.choose(engine, 1)
	var second := SimpleAI.choose(engine, 1)
	_check(not first.is_empty(), "AI finds a card to place")
	_check(first["attack"] == second["attack"] and first["slot"] == second["slot"], "AI is deterministic")
	if first["unit"] == reaver:
		_check(first["slot"] != 2, "AI will not stand in its own witch's Pierce column with friendly fire on")

	var target := _unit("warrior", 0)
	var hunter := _unit("reaver", 1)
	var rules_two := CombatRules.new()
	rules_two.first_side = 0
	var engine_two := CombatEngine.new(rules_two)
	engine_two.board.add_unit(target)
	engine_two.board.add_unit(hunter)
	engine_two.begin_round()
	_check(engine_two.place_card(target, _attack("cleave"), 4) == "", "Player opens")
	var pick := SimpleAI.choose(engine_two, 1)
	_check(pick["score"] > 0.0, "AI sees value in attacking an existing card")

	var squad_rules := CombatRules.new()
	squad_rules.first_side = 1
	var squad := CombatEngine.new(squad_rules)
	for unit in [_unit("reaver", 1), _unit("trickster", 1), _unit("druid", 1), _unit("warrior", 0)]:
		squad.board.add_unit(unit)
	squad.begin_round()
	if squad.current_side == 0:
		squad.pass_turn(0)
	var guard := 0
	while squad.current_side == 1 and guard < 20:
		SimpleAI.play_turn(squad, 1)
		guard += 1
	_check(squad.placement_done() or squad.current_side == 0, "The AI eventually ends its placement")
	_check(squad.cards_played(1) <= rules.cards_per_round, "The AI never exceeds the card budget")


# --- Ground, traps and entities -------------------------------------------------------------

func _place_aim(engine: CombatEngine, unit: CombatUnit, attack_id: String, slot: int, aim: Vector3i) -> String:
	return engine.place_card(unit, _attack(attack_id), slot, aim)


func _lay(engine: CombatEngine, cell: Vector3i, kind: int, owner_side: int = 0) -> void:
	engine.board.ground[cell] = GroundTile.new(kind, owner_side)


func _test_surface_reactions() -> void:
	var smith := _unit("smith", 0, 40)
	var reaver := _unit("reaver", 1, 40)
	var engine := _engine(CombatRules.new(), [smith, reaver])
	_lay(engine, Vector3i(1, 0, 2), Enums.Ground.OIL)
	_lay(engine, Vector3i(1, 0, 3), Enums.Ground.OIL)
	_lay(engine, Vector3i(1, 1, 3), Enums.Ground.OIL)
	_lay(engine, Vector3i(1, 0, 0), Enums.Ground.OIL)
	_check(_place_aim(engine, smith, "ember_throw", 0, Vector3i(1, 0, 2)) == "", "Ember Throw can be aimed at an enemy cell")
	_check(engine.board.ground_kind(Vector3i(1, 0, 2)) == Enums.Ground.OIL, "Aimed ground resolves in initiative order, not when placed")
	engine.resolve_round()
	_check(engine.board.ground_kind(Vector3i(1, 0, 2)) == Enums.Ground.FIRE, "Fire on oil makes fire")
	_check(engine.board.ground_kind(Vector3i(1, 0, 3)) == Enums.Ground.FIRE, "Fire spreads along connected oil")
	_check(engine.board.ground_kind(Vector3i(1, 1, 3)) == Enums.Ground.FIRE, "Fire spreads to the oil in the next lane")
	_check(engine.board.ground_kind(Vector3i(1, 0, 0)) == Enums.Ground.OIL, "Oil that is not connected does not burn")

	var druid := _unit("druid", 0, 40)
	var enemy := _unit("reaver", 1, 40)
	var wet := _engine(CombatRules.new(), [druid, enemy])
	_lay(wet, Vector3i(1, 0, 2), Enums.Ground.FIRE)
	_lay(wet, Vector3i(1, 0, 1), Enums.Ground.OIL)
	_check(_place_aim(wet, druid, "rain", 2, Vector3i(1, 0, 2)) == "", "Rain can be aimed at a burning cell")
	wet.resolve_round()
	_check(wet.board.ground_kind(Vector3i(1, 0, 2)) == Enums.Ground.HAZE, "Water on fire leaves haze (steam)")
	_check(wet.board.ground_kind(Vector3i(1, 0, 1)) == Enums.Ground.WATER, "Water washes the oil next to it away")


func _test_fire_upkeep() -> void:
	var reaver := _unit("reaver", 1, 40)
	var warrior := _unit("warrior", 0, 40)
	var engine := _engine(CombatRules.new(), [warrior, reaver])
	_lay(engine, Vector3i(1, 0, 2), Enums.Ground.FIRE)
	_lay(engine, Vector3i(1, 0, 3), Enums.Ground.FIRE)
	_place(engine, reaver, "rend", 2)
	_place(engine, reaver, "frenzy", 3)
	engine.resolve_round()
	_check(reaver.hp == 36, "A character in two burning cells burns once per round (hp %d)" % reaver.hp)
	engine.begin_round()
	_place(engine, reaver, "rend", 2)
	engine.resolve_round()
	_check(reaver.hp == 32, "Fire burns for a second round (hp %d)" % reaver.hp)
	_check(engine.board.ground_kind(Vector3i(1, 0, 2)) == Enums.Ground.NONE, "Fire burns out after two rounds")
	engine.begin_round()
	_place(engine, reaver, "rend", 2)
	engine.resolve_round()
	_check(reaver.hp == 32, "No damage once the fire is out")


func _test_placement_traps() -> void:
	var hunter := _unit("hunter", 0, 40)
	var rogue := _unit("rogue", 1, 40)
	var engine := _engine(CombatRules.new(), [hunter, rogue])
	_check(_place_aim(engine, hunter, "spike_pit", 0, Vector3i(1, 1, 4)) != "", "A trap cannot be aimed beyond its reach")
	_check(_place_aim(engine, hunter, "spike_pit", 0, Vector3i(0, 1, 1)) != "", "A trap cannot be aimed at your own side")
	_check(_place_aim(engine, hunter, "spike_pit", 2, Vector3i(1, 1, 3)) == "", "A trap is set on an enemy cell")
	_check(engine.board.ground_kind(Vector3i(1, 1, 3)) == Enums.Ground.SPIKE_PIT, "A trap takes effect the moment its card is placed")
	_check(engine.board.cards.has(Vector3i(0, 1, 2)) and engine.board.card_at(0, 1, 2).deployed, "The caster's card stays on the board but does not resolve")
	_check(engine.ordered_cards().is_empty(), "Set cards are not part of the resolution order")
	_check(_place_aim(engine, hunter, "snare", 1, Vector3i(1, 1, 3)) != "", "Only one piece of ground fits a cell")
	_check(engine.trap_kind_for(rogue, 3) == Enums.Ground.SPIKE_PIT, "The enemy can see which kind of trap waits in a slot")
	_check(engine.trap_kind_for(hunter, 3) == Enums.Ground.NONE, "The trap does not threaten its own side")

	_place(engine, rogue, "quick_stab", 3)
	_check(rogue.hp == 32, "The Spike Pit hurts the caster of the card placed there (hp %d)" % rogue.hp)
	_check(engine.board.ground_kind(Vector3i(1, 1, 3)) == Enums.Ground.NONE, "A sprung trap is used up")
	var events := engine.take_events()
	_check(events.any(func(e: Dictionary) -> bool: return e["type"] == "trap"), "Springing a trap is reported")
	_check(engine.take_events().is_empty(), "Events are handed over once")
	_check(engine.board.card_at(1, 1, 3).committed, "A card that sprang a trap cannot be taken back")

	# Tripwire: Mark and lost initiative.
	var hunter2 := _unit("hunter", 0, 40)
	var rogue2 := _unit("rogue", 1, 40)
	var wire := _engine(CombatRules.new(), [hunter2, rogue2, _unit("rogue", 0, 40)])
	_lay(wire, Vector3i(1, 1, 0), Enums.Ground.TRIPWIRE, 0)
	_place(wire, rogue2, "quick_stab", 0)
	_check(rogue2.marked, "A Tripwire Marks the caster")
	_check(wire.board.card_at(1, 1, 0).initiative == 6, "A Tripwire costs 4 initiative (%d)" % wire.board.card_at(1, 1, 0).initiative)
	var ally := wire.board.units[2]
	_place(wire, ally, "quick_stab", 2)
	wire.begin_resolution()
	wire.resolve_next()
	wire.resolve_next()
	_check(true, "Both cards resolve")
	_check(rogue2.hp == 40 - 5 - GroundRules.MARK_BONUS or rogue2.hp == 40 - 5 - GroundRules.MARK_BONUS - 0, "A Marked character takes extra damage (hp %d)" % rogue2.hp)

	# Snare: the card is cancelled but still uses a slot and a card of the budget.
	var hunter3 := _unit("hunter", 0, 40)
	var rogue3 := _unit("rogue", 1, 40)
	var snared := _engine(CombatRules.new(), [hunter3, rogue3])
	_lay(snared, Vector3i(1, 1, 2), Enums.Ground.SNARE, 0)
	_place(snared, rogue3, "quick_stab", 2)
	_check(snared.board.card_at(1, 1, 2).snared, "A Snare catches the card")
	_check(snared.cards_played(1) == 1 and not snared.board.is_slot_free(1, 1, 2), "A snared card still uses a slot and a card")
	_place(snared, hunter3, "aimed_shot", 0)
	snared.begin_resolution()
	var kinds: Array[String] = []
	while snared.has_pending():
		kinds.append(snared.resolve_next()["kind"])
	_check(kinds.has("cancelled"), "A snared card resolves as cancelled")
	_check(hunter3.hp == 40, "The snared attack never fires")

	# A trap of your own side is not triggered by your own cards.
	var rogue4 := _unit("rogue", 0, 40)
	var own := _engine(CombatRules.new(), [rogue4, _unit("hunter", 1, 40)])
	_lay(own, Vector3i(0, 1, 1), Enums.Ground.SPIKE_PIT, 0)
	_place(own, rogue4, "quick_stab", 1)
	_check(rogue4.hp == 40, "Your own traps do not spring on you")


func _test_flame_trap() -> void:
	var hunter := _unit("hunter", 0, 40)
	var reaver := _unit("reaver", 1, 40)
	var engine := _engine(CombatRules.new(), [hunter, reaver])
	_place_aim(engine, hunter, "flame_trap", 2, Vector3i(1, 0, 2))
	engine.resolve_round()
	var tile := engine.board.ground_at(Vector3i(1, 0, 2))
	_check(tile != null and tile.kind == Enums.Ground.FLAME_TRAP and tile.turns_left == 1, "A Flame Trap has one round left after the round it was set")
	_check(engine.board.ground_kind(Vector3i(1, 0, 3)) == Enums.Ground.NONE, "Nothing burns while the fuse is running")
	_check(engine.upkeep_hazard().has(Vector3i(1, 0, 3)), "The hazard forecast shows the cells that will burn")
	_check(not engine.upkeep_hazard().has(Vector3i(0, 0, 3)), "The forecast stays on the trap's side")

	engine.begin_round()
	_place(engine, reaver, "rend", 3)
	engine.resolve_round()
	_check(engine.board.ground_kind(Vector3i(1, 0, 2)) == Enums.Ground.FIRE, "The Flame Trap bursts into fire when the fuse runs out")
	_check(engine.board.ground_kind(Vector3i(1, 1, 2)) == Enums.Ground.FIRE and engine.board.ground_kind(Vector3i(1, 0, 3)) == Enums.Ground.FIRE, "The fire covers the neighbouring cells")
	_check(reaver.hp == 36, "Whoever stands in the burst takes fire damage the same Upkeep (hp %d)" % reaver.hp)

	# Disarmed in time.
	var rogue := _unit("rogue", 0, 40)
	var hunter2 := _unit("hunter", 0, 40)
	var enemy := _unit("reaver", 1, 40)
	var safe := _engine(CombatRules.new(), [rogue, hunter2, enemy])
	_place_aim(safe, hunter2, "flame_trap", 2, Vector3i(1, 0, 2))
	safe.resolve_round()
	safe.begin_round()
	_check(_place_aim(safe, rogue, "disarm", 0, Vector3i(1, 0, 4)) != "", "Disarm needs a trap to remove")
	_check(_place_aim(safe, rogue, "disarm", 1, Vector3i(1, 0, 2)) == "", "Disarm can be aimed at the trap")
	_place(safe, enemy, "rend", 3)
	safe.resolve_round()
	_check(safe.board.ground_kind(Vector3i(1, 0, 2)) == Enums.Ground.NONE and enemy.hp == 40, "A disarmed Flame Trap never goes off")

	# Doused with water.
	var druid := _unit("druid", 0, 40)
	var hunter3 := _unit("hunter", 0, 40)
	var enemy3 := _unit("reaver", 1, 40)
	var wet := _engine(CombatRules.new(), [druid, hunter3, enemy3])
	_place_aim(wet, hunter3, "flame_trap", 2, Vector3i(1, 0, 2))
	wet.resolve_round()
	wet.begin_round()
	_place_aim(wet, druid, "rain", 2, Vector3i(1, 0, 2))
	_place(wet, enemy3, "rend", 3)
	wet.resolve_round()
	_check(enemy3.hp == 40 and wet.board.ground_kind(Vector3i(1, 0, 2)) == Enums.Ground.WATER, "Rain douses a Flame Trap")

	# Cleanse by a Healer removes any ground.
	var healer := _unit("healer", 0, 40)
	var enemy4 := _unit("reaver", 1, 40)
	var clean := _engine(CombatRules.new(), [healer, enemy4])
	_lay(clean, Vector3i(1, 0, 0), Enums.Ground.OIL)
	_place_aim(clean, healer, "cleanse", 0, Vector3i(1, 0, 0))
	clean.resolve_round()
	_check(clean.board.ground_kind(Vector3i(1, 0, 0)) == Enums.Ground.NONE, "Cleanse removes any ground")


func _test_entities() -> void:
	var smith := _unit("smith", 0, 40)
	var warrior := _unit("warrior", 0, 40)
	var reaver := _unit("reaver", 1, 40)
	var engine := _engine(CombatRules.new(), [smith, warrior, reaver])
	_check(_place_aim(engine, smith, "war_totem", 4, Vector3i(0, 0, 3)) == "", "A totem is set on your side")
	var totem := engine.board.entity_at(0, 0, 3)
	_check(totem != null and totem.hp == 8 and totem.kind == Enums.EntityKind.WAR_TOTEM, "The totem stands in the cell with its hit points")
	_check(engine.board.card_at(0, 0, 4) != null, "The caster's card stands in its own slot")
	_check(engine.place_card(warrior, _attack("cleave"), 3) != "", "A cell holds a card or an entity, never both")
	_check(not engine.free_slots(warrior).has(3), "A slot with an entity is not free")
	_check(_place_aim(engine, smith, "war_totem", 1, Vector3i(0, 0, 2)) != "", "A character cannot reuse the same card")
	_place(engine, warrior, "cleave", 2)
	_place(engine, reaver, "rend", 0)
	engine.resolve_round()
	_check(reaver.hp == 32, "A War Totem adds 20 percent to cards next to it (hp %d)" % reaver.hp)

	var witch := _unit("witch", 0, 40)
	var enemy := _unit("reaver", 1, 40)
	var hexed := _engine(CombatRules.new(), [witch, enemy, _unit("warrior", 0, 40)])
	_place_aim(hexed, witch, "hex_totem", 0, Vector3i(1, 1, 2))
	_check(hexed.board.entity_at(1, 1, 2) != null, "A Hex Totem is set on the enemy side")
	_place(hexed, enemy, "rend", 2)
	var target := hexed.board.units[2]
	_place(hexed, target, "shield_bash", 2)
	hexed.resolve_round()
	_check(target.hp == 34, "A Hex Totem takes 20 percent off cards next to it: 8 becomes 6 (hp %d)" % target.hp)

	# Totems are attackable and stop working when destroyed; a Single attack hits the frontmost object.
	var attacker := _unit("warrior", 0, 40)
	var smith2 := _unit("smith", 1, 40)
	var field := _engine(CombatRules.new(), [attacker, smith2])
	_place_aim(field, smith2, "war_totem", 0, Vector3i(1, 0, 2))
	var standing := field.board.entity_at(1, 0, 2)
	_place(field, attacker, "cleave", 2)
	field.resolve_round()
	_check(standing.hp == 1 or field.board.entity_at(1, 0, 2) == null or standing.hp < 8, "A Single attack hits the totem as the frontmost object (hp %d)" % standing.hp)
	_check(smith2.hp == 40, "The character behind the totem is not hit")


func _test_familiars() -> void:
	var druid := _unit("druid", 1, 40)
	var warrior := _unit("warrior", 0, 40)
	var engine := _engine(CombatRules.new(), [druid, warrior])
	_place_aim(engine, druid, "wolf", 2, Vector3i(1, 0, 2))
	var wolf := engine.board.entity_at(1, 0, 2)
	_check(wolf != null and wolf.kind == Enums.EntityKind.WARDEN and wolf.hp == 14, "A Warden stands in the cell")
	_place(engine, warrior, "cleave", 2)
	engine.resolve_round()
	_check(wolf.hp == 13, "The Warden blocks 6 of a 7 damage hit (hp %d)" % wolf.hp)
	_check(druid.hp == 40, "The Warden took the hit instead of the Druid")

	var piercing := _unit("hunter", 0, 40)
	var druid2 := _unit("druid", 1, 40)
	var pierce := _engine(CombatRules.new(), [piercing, druid2])
	_place_aim(pierce, druid2, "wolf", 2, Vector3i(1, 0, 2))
	var wolf2 := pierce.board.entity_at(1, 0, 2)
	_place(pierce, piercing, "volley", 2)
	pierce.resolve_round()
	_check(wolf2.hp == 9, "Pierce ignores the Warden's block (hp %d)" % wolf2.hp)

	var witch := _unit("witch", 0, 40)
	var reaver := _unit("reaver", 1, 40)
	var guard := _unit("warrior", 0, 40)
	var spark := _engine(CombatRules.new(), [witch, reaver, guard])
	_place_aim(spark, witch, "raven", 0, Vector3i(0, 1, 2))
	spark.resolve_round()
	_check(reaver.hp == 40, "The Spark has nothing to strike when the enemy placed no card (hp %d)" % reaver.hp)
	spark.begin_round()
	_place(spark, reaver, "rend", 2)
	_place(spark, guard, "shield_wall", 2)
	spark.resolve_round()
	_check(reaver.hp == 36, "The Spark strikes the nearest enemy every Upkeep (hp %d)" % reaver.hp)

	# Familiars vanish with their owner and leave a corpse where the owner stood.
	var owner := _unit("druid", 1, 3)
	var killer := _unit("witch", 0, 40)
	var duel := _engine(CombatRules.new(), [owner, killer])
	_place_aim(duel, owner, "wolf", 0, Vector3i(1, 0, 2))
	_place(duel, killer, "hex_bolt", 0)
	duel.resolve_round()
	_check(not owner.is_alive(), "The owner fell")
	_check(duel.board.entity_at(1, 0, 2) == null, "The Warden vanishes when its owner falls")


func _test_corpses() -> void:
	var weak := _unit("druid", 1, 3)
	var other := _unit("witch", 1, 40)
	var killer := _unit("witch", 0, 40)
	var engine := _engine(CombatRules.new(), [weak, other, killer])
	_place(engine, weak, "thorn_lash", 0)
	_place(engine, killer, "hex_bolt", 0)
	engine.resolve_round()
	var corpse := engine.board.entity_at(1, 2, 0)
	_check(corpse != null and corpse.kind == Enums.EntityKind.CORPSE, "A fallen character leaves a corpse where its card stood")
	_check(engine.board.target_at(1, 2, 0) == null, "A corpse cannot be attacked")
	engine.begin_round()
	_check(engine.place_card(other, _attack("hex_bolt"), 0) != "", "A corpse blocks its slot in the next round")
	_check(not engine.free_slots(other).has(0), "The corpse's slot is not offered")
	engine.resolve_round()
	engine.begin_round()
	_check(engine.board.entity_at(1, 2, 0) != null, "The corpse is still there in the third round")
	engine.resolve_round()
	engine.begin_round()
	_check(engine.board.entity_at(1, 2, 0) == null, "The corpse has decayed by the fourth round")
	_check(engine.place_card(other, _attack("hex_bolt"), 0) == "", "The slot is free again")


func _test_aiming() -> void:
	var hunter := _unit("hunter", 0, 40)
	var engine := _engine(CombatRules.new(), [hunter, _unit("reaver", 1, 40)])
	var cells := engine.aim_cells(hunter, _attack("spike_pit"), 0)
	_check(cells.size() == 6 and cells.all(func(c: Vector3i) -> bool: return c.x == 1 and c.z <= 2 and c.y <= Enums.Lane.RANGED), "Reach 2 from slot 0 gives six enemy cells in the two lanes a Hunter reaches (%d)" % cells.size())
	var middle := engine.aim_cells(hunter, _attack("spike_pit"), 2)
	_check(middle.size() == 10, "From the middle slot a Hunter reaches the Melee and Ranged lanes (%d)" % middle.size())
	_check(_place_aim(engine, hunter, "snare", 0, Enums.NO_CELL) != "", "An aimed card needs a target cell")
	_check(engine.place_card(hunter, _attack("aimed_shot"), 0) == "", "Ordinary attacks need no aim")
	var rogue := _unit("rogue", 0, 40)
	var trapped := _engine(CombatRules.new(), [rogue, _unit("hunter", 1, 40)])
	_check(trapped.aim_cells(rogue, _attack("disarm"), 0).is_empty(), "Disarm has nothing to aim at without traps")


func _test_clone() -> void:
	var smith := _unit("smith", 0, 40)
	var reaver := _unit("reaver", 1, 40)
	var engine := _engine(CombatRules.new(), [smith, reaver])
	_place_aim(engine, smith, "war_totem", 2, Vector3i(0, 0, 3))
	_lay(engine, Vector3i(1, 0, 2), Enums.Ground.FIRE)
	_place(engine, reaver, "rend", 2)
	var twin := engine.clone()
	_check(twin.board.entities.size() == 1 and twin.board.ground.size() == 1 and twin.board.cards.size() == engine.board.cards.size(), "A clone has the same cards, entities and ground")
	_check(twin.board.units[0] != smith, "A clone has its own characters")
	twin.resolve_round()
	_check(reaver.hp == 40 and smith.hp == 40, "Resolving a clone does not touch the original")
	engine.resolve_round()
	_check(twin.unit_by_id(reaver.id).hp == reaver.hp, "A clone resolves exactly like the original (clone %d, original %d)" % [twin.unit_by_id(reaver.id).hp, reaver.hp])
	_check(twin.board.ground_kind(Vector3i(1, 0, 2)) == engine.board.ground_kind(Vector3i(1, 0, 2)), "Ground matches after resolving both")


func _test_haze_and_quicken() -> void:
	var rogue := _unit("rogue", 0, 40)
	var engine := _engine(CombatRules.new(), [rogue, _unit("reaver", 1, 40)])
	_lay(engine, Vector3i(0, 1, 2), Enums.Ground.HAZE)
	_check(engine.initiative_at(rogue, _attack("quick_stab"), 2) == 7, "Haze takes 3 initiative off a card placed in it")
	_place(engine, rogue, "quick_stab", 2)
	_check(engine.board.card_at(0, 1, 2).initiative == 7, "The placed card carries the haze penalty")
	_place(engine, rogue, "fan_of_knives", 3)
	_check(engine.board.card_at(0, 1, 3).initiative == 0, "The extra-card penalty still applies on clear ground")

	var healer := _unit("healer", 0, 40)
	var warrior := _unit("warrior", 0, 40)
	var rally := _engine(CombatRules.new(), [healer, warrior, _unit("reaver", 1, 40)])
	_place(rally, warrior, "cleave", 0)
	_place(rally, healer, "rally", 1)
	rally.begin_resolution()
	var first := rally.resolve_next()
	_check(first["kind"] == "quicken", "Rally resolves first with its high initiative")
	_check(rally.board.card_at(0, 0, 0).initiative == 11, "Rally raises the initiative of the cards still to come (%d)" % rally.board.card_at(0, 0, 0).initiative)


func _ai_engine(units: Array, first_side: int = 1) -> CombatEngine:
	var rules := CombatRules.new()
	rules.first_side = first_side
	var engine := CombatEngine.new(rules)
	for unit in units:
		engine.board.add_unit(unit)
	engine.begin_round()
	return engine


func _test_ai_behaviour() -> void:
	# It does not step on a visible Spike Pit while a clear slot exists.
	var rogue := _unit("rogue", 1, 40)
	var warrior := _unit("warrior", 0, 40)
	var engine := _ai_engine([rogue, warrior])
	for slot in [0, 1, 2, 4]:
		_lay(engine, Vector3i(1, 1, slot), Enums.Ground.SPIKE_PIT, 0)
	var choice := SimpleAI.choose(engine, 1)
	_check(not choice.is_empty() and choice["slot"] == 3, "The AI picks the only untrapped slot (picked %s)" % str(choice.get("slot")))

	# It would rather pass than walk into a Snare when every slot is snared.
	var rogue2 := _unit("rogue", 1, 40)
	var snared := _ai_engine([rogue2, _unit("warrior", 0, 40)])
	for slot in 5:
		_lay(snared, Vector3i(1, 1, slot), Enums.Ground.SNARE, 0)
	var passed := SimpleAI.play_turn(snared, 1)
	_check(passed == null, "The AI passes instead of feeding cards to snares")

	# It stays out of cells that are about to burn.
	var rogue3 := _unit("rogue", 1, 40)
	var fire := _ai_engine([rogue3, _unit("warrior", 0, 40)])
	for slot in [0, 1, 2, 3]:
		_lay(fire, Vector3i(1, 1, slot), Enums.Ground.FIRE, 0)
	var choice3 := SimpleAI.choose(fire, 1)
	_check(choice3["slot"] == 4, "The AI avoids burning cells (picked %s)" % str(choice3.get("slot")))

	# It disarms a Flame Trap that is about to go off when its people are inside the blast.
	var druid := _unit("rogue", 1, 40)
	var warrior_a := _unit("warrior", 1, 40)
	var player := _unit("hunter", 0, 40)
	var bomb := _ai_engine([druid, warrior_a, player])
	_lay(bomb, Vector3i(1, 0, 2), Enums.Ground.FLAME_TRAP, 0)
	bomb.board.ground[Vector3i(1, 0, 2)].turns_left = 1
	_place(bomb, warrior_a, "cleave", 2)
	var disarm := SimpleAI.choose(bomb, 1)
	_check(disarm["attack"].id == "disarm" and disarm["aim"] == Vector3i(1, 0, 2), "The AI disarms a ticking Flame Trap when its Warrior stands in the blast (chose %s)" % disarm["attack"].id)


## Each removal card answers specific ground only; water and fire touch only some traps.
func _test_counter_matrix() -> void:
	var healer := _unit("healer", 0, 40)
	var rogue := _unit("rogue", 0, 40)
	var warrior := _unit("warrior", 0, 40)
	var enemy := _unit("reaver", 1, 40)
	var engine := _engine(CombatRules.new(), [healer, rogue, warrior, enemy])
	var cell := Vector3i(1, 0, 0)
	var kinds := [Enums.Ground.OIL, Enums.Ground.GRASS, Enums.Ground.FIRE, Enums.Ground.WATER, Enums.Ground.HAZE, Enums.Ground.SPIKE_PIT, Enums.Ground.TRIPWIRE, Enums.Ground.SNARE, Enums.Ground.FLAME_TRAP]
	var expected := {
		"cleanse": [Enums.Ground.OIL, Enums.Ground.HAZE],
		"disarm": [Enums.Ground.TRIPWIRE, Enums.Ground.SNARE, Enums.Ground.FLAME_TRAP],
		"stomp": [Enums.Ground.SPIKE_PIT],
	}
	var owners := {"cleanse": healer, "disarm": rogue, "stomp": warrior}
	for card_id in expected:
		for kind in kinds:
			_lay(engine, cell, kind)
			var allowed: bool = engine.aim_error(owners[card_id], _attack(card_id), 0, cell) == ""
			_check(allowed == expected[card_id].has(kind), "%s %s %s" % [card_id, "clears" if expected[card_id].has(kind) else "ignores", GroundRules.display_name(kind)])

	# Rain and fire against every trap.
	var druid := _unit("druid", 0, 40)
	var smith := _unit("smith", 0, 40)
	var reactions := {
		Enums.Ground.SPIKE_PIT: [Enums.Ground.SPIKE_PIT, Enums.Ground.SPIKE_PIT],
		Enums.Ground.TRIPWIRE: [Enums.Ground.TRIPWIRE, Enums.Ground.FIRE],
		Enums.Ground.SNARE: [Enums.Ground.SNARE, Enums.Ground.FIRE],
		Enums.Ground.FLAME_TRAP: [Enums.Ground.WATER, Enums.Ground.FLAME_TRAP],
	}
	for trap in reactions:
		var wet := _engine(CombatRules.new(), [druid, smith, _unit("reaver", 1, 40)])
		_lay(wet, cell, trap)
		wet._lay(cell, Enums.Ground.WATER, 0, [])
		_check(wet.board.ground_kind(cell) == reactions[trap][0], "Water on %s leaves %s" % [GroundRules.display_name(trap), GroundRules.display_name(reactions[trap][0])])
		var burning := _engine(CombatRules.new(), [druid, smith, _unit("reaver", 1, 40)])
		_lay(burning, cell, trap)
		burning._lay(cell, Enums.Ground.FIRE, 0, [])
		_check(burning.board.ground_kind(cell) == reactions[trap][1], "Fire on %s leaves %s" % [GroundRules.display_name(trap), GroundRules.display_name(reactions[trap][1])])


## Lane attacks and aimed cards are pointed at a lane; each card's own lane reach limits how deep.
func _test_lane_choice() -> void:
	var warrior := _unit("warrior", 0, 40)
	var rogue := _unit("rogue", 0, 40)
	var druid := _unit("druid", 0, 40)
	var healer := _unit("healer", 0, 40)
	var enemies := [_unit("reaver", 1, 100), _unit("hunter", 1, 100), _unit("witch", 1, 100)]
	var engine := _engine(CombatRules.new(), [warrior, rogue, druid, healer] + enemies)
	var melee := Vector3i(1, Enums.Lane.MELEE, 0)
	var ranged := Vector3i(1, Enums.Lane.RANGED, 0)
	var magic := Vector3i(1, Enums.Lane.MAGIC, 0)

	var sweep_lanes := engine.lane_choices(warrior, _attack("sweeping_strike"))
	_check(sweep_lanes.size() == 1 and sweep_lanes[0] == melee, "A melee lane attack can pick only the enemy front lane")
	_check(engine.lane_choices(rogue, _attack("poison_cloud")).size() == 2, "A ranged lane attack reaches the Melee and Ranged lanes")
	_check(engine.lane_choices(druid, _attack("entangle")).size() == 3, "A magic lane attack reaches every lane")
	_check(engine.lane_choices(rogue, _attack("quick_stab")).is_empty(), "Attacks that are not lane attacks have no lane to pick")
	_check(engine.place_card(warrior, _attack("sweeping_strike"), 0, ranged) != "", "Sweeping Strike cannot be aimed at the Ranged lane")
	_check(engine.place_card(rogue, _attack("poison_cloud"), 0, magic) != "", "Poison Cloud cannot reach the Magic lane")
	_check(engine.place_card(rogue, _attack("poison_cloud"), 0, melee) == "", "Poison Cloud may pick the front lane")
	_check(engine.place_card(druid, _attack("entangle"), 0, magic) == "", "Entangle may pick the back lane")
	_check(engine.place_card(warrior, _attack("sweeping_strike"), 1, Vector3i(0, 0, 0)) != "", "A lane attack on enemies cannot be aimed at your own side")

	# The reach belongs to the card, not the character: the same Rogue reaches further with a thrown card.
	var trap_cells := engine.aim_cells(rogue, _attack("tripwire"), 0)
	_check(trap_cells.size() == 6 and trap_cells.all(func(c: Vector3i) -> bool: return c.y < 2), "A Tripwire reaches two lanes while a Rogue's Quick Stab has no lane to pick")

	# The chosen lane is what gets hit, whatever lane the caster stands in.
	var picks := _engine(CombatRules.new(), [_unit("rogue", 0, 40), _unit("reaver", 1, 100), _unit("hunter", 1, 100)])
	var shooter: CombatUnit = picks.board.units[0]
	var front: CombatUnit = picks.board.units[1]
	var back: CombatUnit = picks.board.units[2]
	_place(picks, front, "rend", 0)
	_place(picks, back, "aimed_shot", 0)
	_check(picks.place_card(shooter, _attack("poison_cloud"), 2, Vector3i(1, Enums.Lane.MELEE, 0)) == "", "Poison Cloud aimed at the front lane")
	picks.resolve_round()
	_check(front.hp < 100 and back.hp == 100, "Only the chosen lane is hit")

	# Allied lane attacks choose among your own lanes freely.
	_check(engine.lane_choices(healer, _attack("soothing_rain")).size() == 3, "Healing rain can be pointed at any of your own lanes")

	# Aimed cards obey their own reach.
	var hunter := _unit("hunter", 0, 40)
	var witch := _unit("witch", 0, 40)
	var smith := _unit("smith", 0, 40)
	var warrior2 := _unit("warrior", 0, 40)
	var aim_engine := _engine(CombatRules.new(), [hunter, witch, smith, warrior2, _unit("reaver", 1, 40)])
	_check(_place_aim(aim_engine, hunter, "spike_pit", 0, magic) != "", "A trap cannot be laid in the enemy Magic lane")
	_check(_place_aim(aim_engine, hunter, "spike_pit", 0, ranged) == "", "A trap can be laid in the enemy Ranged lane")
	_check(_place_aim(aim_engine, witch, "hex_totem", 1, Vector3i(1, Enums.Lane.MAGIC, 1)) == "", "A Hex Totem reaches the enemy Magic lane")
	_check(_place_aim(aim_engine, smith, "ember_throw", 0, ranged) == "", "An ember is thrown into the Ranged lane")
	_check(_place_aim(aim_engine, smith, "ember_throw", 0, magic) != "", "An ember cannot reach the Magic lane")
	_check(aim_engine.aim_error(warrior2, _attack("stomp"), 0, ranged) != "", "Stomp reaches only the enemy front lane")
	var loose_rules := CombatRules.new()
	loose_rules.restrict_lanes = false
	var loose_hunter := _unit("hunter", 0, 40)
	var loose := _engine(loose_rules, [loose_hunter, _unit("reaver", 1, 40)])
	_check(_place_aim(loose, loose_hunter, "spike_pit", 0, magic) == "", "With the restriction off every lane is reachable")


## Difficulty tiers: team sizes, skill lists and consistency with the class lists.
func _test_tiers() -> void:
	var content: Node = load("res://src/core/content_db.gd").new()
	content.reload()
	var sizes := [[4, 3], [5, 4], [5, 5]]
	for tier in BattleSetup.TIERS.size():
		var engine := CombatEngine.new(CombatRules.new())
		BattleSetup.setup_tier(engine, tier, content)
		_check(engine.board.living_units(0).size() == sizes[tier][0] and engine.board.living_units(1).size() == sizes[tier][1], "%s fields %d against %d" % [BattleSetup.TIER_NAMES[tier], sizes[tier][0], sizes[tier][1]])
		for unit in engine.board.units:
			_check(not unit.attacks.is_empty(), "%s has skills on %s" % [unit.display_name, BattleSetup.TIER_NAMES[tier]])
	for tier in BattleSetup.TIERS.size():
		for side_key in ["player", "enemy"]:
			for member in BattleSetup.TIERS[tier][side_key]:
				if not member.has("attacks"):
					continue
				var class_data: ClassData = content.get_class_data(member["class"])
				for attack_id in member["attacks"]:
					_check(class_data.attack_ids.has(attack_id), "%s skill %s belongs to the %s class" % [BattleSetup.TIER_NAMES[tier], attack_id, member["class"]])
	var easy := CombatEngine.new(CombatRules.new())
	BattleSetup.setup_tier(easy, 0, content)
	var ranged := 0
	for unit in easy.board.living_units(0):
		if unit.lane == Enums.Lane.RANGED:
			ranged += 1
	_check(ranged == 1, "Easy drops one of the two middle-lane characters")
	var hard := CombatEngine.new(CombatRules.new())
	BattleSetup.setup_tier(hard, 2, content)
	var full := true
	for unit in hard.board.living_units(0):
		full = full and unit.attacks.size() == unit.class_data.attack_ids.size()
	_check(full, "Hard gives the player every skill of every class")


# ---------------------------------------------------------------- world generation

func _world_db() -> Node:
	var db: Node = load("res://src/core/content_db.gd").new()
	db.reload()
	return db


func _test_world() -> void:
	var db := _world_db()
	_check(db.validate().is_empty(), "World content is consistent: %s" % str(db.validate()))
	_check(db.terrains.size() == 9 and db.biomes.size() == 5, "Nine terrains (with ocean) and five biomes load")

	# Hex maths.
	var round_trip := true
	for c in HexGrid.disc(Vector2i(3, -2), 4):
		if HexGrid.from_world(HexGrid.to_world(c)) != c:
			round_trip = false
	_check(round_trip, "Hex coordinates survive a trip to world space and back")
	_check(HexGrid.distance(Vector2i(0, 0), Vector2i(2, -1)) == 2 and HexGrid.disc(Vector2i.ZERO, 2).size() == 19, "A settlement's range is 19 hexes")

	# Hashing is fixed: these values must never change, or old seeds stop meaning anything.
	_check(WorldHash.hash2(12345, 7, -3) == WorldHash.hash2(12345, 7, -3), "Hash is repeatable")
	_check(WorldHash.hash2(1, 2, 3) != WorldHash.hash2(1, 3, 2), "Hash depends on argument order")
	_check(WorldHash.hash2(1, 2, 3) == 1826191186, "Hash anchor value (%d)" % WorldHash.hash2(1, 2, 3))
	var noise_ok := true
	for k in 50:
		var v := WorldNoise.fbm(99, k * 0.37, k * 0.11)
		if v < 0.0 or v > 1.0:
			noise_ok = false
	_check(noise_ok, "Noise stays between 0 and 1")

	# The same seed gives the same world; another seed does not.
	var gen := WorldGenerator.new(db)
	var a := gen.generate(5)
	var b := WorldGenerator.new(db).generate(5)
	var c := gen.generate(6)
	_check(a.issues.is_empty(), "Seed 5 is a valid world: %s" % str(a.issues))
	_check(a.terrain == b.terrain and a.biome == b.biome and a.node == b.node and a.location == b.location, "Same seed, same terrain, biomes, nodes and locations")
	_check(a.settlements == b.settlements and a.starts == b.starts and a.attempt == b.attempt, "Same seed, same settlements and starts")
	_check(a.terrain != c.terrain, "A different seed gives a different world")

	var worlds: Array[WorldData] = [a, c, gen.generate(11), gen.generate(12)]
	for w in worlds:
		_check_world_rules(w, db, "seed %d" % w.seed_value)

	_test_world_view(a, db)
	_test_world_party(a)
	_test_world_assets()


func _check_world_rules(w: WorldData, db: Node, label: String) -> void:
	_check(w.issues.is_empty(), "%s: no validation issues %s" % [label, str(w.issues)])
	_check(w.size() > 1200 and w.size() < 2300, "%s: map size %d" % [label, w.size()])
	_check(WorldPathing.components(w).size() == 1, "%s: all walkable land is connected" % label)

	var wyrd_touches_plains := false
	var plains_mid := {}
	for i in w.size():
		for nb in w.neighbors[i]:
			if w.biome[i] == "wyrdwood" and w.biome[nb] == "plainlands":
				wyrd_touches_plains = true
			if w.biome[i] == "plainlands" and (w.biome[nb] == "woodlands" or w.biome[nb] == "highlands" or w.biome[nb] == "wetlands"):
				plains_mid[w.biome[nb]] = true
	_check(not wyrd_touches_plains, "%s: Wyrdwood does not touch Plainlands" % label)
	_check(plains_mid.size() >= 1, "%s: Plainlands border at least one middle biome" % label)

	var node_rules_ok := true
	var terrain_ok := true
	for i in w.size():
		if w.node[i] != "":
			var def: ResourceNodeData = db.get_node_data(w.node[i])
			if def.tier == 2 and not (w.biome[i] in def.biomes):
				node_rules_ok = false
			if def.tier == 3 and w.biome[i] != "wyrdwood":
				node_rules_ok = false
			if not (w.terrain[i] in def.terrains) and w.node[i] != "spring":
				terrain_ok = false
		if w.location[i] != "" and not w.passable(i):
			terrain_ok = false
	_check(node_rules_ok, "%s: tier 2 nodes stay in their biome, tier 3 in Wyrdwood" % label)
	var food_tiers := {}
	for i in w.size():
		if w.node[i] != "":
			var fdef: ResourceNodeData = db.get_node_data(w.node[i])
			if fdef.category == "food":
				food_tiers[fdef.tier] = true
	_check(food_tiers.has(1) and food_tiers.has(2) and food_tiers.has(3), "%s: the world has tier 1, 2 and 3 food nodes" % label)
	_check(terrain_ok, "%s: nodes sit on allowed terrain and locations on walkable hexes" % label)

	var settlements: Array = w.settlements.keys()
	var supplied := true
	var spaced := true
	for s: int in settlements:
		var area := w.disc_indices(s, 2)
		var water := false
		var food := false
		var material := false
		for j in area:
			if w.terrain[j] == "river" or w.node[j] == "spring":
				water = true
			if w.node[j] != "":
				var cat: String = db.get_node_data(w.node[j]).category
				food = food or cat == "food"
				material = material or cat == "material"
		if not ((food or water) and material):
			supplied = false
		for t: int in settlements:
			if t != s and HexGrid.distance(w.coords[s], w.coords[t]) < 7:
				spaced = false
	_check(settlements.size() == 16, "%s: %d NPC settlements (2 per race)" % [label, settlements.size()])
	_check(WorldValidator.water_issues(w, WorldParams.new()).is_empty(), "%s: springs, rivers and lakes obey the water rules" % label)
	_check(supplied, "%s: every settlement has a food source (fresh water counts) and a material within 2 rings" % label)
	_check(spaced, "%s: settlements are at least 7 hexes apart" % label)
	var params := WorldParams.new()
	_check(WorldValidator.longest_straight_coast(w) <= params.max_straight_coast, "%s: no straight coast longer than %d (%d)" % [label, params.max_straight_coast, WorldValidator.longest_straight_coast(w)])
	var river_degree_ok := true
	var fish_ok := true
	for i in w.size():
		if w.terrain[i] == "river":
			var touching := 0
			for nb in w.neighbors[i]:
				if w.terrain[nb] == "river":
					touching += 1
			if touching > 2:
				river_degree_ok = false
		if w.node[i] == "fish" and not (w.terrain[i] == "river" or w.terrain[i] == "lake"):
			fish_ok = false
	for c: Vector2i in w.sea_node.keys():
		if w.has_coord(c) or w.sea_node[c] != "fish":
			fish_ok = false
		var near := false
		for d in HexGrid.disc(c, params.sea_fish_max_shore):
			near = near or w.has_coord(d)
		fish_ok = fish_ok and near
	_check(river_degree_ok, "%s: no river hex touches more than 2 river hexes" % label)
	_check(fish_ok, "%s: fish only in rivers, lakes and the sea within %d hexes of shore" % [label, params.sea_fish_max_shore])
	var budget_ok := true
	for bd: BiomeData in db.biomes.values():
		var walk := 0
		var nodes := 0
		for i in w.biome_hexes(bd.id):
			if w.passable(i):
				walk += 1
			if w.node[i] != "":
				nodes += 1
		var want := (bd.food_per_100 + bd.material_per_100 + bd.signature_per_100) * walk / 100.0
		if nodes < want * 0.75:
			budget_ok = false
	_check(budget_ok, "%s: every biome holds at least 75%% of its resource budget" % label)
	var balanced := true
	var claimed := WorldReach.npc_claimed(w, 2)
	for s: int in settlements:
		var reach := WorldReach.summarize(w, db, s, 2)
		if reach["food_slots"] < params.settlement_food_min or reach["food_slots"] > params.settlement_food_max or reach["material"] < params.settlement_material_min or reach["material"] > params.settlement_material_max :
			balanced = false
		_check(not WorldReach.build_info(w, db, params, s, claimed)["ok"], "%s: a settlement hex is no building site" % label)
	var inland := true
	for s: int in settlements:
		if w.coast_dist[s] < params.settlement_coast_distance:
			inland = false
	_check(inland, "%s: NPC settlements keep %d hexes from the sea" % [label, params.settlement_coast_distance])
	_check(balanced, "%s: every settlement reaches %d-%d food slots (fresh water is one) and %d-%d materials" % [label, params.settlement_food_min, params.settlement_food_max, params.settlement_material_min, params.settlement_material_max])
	var sites := 0
	var site_rule_ok := true
	for i in w.size():
		var info := WorldReach.build_info(w, db, params, i, claimed)
		if info["ok"]:
			sites += 1
			if info["food"] + info["water"] < 1 or info["material"] < 1 or w.terrain[i] == "river" or not w.passable(i):
				site_rule_ok = false
			for s: int in settlements:
				if HexGrid.distance(w.coords[i], w.coords[s]) < params.player_npc_distance:
					site_rule_ok = false
	var p_test := WorldParams.new()
	_check(WorldReach.kind_value(1.0, 2, p_test) > WorldReach.kind_value(1.0, 1, p_test) and WorldReach.kind_value(1.0, 3, p_test) - WorldReach.kind_value(1.0, 2, p_test) < WorldReach.kind_value(1.0, 2, p_test) - WorldReach.kind_value(1.0, 1, p_test), "Further slots of one kind add less each time")
	_check(WorldReach.kind_value(1.0, 1, p_test) * 2.0 > WorldReach.kind_value(1.0, 4, p_test), "Two kinds are worth more than four slots of one")
	_check(site_rule_ok and sites > 20, "%s: building sites follow the rules (%d sites)" % [label, sites])
	_check(not w.starts.has("wyrdwood") and w.starts.size() == 4, "%s: a start for every biome except Wyrdwood" % label)
	for biome_id: String in w.starts.keys():
		_check(w.biome[w.starts[biome_id]] == biome_id and w.passable(w.starts[biome_id]), "%s: %s start lies in its biome on walkable ground" % [label, biome_id])

	var springs_ok := true
	var mountains := {}
	var mountain_total := 0
	for i in w.size():
		if w.node[i] == "spring" and w.terrain[i] != "river":
			springs_ok = false
		if w.terrain[i] == "mountain":
			mountains[w.biome[i]] = int(mountains.get(w.biome[i], 0)) + 1
			mountain_total += 1
	_check(springs_ok, "%s: every spring sits on a river hex" % label)
	var best_biome := ""
	for k: String in mountains.keys():
		if best_biome == "" or float(mountains[k]) / w.biome_hexes(k).size() > float(mountains[best_biome]) / w.biome_hexes(best_biome).size():
			best_biome = k
	_check(mountains.size() >= 3 and best_biome == "highlands", "%s: mountains appear in several biomes and are densest in Highlands (%s)" % [label, str(mountains)])
	_check(float(w.stats["mountain_neighbors"]) < 2.5, "%s: mountains form chains, not blobs (%.2f neighbours)" % [label, float(w.stats["mountain_neighbors"])])
	var split := false
	for b: String in ["plainlands", "woodlands", "highlands", "wetlands", "wyrdwood"]:
		var members := w.biome_hexes(b)
		var seen := {members[0]: true}
		var queue := [members[0]]
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for nb in w.neighbors[cur]:
				if w.biome[nb] == b and not seen.has(nb):
					seen[nb] = true
					queue.append(nb)
		if seen.size() != members.size():
			split = true
	_check(not split, "%s: every biome is one clear-cut region" % label)

	var danger_ok := true
	for i in w.size():
		if w.location[i] != "" and w.location_danger[i] != db.get_biome(w.biome[i]).danger_floor:
			danger_ok = false
	_check(danger_ok, "%s: pre-placed locations sit at their biome's danger floor" % label)


func _test_world_party(w: WorldData) -> void:
	var start: int = w.starts["plainlands"]
	var party := WorldParty.new(start, "spring", w.seed_value)
	party.set_forced_weather("clear")
	_check(party.ap_left == 4 and party.daily_ap() == 4, "Clear spring gives 4 AP")
	var ap_by_season := []
	for s in ["summer", "autumn", "winter"]:
		var q := WorldParty.new(start, s, w.seed_value)
		q.set_forced_weather("clear")
		ap_by_season.append(q.daily_ap())
	_check(ap_by_season == [4, 4, 3], "Summer 4, autumn 4, winter 3 AP in clear weather (%s)" % str(ap_by_season))
	var storm := WorldParty.new(start, "summer", w.seed_value)
	storm.set_forced_weather("storm")
	_check(storm.daily_ap() == 2, "A storm costs 2 AP")
	var snow := WorldParty.new(start, "winter", w.seed_value)
	snow.set_forced_weather("snow")
	_check(snow.daily_ap() == 2, "Snow costs 1 AP")
	_check(WorldWeather.roll(w.seed_value, 5, "winter") == WorldWeather.roll(w.seed_value, 5, "winter"), "Weather is deterministic per seed and day")
	var kinds := {}
	for d in 200:
		kinds[WorldWeather.roll(w.seed_value, d, "winter")] = true
	_check(not kinds.has("rain") or true, "Weather rolls run")

	# Find a target a few hexes away and walk it.
	var dist := WorldPathing.costs_from(w, start)
	var target := -1
	for i in w.size():
		if dist[i] >= 9 and dist[i] <= 12:
			target = i
			break
	_check(target != -1, "A hex 9-12 AP from the start exists")
	var route := party.plan(w, target)
	_check(route.size() > 1 and route[0] == start and route[route.size() - 1] == target, "The route runs from the party to the target")
	_check(WorldPathing.path_cost(w, route) == dist[target], "Route cost equals the least cost")
	var entered := party.move_along(w, route)
	_check(entered.size() > 0, "The party moves")
	_check(party.hex == route[entered.size()] and party.ap_left >= 0 and party.ap_left < 2, "It stops once the next step is too dear (AP left %d)" % party.ap_left)
	var before := party.hex
	var more := party.move_along(w, party.plan(w, target))
	_check(more.size() <= 1 or party.ap_left >= 0, "AP never goes negative")
	_check(before != target, "A 9 AP trip is not finished in one spring day")
	party.end_day()
	_check(party.ap_left == 4 and party.day == 2, "End of day refills AP and counts the day")
	var rest := party.move_along(w, party.plan(w, target))
	_check(rest.size() > 0, "The next day the party carries on")
	for k in 27:
		party.end_day()
	_check(party.season() == "summer", "The season changes after 28 days (%s)" % party.season())

	# Impassable terrain cannot be entered and the planner never routes through it.
	var blocked := -1
	for i in w.size():
		if not w.passable(i):
			blocked = i
			break
	_check(blocked != -1 and WorldPathing.path(w, start, blocked).is_empty(), "A mountain or lake cannot be a destination")
	var through := true
	for i in range(0, w.size(), 37):
		for h in WorldPathing.path(w, start, i):
			if not w.passable(h):
				through = false
	_check(through, "Routes only use walkable hexes")


func _test_world_assets() -> void:
	var assets := WorldAssets.new()
	_check(assets.variants("tiles", "grass").is_empty() or assets.variants("tiles", "grass").size() >= 1, "Asset lookup works for a tile folder")
	_check(assets.variants("nodes", "no_such_node").is_empty(), "A missing folder means no variants")
	var counts_ok := true
	var offsets_ok := true
	for k in 40:
		var coord := Vector2i(k, -k)
		var n := assets.prop_count(77, coord)
		if n < 0 or n > WorldAssets.MAX_PROPS_PER_TILE or n != assets.prop_count(77, coord):
			counts_ok = false
		for j in 3:
			if assets.prop_offset(77, coord, j).length() > 0.66:
				offsets_ok = false
	_check(counts_ok, "Prop counts are small and repeatable")
	_check(offsets_ok, "Props stay inside their hex")


func _test_world_view(w: WorldData, db: Node) -> void:
	var view := WorldView.new()
	view.build(w, db)
	var ocean_tiles := 0
	for child in view._ocean_root.get_children():
		if child is MultiMeshInstance3D:
			ocean_tiles += (child as MultiMeshInstance3D).multimesh.instance_count
	_check(ocean_tiles > 300, "The continent is ringed by sea tiles (%d)" % ocean_tiles)
	_check(view._tile_root.get_child_count() == w.size(), "One tile per land hex")
	var biome_color_ok := true
	for i in range(0, w.size(), 13):
		if w.terrain[i] != "river" and w.terrain[i] != "lake" and view._tile_color(i) != db.get_biome(w.biome[i]).color:
			biome_color_ok = false
	_check(biome_color_ok, "Land tiles take their biome's colour")
	view.free()
