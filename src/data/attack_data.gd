class_name AttackData
extends Resource
## An attack card. The pattern decides which slots it hits; the caster's class decides its lane.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export var pattern: Enums.Pattern = Enums.Pattern.SINGLE
@export var target_side: Enums.TargetSide = Enums.TargetSide.ENEMY

## Damage dealt to enemies, or health restored when target_side is ALLY.
@export var power: int = 5

## Higher resolves earlier. Wide patterns are meant to be slow.
@export var initiative: int = 5

## Guard cards deal no damage. When resolved, the caster blocks up to this much damage dealt to
## its own cell and to every cell behind it in the same slot column, until the round ends.
@export var guard: int = 0

## Initiative removed from every pending card of each character this attack hits.
@export var delay: int = 0


## --- Aimed cards -----------------------------------------------------------------------------
## Cards with a ground, an entity or a list of ground to clear are pointed at a cell once the caster is placed.
## Traps and entities are set the moment the card is placed; everything else resolves in
## initiative order like an attack.

@export var aim_side: Enums.AimSide = Enums.AimSide.ENEMY
@export var shape: Enums.Shape = Enums.Shape.CELL

## How deep into the enemy side the card can be pointed, counted from the enemy front lane:
## 1 = Melee lane only (no reach), 2 = Melee and Ranged lanes, 3 = every lane. It applies to lane
## attacks and to aimed cards pointed at enemy cells, never to cards pointed at your own side.
@export_range(1, 3) var lane_reach: int = 1

## Furthest slot distance between the caster's slot and the aimed cell. Large means anywhere.
@export var reach: int = 99

## Ground laid on every cell of the footprint. A trap is a single cell.
@export var ground: Enums.Ground = Enums.Ground.NONE

## Entity set in the aimed cell.
@export var entity: Enums.EntityKind = Enums.EntityKind.NONE

## Kinds of ground this card removes from its footprint (Enums.Ground values). Anything else
## under the footprint is left alone, so every removal card answers specific ground only.
@export var clears: PackedInt32Array = PackedInt32Array()

## Initiative added to every pending card of the caster's side.
@export var quicken: int = 0


func is_aimed() -> bool:
	return ground != Enums.Ground.NONE or entity != Enums.EntityKind.NONE or not clears.is_empty()


## Lane attacks (damage or healing) are pointed at one lane, chosen when the card is placed.
func picks_lane() -> bool:
	return pattern == Enums.Pattern.LANE and guard == 0


## Set cards take effect when placed instead of when they resolve.
func is_set() -> bool:
	return entity != Enums.EntityKind.NONE or GroundRules.is_trap(ground)
