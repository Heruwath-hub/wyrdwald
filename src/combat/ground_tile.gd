class_name GroundTile
extends RefCounted
## One piece of ground under a cell.

var kind: int
var turns_left: int
## The side that laid it. Traps only spring for cards of the other side.
var owner_side: int


func _init(p_kind: int = Enums.Ground.NONE, p_owner_side: int = -1) -> void:
	kind = p_kind
	owner_side = p_owner_side
	turns_left = GroundRules.duration(p_kind)


func copy() -> GroundTile:
	var tile := GroundTile.new(kind, owner_side)
	tile.turns_left = turns_left
	return tile
