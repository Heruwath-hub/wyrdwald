extends SceneTree
## Audits state that must reset or stay consistent across rounds. Plays AI and random battles on every
## tier plus mixed squads with every skill, resolving the way the combat screen does (step by step,
## then Upkeep), and counts every broken invariant.
##   AUDIT=60 godot --headless --path . --script tests/audit_rounds.gd

var _fail := {}
var _first := {}
var _checks := 0
var _content: Node


func _init() -> void:
	_content = load("res://src/core/content_db.gd").new()
	_content.reload()
	var battles := int(OS.get_environment("AUDIT")) if OS.get_environment("AUDIT") != "" else 40
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in battles:
		for kind in 5:
			_battle(kind, rng)
	print("%d checks over %d battles per kind" % [_checks, battles])
	if _fail.is_empty():
		print("No inconsistencies found.")
	for key in _fail:
		print("FAIL x%d  %s   e.g. %s" % [_fail[key], key, _first[key]])
	quit()


func _expect(ok: bool, key: String, detail: String) -> void:
	_checks += 1
	if ok:
		return
	_fail[key] = _fail.get(key, 0) + 1
	if not _first.has(key):
		_first[key] = detail


func _battle(kind: int, rng: RandomNumberGenerator) -> void:
	var rules := CombatRules.new()
	var engine := CombatEngine.new(rules)
	engine.rng.seed = rng.randi()
	if kind < 3:
		BattleSetup.setup_tier(engine, kind, _content)
	else:
		var classes := ["warrior", "reaver", "smith", "hunter", "rogue", "trickster", "witch", "druid", "healer"]
		for side in 2:
			for n in 5:
				var id: String = classes[rng.randi() % classes.size()]
				var data: ClassData = _content.get_class_data(id)
				var unit := CombatUnit.new(engine.board.units.size() + 1, "%s%d" % [id, n], side, data, BattleSetup.HP_BY_LANE[data.lane()])
				unit.attacks = _content.attacks_for_class(data)
				engine.board.add_unit(unit)
	BiomeSetup.apply(engine, -1, rng)
	var random_play := kind == 4
	while engine.winner() == CombatEngine.NO_WINNER and engine.round_number < 14:
		engine.begin_round()
		_check_round_start(engine)
		var guard := 0
		while not engine.placement_done() and guard < 80:
			guard += 1
			var side := engine.current_side
			var choice: Dictionary = SimpleAI._random_choice(engine, side) if (random_play or (side == 0 and rng.randf() < 0.3)) else SimpleAI.choose(engine, side)
			if choice.is_empty():
				engine.pass_turn(side)
			else:
				var aim: Vector3i = choice.get("aim", Enums.NO_CELL)
				if engine.place_card(choice["unit"], choice["attack"], choice["slot"], aim) != "":
					engine.pass_turn(side)
		_resolve_like_ui(engine)
		_check_round_end(engine)


func _resolve_like_ui(engine: CombatEngine) -> void:
	engine.begin_resolution()
	var steps := 0
	while engine.has_pending() and steps < 200:
		steps += 1
		var step := engine.resolve_next()
		if step.is_empty():
			break
		for guard in engine._guards:
			_expect(guard["remaining"] >= 0, "guard pool went negative", str(guard["remaining"]))
			var attack_guard := _max_guard(guard)
			_expect(guard["remaining"] <= attack_guard, "guard pool above its card's block value", "%d > %d" % [guard["remaining"], attack_guard])
	engine.run_upkeep()


func _max_guard(guard: Dictionary) -> int:
	var owner: Variant = guard["owner"]
	if owner is CombatEntity:
		return EntityRules.WARDEN_GUARD
	var best := 0
	for attack in owner.attacks:
		best = maxi(best, attack.guard)
	return best


func _check_round_start(engine: CombatEngine) -> void:
	var r := engine.round_number
	_expect(engine._guards.is_empty(), "guards left at the start of a round", "round %d" % r)
	_expect(engine.board.cards.is_empty(), "cards left on the board at round start", "round %d" % r)
	_expect(engine._pending.is_empty(), "pending cards left at round start", "round %d" % r)
	_expect(not engine.resolving, "resolving flag still set at round start", "round %d" % r)
	for unit in engine.board.units:
		_expect(not unit.marked, "Marked flag survived into a new round", unit.display_name)
	_expect(engine.cards_played(0) == 0 and engine.cards_played(1) == 0, "card counters not reset", "round %d" % r)
	_check_board(engine, "round start")


func _check_round_end(engine: CombatEngine) -> void:
	_expect(engine._guards.is_empty(), "guards still active after the round resolved (Upkeep done)", "round %d: %s" % [engine.round_number, str(engine._guards.map(func(g): return "%s %d left" % [g["owner"].display_name, g["remaining"]]))])
	_expect(engine._pending.is_empty(), "cards still pending after the round resolved", "round %d" % engine.round_number)
	_check_board(engine, "round end")


func _check_board(engine: CombatEngine, when: String) -> void:
	var board := engine.board
	for unit in board.units:
		_expect(unit.hp >= 0 and unit.hp <= unit.max_hp, "unit hp out of range", "%s %d/%d" % [unit.display_name, unit.hp, unit.max_hp])
	for cell in board.cards:
		var card: PlacedCard = board.cards[cell]
		_expect(not board.entities.has(cell) or when == "round end", "card placed on a cell holding an entity", str(cell))
	for cell in board.ground:
		var tile: GroundTile = board.ground[cell]
		_expect(tile.kind != Enums.Ground.NONE, "empty ground tile stored", str(cell))
		var permanent: bool = tile.turns_left < 0
		_expect(not permanent or tile.kind in [Enums.Ground.GRASS, Enums.Ground.WATER], "permanent %s tile (should expire)" % GroundRules.display_name(tile.kind), "%s turns_left %d" % [str(cell), tile.turns_left])
		_expect(tile.turns_left != 0, "ground tile with 0 turns left kept", "%s %s" % [GroundRules.display_name(tile.kind), str(cell)])
		_expect(tile.kind != Enums.Ground.FLAME_TRAP or tile.turns_left > 0, "Flame Trap past its fuse kept", str(cell))
	for cell in board.entities:
		var entity: CombatEntity = board.entities[cell]
		_expect(entity.cell == cell, "entity cell mismatch", str(cell))
		_expect(entity.is_alive(), "dead entity still on the board", "%s %s" % [entity.display_name, str(cell)])
		if EntityRules.is_familiar(entity.kind):
			_expect(entity.owner != null and entity.owner.is_alive(), "familiar outlived its owner", "%s at %s" % [entity.display_name, str(cell)])
		if entity.kind == Enums.EntityKind.CORPSE:
			_expect(entity.owner == null or not entity.owner.is_alive(), "corpse of a living unit", str(cell))
		_expect(entity.turns_left != 0, "entity with 0 turns left kept", "%s %s" % [entity.display_name, str(cell)])
