extends SceneTree
## Generates many worlds and prints statistics. godot --headless --path . --script tests/sim_worldgen.gd [-- first count]

func _initialize() -> void:
	var db: Node = load("res://src/core/content_db.gd").new()
	db.reload()
	for p in db.validate():
		print("CONTENT: ", p)
	var args := OS.get_cmdline_user_args()
	var first := int(args[0]) if args.size() > 0 else 1
	var count := int(args[1]) if args.size() > 1 else 10
	var gen := WorldGenerator.new(db)
	var fails := 0
	var terrain_sum := {}
	var node_sum := {}
	var loc_sum := {}
	var cross: Array = []
	var quiet := args.size() > 2
	var coast_sum := 0
	var links_sum := 0.0
	var attempts := 0
	var t0 := Time.get_ticks_msec()
	for s in range(first, first + count):
		var t1 := Time.get_ticks_msec()
		var w := gen.generate(s)
		attempts += w.attempt + 1
		var st := w.stats
		for k in st.get("terrain", {}):
			terrain_sum[k] = int(terrain_sum.get(k, 0)) + int(st["terrain"][k])
		for k in st.get("nodes", {}):
			node_sum[k] = int(node_sum.get(k, 0)) + int(st["nodes"][k])
		for k in st.get("locations", {}):
			loc_sum[k] = int(loc_sum.get(k, 0)) + int(st["locations"][k])
		coast_sum += int(st.get("coast_hexes", 0))
		links_sum += float(st.get("mountain_neighbors", 0.0))
		cross.append(int(st.get("crossing_median_ap", 0)))
		if not quiet:
			print("seed %d attempt %d hexes %d cross %s ms %d areas %s settle %s starts %d issues %s" % [s, w.attempt, w.size(), str(st.get("crossing_median_ap")), Time.get_ticks_msec() - t1, str(st.get("biome_area")), str(st.get("settlements")), w.starts.size(), str(w.issues)])
		if not w.issues.is_empty():
			fails += 1
	var total_hexes := 0
	for k in terrain_sum:
		total_hexes += int(terrain_sum[k])
	var tp := []
	for k in terrain_sum:
		tp.append("%s %.1f%%" % [k, 100.0 * terrain_sum[k] / total_hexes])
	print("terrain ", ", ".join(tp))
	var np := []
	var nk := node_sum.keys()
	nk.sort()
	for k in nk:
		np.append("%s %.1f" % [k, float(node_sum[k]) / count])
	print("nodes per world ", ", ".join(np))
	var lp := []
	for k in loc_sum:
		lp.append("%s %.1f" % [k, float(loc_sum[k]) / count])
	print("locations per world ", ", ".join(lp))
	cross.sort()
	print("crossing AP min %d median %d max %d" % [cross[0], cross[cross.size() / 2], cross[cross.size() - 1]])
	print("coast hexes avg %d, mountain neighbours avg %.2f (a chain is about 2, a blob 4+)" % [coast_sum / count, links_sum / count])
	print("worlds %d failed %d avg attempts %.2f total ms %d" % [count, fails, float(attempts) / count, Time.get_ticks_msec() - t0])
	quit(0)
