class_name WorldView
extends Node3D
## Draws a WorldData in 3D: one tile per hex, props, resource nodes, locations, settlements,
## and a flat colour overlay for biome / danger / AP. Placeholders are used wherever the asset
## folders (see assets/world/README.md) hold no art yet. Reads data only; never changes it.

const TILE_SIZE := 1.0
const OVERLAY_LIFT := 0.03
const OCEAN_MARGIN := 12

enum Overlay { NONE, BIOME, DANGER, AP, BUILD }

var world: WorldData
var assets := WorldAssets.new()

var _db: Variant
var _tile_root := Node3D.new()
var _ocean_root := Node3D.new()
var _prop_root := Node3D.new()
var _marker_root := Node3D.new()
var _overlay := MeshInstance3D.new()
var _highlight := MeshInstance3D.new()
var _range := MeshInstance3D.new()
var _preview := MeshInstance3D.new()
var _npc_reach := MeshInstance3D.new()
var _path_root := Node3D.new()
var _label_root := Node3D.new()
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _heights: Array[float] = []


func _init() -> void:
	add_child(_tile_root)
	add_child(_ocean_root)
	add_child(_prop_root)
	add_child(_marker_root)
	add_child(_overlay)
	add_child(_path_root)
	add_child(_label_root)
	add_child(_npc_reach)
	add_child(_range)
	add_child(_preview)
	add_child(_highlight)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_overlay.material_override = m
	_range.material_override = m
	_preview.material_override = m
	_npc_reach.material_override = m
	_highlight.mesh = _hex_ring_mesh(1.0, 0.82)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(1, 1, 1, 1)
	hm.no_depth_test = true
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight.material_override = hm
	_highlight.visible = false


func build(w: WorldData, content_db: Variant) -> void:
	world = w
	_db = content_db
	assets = WorldAssets.new()
	for root in [_tile_root, _ocean_root, _prop_root, _marker_root, _path_root]:
		for c in root.get_children():
			c.queue_free()
	_range.mesh = null
	_preview.mesh = null
	_npc_reach.mesh = null
	_heights.clear()
	_build_ocean()
	for i in w.size():
		_heights.append(_terrain_height(w.terrain[i]))
		_build_tile(i)
		_build_props(i)
		_build_markers(i)
	_build_sea_markers()
	set_overlay(Overlay.NONE)


## World position of the top of the tile on hex `i`.
func top_of(i: int) -> Vector3:
	var p := HexGrid.to_world(world.coords[i], TILE_SIZE)
	return Vector3(p.x, _heights[i], p.y)


func hex_at_point(point: Vector3) -> int:
	if world == null:
		return -1
	return world.idx(HexGrid.from_world(Vector2(point.x, point.z), TILE_SIZE))


func show_highlight(i: int) -> void:
	_highlight.visible = i >= 0
	if i >= 0:
		_highlight.position = top_of(i) + Vector3(0, OVERLAY_LIFT * 2.0, 0)


func show_path(route: PackedInt32Array, affordable_steps: int) -> void:
	for c in _path_root.get_children():
		c.queue_free()
	for k in range(1, route.size()):
		var dot := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.12
		mesh.height = 0.24
		dot.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.4, 1.0, 0.5) if k <= affordable_steps else Color(1.0, 0.75, 0.25)
		mat.no_depth_test = true
		dot.material_override = mat
		dot.position = top_of(route[k]) + Vector3(0, 0.15, 0)
		_path_root.add_child(dot)


## Shades the hexes a settlement or camp at `center` can reach: the inner ring and the outer ring
## in different strengths, the centre strongest.
func show_range(center: int, rings: int) -> void:
	if center < 0:
		_range.mesh = null
		return
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for j in world.disc_indices(center, rings):
		var d := HexGrid.distance(world.coords[center], world.coords[j])
		var col := Color(1.0, 0.85, 0.2, 0.62 if d == 0 else (0.45 if d == 1 else 0.28))
		_hex_fill(verts, colors, top_of(j) + Vector3(0, OVERLAY_LIFT * 1.6, 0), col, 0.93)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_range.mesh = mesh


