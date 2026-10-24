class_name WorldValidator
extends RefCounted
## Checks a generated world against the design rules. Empty result = the world is fine.
## Also fills `w.stats` with numbers the prototype UI and the simulations report.


## True if a party starting on hex `s` has supplies within reach and a settlement 3-4 days away.
## `camp` marks hexes with enough food slots (fresh water counts) inside their 2-ring disc.
static func start_is_valid(w: WorldData, s: int, camp: PackedByteArray, p: WorldParams) -> bool:
	var dist := WorldPathing.costs_from(w, s, p.start_settlement_max_ap)
	var supplied := false
	var nearest := 1 << 20
	for i in w.size():
		var d := dist[i]
		if d < 0:
			continue
		if d <= p.start_supply_ap and camp[i] == 1:
			supplied = true
		if w.settlements.has(i):
			nearest = mini(nearest, d)
	return supplied and nearest >= p.start_settlement_min_ap and nearest <= p.start_settlement_max_ap


static func validate(w: WorldData, db: Variant, p: WorldParams) -> PackedStringArray:
	var issues := PackedStringArray()
	var biomes: Array[BiomeData] = []
	for b: BiomeData in db.biomes.values():
		biomes.append(b)
	biomes.sort_custom(func(a: BiomeData, b: BiomeData) -> bool:
		return a.tier < b.tier if a.tier != b.tier else a.id < b.id)

	# Biomes are clear-cut: each is one connected region and no hex is shared or blended.
	for b in biomes:
		var members := w.biome_hexes(b.id)
		if members.is_empty():
			issues.append("%s is missing." % b.display_name)
			continue
		var seen := {members[0]: true}
		var queue := PackedInt32Array([members[0]])
		var head := 0
		while head < queue.size():
			var cur := queue[head]
			head += 1
			for nb in w.neighbors[cur]:
				if w.biome[nb] == b.id and not seen.has(nb):
					seen[nb] = true
					queue.append(nb)
		if seen.size() != members.size():
			issues.append("%s is split into several regions." % b.display_name)

	var comps := WorldPathing.components(w)
	if comps.size() != 1:
		issues.append("Walkable land is split into %d parts." % comps.size())

	var border := border_pairs(w)
	var tier_of := {}
	for b in biomes:
		tier_of[b.id] = b.tier
	var t2_total := 0
	for b in biomes:
		if b.tier == 2:
			t2_total += 1
	for b in biomes:
		var t1 := 0
		var t2 := 0
		for key: String in border.keys():
			var parts := key.split("|")
			var other := ""
			if parts[0] == b.id:
				other = parts[1]
			elif parts[1] == b.id:
				other = parts[0]
			if other == "":
				continue
			if tier_of[other] == 1:
				t1 += 1
			elif tier_of[other] == 2 and (border[key] as Array).size() >= p.min_border_pairs:
				t2 += 1
		if b.tier == 1 and t2 < mini(p.min_tier2_neighbors, t2_total):
			issues.append("%s borders only %d middle biomes." % [b.display_name, t2])
		if b.tier == 3 and (t1 > 0 or t2 < mini(p.min_tier2_neighbors, t2_total)):
			issues.append("%s has bad neighbours (%d plains, %d middle)." % [b.display_name, t1, t2])
	for key: String in border.keys():
		if (border[key] as Array).size() < p.min_border_pairs:
			continue
		var crossings := 0
		for pair: Array in border[key]:
			if w.passable(pair[0]) and w.passable(pair[1]):
				crossings += 1
		if crossings < 2:
			issues.append("Border %s has %d walkable crossings." % [key, crossings])

	# Crossing time, measured as least-cost paths between far-apart border hexes of a biome.
	var medians: Array = []
	var per_biome := {}
	for b in biomes:
		var m := _crossing_median(w, b.id)
		per_biome[b.id] = m
		if m > 0:
			medians.append(m)
	medians.sort()
	var median_all := 0
	if not medians.is_empty():
		median_all = medians[medians.size() / 2]
	if median_all < p.crossing_min_ap or median_all > p.crossing_max_ap:
		issues.append("Median biome crossing is %d AP (wanted %d-%d)." % [median_all, p.crossing_min_ap, p.crossing_max_ap])

	for b in biomes:
		if b.start_allowed and not w.starts.has(b.id):
			issues.append("No valid start in %s." % b.display_name)
		if b.settlements_per_race > 0:
			var races := 0
			for r: RaceData in db.races.values():
				if r.native_biome == b.display_name:
					races += 1
			var want := races * b.settlements_per_race
			var have := 0
			for s: int in w.settlements.keys():
				if w.biome[s] == b.id:
					have += 1
			if have != want:
				issues.append("%s has %d settlements (wanted %d)." % [b.display_name, have, want])

	issues.append_array(water_issues(w, p))
	var straight := longest_straight_coast(w)
	if straight > p.max_straight_coast:
		issues.append("The coast runs straight for %d hexes (at most %d)." % [straight, p.max_straight_coast])
	var border_dist := _border_dist(w)
	for s: int in w.settlements.keys():
		if border_dist[s] < p.settlement_border_distance:
			issues.append("Settlement %s is too close to a biome border." % str(w.settlements[s]["id"]))
		if w.coast_dist[s] < p.settlement_coast_distance:
			issues.append("Settlement %s is too close to the sea." % str(w.settlements[s]["id"]))
		var r := WorldReach.summarize(w, db, s, p.settlement_range)
		var tag := str(w.settlements[s]["id"])
		if r["food_slots"] < p.settlement_food_min or r["food_slots"] > p.settlement_food_max:
			issues.append("Settlement %s reaches %d food slots." % [tag, r["food_slots"]])
		if r["material"] < p.settlement_material_min or r["material"] > p.settlement_material_max:
			issues.append("Settlement %s reaches %d material nodes." % [tag, r["material"]])

	_fill_stats(w, biomes, per_biome, median_all)
	return issues


