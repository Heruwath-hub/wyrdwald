extends SceneTree
## How close NPC settlements sit to the sea, and how many nodes a world has.
## godot --headless --path . --script tests/sim_coast.gd -- first count

func _initialize() -> void:
	var db: Node = load("res://src/core/content_db.gd").new()
	db.reload()
	var args := OS.get_cmdline_user_args()
	var first := int(args[0]) if args.size() > 0 else 1
	var count := int(args[1]) if args.size() > 1 else 12
	var gen := WorldGenerator.new(db)
	var hist := {}
	var total := 0
	var nodes := 0
	var sea_nodes := 0
	var river_fish := 0
	var land := 0
	var fish_all := 0
	for s in range(first, first + count):
		var w := gen.generate(s)
		land += w.size()
		for i in w.settlements.keys():
			var d: int = mini(w.coast_dist[i], 6)
			hist[d] = int(hist.get(d, 0)) + 1
			total += 1
		for i in w.size():
			if w.node[i] != "" and w.node[i] != "spring":
				nodes += 1
				if w.node[i] == "fish":
					river_fish += 1
		sea_nodes += w.sea_node.size()
	var keys := hist.keys()
	keys.sort()
	var line := ""
	for k in keys:
		line += "d%d: %.0f%%  " % [k, 100.0 * hist[k] / total]
	print("settlements by distance to the sea (0 = coast): ", line)
	print("per world: land %.0f, nodes %.1f (fish on land water %.1f), sea nodes %.1f" % [float(land) / count, float(nodes) / count, float(river_fish) / count, float(sea_nodes) / count])
	quit()
