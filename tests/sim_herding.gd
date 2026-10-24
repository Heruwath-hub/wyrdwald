extends SceneTree
## Herding test: can traps on the ground push an AI-controlled squad into a few slot columns,
## and does a Column attack then punish it? Run:
##   godot --headless --path . --script tests/sim_herding.gd
## HERD=<n> sets trials per row (default 100).
##
## Side 1 is the squad under test and plays with the normal AI. Side 0 is a tough Witch and Hunter
## (they always survive) that place after side 1 has finished, so they see the finished board.
## Walls of traps are laid on side 1 before the round starts. Everyone is healed between rounds.

var TRIALS := int(OS.get_environment("HERD")) if OS.has_environment("HERD") else 100
const ROUNDS := 3
const SLOT_COUNT := 5

const MIRROR := ["warrior", "hunter", "rogue", "healer", "witch"]
const SQUAD := ["reaver", "trickster", "druid", "rogue"]
const MELEE_HEAVY := ["warrior", "reaver", "smith", "rogue", "healer"]

var _next_id := 1


func _init() -> void:
	for entry in [["Mirror squad (Warrior, Hunter, Rogue, Healer, Witch)", MIRROR], ["Enemy squad (Reaver, Trickster, Druid, Rogue)", SQUAD]]:
		print("")
		print("=== %s ===" % entry[0])
		var lanes := []
		for class_id in entry[1]:
			var class_data := load("res://content/classes/%s.tres" % class_id) as ClassData
			lanes.append("%s=%s" % [class_id, Enums.LANE_NAMES[class_data.lane()]])
		print("lanes: %s" % ", ".join(lanes))
		_header()
		for config in _configs():
			_row(entry[1], config)
	quit()


func _configs() -> Array:
	return [
		{"name": "no traps", "kind": Enums.Ground.NONE, "cols": []},
		{"name": "Spike Pit  col 1 (3 traps)", "kind": Enums.Ground.SPIKE_PIT, "cols": [0]},
		{"name": "Spike Pit  Melee lane 1-3 only", "kind": Enums.Ground.SPIKE_PIT, "cols": [0, 1, 2], "lanes": [0]},
		{"name": "Spike Pit  cols 1-2", "kind": Enums.Ground.SPIKE_PIT, "cols": [0, 1]},
		{"name": "Spike Pit  cols 1-3", "kind": Enums.Ground.SPIKE_PIT, "cols": [0, 1, 2]},
		{"name": "Tripwire   cols 1-3", "kind": Enums.Ground.TRIPWIRE, "cols": [0, 1, 2]},
		{"name": "Snare      cols 1-3", "kind": Enums.Ground.SNARE, "cols": [0, 1, 2]},
		{"name": "Flame Trap cols 1-3", "kind": Enums.Ground.FLAME_TRAP, "cols": [0, 1, 2]},
		{"name": "Spike Pit  cols 1-4 (one gap)", "kind": Enums.Ground.SPIKE_PIT, "cols": [0, 1, 2, 3]},
		{"name": "Spike Pit  cols 1,2,4,5 (gap in 3)", "kind": Enums.Ground.SPIKE_PIT, "cols": [0, 1, 3, 4]},
		{"name": "COMBO oil on cols 4-5 only", "kind": Enums.Ground.NONE, "cols": [], "oil": [3, 4], "burners": true},
		{"name": "COMBO pits 1-3 + oil 4-5", "kind": Enums.Ground.SPIKE_PIT, "cols": [0, 1, 2], "oil": [3, 4], "burners": true},
		{"name": "COMBO no wall, no oil (control)", "kind": Enums.Ground.NONE, "cols": [], "burners": true},
	]


func _header() -> void:
	print("%-34s | round | cards | stepped | idle | cols used | best col | best cross | walls left | answers | Pierce dmg | hit/card | burn dmg | burned | col 1..5 cards" % "wall")


func _unit(class_id: String, side: int, hp: int, unit_name: String) -> CombatUnit:
	var class_data := load("res://content/classes/%s.tres" % class_id) as ClassData
	var max_hp: int = hp if hp > 0 else int(BattleSetup.HP_BY_LANE[class_data.lane()])
	var unit := CombatUnit.new(_next_id, unit_name, side, class_data, max_hp)
	_next_id += 1
	for attack_id in class_data.attack_ids:
		unit.attacks.append(load("res://content/attacks/%s.tres" % attack_id) as AttackData)
	return unit


