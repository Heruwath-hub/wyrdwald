extends SceneTree
## Smoke test: a few AI-vs-AI battles with timing.
func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var started := Time.get_ticks_msec()
	for i in 6:
		var rules := CombatRules.new()
		var engine := CombatEngine.new(rules)
		engine.rng.seed = rng.randi()
		for entry in BattleSetup.PLAYER_TEAM:
			_add(engine, 0, entry)
		for entry in BattleSetup.ENEMY_TEAM:
			_add(engine, 1, entry)
		BiomeSetup.apply(engine, -1, rng)
		var result := CombatEngine.NO_WINNER
		var decisions := 0
		while result == CombatEngine.NO_WINNER and engine.round_number < 25:
			engine.begin_round()
			while not engine.placement_done():
				SimpleAI.play_turn(engine, engine.current_side)
				decisions += 1
			engine.resolve_round()
			result = engine.winner()
		print("battle %d: result %d rounds %d decisions %d" % [i, result, engine.round_number, decisions])
	print("%d ms" % (Time.get_ticks_msec() - started))
	quit()

func _add(engine: CombatEngine, side: int, entry: Dictionary) -> void:
	var class_data := load("res://content/classes/%s.tres" % entry["class"]) as ClassData
	var unit := CombatUnit.new(engine.board.units.size() + 1, entry["name"], side, class_data, BattleSetup.HP_BY_LANE[class_data.lane()])
	for attack_id in class_data.attack_ids:
		unit.attacks.append(load("res://content/attacks/%s.tres" % attack_id) as AttackData)
	engine.board.add_unit(unit)
