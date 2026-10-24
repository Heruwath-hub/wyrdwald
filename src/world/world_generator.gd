class_name WorldGenerator
extends RefCounted
## Builds a whole continent from one integer seed. The same seed and generator version always
## give the same world. Every stage draws only from its own sub-seed, so changing one stage's
## rules never reshuffles the others.
##
## Stages: land -> elevation -> biomes -> hydrology -> terrain -> connectivity -> nodes ->
## settlements -> starts -> locations. A world that fails validation is rebuilt with the next
## attempt number (still fully determined by the seed).

const VERSION := "w1"

var _db: Variant
var _p: WorldParams
var _base: int = 0
var _terrain_defs: Dictionary = {}


func _init(content_db: Variant, params: WorldParams = null) -> void:
	_db = content_db
	_p = params if params != null else WorldParams.new()


func generate(seed_value: int) -> WorldData:
	var last: WorldData = null
	for attempt in _p.max_attempts:
		var w := _build(seed_value, attempt)
		if w == null:
			continue
		w.issues = WorldValidator.validate(w, _db, _p)
		last = w
		if w.issues.is_empty():
			return w
	if last == null:
		last = WorldData.new()
		last.seed_value = seed_value
		last.version = VERSION
		last.issues = PackedStringArray(["No attempt produced a world."])
	return last


func _build(seed_value: int, attempt: int) -> WorldData:
	_base = WorldHash.sub(seed_value, "attempt%d" % attempt)
	var w := WorldData.new()
	w.seed_value = seed_value
	w.version = VERSION
	w.attempt = attempt
	w.radius = _p.radius
	_terrain_defs = _db.terrains
	_stage_land(w)
	_stage_elevation(w)
	if not _stage_biomes(w):
		return null
	var water := _stage_hydrology(w)
	_stage_terrain(w, water)
	_connect_components(w)
	_ensure_crossings(w)
	_stage_nodes(w)
	_stage_settlements(w)
	_stage_starts(w)
	_stage_locations(w)
	return w


# ---------------------------------------------------------------- helpers

func _biome_list() -> Array[BiomeData]:
	var list: Array[BiomeData] = []
	for b: BiomeData in _db.biomes.values():
		list.append(b)
	list.sort_custom(func(a: BiomeData, b: BiomeData) -> bool:
		if a.tier != b.tier:
			return a.tier < b.tier
		return a.id < b.id)
	return list


func _sorted_ids(dict: Dictionary) -> Array:
	var ids := dict.keys()
	ids.sort()
	return ids


func _apply_ap(w: WorldData) -> void:
	for i in w.size():
		var t: TerrainData = _terrain_defs.get(w.terrain[i])
		w.ap[i] = t.ap_cost if t != null and t.passable else -1


# ---------------------------------------------------------------- land

func _stage_land(w: WorldData) -> void:
	var radius := _p.radius
	var land_target := int(round((3 * radius * radius + 3 * radius + 1) * _p.land_scale))
	var cell_target := land_target / _p.land_fraction
	# Each seed picks its own bounds (a wide or a tall rectangle) and its own outline: a skeleton of
	# lobes joined by arms, ragged by noise, so coasts, bays and peninsulas differ from seed to seed.
	var shape := WorldRng.new(WorldHash.sub(_base, "shape"))
	var bounds_aspect := lerpf(_p.bounds_aspect_min, _p.bounds_aspect_max, shape.randf())
	var area := cell_target * 1.5 * HexGrid.SQRT3
	var half_x := sqrt(area / 4.0 * bounds_aspect)
	var half_z := sqrt(area / 4.0 / bounds_aspect)
	w.half_extent = Vector2(half_x, half_z)
	var cells: Array[Vector2i] = []
	var in_bounds := {}
	for q in range(-90, 91):
		for r in range(-90, 91):
			var p := HexGrid.to_world(Vector2i(q, r))
			if absf(p.x) <= half_x and absf(p.y) <= half_z:
				cells.append(Vector2i(q, r))
				in_bounds[Vector2i(q, r)] = true
	var lobe_count := 3 + shape.below(4)
	var lobes: Array = []   # [centre: Vector2, radius: float]
	for k in lobe_count:
		var centre := Vector2(
			(shape.randf() * 2.0 - 1.0) * half_x * 0.62,
			(shape.randf() * 2.0 - 1.0) * half_z * 0.62)
		lobes.append([centre, lerpf(0.16, 0.3, shape.randf()) * (half_x + half_z)])
	# Arms join every lobe to the nearest lobe already joined, so the skeleton is one piece.
	var arms: Array = []   # [from, to, width]
	var joined: Array = [0]
	for k in range(1, lobe_count):
		var nearest := 0
		var nearest_d := 1e9
		for j: int in joined:
			var d: float = (lobes[k][0] as Vector2).distance_to(lobes[j][0])
			if d < nearest_d:
				nearest_d = d
				nearest = j
		arms.append([lobes[k][0], lobes[nearest][0], lerpf(0.08, 0.16, shape.randf()) * (half_x + half_z)])
		joined.append(k)
	var power := lerpf(1.2, 2.2, shape.randf())
	var noise_weight := lerpf(5.0, 8.0, shape.randf())
	var warp := lerpf(6.0, 14.0, shape.randf())
	var freq := lerpf(0.07, 0.13, shape.randf())
	var s := WorldHash.sub(_base, "land")
	var scored: Array = []
	for c in cells:
		var p := HexGrid.to_world(c)
		var q := p + Vector2(
			(WorldNoise.fbm(s + 5, p.x * 0.07 + 40.0, p.y * 0.07, 3) - 0.5) * 2.0 * warp,
			(WorldNoise.fbm(s + 9, p.x * 0.07, p.y * 0.07 + 90.0, 3) - 0.5) * 2.0 * warp)
		var de := 1e9
		for lobe: Array in lobes:
			de = minf(de, q.distance_to(lobe[0]) / lobe[1])
		for arm: Array in arms:
			de = minf(de, _segment_distance(q, arm[0], arm[1]) / arm[2])
		var score := noise_weight * WorldNoise.fbm(s, q.x * freq + 13.0, q.y * freq + 7.0, 5) - 1.2 * pow(de, power)
		# Land never reaches the edge of the bounds, which would cut it into a straight coast.
		var edge := minf(half_x - absf(p.x), half_z - absf(p.y))
		if edge < 7.0:
			score -= (7.0 - edge) * 2.0
		scored.append([score, c])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] > b[0]
		var ca: Vector2i = a[1]
		var cb: Vector2i = b[1]
		if ca.x != cb.x:
			return ca.x < cb.x
		return ca.y < cb.y)
	var target := land_target
	var score_of := {}
	for entry: Array in scored:
		score_of[entry[1]] = entry[0]
	var land := {}
	for k in mini(target, scored.size()):
		land[scored[k][1]] = true
	land = _largest_component(land)
	# The best-scoring hexes may form several pieces; the main one grows by its best neighbours until
	# the land has its size, so every seed ends with one landmass of about the same area.
	while land.size() < target:
		var frontier := {}
		for c: Vector2i in land.keys():
			for d in HexGrid.DIRS:
				var nb: Vector2i = c + d
				if in_bounds.has(nb) and not land.has(nb):
					frontier[nb] = true
		if frontier.is_empty():
			break
		var list: Array = frontier.keys()
		list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if score_of[a] != score_of[b]:
				return score_of[a] > score_of[b]
			return a.x < b.x if a.x != b.x else a.y < b.y)
		for k in mini(maxi(1, (target - land.size()) / 3), list.size()):
			land[list[k]] = true
	# Fill inland seas: water that cannot reach the edge of the bounds becomes land.
	var sea := {}
	var frontier: Array[Vector2i] = []
	for c in cells:
		if land.has(c):
			continue
		var on_rim := false
		for d in HexGrid.DIRS:
			if not in_bounds.has(c + d):
				on_rim = true
				break
		if on_rim:
			sea[c] = true
			frontier.append(c)
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_back()
		for d in HexGrid.DIRS:
			var nb: Vector2i = cur + d
			if not in_bounds.has(nb) or land.has(nb) or sea.has(nb):
				continue
			sea[nb] = true
			frontier.append(nb)
	for c in cells:
		if not land.has(c) and not sea.has(c):
			land[c] = true
	_break_straight_coasts(land, in_bounds, WorldRng.new(WorldHash.sub(_base, "coast")))
	for c in cells:
		if land.has(c):
			w.add_hex(c)
	w.allocate()
	w.build_neighbors()


