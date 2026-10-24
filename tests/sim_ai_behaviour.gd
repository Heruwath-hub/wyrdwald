extends SceneTree
## Behaviour report for the AI on the ground layer. Run:
##   godot --headless --path . --script tests/sim_ai_behaviour.gd
## Part 1 plays full AI-vs-AI battles and counts what the AI does with traps, fire, totems and so on.
## Part 2 sets up small controlled situations and prints what the AI chooses.

var BATTLES := int(OS.get_environment("BATTLES")) if OS.has_environment("BATTLES") else 200
const MAX_ROUNDS := 25

const MIRROR_TEAM := [
	{"class": "warrior", "name": "Brann"},
	{"class": "hunter", "name": "Isolde"},
	{"class": "rogue", "name": "Tarn"},
	{"class": "healer", "name": "Mira"},
	{"class": "witch", "name": "Vesna"},
]

var _next_id := 1


func _init() -> void:
	print("=== Part 1: full battles (AI plays both sides) ===")
	_battery("Standard: your party (5) vs the enemy squad (4)", BattleSetup.PLAYER_TEAM, BattleSetup.ENEMY_TEAM, 101)
	_battery("Mirror: both sides field Warrior, Hunter, Rogue, Healer, Witch", MIRROR_TEAM, MIRROR_TEAM, 202)
	print("")
	print("=== Part 2: controlled situations ===")
	_scenarios()
	quit()


# --- Helpers --------------------------------------------------------------------------------

func _unit(class_id: String, side: int, hp: int = -1, unit_name: String = "") -> CombatUnit:
	var class_data := load("res://content/classes/%s.tres" % class_id) as ClassData
	var max_hp: int = hp if hp > 0 else int(BattleSetup.HP_BY_LANE[class_data.lane()])
	var unit := CombatUnit.new(_next_id, unit_name if unit_name != "" else "%s%d" % [class_id, _next_id], side, class_data, max_hp)
	_next_id += 1
	for attack_id in class_data.attack_ids:
		unit.attacks.append(load("res://content/attacks/%s.tres" % attack_id) as AttackData)
	return unit


func _attack(id: String) -> AttackData:
	return load("res://content/attacks/%s.tres" % id) as AttackData


func _inc(stats: Dictionary, key: String, amount: float = 1.0) -> void:
	stats[key] = stats.get(key, 0.0) + amount


func _pct(part: float, whole: float) -> String:
	if whole <= 0.0:
		return "n/a"
	return "%d%%" % roundi(100.0 * part / whole)


# --- Part 1 ---------------------------------------------------------------------------------

