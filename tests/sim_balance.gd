extends SceneTree
## Balance probe. Plays battles between the preset player party and the preset enemy team.
##   godot --headless --path . --script tests/sim_balance.gd
## "greedy" = the player uses the same AI as the enemy; "random" = random legal cards until the budget is spent.
## Sides alternate cards; who opens each round is random.

const BATTLES := 60
const MAX_ROUNDS := 30


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for budget in [7]:
		for enemy_count in [3, 4, 5]:
			for mode in ["greedy", "random"]:
				_run(rng, mode, enemy_count, budget)
	quit()


func _team(enemy_count: int) -> Array:
	var all := BattleSetup.ENEMY_TEAM + [{"class": "witch", "name": "Dread"}]
	return all.slice(0, enemy_count)


func _add(engine: CombatEngine, side: int, team: Array) -> void:
	for entry in team:
		var class_data := load("res://content/classes/%s.tres" % entry["class"]) as ClassData
		var unit := CombatUnit.new(engine.board.units.size() + 1, entry["name"], side, class_data, BattleSetup.HP_BY_LANE[class_data.lane()])
		for attack_id in class_data.attack_ids:
			unit.attacks.append(load("res://content/attacks/%s.tres" % attack_id) as AttackData)
		engine.board.add_unit(unit)


func _random_turn(engine: CombatEngine, rng: RandomNumberGenerator) -> void:
	var units := engine.units_with_capacity(0)
	var unit := units[rng.randi() % units.size()]
	var options: Array[AttackData] = []
	for attack in unit.attacks:
		if not engine.attack_used(unit, attack):
			options.append(attack)
	var slots := engine.free_slots(unit)
	engine.place_card(unit, options[rng.randi() % options.size()], slots[rng.randi() % slots.size()])


func _run(rng: RandomNumberGenerator, mode: String, enemy_count: int, budget: int) -> void:
	var wins := 0
	var losses := 0
	var stalls := 0
	var rounds_total := 0
	var survivors_total := 0
	for i in BATTLES:
		var rules := CombatRules.new()
		rules.cards_per_round = budget
		var engine := CombatEngine.new(rules)
		engine.rng.seed = rng.randi()
		_add(engine, 0, BattleSetup.PLAYER_TEAM)
		_add(engine, 1, _team(enemy_count))
		var result := CombatEngine.NO_WINNER
		while result == CombatEngine.NO_WINNER and engine.round_number < MAX_ROUNDS:
			engine.begin_round()
			while not engine.placement_done():
				if engine.current_side == 0 and mode == "random":
					_random_turn(engine, rng)
				else:
					SimpleAI.play_turn(engine, engine.current_side)
			engine.resolve_round()
			result = engine.winner()
		rounds_total += engine.round_number
		if result == 0:
			wins += 1
			survivors_total += engine.board.living_units(0).size()
		elif result == CombatEngine.NO_WINNER:
			stalls += 1
		else:
			losses += 1
	print("%d enemies, %d cards  player=%-6s  win %3d%%  loss %3d%%  stall %3d%%  avg rounds %.1f  avg survivors on win %.1f" % [
		enemy_count, budget, mode, 100 * wins / BATTLES, 100 * losses / BATTLES, 100 * stalls / BATTLES,
		float(rounds_total) / BATTLES, float(survivors_total) / maxf(wins, 1)
	])
