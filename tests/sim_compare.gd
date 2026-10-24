extends SceneTree
## AI vs AI win rates for the standard teams with and without the new cards.
##   godot --headless --path . --script tests/sim_compare.gd

const BATTLES := 100


func _init() -> void:
	for mode in ["legacy cards only", "all cards"]:
		for biome in [0, -1]:
			_run(mode, biome)
	quit()


func _unit(entry: Dictionary, side: int, id: int, legacy: bool) -> CombatUnit:
	var class_data := load("res://content/classes/%s.tres" % entry["class"]) as ClassData
	var unit := CombatUnit.new(id, entry["name"], side, class_data, BattleSetup.HP_BY_LANE[class_data.lane()])
	for attack_id in class_data.attack_ids:
		var attack := load("res://content/attacks/%s.tres" % attack_id) as AttackData
		if legacy and (attack.is_aimed() or attack.quicken > 0):
			continue
		unit.attacks.append(attack)
	return unit


func _run(mode: String, biome: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var wins := 0
	var losses := 0
	var stalls := 0
	var rounds := 0
	var survivors := 0
	for battle in BATTLES:
		var engine := CombatEngine.new(CombatRules.new())
		engine.rng.seed = rng.randi()
		var id := 1
		for entry in BattleSetup.PLAYER_TEAM:
			engine.board.add_unit(_unit(entry, 0, id, mode == "legacy cards only"))
			id += 1
		for entry in BattleSetup.ENEMY_TEAM:
			engine.board.add_unit(_unit(entry, 1, id, mode == "legacy cards only"))
			id += 1
		BiomeSetup.apply(engine, biome, rng)
		var result := CombatEngine.NO_WINNER
		while result == CombatEngine.NO_WINNER and engine.round_number < 25:
			engine.begin_round()
			while not engine.placement_done():
				SimpleAI.play_turn(engine, engine.current_side)
			engine.resolve_round()
			result = engine.winner()
		rounds += engine.round_number
		if result == 0:
			wins += 1
			survivors += engine.board.living_units(0).size()
		elif result == 1:
			losses += 1
		else:
			stalls += 1
	print("%-18s biome %-6s party wins %3d%%  loses %3d%%  other %3d%%  rounds %.1f  survivors on win %.1f" % [
		mode, "bare" if biome == 0 else "random", 100 * wins / BATTLES, 100 * losses / BATTLES, 100 * stalls / BATTLES,
		float(rounds) / BATTLES, float(survivors) / maxf(wins, 1)
	])