## Preview of a settlement site: its reach in yellow, hexes also inside an NPC reach in orange.
func show_preview(center: int, rings: int, claimed: Dictionary) -> void:
	if center < 0:
		_preview.mesh = null
		return
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for c in HexGrid.disc(world.coords[center], rings):
		var j := world.idx(c)
		if j < 0:
			continue
		var col := Color(1.0, 0.9, 0.25, 0.5)
		if claimed.has(c):
			col = Color(1.0, 0.45, 0.1, 0.6)
		if j == center:
			col = Color(1.0, 1.0, 1.0, 0.7)
		_hex_fill(verts, colors, top_of(j) + Vector3(0, OVERLAY_LIFT * 2.2, 0), col, 0.9)
	_preview.mesh = _mesh_from(verts, colors)


## Shows or hides the combined reach of every NPC settlement.
func show_npc_reach(visible_: bool) -> void:
	if not visible_ or world == null:
		_npc_reach.mesh = null
		return
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for c: Vector2i in WorldReach.npc_claimed(world, 2).keys():
		var j := world.idx(c)
		if j >= 0:
			_hex_fill(verts, colors, top_of(j) + Vector3(0, OVERLAY_LIFT * 1.2, 0), Color(0.25, 0.5, 1.0, 0.5), 0.95)
	_npc_reach.mesh = _mesh_from(verts, colors)


