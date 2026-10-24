class_name BiomeSetup
extends RefCounted
## Ground the battlefield starts with. Terrain is mirrored across the two sides so neither
## side is favoured, and it belongs to nobody (owner_side -1).
##   Plainlands  dry grass: fuel that fire spreads through.
##   Wetlands    standing water: puts fire out and keeps oil off.
##   None        bare ground.

const TERRAIN_CELLS := 4


static func name_of(biome: int) -> String:
	match biome:
		Enums.Biome.PLAINLANDS:
			return "Plainlands"
		Enums.Biome.WETLANDS:
			return "Wetlands"
	return "Bare ground"


## `biome` -1 picks one of Plainlands, Wetlands or bare ground at random. Returns the biome used.
static func apply(engine: CombatEngine, biome: int, rng: RandomNumberGenerator) -> int:
	if biome < 0:
		biome = rng.randi() % 3
	var kind := Enums.Ground.NONE
	match biome:
		Enums.Biome.PLAINLANDS:
			kind = Enums.Ground.GRASS
		Enums.Biome.WETLANDS:
			kind = Enums.Ground.WATER
	if kind == Enums.Ground.NONE:
		return biome
	var chosen := {}
	while chosen.size() < TERRAIN_CELLS:
		chosen[Vector2i(rng.randi() % Enums.LANE_COUNT, rng.randi() % Enums.SLOTS_PER_LANE)] = true
	for spot in chosen:
		for side in 2:
			var tile := GroundTile.new(kind, -1)
			tile.turns_left = -1
			engine.board.ground[Vector3i(side, spot.x, spot.y)] = tile
	return biome
