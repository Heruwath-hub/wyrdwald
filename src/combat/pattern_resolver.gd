class_name PatternResolver
extends RefCounted
## Derives the cells an attack covers from the slot its card sits in (Thea-style: the card
## is placed on your own side and its pattern reaches across the board).
##
## The board is one line of six lanes, indexed by distance along that line:
##   side 0:  Magic(0)  Ranged(1)  Melee(2)  |  side 1:  Melee(3)  Ranged(4)  Magic(5)
##
## Enemy attacks aim at the closest occupied target:
##   Single  the front card of the nearest occupied slot column
##           (nearest = smallest slot distance, ties go to the lower slot)
##   Lane    the lane the player chose when placing the card (see CombatEngine.lane_reachable);
##           cards placed without a choice take the nearest occupied lane the caster can reach
##   Column  the nearest occupied slot column, all three lanes
##   All     every cell of the enemy side
##   Pierce  the nearest occupied slot column through `pierce_enemy_lanes` enemy lanes, after
##           crossing the lanes in front of the caster in its own slot column
## With nothing to aim at, the attack points at the nominal cell and hits nothing.
##
## Ally attacks use the caster's own slot and lane: Single = own cell, Lane = own lane,
## Column/Pierce = own slot column, All = whole side.
## Totems, familiars and other attackable entities count as targets like characters do; the
## frontmost object of the nearest column is hit.
## Guard cards cover the caster's cell and every cell behind it in the slot column.


static func axis_index(side: int, lane: int) -> int:
	if side == 0:
		return 2 - lane
	return 3 + lane


## Returns Vector2i(side, lane) for a position on the axis.
static func lane_at_axis(index: int) -> Vector2i:
	if index <= 2:
		return Vector2i(0, 2 - index)
	return Vector2i(1, index - 3)


static func affected_cells(
	board: CombatBoard,
	caster_side: int,
	caster_lane: int,
	slot: int,
	attack: AttackData,
	rules: CombatRules,
	chosen_lane: int = -1
) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if attack.guard > 0:
		for lane in range(caster_lane, Enums.LANE_COUNT):
			cells.append(Vector3i(caster_side, lane, slot))
		return cells

	var ally := attack.target_side == Enums.TargetSide.ALLY
	var target_side := caster_side if ally else 1 - caster_side

	match attack.pattern:
		Enums.Pattern.SINGLE:
			if ally:
				cells.append(Vector3i(caster_side, caster_lane, slot))
			else:
				cells.append(_closest_cell(board, target_side, slot))
		Enums.Pattern.LANE:
			var lane := chosen_lane
			if lane < 0:
				lane = caster_lane if ally else closest_lane(board, target_side, caster_lane)
			_add_lane(cells, target_side, lane)
		Enums.Pattern.COLUMN:
			var column := slot if ally else closest_column(board, target_side, slot)
			_add_column(cells, target_side, column)
		Enums.Pattern.ALL:
			for lane in Enums.LANE_COUNT:
				_add_lane(cells, target_side, lane)
		Enums.Pattern.PIERCE:
			if ally:
				_add_column(cells, target_side, slot)
			else:
				_add_pierce(cells, board, caster_side, caster_lane, slot, rules)
	return cells


## The occupied slot column nearest to `slot`, or `slot` itself if the side has no cards.
static func closest_column(board: CombatBoard, side: int, slot: int) -> int:
	var best := -1
	var best_distance := 1000
	for candidate in Enums.SLOTS_PER_LANE:
		if not _column_occupied(board, side, candidate):
			continue
		var distance := absi(candidate - slot)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best if best >= 0 else slot


## The occupied lane nearest to `lane` (front first on ties), or `lane` itself if empty.
static func closest_lane(board: CombatBoard, side: int, lane: int) -> int:
	var best := -1
	var best_distance := 1000
	for candidate in Enums.LANE_COUNT:
		var occupied := false
		for slot in Enums.SLOTS_PER_LANE:
			if board.target_at(side, candidate, slot) != null:
				occupied = true
				break
		if not occupied:
			continue
		var distance := absi(candidate - lane)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best if best >= 0 else lane


static func _column_occupied(board: CombatBoard, side: int, slot: int) -> bool:
	for lane in Enums.LANE_COUNT:
		if board.target_at(side, lane, slot) != null:
			return true
	return false


static func closest_cell(board: CombatBoard, side: int, slot: int) -> Vector3i:
	return _closest_cell(board, side, slot)


static func _closest_cell(board: CombatBoard, side: int, slot: int) -> Vector3i:
	var column := closest_column(board, side, slot)
	for lane in Enums.LANE_COUNT:
		if board.target_at(side, lane, column) != null:
			return Vector3i(side, lane, column)
	return Vector3i(side, Enums.Lane.MELEE, column)


static func _add_lane(cells: Array[Vector3i], side: int, lane: int) -> void:
	for slot in Enums.SLOTS_PER_LANE:
		cells.append(Vector3i(side, lane, slot))


static func _add_column(cells: Array[Vector3i], side: int, slot: int) -> void:
	for lane in Enums.LANE_COUNT:
		cells.append(Vector3i(side, lane, slot))


static func _add_pierce(
	cells: Array[Vector3i], board: CombatBoard, caster_side: int, caster_lane: int, slot: int, rules: CombatRules
) -> void:
	var enemy_column := closest_column(board, 1 - caster_side, slot)
	var direction := 1 if caster_side == 0 else -1
	var start := axis_index(caster_side, caster_lane)
	var enemy_front := axis_index(1 - caster_side, Enums.Lane.MELEE)
	var depth := clampi(rules.pierce_enemy_lanes, 1, Enums.LANE_COUNT)
	var end := enemy_front + direction * (depth - 1)
	var index := start + direction
	while (index - end) * direction <= 0:
		var where := lane_at_axis(index)
		cells.append(Vector3i(where.x, where.y, slot if where.x == caster_side else enemy_column))
		index += direction
