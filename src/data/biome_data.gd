class_name BiomeData
extends Resource
## One of the continent's biomes: how dangerous it is, how big, and what its land is made of.

@export var id: String = ""
@export var display_name: String = ""

## 1 = Plainlands, 2 = the middle biomes, 3 = Wyrdwood. Decides how the biomes may touch.
@export_range(1, 3) var tier: int = 1

## Danger runs on a 1-10 scale. Content placed at generation sits at the floor; the cap is the
## most a biome can ever be made to produce. Neighbouring biomes overlap on purpose.
@export_range(1, 10) var danger_floor: int = 1
@export_range(1, 10) var danger_cap: int = 5

## Share of the continent's land this biome takes. All biomes together should add up to 1.
@export_range(0.05, 0.6) var region_share: float = 0.2

## Terrain id -> percent of this biome's hexes. River and lake entries set how much water the
## hydrology stage aims for; the rest is dealt out by the terrain stage.
@export var terrain_weights: Dictionary = {}

## NPC settlements per race native to this biome. 0 = no NPC settlements (Wyrdwood).
@export_range(0, 6) var settlements_per_race: int = 2

## Players may begin a run here. Wyrdwood is excluded.
@export var start_allowed: bool = true

## Where the biome prefers to sit: +1 on high ground, -1 on low ground, 0 anywhere.
@export_range(-1.0, 1.0) var elevation_bias: float = 0.0

## The terrain that fills most flat ground here and is drawn as a bare tile (grass, marsh).
## Every other terrain is drawn with a model standing on the tile. Empty = every terrain gets one.
@export var plain_terrain: String = ""

## Resource budget: nodes per 100 walkable hexes of this biome, so a biome full of mountains is not
## starved. Food, tier 1 materials, and the biome's own tier 2 or 3 materials are counted apart.
@export_range(0.0, 40.0) var food_per_100: float = 10.0
@export_range(0.0, 40.0) var material_per_100: float = 12.0
@export_range(0.0, 40.0) var signature_per_100: float = 6.0

## Tile colour on the map. The colour is how a hex shows its biome.
@export var color: Color = Color.WHITE


func weight_of(terrain_id: String) -> float:
	return float(terrain_weights.get(terrain_id, 0))
