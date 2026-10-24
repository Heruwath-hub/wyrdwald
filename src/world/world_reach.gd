class_name WorldReach
extends RefCounted
## What a camp (1 ring) or settlement (2 rings) standing on a hex can reach. Shared by the
## generator's balancing, the validator and the map UI.
##
## Fresh water is a food resource: every river hex inside the reach is one slot of the kind
## "fresh_water" (tier 1, food family). Springs only mark where a river rises.

const WATER := "fresh_water"


## Every node inside `rings` of `center`: [{id, coord}]. Includes fish on the shore sea.
static func nodes_in(w: WorldData, center: int, rings: int) -> Array:
	var out: Array = []
	for c in HexGrid.disc(w.coords[center], rings):
		var j := w.idx(c)
		if j >= 0:
			if w.node[j] != "":
				out.append({"id": w.node[j], "coord": c})
		elif w.sea_node.has(c):
			out.append({"id": w.sea_node[c], "coord": c})
	return out


## Every resource slot inside the reach: [{kind, category, tier, coord}]. Nodes and river hexes
## each fill one slot; springs are not a slot of their own.
static func resource_entries(w: WorldData, db: Variant, center: int, rings: int) -> Array:
	var out: Array = []
	for entry: Dictionary in nodes_in(w, center, rings):
		var def: ResourceNodeData = db.nodes.get(entry["id"])
		if def == null or def.category == "water":
			continue
		out.append({"kind": entry["id"], "category": def.category, "tier": def.tier, "coord": entry["coord"]})
	for c in HexGrid.disc(w.coords[center], rings):
		var j := w.idx(c)
		if j >= 0 and w.terrain[j] == "river":
			out.append({"kind": WATER, "category": "food", "tier": 1, "coord": c})
	return out


## Counts by category plus the per-kind counts.
## food = food nodes, water = river hexes, food_slots = food nodes + 1 when any river is in reach
## (water is one more kind of food), material = material nodes.
static func summarize(w: WorldData, db: Variant, center: int, rings: int) -> Dictionary:
	var food := 0
	var material := 0
	var water := 0
	var by_id := {}
	for e: Dictionary in resource_entries(w, db, center, rings):
		by_id[e["kind"]] = int(by_id.get(e["kind"], 0)) + 1
		if e["kind"] == WATER:
			water += 1
		elif e["category"] == "food":
			food += 1
		elif e["category"] == "material":
			material += 1
	return {"food": food, "material": material, "water": water,
			"food_slots": food + (1 if water > 0 else 0), "total": food + material, "by_id": by_id}


## Value of one resource kind that fills `slots` slots: the first slot is worth `weight`, every
## further slot a bit less than the one before it, so variety beats quantity.
static func kind_value(weight: float, slots: int, p: WorldParams) -> float:
	if slots <= 0:
		return 0.0
	return weight * (1.0 + p.slot_bonus * 2.0 * (1.0 - pow(0.5, slots - 1)))


## Hexes (coords, sea included) inside the reach of any NPC settlement.
static func npc_claimed(w: WorldData, rings: int) -> Dictionary:
	var out := {}
	for s: int in w.settlements.keys():
		for c in HexGrid.disc(w.coords[s], rings):
			out[c] = true
	return out


## Whether and how well a player settlement could stand on hex `h`.
## Slots inside an NPC settlement's reach are contested and do not count.
## ok needs: a walkable non-river hex, no settlement, a centre outside every NPC reach, and at
## least one free food slot (fresh water counts) and one free material slot.
## score = value of every kind (tier weighted, diminishing per extra slot) + a morale bonus for
## each food kind beyond the first.
static func build_info(w: WorldData, db: Variant, p: WorldParams, h: int, claimed: Dictionary) -> Dictionary:
	var info := {"ok": false, "reason": "", "food": 0, "material": 0, "water": 0, "score": 0.0,
			"kinds_food": 0, "kinds_material": 0, "shared_food": 0, "shared_material": 0}
	if not w.passable(h) or w.terrain[h] == "river":
		info["reason"] = "not a building site"
		return info
	if w.settlements.has(h):
		info["reason"] = "settlement"
		return info
	for s: int in w.settlements.keys():
		if HexGrid.distance(w.coords[s], w.coords[h]) < p.player_npc_distance:
			info["reason"] = "too close to an NPC settlement"
			return info
	var slots := {}   # kind -> [slots, weight, is_food]
	for e: Dictionary in resource_entries(w, db, h, p.settlement_range):
		if claimed.has(e["coord"]):
			if e["category"] == "food":
				info["shared_food"] += 1
			else:
				info["shared_material"] += 1
			continue
		var weight: float = p.material_tier_value[clampi(e["tier"], 0, p.material_tier_value.size() - 1)]
		var entry: Array = slots.get(e["kind"], [0, weight, e["category"] == "food"])
		entry[0] += 1
		slots[e["kind"]] = entry
		if e["kind"] == WATER:
			info["water"] += 1
		elif e["category"] == "food":
			info["food"] += 1
		else:
			info["material"] += 1
	var score := 0.0
	var food_weight := 0.0
	for kind: String in slots.keys():
		var entry: Array = slots[kind]
		score += kind_value(entry[1], entry[0], p)
		if entry[2]:
			info["kinds_food"] += 1
			food_weight += entry[1]
		else:
			info["kinds_material"] += 1
	score += p.food_variety_bonus * maxf(0.0, food_weight - 1.0)
	info["score"] = score
	if info["food"] + info["water"] < 1:
		info["reason"] = "no free food"
	elif info["material"] < 1:
		info["reason"] = "no free material"
	else:
		info["ok"] = true
	return info


## "Spring x1, Wood x2" style text for the nodes of one category, or "none".
static func describe(w: WorldData, db: Variant, center: int, rings: int, category: String, skip: Dictionary = {}) -> String:
	var counts := {}
	for entry: Dictionary in resource_entries(w, db, center, rings):
		if skip.has(entry["coord"]) or entry["category"] != category:
			continue
		var name := "Fresh water"
		if entry["kind"] != WATER:
			name = (db.nodes[entry["kind"]] as ResourceNodeData).display_name
		counts[name] = int(counts.get(name, 0)) + 1
	if counts.is_empty():
		return "none"
	var keys := counts.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s x%d" % [k, counts[k]])
	return ", ".join(parts)