func _mesh_from(verts: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _hex_fill(verts: PackedVector3Array, colors: PackedColorArray, c: Vector3, col: Color, scale_: float) -> void:
	for k in 6:
		var a0 := _corner(c, k, scale_)
		var a1 := _corner(c, (k + 1) % 6, scale_)
		verts.append_array(PackedVector3Array([c, a1, a0]))
		colors.append_array(PackedColorArray([col, col, col]))


func clear_path() -> void:
	for c in _path_root.get_children():
		c.queue_free()


# ---------------------------------------------------------------- overlay

func set_overlay(mode: int) -> void:
	for child in _label_root.get_children():
		child.queue_free()
	if world == null or mode <= Overlay.NONE:
		_overlay.mesh = null
		return
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var biome_colors := {}
	var floor_min := 99
	var cap_max := 0
	for b: BiomeData in _db.biomes.values():
		biome_colors[b.id] = b.color
		floor_min = mini(floor_min, b.danger_floor)
		cap_max = maxi(cap_max, b.danger_cap)
	var params := WorldParams.new()
	var build_infos: Array = []
	var build_lo := 0.0
	var build_hi := 1.0
	if mode == Overlay.BUILD:
		# The colour scale runs from the 10th to the 90th percentile of the world's sites.
		var claimed := WorldReach.npc_claimed(world, params.settlement_range)
		var scores: Array = []
		for i in world.size():
			var info := WorldReach.build_info(world, _db, params, i, claimed)
			build_infos.append(info)
			if info["ok"]:
				scores.append(info["score"])
		scores.sort()
		if not scores.is_empty():
			build_lo = scores[int(scores.size() * 0.1)]
			build_hi = scores[int(scores.size() * 0.9)]
	for i in world.size():
		var col := Color(0, 0, 0, 0)
		match mode:
			Overlay.BUILD:
				var info: Dictionary = build_infos[i]
				if world.passable(i):
					if info["ok"]:
						_add_score_label(i, info["score"])
						var t := clampf((info["score"] - build_lo) / maxf(build_hi - build_lo, 0.01), 0.0, 1.0)
						col = Color(0.9, 0.2, 0.15).lerp(Color(0.95, 0.9, 0.2), clampf(t * 2.0, 0.0, 1.0)).lerp(Color(0.2, 0.9, 0.35), clampf(t * 2.0 - 1.0, 0.0, 1.0))
						col.a = 0.62
					else:
						col = Color(0.05, 0.05, 0.08, 0.5)
			Overlay.BIOME:
				col = biome_colors.get(world.biome[i], Color.WHITE)
				col.a = 0.6
			Overlay.DANGER:
				var b: BiomeData = _db.biomes.get(world.biome[i])
				var t := clampf(float(b.danger_floor - floor_min) / maxf(cap_max - floor_min, 1.0), 0.0, 1.0)
				col = Color(0.2, 0.8, 0.3).lerp(Color(0.9, 0.15, 0.1), t)
				col.a = 0.6
			Overlay.AP:
				var a := world.ap[i]
				col = Color(0.1, 0.1, 0.1, 0.75) if a < 0 else Color(0.3, 0.85, 0.4).lerp(Color(0.95, 0.3, 0.2), (a - 1) / 3.0)
				col.a = 0.75 if a < 0 else 0.55
		var c := top_of(i) + Vector3(0, OVERLAY_LIFT, 0)
		for k in 6:
			var a0 := _corner(c, k, 0.97)
			var a1 := _corner(c, (k + 1) % 6, 0.97)
			verts.append_array(PackedVector3Array([c, a1, a0]))
			colors.append_array(PackedColorArray([col, col, col]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_overlay.mesh = mesh


## The site value as a number on the hex, one decimal, facing the camera.
func _add_score_label(i: int, score: float) -> void:
	var label := Label3D.new()
	label.text = "%.1f" % score
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.0035
	label.font_size = 56
	label.outline_size = 14
	label.modulate = Color(1, 1, 1)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.position = top_of(i) + Vector3(0, 0.12, 0)
	_label_root.add_child(label)


func _corner(center: Vector3, k: int, scale_: float) -> Vector3:
	# Pointy-top: corner 0 points along +z.
	var ang := deg_to_rad(60.0 * k)
	return center + Vector3(sin(ang), 0, cos(ang)) * TILE_SIZE * scale_


# ---------------------------------------------------------------- tiles and props

func _terrain_height(terrain_id: String) -> float:
	var t: TerrainData = _db.terrains.get(terrain_id)
	return t.height if t != null else 0.3


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_materials[key] = m
	return _materials[key]


## Water keeps its own colour; every land hex is coloured by its biome.
func _tile_color(i: int) -> Color:
	var terrain_id := world.terrain[i]
	if terrain_id == "river" or terrain_id == "lake":
		return (_db.terrains[terrain_id] as TerrainData).color
	var biome: BiomeData = _db.biomes.get(world.biome[i])
	return biome.color if biome != null else Color.WHITE


func _tile_mesh(terrain_id: String, color: Color) -> Mesh:
	var key := terrain_id + color.to_html()
	if not _meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.radial_segments = 6
		mesh.rings = 1
		mesh.top_radius = TILE_SIZE * 0.995
		mesh.bottom_radius = TILE_SIZE * 0.995
		mesh.height = _terrain_height(terrain_id)
		mesh.material = _material(color)
		_meshes[key] = mesh
	return _meshes[key]


func _build_tile(i: int) -> void:
	var terrain_id := world.terrain[i]
	var p := HexGrid.to_world(world.coords[i], TILE_SIZE)
	var art := assets.instance("tiles", terrain_id, world.seed_value, world.coords[i])
	var holder := Node3D.new()
	holder.position = Vector3(p.x, 0, p.y)
	if art != null:
		holder.add_child(art)
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = _tile_mesh(terrain_id, _tile_color(i))
		mi.position.y = _heights[i] * 0.5
		holder.add_child(mi)
	_tile_root.add_child(holder)


## Sea tiles in a ring around the continent. Art in assets/world/tiles/ocean/ is used when present.
func _build_ocean() -> void:
	var ocean: TerrainData = _db.terrains.get("ocean")
	if ocean == null:
		return
	var coords: Array[Vector2i] = []
	var reach := world.half_extent + Vector2(OCEAN_MARGIN * HexGrid.SQRT3, OCEAN_MARGIN * 1.5)
	for q in range(-120, 121):
		for r in range(-90, 91):
			var c := Vector2i(q, r)
			var p := HexGrid.to_world(c, TILE_SIZE)
			if absf(p.x) <= reach.x and absf(p.y) <= reach.y and not world.has_coord(c):
				coords.append(c)
	if assets.has_art("tiles", "ocean"):
		for c in coords:
			var art := assets.instance("tiles", "ocean", world.seed_value, c)
			if art == null:
				continue
			var p := HexGrid.to_world(c, TILE_SIZE)
			art.position = Vector3(p.x, 0, p.y)
			_ocean_root.add_child(art)
		return
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.top_radius = TILE_SIZE * 0.995
	mesh.bottom_radius = TILE_SIZE * 0.995
	mesh.height = ocean.height
	mesh.material = _material(ocean.color)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = coords.size()
	for k in coords.size():
		var p := HexGrid.to_world(coords[k], TILE_SIZE)
		multi.set_instance_transform(k, Transform3D(Basis(), Vector3(p.x, ocean.height * 0.5, p.y)))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = multi
	_ocean_root.add_child(inst)


# ---------------------------------------------------------------- placeholder models
# The tile colour says which biome a hex is in; the model standing on it says what terrain it
# is. The biome's plain terrain (grass, marsh) is a bare tile. All of this is placeholder art.

func _build_props(i: int) -> void:
	var terrain_id := world.terrain[i]
	var coord := world.coords[i]
	var base := top_of(i)
	if assets.has_art("props", terrain_id):
		for k in assets.prop_count(world.seed_value, coord):
			var prop := assets.instance("props", terrain_id, world.seed_value, coord, "#%d" % k)
			if prop == null:
				continue
			var o := assets.prop_offset(world.seed_value, coord, k)
			prop.position = base + Vector3(o.x, 0, o.y)
			_prop_root.add_child(prop)
		return
	if terrain_id == "river" or terrain_id == "lake":
		return
	var biome: BiomeData = _db.biomes.get(world.biome[i])
	if biome == null or biome.plain_terrain == terrain_id:
		return
	var col := biome.color
	match terrain_id:
		"forest":
			for k in assets.prop_count(world.seed_value, coord, 1.0):
				_cone(base, coord, k, 0.2, 0.55, col.darkened(0.45), 6, 0.0)
		"wyrd_forest":
			for k in assets.prop_count(world.seed_value, coord, 1.0):
				_cone(base, coord, k, 0.15, 0.75, col.darkened(0.5), 5, 0.3)
		"hills":
			for k in 1 + assets.prop_count(world.seed_value, coord, 0.5) % 2:
				var o := assets.prop_offset(world.seed_value, coord, k) * 0.7
				var mound := MeshInstance3D.new()
				var sphere := SphereMesh.new()
				sphere.radius = 0.5
				sphere.height = 1.0
				sphere.radial_segments = 12
				sphere.rings = 6
				sphere.material = _material(col.darkened(0.2))
				mound.mesh = sphere
				mound.scale = Vector3(1.0, 0.5, 1.0)
				mound.position = base + Vector3(o.x, 0.0, o.y)
				_prop_root.add_child(mound)
		"mountain":
			var rock := col.lerp(Color(0.6, 0.6, 0.64), 0.55).darkened(0.1)
			for k in 3:
				var o := assets.prop_offset(world.seed_value, coord, k) * 0.55
				var h := 1.0 + 0.6 * WorldHash.unit(WorldHash.hash2(world.seed_value, coord.x * 7 + k, coord.y))
				_cone_at(base + Vector3(o.x, h * 0.5, o.y), 0.42, h, rock, 5, 0.0)
		"grass":
			for k in 3:
				_cone(base, coord, k, 0.06, 0.18, col.lightened(0.15), 4, 0.0)
		"marsh":
			var reed := col.lerp(Color(0.75, 0.68, 0.45), 0.5)
			for k in 3:
				var o := assets.prop_offset(world.seed_value, coord, k)
				var stalk := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.025
				cyl.bottom_radius = 0.035
				cyl.height = 0.34
				cyl.radial_segments = 4
				cyl.material = _material(reed)
				stalk.mesh = cyl
				stalk.position = base + Vector3(o.x, 0.17, o.y)
				_prop_root.add_child(stalk)


func _cone(base: Vector3, coord: Vector2i, k: int, radius: float, height: float, color: Color, segments: int, tilt: float) -> void:
	var o := assets.prop_offset(world.seed_value, coord, k)
	_cone_at(base + Vector3(o.x, height * 0.5, o.y), radius, height, color, segments, tilt)


func _cone_at(pos: Vector3, radius: float, height: float, color: Color, segments: int, tilt: float) -> void:
	var tree := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = segments
	cone.material = _material(color)
	tree.mesh = cone
	tree.position = pos
	if tilt != 0.0:
		var h := WorldHash.hash2(world.seed_value, int(pos.x * 100.0), int(pos.z * 100.0))
		tree.rotation = Vector3(tilt * (WorldHash.unit(h) - 0.5) * 2.0, 0.0, tilt * (WorldHash.unit(h >> 3) - 0.5) * 2.0)
	_prop_root.add_child(tree)


# ---------------------------------------------------------------- nodes, locations, settlements

func _build_markers(i: int) -> void:
	var coord := world.coords[i]
	var base := top_of(i)
	if world.node[i] != "":
		var def: ResourceNodeData = _db.nodes.get(world.node[i])
		var art := assets.instance("nodes", world.node[i], world.seed_value, coord, "#node")
		if art == null:
			art = _placeholder_node(def.color if def != null else Color.WHITE, def.category if def != null else "")
		art.position = base + Vector3(-0.38, 0, -0.22)
		_marker_root.add_child(art)
	if world.location[i] != "":
		var def: LocationData = _db.locations.get(world.location[i])
		var art := assets.instance("locations", world.location[i], world.seed_value, coord, "#loc")
		if art == null:
			art = _placeholder_location(def.color if def != null else Color.WHITE)
		art.position = base + Vector3(0.38, 0, -0.22)
		_marker_root.add_child(art)
	if world.settlements.has(i):
		var art := assets.instance("settlements", "npc_settlement", world.seed_value, coord)
		if art == null:
			art = _placeholder_settlement()
		art.position = base
		_marker_root.add_child(art)


## Fish and other nodes that sit on the shore sea.
func _build_sea_markers() -> void:
	var ocean: TerrainData = _db.terrains.get("ocean")
	var height: float = ocean.height if ocean != null else 0.2
	for c: Vector2i in world.sea_node.keys():
		var id: String = world.sea_node[c]
		var def: ResourceNodeData = _db.nodes.get(id)
		var art := assets.instance("nodes", id, world.seed_value, c, "#node")
		if art == null:
			art = _placeholder_node(def.color if def != null else Color.WHITE, def.category if def != null else "")
		var p := HexGrid.to_world(c)
		art.position = Vector3(p.x - 0.38, height, p.y - 0.22)
		_marker_root.add_child(art)


func _placeholder_node(color: Color, category: String) -> Node3D:
	var mi := MeshInstance3D.new()
	if category == "food":
		var s := SphereMesh.new()
		s.radius = 0.14
		s.height = 0.28
		s.material = _material(color)
		mi.mesh = s
		mi.position.y = 0.14
	elif category == "water":
		var c := CylinderMesh.new()
		c.top_radius = 0.1
		c.bottom_radius = 0.16
		c.height = 0.18
		c.material = _material(color)
		mi.mesh = c
		mi.position.y = 0.09
	else:
		var b := BoxMesh.new()
		b.size = Vector3(0.24, 0.24, 0.24)
		b.material = _material(color)
		mi.mesh = b
		mi.position.y = 0.12
		mi.rotation.y = 0.6
	var holder := Node3D.new()
	holder.add_child(mi)
	return holder


func _placeholder_location(color: Color) -> Node3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.2
	c.height = 0.5
	c.radial_segments = 4
	c.material = _material(color)
	mi.mesh = c
	mi.position.y = 0.25
	var holder := Node3D.new()
	holder.add_child(mi)
	return holder


func _placeholder_settlement() -> Node3D:
	var holder := Node3D.new()
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.28, 0.4)
	box.material = _material(Color(0.82, 0.72, 0.55))
	wall.mesh = box
	wall.position.y = 0.14
	holder.add_child(wall)
	var roof := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.34
	cone.height = 0.24
	cone.radial_segments = 4
	cone.material = _material(Color(0.6, 0.25, 0.2))
	roof.mesh = cone
	roof.position.y = 0.4
	roof.rotation.y = deg_to_rad(45)
	holder.add_child(roof)
	return holder


func make_party_marker() -> Node3D:
	var art := assets.instance("party", "party", world.seed_value if world != null else 0, Vector2i.ZERO)
	if art != null:
		return art
	var holder := Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.15
	cap.height = 0.5
	cap.material = _material(Color(0.95, 0.85, 0.2))
	body.mesh = cap
	body.position.y = 0.25
	holder.add_child(body)
	return holder


func _hex_ring_mesh(outer: float, inner: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	for k in 6:
		var a0 := deg_to_rad(60.0 * k)
		var a1 := deg_to_rad(60.0 * (k + 1))
		var o0 := Vector3(sin(a0), 0, cos(a0)) * outer
		var o1 := Vector3(sin(a1), 0, cos(a1)) * outer
		var i0 := Vector3(sin(a0), 0, cos(a0)) * inner
		var i1 := Vector3(sin(a1), 0, cos(a1)) * inner
		verts.append_array(PackedVector3Array([o0, o1, i0, i0, o1, i1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
