extends SceneTree
## Difficulty tiers against the AI, with a player who plays well or makes mistakes. Run:
##   godot --headless --path . --script tests/sim_difficulty.gd
## DIFF=<n> sets battles per row (default 100). A "sloppy" player replaces a share of its decisions
## with a random legal card in a random slot, which models a new player who misplaces cards and traps.
## The report also follows the player's Healer: how often it dies, when, and what it was doing.

var BATTLES := int(OS.get_environment("DIFF")) if OS.has_environment("DIFF") else 100
const MAX_ROUNDS := 25
const SLOPPY := [0.0, 0.5, 1.0, 10.0, 11.0]

var _content: Node


func _init() -> void:
	_content = load("res://src/core/content_db.gd").new()
	_content.reload()
	var only := OS.get_environment("TIERS")
	for tier in BattleSetup.TIERS.size():
		if only != "" and not only.contains(str(tier)):
			continue
		var entry: Dictionary = BattleSetup.TIERS[tier]
		var skills := 0
		for member in entry["player"]:
			skills += _skill_count(member)
		print("")
		print("=== %s: %d characters with %d skills vs %d enemies (%d skills) ===" % [
			BattleSetup.TIER_NAMES[tier], entry["player"].size(), skills, entry["enemy"].size(), _skill_total(entry["enemy"])
		])
		for sloppy in SLOPPY:
			_row(tier, sloppy)
	quit()


func _policy_name(sloppy: float) -> String:
	if sloppy == 10.0:
		return "novice: first card, leftmost slot"
	if sloppy == 11.0:
		return "novice: biggest hit, leftmost slot"
	return "plays well" if sloppy == 0.0 else "%d%% random" % roundi(sloppy * 100.0)


func _skill_count(member: Dictionary) -> int:
	if member.has("attacks"):
		return member["attacks"].size()
	return (load("res://content/classes/%s.tres" % member["class"]) as ClassData).attack_ids.size()


func _skill_total(team: Array) -> int:
	var total := 0
	for member in team:
		total += _skill_count(member)
	return total


