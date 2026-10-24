class_name CombatEngine
extends RefCounted
## Round flow: card placement, resolution one card at a time in initiative order, then Upkeep.
## Pure rules code; it knows nothing about scenes or UI.
##
## Placement alternates one card at a time between the sides, starting with CombatRules.first_side.
## Each side has a per-round card budget and each character a card cap; a side may pass.
##
## Three layers share the board:
##   cards     placed for one round, resolved in initiative order
##   entities  totems, familiars and corpses; they fill a cell, have hit points and persist
##   ground    oil, fire, water, haze and traps under a cell; Upkeep ticks, spreads and expires it
## Traps and entities take effect the moment their card is placed. Other aimed cards (ground,
## cleanse) resolve in initiative order. Upkeep runs after the last card has resolved.

const NO_WINNER := -1
const DRAW := 2

var board := CombatBoard.new()
var rules: CombatRules
var round_number := 0
var resolving := false

## Whose turn it is to place a card, or -1 once both sides are done.
var current_side := -1
var starting_side := 0
var rng := RandomNumberGenerator.new()

## Tests can switch this off to place cards in any order.
var enforce_turns := true

## Things that happened during placement (traps springing, entities appearing). The UI drains this.
var placement_events: Array[Dictionary] = []

var _counts: Dictionary = {}  # unit id -> cards placed
var _used: Dictionary = {}  # unit id -> attack ids placed
var _sequence := 0
var _played: Array[int] = [0, 0]
var _passed: Array[bool] = [false, false]
var _pending: Array[PlacedCard] = []
var _guards: Array[Dictionary] = []  # {owner, side, lane, slot, remaining}


func _init(p_rules: CombatRules = null) -> void:
	rules = p_rules if p_rules != null else CombatRules.new()


func begin_round() -> void:
	round_number += 1
	board.clear_cards()
	for unit in board.units:
		unit.marked = false
	_counts.clear()
	_used.clear()
	_pending.clear()
	_guards.clear()
	_sequence = 0
	_played = [0, 0]
	_passed = [false, false]
	resolving = false
	placement_events.clear()
	starting_side = rules.first_side if rules.first_side >= 0 else rng.randi() % 2
	current_side = starting_side
	_normalize_turn()


# --- Placement ------------------------------------------------------------------------------

func cards_placed(unit: CombatUnit) -> int:
	return _counts.get(unit.id, 0)


func has_placed(unit: CombatUnit) -> bool:
	return cards_placed(unit) > 0


func attack_used(unit: CombatUnit, attack: AttackData) -> bool:
	return _used.get(unit.id, []).has(attack.id)


## Characters that may still place another card this round.
func units_with_capacity(side: int) -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for unit in board.living_units(side):
		if can_place_more(unit):
			result.append(unit)
	return result


func cards_played(side: int) -> int:
	return _played[side]


func cards_left(side: int) -> int:
	var budget := rules.cards_per_round
	if side == 1 and rules.enemy_cards_per_round >= 0:
		budget = rules.enemy_cards_per_round
	return budget - _played[side]


func can_place_more(unit: CombatUnit) -> bool:
	return (
		unit.is_alive() and not resolving
		and cards_placed(unit) < rules.max_cards_per_character
		and cards_left(unit.side) > 0
		and not free_slots(unit).is_empty()
	)


## True while the side has not passed and could still place a card.
func side_can_place(side: int) -> bool:
	return not _passed[side] and not units_with_capacity(side).is_empty()


func placement_done() -> bool:
	return current_side == -1


func has_passed(side: int) -> bool:
	return _passed[side]


## The side gives up its remaining cards for this round.
func pass_turn(side: int) -> String:
	if enforce_turns and side != current_side:
		return "It is not that side's turn."
	_passed[side] = true
	_advance_turn(side)
	return ""


## Slots in the unit's own lane that can still take a card.
func free_slots(unit: CombatUnit) -> Array[int]:
	var result: Array[int] = []
	for slot in Enums.SLOTS_PER_LANE:
		if board.is_slot_free(unit.side, unit.lane, slot):
			result.append(slot)
	return result


## Initiative the next card of this character would have, before ground modifies it.
func next_initiative(unit: CombatUnit, attack: AttackData) -> int:
	return attack.initiative - rules.extra_card_penalty * cards_placed(unit) + _side_initiative(unit.side)


## Initiative the next card would have in `slot`, including haze on that cell.
func initiative_at(unit: CombatUnit, attack: AttackData, slot: int) -> int:
	return next_initiative(unit, attack) + _ground_initiative(Vector3i(unit.side, unit.lane, slot))


func _side_initiative(side: int) -> int:
	return rules.enemy_initiative if side == 1 else 0


func _ground_initiative(cell: Vector3i) -> int:
	return -GroundRules.HAZE_INIT if board.ground_kind(cell) == Enums.Ground.HAZE else 0