## "a|b" (biome ids, a < b) -> Array of [hex_in_a, hex_in_b] neighbouring pairs.
static func border_pairs(w: WorldData) -> Dictionary:
	var border := {}
	for i in w.size():
		for nb in w.neighbors[i]:
			if w.biome[nb] != w.biome[i] and w.biome[i] < w.biome[nb]:
				var key := "%s|%s" % [w.biome[i], w.biome[nb]]
				if not border.has(key):
					border[key] = []
				(border[key] as Array).append([i, nb])
	return border


static func _border_dist(w: WorldData) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w.size())
	dist.fill(99)
	var queue := PackedInt32Array()
	for i in w.size():
		for nb in w.neighbors[i]:
			if w.biome[nb] != w.biome[i]:
				dist[i] = 0
				queue.append(i)
				break
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for nb in w.neighbors[cur]:
			if dist[nb] == 99 and w.biome[nb] == w.biome[cur]:
				dist[nb] = dist[cur] + 1
				queue.append(nb)
	return dist


## Longest run of hexes along one hex axis whose sea side is open water for the whole run.
static func longest_straight_coast(w: WorldData) -> int:
	var best := 0
	for run: Dictionary in straight_runs(w.index, 2):
		best = maxi(best, (run["cells"] as Array).size())
	return best


## Stretches of coast that run straight along a hex axis, each at least `min_len` long.
## `land` is any Dictionary keyed by Vector2i. Result: [{cells: Array[Vector2i], d1, d2}] where d1
## and d2 are the two directions that face the sea.
static func straight_runs(land: Dictionary, min_len: int) -> Array:
	var out: Array = []
	var keys := land.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y)
	for a in 3:
		for side in [1, -1]:
			var d1: Vector2i = HexGrid.DIRS[(a + side + 6) % 6]
			var d2: Vector2i = HexGrid.DIRS[(a + 2 * side + 6) % 6]
			var step: Vector2i = HexGrid.DIRS[a]
			for c: Vector2i in keys:
				if not _faces_sea(land, c, d1, d2) or _faces_sea(land, c - step, d1, d2):
					continue
				var cells: Array[Vector2i] = [c]
				var cur := c + step
				while _faces_sea(land, cur, d1, d2):
					cells.append(cur)
					cur += step
				if cells.size() >= min_len:
					out.append({"cells": cells, "d1": d1, "d2": d2})
	return out


static func _faces_sea(land: Dictionary, c: Vector2i, d1: Vector2i, d2: Vector2i) -> bool:
	return land.has(c) and not land.has(c + d1) and not land.has(c + d2)