## Notches or bumps the middle of every straight stretch of coast that is too long.
func _break_straight_coasts(land: Dictionary, in_bounds: Dictionary, rng: WorldRng) -> void:
	for pass_index in 14:
		var runs := WorldValidator.straight_runs(land, _p.max_straight_coast + 1)
		if runs.is_empty():
			return
		for run: Dictionary in runs:
			var cells: Array = run["cells"]
			var mid: Vector2i = cells[cells.size() / 2 + rng.below(3) - 1]
			var d1: Vector2i = run["d1"]
			var d2: Vector2i = run["d2"]
			if not land.has(mid) or land.has(mid + d1) or land.has(mid + d2):
				continue   # an earlier fix in this pass already changed the spot
			if rng.randf() < 0.5 and _removable(land, mid):
				land.erase(mid)
			else:
				var out: Vector2i = mid + (d1 if rng.randf() < 0.5 else d2)
				if in_bounds.has(out):
					land[out] = true


## A coastal hex can go without cutting the land when its land neighbours form one arc.
func _removable(land: Dictionary, c: Vector2i) -> bool:
	var transitions := 0
	var land_count := 0
	for k in 6:
		var here: bool = land.has(c + HexGrid.DIRS[k])
		var next: bool = land.has(c + HexGrid.DIRS[(k + 1) % 6])
		if here:
			land_count += 1
		if here and not next:
			transitions += 1
	return land_count >= 2 and land_count <= 4 and transitions == 1


func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _largest_component(land: Dictionary) -> Dictionary:
	var seen := {}
	var best: Array[Vector2i] = []
	var keys := land.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y)
	for start: Vector2i in keys:
		if seen.has(start):
			continue
		var group: Array[Vector2i] = [start]
		seen[start] = true
		var head := 0
		while head < group.size():
			var cur := group[head]
			head += 1
			for d in HexGrid.DIRS:
				var nb: Vector2i = cur + d
				if land.has(nb) and not seen.has(nb):
					seen[nb] = true
					group.append(nb)
		if group.size() > best.size():
			best = group
	var out := {}
	for c in best:
		out[c] = true
	return out


# ---------------------------------------------------------------- elevation

func _stage_elevation(w: WorldData) -> void:
	var n := w.size()
	var coast := PackedInt32Array()
	coast.resize(n)
	coast.fill(-1)
	var queue := PackedInt32Array()
	for i in n:
		if w.neighbors[i].size() < 6:
			coast[i] = 0
			queue.append(i)
	var head := 0
	var max_d := 1
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for nb in w.neighbors[cur]:
			if coast[nb] == -1:
				coast[nb] = coast[cur] + 1
				max_d = maxi(max_d, coast[nb])
				queue.append(nb)
	for i in n:
		w.coast_dist[i] = coast[i]
	var se := WorldHash.sub(_base, "elevation")
	var sm := WorldHash.sub(_base, "moisture")
	var sr := WorldHash.sub(_base, "ridges")
	var lo := 1e9
	var hi := -1e9
	var rlo := 1e9
	var rhi := -1e9
	for i in n:
		var p := HexGrid.to_world(w.coords[i])
		var inland := pow(float(coast[i]) / max_d, 0.8)
		# Ridged noise: the lines where the noise crosses its middle become mountain chains.
		var q := p + Vector2(
			(WorldNoise.fbm(sr + 3, p.x * 0.05 + 11.0, p.y * 0.05, 3) - 0.5) * 9.0,
			(WorldNoise.fbm(sr + 8, p.x * 0.05, p.y * 0.05 + 23.0, 3) - 0.5) * 9.0)
		var ridge := 1.0 - absf(2.0 * WorldNoise.fbm(sr, q.x * 0.075, q.y * 0.075, 3) - 1.0)
		var e := 0.4 * WorldNoise.fbm(se, p.x * 0.11, p.y * 0.11, 4) + 0.35 * inland + 0.25 * ridge
		w.elevation[i] = e
		w.relief[i] = 0.85 * ridge + 0.15 * e
		lo = minf(lo, e)
		hi = maxf(hi, e)
		rlo = minf(rlo, w.relief[i])
		rhi = maxf(rhi, w.relief[i])
		w.moisture[i] = WorldNoise.fbm(sm, p.x * 0.13 + 50.0, p.y * 0.13 + 20.0, 3)
	for i in n:
		w.elevation[i] = (w.elevation[i] - lo) / maxf(hi - lo, 0.0001)
		w.relief[i] = (w.relief[i] - rlo) / maxf(rhi - rlo, 0.0001)


# ---------------------------------------------------------------- biomes

func _stage_biomes(w: WorldData) -> bool:
	var biomes := _biome_list()
	var n := w.size()
	var sorted_elev: Array = []
	for i in n:
		sorted_elev.append(w.elevation[i])
	sorted_elev.sort()
	var q30: float = sorted_elev[int(n * 0.3)]
	var sorted_relief: Array = []
	for i in n:
		sorted_relief.append(w.relief[i])
	sorted_relief.sort()
	var q70: float = sorted_relief[int(n * 0.7)]
	var ws := WorldHash.sub(_base, "warp")
	var warped := PackedVector2Array()
	for i in n:
		var p := HexGrid.to_world(w.coords[i])
		warped.append(p + Vector2(
			(WorldNoise.fbm(ws, p.x * 0.14, p.y * 0.14, 4) - 0.5) * 17.0,
			(WorldNoise.fbm(ws + 77, p.x * 0.14 + 31.0, p.y * 0.14, 4) - 0.5) * 17.0))
	for t in 40:
		var rng := WorldRng.new(WorldHash.sub(_base, "anchors%d" % t))
		var anchors := _pick_anchors(w, biomes, rng, q30, q70)
		if anchors.is_empty():
			continue
		# Biomes can have extra seeds near their anchor, which stretches them into arms and lobes.
		var extras: Array = []
		for k in biomes.size():
			var list: Array[Vector2] = []
			var base_pos := HexGrid.to_world(w.coords[anchors[k]])
			for e in rng.below(3):
				var ang := rng.randf() * TAU
				list.append(base_pos + Vector2(cos(ang), sin(ang)) * lerpf(9.0, 22.0, rng.randf()))
			extras.append(list)
		var assign := _voronoi(w, warped, biomes, anchors, extras)
		_cleanup_regions(w, assign, biomes.size())
		if _topology_ok(w, assign, biomes):
			for i in n:
				w.biome[i] = biomes[assign[i]].id
			return true
	return false


