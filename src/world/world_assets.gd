class_name WorldAssets
extends RefCounted
## Finds world art on disk and picks one variant per object.
##
## Layout: res://assets/world/<kind>/<id>/<any file>
##   kind = tiles | props | nodes | locations | settlements | party
##   id   = terrain id, node id, location id, ... (the same string ids the content uses)
## Every file in a folder is one variant. Which variant a hex gets is a hash of the world seed
## and the hex, so the same world always looks the same. Supported files: tscn, scn, glb, gltf, obj.
## Tiles are rotated in 60 degree steps (a hex looks the same turned that way), everything else
## gets any yaw. A folder with no files means "use the placeholder".

const ROOT := "res://assets/world"
const EXTENSIONS: PackedStringArray = ["tscn", "scn", "glb", "gltf", "obj"]
## How many extra props (trees, rocks) one tile may carry.
const MAX_PROPS_PER_TILE := 3

var _cache: Dictionary = {}   # "kind/id" -> PackedStringArray


## Paths of all variants for an asset, sorted. Empty if the folder is empty or missing.
func variants(kind: String, id: String) -> PackedStringArray:
	var key := kind + "/" + id
	if _cache.has(key):
		return _cache[key]
	var found := PackedStringArray()
	var dir := DirAccess.open(ROOT.path_join(kind).path_join(id))
	if dir != null:
		for file_name in dir.get_files():
			# Exported builds list imported files as '<name>.<ext>.import' or '.remap'.
			var clean := file_name.trim_suffix(".remap").trim_suffix(".import")
			if clean.get_extension().to_lower() in EXTENSIONS and not found.has(clean):
				found.append(clean)
	found.sort()
	var paths := PackedStringArray()
	for f in found:
		paths.append(ROOT.path_join(kind).path_join(id).path_join(f))
	_cache[key] = paths
	return paths


func has_art(kind: String, id: String) -> bool:
	return not variants(kind, id).is_empty()


## Variant picked for `coord`, loaded and instanced; null if there is no art.
## `salt` separates several things on one hex (a node and a location, say).
func instance(kind: String, id: String, world_seed: int, coord: Vector2i, salt: String = "") -> Node3D:
	var list := variants(kind, id)
	if list.is_empty():
		return null
	var h := WorldHash.hash2(WorldHash.sub(world_seed, kind + "/" + id + salt), coord.x, coord.y)
	var node := _load_node(list[h % list.size()])
	if node == null:
		return null
	if kind == "tiles":
		node.rotation.y = deg_to_rad(60.0 * float((h >> 8) % 6))
	else:
		node.rotation.y = TAU * float((h >> 8) & 0xFFFF) / 65536.0
	return node


## Number of props a tile carries (0..MAX_PROPS_PER_TILE), the same every time for that hex.
func prop_count(world_seed: int, coord: Vector2i, chance: float = 0.8) -> int:
	var h := WorldHash.hash2(WorldHash.sub(world_seed, "prop_count"), coord.x, coord.y)
	if WorldHash.unit(h) > chance:
		return 0
	return 1 + (h >> 4) % MAX_PROPS_PER_TILE


## A spot inside the hex for prop number `k`, as an offset from the hex centre.
func prop_offset(world_seed: int, coord: Vector2i, k: int) -> Vector2:
	var h := WorldHash.hash2(WorldHash.sub(world_seed, "prop_pos%d" % k), coord.x, coord.y)
	var angle := TAU * float(h & 0xFFFF) / 65536.0
	var dist := 0.65 * sqrt(float((h >> 16) & 0xFFFF) / 65536.0)
	return Vector2(cos(angle), sin(angle)) * dist


func _load_node(path: String) -> Node3D:
	var res: Resource = load(path)
	if res is PackedScene:
		var inst: Node = (res as PackedScene).instantiate()
		if inst is Node3D:
			return inst as Node3D
		inst.queue_free()
		return null
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res as Mesh
		return mi
	return null
