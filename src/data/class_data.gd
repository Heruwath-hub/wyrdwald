class_name ClassData
extends Resource
## A character class. The main attribute decides the combat lane.

@export var id: String = ""
@export var display_name: String = ""
@export var main_attribute: Enums.Attribute = Enums.Attribute.MIGHT
@export var secondary_attribute: Enums.Attribute = Enums.Attribute.MIGHT
@export var excelling_race_id: String = ""
@export var legendary_title: String = ""

## Ids of the AttackData cards this class can place. Resolved through ContentDB.
@export var attack_ids: PackedStringArray = PackedStringArray()


func lane() -> Enums.Lane:
	return Enums.lane_for_attribute(main_attribute)
