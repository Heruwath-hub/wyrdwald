class_name SimpleAI
extends RefCounted
## Deterministic greedy opponent. It scores every legal card and plays the best one each turn,
## or passes once nothing scores well enough. It does not plan ahead; it exists to be readable.
##
## Scores are in "points of damage". Ordinary attacks are valued from what they would hit.
## Aimed cards (ground, traps, totems, familiars, cleanse) are valued from the board they leave
## behind: damage dealt now, plus what standing traps, totems and familiars are worth. Cards
## whose outcome depends on the order of resolution (fire, water, cleanse) are tried out on a
## copy of the fight. Placement always weighs the cost of the cell itself: a trap that would
## spring, fire that is about to burn, haze, and the damage already aimed at it.

const KILL_BONUS := 5.0
const DANGER_WEIGHT := 0.5
const GUARD_WEIGHT := 0.8
const DELAY_WEIGHT := 0.5
const PASS_BELOW := 0.5
const INITIATIVE_WEIGHT := 0.25

## Cards resolve against whatever stands there at the time, so an opener that sees no enemy
## cards yet still values its attack: this share of its power times the targets it expects to hit.
const BLIND_POWER_SHARE := 0.6
const BLIND_GUARD_SHARE := 0.4

## What an ordinary hit on a totem or familiar is worth compared with the same damage on a character.
const ENTITY_STRIKE_WEIGHT := 0.6
## Share of a trap's cost counted as its value (traps are visible, so they are rarely stepped on).
const TRAP_VALUE_SHARE := 0.6
## Cards a cell is expected to see: used to turn lane crowding into a trap trigger chance.
const TRIPWIRE_COST := 5.0
const SNARE_COST := 6.0
const FLAME_TRAP_VALUE := 1.5
## Each free slot a Flame Trap's blast would take away from a lane that has characters in it.
const FLAME_DENIAL_VALUE := 0.9
const OIL_CELL_VALUE := 0.5
const HAZE_CELL_VALUE := 0.3
const SIM_CANDIDATES := 5

## True while an enemy turn is played blind (see CombatRules.enemy_awareness): the opponent's placed
## cards are ignored, so nothing is countered.
static var blind := false

## When true, the scored candidates of the last choose() call are kept in last_trace.
static var trace := false
static var last_trace: Array[Dictionary] = []


## Plays one turn: places the best card and returns it, or passes and returns null.
static func play_turn(engine: CombatEngine, side: int) -> PlacedCard:
	var choice := pick(engine, side)
	if choice.is_empty() or choice["score"] < PASS_BELOW:
		engine.pass_turn(side)
		return null
	var aim: Vector3i = choice.get("aim", Enums.NO_CELL)
	if engine.place_card(choice["unit"], choice["attack"], choice["slot"], aim) != "":
		engine.pass_turn(side)
		return null
	return engine.board.card_at(side, choice["unit"].lane, choice["slot"])


## The turn the enemy actually takes: usually the best card, but on easier tiers sometimes a mistake.
static func pick(engine: CombatEngine, side: int) -> Dictionary:
	if side == 1 and engine.rules.enemy_awareness < 1.0 and engine.rng.randf() >= engine.rules.enemy_awareness:
		blind = true
		var blind_choice := choose(engine, side)
		blind = false
		if not blind_choice.is_empty():
			return blind_choice
	if side == 1 and engine.rules.enemy_mistakes > 0.0 and engine.rng.randf() < engine.rules.enemy_mistakes:
		var blunder := _random_choice(engine, side)
		if not blunder.is_empty():
			return blunder
	return choose(engine, side)


