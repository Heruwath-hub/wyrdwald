class_name WorldParams
extends RefCounted
## Tunable numbers for world generation. Defaults match the current design draft.

## Land size, given as the radius of a hex map with about as many land hexes. The land sits in a
## rectangle of random proportions that is larger than the land itself.
var radius: int = 28
var bounds_aspect_min: float = 0.72
var bounds_aspect_max: float = 1.5
## Share of the bounds that becomes land.
var land_fraction: float = 0.38
## Land hexes as a share of a hex map with `radius`.
var land_scale: float = 0.72
## A straight stretch of coast along one hex axis may not be longer than this.
var max_straight_coast: int = 6
## No river hex touches more than this many other river hexes.
var river_max_neighbors: int = 2
## Fish at sea sit at most this many hexes from the shore.
var sea_fish_max_shore: int = 2
## Share of those shore sea hexes that hold a node (fish).
var sea_node_share: float = 0.045
## NPC settlements keep this many hexes between their centres.
var npc_settlement_spacing: int = 7
## Rings a settlement can reach (design bible 5.1). Settlements need food and a material here.
var settlement_range: int = 2
## A start needs food (fresh water counts) within this many AP (two days at 4 AP).
var start_supply_ap: int = 8
## ...and the nearest NPC settlement within four days, but not on top of the start.
var start_settlement_min_ap: int = 4
var start_settlement_max_ap: int = 16
## One biome crossing takes about a week at 4 AP.
var crossing_target_ap: int = 28
var crossing_min_ap: int = 18
var crossing_max_ap: int = 46
## Biomes count as neighbours only when their border is at least this many hex pairs long.
var min_border_pairs: int = 3
## Plainlands and Wyrdwood must border at least this many tier 2 biomes.
var min_tier2_neighbors: int = 1
## A spring needs this many hexes between it and the sea.
var spring_min_coast: int = 3
## A river is at least this many hexes long, counted from its source to a confluence, lake or sea.
var river_min_length: int = 2
## Where a river enters a lake and another leaves it, the two end hexes keep this distance.
var lake_min_gap: int = 2
## A lake keeps this many hexes from the sea.
var lake_min_coast: int = 2
## NPC settlements keep this many hexes from the border of their biome.
var settlement_border_distance: int = 2
## ...and this many hexes from the sea (0 = coast), so settlements do not hug the shore.
var settlement_coast_distance: int = 3
## Extra rivers and lakes are generated and the ones that break a rule are removed again.
var river_oversample: float = 1.8
## A biome with NPC settlements has at least this many hexes two or more steps from its border.
var min_settlement_interior: int = 90
var lake_oversample: float = 3.0
var max_attempts: int = 24
## What an NPC settlement can reach inside its 2 rings. Food slots are food nodes plus one for
## fresh water when a river is in reach; materials are nodes.
var settlement_food_min: int = 2
var settlement_food_max: int = 3
var settlement_material_min: int = 2
var settlement_material_max: int = 3
## A player settlement needs this many hexes between it and an NPC settlement.
var player_npc_distance: int = 3
## What a node is worth in a build site's score, by its tier (food and materials alike).
var material_tier_value: Array[float] = [0.0, 1.0, 2.0, 3.0]
## A resource kind's further slots add this share of the first slot, halving with each slot, so
## several of one kind are worth little and variety is worth the most.
var slot_bonus: float = 0.4
## Morale: extra value for each food kind beyond the first, weighted by tier and not capped.
var food_variety_bonus: float = 0.5
## Tier 2/3 food nodes of a biome as a share of its signature material budget.
var signature_food_share: float = 0.5
## A start needs this many food slots (food nodes, fresh water as one) in reach.
var start_food_slots_min: int = 2