func _row(team: Array, config: Dictionary) -> void:
	var totals := []
	for round_index in ROUNDS:
		totals.append({})
	for trial in TRIALS:
		_trial(team, config, 9000 + trial, totals)
	for round_index in ROUNDS:
		var t: Dictionary = totals[round_index]
		var n := float(TRIALS)
		var dist := []
		for slot in SLOT_COUNT:
			dist.append("%.1f" % (t.get("slot%d" % slot, 0.0) / n))
		print("%-34s |   %d   | %5.1f | %7.2f | %4.2f | %9.2f | %8.2f | %10.2f | %10.1f | %7.2f | %10.1f | %8.2f | %8.1f | %6.2f | %s" % [
			config["name"] if round_index == 0 else "", round_index + 1,
			t.get("cards", 0.0) / n, t.get("stepped", 0.0) / n, t.get("idle", 0.0) / n,
			t.get("cols", 0.0) / n, t.get("best_col", 0.0) / n, t.get("best_cross", 0.0) / n,
			t.get("walls", 0.0) / n, t.get("answers", 0.0) / n,
			t.get("aoe_dmg", 0.0) / n, t.get("hits", 0.0) / maxf(t.get("strikes", 0.0), 1.0), t.get("burn", 0.0) / n, t.get("burned", 0.0) / n, " ".join(dist),
		])


func _add(totals: Array, round_index: int, key: String, amount: float) -> void:
	var t: Dictionary = totals[round_index]
	t[key] = t.get(key, 0.0) + amount