func _pick_anchors(w: WorldData, biomes: Array[BiomeData], rng: WorldRng, q30: float, q70: float) -> PackedInt32Array:
	var n := w.size()
	var anchors := PackedInt32Array()
	anchors.resize(biomes.size())
	anchors.fill(-1)
	var top := -1
	for k in biomes.size():
		if biomes[k].tier == 3:
			anchors[k] = rng.below(n)
			if top == -1:
				top = anchors[k]
	for k in biomes.size():
		if biomes[k].tier != 1:
			continue
		if top == -1:
			anchors[k] = rng.below(n)
			continue
		var far: Array = []
		for i in n:
			far.append([HexGrid.distance(w.coords[i], w.coords[top]), i])
		far.sort_custom(func(a: Array, b: Array) -> bool:
			return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
		anchors[k] = far[rng.below(maxi(1, n / 5))][1]
	for k in biomes.size():
		if biomes[k].tier != 2:
			continue
		var pool: Array = []
		for i in n:
			var bias := biomes[k].elevation_bias
			if bias > 0.5 and w.relief[i] < q70:
				continue
			if bias < -0.5 and w.elevation[i] > q30:
				continue
			var ok := true
			for a in anchors:
				if a != -1 and HexGrid.distance(w.coords[i], w.coords[a]) < 8:
					ok = false
					break
			if ok:
				pool.append(i)
		if pool.is_empty():
			return PackedInt32Array()
		anchors[k] = pool[rng.below(pool.size())]
	return anchors


func _voronoi(w: WorldData, warped: PackedVector2Array, biomes: Array[BiomeData], anchors: PackedInt32Array, extras: Array) -> PackedInt32Array:
	var n := w.size()
	var kb := biomes.size()
	var share_sum := 0.0
	for b in biomes:
		share_sum += b.region_share
	var offset := PackedFloat32Array()
	offset.resize(kb)
	var apos := PackedVector2Array()
	for k in kb:
		apos.append(HexGrid.to_world(w.coords[anchors[k]]))
	var assign := PackedInt32Array()
	assign.resize(n)
	for iter in 14:
		var counts := PackedInt32Array()
		counts.resize(kb)
		for i in n:
			var best := 0
			var best_d := 1e9
			for k in kb:
				var d := warped[i].distance_to(apos[k]) - offset[k]
				if d < best_d:
					best_d = d
					best = k
			assign[i] = best
			counts[best] += 1
		for k in kb:
			var target := biomes[k].region_share / share_sum * n
			offset[k] += (target - counts[k]) / n * 16.0
	return assign


func _cleanup_regions(w: WorldData, assign: PackedInt32Array, kb: int) -> void:
	var n := w.size()
	var seen := PackedByteArray()
	seen.resize(n)
	var comps: Array = []   # [biome, PackedInt32Array]
	for s in n:
		if seen[s] == 1:
			continue
		var group := PackedInt32Array([s])
		seen[s] = 1
		var head := 0
		while head < group.size():
			var cur := group[head]
			head += 1
			for nb in w.neighbors[cur]:
				if seen[nb] == 0 and assign[nb] == assign[s]:
					seen[nb] = 1
					group.append(nb)
		comps.append([assign[s], group])
	var best := {}
	for c in comps:
		var b: int = c[0]
		var g: PackedInt32Array = c[1]
		if not best.has(b) or g.size() > (best[b] as PackedInt32Array).size():
			best[b] = g
	var orphans := 0
	for c in comps:
		if (best[c[0]] as PackedInt32Array) != (c[1] as PackedInt32Array):
			for i in (c[1] as PackedInt32Array):
				assign[i] = -1
				orphans += 1
	var guard := 0
	while orphans > 0 and guard < 200:
		guard += 1
		var changes: Array = []
		for i in n:
			if assign[i] != -1:
				continue
			var votes := PackedInt32Array()
			votes.resize(kb)
			var any := false
			for nb in w.neighbors[i]:
				if assign[nb] != -1:
					votes[assign[nb]] += 1
					any = true
			if any:
				var pick := 0
				for k in kb:
					if votes[k] > votes[pick]:
						pick = k
				changes.append([i, pick])
		for ch in changes:
			assign[ch[0]] = ch[1]
			orphans -= 1


func _topology_ok(w: WorldData, assign: PackedInt32Array, biomes: Array[BiomeData]) -> bool:
	var kb := biomes.size()
	var area := PackedInt32Array()
	area.resize(kb)
	var adj: Array = []
	for k in kb:
		adj.append({})
	for i in w.size():
		if assign[i] < 0:
			return false
		area[assign[i]] += 1
		for nb in w.neighbors[i]:
			if assign[nb] != assign[i]:
				var edges: Dictionary = adj[assign[i]]
				edges[assign[nb]] = int(edges.get(assign[nb], 0)) + 1
	var tier2 := 0
	for b in biomes:
		if b.tier == 2:
			tier2 += 1
	# Biomes with NPC settlements need room for them: hexes two or more steps from any border.
	var border := PackedByteArray()
	border.resize(w.size())
	for i in w.size():
		for nb in w.neighbors[i]:
			if assign[nb] != assign[i]:
				border[i] = 1
				break
	var interior := PackedInt32Array()
	interior.resize(kb)
	for i in w.size():
		var deep := border[i] == 0 and w.coast_dist[i] >= _p.settlement_coast_distance
		if deep:
			for nb in w.neighbors[i]:
				if border[nb] == 1:
					deep = false
					break
		if deep:
			interior[assign[i]] += 1
	for k in kb:
		if biomes[k].settlements_per_race > 0 and interior[k] < _p.min_settlement_interior:
			return false
		if area[k] < 25:
			return false
		var t2 := 0
		var t1 := 0
		for other: int in (adj[k] as Dictionary).keys():
			if biomes[other].tier == 2 and int((adj[k] as Dictionary)[other]) >= _p.min_border_pairs:
				t2 += 1
			elif biomes[other].tier == 1:
				t1 += 1
		if biomes[k].tier == 1 and t2 < mini(_p.min_tier2_neighbors, tier2):
			return false
		if biomes[k].tier == 3 and (t1 > 0 or t2 < mini(_p.min_tier2_neighbors, tier2)):
			return false
	return true


# ---------------------------------------------------------------- hydrology

## Returns {"river": PackedByteArray, "lake": PackedByteArray}.
## Rivers rise at a spring (never near the sea) or flow out of a lake, and end at the sea or in a
## lake. A lake touches only the river flowing in and the river flowing out, with a gap between
## their end hexes. Rivers are at least two hexes long.
func _stage_hydrology(w: WorldData) -> Dictionary:
	var n := w.size()
	var s := WorldHash.sub(_base, "hydrology")
	var level := PackedInt32Array()
	level.resize(n)
	for i in n:
		var jitter := WorldHash.unit(WorldHash.hash2(s, w.coords[i].x, w.coords[i].y)) * 0.01
		level[i] = clampi(int((w.elevation[i] + jitter) * 9000.0), 0, 9999)
	var filled := level.duplicate()
	var visited := PackedByteArray()
	visited.resize(n)
	var buckets: Array = []
	for b in 10000:
		buckets.append([])
	for i in n:
		if w.neighbors[i].size() < 6:
			visited[i] = 1
			buckets[level[i]].append(i)
	var order := PackedInt32Array()
	var cur := 0
	while cur < 10000:
		var bucket: Array = buckets[cur]
		if bucket.is_empty():
			cur += 1
			continue
		var i: int = bucket.pop_back()
		order.append(i)
		for nb in w.neighbors[i]:
			if visited[nb] == 1:
				continue
			visited[nb] = 1
			filled[nb] = maxi(level[nb], filled[i])
			w.flow_to[nb] = i
			buckets[filled[nb]].append(nb)
	var acc := PackedInt32Array()
	acc.resize(n)
	acc.fill(1)
	for k in range(order.size() - 1, -1, -1):
		var i := order[k]
		var f := w.flow_to[i]
		if f >= 0:
			acc[f] += acc[i]
	var ranked: Array = []
	for i in n:
		ranked.append(i)
	ranked.sort_custom(func(a: int, b: int) -> bool:
		return acc[a] > acc[b] if acc[a] != acc[b] else a < b)
	var river := PackedByteArray()
	river.resize(n)
	var lake_target := 0.0
	# Each biome gets its own rivers (its share of the top flows), followed downstream to the sea.
	for b in _biome_list():
		var area := w.biome_hexes(b.id).size()
		lake_target += b.weight_of("lake") * area / 100.0
		var quota := int(round(b.weight_of("river") * area / 100.0 * _p.river_oversample))
		for i: int in ranked:
			if quota <= 0:
				break
			if w.biome[i] == b.id and river[i] == 0:
				_mark_downstream(w, river, i)
				quota -= 1
	# Lake candidates: the deepest hollows. Most are thrown out again by the rules below.
	var lake := PackedByteArray()
	lake.resize(n)
	var pits: Array = []
	for i in n:
		var depth := filled[i] - level[i]
		if depth >= 3:
			pits.append([depth, i])
	pits.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	for k in mini(int(round(lake_target * _p.lake_oversample)), pits.size()):
		lake[pits[k][1]] = 1
	var depth_of := PackedInt32Array()
	depth_of.resize(n)
	for i in n:
		depth_of[i] = filled[i] - level[i]
	# Every lake gets an outflow river.
	for i in n:
		if lake[i] == 1:
			var out := w.flow_to[i]
			if out != -1 and lake[out] == 0:
				_mark_downstream(w, river, out)
	for round_index in 16:
		var changed := _trim_rivers(w, river, lake)
		if _limit_river_degree(w, river, lake, acc):
			changed = true
		if _validate_lakes(w, river, lake):
			changed = true
		if not changed:
			changed = _cap_lakes(w, lake, depth_of, int(round(lake_target)))
		if not changed:
			break
	# River heads: a spring for the ones that start on land, none where a lake feeds the river.
	for i in n:
		w.river_source[i] = 0
		if river[i] != 1 or lake[i] == 1 or _river_upstream(w, river, lake, i) > 0:
			continue
		var fed := false
		for nb in w.neighbors[i]:
			if lake[nb] == 1 and w.flow_to[nb] == i:
				fed = true
		w.river_source[i] = 2 if fed else 1
	return {"river": river, "lake": lake}


## No river hex may touch more than `river_max_neighbors` other river hexes (no confluences, no
## rivers running side by side). The weaker neighbour, with everything upstream of it, is dropped.
func _limit_river_degree(w: WorldData, river: PackedByteArray, lake: PackedByteArray, acc: PackedInt32Array) -> bool:
	var changed := false
	var again := true
	while again:
		again = false
		for i in w.size():
			if not _is_river(river, lake, i):
				continue
			var near: Array = []
			for nb in w.neighbors[i]:
				if _is_river(river, lake, nb):
					near.append(nb)
			if near.size() <= _p.river_max_neighbors:
				continue
			var weakest := -1
			for nb: int in near:
				if nb == w.flow_to[i] and near.size() > 1:
					continue
				if weakest == -1 or acc[nb] < acc[weakest] or (acc[nb] == acc[weakest] and nb < weakest):
					weakest = nb
			_remove_upstream(w, river, lake, weakest)
			again = true
			changed = true
	return changed


func _remove_upstream(w: WorldData, river: PackedByteArray, lake: PackedByteArray, start: int) -> void:
	var stack: Array[int] = [start]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		if not _is_river(river, lake, cur):
			continue
		river[cur] = 0
		for nb in w.neighbors[cur]:
			if w.flow_to[nb] == cur:
				stack.append(nb)


func _mark_downstream(w: WorldData, river: PackedByteArray, start: int) -> void:
	var cur := start
	while cur != -1 and river[cur] == 0:
		river[cur] = 1
		cur = w.flow_to[cur]


func _is_river(river: PackedByteArray, lake: PackedByteArray, i: int) -> bool:
	return river[i] == 1 and lake[i] == 0


func _river_upstream(w: WorldData, river: PackedByteArray, lake: PackedByteArray, i: int) -> int:
	var count := 0
	for nb in w.neighbors[i]:
		if w.flow_to[nb] == i and _is_river(river, lake, nb):
			count += 1
	return count


## Removes river sources too close to the sea and branches shorter than the minimum length.
func _trim_rivers(w: WorldData, river: PackedByteArray, lake: PackedByteArray) -> bool:
	var changed := false
	var again := true
	while again:
		again = false
		for i in w.size():
			if not _is_river(river, lake, i) or _river_upstream(w, river, lake, i) > 0:
				continue
			var fed := false
			for nb in w.neighbors[i]:
				if lake[nb] == 1 and w.flow_to[nb] == i:
					fed = true
			if not fed and w.coast_dist[i] < _p.spring_min_coast:
				river[i] = 0
				again = true
				changed = true
				continue
			var branch: Array[int] = [i]
			var next := w.flow_to[i]
			while next != -1 and _is_river(river, lake, next) and _river_upstream(w, river, lake, next) == 1:
				branch.append(next)
				next = w.flow_to[next]
			if branch.size() < _p.river_min_length:
				for h in branch:
					river[h] = 0
				again = true
				changed = true
	return changed


func _lake_components(w: WorldData, lake: PackedByteArray) -> Array:
	var seen := PackedByteArray()
	seen.resize(w.size())
	var comps: Array = []
	for s in w.size():
		if lake[s] == 0 or seen[s] == 1:
			continue
		var group := PackedInt32Array([s])
		seen[s] = 1
		var head := 0
		while head < group.size():
			var cur := group[head]
			head += 1
			for nb in w.neighbors[cur]:
				if lake[nb] == 1 and seen[nb] == 0:
					seen[nb] = 1
					group.append(nb)
		comps.append(group)
	return comps


## Dissolves every lake that breaks a rule: it must keep off the coast, have an outflow river,
## touch no river except those flowing in and out, and keep a gap between inflow and outflow.
func _validate_lakes(w: WorldData, river: PackedByteArray, lake: PackedByteArray) -> bool:
	var changed := false
	for comp: PackedInt32Array in _lake_components(w, lake):
		var members := {}
		for c in comp:
			members[c] = true
		var ok := true
		var outflows := {}
		var touching := {}
		for c in comp:
			if w.coast_dist[c] < _p.lake_min_coast:
				ok = false
			var out := w.flow_to[c]
			if out != -1 and not members.has(out):
				if _is_river(river, lake, out):
					outflows[out] = true
				else:
					ok = false
			for nb in w.neighbors[c]:
				if not members.has(nb) and _is_river(river, lake, nb):
					touching[nb] = true
		if outflows.size() != 1:
			ok = false
		var inflows: Array = []
		for r: int in touching.keys():
			if members.has(w.flow_to[r]):
				inflows.append(r)
			elif not outflows.has(r):
				ok = false
		if ok:
			for e: int in inflows:
				for o: int in outflows.keys():
					if HexGrid.distance(w.coords[e], w.coords[o]) < _p.lake_min_gap:
						ok = false
		if not ok:
			for c in comp:
				lake[c] = 0
			changed = true
	return changed


## Keeps only the deepest lakes once there are enough of them.
func _cap_lakes(w: WorldData, lake: PackedByteArray, depth_of: PackedInt32Array, target_hexes: int) -> bool:
	var comps := _lake_components(w, lake)
	var total := 0
	for comp: PackedInt32Array in comps:
		total += comp.size()
	if total <= target_hexes:
		return false
	comps.sort_custom(func(a: PackedInt32Array, b: PackedInt32Array) -> bool:
		var da := 0
		var db := 0
		for c in a:
			da = maxi(da, depth_of[c])
		for c in b:
			db = maxi(db, depth_of[c])
		return da < db if da != db else a[0] > b[0])
	var changed := false
	for comp: PackedInt32Array in comps:
		if total - comp.size() < target_hexes:
			continue
		for c in comp:
			lake[c] = 0
		total -= comp.size()
		changed = true
		if total <= target_hexes:
			break
	return changed


# ---------------------------------------------------------------- terrain

func _stage_terrain(w: WorldData, water: Dictionary) -> void:
	var river: PackedByteArray = water["river"]
	var lake: PackedByteArray = water["lake"]
	for b in _biome_list():
		var hexes := w.biome_hexes(b.id)
		var total := hexes.size()
		var rest: Array = []
		for i in hexes:
			if lake[i] == 1:
				w.terrain[i] = "lake"
			elif river[i] == 1:
				w.terrain[i] = "river"
			else:
				rest.append(i)
		rest.sort_custom(func(x: int, y: int) -> bool:
			var ex := w.relief[x]
			var ey := w.relief[y]
			return ex > ey if ex != ey else x < y)
		var mountain_q := mini(int(round(b.weight_of("mountain") * total / 100.0)), rest.size())
		for k in mountain_q:
			w.terrain[rest[k]] = "mountain"
		var hills_q := mini(int(round(b.weight_of("hills") * total / 100.0)), rest.size() - mountain_q)
		for k in hills_q:
			w.terrain[rest[mountain_q + k]] = "hills"
		var left: Array = rest.slice(mountain_q + hills_q)
		left.sort_custom(func(x: int, y: int) -> bool:
			var mx := w.moisture[x]
			var my := w.moisture[y]
			return mx < my if mx != my else x < y)
		var kinds: Array = []
		for kind in ["grass", "forest", "wyrd_forest", "marsh"]:
			if b.weight_of(kind) > 0.0:
				kinds.append(kind)
		var weight_sum := 0.0
		var biggest := 0
		for k in kinds.size():
			weight_sum += b.weight_of(kinds[k])
			if b.weight_of(kinds[k]) > b.weight_of(kinds[biggest]):
				biggest = k
		var counts: Array = []
		var assigned := 0
		for k in kinds.size():
			var cnt := int(floor(left.size() * b.weight_of(kinds[k]) / weight_sum))
			counts.append(cnt)
			assigned += cnt
		if not counts.is_empty():
			counts[biggest] += left.size() - assigned
		var pos := 0
		for k in kinds.size():
			for m in counts[k]:
				w.terrain[left[pos]] = kinds[k]
				pos += 1
	_shape_mountains(w)
	_apply_ap(w)


## Keeps mountains as chains: a lone peak or the fat core of a cluster becomes hills.
func _shape_mountains(w: WorldData) -> void:
	var change: Array[int] = []
	for i in w.size():
		if w.terrain[i] != "mountain":
			continue
		var links := 0
		for nb in w.neighbors[i]:
			if w.terrain[nb] == "mountain":
				links += 1
		if links == 0 or links >= 4:
			change.append(i)
	for i in change:
		w.terrain[i] = "hills"


# ---------------------------------------------------------------- connectivity

func _carve_cost(w: WorldData, i: int) -> int:
	return w.ap[i] if w.ap[i] >= 0 else (8 if w.terrain[i] == "lake" else 6)


## Joins stray walkable pockets to the main land by opening the cheapest way through
## mountains (to hills) and lakes (to marsh).
func _connect_components(w: WorldData) -> void:
	for guard in 40:
		var comps := WorldPathing.components(w)
		if comps.size() <= 1:
			return
		var main := {}
		for i in comps[0]:
			main[i] = true
		var n := w.size()
		var dist := PackedInt32Array()
		dist.resize(n)
		dist.fill(-1)
		var prev := PackedInt32Array()
		prev.resize(n)
		prev.fill(-1)
		var buckets: Array = [[]]
		for i in comps[1]:
			dist[i] = 0
			buckets[0].append(i)
		var c := 0
		var goal := -1
		while c < buckets.size() and goal == -1:
			for i: int in buckets[c]:
				if dist[i] != c:
					continue
				if main.has(i):
					goal = i
					break
				for nb in w.neighbors[i]:
					var nc := c + _carve_cost(w, nb)
					if dist[nb] == -1 or nc < dist[nb]:
						dist[nb] = nc
						prev[nb] = i
						while buckets.size() <= nc:
							buckets.append([])
						buckets[nc].append(nb)
			c += 1
		var cur := goal
		while cur != -1:
			if w.ap[cur] < 0:
				w.terrain[cur] = "marsh" if w.terrain[cur] == "lake" else "hills"
			cur = prev[cur]
		_apply_ap(w)


## Every pair of neighbouring biomes gets at least two walkable crossings.
func _ensure_crossings(w: WorldData) -> void:
	var border := WorldValidator.border_pairs(w)
	for key: String in border.keys():
		var pairs: Array = border[key]
		var used := {}
		var crossings := 0
		for pair: Array in pairs:
			if w.passable(pair[0]) and w.passable(pair[1]):
				used[pair] = true
				crossings += 1
		var guard := 0
		while crossings < 2 and guard < 20:
			guard += 1
			var best: Array = []
			var best_blocked := 3
			for pair: Array in pairs:
				if used.has(pair):
					continue
				var blocked := int(not w.passable(pair[0])) + int(not w.passable(pair[1]))
				if blocked == 2:
					continue
				if blocked < best_blocked:
					best_blocked = blocked
					best = pair
			if best.is_empty():
				break
			for i: int in best:
				if not w.passable(i):
					w.terrain[i] = "marsh" if w.terrain[i] == "lake" else "hills"
			_apply_ap(w)
			used[best] = true
			crossings += 1


# ---------------------------------------------------------------- nodes

## Every biome gets a resource budget (nodes per 100 walkable hexes) for food, tier 1 materials and
## its own tier 2/3 materials. Nodes go where they are furthest from their neighbours, so resources
## spread evenly instead of piling up where the terrain happens to be eligible.
func _stage_nodes(w: WorldData) -> void:
	_place_springs(w)
	var spots := {}   # Vector2i -> node id, for spacing
	for b in _biome_list():
		var walk := 0
		for i in w.biome_hexes(b.id):
			if w.passable(i):
				walk += 1
		var rng := WorldRng.new(WorldHash.sub(_base, "nodes/" + b.id))
		_place_group(w, b, "food", int(round(b.food_per_100 * walk / 100.0)), rng, spots)
		_place_group(w, b, "material", int(round(b.material_per_100 * walk / 100.0)), rng, spots)
		_place_group(w, b, "signature", int(round(b.signature_per_100 * walk / 100.0)), rng, spots)
		_place_group(w, b, "signature_food", int(round(b.signature_per_100 * _p.signature_food_share * walk / 100.0)), rng, spots)
	_place_sea_nodes(w, spots)


func _group_defs(b: BiomeData, group: String) -> Array:
	var out: Array = []
	for id in _sorted_ids(_db.nodes):
		var def: ResourceNodeData = _db.nodes[id]
		if def.density <= 0.0 or def.category == "water":
			continue
		if not def.biomes.is_empty() and not (b.id in def.biomes):
			continue
		var in_group := false
		match group:
			"food":
				in_group = def.category == "food" and def.tier == 1
			"signature_food":
				in_group = def.category == "food" and def.tier >= 2
			"material":
				in_group = def.category == "material" and def.tier == 1
			"signature":
				in_group = def.category == "material" and def.tier >= 2
		if in_group:
			out.append(def)
	return out


func _place_group(w: WorldData, b: BiomeData, group: String, budget: int, rng: WorldRng, spots: Dictionary) -> void:
	var defs := _group_defs(b, group)
	var pools := {}
	for def: ResourceNodeData in defs:
		var list: Array = []
		for i in w.biome_hexes(b.id):
			if w.node[i] != "" or not (w.terrain[i] in def.terrains):
				continue
			if def.needs_adjacent_terrain != "":
				var touches := false
				for nb in w.neighbors[i]:
					if w.terrain[nb] == def.needs_adjacent_terrain:
						touches = true
						break
				if not touches:
					continue
			list.append(i)
		rng.shuffle(list)
		pools[def.id] = list
	var picks := {}
	var cap := maxi(2, int(ceil(budget * 0.5)))
	for k in budget:
		var total := 0.0
		for def: ResourceNodeData in defs:
			if not (pools[def.id] as Array).is_empty() and (int(picks.get(def.id, 0)) < cap or defs.size() == 1):
				total += def.density
		if total <= 0.0:
			return
		var roll := rng.randf() * total
		var chosen: ResourceNodeData = null
		for def: ResourceNodeData in defs:
			if (pools[def.id] as Array).is_empty() or (int(picks.get(def.id, 0)) >= cap and defs.size() > 1):
				continue
			chosen = def
			roll -= def.density
			if roll <= 0.0:
				break
		var pool: Array = pools[chosen.id]
		# Best of a few random candidates: the one furthest from other nodes.
		var best := -1
		var best_score := -1.0
		for t in mini(10, pool.size()):
			var i: int = pool[pool.size() - 1 - t]
			if w.node[i] != "":
				continue
			var score := _spread_score(w.coords[i], chosen.id, spots) + rng.randf() * 0.01
			if score > best_score:
				best_score = score
				best = i
		if best == -1:
			pool.clear()
			continue
		pool.erase(best)
		w.node[best] = chosen.id
		spots[w.coords[best]] = chosen.id
		picks[chosen.id] = int(picks.get(chosen.id, 0)) + 1


## Higher = further from other nodes, and from nodes of the same kind in particular.
func _spread_score(c: Vector2i, id: String, spots: Dictionary) -> float:
	var any := 4
	var same := 5
	for d in HexGrid.disc(c, 4):
		if not spots.has(d):
			continue
		var dist := HexGrid.distance(c, d)
		any = mini(any, dist)
		if spots[d] == id:
			same = mini(same, dist)
	return float(same) * 2.0 + float(any)


## Fish on the shore sea, spread out like everything else.
func _place_sea_nodes(w: WorldData, spots: Dictionary) -> void:
	for id in _sorted_ids(_db.nodes):
		var def: ResourceNodeData = _db.nodes[id]
		var sea: Array = _sea_cells(w, def)
		if def.density <= 0.0 or sea.is_empty():
			continue
		var rng := WorldRng.new(WorldHash.sub(_base, "sea/" + id))
		rng.shuffle(sea)
		var count := int(round(sea.size() * _p.sea_node_share))
		for k in count:
			if sea.is_empty():
				break
			var best := -1
			var best_score := -1.0
			for t in mini(10, sea.size()):
				var c: Vector2i = sea[sea.size() - 1 - t]
				var score := _spread_score(c, id, spots) + rng.randf() * 0.01
				if score > best_score:
					best_score = score
					best = sea.size() - 1 - t
			var spot: Vector2i = sea[best]
			sea.remove_at(best)
			w.sea_node[spot] = id
			spots[spot] = id


## Shore sea hexes (up to `sea_fish_max_shore` from land) a node may sit on, when its terrains
## include the ocean. Sorted so the result does not depend on dictionary order.
func _sea_cells(w: WorldData, def: ResourceNodeData) -> Array:
	if not ("ocean" in def.terrains):
		return []
	var seen := {}
	for c in w.coords:
		for d in HexGrid.disc(c, _p.sea_fish_max_shore):
			if not w.has_coord(d):
				seen[d] = true
	var cells: Array = seen.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y)
	return cells


