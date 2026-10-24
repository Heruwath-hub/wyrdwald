class_name ResourceNodeData
extends Resource
## A resource node that can sit on a hex. Nodes are never used up. A camp (1 ring) or settlement
## (2 rings) reaches every node inside its range without standing on it.

@export var id: String = ""
@export var display_name: String = ""

## food, water or material. Settlements need food (fresh water counts) and a material in range.
@export_enum("food", "water", "material") var category: String = "material"

## Tier 1-3 for food and materials (the tiers in the design bible). Tier 2 stays in its own biome, tier 3 in Wyrdwood.
@export_range(0, 3) var tier: int = 1

## Terrain ids the node may sit on.
@export var terrains: PackedStringArray = PackedStringArray()

## Biome ids the node appears in. Empty = any biome.
@export var biomes: PackedStringArray = PackedStringArray()

## Relative weight among the nodes of the same group (food, tier 1 material, tier 2/3 material) in
## a biome. How many nodes a biome gets comes from its budget; this only splits that budget.
## Water nodes with weight 0 are placed by the hydrology stage.
@export_range(0.0, 50.0) var density: float = 3.0

## If set, a hex of this terrain must touch the node's hex (wheat grows next to a river).
@export var needs_adjacent_terrain: String = ""

## Placeholder colour on the map.
@export var color: Color = Color.WHITE
