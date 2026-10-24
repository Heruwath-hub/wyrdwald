class_name EntityRules
extends RefCounted
## Static facts about every kind of entity (an object that fills a cell instead of a card).

const SPARK_DAMAGE := 4
const WARDEN_GUARD := 6
const CORPSE_DURATION := 3


static func display_name(kind: int) -> String:
	match kind:
		Enums.EntityKind.CORPSE:
			return "Corpse"
		Enums.EntityKind.WAR_TOTEM:
			return "War Totem"
		Enums.EntityKind.HEX_TOTEM:
			return "Hex Totem"
		Enums.EntityKind.WARDEN:
			return "Warden"
		Enums.EntityKind.SPARK:
			return "Spark"
	return ""


static func describe(kind: int) -> String:
	match kind:
		Enums.EntityKind.CORPSE:
			return "Blocks the cell until it decays. Cannot be attacked."
		Enums.EntityKind.WAR_TOTEM:
			return "Cards in the cells next to it deal 20% more. Lasts 3 rounds."
		Enums.EntityKind.HEX_TOTEM:
			return "Cards in the cells next to it deal 20% less. Lasts 3 rounds."
		Enums.EntityKind.WARDEN:
			return "A familiar. Blocks %d damage for its cell and the cells behind it each round. Vanishes with its owner." % WARDEN_GUARD
		Enums.EntityKind.SPARK:
			return "A familiar. Hits the nearest enemy for %d each Upkeep. Vanishes with its owner." % SPARK_DAMAGE
	return ""


static func max_hp(kind: int) -> int:
	match kind:
		Enums.EntityKind.WAR_TOTEM, Enums.EntityKind.HEX_TOTEM:
			return 8
		Enums.EntityKind.WARDEN:
			return 14
		Enums.EntityKind.SPARK:
			return 6
	return 0


## Upkeeps the entity stays; -1 lasts until killed (familiars also end with their owner).
static func duration(kind: int) -> int:
	match kind:
		Enums.EntityKind.CORPSE:
			return CORPSE_DURATION
		Enums.EntityKind.WAR_TOTEM, Enums.EntityKind.HEX_TOTEM:
			return 3
	return -1


## Corpses only block a cell. Everything else can be attacked.
static func targetable(kind: int) -> bool:
	return kind != Enums.EntityKind.CORPSE and kind != Enums.EntityKind.NONE


static func is_familiar(kind: int) -> bool:
	return kind == Enums.EntityKind.WARDEN or kind == Enums.EntityKind.SPARK


## Percent change to the power of cards standing next to the entity.
static func aura_percent(kind: int) -> int:
	match kind:
		Enums.EntityKind.WAR_TOTEM:
			return 20
		Enums.EntityKind.HEX_TOTEM:
			return -20
	return 0