## Returns an empty string on success, otherwise the reason the card was rejected.
## Aimed cards also need `aim`, the cell they are pointed at.
func place_card(unit: CombatUnit, attack: AttackData, slot: int, aim: Vector3i = Enums.NO_CELL) -> String:
	if unit == null or attack == null:
		return "Pick a character and an attack first."
	if resolving:
		return "The round is already resolving."
	if not unit.is_alive():
		return "%s is down." % unit.display_name
	if enforce_turns and unit.side != current_side:
		return "It is not that side's turn to place a card."
	if cards_left(unit.side) <= 0:
		return "No cards left this round."
	if cards_placed(unit) >= rules.max_cards_per_character:
		return "%s has no cards left this round." % unit.display_name
	if not unit.attacks.has(attack):
		return "%s cannot use %s." % [unit.display_name, attack.display_name]
	if attack_used(unit, attack):
		return "%s already placed %s this round." % [unit.display_name, attack.display_name]
	if attack.picks_lane() and aim == Enums.NO_CELL:
		aim = default_lane(unit, attack)
	if needs_aim(attack):
		if aim == Enums.NO_CELL:
			return "Pick a cell to aim %s at." % attack.display_name
		var aim_problem := aim_error(unit, attack, slot, aim)
		if aim_problem != "":
			return aim_problem
		if attack.picks_lane():
			aim = Vector3i(aim.x, aim.y, 0)

	var card := PlacedCard.new()
	card.caster = unit
	card.attack = attack
	card.slot = slot
	card.sequence = _sequence
	card.init_mod = _ground_initiative(Vector3i(unit.side, unit.lane, slot))
	card.initiative = next_initiative(unit, attack) + card.init_mod
	var error := board.put_card(card)
	if error != "":
		return error
	_sequence += 1
	_counts[unit.id] = cards_placed(unit) + 1
	_played[unit.side] += 1
	var used: Array = _used.get(unit.id, [])
	used.append(attack.id)
	_used[unit.id] = used

	_spring_trap(card)
	if attack.picks_lane():
		card.aim = aim
	if attack.is_aimed():
		card.aim = aim
		if attack.is_set() and unit.is_alive() and not card.snared:
			_deploy(card)
	_advance_turn(unit.side)
	return ""


## Takes a card back during placement. Remaining cards of that character are re-timed.
## Cards that sprang a trap or set something cannot be taken back.
func remove_card(card: PlacedCard) -> void:
	if resolving or card == null or card.committed or board.cards.get(card.cell()) != card:
		return
	var unit := card.caster
	board.remove_card(card)
	_counts[unit.id] = cards_placed(unit) - 1
	_played[unit.side] -= 1
	if current_side == -1 and side_can_place(unit.side):
		current_side = unit.side
	var used: Array = _used.get(unit.id, [])
	used.erase(card.attack.id)
	_used[unit.id] = used

	var remaining := board.cards_of(unit)
	remaining.sort_custom(func(a: PlacedCard, b: PlacedCard) -> bool: return a.sequence < b.sequence)
	for index in remaining.size():
		remaining[index].initiative = remaining[index].attack.initiative - rules.extra_card_penalty * index + remaining[index].init_mod + _side_initiative(unit.side)


func _normalize_turn() -> void:
	if side_can_place(current_side):
		return
	var other := 1 - current_side
	current_side = other if side_can_place(other) else -1


## After `side` acted: the other side goes next if it can, otherwise `side` keeps going.
func _advance_turn(side: int) -> void:
	var other := 1 - side
	if side_can_place(other):
		current_side = other
	elif side_can_place(side):
		current_side = side
	else:
		current_side = -1


## Hands over the placement events gathered since the last call.
func take_events() -> Array[Dictionary]:
	var taken := placement_events.duplicate()
	placement_events.clear()
	var result: Array[Dictionary] = []
	result.assign(taken)
	return result


# --- Aiming ---------------------------------------------------------------------------------

## Why `aim` is not a legal target for this card placed in `slot`, or an empty string.
func aim_error(unit: CombatUnit, attack: AttackData, slot: int, aim: Vector3i) -> String:
	if not CombatBoard.is_valid_cell(aim):
		return "That is not a cell."
	if attack.picks_lane():
		var lane_side := unit.side if attack.target_side == Enums.TargetSide.ALLY else 1 - unit.side
		if aim.x != lane_side:
			return "%s must be aimed at a lane on the %s side." % [attack.display_name, "your" if lane_side == unit.side else "enemy"]
		if not lane_reachable(unit, attack, aim.x, aim.y):
			return lane_reach_text(unit, attack)
		return ""
	if attack.aim_side == Enums.AimSide.ENEMY and aim.x == unit.side:
		return "%s must be aimed at the enemy side." % attack.display_name
	if attack.aim_side == Enums.AimSide.OWN and aim.x != unit.side:
		return "%s must be aimed at your own side." % attack.display_name
	if not lane_reachable(unit, attack, aim.x, aim.y):
		return lane_reach_text(unit, attack)
	if absi(aim.z - slot) > attack.reach:
		return "%s reaches %d slots from where the caster stands." % [attack.display_name, attack.reach]
	var caster_cell := Vector3i(unit.side, unit.lane, slot)
	if attack.entity != Enums.EntityKind.NONE:
		if aim == caster_cell or board.cards.has(aim) or board.entities.has(aim):
			return "That cell is occupied."
	elif GroundRules.is_trap(attack.ground):
		if board.ground.has(aim):
			return "That cell already has ground."
	elif not attack.clears.is_empty():
		var tile := board.ground_at(aim)
		if tile == null:
			return "There is nothing to clear there."
		if not attack.clears.has(tile.kind):
			return "%s cannot clear %s." % [attack.display_name, GroundRules.display_name(tile.kind)]
	return ""