func _row(tier: int, sloppy: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5000 + tier
	var stats := {}
	for battle in BATTLES:
		_battle(tier, sloppy, rng, stats)
	var n := float(BATTLES)
	var healer_rounds: float = stats.get("healer_rounds", 0.0)
	var double_rounds: float = stats.get("healer_double_rounds", 0.0)
	var single_rounds := healer_rounds - double_rounds
	print("player %-9s| wins %3d%% | losses %3d%% | stalls %2d%% | rounds %4.1f | player units lost %.1f | enemy units lost %.1f" % [
		_policy_name(sloppy),
		roundi(100.0 * stats.get("wins", 0.0) / n), roundi(100.0 * stats.get("losses", 0.0) / n), roundi(100.0 * stats.get("stalls", 0.0) / n),
		stats.get("rounds", 0.0) / n, stats.get("player_lost", 0.0) / n, stats.get("enemy_lost", 0.0) / n,
	])
	print("    Healer: dies in %3d%% of battles, first of the party to fall in %3d%%; places 2+ cards in %3d%% of its rounds; death risk per round: %.0f%% with 1 card, %.0f%% with 2+ cards" % [
		roundi(100.0 * stats.get("healer_dead", 0.0) / n), roundi(100.0 * stats.get("healer_first", 0.0) / n),
		roundi(100.0 * double_rounds / maxf(healer_rounds, 1.0)),
		100.0 * (stats.get("healer_died_single", 0.0)) / maxf(single_rounds, 1.0),
		100.0 * (stats.get("healer_died_double", 0.0)) / maxf(double_rounds, 1.0),
	])
	var pc: float = maxf(stats.get("p_cards", 1.0), 1.0)
	var ec: float = maxf(stats.get("e_cards", 1.0), 1.0)
	var rounds_played: float = maxf(stats.get("player_rounds", 1.0), 1.0)
	print("    Speed: mean initiative player %.1f vs enemy %.1f; resolves at %d%% of the order (player) vs %d%% (enemy), 0%% = first; cards cancelled because the caster fell first: player %.1f%% (%.2f per round), enemy %.1f%%; characters wiped before acting per round: player %.2f, enemy %.2f" % [
		stats.get("p_init", 0.0) / pc, stats.get("e_init", 0.0) / ec,
		roundi(100.0 * stats.get("p_rank", 0.0) / pc), roundi(100.0 * stats.get("e_rank", 0.0) / ec),
		100.0 * stats.get("p_cancelled", 0.0) / pc, stats.get("p_cancelled", 0.0) / rounds_played, 100.0 * stats.get("e_cancelled", 0.0) / ec,
		stats.get("p_wiped", 0.0) / rounds_played, stats.get("e_wiped", 0.0) / rounds_played,
	])
	var seen: float = maxf(stats.get("ai_decisions", 1.0), 1.0)
	print("    Enemy counter play: stands in a cell the player already threatens in %d%% of its placements (a random slot would: %d%%); guards cover incoming damage in %d%% of its guard cards" % [
		roundi(100.0 * stats.get("ai_threatened", 0.0) / seen), roundi(100.0 * stats.get("ai_threat_share", 0.0) / seen),
		roundi(100.0 * stats.get("ai_guard_useful", 0.0) / maxf(stats.get("ai_guards", 1.0), 1.0)),
	])
	var tg: float = maxf(stats.get("tg_decisions", 1.0), 1.0)
	print("    Enemy targeting: the character its attacks aim at has %d%% of its HP on average (the other slots it could have used: %d%%); it aims at your Healer in %d%% of attacks (other slots: %d%%)" % [
		roundi(100.0 * stats.get("tg_chosen_hp", 0.0) / tg), roundi(100.0 * stats.get("tg_option_hp", 0.0) / tg),
		roundi(100.0 * stats.get("tg_chosen_healer", 0.0) / tg), roundi(100.0 * stats.get("tg_option_healer", 0.0) / tg),
	])
	print("    Player HP lost per round: %.1f; ground cards played per battle: %.1f; traps stepped on per battle: %.2f" % [
		stats.get("hp_lost", 0.0) / maxf(stats.get("player_rounds", 1.0), 1.0), stats.get("ground_cards", 0.0) / n, stats.get("stepped", 0.0) / n,
	])


func _battle(tier: int, sloppy: float, rng: RandomNumberGenerator, stats: Dictionary) -> void:
	var rules := CombatRules.new()
	rules.difficulty = tier
	if OS.has_environment("FIRST"):
		rules.first_side = int(OS.get_environment("FIRST"))
	var engine := CombatEngine.new(rules)
	engine.rng.seed = rng.randi()
	BattleSetup.setup_tier(engine, tier, _content)
	BiomeSetup.apply(engine, -1, rng)
	# TUNE="cards,mistakes,initiative,awareness,last_stand" overrides the enemy levers while balancing.
	if OS.has_environment("TUNE"):
		var parts := OS.get_environment("TUNE").split(",")
		engine.rules.enemy_cards_per_round = int(parts[0])
		engine.rules.enemy_mistakes = float(parts[1])
		engine.rules.enemy_initiative = int(parts[2])
		engine.rules.enemy_awareness = float(parts[3])
		engine.rules.player_last_stand = parts[4] == "1"
	var healer: CombatUnit = null
	for unit in engine.board.units:
		if unit.side == 0 and unit.class_data.id == "healer":
			healer = unit
	var first_fallen: CombatUnit = null
	var result := CombatEngine.NO_WINNER
	while result == CombatEngine.NO_WINNER and engine.round_number < MAX_ROUNDS:
		engine.begin_round()
		var hp_before := _party_hp(engine, 0)
		var guard := 0
		while not engine.placement_done() and guard < 40:
			guard += 1
			if engine.current_side == 0:
				_player_turn(engine, rng, sloppy, stats)
			else:
				_ai_turn(engine, 1, stats)
		var healer_cards := engine.board.cards_of(healer).size() if healer != null and healer.is_alive() else 0
		var alive_before: Array = engine.board.living_units(0)
		for card in engine.board.cards.values():
			var side_key := "p" if card.caster.side == 0 else "e"
			stats[side_key + "_cards"] = stats.get(side_key + "_cards", 0.0) + 1.0
			stats[side_key + "_init"] = stats.get(side_key + "_init", 0.0) + float(card.initiative)
		engine.begin_resolution()
		var rank := 0
		var total := engine.board.cards.size()
		var fell_unacted := {}
		while engine.has_pending():
			var step := engine.resolve_next()
			var card: PlacedCard = step.get("card", null)
			if card != null:
				var key := "p" if card.caster.side == 0 else "e"
				stats[key + "_rank"] = stats.get(key + "_rank", 0.0) + float(rank) / maxf(float(total - 1), 1.0)
				stats[key + "_acted"] = stats.get(key + "_acted", 0.0) + 1.0
				if step["kind"] == "cancelled":
					stats[key + "_cancelled"] = stats.get(key + "_cancelled", 0.0) + 1.0
					if engine.round_number >= 3:
						stats[key + "_cancelled_late"] = stats.get(key + "_cancelled_late", 0.0) + 1.0
					fell_unacted[card.caster.id] = key
			rank += 1
		for id in fell_unacted:
			var wiped_key: String = fell_unacted[id] + "_wiped"
			stats[wiped_key] = stats.get(wiped_key, 0.0) + 1.0
		engine.run_upkeep()
		stats["hp_lost"] = stats.get("hp_lost", 0.0) + maxf(hp_before - _party_hp(engine, 0), 0.0)
		stats["player_rounds"] = stats.get("player_rounds", 0.0) + 1.0
		if healer_cards > 0:
			stats["healer_rounds"] = stats.get("healer_rounds", 0.0) + 1.0
			var died := not healer.is_alive()
			if healer_cards >= 2:
				stats["healer_double_rounds"] = stats.get("healer_double_rounds", 0.0) + 1.0
				if died:
					stats["healer_died_double"] = stats.get("healer_died_double", 0.0) + 1.0
			elif died:
				stats["healer_died_single"] = stats.get("healer_died_single", 0.0) + 1.0
		if first_fallen == null:
			for unit in alive_before:
				if not unit.is_alive():
					first_fallen = unit
					break
		result = engine.winner()
	stats["rounds"] = stats.get("rounds", 0.0) + engine.round_number
	if result == 0:
		stats["wins"] = stats.get("wins", 0.0) + 1.0
	elif result == 1:
		stats["losses"] = stats.get("losses", 0.0) + 1.0
	elif result == CombatEngine.NO_WINNER:
		stats["stalls"] = stats.get("stalls", 0.0) + 1.0
	if healer != null and not healer.is_alive():
		stats["healer_dead"] = stats.get("healer_dead", 0.0) + 1.0
		if first_fallen == healer:
			stats["healer_first"] = stats.get("healer_first", 0.0) + 1.0
	stats["player_lost"] = stats.get("player_lost", 0.0) + float(engine.board.units.filter(func(u: CombatUnit) -> bool: return u.side == 0 and not u.is_alive()).size())
	stats["enemy_lost"] = stats.get("enemy_lost", 0.0) + float(engine.board.units.filter(func(u: CombatUnit) -> bool: return u.side == 1 and not u.is_alive()).size())


func _party_hp(engine: CombatEngine, side: int) -> float:
	var total := 0.0
	for unit in engine.board.units:
		if unit.side == side and unit.is_alive():
			total += float(unit.hp)
	return total


func _ai_turn(engine: CombatEngine, side: int, stats: Dictionary = {}) -> void:
	var choice := SimpleAI.pick(engine, side)
	if not choice.is_empty() and choice["score"] >= SimpleAI.PASS_BELOW and not stats.is_empty():
		_measure_counter(engine, choice, stats)
	if choice.is_empty() or choice["score"] < SimpleAI.PASS_BELOW:
		engine.pass_turn(side)
		return
	if engine.place_card(choice["unit"], choice["attack"], choice["slot"], choice["aim"]) != "":
		engine.pass_turn(side)
	engine.take_events()


func _novice_turn(engine: CombatEngine, mode: int, rng: RandomNumberGenerator) -> void:
	# Walks through the party in order. Picks a card without reading the board and puts it in the
	# leftmost free slot (the nearest column, which is where the enemy hits first).
	for unit in engine.units_with_capacity(0):
		var best: AttackData = null
		for attack in unit.attacks:
			if engine.attack_used(unit, attack) or attack.is_aimed():
				continue
			if mode == 10:
				best = attack
				break
			if attack.target_side == Enums.TargetSide.ENEMY and attack.guard == 0 and (best == null or attack.power > best.power):
				best = attack
		if best == null:
			continue
		var slots := engine.free_slots(unit)
		if slots.is_empty():
			continue
		var aim := Enums.NO_CELL
		if best.picks_lane():
			var choices := engine.lane_choices(unit, best)
			aim = choices[rng.randi() % choices.size()]
		if engine.place_card(unit, best, slots[0], aim) == "":
			engine.take_events()
			return
	engine.pass_turn(0)


func _player_turn(engine: CombatEngine, rng: RandomNumberGenerator, sloppy: float, stats: Dictionary) -> void:
	if sloppy >= 10.0:
		_novice_turn(engine, int(sloppy), rng)
		return
	if rng.randf() >= sloppy:
		var choice := SimpleAI.choose(engine, 0)
		if choice.is_empty() or choice["score"] < SimpleAI.PASS_BELOW:
			engine.pass_turn(0)
			return
		_count(engine, stats, choice["unit"], choice["attack"], choice["slot"])
		if engine.place_card(choice["unit"], choice["attack"], choice["slot"], choice["aim"]) != "":
			engine.pass_turn(0)
		engine.take_events()
		return
	# A mistake: any legal card in any slot, whatever it costs.
	for attempt in 12:
		var units := engine.units_with_capacity(0)
		if units.is_empty():
			break
		var unit: CombatUnit = units[rng.randi() % units.size()]
		var usable: Array[AttackData] = []
		for attack in unit.attacks:
			if not engine.attack_used(unit, attack):
				usable.append(attack)
		var slots := engine.free_slots(unit)
		if usable.is_empty() or slots.is_empty():
			continue
		var attack: AttackData = usable[rng.randi() % usable.size()]
		var slot: int = slots[rng.randi() % slots.size()]
		var aim := Enums.NO_CELL
		if engine.needs_aim(attack):
			var options: Array[Vector3i] = engine.aim_cells(unit, attack, slot)
			if options.is_empty():
				continue
			aim = options[rng.randi() % options.size()]
		_count(engine, stats, unit, attack, slot)
		if engine.place_card(unit, attack, slot, aim) == "":
			engine.take_events()
			return
	engine.pass_turn(0)


func _count(engine: CombatEngine, stats: Dictionary, unit: CombatUnit, attack: AttackData, slot: int) -> void:
	if attack.is_aimed():
		stats["ground_cards"] = stats.get("ground_cards", 0.0) + 1.0
	if engine.trap_kind_for(unit, slot) != Enums.Ground.NONE:
		stats["stepped"] = stats.get("stepped", 0.0) + 1.0


## Does the enemy stand where the player's placed cards are already aimed? Compared with a random slot.
func _measure_counter(engine: CombatEngine, choice: Dictionary, stats: Dictionary) -> void:
	var unit: CombatUnit = choice["unit"]
	var attack: AttackData = choice["attack"]
	var threatened := {}
	var any_player_cards := false
	for card in engine.board.cards.values():
		if card.caster.side == 0 and card.caster.is_alive() and card.attack.power > 0 and card.attack.target_side == Enums.TargetSide.ENEMY:
			any_player_cards = true
			for cell in engine.card_cells(card):
				threatened[cell] = true
	if attack.guard > 0:
		stats["ai_guards"] = stats.get("ai_guards", 0.0) + 1.0
		var covered := false
		for slot_cell in [Vector3i(1, unit.lane, choice["slot"])]:
			covered = threatened.has(slot_cell)
		if covered or any_player_cards:
			stats["ai_guard_useful"] = stats.get("ai_guard_useful", 0.0) + (1.0 if covered else 0.0)
	if not any_player_cards or attack.is_aimed():
		return
	_measure_targeting(engine, choice, stats)
	var slots := engine.free_slots(unit)
	var share := 0.0
	for slot in slots:
		if threatened.has(Vector3i(1, unit.lane, slot)):
			share += 1.0
	stats["ai_decisions"] = stats.get("ai_decisions", 0.0) + 1.0
	stats["ai_threat_share"] = stats.get("ai_threat_share", 0.0) + share / maxf(float(slots.size()), 1.0)
	if threatened.has(Vector3i(1, unit.lane, choice["slot"])):
		stats["ai_threatened"] = stats.get("ai_threatened", 0.0) + 1.0


## Which character does the chosen placement hit, compared with what the other slots would hit?
func _measure_targeting(engine: CombatEngine, choice: Dictionary, stats: Dictionary) -> void:
	var unit: CombatUnit = choice["unit"]
	var attack: AttackData = choice["attack"]
	if attack.guard > 0 or attack.target_side != Enums.TargetSide.ENEMY or attack.power <= 0:
		return
	var chosen := _weakest_hit(engine, unit, attack, choice["slot"], choice["aim"])
	if chosen == null:
		return
	var total := 0.0
	var counted := 0.0
	var healer_slots := 0.0
	for slot in engine.free_slots(unit):
		var hit := _weakest_hit(engine, unit, attack, slot, choice["aim"])
		if hit != null:
			total += float(hit.hp) / float(hit.max_hp)
			counted += 1.0
			if hit.class_data.id == "healer":
				healer_slots += 1.0
	stats["tg_decisions"] = stats.get("tg_decisions", 0.0) + 1.0
	stats["tg_chosen_hp"] = stats.get("tg_chosen_hp", 0.0) + float(chosen.hp) / float(chosen.max_hp)
	stats["tg_option_hp"] = stats.get("tg_option_hp", 0.0) + total / maxf(counted, 1.0)
	stats["tg_chosen_healer"] = stats.get("tg_chosen_healer", 0.0) + (1.0 if chosen.class_data.id == "healer" else 0.0)
	stats["tg_option_healer"] = stats.get("tg_option_healer", 0.0) + healer_slots / maxf(counted, 1.0)


func _weakest_hit(engine: CombatEngine, unit: CombatUnit, attack: AttackData, slot: int, aim: Vector3i) -> CombatUnit:
	var cell := Vector3i(unit.side, unit.lane, slot)
	if engine.board.cards.has(cell):
		return null
	var ghost := PlacedCard.new()
	ghost.caster = unit
	ghost.attack = attack
	ghost.slot = slot
	ghost.aim = aim
	engine.board.cards[cell] = ghost
	var weakest: CombatUnit = null
	for target_cell in engine.card_cells(ghost):
		var target: CombatUnit = engine.board.unit_at(target_cell.x, target_cell.y, target_cell.z)
		if target != null and target.side != unit.side and (weakest == null or target.hp < weakest.hp):
			weakest = target
	engine.board.cards.erase(cell)
	return weakest
