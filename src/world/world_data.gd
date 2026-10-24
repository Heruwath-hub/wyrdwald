class_name WorldData
extends RefCounted
## The finished world: one record per land hex, plus settlements and start sites.
## Everything is plain data; no scene, no node.

const NONE := -1

var seed_value: int = 0
var version: String = ""
var attempt: int = 0
var radius: int = 0
## Half the width and depth of the bounds in world units (the map is a rectangle).
var half_extent: Vector2 = Vector2.ZERO
var issues: PackedStringArray = PackedStringArray()
var stats: Dictionary = {}

var coords: Array[Vector2i] = []
var index: Dictionary = {}                      # Vector2i -> int
var neighbors: Array[PackedInt32Array] = []     # land neighbours of each hex

var terrain: PackedStringArray = PackedStringArray()
var biome: PackedStringArray = PackedStringArray()
var elevation: PackedFloat32Array = PackedFloat32Array()
var moisture: PackedFloat32Array = PackedFloat32Array()
var relief: PackedFloat32Array = PackedFloat32Array()    # high along mountain ridges
var ap: PackedInt32Array = PackedInt32Array()   # AP to enter, -1 = impassable
var node: PackedStringArray = PackedStringArray()       # resource node id or ""
var location: PackedStringArray = PackedStringArray()   # location id or ""
var location_danger: PackedInt32Array = PackedInt32Array()

## hex index -> {"id": String, "biome": String, "race": String}
var settlements: Dictionary = {}
## biome id -> hex index
var starts: Dictionary = {}

# Hydrology, kept for debugging and for the springs.
var flow_to: PackedInt32Array = PackedInt32Array()
## 1 = river head that needs a spring, 2 = river head fed by a lake, 0 = not a head.
var river_source: PackedByteArray = PackedByteArray()
var sea_node: Dictionary = {}                            # Vector2i of a shore sea hex -> node id (fish)
var coast_dist: PackedInt32Array = PackedInt32Array()   # hexes to the sea, 0 on the coast


func size() -> int:
	return coords.size()


func has_coord(c: Vector2i) -> bool:
	return index.has(c)


func idx(c: Vector2i) -> int:
	return int(index.get(c, NONE))


func passable(i: int) -> bool:
	return ap[i] >= 0


func add_hex(c: Vector2i) -> int:
	var i := coords.size()
	coords.append(c)
	index[c] = i
	return i


func allocate() -> void:
	var n := coords.size()
	terrain.resize(n)
	biome.resize(n)
	elevation.resize(n)
	moisture.resize(n)
	relief.resize(n)
	ap.resize(n)
	node.resize(n)
	location.resize(n)
	location_danger.resize(n)
	flow_to.resize(n)
	river_source.resize(n)
	coast_dist.resize(n)
	for i in n:
		flow_to[i] = NONE


func build_neighbors() -> void:
	neighbors.clear()
	for i in coords.size():
		var list := PackedInt32Array()
		for d in HexGrid.DIRS:
			var j := idx(coords[i] + d)
			if j != NONE:
				list.append(j)
		neighbors.append(list)


## Land hexes within `r` of hex `i`, including `i`.
func disc_indices(i: int, r: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in HexGrid.disc(coords[i], r):
		var j := idx(c)
		if j != NONE:
			out.append(j)
	return out


func biome_hexes(biome_id: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in coords.size():
		if biome[i] == biome_id:
			out.append(i)
	return out