## Rules for rivers, lakes and springs, read from the finished terrain.
static func water_issues(w: WorldData, p: WorldParams) -> PackedStringArray:
	var issues := PackedStringArray()
	var n := w.size()
	for i in n:
		if w.terrain[i] == "river":
			var river_nb := 0
			for nb in w.neighbors[i]:
				if w.terrain[nb] == "river":
					river_nb += 1
			if river_nb > p.river_max_neighbors:
				issues.append("The river at %s touches %d other river hexes." % [str(w.coords[i]), river_nb])
			var upstream := 0
			var fed := false
			for nb in w.neighbors[i]:
				if w.flow_to[nb] == i and w.terrain[nb] == "river":
					upstream += 1
				if w.flow_to[nb] == i and w.terrain[nb] == "lake":
					fed = true
			if upstream == 0:
				if fed:
					if w.node[i] == "spring":
						issues.append("A lake-fed river at %s has a spring." % str(w.coords[i]))
				else:
					if w.node[i] != "spring":
						issues.append("A river head at %s has no spring." % str(w.coords[i]))
					if w.coast_dist[i] < p.spring_min_coast:
						issues.append("The spring at %s is too close to the sea." % str(w.coords[i]))
				var length := 1
				var cur := w.flow_to[i]
				while cur != -1 and w.terrain[cur] == "river":
					var ups := 0
					for nb in w.neighbors[cur]:
						if w.flow_to[nb] == cur and w.terrain[nb] == "river":
							ups += 1
					if ups > 1:
						break
					length += 1
					cur = w.flow_to[cur]
				if length < p.river_min_length:
					issues.append("A river at %s is only %d long." % [str(w.coords[i]), length])
		elif w.node[i] == "spring":
			issues.append("A spring at %s is not on a river." % str(w.coords[i]))
	# Lakes: only the inflow and the outflow river may touch them, with a gap between those ends.
	var seen := {}
	for s in n:
		if w.terrain[s] != "lake" or seen.has(s):
			continue
		var members := {s: true}
		var queue := [s]
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for nb in w.neighbors[cur]:
				if w.terrain[nb] == "lake" and not members.has(nb):
					members[nb] = true
					queue.append(nb)
		for m in members:
			seen[m] = true
		var inflow: Array = []
		var outflow := {}
		var touching := {}
		for c: int in members.keys():
			if w.coast_dist[c] < p.lake_min_coast:
				issues.append("A lake at %s touches the sea." % str(w.coords[c]))
			var out := w.flow_to[c]
			if out != -1 and not members.has(out) and w.terrain[out] == "river":
				outflow[out] = true
			for nb in w.neighbors[c]:
				if not members.has(nb) and w.terrain[nb] == "river":
					touching[nb] = true
		for r: int in touching.keys():
			if members.has(w.flow_to[r]):
				inflow.append(r)
			elif not outflow.has(r):
				issues.append("A river runs alongside the lake at %s." % str(w.coords[r]))
		if outflow.is_empty():
			issues.append("The lake at %s has no outflow." % str(w.coords[s]))
		for e: int in inflow:
			for o: int in outflow.keys():
				if HexGrid.distance(w.coords[e], w.coords[o]) < p.lake_min_gap:
					issues.append("The lake at %s has its inflow and outflow side by side." % str(w.coords[s]))
	return issues


static func _crossing_median(w: WorldData, biome_id: String) -> int:
	var edge: Array = []
	for i in w.biome_hexes(biome_id):
		if not w.passable(i):
			continue
		for nb in w.neighbors[i]:
			if w.biome[nb] != biome_id:
				edge.append(i)
				break
	if edge.size() < 2:
		return 0
	var costs: Array = []
	var step := maxi(1, edge.size() / 10)
	for a in range(0, edge.size(), step):
		var dist := WorldPathing.costs_from(w, edge[a])
		var best_far := 0
		for b: int in edge:
			best_far = maxi(best_far, HexGrid.distance(w.coords[edge[a]], w.coords[b]))
		for b: int in edge:
			if HexGrid.distance(w.coords[edge[a]], w.coords[b]) >= int(best_far * 0.8) and dist[b] > 0:
				costs.append(dist[b])
	if costs.is_empty():
		return 0
	costs.sort()
	return costs[costs.size() / 2]


static func _fill_stats(w: WorldData, biomes: Array[BiomeData], per_biome: Dictionary, median_all: int) -> void:
	var terrain_counts := {}
	var node_counts := {}
	var location_counts := {}
	for i in w.size():
		terrain_counts[w.terrain[i]] = int(terrain_counts.get(w.terrain[i], 0)) + 1
		if w.node[i] != "":
			node_counts[w.node[i]] = int(node_counts.get(w.node[i], 0)) + 1
		if w.location[i] != "":
			location_counts[w.location[i]] = int(location_counts.get(w.location[i], 0)) + 1
	var areas := {}
	var settle := {}
	for b in biomes:
		areas[b.id] = w.biome_hexes(b.id).size()
		settle[b.id] = 0
	for s: int in w.settlements.keys():
		settle[w.biome[s]] = int(settle[w.biome[s]]) + 1
	var coast := 0
	var mountains := 0
	var mountain_links := 0
	for i in w.size():
		if w.neighbors[i].size() < 6:
			coast += 1
		if w.terrain[i] == "mountain":
			mountains += 1
			for nb in w.neighbors[i]:
				if w.terrain[nb] == "mountain":
					mountain_links += 1
	w.stats = {
		"coast_hexes": coast,
		"mountains": mountains,
		"mountain_neighbors": float(mountain_links) / maxf(mountains, 1.0),
		"hexes": w.size(),
		"biome_area": areas,
		"terrain": terrain_counts,
		"nodes": node_counts,
		"locations": location_counts,
		"settlements": settle,
		"crossing_ap": per_biome,
		"crossing_median_ap": median_all,
	}
