class_name GroundRules
extends RefCounted
## Static facts about every kind of ground: how long it lasts, what it is made of and what it does.
## Numbers live here so they can be tuned in one place.

const SPIKE_DAMAGE := 8
const TRIPWIRE_INIT := 4
const MARK_BONUS := 2
const FIRE_DAMAGE := 4
const HAZE_INIT := 3
const FLAME_FUSE := 2


static func display_name(kind: int) -> String:
	match kind:
		Enums.Ground.OIL:
			return "Oil"
		Enums.Ground.GRASS:
			return "Dry Grass"
		Enums.Ground.FIRE:
			return "Fire"
		Enums.Ground.WATER:
			return "Water"
		Enums.Ground.HAZE:
			return "Haze"
		Enums.Ground.SPIKE_PIT:
			return "Spike Pit"
		Enums.Ground.TRIPWIRE:
			return "Tripwire"
		Enums.Ground.SNARE:
			return "Snare"
		Enums.Ground.FLAME_TRAP:
			return "Flame Trap"
	return ""


static func describe(kind: int) -> String:
	match kind:
		Enums.Ground.OIL:
			return "Fuel. Burns when touched by fire. Rain or Cleanse washes it away."
		Enums.Ground.GRASS:
			return "Fuel. Burns when touched by fire."
		Enums.Ground.FIRE:
			return "%d damage to whatever stands here each Upkeep. Spreads along fuel." % FIRE_DAMAGE
		Enums.Ground.WATER:
			return "Puts out fire (it turns to steam), washes away oil and douses a Flame Trap. Pits, cords and nets do not mind it."
		Enums.Ground.HAZE:
			return "Cards placed here lose %d initiative. Cleanse clears it." % HAZE_INIT
		Enums.Ground.SPIKE_PIT:
			return "Springs when an enemy places a card here: the caster takes %d damage. Only Stomp fills it in." % SPIKE_DAMAGE
		Enums.Ground.TRIPWIRE:
			return "Springs when an enemy places a card here: the caster is Marked (+%d damage taken) and the card loses %d initiative. Disarm or fire removes it." % [MARK_BONUS, TRIPWIRE_INIT]
		Enums.Ground.SNARE:
			return "Springs when an enemy places a card here: that card is cancelled. Disarm or fire removes it."
		Enums.Ground.FLAME_TRAP:
			return "A fuse of %d rounds. When it runs out the cell and its neighbours catch fire. Disarm it or douse it with water." % FLAME_FUSE
	return ""


## Upkeeps the ground stays; -1 lasts until something changes it.
static func duration(kind: int) -> int:
	match kind:
		Enums.Ground.OIL:
			return 4
		Enums.Ground.GRASS:
			return -1
		Enums.Ground.FIRE:
			return 2
		Enums.Ground.WATER:
			return 3
		Enums.Ground.HAZE:
			return 3
		Enums.Ground.FLAME_TRAP:
			return FLAME_FUSE
	if is_placement_trap(kind):
		return 3
	return -1


static func is_placement_trap(kind: int) -> bool:
	return kind == Enums.Ground.SPIKE_PIT or kind == Enums.Ground.TRIPWIRE or kind == Enums.Ground.SNARE


## Ground that fire destroys outright (cord and net); pits and fuses are untouched by it.
static func burns_away(kind: int) -> bool:
	return kind == Enums.Ground.TRIPWIRE or kind == Enums.Ground.SNARE


static func is_trap(kind: int) -> bool:
	return is_placement_trap(kind) or kind == Enums.Ground.FLAME_TRAP


static func is_fuel(kind: int) -> bool:
	return kind == Enums.Ground.OIL or kind == Enums.Ground.GRASS