## Every spring sits on a river hex, at the head of the river.
func _place_springs(w: WorldData) -> void:
	if not _db.nodes.has("spring"):
		return
	for i in w.size():
		if w.river_source[i] == 1 and w.terrain[i] == "river" and w.node[i] == "":
			w.node[i] = "spring"


# ---------------------------------------------------------------- settlements

func _has_node_category(w: WorldData, hexes: PackedInt32Array, category: String) -> bool:
	for j in hexes:
		if w.node[j] != "":
			var def: ResourceNodeData = _db.nodes.get(w.node[j])
			if def != null and def.category == category:
				return true
	return false


## Hexes between each hex and the nearest hex of another biome (0 on the border itself).
func _border_distance(w: WorldData) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w.size())
	dist.fill(-1)
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
			if dist[nb] == -1 and w.biome[nb] == w.biome[cur]:
				dist[nb] = dist[cur] + 1
				queue.append(nb)
	for i in w.size():
		if dist[i] == -1:
			dist[i] = 99
	return dist


## Each race native to a biome gets `settlements_per_race` NPC settlements in it, away from the
## biome's border, each with fresh water, food and a material inside its 2 rings.
func _stage_settlements(w: WorldData) -> void:
	var counter := 0
	var border_dist := _border_distance(w)
	for b in _biome_list():
		if b.settlements_per_race <= 0:
			continue
		var races: Array = []
		for r: RaceData in _db.races.values():
			if r.native_biome == b.display_name:
				races.append(r.id)
		races.sort()
		if races.is_empty():
			continue
		var want: int = races.size() * b.settlements_per_race
		var cands: Array = []
		for i in w.biome_hexes(b.id):
			if not w.passable(i) or w.terrain[i] == "river" or border_dist[i] < _p.settlement_border_distance or w.coast_dist[i] < _p.settlement_coast_distance:
				continue
			cands.append(i)
		var rng := WorldRng.new(WorldHash.sub(_base, "settlements/" + b.id))
		# Sites that stay legal next to the settlements other biomes already placed.
		var open_sites: Array = []
		for c: int in cands:
			var legal := true
			for s: int in w.settlements.keys():
				if HexGrid.distance(w.coords[c], w.coords[s]) < _p.npc_settlement_spacing:
					legal = false
					break
			if legal:
				open_sites.append(c)
		var placed := 0
		for round_index in 4:
			if placed >= want or open_sites.is_empty():
				break
			var chosen := _pick_sites(w, open_sites, want - placed, rng)
			for site: int in chosen:
				open_sites.erase(site)
				if not _ensure_supplies(w, site, rng):
					continue
				counter += 1
				w.settlements[site] = {"id": "npc_%d" % counter, "biome": b.id, "race": str(races[placed % races.size()])}
				placed += 1
				# Sites too close to the new settlement are no longer open.
				var still: Array = []
				for o: int in open_sites:
					if HexGrid.distance(w.coords[o], w.coords[site]) >= _p.npc_settlement_spacing:
						still.append(o)
				open_sites = still
	_balance_settlements(w)


