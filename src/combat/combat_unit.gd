class_name CombatUnit
extends RefCounted
## One fighter. Its lane comes from its class; it has no fixed position, because the card it
## places decides where it "stands" this round.

var id: int
var display_name: String
var side: int
var class_data: ClassData
var max_hp: int
var hp: int
var attacks: Array[AttackData] = []

## Marked characters take extra damage for the rest of the round.
var marked := false

var lane: int:
	get:
		return class_data.lane()


func _init(p_id: int, p_name: String, p_side: int, p_class: ClassData, p_max_hp: int) -> void:
	id = p_id
	display_name = p_name
	side = p_side
	class_data = p_class
	max_hp = p_max_hp
	hp = p_max_hp


func is_alive() -> bool:
	return hp > 0