## Cards that are pointed at something when placed: aimed cards and lane attacks.
func needs_aim(attack: AttackData) -> bool:
	return attack.is_aimed() or attack.picks_lane()


## Whether `attack` from `unit` may be pointed at this lane of `side`. Enemy lanes are reachable
## up to the card's own `lane_reach`; your own side is always reachable.
func lane_reachable(unit: CombatUnit, attack: AttackData, side: int, lane: int) -> bool:
	return side == unit.side or not rules.restrict_lanes or lane < attack.lane_reach


func lane_reach_text(unit: CombatUnit, attack: AttackData) -> String:
	return "%s reaches %s." % [attack.display_name, lane_reach_summary(attack)]


## "only the enemy Melee lane", "the enemy Melee and Ranged lanes" or "every enemy lane".
static func lane_reach_summary(attack: AttackData) -> String:
	if attack.lane_reach >= Enums.LANE_COUNT:
		return "every enemy lane"
	var names: Array[String] = []
	for lane in attack.lane_reach:
		names.append(Enums.LANE_NAMES[lane])
	return ("only the enemy %s lane" if names.size() == 1 else "the enemy %s lanes") % " and ".join(names)


## One cell per lane a lane attack could be pointed at, as Vector3i(side, lane, 0).
func lane_choices(unit: CombatUnit, attack: AttackData) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if not attack.picks_lane():
		return result
	var side := unit.side if attack.target_side == Enums.TargetSide.ALLY else 1 - unit.side
	for lane in Enums.LANE_COUNT:
		if lane_reachable(unit, attack, side, lane):
			result.append(Vector3i(side, lane, 0))
	return result


## The lane a lane attack takes when no choice is made: the caster's own lane for allies, otherwise
## the occupied reachable enemy lane nearest to the caster's lane (the front one on ties).
func default_lane(unit: CombatUnit, attack: AttackData) -> Vector3i:
	var choices := lane_choices(unit, attack)
	if choices.is_empty():
		return Enums.NO_CELL
	if attack.target_side == Enums.TargetSide.ALLY:
		return Vector3i(unit.side, unit.lane, 0)
	var best := choices[0]
	var best_distance := 1000
	for choice in choices:
		var occupied := false
		for target_slot in Enums.SLOTS_PER_LANE:
			if board.target_at(choice.x, choice.y, target_slot) != null:
				occupied = true
		if occupied and absi(choice.y - unit.lane) < best_distance:
			best = choice
			best_distance = absi(choice.y - unit.lane)
	return best


