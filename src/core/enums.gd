class_name Enums
extends RefCounted
## Shared enums and board constants. Never instantiated; access as Enums.Lane.MELEE etc.

enum Attribute { MIGHT, FINESSE, INSIGHT }

## Lanes measure distance from the enemy: Melee is closest, Magic is farthest.
enum Lane { MELEE, RANGED, MAGIC }

enum Pattern { SINGLE, LANE, PIERCE, COLUMN, ALL }

## Ground lies under a cell. One piece per cell. Traps are ground that waits for a card.
enum Ground { NONE, OIL, GRASS, FIRE, WATER, HAZE, SPIKE_PIT, TRIPWIRE, SNARE, FLAME_TRAP }

## Objects that occupy a cell instead of a card.
enum EntityKind { NONE, CORPSE, WAR_TOTEM, HEX_TOTEM, WARDEN, SPARK }

## Which side of the board an aimed card may be pointed at.
enum AimSide { ENEMY, OWN, ANY }

## Footprint of an aimed card around the cell it is pointed at.
enum Shape { CELL, CROSS, COLUMN }

enum Biome { NONE, PLAINLANDS, WETLANDS }

## Which side of the board a card targets.
enum TargetSide { ENEMY, ALLY }

const LANE_NAMES := ["Melee", "Ranged", "Magic"]
const NO_CELL := Vector3i(-1, -1, -1)
const LANE_COUNT := 3
const SLOTS_PER_LANE := 5


## Every attribute owns exactly one combat lane.
static func lane_for_attribute(attribute: Attribute) -> Lane:
	match attribute:
		Attribute.MIGHT:
			return Lane.MELEE
		Attribute.FINESSE:
			return Lane.RANGED
		_:
			return Lane.MAGIC