func _trial(team: Array, config: Dictionary, seed_value: int, totals: Array) -> void:
	var rules := CombatRules.new()
	rules.first_side = 1
	rules.restrict_lanes = OS.get_environment("RESTRICT") != "0"
	var engine := CombatEngine.new(rules)
	engine.rng.seed = seed_value
	var squad: Array[CombatUnit] = []
	for class_id in team:
		var unit := _unit(class_id, 1, -1, class_id)
		squad.append(unit)
		engine.board.add_unit(unit)
	var attackers := [["witch", "chain_lightning"], ["witch", "chain_lightning"], ["hunter", "volley"], ["hunter", "volley"]]
	if config.get("burners", false):
		attackers = [["smith", "ember_throw"], ["smith", "ember_throw"]]
	for attacker in attackers:
		var striker := _unit(attacker[0], 0, 300, "Atk" + attacker[1])
		striker.attacks = [load("res://content/attacks/%s.tres" % attacker[1]) as AttackData]
		engine.board.add_unit(striker)

	# The wall: one trap per cell, in the chosen slot columns of every lane.
	if config["kind"] != Enums.Ground.NONE:
		for lane in config.get("lanes", [0, 1, 2]):
			for col in config["cols"]:
				engine.board.ground[Vector3i(1, lane, col)] = GroundTile.new(config["kind"], 0)
	if config.has("oil"):
		for lane in Enums.LANE_COUNT:
			for col in config["oil"]:
				engine.board.ground[Vector3i(1, lane, col)] = GroundTile.new(Enums.Ground.OIL, 0)

	for round_index in ROUNDS:
		for unit in squad:
			if unit.is_alive():
				unit.hp = unit.max_hp
		engine.begin_round()
		engine.enforce_turns = false

		var walls := 0
		for cell in engine.board.ground:
			if cell.x == 1 and GroundRules.is_trap(engine.board.ground[cell].kind):
				walls += 1
		_add(totals, round_index, "walls", walls)

		# Side 1 places everything it wants.
		var placed := 0
		var stepped := 0
		var answers := 0
		for attempt in 16:
			var choice := SimpleAI.choose(engine, 1)
			if choice.is_empty() or choice["score"] < SimpleAI.PASS_BELOW:
				break
			var unit: CombatUnit = choice["unit"]
			var attack: AttackData = choice["attack"]
			if engine.trap_kind_for(unit, choice["slot"]) != Enums.Ground.NONE and not attack.is_set():
				stepped += 1
			if not attack.clears.is_empty() or attack.ground == Enums.Ground.WATER:
				if choice["aim"].x == 1:
					answers += 1
			var error := engine.place_card(unit, attack, choice["slot"], choice["aim"])
			if error != "":
				break
			placed += 1
		engine.take_events()
		_add(totals, round_index, "cards", placed)
		_add(totals, round_index, "stepped", stepped)
		_add(totals, round_index, "answers", answers)

		# Where did the squad end up?
		var idle := 0
		var columns: Array = []
		for slot in SLOT_COUNT:
			columns.append([])
		var standing: Dictionary = {}  # cell -> unit
		for cell in engine.board.cards:
			var card: PlacedCard = engine.board.cards[cell]
			if cell.x != 1 or not (card.caster in squad):
				continue
			if not columns[cell.z].has(card.caster):
				columns[cell.z].append(card.caster)
			standing[cell] = card.caster
		for unit in squad:
			var has_card := false
			for cell in standing:
				if standing[cell] == unit:
					has_card = true
			if unit.is_alive() and not has_card:
				idle += 1
		var used := 0
		var best_col := 0
		for slot in SLOT_COUNT:
			if not columns[slot].is_empty():
				used += 1
			best_col = maxi(best_col, columns[slot].size())
		var best_cross := 0
		for lane in Enums.LANE_COUNT:
			for slot in SLOT_COUNT:
				var centre := Vector3i(1, lane, slot)
				var cells: Array[Vector3i] = [centre]
				cells.append_array(CombatBoard.cross_neighbours(centre))
				var found: Array = []
				for cell in cells:
					if standing.has(cell) and not found.has(standing[cell]):
						found.append(standing[cell])
				best_cross = maxi(best_cross, found.size())
		for slot in SLOT_COUNT:
			_add(totals, round_index, "slot%d" % slot, standing_per_slot(standing, slot))
		_add(totals, round_index, "idle", idle)
		_add(totals, round_index, "cols", used)
		_add(totals, round_index, "best_col", best_col)
		_add(totals, round_index, "best_cross", best_cross)

		# Side 0 sees the finished board and answers. The fire test plays the combo by hand: the AI
		# counts the damage its Smith would draw as a cost and often passes, which says nothing about herding.
		if config.get("burners", false):
			var targets := [Vector3i(1, Enums.Lane.MELEE, 3), Vector3i(1, Enums.Lane.MELEE, 4)]
			for unit in engine.board.living_units(0):
				var slots := engine.free_slots(unit)
				if slots.is_empty() or targets.is_empty():
					continue
				engine.place_card(unit, unit.attacks[0], slots[0], targets.pop_front())
		for attempt in 16:
			if config.get("burners", false):
				break
			var choice := SimpleAI.choose(engine, 0)
			if choice.is_empty() or choice["score"] < SimpleAI.PASS_BELOW:
				break
			if engine.place_card(choice["unit"], choice["attack"], choice["slot"], choice["aim"]) != "":
				break
		engine.take_events()

		# Resolution: what the AoE cards of side 0 did to the squad.
		var dmg := 0.0
		var strikes := 0
		var hits := 0
		engine.begin_resolution()
		while engine.has_pending():
			var step := engine.resolve_next()
			var hit_units: Array = []
			for hit in step["hits"]:
				if hit["unit"] is CombatUnit and hit["unit"].side == 1 and hit["type"] == "damage":
					dmg += hit["amount"]
					if not hit_units.has(hit["unit"]):
						hit_units.append(hit["unit"])
			if step.get("card", null) != null and step["card"].caster.side == 0:
				strikes += 1
				hits += hit_units.size()
		var burn := 0.0
		var burned: Array = []
		for step in engine.run_upkeep():
			if step["kind"] == "burn":
				for hit in step["hits"]:
					burn += hit["amount"]
					if not burned.has(hit["unit"]):
						burned.append(hit["unit"])
		_add(totals, round_index, "burn", burn)
		_add(totals, round_index, "burned", burned.size())
		_add(totals, round_index, "aoe_dmg", dmg)
		_add(totals, round_index, "strikes", strikes)
		_add(totals, round_index, "hits", hits)


func standing_per_slot(standing: Dictionary, slot: int) -> float:
	var count := 0
	for cell in standing:
		if cell.z == slot:
			count += 1
	return float(count)