## Every cell this card could be pointed at if the caster stood in `slot`.
func aim_cells(unit: CombatUnit, attack: AttackData, slot: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if not needs_aim(attack):
		return result
	for side in 2:
		for lane in Enums.LANE_COUNT:
			for target_slot in Enums.SLOTS_PER_LANE:
				var cell := Vector3i(side, lane, target_slot)
				if aim_error(unit, attack, slot, cell) == "":
					result.append(cell)
	return result


## Cells the attack would cover if `unit` placed it in `slot` right now.
func preview_cells(unit: CombatUnit, attack: AttackData, slot: int, aim: Vector3i = Enums.NO_CELL) -> Array[Vector3i]:
	if attack.is_aimed():
		if aim == Enums.NO_CELL:
			var none: Array[Vector3i] = []
			return none
		return CombatBoard.shape_cells(aim, attack.shape)
	var lane := -1
	if attack.picks_lane():
		lane = (aim if aim != Enums.NO_CELL else default_lane(unit, attack)).y
	return PatternResolver.affected_cells(board, unit.side, unit.lane, slot, attack, rules, lane)


## Cells an already placed card covers right now.
func card_cells(card: PlacedCard) -> Array[Vector3i]:
	if card.attack.is_aimed():
		if not card.has_aim():
			var none: Array[Vector3i] = []
			return none
		return CombatBoard.shape_cells(card.aim, card.attack.shape)
	var lane := card.aim.y if card.attack.picks_lane() and card.has_aim() else -1
	return PatternResolver.affected_cells(board, card.caster.side, card.caster.lane, card.slot, card.attack, rules, lane)


## Percent change to cards standing in `cell` from totems in the cells next to it.
func aura_percent(cell: Vector3i) -> int:
	var percent := 0
	for neighbour in CombatBoard.cross_neighbours(cell):
		var entity: CombatEntity = board.entities.get(neighbour, null)
		if entity != null and entity.hp > 0:
			percent += EntityRules.aura_percent(entity.kind)
	return percent


## Power of `attack` when placed in `cell`, after totem auras.
func effective_power(attack: AttackData, cell: Vector3i) -> int:
	var percent := aura_percent(cell)
	if percent == 0 or attack.power <= 0:
		return attack.power
	return maxi(1, roundi(attack.power * (100 + percent) / 100.0))


## A trap that would spring if `unit` placed a card in `slot`, or Enums.Ground.NONE.
func trap_kind_for(unit: CombatUnit, slot: int) -> int:
	var tile := board.ground_at(Vector3i(unit.side, unit.lane, slot))
	if tile != null and GroundRules.is_placement_trap(tile.kind) and tile.owner_side != unit.side:
		return tile.kind
	return Enums.Ground.NONE


func _spring_trap(card: PlacedCard) -> void:
	var cell := card.cell()
	var tile := board.ground_at(cell)
	if tile == null or not GroundRules.is_placement_trap(tile.kind) or tile.owner_side == card.caster.side:
		return
	board.ground.erase(cell)
	card.committed = true
	var unit := card.caster
	var events: Array = []
	match tile.kind:
		Enums.Ground.SPIKE_PIT:
			var dealt := _damage_unit(unit, GroundRules.SPIKE_DAMAGE, events)
			placement_events.append(_event("trap", "%s places a card on a Spike Pit and takes %d damage (%d/%d)." % [unit.display_name, dealt, unit.hp, unit.max_hp]))
		Enums.Ground.TRIPWIRE:
			unit.marked = true
			card.init_mod -= GroundRules.TRIPWIRE_INIT
			card.initiative -= GroundRules.TRIPWIRE_INIT
			placement_events.append(_event("trap", "%s trips a Tripwire: Marked, and the card loses %d initiative." % [unit.display_name, GroundRules.TRIPWIRE_INIT]))
		Enums.Ground.SNARE:
			card.snared = true
			placement_events.append(_event("trap", "%s is caught in a Snare: the card is cancelled." % unit.display_name))
	for event in events:
		placement_events.append(event)


func _deploy(card: PlacedCard) -> void:
	var attack := card.attack
	card.deployed = true
	card.committed = true
	if attack.entity != Enums.EntityKind.NONE:
		var entity := CombatEntity.new(attack.entity, card.aim, card.caster)
		board.entities[card.aim] = entity
		placement_events.append(_event("set", "%s sets a %s at %s." % [card.caster.display_name, entity.display_name, cell_name(card.aim)]))
	else:
		board.ground[card.aim] = GroundTile.new(attack.ground, card.caster.side)
		placement_events.append(_event("set", "%s sets a %s at %s." % [card.caster.display_name, GroundRules.display_name(attack.ground), cell_name(card.aim)]))


# --- Resolution -----------------------------------------------------------------------------

## Every card that resolves this round, highest initiative first.
func ordered_cards() -> Array[PlacedCard]:
	var ordered: Array[PlacedCard] = []
	for card in board.cards.values():
		if not card.deployed:
			ordered.append(card)
	ordered.sort_custom(_card_before)
	return ordered


## Cards that have not resolved yet, in the order they will fire (delays already applied).
func pending_cards() -> Array[PlacedCard]:
	var ordered: Array[PlacedCard] = []
	ordered.append_array(_pending)
	ordered.sort_custom(_card_before)
	return ordered


func has_pending() -> bool:
	return not _pending.is_empty()


func begin_resolution() -> void:
	resolving = true
	_guards.clear()
	_pending.clear()
	for card in board.cards.values():
		if not card.deployed:
			_pending.append(card)
	for warden in board.entities_of_kind(Enums.EntityKind.WARDEN):
		_guards.append({"owner": warden, "side": warden.side, "lane": warden.cell.y, "slot": warden.cell.z, "remaining": EntityRules.WARDEN_GUARD})


## Resolves the next card. Returns an empty dictionary when nothing is pending, otherwise
## {card, kind: cast|miss|cancelled|guard|ground|cleanse|quicken, cells, hits: [{unit, cell, type,
## amount, blocked, delayed, fell}], events: [{type, text}]}. `unit` may be a CombatEntity.
func resolve_next() -> Dictionary:
	if not resolving:
		begin_resolution()
	var queue := pending_cards()
	if queue.is_empty():
		return {}
	var card := queue[0]
	_pending.erase(card)
	return _resolve_card(card)


## Resolves the whole round (cards, then Upkeep) at once and returns the flat event list.
func resolve_round() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	begin_resolution()
	while has_pending():
		events.append_array(resolve_next()["events"])
	for step in run_upkeep():
		events.append_array(step["events"])
	return events


func winner() -> int:
	var side_zero_alive := not board.living_units(0).is_empty()
	var side_one_alive := not board.living_units(1).is_empty()
	if side_zero_alive and side_one_alive:
		return NO_WINNER
	if side_zero_alive:
		return 0
	if side_one_alive:
		return 1
	return DRAW


func _card_before(a: PlacedCard, b: PlacedCard) -> bool:
	if a.initiative != b.initiative:
		return a.initiative > b.initiative
	return a.sequence < b.sequence


func _new_step(card: PlacedCard, kind: String = "cast") -> Dictionary:
	return {"card": card, "kind": kind, "cells": [], "hits": [], "events": [], "origin": card.cell() if card != null else Enums.NO_CELL}


func _resolve_card(card: PlacedCard) -> Dictionary:
	var caster := card.caster
	var attack := card.attack
	var step := _new_step(card)
	var events: Array = step["events"]
	var hits: Array = step["hits"]

	var last_stand := rules.player_last_stand and caster.side == 0
	if not caster.is_alive() and rules.cancel_on_caster_death and not last_stand:
		step["kind"] = "cancelled"
		events.append(_event("cancelled", "%s is down, so %s is cancelled." % [caster.display_name, attack.display_name]))
		return step
	if card.snared:
		step["kind"] = "cancelled"
		events.append(_event("cancelled", "%s is snared, so %s is cancelled." % [caster.display_name, attack.display_name]))
		return step

	var cells := card_cells(card)
	step["cells"] = cells

	if attack.is_aimed():
		return _resolve_aimed(card, step)

	if attack.guard > 0:
		step["kind"] = "guard"
		if not caster.is_alive():
			events.append(_event("miss", "%s is down and cannot raise %s." % [caster.display_name, attack.display_name]))
			return step
		_guards.append({"owner": caster, "side": caster.side, "lane": caster.lane, "slot": card.slot, "remaining": attack.guard})
		events.append(_event("guard", "%s raises %s (blocks %d)." % [caster.display_name, attack.display_name, attack.guard]))
		var covered := {}
		for cell in cells:
			var unit := board.unit_at(cell.x, cell.y, cell.z)
			if unit != null and not covered.has(unit.id):
				covered[unit.id] = true
				hits.append({"unit": unit, "cell": cell, "type": "guard", "amount": 0, "blocked": 0, "delayed": 0, "fell": false})
		return step

	if attack.quicken > 0:
		step["kind"] = "quicken"
		var boosted: Array[Vector3i] = []
		for other in _pending:
			if other.caster.side == caster.side and other.caster.is_alive():
				other.initiative += attack.quicken
				boosted.append(other.cell())
		step["cells"] = boosted
		events.append(_event("quicken", "%s uses %s: %d card(s) gain %d initiative." % [caster.display_name, attack.display_name, boosted.size(), attack.quicken]))
		return step

	var seen := {}
	var targets: Array[Dictionary] = []
	for cell in cells:
		var target: Variant = board.target_at(cell.x, cell.y, cell.z)
		if target != null and not seen.has(target):
			seen[target] = true
			targets.append({"unit": target, "cell": cell})
	if targets.is_empty():
		step["kind"] = "miss"
		events.append(_event("miss", "%s uses %s and hits nothing." % [caster.display_name, attack.display_name]))
		return step

	events.append(_event("cast", "%s uses %s." % [caster.display_name, attack.display_name]))
	var power := effective_power(attack, card.cell())
	for entry in targets:
		var target: Variant = entry["unit"]
		var cell: Vector3i = entry["cell"]

		if attack.target_side == Enums.TargetSide.ALLY:
			if not (target is CombatUnit):
				continue
			var healed := mini(power, target.max_hp - target.hp)
			if healed == 0:
				continue
			target.hp += healed
			hits.append({"unit": target, "cell": cell, "type": "heal", "amount": healed, "blocked": 0, "delayed": 0, "fell": false})
			events.append(_event("heal", "  %s recovers %d HP (%d/%d)." % [target.display_name, healed, target.hp, target.max_hp]))
			continue

		var friendly: bool = target.side == caster.side
		if friendly and not rules.friendly_fire:
			continue
		_strike(target, cell, power, caster.side, attack.pattern == Enums.Pattern.PIERCE, attack.delay, step)
	return step


## Aimed cards that resolve in initiative order: ground laid, ground cleansed.
func _resolve_aimed(card: PlacedCard, step: Dictionary) -> Dictionary:
	var caster := card.caster
	var attack := card.attack
	var events: Array = step["events"]
	var cells: Array = step["cells"]

	if attack.is_set():
		step["kind"] = "miss"
		events.append(_event("miss", "%s has nothing to resolve." % attack.display_name))
		return step

	if not attack.clears.is_empty():
		step["kind"] = "cleanse"
		var cleared := 0
		for cell in cells:
			var tile := board.ground_at(cell)
			if tile == null:
				continue
			if not attack.clears.has(tile.kind):
				continue
			board.ground.erase(cell)
			cleared += 1
			events.append(_event("cleanse", "%s clears %s at %s." % [caster.display_name, GroundRules.display_name(tile.kind), cell_name(cell)]))
		if cleared == 0:
			step["kind"] = "miss"
			events.append(_event("miss", "%s finds nothing to clear." % caster.display_name))
		return step

	step["kind"] = "ground"
	events.append(_event("cast", "%s uses %s." % [caster.display_name, attack.display_name]))
	for cell in cells:
		_lay(cell, attack.ground, caster.side, events)
	var power := effective_power(attack, card.cell())
	if power > 0:
		var seen := {}
		for cell in cells:
			var target: Variant = board.target_at(cell.x, cell.y, cell.z)
			if target == null or seen.has(target):
				continue
			seen[target] = true
			if target.side == caster.side and not rules.friendly_fire:
				continue
			_strike(target, cell, power, caster.side, true, 0, step)
	return step


## Deals `power` to a unit or entity: guards soak it first unless `pierce`. Appends to the step.
func _strike(target: Variant, cell: Vector3i, power: int, source_side: int, pierce: bool, delay: int, step: Dictionary) -> void:
	var events: Array = step["events"]
	var hits: Array = step["hits"]
	if not target.is_alive():
		return
	var friendly: bool = target.side == source_side
	var hit := {"unit": target, "cell": cell, "type": "damage", "amount": 0, "blocked": 0, "delayed": 0, "fell": false}
	var incoming := power
	var blocked := 0 if pierce else _absorb(target.side, cell, incoming)
	incoming -= blocked
	var dealt := 0
	if target is CombatUnit:
		dealt = _damage_unit(target, incoming, events, false)
	else:
		dealt = _damage_entity(target, incoming, events, false)
	hit["amount"] = dealt
	hit["blocked"] = blocked
	if dealt == 0 and blocked > 0:
		hit["type"] = "block"
	hit["fell"] = not target.is_alive() and dealt > 0
	var note := " (friendly fire)" if friendly else ""
	var text := "  %s takes %d damage%s (%d/%d)." % [target.display_name, dealt, note, target.hp, target.max_hp]
	if blocked > 0:
		text = "  %s blocks %d, takes %d damage%s (%d/%d)." % [target.display_name, blocked, dealt, note, target.hp, target.max_hp]
	events.append(_event("damage", text))
	if hit["fell"]:
		events.append(_event("down", "  %s %s." % [target.display_name, "falls" if target is CombatUnit else "is destroyed"]))
		if target is CombatUnit:
			_unit_down(target, events)

	if delay > 0 and target is CombatUnit and target.is_alive() and not friendly:
		for other in _pending:
			if other.caster == target:
				other.initiative -= delay
				hit["delayed"] = delay
		if hit["delayed"] > 0:
			events.append(_event("delay", "  %s's remaining cards are delayed by %d." % [target.display_name, delay]))
	hits.append(hit)


## Applies damage to a character (Marked characters take extra). Returns what was dealt.
## `announce` adds the fall and corpse events itself; _strike does that on its own.
func _damage_unit(unit: CombatUnit, amount: int, events: Array, announce: bool = true) -> int:
	if amount > 0 and unit.marked:
		amount += GroundRules.MARK_BONUS
	var dealt := mini(amount, unit.hp)
	unit.hp -= dealt
	if announce and dealt > 0 and unit.hp == 0:
		events.append(_event("down", "  %s falls." % unit.display_name))
		_unit_down(unit, events)
	return dealt


func _damage_entity(entity: CombatEntity, amount: int, events: Array, announce: bool = true) -> int:
	var dealt := mini(amount, entity.hp)
	entity.hp -= dealt
	if entity.hp == 0 and dealt > 0:
		board.entities.erase(entity.cell)
		if announce:
			events.append(_event("down", "  %s is destroyed." % entity.display_name))
	return dealt


## A character fell: its cell keeps a corpse for a while and its familiars vanish.
func _unit_down(unit: CombatUnit, events: Array) -> void:
	var own_cards := board.cards_of(unit)
	own_cards.sort_custom(func(a: PlacedCard, b: PlacedCard) -> bool: return a.sequence < b.sequence)
	if not own_cards.is_empty():
		var cell := own_cards[0].cell()
		if not board.entities.has(cell):
			board.entities[cell] = CombatEntity.new(Enums.EntityKind.CORPSE, cell, unit)
			events.append(_event("corpse", "  %s leaves a corpse at %s." % [unit.display_name, cell_name(cell)]))
	for cell in CombatBoard.sorted_cells(board.entities):
		var entity: CombatEntity = board.entities[cell]
		if entity.owner == unit and EntityRules.is_familiar(entity.kind):
			board.entities.erase(cell)
			events.append(_event("vanish", "  %s vanishes with %s." % [entity.display_name, unit.display_name]))


## Lets active guards on the target's side soak damage aimed at `cell`. Returns the amount blocked.
func _absorb(target_side: int, cell: Vector3i, amount: int) -> int:
	var blocked := 0
	for guard in _guards:
		if guard["side"] != target_side or not guard["owner"].is_alive():
			continue
		if guard["slot"] != cell.z or cell.y < guard["lane"]:
			continue
		var soak := mini(guard["remaining"], amount - blocked)
		guard["remaining"] -= soak
		blocked += soak
	return blocked


# --- Ground ---------------------------------------------------------------------------------

## Lays ground on a cell and plays out the reaction with whatever is already there.
func _lay(cell: Vector3i, kind: int, owner_side: int, events: Array) -> void:
	var tile := board.ground_at(cell)
	var existing := tile.kind if tile != null else Enums.Ground.NONE
	var result := kind
	var where := cell_name(cell)
	match kind:
		Enums.Ground.OIL:
			if existing == Enums.Ground.FIRE or existing == Enums.Ground.WATER or GroundRules.is_trap(existing):
				return
			events.append(_event("ground", "  Oil spreads over %s." % where))
		Enums.Ground.FIRE:
			if existing == Enums.Ground.WATER:
				result = Enums.Ground.HAZE
				events.append(_event("ground", "  Fire meets water: steam rises at %s." % where))
			elif GroundRules.is_fuel(existing):
				events.append(_event("ground", "  The %s at %s catches fire." % [GroundRules.display_name(existing).to_lower(), where]))
			elif GroundRules.burns_away(existing):
				events.append(_event("ground", "  Fire burns away the %s at %s." % [GroundRules.display_name(existing), where]))
			elif GroundRules.is_trap(existing):
				return  # stone and fuse are not hurt by a flame
			else:
				events.append(_event("ground", "  Fire breaks out at %s." % where))
		Enums.Ground.WATER:
			if existing == Enums.Ground.FIRE:
				result = Enums.Ground.HAZE
				events.append(_event("ground", "  Water douses the fire: steam rises at %s." % where))
			elif existing == Enums.Ground.FLAME_TRAP:
				events.append(_event("ground", "  Water douses the Flame Trap at %s." % where))
			elif GroundRules.is_trap(existing):
				return  # a pit, a cord and a net do not mind rain
			else:
				events.append(_event("ground", "  Water pools at %s." % where))
		Enums.Ground.HAZE:
			if existing != Enums.Ground.NONE and existing != Enums.Ground.HAZE:
				return
			events.append(_event("ground", "  Haze settles over %s." % where))
	board.ground[cell] = GroundTile.new(result, owner_side)


# --- Upkeep ---------------------------------------------------------------------------------

## Ticks fuses, spreads fire, burns whatever stands in it, lets familiars act and expires things.
## Returns steps shaped like resolve_next() results (without a card) so they can be played back.
func run_upkeep() -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	_upkeep_fuses(steps)
	_upkeep_spread(steps)
	_upkeep_burn(steps)
	_upkeep_familiars(steps)
	_upkeep_expire(steps)
	# Guards last until the round ends, and Upkeep is the end of the round.
	_guards.clear()
	return steps


func _upkeep_step(kind: String, origin: Vector3i = Enums.NO_CELL) -> Dictionary:
	var step := _new_step(null, kind)
	step["origin"] = origin
	return step


func _upkeep_fuses(steps: Array) -> void:
	for cell in CombatBoard.sorted_cells(board.ground):
		var tile: GroundTile = board.ground[cell]
		if tile.kind != Enums.Ground.FLAME_TRAP:
			continue
		tile.turns_left -= 1
		var step := _upkeep_step("fuse", cell)
		step["cells"] = [cell]
		if tile.turns_left > 0:
			step["events"].append(_event("fuse", "The Flame Trap at %s ticks: %d round left." % [cell_name(cell), tile.turns_left]))
		else:
			board.ground.erase(cell)
			step["kind"] = "detonate"
			var area := CombatBoard.shape_cells(cell, Enums.Shape.CROSS)
			step["cells"] = area
			step["events"].append(_event("detonate", "The Flame Trap at %s detonates!" % cell_name(cell)))
			for target in area:
				_lay(target, Enums.Ground.FIRE, tile.owner_side, step["events"])
		steps.append(step)


func _upkeep_spread(steps: Array) -> void:
	var frontier: Array[Vector3i] = []
	for cell in CombatBoard.sorted_cells(board.ground):
		if board.ground[cell].kind == Enums.Ground.FIRE:
			frontier.append(cell)
	var step := _upkeep_step("spread")
	while not frontier.is_empty():
		var next: Array[Vector3i] = []
		for cell in frontier:
			for neighbour in CombatBoard.cross_neighbours(cell):
				var tile := board.ground_at(neighbour)
				if tile != null and GroundRules.is_fuel(tile.kind):
					step["cells"].append(neighbour)
					step["events"].append(_event("ground", "Fire spreads to the %s at %s." % [GroundRules.display_name(tile.kind).to_lower(), cell_name(neighbour)]))
					board.ground[neighbour] = GroundTile.new(Enums.Ground.FIRE, tile.owner_side)
					next.append(neighbour)
		frontier = next
	if not step["events"].is_empty():
		steps.append(step)


func _upkeep_burn(steps: Array) -> void:
	var step := _upkeep_step("burn")
	var burned := {}
	for cell in CombatBoard.sorted_cells(board.ground):
		if board.ground[cell].kind != Enums.Ground.FIRE:
			continue
		step["cells"].append(cell)
		var target: Variant = board.target_at(cell.x, cell.y, cell.z)
		if target == null or burned.has(target):
			continue
		burned[target] = true
		var before_cards: Array = step["events"]
		before_cards.append(_event("burn", "Fire burns at %s." % cell_name(cell)))
		_strike(target, cell, GroundRules.FIRE_DAMAGE, -1, true, 0, step)
	if not step["cells"].is_empty() and not step["hits"].is_empty():
		steps.append(step)


func _upkeep_familiars(steps: Array) -> void:
	for spark in board.entities_of_kind(Enums.EntityKind.SPARK):
		if not spark.is_alive() or not board.entities.has(spark.cell):
			continue
		var target_cell := PatternResolver.closest_cell(board, 1 - spark.side, spark.cell.z)
		var target: Variant = board.target_at(target_cell.x, target_cell.y, target_cell.z)
		var step := _upkeep_step("familiar", spark.cell)
		step["cells"] = [target_cell]
		if target == null:
			continue
		step["events"].append(_event("cast", "%s strikes." % spark.display_name))
		_strike(target, target_cell, EntityRules.SPARK_DAMAGE, spark.side, true, 0, step)
		steps.append(step)


func _upkeep_expire(steps: Array) -> void:
	var step := _upkeep_step("expire")
	for cell in CombatBoard.sorted_cells(board.ground):
		var tile: GroundTile = board.ground[cell]
		if tile.kind == Enums.Ground.FLAME_TRAP or tile.turns_left < 0:
			continue
		tile.turns_left -= 1
		if tile.turns_left <= 0:
			board.ground.erase(cell)
			if GroundRules.is_trap(tile.kind):
				step["events"].append(_event("expire", "The %s at %s fades." % [GroundRules.display_name(tile.kind), cell_name(cell)]))
	for cell in CombatBoard.sorted_cells(board.entities):
		var entity: CombatEntity = board.entities[cell]
		if entity.turns_left < 0:
			continue
		entity.turns_left -= 1
		if entity.turns_left <= 0:
			board.entities.erase(cell)
			if entity.kind != Enums.EntityKind.CORPSE:
				step["events"].append(_event("expire", "The %s at %s fades." % [entity.display_name, cell_name(cell)]))
	if not step["events"].is_empty():
		steps.append(step)


## Cells that will burn at the next Upkeep, as {cell: damage}. Looks ahead through fuses and spreading.
func upkeep_hazard() -> Dictionary:
	var sim := clone()
	var scratch: Array = []
	sim._upkeep_fuses(scratch)
	sim._upkeep_spread(scratch)
	var hazard := {}
	for cell in sim.board.ground:
		if sim.board.ground[cell].kind == Enums.Ground.FIRE:
			hazard[cell] = GroundRules.FIRE_DAMAGE
	return hazard


# --- Copying --------------------------------------------------------------------------------

func unit_by_id(id: int) -> CombatUnit:
	for unit in board.units:
		if unit.id == id:
			return unit
	return null


## A deep copy of the whole fight, for looking ahead without touching the real one.
func clone() -> CombatEngine:
	var copy := CombatEngine.new(rules)
	copy.round_number = round_number
	copy.resolving = resolving
	copy.current_side = current_side
	copy.starting_side = starting_side
	copy.enforce_turns = false
	copy._counts = _counts.duplicate(true)
	copy._used = _used.duplicate(true)
	copy._sequence = _sequence
	copy._played = _played.duplicate()
	copy._passed = _passed.duplicate()

	var unit_map := {}
	for unit in board.units:
		var twin := CombatUnit.new(unit.id, unit.display_name, unit.side, unit.class_data, unit.max_hp)
		twin.hp = unit.hp
		twin.marked = unit.marked
		twin.attacks = unit.attacks
		unit_map[unit] = twin
		copy.board.units.append(twin)

	var card_map := {}
	for cell in board.cards:
		var card: PlacedCard = board.cards[cell]
		var twin := card.copy(unit_map[card.caster])
		card_map[card] = twin
		copy.board.cards[cell] = twin
	for card in _pending:
		copy._pending.append(card_map[card])

	var owner_map := {}
	for cell in board.entities:
		var entity: CombatEntity = board.entities[cell]
		var twin := CombatEntity.new(entity.kind, entity.cell, unit_map.get(entity.owner, null))
		twin.hp = entity.hp
		twin.turns_left = entity.turns_left
		owner_map[entity] = twin
		copy.board.entities[cell] = twin
	for cell in board.ground:
		copy.board.ground[cell] = board.ground[cell].copy()

	for guard in _guards:
		var owner: Variant = guard["owner"]
		var mapped: Variant = unit_map.get(owner, owner_map.get(owner, owner))
		copy._guards.append({"owner": mapped, "side": guard["side"], "lane": guard["lane"], "slot": guard["slot"], "remaining": guard["remaining"]})
	return copy


# --- Helpers --------------------------------------------------------------------------------

static func cell_name(cell: Vector3i) -> String:
	return "%s %s %d" % ["your" if cell.x == 0 else "enemy", Enums.LANE_NAMES[cell.y], cell.z + 1]


func _event(type: String, text: String) -> Dictionary:
	return {"type": type, "text": text}
