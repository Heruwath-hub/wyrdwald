class_name LocationData
extends Resource
## A pre-placed location (ruin, shrine, lair...). Locations placed at generation take the danger
## floor of their biome and keep it unless a runtime event changes it.

@export var id: String = ""
@export var display_name: String = ""
@export var terrains: PackedStringArray = PackedStringArray()
@export var biomes: PackedStringArray = PackedStringArray()

## Locations per 100 eligible hexes.
@export_range(0.0, 20.0) var density: float = 1.0

## Minimum distance in hexes between two locations of this kind.
@export_range(1, 12) var spacing: int = 3

@export var color: Color = Color.WHITE