## Any legal card in any legal slot, aimed at any legal target.
static func _random_choice(engine: CombatEngine, side: int) -> Dictionary:
	var units := engine.units_with_capacity(side)
	if units.is_empty():
		return {}
	var unit: CombatUnit = units[engine.rng.randi() % units.size()]
	var usable: Array[AttackData] = []
	for attack in unit.attacks:
		if not engine.attack_used(unit, attack):
			usable.append(attack)
	var slots := engine.free_slots(unit)
	if usable.is_empty() or slots.is_empty():
		return {}
	var attack: AttackData = usable[engine.rng.randi() % usable.size()]
	var slot: int = slots[engine.rng.randi() % slots.size()]
	var aim := Enums.NO_CELL
	if engine.needs_aim(attack):
		var options: Array[Vector3i] = engine.aim_cells(unit, attack, slot)
		if options.is_empty():
			return {}
		aim = options[engine.rng.randi() % options.size()]
	return {"unit": unit, "attack": attack, "slot": slot, "aim": aim, "score": 1.0}


## Returns {unit, attack, slot, aim, score} for the best card, or an empty dictionary if nothing can be placed.
static func choose(engine: CombatEngine, side: int) -> Dictionary:
	var context := _context(engine, side)
	last_trace.clear()
	var best: Dictionary = {}
	var best_score := -1000000.0
	for unit in engine.units_with_capacity(side):
		for attack in unit.attacks:
			if engine.attack_used(unit, attack):
				continue
			var candidate: Dictionary
			if attack.is_aimed():
				candidate = _best_aimed(engine, context, unit, attack)
			else:
				candidate = _best_plain(engine, context, unit, attack)
			if candidate.is_empty():
				continue
			if trace:
				last_trace.append(candidate)
			if candidate["score"] > best_score:
				best_score = candidate["score"]
				best = candidate
	return best


static func _context(engine: CombatEngine, side: int) -> Dictionary:
	return {
		"side": side,
		"hazard": engine.upkeep_hazard(),
		"baseline": null,  # filled lazily: material after resolving the current board
		"fire_user": _has_fire(engine, side),
	}


static func _has_fire(engine: CombatEngine, side: int) -> bool:
	for unit in engine.board.living_units(side):
		for attack in unit.attacks:
			if attack.ground == Enums.Ground.FIRE or attack.ground == Enums.Ground.FLAME_TRAP:
				return true
	return false


# --- Ordinary attacks -----------------------------------------------------------------------

static func _best_plain(engine: CombatEngine, context: Dictionary, unit: CombatUnit, attack: AttackData) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1000000.0
	# Lane attacks are tried against every lane the caster can reach.
	var aims: Array[Vector3i] = engine.lane_choices(unit, attack)
	if aims.is_empty():
		aims.append(Enums.NO_CELL)
	for aim in aims:
		for slot in engine.free_slots(unit):
			var score := _evaluate(engine, context, unit, attack, slot, aim)
			if score > best_score:
				best_score = score
				best = {"unit": unit, "attack": attack, "slot": slot, "aim": aim, "score": score}
	return best


## Scores a candidate card with the card temporarily on the board, so Single cards re-aim around it.
static func _evaluate(engine: CombatEngine, context: Dictionary, unit: CombatUnit, attack: AttackData, slot: int, aim: Vector3i = Enums.NO_CELL) -> float:
	var board := engine.board
	var candidate := PlacedCard.new()
	candidate.caster = unit
	candidate.attack = attack
	candidate.slot = slot
	candidate.sequence = 1000
	candidate.initiative = engine.initiative_at(unit, attack, slot)
	candidate.aim = aim
	var cell := candidate.cell()
	board.cards[cell] = candidate

	var cells := engine.card_cells(candidate)
	var power := engine.effective_power(attack, cell)
	var score := _offense(engine, unit, attack, cells, power, aim)
	if attack.guard > 0:
		score += GUARD_WEIGHT * _guard_value(engine, unit, attack, cells, candidate)
	if attack.quicken > 0:
		score += _quicken_value(engine, unit, attack)
	score -= _cell_cost(engine, context, unit, attack, slot, cell, candidate)

	board.cards.erase(cell)
	# A snare cancels the whole card: whatever it would have done is lost.
	if engine.trap_kind_for(unit, slot) == Enums.Ground.SNARE:
		return -1.0
	return score


