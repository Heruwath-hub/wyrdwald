class_name WorldPathing
extends RefCounted
## Least-cost movement over the hex map. The cost of a step is the AP of the hex entered.


## AP cost from `start` to every reachable hex (-1 = unreachable or beyond `limit`).
## `prev` (optional, resized here) receives each hex's predecessor for path building.
static func costs_from(w: WorldData, start: int, limit: int = 1 << 20, prev: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var n := w.size()
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	if prev.size() != n:
		prev.resize(n)
	prev.fill(-1)
	var buckets: Array = [PackedInt32Array([start])]
	dist[start] = 0
	var c := 0
	while c < buckets.size() and c <= limit:
		var bucket: PackedInt32Array = buckets[c]
		for node_idx in bucket:
			if dist[node_idx] != c:
				continue
			for nb in w.neighbors[node_idx]:
				var a := w.ap[nb]
				if a < 0:
					continue
				var nc := c + a
				if nc > limit:
					continue
				if dist[nb] == -1 or nc < dist[nb]:
					dist[nb] = nc
					prev[nb] = node_idx
					while buckets.size() <= nc:
						buckets.append(PackedInt32Array())
					var target: PackedInt32Array = buckets[nc]
					target.append(nb)
					buckets[nc] = target
		c += 1
	return dist


## Hex indices from `from` to `to`, both included. Empty if `to` cannot be reached.
static func path(w: WorldData, from: int, to: int) -> PackedInt32Array:
	var prev := PackedInt32Array()
	var dist := costs_from(w, from, 1 << 20, prev)
	if dist[to] == -1:
		return PackedInt32Array()
	var rev := PackedInt32Array()
	var cur := to
	while cur != -1:
		rev.append(cur)
		cur = prev[cur]
	rev.reverse()
	return rev


static func path_cost(w: WorldData, hexes: PackedInt32Array) -> int:
	var total := 0
	for k in range(1, hexes.size()):
		total += w.ap[hexes[k]]
	return total


## Connected groups of passable hexes, largest first.
static func components(w: WorldData) -> Array[PackedInt32Array]:
	var seen := PackedByteArray()
	seen.resize(w.size())
	var groups: Array[PackedInt32Array] = []
	for s in w.size():
		if seen[s] == 1 or not w.passable(s):
			continue
		var group := PackedInt32Array([s])
		seen[s] = 1
		var head := 0
		while head < group.size():
			var cur := group[head]
			head += 1
			for nb in w.neighbors[cur]:
				if seen[nb] == 0 and w.passable(nb):
					seen[nb] = 1
					group.append(nb)
		groups.append(group)
	groups.sort_custom(func(a: PackedInt32Array, b: PackedInt32Array) -> bool: return a.size() > b.size())
	return groups