## Chooses `want` sites at least `npc_settlement_spacing` apart. Each pick is the site that leaves the
## most other sites open, and a few restarts from different
## first picks make sure thin biomes still fit all of them.
func _pick_sites(w: WorldData, sites: Array, want: int, rng: WorldRng) -> Array:
	var best: Array = []
	for restart in 8:
		var remaining: Array = sites.duplicate()
		var picked: Array = []
		for k in want:
			if remaining.is_empty():
				break
			var pick := -1
			if k == 0 and restart > 0:
				pick = remaining[rng.below(remaining.size())]
			else:
				var best_score := -1e9
				for c: int in remaining:
					var room := 0
					for o: int in remaining:
						if o != c and HexGrid.distance(w.coords[c], w.coords[o]) >= _p.npc_settlement_spacing:
							room += 1
					# Open sites count most; among them, inland ones win over the shore.
					var score := float(room) / maxf(remaining.size(), 1.0) + 0.6 * float(mini(w.coast_dist[c], 6)) / 6.0 + rng.randf() * 0.01
					if score > best_score:
						best_score = score
						pick = c
			picked.append(pick)
			var next: Array = []
			for o: int in remaining:
				if HexGrid.distance(w.coords[pick], w.coords[o]) >= _p.npc_settlement_spacing:
					next.append(o)
			remaining = next
		if picked.size() > best.size():
			best = picked
		if best.size() >= want:
			break
	return best