## What standing in this cell costs: damage already aimed at it, fire about to burn it, haze,
## and any trap that would spring. Aimed cards that are simulated skip the parts the simulation shows.
static func _cell_cost(engine: CombatEngine, context: Dictionary, unit: CombatUnit, attack: AttackData, slot: int, cell: Vector3i, candidate: PlacedCard) -> float:
	var cost := DANGER_WEIGHT * _danger(engine, unit, cell, candidate)
	cost += INITIATIVE_WEIGHT * float(attack.initiative - candidate.initiative)
	cost += _hazard_cost(context, unit, cell)
	cost += _trap_cost(engine, unit, slot)
	return cost


static func _hazard_cost(context: Dictionary, unit: CombatUnit, cell: Vector3i) -> float:
	var burn: int = context["hazard"].get(cell, 0)
	if burn <= 0:
		return 0.0
	var cost := float(mini(burn, unit.hp))
	if burn >= unit.hp:
		cost += KILL_BONUS
	return cost


## Cost of stepping on a visible placement trap in this slot (snare is handled by the caller).
static func _trap_cost(engine: CombatEngine, unit: CombatUnit, slot: int) -> float:
	match engine.trap_kind_for(unit, slot):
		Enums.Ground.SPIKE_PIT:
			var cost := float(GroundRules.SPIKE_DAMAGE)
			if unit.hp <= GroundRules.SPIKE_DAMAGE:
				cost += KILL_BONUS
			return cost
		Enums.Ground.TRIPWIRE:
			return TRIPWIRE_COST
	return 0.0


static func _offense(engine: CombatEngine, unit: CombatUnit, attack: AttackData, cells: Array[Vector3i], power: int, aim: Vector3i = Enums.NO_CELL) -> float:
	if attack.guard > 0 or attack.quicken > 0:
		return 0.0
	if attack.target_side == Enums.TargetSide.ENEMY and not _opponent_has_cards(engine, unit.side):
		# Nothing is placed yet. The roster is known, though, and every character stands in its class lane.
		if attack.picks_lane() and aim != Enums.NO_CELL:
			var in_lane := 0.0
			for enemy in engine.board.living_units(1 - unit.side):
				if enemy.lane == aim.y:
					in_lane += 1.0
			return BLIND_POWER_SHARE * float(power) * minf(in_lane, float(Enums.SLOTS_PER_LANE))
		var blind := BLIND_POWER_SHARE * float(power) * _expected_targets(engine, unit.side, attack)
		return blind
	var score := 0.0
	var seen := {}
	for cell in cells:
		var target: Variant = engine.board.target_at(cell.x, cell.y, cell.z)
		if target == null or seen.has(target):
			continue
		seen[target] = true
		if attack.target_side == Enums.TargetSide.ALLY:
			if target is CombatUnit:
				score += float(mini(power, target.max_hp - target.hp))
			continue
		var dealt := mini(power, target.hp)
		var value := float(dealt)
		if target is CombatEntity:
			value = float(dealt) * ENTITY_STRIKE_WEIGHT
			if dealt >= target.hp:
				value += _entity_value(engine, target)
		elif dealt >= target.hp:
			value += KILL_BONUS
		if target.side == unit.side:
			if engine.rules.friendly_fire:
				score -= value
		else:
			score += value
			if attack.delay > 0 and target is CombatUnit:
				score += DELAY_WEIGHT * attack.delay * engine.board.cards_of(target).size()
	return score


static func _opponent_has_cards(engine: CombatEngine, side: int) -> bool:
	if blind:
		return false
	for card in engine.board.cards.values():
		if card.caster.side != side and card.caster.is_alive():
			return true
	return false


static func _expected_targets(engine: CombatEngine, side: int, attack: AttackData) -> float:
	var living := float(engine.board.living_units(1 - side).size())
	match attack.pattern:
		Enums.Pattern.SINGLE:
			return minf(1.0, living)
		Enums.Pattern.ALL:
			return living
	return minf(1.5, living)


