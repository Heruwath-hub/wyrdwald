extends Node
## Drives the combat screen like a player would and saves screenshots. Run with a display:
##   xvfb-run godot --path . res://tests/ui_smoke.tscn
## Prints PASS/FAIL lines and quits.

var _fail := 0


func _check(ok: bool, text: String) -> void:
	print(("PASS " if ok else "FAIL ") + text)
	if not ok:
		_fail += 1


func _frames(n: int = 4) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _frames()
	get_viewport().get_texture().get_image().save_png("res://%s.png" % name)


func _ready() -> void:
	var screen = load("res://scenes/combat/combat_screen.tscn").instantiate()
	add_child(screen)
	screen.rules.first_side = 0
	screen.rules.biome = 2
	screen._skip = true
	while screen._enemy_acting or screen._playing:
		await get_tree().process_frame
	screen._new_battle()
	await _frames(6)
	var e: CombatEngine = screen.engine
	_check(e.current_side == 0 and not e.board.ground.is_empty(), "battle starts on the player's turn with Plainlands grass")

	var isolde: CombatUnit = null
	for u in e.board.living_units(0):
		if u.class_data.id == "hunter":
			isolde = u
	var trap := ContentDB.get_attack("spike_pit")
	screen._on_hand_pressed(isolde)
	screen._on_attack_pressed(trap)
	screen._on_cell_pressed(Vector3i(0, isolde.lane, 2))
	_check(screen._pending_slot == 2 and not screen._aim_cells.is_empty(), "placing an aimed card asks for a target cell")
	screen._on_cell_hovered(Vector3i(1, 1, 3))
	await _shot("shot_aim")
	screen._step_back()
	_check(screen._pending_slot == -1 and screen._selected_attack == trap, "Esc steps back from the aim stage to the card stage")
	screen._step_back()
	_check(screen._selected_attack == null and screen._selected_unit == isolde, "Esc again steps back to the character stage")
	screen._on_attack_pressed(trap)
	screen._on_cell_pressed(Vector3i(0, isolde.lane, 2))
	var pit_cell := Enums.NO_CELL
	for cell in e.aim_cells(isolde, trap, 2):
		if cell.x == 1 and e.board.ground_kind(cell) == Enums.Ground.NONE:
			pit_cell = cell
			break
	screen._on_cell_pressed(pit_cell)
	_check(e.board.ground_kind(pit_cell) == Enums.Ground.SPIKE_PIT, "the Spike Pit was set on the enemy cell")
	while screen._enemy_acting:
		await get_tree().process_frame
	await _shot("shot_after_trap")

	# A lane attack asks for a lane, and a Melee character may only pick the front one.
	var brann: CombatUnit = null
	for u in e.board.living_units(0):
		if u.class_data.id == "warrior":
			brann = u
	var sweep := ContentDB.get_attack("sweeping_strike")
	screen._on_hand_pressed(brann)
	screen._on_attack_pressed(sweep)
	screen._on_cell_pressed(Vector3i(0, brann.lane, e.free_slots(brann)[0]))
	_check(screen._pending_slot >= 0 and screen._aim_cells.size() == Enums.SLOTS_PER_LANE, "a lane attack offers only the lane a Melee character reaches")
	screen._on_cell_hovered(Vector3i(1, 0, 2))
	await _shot("shot_lane_pick")
	screen._on_cell_pressed(Vector3i(1, 1, 2))
	_check(screen._pending_slot >= 0, "an out-of-reach lane is refused and the pick stays open")
	screen._on_cell_pressed(Vector3i(1, 0, 2))
	_check(screen._pending_slot < 0 and e.board.cards_of(brann).size() == 1 and e.board.cards_of(brann)[0].aim.y == 0, "picking the front lane places the card")
	while screen._enemy_acting:
		await get_tree().process_frame

	# Let the enemy and the player alternate through placement with simple greedy choices.
	var guard := 0
	while not e.placement_done() and guard < 30:
		guard += 1
		if e.current_side == 0:
			var placed := false
			for u in e.board.living_units(0):
				if not e.can_place_more(u):
					continue
				for a in u.attacks:
					if e.attack_used(u, a) or e.needs_aim(a):
						continue
					screen._on_hand_pressed(u)
					screen._on_attack_pressed(a)
					var slot := e.free_slots(u)[0]
					screen._on_cell_pressed(Vector3i(0, u.lane, slot))
					if screen._confirm_slot >= 0:
						screen._on_cell_pressed(Vector3i(0, u.lane, slot))
					placed = true
					break
				if placed:
					break
			if not placed:
				screen._on_pass_pressed()
		await _frames(2)
		while screen._enemy_acting:
			await get_tree().process_frame
	_check(e.placement_done(), "placement finishes")
	await _shot("shot_placed")
	screen._skip = false
	screen._fast = true
	screen._on_resolve_pressed()
	await get_tree().create_timer(0.4).timeout
	await _shot("shot_resolving")
	screen._skip = true
	while screen._playing:
		await get_tree().process_frame
	_check(screen._resolved, "the round resolves including Upkeep")
	await _shot("shot_resolved")
	if not screen._game_over:
		screen._on_resolve_pressed()
		await _frames(6)
		while screen._enemy_acting:
			await get_tree().process_frame
		_check(e.round_number == 2, "a second round starts")
		await _shot("shot_round2")
	print("failures: %d" % _fail)
	get_tree().quit(_fail)
