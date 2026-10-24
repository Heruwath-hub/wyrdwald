extends SceneTree
## Counts which rules reject generation attempts. godot --headless --path . --script tests/sim_rejections.gd -- first count attempts
func _initialize() -> void:
	var db: Node = load("res://src/core/content_db.gd").new()
	db.reload()
	var args := OS.get_cmdline_user_args()
	var first := int(args[0]) if args.size() > 0 else 1
	var count := int(args[1]) if args.size() > 1 else 10
	var per := int(args[2]) if args.size() > 2 else 4
	var gen := WorldGenerator.new(db)
	var kinds := {}
	var total := 0
	var failed := 0
	var null_builds := 0
	for s in range(first, first + count):
		for a in per:
			total += 1
			var w = gen._build(s, a)
			if w == null:
				null_builds += 1
				failed += 1
				continue
			var found := {}
			for issue in WorldValidator.validate(w, db, gen._p):
				found[_rule(issue)] = true
				if issue.contains("settlements (wanted"):
					found[issue.substr(0, 40)] = true
			if not found.is_empty():
				failed += 1
			for k in found:
				kinds[k] = int(kinds.get(k, 0)) + 1
	print("attempts %d, rejected %d (%.0f%%), biome topology failed before build %d" % [total, failed, 100.0 * failed / total, null_builds])
	var keys := kinds.keys()
	keys.sort_custom(func(a, b): return kinds[a] > kinds[b])
	for k in keys:
		print("  %3d  %s" % [kinds[k], k])
	quit()

func _rule(issue: String) -> String:
	for key in ["borders only", "bad neighbours", "split into several", "Walkable land is split", "walkable crossings", "Median biome crossing", "No valid start", "settlements (wanted", "too close to a biome border", "food nodes", "material nodes", "no fresh water", "coast runs straight", "touches", "river head", "spring", "only", "lake", "is missing"]:
		if issue.contains(key):
			return key
	return issue.substr(0, 30)