## Damage the already placed enemy cards aim at the units this guard would cover, capped at the block.
static func _guard_value(engine: CombatEngine, unit: CombatUnit, attack: AttackData, cells: Array[Vector3i], candidate: PlacedCard) -> float:
	var incoming := 0.0
	for other in engine.board.cards.values():
		if other == candidate or other.caster.side == unit.side or not other.caster.is_alive():
			continue
		if other.attack.guard > 0 or other.attack.target_side == Enums.TargetSide.ALLY or other.attack.is_aimed():
			continue
		var footprint := engine.card_cells(other)
		for cell in cells:
			if footprint.has(cell) and engine.board.unit_at(cell.x, cell.y, cell.z) != null:
				incoming += float(other.attack.power)
	if incoming == 0.0 and not _opponent_has_cards(engine, unit.side):
		return BLIND_GUARD_SHARE * float(attack.guard)
	return minf(float(attack.guard), incoming)


## Quicken is worth a little for every card of the side that has not resolved yet.
static func _quicken_value(engine: CombatEngine, unit: CombatUnit, attack: AttackData) -> float:
	var allies := 0
	for card in engine.board.cards.values():
		if card.caster.side == unit.side and card.caster.is_alive() and card.caster != unit and not card.deployed:
			allies += 1
	return 0.4 * float(attack.quicken) * float(allies)


## Damage the already placed cards would deal to the candidate's character.
static func _danger(engine: CombatEngine, unit: CombatUnit, cell: Vector3i, candidate: PlacedCard) -> float:
	if blind:
		return 0.0
	var danger := 0.0
	for other in engine.board.cards.values():
		if other == candidate or not other.caster.is_alive():
			continue
		if other.attack.target_side == Enums.TargetSide.ALLY or other.attack.guard > 0:
			continue
		if other.caster.side == unit.side and not engine.rules.friendly_fire:
			continue
		if other.attack.is_aimed() and other.attack.power <= 0:
			continue
		if engine.card_cells(other).has(cell):
			danger += float(mini(other.attack.power, unit.hp))
	return danger


# --- Aimed cards ----------------------------------------------------------------------------

static func _best_aimed(engine: CombatEngine, context: Dictionary, unit: CombatUnit, attack: AttackData) -> Dictionary:
	var side: int = context["side"]
	# For every aimable cell remember the cheapest slot the caster can stand in to reach it.
	var slots := engine.free_slots(unit)
	var slot_cost := {}
	var options := {}  # aim cell -> slot
	for slot in slots:
		slot_cost[slot] = _slot_cost(engine, context, unit, attack, slot)
		for aim in engine.aim_cells(unit, attack, slot):
			if not options.has(aim) or slot_cost[slot] < slot_cost[options[aim]]:
				options[aim] = slot
	if options.is_empty():
		return {}

	var scored: Array[Dictionary] = []
	for aim in options:
		if _already_answered(engine, context["side"], attack, aim):
			continue
		var slot: int = options[aim]
		var value := _aim_value(engine, context, unit, attack, slot, aim)
		if value > -999.0:
			scored.append({"aim": aim, "slot": slot, "value": value})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] > b["value"])

	var best: Dictionary = {}
	var best_score := -1000000.0
	var simulate := _needs_simulation(attack)
	var limit := mini(scored.size(), SIM_CANDIDATES if simulate else 3)
	for index in limit:
		var entry: Dictionary = scored[index]
		var slot: int = entry["slot"]
		var aim: Vector3i = entry["aim"]
		var score: float = entry["value"]
		if simulate:
			if score < 0.1:
				continue  # nothing to gain there, so no trial run is worth the time
			score = _simulated_gain(engine, context, unit, attack, slot, aim)
			score -= INITIATIVE_WEIGHT * float(attack.initiative - engine.initiative_at(unit, attack, slot))
			# A Spike Pit's damage shows in the trial run; a Tripwire's Mark and delay do not.
			if engine.trap_kind_for(unit, slot) == Enums.Ground.TRIPWIRE:
				score -= TRIPWIRE_COST
		else:
			score -= slot_cost[slot]
		if score > best_score:
			best_score = score
			best = {"unit": unit, "attack": attack, "slot": slot, "aim": aim, "score": score}
	return best