func _battery(title: String, team0: Array, team1: Array, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var stats := {}
	var started := Time.get_ticks_msec()
	for battle in BATTLES:
		_one_battle(rng, team0, team1, stats)
	print("")
	print("--- %s (%d battles, %.1fs) ---" % [title, BATTLES, (Time.get_ticks_msec() - started) / 1000.0])
	_report(stats)


func _one_battle(rng: RandomNumberGenerator, team0: Array, team1: Array, stats: Dictionary) -> void:
	var rules := CombatRules.new()
	var engine := CombatEngine.new(rules)
	engine.rng.seed = rng.randi()
	for entry in team0:
		engine.board.add_unit(_unit(entry["class"], 0, -1, entry["name"]))
	for entry in team1:
		engine.board.add_unit(_unit(entry["class"], 1, -1, entry["name"]))
	BiomeSetup.apply(engine, -1, rng)
	_inc(stats, "battles")

	var result := CombatEngine.NO_WINNER
	var bombs := {}  # cell -> {side, fuse_when_answered}
	while result == CombatEngine.NO_WINNER and engine.round_number < MAX_ROUNDS:
		engine.begin_round()
		# Flame traps that go off this round unless something is done.
		var armed := {}
		for cell in engine.board.ground:
			var tile: GroundTile = engine.board.ground[cell]
			if tile.kind == Enums.Ground.FLAME_TRAP:
				armed[cell] = tile.turns_left
				if tile.turns_left == 1:
					_inc(stats, "bomb_rounds_at_fuse1")
		var answered := {}
		while not engine.placement_done():
			_decision(engine, engine.current_side, stats, armed, answered, bombs)
		_resolve(engine, stats)
		for cell in bombs.keys():
			var standing := engine.board.ground_at(cell)
			if standing != null and standing.kind == Enums.Ground.FLAME_TRAP:
				continue
			if answered.has(cell):
				_inc(stats, "bombs_answered")
				_inc(stats, "bomb_answers_total", bombs[cell].get("answers", 1))
				_inc(stats, "bombs_answered_at_fuse_%d" % bombs[cell]["fuse_when_answered"] if bombs[cell].has("fuse_when_answered") else "bombs_answered_at_fuse_?")
			elif engine.board.ground_kind(cell) == Enums.Ground.FIRE:
				_inc(stats, "bombs_detonated")
			else:
				_inc(stats, "bombs_otherwise_gone")
			bombs.erase(cell)
		for cell in armed:
			if armed[cell] != 1:
				continue
			var tile := engine.board.ground_at(cell)
			var burned: bool = engine.board.ground_kind(cell) == Enums.Ground.FIRE
			if burned:
				_inc(stats, "bomb_detonated")
			else:
				_inc(stats, "bomb_removed")
				if answered.has(cell):
					_inc(stats, "bomb_removed_by_card")
		result = engine.winner()
	_inc(stats, "rounds", engine.round_number)
	if result == 0:
		_inc(stats, "win_side0")
	elif result == 1:
		_inc(stats, "win_side1")
	elif result == CombatEngine.DRAW:
		_inc(stats, "draws")
	else:
		_inc(stats, "stalls")


func _decision(engine: CombatEngine, side: int, stats: Dictionary, armed: Dictionary, answered: Dictionary, bombs: Dictionary) -> void:
	var choice := SimpleAI.choose(engine, side)
	_inc(stats, "decisions")
	if choice.is_empty() or choice["score"] < SimpleAI.PASS_BELOW:
		_inc(stats, "passes")
		engine.pass_turn(side)
		return
	var unit: CombatUnit = choice["unit"]
	var attack: AttackData = choice["attack"]
	var slot: int = choice["slot"]
	var aim: Vector3i = choice["aim"]
	var cell := Vector3i(side, unit.lane, slot)

	# Did it step on a visible placement trap?
	var trapped_slots := 0
	var clear_slots := 0
	for free in engine.free_slots(unit):
		if engine.trap_kind_for(unit, free) != Enums.Ground.NONE:
			trapped_slots += 1
		else:
			clear_slots += 1
	if trapped_slots > 0:
		_inc(stats, "trap_exposed_decisions")
		if clear_slots == 0:
			_inc(stats, "trap_all_slots_trapped")
		if engine.trap_kind_for(unit, slot) != Enums.Ground.NONE:
			_inc(stats, "trap_stepped_on")
			if clear_slots > 0:
				_inc(stats, "trap_stepped_on_with_clear_slot")
				var cases: Array = stats.get("trap_cases", [])
				cases.append("%s plays %s onto a %s (score %.1f, %d clear slots left)" % [
					unit.class_data.display_name, attack.display_name, GroundRules.display_name(engine.trap_kind_for(unit, slot)), choice["score"], clear_slots
				])
				stats["trap_cases"] = cases
			else:
				_inc(stats, "trap_stepped_on_forced")
	# Did it stand in a cell that will burn?
	var hazard := engine.upkeep_hazard()
	var safe_slots := 0
	var burning_slots := 0
	for free in engine.free_slots(unit):
		if hazard.has(Vector3i(side, unit.lane, free)):
			burning_slots += 1
		else:
			safe_slots += 1
	if burning_slots > 0:
		_inc(stats, "fire_exposed_decisions")
		if hazard.has(cell):
			_inc(stats, "fire_stood_in")
			if safe_slots > 0:
				_inc(stats, "fire_stood_in_with_safe_slot")
	# Aura: where did it stand relative to the average slot?
	var aura_here := engine.aura_percent(cell)
	var aura_sum := 0.0
	var free_slots := engine.free_slots(unit)
	var any_aura := false
	for free in free_slots:
		var value := engine.aura_percent(Vector3i(side, unit.lane, free))
		aura_sum += value
		if value != 0:
			any_aura = true
	if any_aura and not attack.is_aimed() and attack.guard == 0:
		_inc(stats, "aura_decisions")
		_inc(stats, "aura_chosen_sum", aura_here)
		_inc(stats, "aura_average_sum", aura_sum / float(free_slots.size()))

	if attack.picks_lane() and attack.target_side == Enums.TargetSide.ENEMY and aim != Enums.NO_CELL:
		var best_count := 0
		var picked_count := 0
		for option in engine.lane_choices(unit, attack):
			var count := 0
			for target_slot in Enums.SLOTS_PER_LANE:
				if engine.board.target_at(option.x, option.y, target_slot) != null:
					count += 1
			best_count = maxi(best_count, count)
			if option.y == aim.y:
				picked_count = count
		_inc(stats, "lane_picks")
		_inc(stats, "lane_pick_choices", engine.lane_choices(unit, attack).size())
		_inc(stats, "lane_pick_%s" % Enums.LANE_NAMES[aim.y].to_lower())
		if best_count > 0:
			_inc(stats, "lane_pick_decidable")
			if picked_count == best_count:
				_inc(stats, "lane_pick_best")
			if picked_count > 0:
				_inc(stats, "lane_pick_hit")
		else:
			_inc(stats, "lane_pick_blind")
	_inc(stats, "played_" + attack.id)
	if attack.is_aimed():
		_inc(stats, "aimed_cards")
	# Removal aimed at a bomb.
	if not attack.clears.is_empty() or attack.ground == Enums.Ground.WATER:
		for target in CombatBoard.shape_cells(aim, attack.shape):
			if engine.board.ground_kind(target) == Enums.Ground.FLAME_TRAP and bombs.has(target) and bombs[target]["side"] != side:
				if answered.has(target):
					_inc(stats, "bomb_answer_redundant_same_round")
				answered[target] = true
				var tile := engine.board.ground_at(target)
				bombs[target]["fuse_when_answered"] = tile.turns_left
				bombs[target]["answers"] = bombs[target].get("answers", 0) + 1
				_inc(stats, "bomb_answer_" + attack.id)
				if armed.has(target) and armed[target] == 1:
					_inc(stats, "bomb_answer_cards")
	if attack.ground == Enums.Ground.FLAME_TRAP:
		bombs[aim] = {"side": side}
		_inc(stats, "bombs_laid")
	engine.place_card(unit, attack, slot, aim)
	for event in engine.take_events():
		_inc(stats, "event_" + event["type"])


func _resolve(engine: CombatEngine, stats: Dictionary) -> void:
	engine.begin_resolution()
	while engine.has_pending():
		var step := engine.resolve_next()
		_tally(step, stats)
	for step in engine.run_upkeep():
		_tally(step, stats)


func _tally(step: Dictionary, stats: Dictionary) -> void:
	for event in step["events"]:
		_inc(stats, "event_" + event["type"])
	for hit in step["hits"]:
		if hit["unit"] is CombatEntity and hit["type"] == "damage":
			_inc(stats, "entity_hits")
			if hit["fell"]:
				_inc(stats, "entity_kills")
	if step["kind"] == "burn":
		for hit in step["hits"]:
			_inc(stats, "burn_damage", hit["amount"])
	if step["kind"] == "familiar":
		for hit in step["hits"]:
			_inc(stats, "spark_damage", hit["amount"])


func _report(stats: Dictionary) -> void:
	var battles: float = stats.get("battles", 1.0)
	print("Outcome: side 0 wins %s, side 1 wins %s, draws %s, stalls %s; average %.1f rounds" % [
		_pct(stats.get("win_side0", 0.0), battles), _pct(stats.get("win_side1", 0.0), battles),
		_pct(stats.get("draws", 0.0), battles), _pct(stats.get("stalls", 0.0), battles),
		stats.get("rounds", 0.0) / battles
	])
	var decisions: float = stats.get("decisions", 1.0)
	print("Decisions: %d (%d per battle), passes %s" % [decisions, decisions / battles, _pct(stats.get("passes", 0.0), decisions)])

	print("Cards played per battle:")
	var rows: Array[String] = []
	for key in stats.keys():
		if key.begins_with("played_"):
			rows.append("%s %.2f" % [key.trim_prefix("played_"), stats[key] / battles])
	rows.sort()
	print("  " + ", ".join(rows))
	print("  aimed cards (ground, traps, totems, familiars, cleanse): %.1f per battle of %.1f cards" % [
		stats.get("aimed_cards", 0.0) / battles, (decisions - stats.get("passes", 0.0)) / battles
	])

	var picks: float = stats.get("lane_picks", 0.0)
	if picks > 0.0:
		print("Lane attacks against the enemy: %.2f per battle, %.1f lanes reachable on average" % [picks / battles, stats.get("lane_pick_choices", 0.0) / picks])
		print("  lane chosen: Melee %s, Ranged %s, Magic %s" % [_pct(stats.get("lane_pick_melee", 0.0), picks), _pct(stats.get("lane_pick_ranged", 0.0), picks), _pct(stats.get("lane_pick_magic", 0.0), picks)])
		var decidable: float = stats.get("lane_pick_decidable", 0.0)
		print("  with enemy cards on the board (%s of picks): chose a lane holding the most targets %s, lane held at least one target %s" % [
			_pct(decidable, picks), _pct(stats.get("lane_pick_best", 0.0), decidable), _pct(stats.get("lane_pick_hit", 0.0), decidable)
		])
		print("  placed before any enemy card existed: %s of picks (the AI picks the lane holding most enemy characters)" % _pct(stats.get("lane_pick_blind", 0.0), picks))

	print("Traps:")
	print("  placement traps sprung per battle: %.2f (spike/tripwire/snare events)" % (stats.get("event_trap", 0.0) / battles))
	var exposed: float = stats.get("trap_exposed_decisions", 0.0)
	print("  decisions with a trapped slot in the caster's lane: %d" % exposed)
	print("    stepped on a trap anyway: %s (%d)" % [_pct(stats.get("trap_stepped_on", 0.0), exposed), stats.get("trap_stepped_on", 0.0)])
	print("    ... while an untrapped slot existed: %d" % stats.get("trap_stepped_on_with_clear_slot", 0.0))
	print("    ... with every slot trapped (forced): %d" % stats.get("trap_stepped_on_forced", 0.0))
	print("    decisions where every free slot was trapped: %d" % stats.get("trap_all_slots_trapped", 0.0))
	for case in stats.get("trap_cases", []).slice(0, 6):
		print("      e.g. " + case)

	print("Flame traps:")
	var laid: float = stats.get("bombs_laid", 0.0)
	print("  laid per battle: %.2f; detonated %s; answered with Disarm/Rain %s; otherwise gone %s" % [
		laid / battles, _pct(stats.get("bombs_detonated", 0.0), laid), _pct(stats.get("bombs_answered", 0.0), laid),
		_pct(stats.get("bombs_otherwise_gone", 0.0), laid)
	])
	var answers: Array[String] = []
	for key in stats.keys():
		if key.begins_with("bomb_answer_") and key != "bomb_answer_cards":
			answers.append("%s %d" % [key.trim_prefix("bomb_answer_"), stats[key]])
	answers.sort()
	print("  answers by card: %s; answer cards per answered bomb %.2f" % [
		", ".join(answers) if not answers.is_empty() else "none",
		stats.get("bomb_answers_total", 0.0) / maxf(stats.get("bombs_answered", 0.0), 1.0)
	])
	print("  second answer cards aimed at a bomb that already had one placed that round: %d" % stats.get("bomb_answer_redundant_same_round", 0.0))
	var fuse1: float = stats.get("bomb_rounds_at_fuse1", 0.0)
	print("  bombs that reached their last round: %d; an answer card was played in that round for %s" % [fuse1, _pct(stats.get("bomb_answer_cards", 0.0), fuse1)])
	print("  fire damage dealt per battle: %.1f" % (stats.get("burn_damage", 0.0) / battles))
	var fire_exposed: float = stats.get("fire_exposed_decisions", 0.0)
	print("  decisions with a burning (or about to burn) cell in the lane: %d; stood in it: %s; with a safe slot available: %d" % [
		fire_exposed, _pct(stats.get("fire_stood_in", 0.0), fire_exposed), stats.get("fire_stood_in_with_safe_slot", 0.0)
	])

	print("Totems, familiars, corpses:")
	print("  entity hits by cards per battle: %.2f; entities destroyed: %.2f; Spark damage per battle: %.1f" % [
		stats.get("entity_hits", 0.0) / battles, stats.get("entity_kills", 0.0) / battles, stats.get("spark_damage", 0.0) / battles
	])
	print("  corpses per battle: %.2f; familiars that vanished with their owner: %.2f" % [
		stats.get("event_corpse", 0.0) / battles, stats.get("event_vanish", 0.0) / battles
	])
	var aura_decisions: float = stats.get("aura_decisions", 0.0)
	if aura_decisions > 0.0:
		print("  placements with a totem aura on some slot of the lane: %d; average aura on the chosen slot %+.1f%% vs %+.1f%% across the lane" % [
			aura_decisions, stats.get("aura_chosen_sum", 0.0) / aura_decisions, stats.get("aura_average_sum", 0.0) / aura_decisions
		])


# --- Part 2: controlled situations ----------------------------------------------------------

func _engine_for(units: Array, first_side: int = 1) -> CombatEngine:
	var rules := CombatRules.new()
	rules.first_side = first_side
	var engine := CombatEngine.new(rules)
	for unit in units:
		engine.board.add_unit(unit)
	engine.begin_round()
	return engine


func _lay(engine: CombatEngine, cell: Vector3i, kind: int, owner_side: int = 0, turns: int = -2) -> void:
	var tile := GroundTile.new(kind, owner_side)
	if turns != -2:
		tile.turns_left = turns
	engine.board.ground[cell] = tile


func _describe(choice: Dictionary) -> String:
	if choice.is_empty():
		return "no card"
	if choice["score"] < SimpleAI.PASS_BELOW:
		return "passes (best was %s, score %.1f)" % [choice["attack"].display_name, choice["score"]]
	var text: String = "%s plays %s in slot %d" % [choice["unit"].display_name, choice["attack"].display_name, choice["slot"] + 1]
	if choice["aim"] != Enums.NO_CELL:
		text += " aimed at %s" % CombatEngine.cell_name(choice["aim"])
	return text + " (score %.1f)" % choice["score"]


## Lets the AI take up to `turns` turns on `side` (the other side passes) and describes each.
func _play_out(engine: CombatEngine, side: int, turns: int) -> String:
	var parts: Array[String] = []
	engine.enforce_turns = false
	for turn in turns:
		var choice := SimpleAI.choose(engine, side)
		if choice.is_empty() or choice["score"] < SimpleAI.PASS_BELOW:
			parts.append("passes")
			break
		var text: String = "%s %s" % [choice["unit"].class_data.display_name, choice["attack"].display_name]
		if choice["aim"] != Enums.NO_CELL:
			text += " -> %s" % CombatEngine.cell_name(choice["aim"])
		else:
			text += " (slot %d)" % [choice["slot"] + 1]
		parts.append(text)
		engine.place_card(choice["unit"], choice["attack"], choice["slot"], choice["aim"])
	return "; ".join(parts)


func _scenarios() -> void:
	# 1. Placement traps: one clear slot among trapped ones, and all slots trapped.
	for kind in [Enums.Ground.SPIKE_PIT, Enums.Ground.TRIPWIRE, Enums.Ground.SNARE]:
		var name := GroundRules.display_name(kind)
		for trapped in [1, 3, 4, 5]:
			var rogue := _unit("rogue", 1)
			var engine := _engine_for([rogue, _unit("warrior", 0)])
			for slot in trapped:
				_lay(engine, Vector3i(1, 1, slot), kind, 0)
			var choice := SimpleAI.choose(engine, 1)
			var verdict := _describe(choice)
			if not choice.is_empty() and choice["score"] >= SimpleAI.PASS_BELOW:
				verdict += "  -> %s" % ("STEPS ON THE TRAP" if engine.trap_kind_for(rogue, choice["slot"]) != Enums.Ground.NONE else "avoids the trap")
			print("%-10s %d of 5 slots trapped: %s" % [name, trapped, verdict])
	print("")

	# 2. A Flame Trap in its last round with different answers available.
	print("Flame Trap with one round left on its fuse (the enemy bomb sits in the AI's Melee lane, slot 3):")
	var variants := [
		{"label": "AI has Rogue (Disarm) and Healer (Cleanse); its Warrior already stands in the blast", "team": ["rogue", "healer", "warrior"], "placed": true},
		{"label": "AI has only a Rogue (Disarm); its Warrior already stands in the blast", "team": ["rogue", "warrior"], "placed": true},
		{"label": "AI has a Druid (Rain); its Warrior already stands in the blast", "team": ["druid", "warrior"], "placed": true},
		{"label": "AI has only a Warrior, which has not placed yet (no answer card exists)", "team": ["warrior"], "placed": false},
		{"label": "AI has Rogue and Warrior, nobody placed yet", "team": ["rogue", "warrior"], "placed": false},
	]
	for variant in variants:
		var units: Array = []
		var warrior: CombatUnit = null
		for class_id in variant["team"]:
			var unit := _unit(class_id, 1)
			units.append(unit)
			if class_id == "warrior":
				warrior = unit
		var engine := _engine_for(units + [_unit("hunter", 0)])
		_lay(engine, Vector3i(1, 0, 2), Enums.Ground.FLAME_TRAP, 0, 1)
		if variant["placed"]:
			engine.place_card(warrior, _attack("cleave"), 3)
		print("  %s" % variant["label"])
		print("    -> " + _play_out(engine, 1, 4))
	print("")

	# 3. Fire on the board.
	print("Burning cells:")
	var rogue := _unit("rogue", 1)
	var burn := _engine_for([rogue, _unit("warrior", 0)])
	for slot in [0, 1, 2, 3]:
		_lay(burn, Vector3i(1, 1, slot), Enums.Ground.FIRE, 0)
	print("  Slots 1-4 of the Ranged lane burn: %s" % _describe(SimpleAI.choose(burn, 1)))
	var rogue2 := _unit("rogue", 1, 12)
	var burn2 := _engine_for([rogue2, _unit("warrior", 0)])
	for slot in 5:
		_lay(burn2, Vector3i(1, 1, slot), Enums.Ground.FIRE, 0)
	print("  Every Ranged slot burns (Rogue has 12 HP): %s" % _describe(SimpleAI.choose(burn2, 1)))
	print("")

	# 4. Does it set traps, and where?
	print("Does it lay traps? (AI Hunter alone against two enemy Rogues, nothing placed yet; 5 slots free)")
	var hunter := _unit("hunter", 1)
	var lay := _engine_for([hunter, _unit("rogue", 0), _unit("rogue", 0)])
	SimpleAI.trace = true
	var best := SimpleAI.choose(lay, 1)
	print("  best card: %s" % _describe(best))
	var trace := SimpleAI.last_trace.duplicate()
	trace.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	for entry in trace:
		print("    %-14s score %5.1f" % [entry["attack"].display_name, entry["score"]])
	print("  Same, but the enemy Ranged lane is nearly full (4 of 5 slots taken by cards):")
	var hunter2 := _unit("hunter", 1)
	var filler := [_unit("rogue", 0), _unit("rogue", 0), _unit("trickster", 0), _unit("hunter", 0)]
	var crowded2 := _engine_for([hunter2] + filler, 0)
	crowded2.rules.cards_per_round = 12
	crowded2.enforce_turns = false
	var slot_index := 0
	for unit in filler:
		var first_attack: AttackData = unit.attacks[0]
		crowded2.place_card(unit, first_attack, slot_index)
		slot_index += 1
	crowded2.enforce_turns = true
	crowded2.current_side = 1
	var best2 := SimpleAI.choose(crowded2, 1)
	print("    best card: %s" % _describe(best2))
	SimpleAI.trace = false
	print("")

	# 5. Totem placement.
	print("Totems:")
	var smith := _unit("smith", 1)
	var warrior := _unit("warrior", 1)
	var totem_engine := _engine_for([smith, warrior, _unit("hunter", 0)])
	SimpleAI.trace = true
	var totem_choice := SimpleAI.choose(totem_engine, 1)
	print("  Smith + Warrior vs Hunter, empty board: %s" % _describe(totem_choice))
	for entry in SimpleAI.last_trace:
		if entry["attack"].entity != Enums.EntityKind.NONE:
			print("    %s would go to %s with score %.1f" % [entry["attack"].display_name, CombatEngine.cell_name(entry["aim"]), entry["score"]])
	SimpleAI.trace = false
	var warrior2 := _unit("warrior", 1)
	var aura_engine := _engine_for([warrior2, _unit("smith", 1), _unit("hunter", 0)])
	aura_engine.board.entities[Vector3i(1, 0, 3)] = CombatEntity.new(Enums.EntityKind.WAR_TOTEM, Vector3i(1, 0, 3), aura_engine.board.units[1])
	aura_engine.board.units[1].hp = 0  # take the Smith out so only the Warrior chooses
	var aura_choice := SimpleAI.choose(aura_engine, 1)
	print("  A War Totem stands at slot 4 of the AI's Melee lane -> Warrior plays slot %d (slots 3 and 5 are boosted)" % [aura_choice["slot"] + 1])
	var warrior3 := _unit("warrior", 1)
	var hex_engine := _engine_for([warrior3, _unit("witch", 0)])
	hex_engine.board.entities[Vector3i(1, 0, 3)] = CombatEntity.new(Enums.EntityKind.HEX_TOTEM, Vector3i(1, 0, 3), hex_engine.board.units[1])
	var hex_choice := SimpleAI.choose(hex_engine, 1)
	print("  An enemy Hex Totem stands at slot 4 of the AI's Melee lane -> Warrior plays slot %d (slots 3 and 5 are hexed)" % [hex_choice["slot"] + 1])
	var target_engine := _engine_for([_unit("warrior", 0), _unit("smith", 1)], 0)
	var tot := CombatEntity.new(Enums.EntityKind.HEX_TOTEM, Vector3i(1, 0, 2), target_engine.board.units[0])
	target_engine.board.entities[Vector3i(1, 0, 2)] = tot
	var attacker := target_engine.board.units[0]
	var attack_choice := SimpleAI.choose(target_engine, 0)
	print("  Your Warrior vs a lone Hex Totem (AI plays the Warrior): %s" % _describe(attack_choice))
	print("")

	# 6. Cleanse a trap on its own side.
	print("Trap on the AI's own side:")
	var rogue3 := _unit("rogue", 1)
	var warrior_b := _unit("warrior", 1)
	var own := _engine_for([rogue3, warrior_b, _unit("hunter", 0)])
	for slot in 5:
		_lay(own, Vector3i(1, 1, slot), Enums.Ground.SPIKE_PIT, 0)
	print("  Rogue's lane fully covered in Spike Pits, Rogue cannot Disarm a pit: %s" % _describe(SimpleAI.choose(own, 1)))
	var rogue4 := _unit("rogue", 1)
	var own2 := _engine_for([rogue4, _unit("hunter", 0)])
	for slot in [0, 1, 2, 4]:
		_lay(own2, Vector3i(1, 1, slot), Enums.Ground.SPIKE_PIT, 0)
	print("  Rogue's lane with 4 of 5 slots in Spike Pits: %s" % _describe(SimpleAI.choose(own2, 1)))
