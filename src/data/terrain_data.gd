class_name TerrainData
extends Resource
## A terrain a map hex can have. The terrain alone decides what the hex costs to enter.

@export var id: String = ""
@export var display_name: String = ""

## Action points a party pays to enter a hex of this terrain. Ignored when not passable.
@export_range(1, 6) var ap_cost: int = 1

## Impassable terrain (mountains, lakes) cannot be entered at all.
@export var passable: bool = true

## Placeholder colour used until the terrain has art.
@export var color: Color = Color.WHITE

## Height of the placeholder tile in map units.
@export_range(0.05, 2.0) var height: float = 0.3

## Battlefield ground a fight on this terrain starts with. Read by the combat setup.
@export var battle_ground: String = ""