## Makes sure the 2-ring area around a settlement site holds food and a material, adding a node
## of the missing kind on a free hex when it has none. False if that is not possible.
func _ensure_supplies(w: WorldData, site: int, rng: WorldRng) -> bool:
	var area := w.disc_indices(site, _p.settlement_range)
	for category in ["food", "material"]:
		if _has_node_category(w, area, category):
			continue
		var options: Array = []
		for id in _sorted_ids(_db.nodes):
			var def: ResourceNodeData = _db.nodes[id]
			if def.category != category or def.density <= 0.0 or def.tier != 1:
				continue
			for j in area:
				if w.node[j] != "" or w.settlements.has(j) or not (w.terrain[j] in def.terrains):
					continue
				if not def.biomes.is_empty() and not (w.biome[j] in def.biomes):
					continue
				options.append([id, j])
		if options.is_empty():
			return false
		var chosen: Array = options[rng.below(options.size())]
		w.node[chosen[1]] = chosen[0]
	return true


## Every NPC settlement reaches the same amount of resources: food and materials inside their bands,
## at least one tier 1 material and, where the biome has one, a tier 2 material. Surplus nodes in the
## 2 rings are taken away (the most common kind first) and missing ones are added on free hexes.
## Reaches of two NPC settlements never overlap, so settlements do not take from each other.
func _balance_settlements(w: WorldData) -> void:
	var ids: Array = w.settlements.keys()
	ids.sort()
	for site: int in ids:
		var rng := WorldRng.new(WorldHash.sub(_base, "balance/%d" % site))
		var biome_id: String = w.settlements[site]["biome"]
		for pass_index in 2:
			for category in ["food", "material"]:
				var max_count: int = _p.settlement_food_max if category == "food" else _p.settlement_material_max
				var min_count: int = _p.settlement_food_min if category == "food" else _p.settlement_material_min
				while _reach_slots(w, site, category) > max_count:
					if not _remove_surplus(w, site, category, rng):
						break
				while _reach_slots(w, site, category) < min_count:
					if not _add_node(w, site, category, biome_id, rng):
						break
			# Tier coverage for materials.
			if not _has_tier(w, site, 1):
				_add_node(w, site, "material", biome_id, rng, 1)
			if _biome_has_tier2(biome_id) and not _has_tier(w, site, 2):
				_add_node(w, site, "material", biome_id, rng, 2)


