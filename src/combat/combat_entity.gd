class_name CombatEntity
extends RefCounted
## An object standing in a cell: a totem, a familiar or a corpse. A cell holds a card or an entity.

var kind: int
var cell: Vector3i
var owner: CombatUnit = null
var hp: int
var max_hp: int
var turns_left: int

var side: int:
	get:
		return cell.x

var display_name: String:
	get:
		return EntityRules.display_name(kind)


func _init(p_kind: int, p_cell: Vector3i, p_owner: CombatUnit = null) -> void:
	kind = p_kind
	cell = p_cell
	owner = p_owner
	max_hp = EntityRules.max_hp(p_kind)
	hp = max_hp
	turns_left = EntityRules.duration(p_kind)


func is_alive() -> bool:
	return kind == Enums.EntityKind.CORPSE or hp > 0


func targetable() -> bool:
	return EntityRules.targetable(kind) and hp > 0
