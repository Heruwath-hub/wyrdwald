class_name CombatBoard
extends RefCounted
## Holds every unit, the cards placed this round, the entities standing on the board and the
## ground under its cells. A cell is Vector3i(side, lane, slot).
##
## A cell holds a card or an entity, never both. Ground lies under either.

var units: Array[CombatUnit] = []
var cards: Dictionary = {}  ## Vector3i -> PlacedCard
var entities: Dictionary = {}  ## Vector3i -> CombatEntity
var ground: Dictionary = {}  ## Vector3i -> GroundTile


func add_unit(unit: CombatUnit) -> void:
	units.append(unit)


## Returns an empty string on success, otherwise the reason the card was rejected.
func put_card(card: PlacedCard) -> String:
	if card.slot < 0 or card.slot >= Enums.SLOTS_PER_LANE:
		return "Slot %d is outside the lane." % card.slot
	if cards.has(card.cell()):
		return "That slot already holds a card."
	if entities.has(card.cell()):
		return "That slot holds a %s." % entities[card.cell()].display_name
	cards[card.cell()] = card
	return ""


func clear_cards() -> void:
	cards.clear()


## The card in a cell, or null. Cards of fallen casters still exist but are not targets.
func card_at(side: int, lane: int, slot: int) -> PlacedCard:
	return cards.get(Vector3i(side, lane, slot), null)


## The living character whose card fills the cell, or null.
func unit_at(side: int, lane: int, slot: int) -> CombatUnit:
	var card := card_at(side, lane, slot)
	if card != null and card.caster.is_alive():
		return card.caster
	return null


func entity_at(side: int, lane: int, slot: int) -> CombatEntity:
	return entities.get(Vector3i(side, lane, slot), null)


## Whatever an attack hitting this cell would hit: a living character or an attackable entity.
func target_at(side: int, lane: int, slot: int) -> Variant:
	var unit := unit_at(side, lane, slot)
	if unit != null:
		return unit
	var entity := entity_at(side, lane, slot)
	if entity != null and entity.targetable():
		return entity
	return null


func ground_at(cell: Vector3i) -> GroundTile:
	return ground.get(cell, null)


func ground_kind(cell: Vector3i) -> int:
	var tile: GroundTile = ground.get(cell, null)
	return tile.kind if tile != null else Enums.Ground.NONE


func is_slot_free(side: int, lane: int, slot: int) -> bool:
	var cell := Vector3i(side, lane, slot)
	return not cards.has(cell) and not entities.has(cell)


func living_units(side: int) -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for unit in units:
		if unit.side == side and unit.is_alive():
			result.append(unit)
	return result


func units_in_cells(cells: Array[Vector3i]) -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for cell in cells:
		var unit := unit_at(cell.x, cell.y, cell.z)
		if unit != null and not result.has(unit):
			result.append(unit)
	return result


func cards_of(unit: CombatUnit) -> Array[PlacedCard]:
	var result: Array[PlacedCard] = []
	for card in cards.values():
		if card.caster == unit:
			result.append(card)
	return result


func remove_card(card: PlacedCard) -> void:
	cards.erase(card.cell())


func entities_of_kind(kind: int) -> Array[CombatEntity]:
	var result: Array[CombatEntity] = []
	for cell in sorted_cells(entities):
		if entities[cell].kind == kind:
			result.append(entities[cell])
	return result


## Neighbours in the same side: one lane nearer or farther, one slot left or right.
static func cross_neighbours(cell: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for step in [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1)]:
		var next: Vector3i = cell + step
		if is_valid_cell(next):
			result.append(next)
	return result


static func is_valid_cell(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.x <= 1 and cell.y >= 0 and cell.y < Enums.LANE_COUNT and cell.z >= 0 and cell.z < Enums.SLOTS_PER_LANE


## The cells an aimed card covers around `center`.
static func shape_cells(center: Vector3i, shape: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = [center]
	match shape:
		Enums.Shape.CROSS:
			result.append_array(cross_neighbours(center))
		Enums.Shape.COLUMN:
			result.clear()
			for lane in Enums.LANE_COUNT:
				result.append(Vector3i(center.x, lane, center.z))
	return result


## Dictionary keys sorted so that anything iterating the board is deterministic.
static func sorted_cells(source: Dictionary) -> Array[Vector3i]:
	var keys: Array[Vector3i] = []
	for key in source.keys():
		keys.append(key)
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		if a.y != b.y:
			return a.y < b.y
		return a.z < b.z
	)
	return keys