## True when an own removal card (cleanse or water) is already aimed at this cell this round.
static func _already_answered(engine: CombatEngine, side: int, attack: AttackData, aim: Vector3i) -> bool:
	if attack.clears.is_empty() and attack.ground != Enums.Ground.WATER:
		return false
	for card in engine.board.cards.values():
		if card.caster.side != side or card.aim != aim:
			continue
		if not card.attack.clears.is_empty() or card.attack.ground == Enums.Ground.WATER:
			return true
	return false


## Fire, water and cleanse change what other cards do; their value is read off a trial run.
static func _needs_simulation(attack: AttackData) -> bool:
	if blind:
		return false
	return attack.ground == Enums.Ground.FIRE or attack.ground == Enums.Ground.WATER or not attack.clears.is_empty()


## Cheap cost of the caster standing in a slot (used to pick the slot for an aimed card).
static func _slot_cost(engine: CombatEngine, context: Dictionary, unit: CombatUnit, attack: AttackData, slot: int) -> float:
	var candidate := PlacedCard.new()
	candidate.caster = unit
	candidate.attack = attack
	candidate.slot = slot
	candidate.sequence = 1000
	candidate.initiative = engine.initiative_at(unit, attack, slot)
	var cell := candidate.cell()
	var cost := _cell_cost(engine, context, unit, attack, slot, cell, candidate)
	if engine.trap_kind_for(unit, slot) == Enums.Ground.SNARE:
		cost += SNARE_COST
	return cost


## Cheap estimate used to rank aim cells before anything is simulated.
static func _aim_value(engine: CombatEngine, context: Dictionary, unit: CombatUnit, attack: AttackData, slot: int, aim: Vector3i) -> float:
	var side: int = context["side"]
	var value := 0.0
	if not attack.clears.is_empty():
		value = _cleanse_value(engine, side, aim, attack)
	elif attack.entity != Enums.EntityKind.NONE:
		value = _new_entity_value(engine, unit, attack, aim)
	elif GroundRules.is_trap(attack.ground):
		value = _trap_value(engine, GroundTile.new(attack.ground, side), aim, side)
	elif attack.ground == Enums.Ground.FIRE or attack.ground == Enums.Ground.WATER:
		value = _surface_relevance(engine, attack, aim, side)
	else:
		value = _surface_value(engine, context, attack, aim, side)
	# Small, stable tie-break so equal cells do not always collapse to the lowest slot.
	value += 0.001 * float((aim.z * 7 + aim.y * 3 + engine.round_number) % 5)
	return value


## Value of what is left on the board after the card, from `side`'s point of view.
static func _simulated_gain(engine: CombatEngine, context: Dictionary, unit: CombatUnit, attack: AttackData, slot: int, aim: Vector3i) -> float:
	var side: int = context["side"]
	if context["baseline"] == null:
		var base := engine.clone()
		_run_round(base)
		context["baseline"] = _material(base, side)
	var sim := engine.clone()
	var sim_unit := sim.unit_by_id(unit.id)
	if sim.place_card(sim_unit, attack, slot, aim) != "":
		return -1000.0
	_run_round(sim)
	return _material(sim, side) - float(context["baseline"])


static func _run_round(sim: CombatEngine) -> void:
	sim.begin_resolution()
	while sim.has_pending():
		sim.resolve_next()
	sim.run_upkeep()


## Net advantage for `side`: damage taken by the enemy minus damage taken by us, plus what the
## traps, totems and familiars still standing are worth.
static func _material(sim: CombatEngine, side: int) -> float:
	var total := 0.0
	for unit in sim.board.units:
		var lost := float(unit.max_hp - unit.hp)
		if not unit.is_alive():
			lost += KILL_BONUS
		total += -lost if unit.side == side else lost
	total += _standing(sim, side)
	return total