## [{id, coord}] of the nodes of one category inside the settlement's reach.
func _reach_nodes(w: WorldData, site: int, category: String) -> Array:
	var out: Array = []
	for entry: Dictionary in WorldReach.nodes_in(w, site, _p.settlement_range):
		var def: ResourceNodeData = _db.nodes.get(entry["id"])
		if def != null and def.category == category:
			out.append(entry)
	return out


## Slots of a category inside the reach: nodes, plus one for fresh water when it counts as food.
func _reach_slots(w: WorldData, site: int, category: String) -> int:
	var count := _reach_nodes(w, site, category).size()
	if category == "food" and int(WorldReach.summarize(w, _db, site, _p.settlement_range)["water"]) > 0:
		count += 1
	return count


func _has_tier(w: WorldData, site: int, tier: int) -> bool:
	for entry: Dictionary in _reach_nodes(w, site, "material"):
		if (_db.nodes[entry["id"]] as ResourceNodeData).tier == tier:
			return true
	return false


func _biome_has_tier2(biome_id: String) -> bool:
	for def: ResourceNodeData in _db.nodes.values():
		if def.category == "material" and def.tier == 2 and def.density > 0.0 and biome_id in def.biomes:
			return true
	return false


func _remove_surplus(w: WorldData, site: int, category: String, rng: WorldRng) -> bool:
	var entries := _reach_nodes(w, site, category)
	var count := {}
	var tier_count := {}
	for e: Dictionary in entries:
		count[e["id"]] = int(count.get(e["id"], 0)) + 1
		var tier: int = (_db.nodes[e["id"]] as ResourceNodeData).tier
		tier_count[tier] = int(tier_count.get(tier, 0)) + 1
	var pool: Array = []
	var top := 0
	for e: Dictionary in entries:
		var tier: int = (_db.nodes[e["id"]] as ResourceNodeData).tier
		# Never remove the last node of a tier a material settlement needs.
		if category == "material" and (tier == 1 or tier == 2) and int(tier_count[tier]) <= 1:
			continue
		var c: int = count[e["id"]]
		if c > top:
			top = c
			pool.clear()
		if c == top:
			pool.append(e)
	if pool.is_empty():
		return false
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Vector2i = a["coord"]
		var cb: Vector2i = b["coord"]
		return ca.x < cb.x if ca.x != cb.x else ca.y < cb.y)
	var pick: Dictionary = pool[rng.below(pool.size())]
	var j := w.idx(pick["coord"])
	if j >= 0:
		w.node[j] = ""
	else:
		w.sea_node.erase(pick["coord"])
	return true


