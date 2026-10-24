class_name RaceData
extends Resource
## A race and its natural affinity for each attribute (weights out of 10).

@export var id: String = ""
@export var display_name: String = ""
@export var native_biome: String = ""
@export var playable: bool = true

@export_group("Attribute Weights")
@export_range(0, 10) var might_weight: int = 5
@export_range(0, 10) var finesse_weight: int = 5
@export_range(0, 10) var insight_weight: int = 5


func weight_for(attribute: Enums.Attribute) -> int:
	match attribute:
		Enums.Attribute.MIGHT:
			return might_weight
		Enums.Attribute.FINESSE:
			return finesse_weight
		_:
			return insight_weight