## Worth of the traps, entities and ground on the board to `side` (negative when they favour the enemy).
static func _standing(engine: CombatEngine, side: int) -> float:
	var total := 0.0
	for cell in engine.board.ground:
		var tile: GroundTile = engine.board.ground[cell]
		var value := _ground_value(engine, tile, cell, side)
		total += value
	for cell in engine.board.entities:
		var entity: CombatEntity = engine.board.entities[cell]
		if not EntityRules.targetable(entity.kind):
			continue
		var value := _entity_value(engine, entity)
		total += value if entity.owner != null and entity.owner.side == side else -value
	return total


static func _ground_value(engine: CombatEngine, tile: GroundTile, cell: Vector3i, side: int) -> float:
	if GroundRules.is_trap(tile.kind):
		var value := _trap_value(engine, tile, cell, tile.owner_side)
		return value if tile.owner_side == side else -value
	if GroundRules.is_fuel(tile.kind) or tile.kind == Enums.Ground.HAZE:
		return _plain_ground_value(engine, tile, cell, side)
	return 0.0


## Oil and dry grass favour whoever can set fire to them; haze hurts whoever must place in it.
static func _plain_ground_value(engine: CombatEngine, tile: GroundTile, cell: Vector3i, side: int) -> float:
	if tile.kind == Enums.Ground.HAZE:
		if not _lane_has_unit(engine, cell):
			return 0.0
		return -HAZE_CELL_VALUE if cell.x == side else HAZE_CELL_VALUE
	var mine := _has_fire(engine, side)
	var theirs := _has_fire(engine, 1 - side)
	var danger_for_cell_owner := (OIL_CELL_VALUE if _lane_has_unit(engine, cell) else 0.0)
	if cell.x == side:
		return -danger_for_cell_owner if theirs else 0.0
	return danger_for_cell_owner if mine else 0.0


static func _lane_has_unit(engine: CombatEngine, cell: Vector3i) -> bool:
	for unit in engine.board.living_units(cell.x):
		if unit.lane == cell.y:
			return true
	return false


## Free slots, in lanes that hold characters, inside the blast of a Flame Trap at `cell`.
static func _blast_slots(engine: CombatEngine, cell: Vector3i) -> int:
	var count := 0
	for target in CombatBoard.shape_cells(cell, Enums.Shape.CROSS):
		if engine.board.is_slot_free(target.x, target.y, target.z) and _lane_has_unit(engine, target):
			count += 1
	return count


## Worth of a trap to the side that laid it: its cost times the chance somebody steps on it.
## Crowded lanes with few free slots make a trigger likely.
static func _trap_value(engine: CombatEngine, tile: GroundTile, cell: Vector3i, laid_by: int) -> float:
	var victims := 0
	for unit in engine.board.living_units(cell.x):
		if unit.lane == cell.y:
			victims += 1
	if victims == 0:
		return 0.0
	if tile.kind == Enums.Ground.FLAME_TRAP:
		return FLAME_TRAP_VALUE + FLAME_DENIAL_VALUE * float(_blast_slots(engine, cell))
	var free := 0
	for slot in Enums.SLOTS_PER_LANE:
		if engine.board.is_slot_free(cell.x, cell.y, slot):
			free += 1
	var chance := clampf(float(victims) / maxf(float(free), 1.0), 0.0, 1.0) * TRAP_VALUE_SHARE
	var cost := 0.0
	match tile.kind:
		Enums.Ground.SPIKE_PIT:
			cost = float(GroundRules.SPIKE_DAMAGE)
		Enums.Ground.TRIPWIRE:
			cost = TRIPWIRE_COST
		Enums.Ground.SNARE:
			cost = SNARE_COST
	return cost * chance


