extends SceneTree
## Per biome: walkable share, valid build sites, resource amount and how evenly it is spread.
## godot --headless --path . --script tests/sim_sites.gd -- first count

func _initialize() -> void:
	var db: Node = load("res://src/core/content_db.gd").new()
	db.reload()
	var args := OS.get_cmdline_user_args()
	var first := int(args[0]) if args.size() > 0 else 1
	var count := int(args[1]) if args.size() > 1 else 6
	var gen := WorldGenerator.new(db)
	var p := WorldParams.new()
	var stat := {}   # biome -> {hexes, walk, sites, nodes, values:[], reach:[]}
	for s in range(first, first + count):
		var w := gen.generate(s)
		var claimed := WorldReach.npc_claimed(w, p.settlement_range)
		for i in w.size():
			var b := w.biome[i]
			if not stat.has(b):
				stat[b] = {"hexes": 0, "walk": 0, "sites": 0, "nodes": 0, "values": [], "reach": []}
			var st: Dictionary = stat[b]
			st["hexes"] += 1
			if w.node[i] != "":
				st["nodes"] += 1
			if not w.passable(i):
				continue
			st["walk"] += 1
			var r := WorldReach.summarize(w, db, i, p.settlement_range)
			(st["reach"] as Array).append(r["total"])
			var info := WorldReach.build_info(w, db, p, i, claimed)
			if info["ok"]:
				st["sites"] += 1
				(st["values"] as Array).append(info["score"])
	print("biome        walk%  sites%/walk  nodes/100walk  reach mean  reach CV  site score p10/p50/p90")
	for b in ["plainlands", "woodlands", "highlands", "wetlands", "wyrdwood"]:
		var st: Dictionary = stat[b]
		var reach: Array = st["reach"]
		var mean := 0.0
		for v in reach:
			mean += v
		mean /= maxi(reach.size(), 1)
		var var_sum := 0.0
		for v in reach:
			var_sum += (v - mean) * (v - mean)
		var cv := sqrt(var_sum / maxi(reach.size(), 1)) / maxf(mean, 0.001)
		var vals: Array = st["values"]
		vals.sort()
		var q := func(f: float) -> float: return vals[int(f * (vals.size() - 1))] if not vals.is_empty() else 0.0
		print("%-12s %4.0f%%  %5.1f%%       %6.1f         %5.2f      %5.2f     %.1f / %.1f / %.1f" % [
			b, 100.0 * st["walk"] / st["hexes"], 100.0 * st["sites"] / maxi(st["walk"], 1),
			100.0 * st["nodes"] / maxi(st["walk"], 1), mean, cv, q.call(0.1), q.call(0.5), q.call(0.9)])
	quit()