## Adds one node of `category` on a free hex of the settlement's reach. Kinds the settlement has the
## fewest of come first. `tier` limits materials to one tier (0 = any tier the biome offers).
func _add_node(w: WorldData, site: int, category: String, biome_id: String, rng: WorldRng, tier: int = 0) -> bool:
	var have := {}
	for e: Dictionary in _reach_nodes(w, site, category):
		have[e["id"]] = int(have.get(e["id"], 0)) + 1
	var by_id := {}
	for c in HexGrid.disc(w.coords[site], _p.settlement_range):
		var j := w.idx(c)
		for id in _sorted_ids(_db.nodes):
			var def: ResourceNodeData = _db.nodes[id]
			if def.category != category or def.density <= 0.0:
				continue
			if def.tier == 3 or (category == "food" and def.tier != 1) or (category == "material" and tier != 0 and def.tier != tier):
				continue
			if not def.biomes.is_empty() and not (biome_id in def.biomes):
				continue
			if j >= 0:
				if w.node[j] != "" or w.settlements.has(j) or not (w.terrain[j] in def.terrains):
					continue
				if def.needs_adjacent_terrain != "":
					var touches := false
					for nb in w.neighbors[j]:
						if w.terrain[nb] == def.needs_adjacent_terrain:
							touches = true
					if not touches:
						continue
			else:
				if w.sea_node.has(c) or not ("ocean" in def.terrains) or not _near_land(w, c):
					continue
			if not by_id.has(id):
				by_id[id] = []
			(by_id[id] as Array).append(c)
	if by_id.is_empty():
		return false
	var fewest := 99
	for id: String in by_id.keys():
		fewest = mini(fewest, int(have.get(id, 0)))
	var kinds: Array = []
	for id: String in _sorted_ids(by_id):
		if int(have.get(id, 0)) == fewest:
			kinds.append(id)
	var kind: String = kinds[rng.below(kinds.size())]
	var spots: Array = by_id[kind]
	var spot: Vector2i = spots[rng.below(spots.size())]
	var idx := w.idx(spot)
	if idx >= 0:
		w.node[idx] = kind
	else:
		w.sea_node[spot] = kind
	return true


func _near_land(w: WorldData, c: Vector2i) -> bool:
	for d in HexGrid.disc(c, _p.sea_fish_max_shore):
		if w.has_coord(d):
			return true
	return false


# ---------------------------------------------------------------- starts

func _stage_starts(w: WorldData) -> void:
	var camp := PackedByteArray()
	camp.resize(w.size())
	for i in w.size():
		if not w.passable(i):
			continue
		if int(WorldReach.summarize(w, _db, i, _p.settlement_range)["food_slots"]) >= _p.start_food_slots_min:
			camp[i] = 1
	for b in _biome_list():
		if not b.start_allowed:
			continue
		var hexes: Array = []
		for i in w.biome_hexes(b.id):
			if w.passable(i) and not w.settlements.has(i) and w.terrain[i] != "river":
				hexes.append(i)
		var rng := WorldRng.new(WorldHash.sub(_base, "starts/" + b.id))
		rng.shuffle(hexes)
		for i: int in hexes:
			if WorldValidator.start_is_valid(w, i, camp, _p):
				w.starts[b.id] = i
				break


# ---------------------------------------------------------------- locations

func _stage_locations(w: WorldData) -> void:
	var biome_by_id := {}
	for b in _biome_list():
		biome_by_id[b.id] = b
	var start_hexes := {}
	for s in w.starts.values():
		start_hexes[s] = true
	for id in _sorted_ids(_db.locations):
		var def: LocationData = _db.locations[id]
		var eligible: Array = []
		for i in w.size():
			if not w.passable(i) or w.location[i] != "" or w.settlements.has(i) or start_hexes.has(i):
				continue
			if not (w.terrain[i] in def.terrains):
				continue
			if not def.biomes.is_empty() and not (w.biome[i] in def.biomes):
				continue
			eligible.append(i)
		var rng := WorldRng.new(WorldHash.sub(_base, "locations/" + id))
		rng.shuffle(eligible)
		var expected := def.density * eligible.size() / 100.0
		var count := int(floor(expected))
		if rng.randf() < expected - count:
			count += 1
		var placed: Array[int] = []
		for i: int in eligible:
			if placed.size() >= count:
				break
			var clear := true
			for other in placed:
				if HexGrid.distance(w.coords[i], w.coords[other]) < def.spacing:
					clear = false
					break
			if not clear:
				continue
			placed.append(i)
			w.location[i] = id
			w.location_danger[i] = (biome_by_id[w.biome[i]] as BiomeData).danger_floor