static func _new_entity_value(engine: CombatEngine, unit: CombatUnit, attack: AttackData, aim: Vector3i) -> float:
	var entity := CombatEntity.new(attack.entity, aim, unit)
	return _entity_value(engine, entity)


## Worth of an entity to its owner.
static func _entity_value(engine: CombatEngine, entity: CombatEntity) -> float:
	var owner_side := entity.owner.side if entity.owner != null else entity.side
	var value := 0.2 * float(entity.hp)
	var cell := entity.cell
	match entity.kind:
		Enums.EntityKind.WAR_TOTEM:
			value += _aura_reach(engine, owner_side, cell)
		Enums.EntityKind.HEX_TOTEM:
			value += _aura_reach(engine, 1 - owner_side, cell)
		Enums.EntityKind.WARDEN:
			value += 3.0
		Enums.EntityKind.SPARK:
			value += 4.0
	return value


## How many characters of `side` can be reached by a totem aura centred on `cell`.
static func _aura_reach(engine: CombatEngine, side: int, cell: Vector3i) -> float:
	var reach := 0.0
	for unit in engine.board.living_units(side):
		var distance := absi(unit.lane - cell.y)
		if distance == 0:
			reach += 3.0
		elif distance == 1:
			reach += 1.5
	return minf(reach, 7.0)


## Oil and haze are worth what they leave on the cells they cover.
static func _surface_value(engine: CombatEngine, context: Dictionary, attack: AttackData, aim: Vector3i, side: int) -> float:
	var value := 0.0
	for cell in CombatBoard.shape_cells(aim, attack.shape):
		var existing := engine.board.ground_kind(cell)
		var tile := GroundTile.new(attack.ground, side)
		if attack.ground == Enums.Ground.OIL and (existing == Enums.Ground.FIRE or existing == Enums.Ground.WATER or GroundRules.is_trap(existing)):
			continue
		if attack.ground == Enums.Ground.HAZE and existing != Enums.Ground.NONE and existing != Enums.Ground.HAZE:
			continue
		value += _plain_ground_value(engine, tile, cell, side)
	return value


## A quick guess at how much a fire or water card matters in a place, to pick what to simulate.
static func _surface_relevance(engine: CombatEngine, attack: AttackData, aim: Vector3i, side: int) -> float:
	var relevance := 0.0
	for cell in CombatBoard.shape_cells(aim, attack.shape):
		var kind := engine.board.ground_kind(cell)
		if attack.ground == Enums.Ground.WATER:
			if kind == Enums.Ground.FIRE or kind == Enums.Ground.FLAME_TRAP:
				relevance += 3.0
			elif GroundRules.is_trap(kind) and engine.board.ground_at(cell).owner_side != side:
				relevance += 1.0
		else:
			var target: Variant = engine.board.target_at(cell.x, cell.y, cell.z)
			if target != null and target.side != side:
				relevance += 2.0
			elif _lane_has_unit(engine, cell) and cell.x != side:
				relevance += 0.5
			if GroundRules.is_fuel(kind) and cell.x != side:
				relevance += 1.0
	return relevance


static func _cleanse_value(engine: CombatEngine, side: int, aim: Vector3i, attack: AttackData) -> float:
	var tile := engine.board.ground_at(aim)
	if tile == null:
		return 0.0
	var value := 0.0
	if GroundRules.is_trap(tile.kind):
		value = _trap_value(engine, tile, aim, tile.owner_side)
		if tile.kind == Enums.Ground.FLAME_TRAP:
			value += 4.0 if aim.x == side else 0.0
		return value if tile.owner_side != side else -value
	if tile.kind == Enums.Ground.FIRE:
		return 3.0 if _lane_has_unit(engine, aim) and aim.x == side else 0.0
	# Oil and Haze: worth clearing only where the AI itself would stand.
	if aim.x == side and _lane_has_unit(engine, aim):
		if tile.kind == Enums.Ground.HAZE:
			return 1.5
		if tile.kind == Enums.Ground.OIL:
			return 1.0
	return 0.0
