extends SceneTree
## Prints how much each NPC settlement can reach. godot --headless --path . --script tests/sim_reach.gd -- first count

func _initialize() -> void:
	var db: Node = load("res://src/core/content_db.gd").new()
	db.reload()
	var args := OS.get_cmdline_user_args()
	var first := int(args[0]) if args.size() > 0 else 1
	var count := int(args[1]) if args.size() > 1 else 6
	var gen := WorldGenerator.new(db)
	var totals: Array = []
	var foods: Array = []
	var mats: Array = []
	for s in range(first, first + count):
		var w := gen.generate(s)
		var line := PackedStringArray()
		for h: int in w.settlements.keys():
			var r := WorldReach.summarize(w, db, h, 2)
			totals.append(r["total"])
			foods.append(r["food"])
			mats.append(r["material"])
			line.append("%d/%d/%d" % [r["food"], r["material"], r["water"]])
		print("seed %d issues %d  food/mat/water: %s" % [s, w.issues.size(), " ".join(line)])
	totals.sort()
	foods.sort()
	mats.sort()
	print("total nodes in reach: min %d p25 %d median %d p75 %d max %d" % [totals[0], totals[totals.size() / 4], totals[totals.size() / 2], totals[totals.size() * 3 / 4], totals[-1]])
	print("food: min %d median %d max %d   material: min %d median %d max %d" % [foods[0], foods[foods.size() / 2], foods[-1], mats[0], mats[mats.size() / 2], mats[-1]])
	quit()
