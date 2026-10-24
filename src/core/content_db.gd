extends Node
## Autoload. Loads every content Resource at startup and indexes it by id.
## Content lives in res://content/<kind>/*.tres and is tuned in the inspector.

const RACES_DIR := "res://content/races"
const CLASSES_DIR := "res://content/classes"
const ATTACKS_DIR := "res://content/attacks"
const TERRAIN_DIR := "res://content/terrain"
const BIOMES_DIR := "res://content/biomes"
const NODES_DIR := "res://content/nodes"
const LOCATIONS_DIR := "res://content/locations"

var races: Dictionary = {}
var classes: Dictionary = {}
var attacks: Dictionary = {}
var terrains: Dictionary = {}
var biomes: Dictionary = {}
var nodes: Dictionary = {}
var locations: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	races = _load_dir(RACES_DIR)
	classes = _load_dir(CLASSES_DIR)
	attacks = _load_dir(ATTACKS_DIR)
	terrains = _load_dir(TERRAIN_DIR)
	biomes = _load_dir(BIOMES_DIR)
	nodes = _load_dir(NODES_DIR)
	locations = _load_dir(LOCATIONS_DIR)


func get_race(id: String) -> RaceData:
	return races.get(id) as RaceData


func get_class_data(id: String) -> ClassData:
	return classes.get(id) as ClassData


func get_attack(id: String) -> AttackData:
	return attacks.get(id) as AttackData


func get_terrain(id: String) -> TerrainData:
	return terrains.get(id) as TerrainData


func get_biome(id: String) -> BiomeData:
	return biomes.get(id) as BiomeData


func get_node_data(id: String) -> ResourceNodeData:
	return nodes.get(id) as ResourceNodeData


func get_location(id: String) -> LocationData:
	return locations.get(id) as LocationData


func attacks_for_class(class_data: ClassData) -> Array[AttackData]:
	var result: Array[AttackData] = []
	for attack_id in class_data.attack_ids:
		var attack := get_attack(attack_id)
		if attack != null:
			result.append(attack)
	return result


## Returns a list of human-readable problems; empty means the content is consistent.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	for class_data: ClassData in classes.values():
		if class_data.excelling_race_id != "" and not races.has(class_data.excelling_race_id):
			problems.append("Class '%s' references unknown race '%s'." % [class_data.id, class_data.excelling_race_id])
		for attack_id in class_data.attack_ids:
			if not attacks.has(attack_id):
				problems.append("Class '%s' references unknown attack '%s'." % [class_data.id, attack_id])
	for biome: BiomeData in biomes.values():
		for terrain_id in biome.terrain_weights:
			if not terrains.has(terrain_id):
				problems.append("Biome '%s' uses unknown terrain '%s'." % [biome.id, terrain_id])
	for node: ResourceNodeData in nodes.values():
		for terrain_id in node.terrains:
			if not terrains.has(terrain_id):
				problems.append("Node '%s' uses unknown terrain '%s'." % [node.id, terrain_id])
		for biome_id in node.biomes:
			if not biomes.has(biome_id):
				problems.append("Node '%s' uses unknown biome '%s'." % [node.id, biome_id])
	for location: LocationData in locations.values():
		for terrain_id in location.terrains:
			if not terrains.has(terrain_id):
				problems.append("Location '%s' uses unknown terrain '%s'." % [location.id, terrain_id])
		for biome_id in location.biomes:
			if not biomes.has(biome_id):
				problems.append("Location '%s' uses unknown biome '%s'." % [location.id, biome_id])
	return problems


func _load_dir(path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("Content folder missing: %s" % path)
		return out
	for file_name in dir.get_files():
		# Exported builds list resources as '<name>.tres.remap'.
		var clean_name := file_name.trim_suffix(".remap")
		if not clean_name.ends_with(".tres"):
			continue
		var res := load(path.path_join(clean_name))
		if res == null:
			continue
		var res_id: Variant = res.get("id")
		if res_id == null or str(res_id) == "":
			push_warning("Resource without id: %s" % clean_name)
			continue
		out[str(res_id)] = res
	return out
