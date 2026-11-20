extends Node3D
class_name CityMegaBuilder

## Architectural Mega-City Generator (`1,400m x 1,400m` across both Nile banks).
## Builds:
## - Partitioned driveable ground slabs around 4 wide underground tunnel trenches
## - Nile River north/south extensions (`z in [-700..+700]`), twin Corniche promenades, and 3 Boat Docks
## - Extended asphalt avenues, 8 roundabouts, streetlights, lane markings, and highway gateway arches
## - 3 Cross-Nile Bridges (`GrandNileBridge` z=0, `NorthernNileBridge` z=-360, `SouthernNileBridge` z=+360)
## - 4 Elevated Highway Overpasses (ramps 7.36 deg <= 12 deg)
## - 4 Illuminated Underground Tunnels (width 16m, clear height 6.5m >= 6.0m, ramps 8.41 deg <= 12 deg)
## - 3 New Distinct Mosques + 6 Automated Bakeries + Health/Emergency/Engineering/Sports Landmarks
## - ~290-310 varied buildings across 8 named districts using 12 shared materials & 6 architectural silhouettes

const SCENE_BAKERY: PackedScene = preload("res://scenes/buildings/automated_bakery.tscn")
const SCENE_MOSQUE_NILE: PackedScene = preload("res://scenes/buildings/mosque_nile_grand.tscn")
const SCENE_MOSQUE_WEST: PackedScene = preload("res://scenes/buildings/mosque_west_heritage.tscn")
const SCENE_MOSQUE_ALNOOR: PackedScene = preload("res://scenes/buildings/mosque_alnoor.tscn")

const TEX_PLASTER_ALB: Texture2D = preload("res://assets/textures/plaster/albedo.jpg")
const TEX_PLASTER_NOR: Texture2D = preload("res://assets/textures/plaster/normal.jpg")
const TEX_PLASTER_RGH: Texture2D = preload("res://assets/textures/plaster/roughness.jpg")
const TEX_BRICK_ALB: Texture2D = preload("res://assets/textures/brick/albedo.jpg")
const TEX_BRICK_NOR: Texture2D = preload("res://assets/textures/brick/normal.jpg")
const TEX_BRICK_RGH: Texture2D = preload("res://assets/textures/brick/roughness.jpg")
const TEX_ASPHALT_ALB: Texture2D = preload("res://assets/textures/asphalt/albedo.jpg")
const TEX_ASPHALT_NOR: Texture2D = preload("res://assets/textures/asphalt/normal.jpg")
const TEX_ASPHALT_RGH: Texture2D = preload("res://assets/textures/asphalt/roughness.jpg")
const TEX_SAND_ALB: Texture2D = preload("res://assets/textures/sand_dirt/albedo.jpg")
const TEX_SAND_NOR: Texture2D = preload("res://assets/textures/sand_dirt/normal.jpg")
const TEX_SAND_RGH: Texture2D = preload("res://assets/textures/sand_dirt/roughness.jpg")
const TEX_WOOD_ALB: Texture2D = preload("res://assets/textures/wood/albedo.jpg")

const WORLD_HALF: float = 700.0
const WEB_DISTRICT_RADIUS: float = 320.0
const WEB_YIELD_BATCH: int = 15
const VIS_BUILDING: float = 520.0
const VIS_DETAIL: float = 105.0

var _palette_mats: Array[StandardMaterial3D] = []
var _trim_mats: Array[StandardMaterial3D] = []
var _mat_ground: StandardMaterial3D
var _mat_asphalt: StandardMaterial3D
var _mat_concrete: StandardMaterial3D
var _mat_curb: StandardMaterial3D
var _mat_water: StandardMaterial3D
var _mat_glass: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_steel: StandardMaterial3D
var _mat_yellow: StandardMaterial3D
var _mat_red: StandardMaterial3D
var _mat_blue: StandardMaterial3D
var _mat_green: StandardMaterial3D
var _mat_white: StandardMaterial3D
var _mat_lane: StandardMaterial3D
var _mat_lamp_glow: StandardMaterial3D
var _mat_tunnel_wall: StandardMaterial3D
var _mat_tunnel_strip: StandardMaterial3D

var _blocked_rects: Array[Rect2] = []
var _building_records: Array[Dictionary] = []
var _tunnel_rects: Array[Rect2] = []
var _bridge_rects: Array[Rect2] = []
var _overpass_rects: Array[Rect2] = []
var _role_stations: Array[Dictionary] = []
var _landmark_minimap_points: Array[Dictionary] = []
var _built_buildings_count: int = 0
var _ramps_audit: Array[Dictionary] = []
var _tunnels_audit: Array[Dictionary] = []

var _terrain_root: Node3D
var _roads_root: Node3D
var _structures_root: Node3D
var _landmarks_root: Node3D
var _city_buildings_root: Node3D


func _ready() -> void:
	add_to_group("city_mega_builder")
	_init_shared_materials()
	_create_containers()
	_register_initial_exclusion_zones()
	_build_partitioned_ground()
	if OS.has_feature("web"):
		call_deferred("_build_city_web_progressive")
		return
	_build_nile_extensions_and_docks()
	_build_arterial_road_network()
	_build_secondary_neighborhood_streets()
	_build_three_nile_bridges()
	_build_four_overpasses()
	_build_four_tunnels()
	_build_landmarks_and_bakeries()
	_build_eight_district_cities()
	OuterCityDetailBuilder.build_outer_street_life(_city_buildings_root, _blocked_rects, _role_stations)
	_register_core_work_stations()
	set_meta("built_buildings_count", _built_buildings_count)
	set_meta("role_stations_count", _role_stations.size())
	print("[CityMegaBuilder] Built 1400x1400m city: %d varied buildings, 4 mosques, 6 bakeries, 3 Nile bridges, 4 overpasses, 4 tunnels, %d role stations." % [
		_built_buildings_count, _role_stations.size()
	])


func _build_city_web_progressive() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_nile_extensions_and_docks()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_arterial_road_network()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_secondary_neighborhood_streets()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_three_nile_bridges(true)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_four_overpasses(true)
	_build_four_tunnels(true)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await _build_landmarks_and_bakeries_web()
	if not is_inside_tree():
		return
	await _build_eight_district_cities_web()
	if not is_inside_tree():
		return
	OuterCityDetailBuilder.build_outer_street_life(_city_buildings_root, _blocked_rects, _role_stations)
	_register_core_work_stations()
	_apply_web_safari_visibility_profile()
	get_tree().call_group("network_hud", "_apply_safari_web_graphics_profile")
	set_meta("built_buildings_count", _built_buildings_count)
	set_meta("role_stations_count", _role_stations.size())
	print("[CityMegaBuilder] Web progressive core city ready (%d buildings within %.0fm)." % [_built_buildings_count, WEB_DISTRICT_RADIUS])


func get_role_work_stations() -> Array[Dictionary]:
	return _role_stations


func get_building_records() -> Array[Dictionary]:
	return _building_records


func get_blocked_rects() -> Array[Rect2]:
	return _blocked_rects


func get_ramp_audits() -> Array[Dictionary]:
	return _ramps_audit


func get_tunnel_audits() -> Array[Dictionary]:
	return _tunnels_audit


func get_minimap_landmarks() -> Array[Dictionary]:
	return _landmark_minimap_points


func _apply_web_safari_visibility_profile() -> void:
	# Lightweight Safari WebGL2 profile: 140m max for buildings, 65m for props
	_cap_tree_visibility(_city_buildings_root, 140.0, 65.0)
	_cap_tree_visibility(_landmarks_root, 140.0, 65.0)
	_cap_tree_visibility(_structures_root, 140.0, 65.0)


func _cap_tree_visibility(node: Node, bld_cap: float, prop_cap: float) -> void:
	if node == null:
		return
	var is_prop_node := node.name in ["OuterStreetLife", "StreetProps", "RooftopWaterTankKit"]
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if is_prop_node or (gi.visibility_range_end > prop_cap and gi.visibility_range_end < 300.0):
			gi.visibility_range_end = prop_cap
		elif gi.visibility_range_end <= 0.0 or gi.visibility_range_end > bld_cap:
			gi.visibility_range_end = bld_cap
	for ch in node.get_children():
		_cap_tree_visibility(ch, bld_cap, prop_cap)


func _create_containers() -> void:
	_terrain_root = Node3D.new()
	_terrain_root.name = "MegaTerrain"
	add_child(_terrain_root)

	_roads_root = Node3D.new()
	_roads_root.name = "MegaRoads"
	add_child(_roads_root)

	_structures_root = Node3D.new()
	_structures_root.name = "MegaInfrastructure"
	add_child(_structures_root)

	_landmarks_root = Node3D.new()
	_landmarks_root.name = "MegaLandmarks"
	add_child(_landmarks_root)

	_city_buildings_root = Node3D.new()
	_city_buildings_root.name = "MegaBuildings"
	add_child(_city_buildings_root)


func _init_shared_materials() -> void:
	_mat_ground = StandardMaterial3D.new()
	_mat_ground.albedo_color = Color(1.0, 0.75, 0.57, 1.0)
	_mat_ground.albedo_texture = TEX_SAND_ALB
	_mat_ground.normal_enabled = true
	_mat_ground.normal_texture = TEX_SAND_NOR
	_mat_ground.roughness = 0.95
	_mat_ground.roughness_texture = TEX_SAND_RGH
	_mat_ground.uv1_scale = Vector3(120, 120, 1)

	_mat_asphalt = StandardMaterial3D.new()
	_mat_asphalt.albedo_color = Color(0.76, 0.76, 0.78, 1.0)
	_mat_asphalt.albedo_texture = TEX_ASPHALT_ALB
	_mat_asphalt.normal_enabled = true
	_mat_asphalt.normal_texture = TEX_ASPHALT_NOR
	_mat_asphalt.roughness = 0.9
	_mat_asphalt.roughness_texture = TEX_ASPHALT_RGH
	_mat_asphalt.uv1_scale = Vector3(18, 2, 1)

	_mat_concrete = StandardMaterial3D.new()
	_mat_concrete.albedo_color = Color(0.84, 0.81, 0.76, 1.0)
	_mat_concrete.albedo_texture = TEX_PLASTER_ALB
	_mat_concrete.roughness = 0.88
	_mat_concrete.uv1_triplanar = true
	_mat_concrete.uv1_scale = Vector3(0.32, 0.32, 0.32)

	_mat_curb = StandardMaterial3D.new()
	_mat_curb.albedo_color = Color(0.72, 0.67, 0.59, 1.0)
	_mat_curb.roughness = 0.9

	_mat_water = StandardMaterial3D.new()
	_mat_water.albedo_color = Color(0.11, 0.38, 0.52, 0.92)
	_mat_water.roughness = 0.14
	_mat_water.metallic = 0.08

	_mat_glass = StandardMaterial3D.new()
	_mat_glass.albedo_color = Color(0.24, 0.42, 0.56, 1.0)
	_mat_glass.roughness = 0.25
	_mat_glass.metallic = 0.15

	_mat_wood = StandardMaterial3D.new()
	_mat_wood.albedo_color = Color(0.66, 0.44, 0.26, 1.0)
	_mat_wood.albedo_texture = TEX_WOOD_ALB
	_mat_wood.roughness = 0.84

	_mat_steel = StandardMaterial3D.new()
	_mat_steel.albedo_color = Color(0.40, 0.44, 0.48, 1.0)
	_mat_steel.metallic = 0.35
	_mat_steel.roughness = 0.55

	_mat_yellow = StandardMaterial3D.new()
	_mat_yellow.albedo_color = Color(0.94, 0.72, 0.14, 1.0)
	_mat_yellow.roughness = 0.65

	_mat_red = StandardMaterial3D.new()
	_mat_red.albedo_color = Color(0.82, 0.18, 0.16, 1.0)
	_mat_red.roughness = 0.72

	_mat_blue = StandardMaterial3D.new()
	_mat_blue.albedo_color = Color(0.16, 0.44, 0.78, 1.0)
	_mat_blue.roughness = 0.72

	_mat_green = StandardMaterial3D.new()
	_mat_green.albedo_color = Color(0.18, 0.54, 0.28, 1.0)
	_mat_green.roughness = 0.8

	_mat_white = StandardMaterial3D.new()
	_mat_white.albedo_color = Color(0.96, 0.95, 0.92, 1.0)
	_mat_white.roughness = 0.82

	_mat_lane = StandardMaterial3D.new()
	_mat_lane.albedo_color = Color(0.95, 0.90, 0.76, 1.0)
	_mat_lane.roughness = 0.8

	_mat_lamp_glow = StandardMaterial3D.new()
	_mat_lamp_glow.albedo_color = Color(1.0, 0.90, 0.62, 1.0)
	_mat_lamp_glow.emission_enabled = true
	_mat_lamp_glow.emission = Color(1.0, 0.82, 0.44, 1.0)
	_mat_lamp_glow.emission_energy_multiplier = 1.6

	_mat_tunnel_wall = StandardMaterial3D.new()
	_mat_tunnel_wall.albedo_color = Color(0.76, 0.74, 0.70, 1.0)
	_mat_tunnel_wall.albedo_texture = TEX_PLASTER_ALB
	_mat_tunnel_wall.roughness = 0.85
	_mat_tunnel_wall.uv1_triplanar = true
	_mat_tunnel_wall.uv1_scale = Vector3(0.35, 0.35, 0.35)

	_mat_tunnel_strip = StandardMaterial3D.new()
	_mat_tunnel_strip.albedo_color = Color(1.0, 0.94, 0.80, 1.0)
	_mat_tunnel_strip.emission_enabled = true
	_mat_tunnel_strip.emission = Color(1.0, 0.90, 0.70, 1.0)
	_mat_tunnel_strip.emission_energy_multiplier = 2.0

	# 12 distinct Sudanese architectural wall colors shared across all ~300 procedural buildings
	var colors: Array[Color] = [
		Color(0.95, 0.89, 0.76, 1.0), # 0: Warm Khartoum Cream
		Color(0.86, 0.60, 0.44, 1.0), # 1: Sudanese Terracotta
		Color(0.96, 0.96, 0.94, 1.0), # 2: Whitewash Chalk
		Color(0.91, 0.74, 0.46, 1.0), # 3: Nubian Ochre
		Color(0.78, 0.86, 0.77, 1.0), # 4: Pale Oasis Sage
		Color(0.88, 0.72, 0.68, 1.0), # 5: Desert Rose Plaster
		Color(0.82, 0.82, 0.80, 1.0), # 6: Limestone Grey
		Color(0.92, 0.81, 0.60, 1.0), # 7: Honey Sandstone
		Color(0.81, 0.88, 0.94, 1.0), # 8: Nile Sky Chalk
		Color(0.82, 0.73, 0.50, 1.0), # 9: Olive Sand
		Color(0.76, 0.46, 0.34, 1.0), # 10: Burnt Brick Sienna
		Color(0.95, 0.80, 0.69, 1.0), # 11: Soft Peach Plaster
	]
	for idx in range(colors.size()):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[idx]
		mat.uv1_triplanar = true
		if idx == 1 or idx == 10:
			mat.albedo_texture = TEX_BRICK_ALB
			mat.normal_enabled = true
			mat.normal_texture = TEX_BRICK_NOR
			mat.roughness = 0.88
			mat.roughness_texture = TEX_BRICK_RGH
			mat.uv1_scale = Vector3(0.45, 0.45, 0.45)
		else:
			mat.albedo_texture = TEX_PLASTER_ALB
			mat.normal_enabled = true
			mat.normal_texture = TEX_PLASTER_NOR
			mat.roughness = 0.86
			mat.roughness_texture = TEX_PLASTER_RGH
			mat.uv1_scale = Vector3(0.32, 0.32, 0.32)
		_palette_mats.append(mat)

	var trim_colors: Array[Color] = [
		Color(0.96, 0.94, 0.89, 1.0),
		Color(0.68, 0.46, 0.28, 1.0),
		Color(0.22, 0.52, 0.74, 1.0),
		Color(0.22, 0.52, 0.34, 1.0),
		Color(0.76, 0.60, 0.32, 1.0),
	]
	for c in trim_colors:
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = c
		tmat.roughness = 0.82
		_trim_mats.append(tmat)


func _register_initial_exclusion_zones() -> void:
	# Preserve 100% of original Al-Azhari historic core [-136..+136]
	_blocked_rects.append(Rect2(-136.0, -136.0, 272.0, 272.0))
	# Reserve Nile water channel + Corniche margins x in [-252 .. -132], z in [-700 .. +700]
	_blocked_rects.append(Rect2(-252.0, -700.0, 120.0, 1400.0))

	# Define the 4 tunnel trench rectangles (width = 16m, total length = 144m)
	_tunnel_rects = [
		Rect2(-72.0, -208.0, 144.0, 16.0),   # Tunnel 1: along z = -200 under x = 0
		Rect2(148.0, 192.0, 144.0, 16.0),    # Tunnel 2: along z = +200 under x = +220
		Rect2(392.0, 128.0, 16.0, 144.0),    # Tunnel 3: along x = +400 under z = +200
		Rect2(-492.0, 192.0, 144.0, 16.0),   # Tunnel 4: along z = +200 under x = -420
	]
	for tr in _tunnel_rects:
		_blocked_rects.append(tr.grow(4.0))

	# Reserve 3 Nile bridges + ramps
	_bridge_rects = [
		Rect2(-292.0, -12.0, 204.0, 24.0),
		Rect2(-292.0, -372.0, 204.0, 24.0),
		Rect2(-292.0, 348.0, 204.0, 24.0),
	]
	for br in _bridge_rects:
		_blocked_rects.append(br.grow(4.0))

	# Reserve 4 elevated overpasses
	_overpass_rects = [
		Rect2(208.0, -268.0, 24.0, 136.0),   # Overpass 1 along x=+220 over z=-200
		Rect2(388.0, -68.0, 24.0, 136.0),    # Overpass 2 along x=+400 over z=0
		Rect2(152.0, -372.0, 136.0, 24.0),   # Overpass 3 along z=-360 over x=+220
		Rect2(-432.0, -268.0, 24.0, 136.0),  # Overpass 4 along x=-420 over z=-200
	]
	for ov in _overpass_rects:
		_blocked_rects.append(ov.grow(4.0))


func _build_partitioned_ground() -> void:
	# Replace static Neighborhood/Ground box with exact partitioned 1400x1400 ground slabs
	var parent_node := get_parent()
	if parent_node:
		var old_ground := parent_node.get_node_or_null("Neighborhood/Ground")
		if old_ground:
			old_ground.queue_free()

	var slabs: Array[Rect2] = [Rect2(-WORLD_HALF, -WORLD_HALF, WORLD_HALF * 2.0, WORLD_HALF * 2.0)]
	# Carve out the Nile River channel (x in [-235..-145]) so players enter deep water instead of walking on y=0 ground
	slabs = _subtract_rect_from_list(slabs, Rect2(-235.0, -WORLD_HALF, 90.0, WORLD_HALF * 2.0))
	for hole in _tunnel_rects:
		slabs = _subtract_rect_from_list(slabs, hole)

	var idx := 0
	for r in slabs:
		if r.size.x < 0.2 or r.size.y < 0.2:
			continue
		idx += 1
		var cx := r.position.x + r.size.x * 0.5
		var cz := r.position.y + r.size.y * 0.5
		var sb := StaticBody3D.new()
		sb.name = "GroundSlab_%d" % idx
		sb.position = Vector3(cx, -0.5, cz)
		_terrain_root.add_child(sb)

		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r.size.x, 1.0, r.size.y)
		bm.material = _mat_ground
		mi.mesh = bm
		sb.add_child(mi)

		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(r.size.x, 1.0, r.size.y)
		col.shape = bs
		sb.add_child(col)


func _subtract_rect_from_list(rects: Array[Rect2], hole: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in rects:
		if not r.intersects(hole):
			out.append(r)
			continue
		var ix0 := maxf(r.position.x, hole.position.x)
		var ix1 := minf(r.end.x, hole.end.x)
		var iz0 := maxf(r.position.y, hole.position.y)
		var iz1 := minf(r.end.y, hole.end.y)
		# Left strip
		if ix0 > r.position.x + 0.05:
			out.append(Rect2(r.position.x, r.position.y, ix0 - r.position.x, r.size.y))
		# Right strip
		if r.end.x > ix1 + 0.05:
			out.append(Rect2(ix1, r.position.y, r.end.x - ix1, r.size.y))
		# Top strip (between ix0..ix1)
		if iz0 > r.position.y + 0.05:
			out.append(Rect2(ix0, r.position.y, ix1 - ix0, iz0 - r.position.y))
		# Bottom strip (between ix0..ix1)
		if r.end.y > iz1 + 0.05:
			out.append(Rect2(ix0, iz1, ix1 - ix0, r.end.y - iz1))
	return out


func _build_nile_extensions_and_docks() -> void:
	# Mount upgraded Nile River environment (realistic water shader, deep riverbed, sloped banks,
	# NileWaterZone buoyancy Area3D, natural islands/sandbars, palms/reeds, and river rocks)
	var nile_env := NileRiverEnvironment.new()
	nile_env.name = "NileRiverEnvironment"
	add_child(nile_env)

	# Extend East Corniche promenade North [-700..-250] and South [+250..+700] seamlessly.
	for seg in [Vector2(-475.0, 450.0), Vector2(475.0, 450.0)]:
		var cz: float = seg.x
		var length: float = seg.y
		_add_static_box(_terrain_root, "EastCornicheWalk_%d" % int(cz), Vector3(-139.0, 0.35, cz), Vector3(11.0, 0.7, length), _mat_curb, VIS_BUILDING)
		_add_static_box(_terrain_root, "EastCornicheWall_%d" % int(cz), Vector3(-143.8, 0.9, cz), Vector3(0.6, 0.7, length), _mat_white, VIS_DETAIL)

	# Full West Bank Corniche (z in [-700..+700], skipping bridge approaches at z=0, -360, +360)
	for span in [
		Vector2(-700.0, -372.0),
		Vector2(-348.0, -12.0),
		Vector2(12.0, 348.0),
		Vector2(372.0, 700.0),
	]:
		var length: float = span.y - span.x
		var cz: float = (span.x + span.y) * 0.5
		_add_static_box(_terrain_root, "WestCornicheWalk_%d" % int(cz), Vector3(-241.0, 0.35, cz), Vector3(11.0, 0.7, length), _mat_curb, VIS_BUILDING)
		_add_static_box(_terrain_root, "WestCornicheWall_%d" % int(cz), Vector3(-236.2, 0.9, cz), Vector3(0.6, 0.7, length), _mat_white, VIS_DETAIL)

	# 3 Nile Boat Docks (مرسى القوارب) with parked wooden Felucca / Nile boats + Dock Master stations
	var docks: Array[Dictionary] = [
		{"name": "EastNileMarinaNorth", "pos": Vector3(-144.0, 0.0, -90.0), "facing": -1.0},
		{"name": "WestNileDock", "pos": Vector3(-236.0, 0.0, -110.0), "facing": 1.0},
		{"name": "EastNileMarinaSouth", "pos": Vector3(-144.0, 0.0, 240.0), "facing": -1.0},
	]
	for d in docks:
		var p: Vector3 = d["pos"]
		var dir: float = d["facing"]
		var dock_node := Node3D.new()
		dock_node.name = d["name"]
		dock_node.position = p
		_landmarks_root.add_child(dock_node)

		_add_static_box(dock_node, "PierDeck", Vector3(dir * 7.5, 0.45, 0.0), Vector3(15.0, 0.3, 6.0), _mat_wood, VIS_DETAIL)
		for px in [2.0, 7.5, 13.0]:
			for pz in [-2.6, 2.6]:
				_add_cylinder_mesh(dock_node, "Piling_%d_%d" % [int(px), int(pz)], Vector3(dir * px, 0.0, pz), 0.22, 1.8, _mat_wood, VIS_DETAIL)
		_add_static_box(dock_node, "TicketBooth", Vector3(-dir * 1.5, 1.35, 3.8), Vector3(3.2, 2.2, 2.8), _mat_white, VIS_DETAIL)
		_add_box_mesh(dock_node, "BoothRoof", Vector3(-dir * 1.5, 2.6, 3.8), Vector3(3.6, 0.25, 3.2), _mat_blue, VIS_DETAIL)
		_add_label3d(dock_node, "DockSign", Vector3(-dir * 1.5, 3.1, 3.8), "مرسى القوارب\nNile Boat Dock", Color(0.95, 0.98, 1.0), 34, 42.0)

		# Moored traditional Nile boat
		_add_box_mesh(dock_node, "BoatHull", Vector3(dir * 11.5, 0.35, -5.2), Vector3(2.4, 0.7, 7.2), _mat_wood, VIS_DETAIL)
		_add_box_mesh(dock_node, "BoatCabin", Vector3(dir * 11.5, 0.95, -5.2), Vector3(1.8, 0.8, 3.2), _mat_white, VIS_DETAIL)

		var yaw := -PI * 0.5 if dir < 0.0 else PI * 0.5
		_role_stations.append({
			"role": "dock_master",
			"district": "Nile Corniche & Marina District",
			"label": "مسؤول المرسى النيلي",
			"position": Vector3(p.x + dir * 2.2, 0.62, p.z + 1.8),
			"yaw": yaw,
			"lines": [
				"أهلاً بك في مرسى قوارب النيل!",
				"الرحلات النيلية جاهزة بين الضفتين الشرقية والغربية.",
				"يرجى ارتداء سترة النجاة عند الصعود للقارب."
			],
		})
		_landmark_minimap_points.append({"pos": p, "tag": "D", "color": Color(0.25, 0.78, 0.96)})


func _add_road_strip(name_prefix: String, center: Vector2, size_xz: Vector2, add_dashes_ns: bool = false, add_dashes_ew: bool = false) -> void:
	if size_xz.x < 1.0 or size_xz.y < 1.0:
		return
	_blocked_rects.append(Rect2(center.x - size_xz.x * 0.5 - 2.0, center.y - size_xz.y * 0.5 - 2.0, size_xz.x + 4.0, size_xz.y + 4.0))
	var mi := MeshInstance3D.new()
	mi.name = name_prefix
	var bm := BoxMesh.new()
	bm.size = Vector3(size_xz.x, 0.025, size_xz.y)
	bm.material = _mat_asphalt
	mi.mesh = bm
	mi.position = Vector3(center.x, 0.015, center.y)
	mi.visibility_range_end = VIS_BUILDING
	_roads_root.add_child(mi)

	if add_dashes_ns and size_xz.y > 16.0:
		var z := center.y - size_xz.y * 0.5 + 8.0
		var z_end := center.y + size_xz.y * 0.5 - 8.0
		var d_idx := 0
		while z < z_end:
			var dash := MeshInstance3D.new()
			dash.name = "%s_Dash_%d" % [name_prefix, d_idx]
			var db := BoxMesh.new()
			db.size = Vector3(0.32, 0.012, 4.5)
			db.material = _mat_lane
			dash.mesh = db
			dash.position = Vector3(center.x, 0.032, z)
			dash.visibility_range_end = VIS_DETAIL
			_roads_root.add_child(dash)
			z += 12.0
			d_idx += 1
	elif add_dashes_ew and size_xz.x > 16.0:
		var x := center.x - size_xz.x * 0.5 + 8.0
		var x_end := center.x + size_xz.x * 0.5 - 8.0
		var d_idx := 0
		while x < x_end:
			var dash := MeshInstance3D.new()
			dash.name = "%s_Dash_%d" % [name_prefix, d_idx]
			var db := BoxMesh.new()
			db.size = Vector3(4.5, 0.012, 0.32)
			db.material = _mat_lane
			dash.mesh = db
			dash.position = Vector3(x, 0.032, center.y)
			dash.visibility_range_end = VIS_DETAIL
			_roads_root.add_child(dash)
			x += 12.0
			d_idx += 1


func _build_arterial_road_network() -> void:
	# North-South Avenues (never overlapping x = [-240..-140] river or core [-136..+136] sidewalks)
	var ns_segments: Array[Array] = [
		["WestOuterNS", -560.0, -620.0, 620.0, 14.0],
		["WestVillasNS_N", -420.0, -620.0, -265.0, 14.0], # breaks for Overpass 4 [-265..-135]
		["WestVillasNS_M", -420.0, -135.0, 620.0, 14.0],
		["WestCornicheNS", -268.0, -620.0, 620.0, 14.0],
		["EastCornicheNS_N", -112.0, -620.0, -140.0, 14.0],
		["EastCornicheNS_S", -112.0, 140.0, 620.0, 14.0],
		["CentralNS_N", 0.0, -620.0, -220.0, 12.0],       # joins existing RoadNS [-220..+220]
		["CentralNS_S", 0.0, 220.0, 620.0, 12.0],
		["MidEastNS_N", 220.0, -620.0, -265.0, 14.0],     # breaks for Overpass 1 [-265..-135]
		["MidEastNS_S", 220.0, -135.0, 620.0, 14.0],
		["EastCivicNS_N", 400.0, -620.0, -65.0, 14.0],    # breaks for Overpass 2 [-65..+65] and Tunnel 3 [+128..+272]
		["EastCivicNS_M", 400.0, 65.0, 128.0, 14.0],
		["EastCivicNS_S", 400.0, 272.0, 620.0, 14.0],
		["EastOuterNS", 560.0, -620.0, 620.0, 14.0],
	]
	for seg in ns_segments:
		var z0: float = seg[2]
		var z1: float = seg[3]
		_add_road_strip(seg[0], Vector2(seg[1], (z0 + z1) * 0.5), Vector2(seg[4], z1 - z0), true, false)

	# East-West Avenues (skipping Nile [-288..-92] except at bridge landings, skipping tunnels & Overpass 3)
	var ew_segments: Array[Array] = [
		["NorthRimEW_W", -560.0, -620.0, -268.0, 14.0],
		["NorthRimEW_E", -560.0, -112.0, 620.0, 14.0],
		["NorthBridgeEW_W", -360.0, -620.0, -288.0, 14.0],
		["NorthBridgeEW_E1", -360.0, -92.0, 155.0, 14.0],  # breaks for Overpass 3 [155..285]
		["NorthBridgeEW_E2", -360.0, 285.0, 620.0, 14.0],
		["NorthMidEW_W", -200.0, -620.0, -268.0, 14.0],
		["NorthMidEW_E1", -200.0, -112.0, -72.0, 14.0],   # breaks for Tunnel 1 [-72..+72]
		["NorthMidEW_E2", -200.0, 72.0, 620.0, 14.0],
		["CentralEW_W", 0.0, -620.0, -288.0, 14.0],       # Grand Nile Bridge covers [-288..-92]; RoadEW covers [-220..+220]
		["CentralEW_E", 0.0, 220.0, 620.0, 12.0],
		["SouthMidEW_W1", 200.0, -620.0, -492.0, 14.0],   # breaks for Tunnel 4 [-492..-348]
		["SouthMidEW_W2", 200.0, -348.0, -268.0, 14.0],
		["SouthMidEW_E1", 200.0, -112.0, 148.0, 14.0],    # breaks for Tunnel 2 [148..292]
		["SouthMidEW_E2", 200.0, 292.0, 620.0, 14.0],
		["SouthBridgeEW_W", 360.0, -620.0, -288.0, 14.0],
		["SouthBridgeEW_E", 360.0, -92.0, 620.0, 14.0],
		["SouthRimEW_W", 560.0, -620.0, -268.0, 14.0],
		["SouthRimEW_E", 560.0, -112.0, 620.0, 14.0],
	]
	for seg in ew_segments:
		var x0: float = seg[2]
		var x1: float = seg[3]
		_add_road_strip(seg[0], Vector2((x0 + x1) * 0.5, seg[1]), Vector2(x1 - x0, seg[4]), false, true)

	# 8 Roundabouts (صواني المرور) across the expanded city
	var roundabouts: Array[Vector2] = [
		Vector2(-420.0, -360.0),
		Vector2(-420.0, 0.0),
		Vector2(-420.0, 360.0),
		Vector2(0.0, -360.0),
		Vector2(0.0, 360.0),
		Vector2(220.0, 0.0),
		Vector2(400.0, -360.0),
		Vector2(400.0, 360.0),
	]
	for idx in range(roundabouts.size()):
		var c: Vector2 = roundabouts[idx]
		_blocked_rects.append(Rect2(c.x - 18.0, c.y - 18.0, 36.0, 36.0))
		_add_cylinder_mesh(_roads_root, "Roundabout_%d" % idx, Vector3(c.x, 0.02, c.y), 14.5, 0.04, _mat_asphalt, VIS_BUILDING)
		_add_static_cylinder(_roads_root, "RoundaboutIsland_%d" % idx, Vector3(c.x, 0.25, c.y), 4.6, 0.5, _mat_curb, VIS_DETAIL)
		_add_cylinder_mesh(_roads_root, "RoundaboutGreen_%d" % idx, Vector3(c.x, 0.55, c.y), 3.6, 0.12, _mat_green, VIS_DETAIL)

	# Streetlight poles along major East-West & North-South avenues (lightweight geometry, visibility <= 280m)
	for lx in [-520, -360, -280, -40, 140, 310, 480]:
		for lz in [-352, 12, 368]:
			_add_streetlight(Vector3(float(lx), 0.0, float(lz)))

	# 2 Highway Gateway Arches (North & South entrances on CentralNS x=0)
	_build_highway_gateway(Vector3(0.0, 0.0, -585.0), "بوابة الخرطوم الشمالية - Khartoum North Gate")
	_build_highway_gateway(Vector3(0.0, 0.0, 585.0), "بوابة الأزهري الجنوبية - Al-Azhari South Gate")


func _build_secondary_neighborhood_streets() -> void:
	# Subdivides the large outer & southern neighborhood blocks with 9m-wide secondary streets + curbs
	# Merged into 1 single multi-surface ArrayMesh (`SecondaryNeighborhoodStreets`) to keep draw calls minimal!
	var b := InteriorMeshBatcher.new()
	var mat_sec_road := _mat_asphalt.duplicate() as StandardMaterial3D
	mat_sec_road.albedo_color = Color(0.68, 0.66, 0.64, 1.0)
	mat_sec_road.uv1_triplanar = true
	mat_sec_road.uv1_scale = Vector3(0.18, 0.18, 0.18)

	var road_w := 9.0
	var curb_w := 0.85

	# East-West secondary neighborhood streets [z, x0, x1]
	var ew_sec: Array[Array] = [
		# Southern Al-Azhari Extension connector street (z = 148, hugging south rim of historic core z=136)
		[148.0, -104.0, -7.0],
		[148.0, 7.0, 212.0],
		[148.0, 228.0, 390.0],
		# Mid-South block connectors (z = 280)
		[280.0, -552.0, -428.0],
		[280.0, -412.0, -276.0],
		[280.0, -104.0, -7.0],
		[280.0, 7.0, 212.0],
		[280.0, 228.0, 392.0],
		[280.0, 408.0, 552.0],
		# Deep-South block connectors (z = 460)
		[460.0, -552.0, -428.0],
		[460.0, -412.0, -276.0],
		[460.0, -104.0, -7.0],
		[460.0, 7.0, 212.0],
		[460.0, 228.0, 392.0],
		[460.0, 408.0, 552.0],
		# Northern outer block connectors (z = -280)
		[-280.0, -552.0, -428.0],
		[-280.0, -412.0, -276.0],
		[-280.0, -104.0, -7.0],
		[-280.0, 7.0, 212.0],
		[-280.0, 228.0, 392.0],
		[-280.0, 408.0, 552.0],
	]
	for seg in ew_sec:
		var zc: float = seg[0]
		var x0: float = seg[1]
		var x1: float = seg[2]
		var length: float = x1 - x0
		var xc: float = (x0 + x1) * 0.5
		if length < 10.0:
			continue
		b.add_box(Vector3(xc, 0.012, zc), Vector3(length, 0.024, road_w), mat_sec_road)
		b.add_box(Vector3(xc, 0.055, zc - road_w * 0.5 - curb_w * 0.5), Vector3(length, 0.11, curb_w), _mat_curb)
		b.add_box(Vector3(xc, 0.055, zc + road_w * 0.5 + curb_w * 0.5), Vector3(length, 0.11, curb_w), _mat_curb)
		_blocked_rects.append(Rect2(x0 - 1.0, zc - road_w * 0.5 - curb_w - 1.5, length + 2.0, road_w + curb_w * 2.0 + 3.0))

	# North-South secondary neighborhood streets [x, z0, z1]
	var ns_sec: Array[Array] = [
		[-490.0, -552.0, -368.0],
		[-490.0, -352.0, -208.0],
		[-490.0, 208.0, 352.0],
		[-490.0, 368.0, 552.0],
		[-345.0, -552.0, -368.0],
		[-345.0, -352.0, -208.0],
		[-345.0, 208.0, 352.0],
		[-345.0, 368.0, 552.0],
		[-56.0, -552.0, -368.0],
		[-56.0, -352.0, -208.0],
		[-56.0, 140.0, 192.0],
		[-56.0, 208.0, 352.0],
		[-56.0, 368.0, 552.0],
		[110.0, -552.0, -368.0],
		[110.0, -352.0, -208.0],
		[110.0, 140.0, 192.0],
		[110.0, 208.0, 352.0],
		[110.0, 368.0, 552.0],
		[310.0, -552.0, -368.0],
		[310.0, -352.0, -208.0],
		[310.0, 208.0, 352.0],
		[310.0, 368.0, 552.0],
		[480.0, -552.0, -368.0],
		[480.0, -352.0, -208.0],
		[480.0, 208.0, 352.0],
		[480.0, 368.0, 552.0],
	]
	for seg in ns_sec:
		var xc: float = seg[0]
		var z0: float = seg[1]
		var z1: float = seg[2]
		var length: float = z1 - z0
		var zc: float = (z0 + z1) * 0.5
		if length < 10.0:
			continue
		b.add_box(Vector3(xc, 0.011, zc), Vector3(road_w, 0.022, length), mat_sec_road)
		b.add_box(Vector3(xc - road_w * 0.5 - curb_w * 0.5, 0.050, zc), Vector3(curb_w, 0.10, length), _mat_curb)
		b.add_box(Vector3(xc + road_w * 0.5 + curb_w * 0.5, 0.050, zc), Vector3(curb_w, 0.10, length), _mat_curb)
		_blocked_rects.append(Rect2(xc - road_w * 0.5 - curb_w - 1.5, z0 - 1.0, road_w + curb_w * 2.0 + 3.0, length + 2.0))

	if not b.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "SecondaryNeighborhoodStreets"
		mi.mesh = b.commit()
		mi.visibility_range_end = VIS_BUILDING
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_roads_root.add_child(mi)


func _add_streetlight(pos: Vector3) -> void:
	_add_cylinder_mesh(_roads_root, "LampPole_%d_%d" % [int(pos.x), int(pos.z)], pos + Vector3(0, 3.2, 0), 0.14, 6.4, _mat_steel, VIS_DETAIL)
	_add_box_mesh(_roads_root, "LampHead_%d_%d" % [int(pos.x), int(pos.z)], pos + Vector3(0, 6.3, 0), Vector3(1.1, 0.22, 0.45), _mat_lamp_glow, VIS_DETAIL)


func _build_highway_gateway(pos: Vector3, title_txt: String) -> void:
	var gate := Node3D.new()
	gate.name = "Gateway_%d" % int(pos.z)
	gate.position = pos
	_landmarks_root.add_child(gate)
	_blocked_rects.append(Rect2(pos.x - 14.0, pos.z - 5.0, 28.0, 10.0))

	_add_static_box(gate, "PillarL", Vector3(-9.5, 4.2, 0.0), Vector3(2.2, 8.4, 2.6), _palette_safe(0), VIS_BUILDING)
	_add_static_box(gate, "PillarR", Vector3(9.5, 4.2, 0.0), Vector3(2.2, 8.4, 2.6), _palette_safe(0), VIS_BUILDING)
	_add_static_box(gate, "ArchBeam", Vector3(0.0, 7.6, 0.0), Vector3(21.2, 1.8, 2.6), _palette_safe(3), VIS_BUILDING)
	_add_box_mesh(gate, "CrownBand", Vector3(0.0, 8.7, 0.0), Vector3(21.6, 0.45, 2.8), _mat_yellow, VIS_BUILDING)
	_add_label3d(gate, "GateSign", Vector3(0.0, 7.6, 1.45), title_txt, Color(1.0, 0.96, 0.85), 42, 65.0)
	_add_label3d(gate, "GateSignBack", Vector3(0.0, 7.6, -1.45), title_txt, Color(1.0, 0.96, 0.85), 42, 65.0, PI)


func _build_three_nile_bridges(web_core_only: bool = false) -> void:
	var bridges: Array[Dictionary] = [
		{"name": "GrandNileBridge", "z": 0.0, "color": _mat_white},
		{"name": "NorthernNileBridge", "z": -360.0, "color": _mat_concrete},
		{"name": "SouthernNileBridge", "z": 360.0, "color": _palette_safe(7)},
	]
	for b in bridges:
		var zc: float = b["z"]
		if web_core_only and absf(zc) > WEB_DISTRICT_RADIUS:
			continue
		var node := Node3D.new()
		node.name = b["name"]
		node.add_to_group("nile_bridges")
		node.position = Vector3(0.0, 0.0, zc)
		node.set_meta("bridge_bounds", Rect2(-288.0, zc - 7.0, 196.0, 14.0))
		_structures_root.add_child(node)

		# Flat span x in [-240 .. -140] -> center -190, width 100m, top at y = 6.2m (thickness 0.7m -> center y=5.85)
		_add_static_box(node, "Deck", Vector3(-190.0, 5.85, 0.0), Vector3(100.0, 0.7, 14.0), _mat_asphalt, VIS_BUILDING)
		_add_static_box(node, "RailNorth", Vector3(-190.0, 6.75, -6.7), Vector3(100.0, 1.1, 0.5), b["color"], VIS_BUILDING)
		_add_static_box(node, "RailSouth", Vector3(-190.0, 6.75, 6.7), Vector3(100.0, 1.1, 0.5), b["color"], VIS_BUILDING)

		# Steel/Concrete Arch Towers at x = -222 and -158
		for tx in [-222.0, -158.0]:
			for tz in [-6.8, 6.8]:
				_add_static_box(node, "Pylon_%d_%d" % [int(tx), int(tz)], Vector3(tx, 9.0, tz), Vector3(2.2, 18.0, 1.4), b["color"], VIS_BUILDING)
			_add_box_mesh(node, "CrossBrace_%d" % int(tx), Vector3(tx, 16.5, 0.0), Vector3(1.8, 1.2, 14.4), _mat_yellow, VIS_BUILDING)

		# Sturdy paired concrete bridge piers anchored cleanly down into the -4.2m Nile riverbed (y = -4.5 .. +5.55)
		# Plus bank portal piers at x = -240 (West bank) and x = -144.5 (East riverbank, leaving Corniche [-143..-130] open!)
		for px in [-240.0, -218.0, -196.0, -172.0, -144.5]:
			_add_bridge_pier_pair(node, "PierPair_%d" % int(absf(px)), px, -4.5, 5.55, 13.6, 4.5, 1.8)

		# Driveable 48m ramps (x in [-288..-240] and [-140..-92]): rise = 6.2m, run = 48.0m -> 7.36 deg <= 12 deg
		# Includes solid concrete retaining abutment enclosing the <4.2m low wedge + transition piers
		_add_driveable_ramp_x(node, "WestRamp", Vector3(-264.0, 0.0, 0.0), 48.0, 14.0, 6.2, true, _mat_asphalt, b["color"])
		_add_driveable_ramp_x(node, "EastRamp", Vector3(-116.0, 0.0, 0.0), 48.0, 14.0, 6.2, false, _mat_asphalt, b["color"])

		_ramps_audit.append({"name": b["name"], "angle_deg": rad_to_deg(atan2(6.2, 48.0))})
		_landmark_minimap_points.append({"pos": Vector3(-190.0, 0.0, zc), "tag": "BR", "color": Color(0.95, 0.85, 0.45)})

		# Police checkpoint officer on East approach of Grand & Northern Nile bridges
		if absf(zc) < 400.0:
			_role_stations.append({
				"role": "police",
				"district": "Nile Bridge Checkpoint",
				"label": "شرطي مرور الجسر",
				"position": Vector3(-92.0, 0.0, zc + 7.2),
				"yaw": PI,
				"lines": [
					"حركة المرور على الجسر تسير بانسيابية تامة.",
					"الرجاء الالتزام بالسرعة القانونية أعلى الكبري."
				],
			})


func _build_four_overpasses(web_core_only: bool = false) -> void:
	# 4 elevated highway overpasses: flat span 38m at y=6.2m (bottom 5.65m >= 5.5m clearance), two 48m ramps (7.36 deg)
	var defs: Array[Dictionary] = [
		{"name": "Overpass_Engineering", "pos": Vector3(220.0, 0.0, -200.0), "along_x": false},
		{"name": "Overpass_CentralEast", "pos": Vector3(400.0, 0.0, 0.0), "along_x": false},
		{"name": "Overpass_NorthernSpine", "pos": Vector3(220.0, 0.0, -360.0), "along_x": true},
		{"name": "Overpass_WestVillas", "pos": Vector3(-420.0, 0.0, -200.0), "along_x": false},
	]
	for od in defs:
		if web_core_only and (od["pos"] as Vector3).length() > WEB_DISTRICT_RADIUS:
			continue
		var node := Node3D.new()
		node.name = od["name"]
		node.position = od["pos"]
		if not od["along_x"]:
			node.rotation.y = PI * 0.5
		_structures_root.add_child(node)

		# Flat elevated deck (-19m .. +19m along local X), top at y = 6.2m (bottom y=5.6m clear over perpendicular road)
		_add_static_box(node, "Deck", Vector3(0.0, 5.9, 0.0), Vector3(38.0, 0.6, 14.0), _mat_asphalt, VIS_BUILDING)
		_add_static_box(node, "RailA", Vector3(0.0, 6.7, -6.75), Vector3(38.0, 1.0, 0.5), _mat_concrete, VIS_BUILDING)
		_add_static_box(node, "RailB", Vector3(0.0, 6.7, 6.75), Vector3(38.0, 1.0, 0.5), _mat_concrete, VIS_BUILDING)

		# Piers strictly outside +/-11m crossing road width
		for px in [-16.0, 16.0]:
			for pz in [-5.2, 5.2]:
				_add_static_box(node, "Pier_%d_%d" % [int(px), int(pz)], Vector3(px, 2.8, pz), Vector3(1.6, 5.6, 1.6), _mat_concrete, VIS_BUILDING)

		# Ramps (-67..-19 and +19..+67) -> total span 134m (-67..+67 -> matches +/-65m road breaks smoothly!)
		_add_driveable_ramp_x(node, "RampNeg", Vector3(-42.0, 0.0, 0.0), 46.0, 14.0, 6.2, true, _mat_asphalt, _mat_concrete)
		_add_driveable_ramp_x(node, "RampPos", Vector3(42.0, 0.0, 0.0), 46.0, 14.0, 6.2, false, _mat_asphalt, _mat_concrete)
		_ramps_audit.append({"name": od["name"], "angle_deg": rad_to_deg(atan2(6.2, 46.0))})


func _build_four_tunnels(web_core_only: bool = false) -> void:
	# 4 wide illuminated tunnels: width 16m, bore 52m covered, floor y=-6.8m, roof soffit y=-0.30m (clearance 6.50m >= 6.0m), 46m ramps (8.41 deg <= 12 deg)
	var defs: Array[Dictionary] = [
		{"name": "Tunnel_NorthCore", "pos": Vector3(0.0, 0.0, -200.0), "along_x": true},
		{"name": "Tunnel_SouthCentral", "pos": Vector3(220.0, 0.0, 200.0), "along_x": true},
		{"name": "Tunnel_EastDistrict", "pos": Vector3(400.0, 0.0, 200.0), "along_x": false},
		{"name": "Tunnel_WestBoulevard", "pos": Vector3(-420.0, 0.0, 200.0), "along_x": true},
	]
	for td in defs:
		if web_core_only and (td["pos"] as Vector3).length() > WEB_DISTRICT_RADIUS:
			continue
		var node := Node3D.new()
		node.name = td["name"]
		node.position = td["pos"]
		if not td["along_x"]:
			node.rotation.y = PI * 0.5
		_structures_root.add_child(node)

		# Central underground chamber (-26..+26 -> length 52m, width 16m, floor top y = -6.8m)
		_add_static_box(node, "Floor", Vector3(0.0, -7.1, 0.0), Vector3(52.0, 0.6, 16.0), _mat_asphalt, VIS_BUILDING)
		_add_static_box(node, "WallN", Vector3(0.0, -3.4, -8.3), Vector3(144.0, 7.0, 0.6), _mat_tunnel_wall, VIS_BUILDING)
		_add_static_box(node, "WallS", Vector3(0.0, -3.4, 8.3), Vector3(144.0, 7.0, 0.6), _mat_tunnel_wall, VIS_BUILDING)
		# Tunnel roof / surface road bridge deck (-26..+26, top at y=0.0, bottom at y=-0.30 -> 6.50m vertical clearance!)
		_add_static_box(node, "RoofDeck", Vector3(0.0, -0.15, 0.0), Vector3(52.0, 0.30, 16.8), _mat_asphalt, VIS_BUILDING)
		# Portal arches
		for sx in [-26.0, 26.0]:
			_add_static_box(node, "PortalBeam_%d" % int(sx), Vector3(sx, 0.45, 0.0), Vector3(1.4, 0.9, 17.6), _mat_concrete, VIS_BUILDING)
			_add_label3d(node, "PortalSign_%d" % int(sx), Vector3(sx + (0.85 if sx > 0 else -0.85), 0.55, 0.0), "نفق الخرطوم\nClearance 6.5m", Color(1.0, 0.92, 0.65), 32, 48.0, (PI * 0.5 if sx > 0 else -PI * 0.5))

		# Emissive ceiling light strips + 2 OmniLight3Ds inside tunnel
		for lx in [-16.0, 0.0, 16.0]:
			_add_box_mesh(node, "LightStrip_%d" % int(lx), Vector3(lx, -0.34, 0.0), Vector3(9.0, 0.08, 1.4), _mat_tunnel_strip, VIS_DETAIL)
		for lx in [-12.0, 12.0]:
			var omni := OmniLight3D.new()
			omni.name = "TunnelLamp_%d" % int(lx)
			omni.position = Vector3(lx, -1.2, 0.0)
			omni.light_color = Color(1.0, 0.91, 0.72)
			omni.light_energy = 2.6
			omni.omni_range = 24.0
			omni.shadow_enabled = false
			node.add_child(omni)

		# Safety guardrails at open trench sides outside roof (-72..-26 and +26..+72)
		for side_x in [-49.0, 49.0]:
			for gz in [-8.3, 8.3]:
				_add_static_box(node, "TrenchCurb_%d_%d" % [int(side_x), int(gz)], Vector3(side_x, 0.35, gz), Vector3(46.0, 0.7, 0.6), _mat_yellow, VIS_DETAIL)

		# Driveable downward ramps (-72..-26 and +26..+72): top y=0.0 at |x|=72 sloping down to y=-6.8 at |x|=26
		_add_tunnel_ramp_x(node, "RampNeg", -72.0, -26.0, -6.8, 16.0)
		_add_tunnel_ramp_x(node, "RampPos", 72.0, 26.0, -6.8, 16.0)

		var angle := rad_to_deg(atan2(6.8, 46.0))
		_ramps_audit.append({"name": td["name"], "angle_deg": angle})
		_tunnels_audit.append({"name": td["name"], "width": 16.0, "clearance": 6.50, "ramp_angle_deg": angle})


func _add_driveable_ramp_x(parent: Node3D, node_name: String, center_base: Vector3, run_len: float, width: float, rise: float, rises_toward_pos_x: bool, mat_top: Material, mat_side: Material) -> void:
	# Sloped box whose surface connects y=0.0 at one end to y=rise at the other end cleanly
	var hyp := sqrt(run_len * run_len + rise * rise)
	var angle := atan2(rise, run_len)
	var tilt := angle if rises_toward_pos_x else -angle
	var thickness := 0.55
	var sb := StaticBody3D.new()
	sb.name = node_name
	# Top surface at center_x sits at y = rise * 0.5; shift center down along tilted normal by thickness*0.5
	sb.position = Vector3(center_base.x, rise * 0.5 - thickness * 0.5 * cos(angle), center_base.z)
	sb.rotation.z = tilt
	parent.add_child(sb)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(hyp, thickness, width)
	bm.material = mat_top
	mi.mesh = bm
	mi.visibility_range_end = VIS_BUILDING
	sb.add_child(mi)

	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(hyp, thickness, width)
	col.shape = bs
	sb.add_child(col)

	# Side parapets on ramp (with solid collision so vehicles stay safely on the ramp!)
	for pz in [-width * 0.5 + 0.25, width * 0.5 - 0.25]:
		var rail := MeshInstance3D.new()
		var rbm := BoxMesh.new()
		rbm.size = Vector3(hyp, 0.75, 0.45)
		rbm.material = mat_side
		rail.mesh = rbm
		rail.position = Vector3(0.0, thickness * 0.5 + 0.35, pz)
		rail.visibility_range_end = VIS_BUILDING
		sb.add_child(rail)
		var rcol := CollisionShape3D.new()
		var rbs := BoxShape3D.new()
		rbs.size = Vector3(hyp, 0.75, 0.45)
		rcol.shape = rbs
		rcol.position = rail.position
		sb.add_child(rcol)

	# --------------------------------------------------------------------------
	# SOLID CONCRETE RETAINING WALL ABUTMENT UNDER LOW-CLEARANCE WEDGE (< 4.2m)
	# Prevents cars & NPCs from driving under the low triangular ramp wedge and clipping the deck,
	# while keeping the high span (>= 4.2m clearance) wide open over riverside roads/avenues!
	# --------------------------------------------------------------------------
	var clear_cutoff := 4.20
	var vertical_slab := thickness / maxf(0.5, cos(angle))
	var t_cut := clampf((clear_cutoff + vertical_slab) / maxf(0.1, rise), 0.15, 1.0)
	var x_toe := center_base.x - run_len * 0.5 if rises_toward_pos_x else center_base.x + run_len * 0.5
	var x_high := center_base.x + run_len * 0.5 if rises_toward_pos_x else center_base.x - run_len * 0.5
	var x_cut := lerpf(x_toe, x_high, t_cut)
	var y_top_cut := clear_cutoff + 0.04 # Tucked cleanly into the underside of the sloped deck slab
	var y_bot := -0.35
	var half_w := width * 0.5 - 0.12

	var abut := StaticBody3D.new()
	abut.name = node_name + "_UnderRampAbutment"
	abut.add_to_group("bridge_abutments")
	parent.add_child(abut)

	# 1. Exact 8-vertex sloped retaining concrete wedge mesh + pilaster ribs merged into 1 ArrayMesh
	var amesh := _build_under_ramp_abutment_mesh(x_toe, x_cut, y_bot, y_top_cut, center_base.z, half_w)
	var ami := MeshInstance3D.new()
	ami.name = "RetainingWallMesh"
	ami.mesh = amesh
	ami.visibility_range_end = VIS_BUILDING
	ami.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	abut.add_child(ami)

	# 2. Exact matching ConvexPolygonShape3D collision closing off the entire <4.2m wedge
	var cshape := ConvexPolygonShape3D.new()
	cshape.points = PackedVector3Array([
		Vector3(x_toe, y_bot, center_base.z - half_w),
		Vector3(x_toe, y_bot, center_base.z + half_w),
		Vector3(x_toe, 0.02, center_base.z - half_w),
		Vector3(x_toe, 0.02, center_base.z + half_w),
		Vector3(x_cut, y_bot, center_base.z - half_w),
		Vector3(x_cut, y_bot, center_base.z + half_w),
		Vector3(x_cut, y_top_cut, center_base.z - half_w),
		Vector3(x_cut, y_top_cut, center_base.z + half_w),
	])
	var acs := CollisionShape3D.new()
	acs.name = "AbutmentConvexCol"
	acs.shape = cshape
	abut.add_child(acs)

	# 3. Sturdy paired concrete support columns right at the 4.2m clearance transition edge
	if t_cut < 0.98:
		_add_bridge_pier_pair(parent, node_name + "_TransitionPiers", x_cut, -0.35, y_top_cut + 0.08, width - 0.4, width * 0.5 - 1.35, 1.45)


func _add_bridge_pier_pair(parent: Node3D, node_name: String, x_pos: float, y_bot: float, y_top: float, beam_width: float, col_z_off: float, col_size: float) -> void:
	var h := maxf(1.0, y_top - y_bot)
	var cap_h := 0.72
	var col_h := maxf(0.5, h - cap_h)
	var col_cy := y_bot + col_h * 0.5
	var cap_cy := y_top - cap_h * 0.5

	var sb := StaticBody3D.new()
	sb.name = node_name
	sb.add_to_group("bridge_piers")
	parent.add_child(sb)

	var b := InteriorMeshBatcher.new()
	var mat_pier := _mat_concrete
	var mat_cap := InteriorMeshBatcher.get_color_mat("br_pier_cap", Color(0.68, 0.65, 0.60), 0.86)

	for sz: float in [-col_z_off, col_z_off]:
		b.add_box(Vector3(x_pos, col_cy, sz), Vector3(col_size, col_h, col_size), mat_pier)
		# Concrete pedestal base footing
		b.add_box(Vector3(x_pos, y_bot + 0.35, sz), Vector3(col_size + 0.45, 0.70, col_size + 0.45), mat_cap)
		InteriorMeshBatcher.add_box_collider(sb, "PierCol_%.0f" % sz, Vector3(x_pos, col_cy, sz), Vector3(col_size, col_h, col_size))

	# Horizontal pier cap beam tying both concrete columns under the deck
	b.add_box(Vector3(x_pos, cap_cy, 0.0), Vector3(col_size + 0.45, cap_h, beam_width), mat_cap)
	InteriorMeshBatcher.add_box_collider(sb, "PierCapCol", Vector3(x_pos, cap_cy, 0.0), Vector3(col_size + 0.45, cap_h, beam_width))

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.visibility_range_end = VIS_BUILDING
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sb.add_child(mi)


func _build_under_ramp_abutment_mesh(x_toe: float, x_cut: float, y_bot: float, y_top_cut: float, z_ctr: float, half_w: float) -> ArrayMesh:
	# Normalize X ordering so x_lo < x_hi for consistent outward clockwise winding
	var x_lo := x_toe
	var y_lo_t := 0.02
	var x_hi := x_cut
	var y_hi_t := y_top_cut
	if x_lo > x_hi:
		x_lo = x_cut
		y_lo_t = y_top_cut
		x_hi = x_toe
		y_hi_t = 0.02

	var z0 := z_ctr - half_w
	var z1 := z_ctr + half_w

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat_wall := InteriorMeshBatcher.get_pbr_mat("br_abut_wall", "res://assets/textures/plaster", Color(0.76, 0.73, 0.67), 0.90, Vector3(0.18, 0.18, 0.18))
	st.set_material(mat_wall)

	var v000 := Vector3(x_lo, y_bot, z0)
	var v100 := Vector3(x_hi, y_bot, z0)
	var v110 := Vector3(x_hi, y_hi_t, z0)
	var v010 := Vector3(x_lo, y_lo_t, z0)
	var v001 := Vector3(x_lo, y_bot, z1)
	var v101 := Vector3(x_hi, y_bot, z1)
	var v111 := Vector3(x_hi, y_hi_t, z1)
	var v011 := Vector3(x_lo, y_lo_t, z1)

	# Outward CW faces for Godot 4
	_add_abut_quad(st, v010, v110, v111, v011) # Top sloped face
	_add_abut_quad(st, v001, v101, v100, v000) # Bottom
	_add_abut_quad(st, v001, v011, v111, v101) # South (+Z) exterior retaining wall
	_add_abut_quad(st, v100, v110, v010, v000) # North (-Z) exterior retaining wall
	_add_abut_quad(st, v101, v111, v110, v100) # East (+X) end wall
	_add_abut_quad(st, v000, v010, v011, v001) # West (-X) end wall

	var am := st.commit()

	# Add architectural concrete pilaster ribs along both retaining walls (surface 1)
	var rib_b := InteriorMeshBatcher.new()
	var mat_rib := InteriorMeshBatcher.get_color_mat("br_abut_rib", Color(0.66, 0.63, 0.58), 0.88)
	var span_x := absf(x_cut - x_toe)
	var n_ribs := maxi(2, int(round(span_x / 6.0)))
	for ri in range(1, n_ribs):
		var t := float(ri) / float(n_ribs)
		var rx := lerpf(x_toe, x_cut, t)
		var rh := lerpf(0.02, y_top_cut, t) - y_bot
		if rh < 0.45:
			continue
		for sz_side: float in [-1.0, 1.0]:
			rib_b.add_box(Vector3(rx, y_bot + rh * 0.5, z_ctr + sz_side * (half_w + 0.07)), Vector3(0.42, rh, 0.16), mat_rib)
	if not rib_b.is_empty():
		var rib_am := rib_b.commit()
		var arrays := rib_am.surface_get_arrays(0)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(am.get_surface_count() - 1, mat_rib)
	return am


func _add_abut_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (c - a).cross(b - a).normalized()
	if n.length_squared() < 0.0001:
		return
	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_normal(n); st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_normal(n); st.set_uv(Vector2(0, 1)); st.add_vertex(d)


func _add_tunnel_ramp_x(parent: Node3D, node_name: String, x_surface: float, x_deep: float, deep_y: float, width: float) -> void:
	var run_len := absf(x_deep - x_surface)
	var drop := absf(deep_y)
	var hyp := sqrt(run_len * run_len + drop * drop)
	var angle := atan2(drop, run_len)
	# If x_deep > x_surface (x_surface = -72, x_deep = -26), height drops as x increases -> negative rotation.z
	var tilt := -angle if x_deep > x_surface else angle
	var thickness := 0.5
	var cx := (x_surface + x_deep) * 0.5

	var sb := StaticBody3D.new()
	sb.name = node_name
	sb.position = Vector3(cx, deep_y * 0.5 - thickness * 0.5 * cos(angle), 0.0)
	sb.rotation.z = tilt
	parent.add_child(sb)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(hyp, thickness, width)
	bm.material = _mat_asphalt
	mi.mesh = bm
	mi.visibility_range_end = VIS_BUILDING
	sb.add_child(mi)

	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(hyp, thickness, width)
	col.shape = bs
	sb.add_child(col)


func _build_landmarks_and_bakeries_web() -> void:
	var core_bakery := Node3D.new()
	core_bakery.name = "AutomatedBakery_AlAzhariCore"
	core_bakery.position = Vector3(26.5, 0.0, -14.5)
	core_bakery.set_script(preload("res://scripts/automated_bakery.gd"))
	core_bakery.bakery_title = "مخبز الأزهري الآلي"
	core_bakery.district_name = "Al-Azhari Historic Core"
	_landmarks_root.add_child(core_bakery)
	var c_counter := Node3D.new()
	c_counter.name = "BakeryCounter"
	core_bakery.add_child(c_counter)
	_landmark_minimap_points.append({"pos": Vector3(26.5, 0.0, -14.5), "tag": "B", "color": Color(0.98, 0.74, 0.25)})

	var bakeries: Array[Dictionary] = [
		{"name": "AutomatedBakery_CornicheNorth", "title": "مخبز الكورنيش الآلي", "district": "Nile Corniche & Marina District", "pos": Vector3(-76.0, 0.0, -230.0), "yaw": 0.0},
		{"name": "AutomatedBakery_YouthSouth", "title": "مخبز حي الشباب الآلي", "district": "Sports & Youth District", "pos": Vector3(155.0, 0.0, 245.0), "yaw": PI},
	]
	for bk in bakeries:
		if (bk["pos"] as Vector3).length() > WEB_DISTRICT_RADIUS:
			continue
		var inst: Node3D = SCENE_BAKERY.instantiate()
		inst.name = bk["name"]
		inst.position = bk["pos"]
		inst.rotation.y = bk["yaw"]
		if "bakery_title" in inst:
			inst.bakery_title = bk["title"]
		if "district_name" in inst:
			inst.district_name = bk["district"]
		_landmarks_root.add_child(inst)
		_reserve_footprint(bk["pos"], Vector2(18.0, 16.0), bk["name"], "bakery")
		_built_buildings_count += 1
		_landmark_minimap_points.append({"pos": bk["pos"], "tag": "B", "color": Color(0.98, 0.74, 0.25)})
		await get_tree().process_frame

	var mosques: Array[Dictionary] = [
		{"scene": SCENE_MOSQUE_NILE, "name": "Mosque_NileGrand", "title": "مسجد النيل الكبير", "pos": Vector3(-76.0, 0.0, -285.0), "yaw": -PI * 0.5, "size": Vector2(34.0, 34.0)},
		{"scene": SCENE_MOSQUE_ALNOOR, "name": "Mosque_AlNoor", "title": "مسجد النور", "pos": Vector3(145.0, 0.0, -275.0), "yaw": 0.0, "size": Vector2(22.0, 22.0)},
	]
	for mq in mosques:
		if (mq["pos"] as Vector3).length() > WEB_DISTRICT_RADIUS:
			continue
		var m_inst: Node3D = mq["scene"].instantiate()
		m_inst.name = mq["name"]
		m_inst.position = mq["pos"]
		m_inst.rotation.y = mq["yaw"]
		_landmarks_root.add_child(m_inst)
		_reserve_footprint(mq["pos"], mq["size"], mq["name"], "mosque")
		_built_buildings_count += 1
		_landmark_minimap_points.append({"pos": mq["pos"], "tag": "M", "color": Color(0.32, 0.88, 0.48)})
		await get_tree().process_frame

	if Vector3(75.0, 0.0, 245.0).length() <= WEB_DISTRICT_RADIUS:
		_build_barber_shop("BarberShop_Youth", Vector3(75.0, 0.0, 245.0), PI, "Sports & Youth District")


func _build_landmarks_and_bakeries() -> void:
	# 1. Mount AutomatedBakery zone over existing Bakery #1 inside CommercialStrip (26.5, 0, -14.5)
	var core_bakery := Node3D.new()
	core_bakery.name = "AutomatedBakery_AlAzhariCore"
	core_bakery.position = Vector3(26.5, 0.0, -14.5)
	core_bakery.set_script(preload("res://scripts/automated_bakery.gd"))
	core_bakery.bakery_title = "مخبز الأزهري الآلي"
	core_bakery.district_name = "Al-Azhari Historic Core"
	_landmarks_root.add_child(core_bakery)
	var c_counter := Node3D.new()
	c_counter.name = "BakeryCounter"
	core_bakery.add_child(c_counter)
	_role_stations.append({
		"role": "baker",
		"district": "Al-Azhari Historic Core",
		"label": "خباز الأزهري",
		"position": Vector3(26.5, 0.0, -16.8),
		"yaw": 0.0,
		"lines": [
			"العيش البلدي الساخن طالع من الفرن الآن!",
			"اضغط [E] لشراء رغيف طازج يمنحك طاقة وجري أسرع."
		],
	})
	_landmark_minimap_points.append({"pos": Vector3(26.5, 0.0, -14.5), "tag": "B", "color": Color(0.98, 0.74, 0.25)})

	# 2. Place 5 new Automated Bakeries across the expanded districts (total = 6 bakeries)
	var bakeries: Array[Dictionary] = [
		{"name": "AutomatedBakery_CornicheNorth", "title": "مخبز الكورنيش الآلي", "district": "Nile Corniche & Marina District", "pos": Vector3(-76.0, 0.0, -230.0), "yaw": 0.0},
		{"name": "AutomatedBakery_WestVillas", "title": "مخبز الضفة الغربية الآلي", "district": "West Bank Modern Villas", "pos": Vector3(-345.0, 0.0, 115.0), "yaw": PI * 0.5},
		{"name": "AutomatedBakery_Engineering", "title": "مخبز المنطقة الهندسية الآلي", "district": "Engineering & Infrastructure Zone", "pos": Vector3(475.0, 0.0, -245.0), "yaw": 0.0},
		{"name": "AutomatedBakery_MarketEast", "title": "مخبز السوق التجاري الآلي", "district": "Central Commercial & Market Boulevard", "pos": Vector3(295.0, 0.0, -245.0), "yaw": 0.0},
		{"name": "AutomatedBakery_YouthSouth", "title": "مخبز حي الشباب الآلي", "district": "Sports & Youth District", "pos": Vector3(155.0, 0.0, 245.0), "yaw": PI},
	]
	for bk in bakeries:
		var inst: Node3D = SCENE_BAKERY.instantiate()
		inst.name = bk["name"]
		inst.position = bk["pos"]
		inst.rotation.y = bk["yaw"]
		if "bakery_title" in inst:
			inst.bakery_title = bk["title"]
		if "district_name" in inst:
			inst.district_name = bk["district"]
		_landmarks_root.add_child(inst)
		_reserve_footprint(bk["pos"], Vector2(18.0, 16.0), bk["name"], "bakery")
		_built_buildings_count += 1
		var baker_local := Vector3(-1.5, 0.0, 1.8).rotated(Vector3.UP, bk["yaw"])
		_role_stations.append({
			"role": "baker",
			"district": bk["district"],
			"label": "الخباز - " + bk["title"],
			"position": bk["pos"] + baker_local,
			"yaw": bk["yaw"],
			"lines": [
				"أهلاً بك في %s!" % bk["title"],
				"رغيف ساخن بالضغط على [E] يمنحك نشاط وحيوية 45 ثانية."
			],
		})
		_landmark_minimap_points.append({"pos": bk["pos"], "tag": "B", "color": Color(0.98, 0.74, 0.25)})

	# 3. Place the 3 New Distinct Mosques (total = 4 mosques counting existing Al-Azhari Mosque)
	var mosques: Array[Dictionary] = [
		{"scene": SCENE_MOSQUE_NILE, "name": "Mosque_NileGrand", "title": "مسجد النيل الكبير", "pos": Vector3(-76.0, 0.0, -285.0), "yaw": -PI * 0.5, "size": Vector2(34.0, 34.0)},
		{"scene": SCENE_MOSQUE_WEST, "name": "Mosque_WestHeritage", "title": "مسجد التراث الغربي", "pos": Vector3(-345.0, 0.0, -90.0), "yaw": PI * 0.5, "size": Vector2(26.0, 26.0)},
		{"scene": SCENE_MOSQUE_ALNOOR, "name": "Mosque_AlNoor", "title": "مسجد النور", "pos": Vector3(145.0, 0.0, -275.0), "yaw": 0.0, "size": Vector2(22.0, 22.0)},
	]
	for mq in mosques:
		var m_inst: Node3D = mq["scene"].instantiate()
		m_inst.name = mq["name"]
		m_inst.position = mq["pos"]
		m_inst.rotation.y = mq["yaw"]
		_landmarks_root.add_child(m_inst)
		_reserve_footprint(mq["pos"], mq["size"], mq["name"], "mosque")
		_built_buildings_count += 1
		_landmark_minimap_points.append({"pos": mq["pos"], "tag": "M", "color": Color(0.32, 0.88, 0.48)})

	# 4. Civic & Emergency Quarter Landmarks (Health Center, Duty Pharmacy, Police HQ, Fire Station)
	_build_health_center("MainHealthCenter", "المستشفى ومركز الرعاية الأولية\nMain Health Center", Vector3(310.0, 0.0, 78.0), -PI * 0.5, "Civic & Emergency Quarter")
	_build_health_center("WestBankClinic", "عيادة الضفة الغربية وصيدلية المناوبة\nWest Bank Health Clinic", Vector3(-485.0, 0.0, -90.0), PI * 0.5, "West Bank Modern Villas")
	_build_pharmacy("DutyPharmacy_EastMarket", "صيدلية الشفاء المناوبة\nDuty Pharmacy 24h", Vector3(310.0, 0.0, -145.0), -PI * 0.5, "Central Commercial & Market Boulevard")
	_build_police_hq(Vector3(310.0, 0.0, 145.0), -PI * 0.5)
	_build_fire_station(Vector3(465.0, 0.0, 105.0), -PI * 0.5)

	# 5. Engineering & Infrastructure Zone Landmarks (Engineering HQ + Cranes + Material Yard)
	_build_engineering_hq(Vector3(485.0, 0.0, -95.0), -PI * 0.5)
	_build_tower_crane("TowerCrane_North", Vector3(495.0, 0.0, -295.0), "Engineering & Infrastructure Zone")
	_build_tower_crane("TowerCrane_WestYard", Vector3(325.0, 0.0, -455.0), "Engineering & Infrastructure Zone")

	# 6. Barber Shops (صالون حلاقة) across Districts
	_build_barber_shop("BarberShop_West", Vector3(-345.0, 0.0, 55.0), PI * 0.5, "West Bank Modern Villas")
	_build_barber_shop("BarberShop_Youth", Vector3(75.0, 0.0, 245.0), PI, "Sports & Youth District")

	# 7. Sports & Youth District Daffori Stadium & Youth Center
	_build_stadium(Vector3(145.0, 0.0, 445.0))


func _reserve_footprint(pos: Vector3, size_xz: Vector2, b_name: String, b_type: String) -> void:
	_blocked_rects.append(Rect2(pos.x - size_xz.x * 0.5 - 3.0, pos.z - size_xz.y * 0.5 - 3.0, size_xz.x + 6.0, size_xz.y + 6.0))
	_building_records.append({"name": b_name, "type": b_type, "pos": pos, "size": size_xz})


func _build_health_center(n_name: String, title_txt: String, pos: Vector3, yaw: float, district: String) -> void:
	var root := _make_landmark_root(n_name, pos, yaw, Vector2(24.0, 18.0), "health")
	_add_static_box(root, "MainBlock", Vector3(0, 4.0, 0), Vector3(20.0, 8.0, 14.0), _mat_white, VIS_BUILDING)
	_add_static_box(root, "PharmacyWing", Vector3(0, 2.2, 8.2), Vector3(12.0, 4.4, 3.0), _palette_safe(8), VIS_BUILDING)
	_add_box_mesh(root, "RedCrossV", Vector3(0, 6.0, 7.1), Vector3(1.1, 3.4, 0.25), _mat_red, VIS_BUILDING)
	_add_box_mesh(root, "RedCrossH", Vector3(0, 6.0, 7.1), Vector3(3.4, 1.1, 0.25), _mat_red, VIS_BUILDING)
	_add_box_mesh(root, "Canopy", Vector3(0, 3.8, 9.8), Vector3(7.0, 0.3, 2.6), _mat_blue, VIS_DETAIL)
	_add_label3d(root, "Sign", Vector3(0, 8.9, 7.2), title_txt, Color(0.95, 0.99, 1.0), 34, 48.0)

	var doc_pos := pos + Vector3(-2.8, 0.0, 9.4).rotated(Vector3.UP, yaw)
	var pharm_pos := pos + Vector3(2.8, 0.0, 9.4).rotated(Vector3.UP, yaw)
	_role_stations.append({
		"role": "doctor",
		"district": district,
		"label": "الطبيب المناوب",
		"position": doc_pos,
		"yaw": yaw,
		"lines": [
			"مرحباً بك في العيادة! الطاقم الطبي جاهز على مدار الساعة.",
			"الفحص الأولي والإسعافات الأولية متوفرة هنا."
		],
	})
	_role_stations.append({
		"role": "pharmacist",
		"district": district,
		"label": "الصيدلي",
		"position": pharm_pos,
		"yaw": yaw,
		"lines": [
			"أهلاً، الصيدلية توفر كل الأدوية والوصفات الطبية.",
			"نتمنى لك دوام الصحة والعافية."
		],
	})
	_landmark_minimap_points.append({"pos": pos, "tag": "H", "color": Color(0.96, 0.32, 0.32)})


func _build_pharmacy(n_name: String, title_txt: String, pos: Vector3, yaw: float, district: String) -> void:
	var root := _make_landmark_root(n_name, pos, yaw, Vector2(14.0, 12.0), "pharmacy")
	_add_static_box(root, "Body", Vector3(0, 2.5, 0), Vector3(11.0, 5.0, 9.0), _mat_white, VIS_BUILDING)
	_add_box_mesh(root, "GreenStripe", Vector3(0, 4.6, 4.6), Vector3(11.2, 0.65, 0.25), _mat_green, VIS_DETAIL)
	_add_box_mesh(root, "CrossV", Vector3(4.0, 3.4, 4.65), Vector3(0.55, 1.6, 0.2), _mat_green, VIS_DETAIL)
	_add_box_mesh(root, "CrossH", Vector3(4.0, 3.4, 4.65), Vector3(1.6, 0.55, 0.2), _mat_green, VIS_DETAIL)
	_add_box_mesh(root, "Counter", Vector3(0, 0.55, 5.2), Vector3(5.5, 1.1, 1.0), _mat_white, VIS_DETAIL)
	_add_label3d(root, "Sign", Vector3(0, 5.6, 4.8), title_txt, Color(0.85, 1.0, 0.88), 32, 42.0)

	_role_stations.append({
		"role": "pharmacist",
		"district": district,
		"label": "صيدلي المناوبة",
		"position": pos + Vector3(0.0, 0.0, 5.8).rotated(Vector3.UP, yaw),
		"yaw": yaw,
		"lines": [
			"صيدلية المناوبة مفتوحة 24 ساعة لخدمة أهل الحي.",
			"تفضل بطلب الدواء أو الفيتامينات."
		],
	})


func _build_police_hq(pos: Vector3, yaw: float) -> void:
	var root := _make_landmark_root("PoliceHQ", pos, yaw, Vector2(24.0, 18.0), "police")
	_add_static_box(root, "MainBlock", Vector3(0, 4.0, 0), Vector3(20.0, 8.0, 14.0), _palette_safe(6), VIS_BUILDING)
	_add_box_mesh(root, "NavyStripe", Vector3(0, 7.3, 7.1), Vector3(20.2, 1.1, 0.3), _mat_blue, VIS_BUILDING)
	_add_static_box(root, "GuardBooth", Vector3(-6.5, 1.4, 8.8), Vector3(2.8, 2.8, 2.8), _mat_white, VIS_DETAIL)
	_add_label3d(root, "Sign", Vector3(0, 8.8, 7.2), "قسم الشرطة المركزي\nCentral Police HQ", Color(0.75, 0.88, 1.0), 36, 48.0)

	for offset in [Vector3(-4.0, 0.0, 9.2), Vector3(3.5, 0.0, 9.2)]:
		_role_stations.append({
			"role": "police",
			"district": "Civic & Emergency Quarter",
			"label": "ضابط شرطة القسم",
			"position": pos + offset.rotated(Vector3.UP, yaw),
			"yaw": yaw,
			"lines": [
				"أهلاً بك في قسم شرطة الأزهري المركزي.",
				"الدوريات متواجدة لتأمين جميع الشوارع والجسور."
			],
		})
	_landmark_minimap_points.append({"pos": pos, "tag": "P", "color": Color(0.28, 0.56, 0.98)})


func _build_fire_station(pos: Vector3, yaw: float) -> void:
	var root := _make_landmark_root("FireStation", pos, yaw, Vector2(24.0, 18.0), "fire")
	_add_static_box(root, "MainHall", Vector3(0, 3.6, 0), Vector3(20.0, 7.2, 14.0), _palette_safe(2), VIS_BUILDING)
	_add_box_mesh(root, "RedTrim", Vector3(0, 6.8, 7.1), Vector3(20.2, 1.2, 0.3), _mat_red, VIS_BUILDING)
	_add_box_mesh(root, "GarageBay1", Vector3(-4.5, 2.2, 7.08), Vector3(5.2, 4.4, 0.2), _mat_red, VIS_DETAIL)
	_add_box_mesh(root, "GarageBay2", Vector3(4.5, 2.2, 7.08), Vector3(5.2, 4.4, 0.2), _mat_red, VIS_DETAIL)
	_add_label3d(root, "Sign", Vector3(0, 8.4, 7.2), "مركز الإطفاء والدفاع المدني\nCivil Defense & Fire Station", Color(1.0, 0.85, 0.80), 36, 48.0)

	_role_stations.append({
		"role": "firefighter",
		"district": "Civic & Emergency Quarter",
		"label": "رجل الإطفاء",
		"position": pos + Vector3(0.0, 0.0, 8.8).rotated(Vector3.UP, yaw),
		"yaw": yaw,
		"lines": [
			"فريق الدفاع المدني على أهبة الاستعداد دائماً.",
			"سيارات الإطفاء جاهزة للتحرك الفوري لأي طارئ."
		],
	})


func _build_engineering_hq(pos: Vector3, yaw: float) -> void:
	var root := _make_landmark_root("EngineeringHQ", pos, yaw, Vector2(24.0, 18.0), "engineering")
	_add_static_box(root, "MainBlock", Vector3(0, 4.2, 0), Vector3(20.0, 8.4, 14.0), _mat_concrete, VIS_BUILDING)
	_add_box_mesh(root, "SafetyStripe", Vector3(0, 7.8, 7.1), Vector3(20.2, 0.9, 0.25), _mat_yellow, VIS_BUILDING)
	_add_static_box(root, "BlueprintTable", Vector3(0, 0.55, 8.6), Vector3(4.4, 1.1, 1.6), _mat_wood, VIS_DETAIL)
	_add_label3d(root, "Sign", Vector3(0, 9.2, 7.2), "مركز الهندسة والإنشاءات\nCivil Engineering HQ", Color(1.0, 0.94, 0.65), 36, 48.0)

	for ox in [-3.0, 3.0]:
		_role_stations.append({
			"role": "engineer",
			"district": "Engineering & Infrastructure Zone",
			"label": "مهندس الموقع المدني",
			"position": pos + Vector3(ox, 0.0, 9.5).rotated(Vector3.UP, yaw),
			"yaw": yaw,
			"lines": [
				"نراجع الآن المخططات الإنشائية للجسور والأنفاق الجديدة.",
				"كل الطرق والجسور مصممة بمواصفات هندسية عالية."
			],
		})
	_landmark_minimap_points.append({"pos": pos, "tag": "E", "color": Color(0.98, 0.78, 0.18)})


func _build_tower_crane(c_name: String, pos: Vector3, district: String) -> void:
	var root := _make_landmark_root(c_name, pos, 0.4, Vector2(12.0, 12.0), "crane")
	_add_static_box(root, "BaseBlock", Vector3(0, 0.9, 0), Vector3(5.0, 1.8, 5.0), _mat_concrete, VIS_BUILDING)
	_add_static_box(root, "Mast", Vector3(0, 16.0, 0), Vector3(1.8, 30.0, 1.8), _mat_yellow, VIS_BUILDING)
	_add_box_mesh(root, "Jib", Vector3(9.0, 29.5, 0), Vector3(28.0, 1.4, 1.4), _mat_yellow, VIS_BUILDING)
	_add_box_mesh(root, "CounterWeight", Vector3(-6.5, 29.0, 0), Vector3(3.2, 2.2, 2.2), _mat_concrete, VIS_BUILDING)
	_add_static_box(root, "SiteOffice", Vector3(-5.0, 1.4, 4.2), Vector3(4.5, 2.8, 3.0), _palette_safe(6), VIS_DETAIL)

	_role_stations.append({
		"role": "engineer",
		"district": district,
		"label": "مهندس الرافعة والموقع",
		"position": pos + Vector3(-5.0, 0.0, 6.2),
		"yaw": 0.0,
		"lines": [
			"منطقة عمل إنشائية: يرجى ارتداء الخوذة الواقية!",
			"نعمل على تشييد أبراج سكنية وتجارية حديثة."
		],
	})


func _build_barber_shop(b_name: String, pos: Vector3, yaw: float, district: String) -> void:
	var root := _make_landmark_root(b_name, pos, yaw, Vector2(12.0, 10.0), "barber")
	_add_static_box(root, "ShopBody", Vector3(0, 2.1, 0), Vector3(9.0, 4.2, 7.5), _palette_safe(8), VIS_BUILDING)
	_add_cylinder_mesh(root, "BarberPole", Vector3(-3.8, 2.0, 4.1), 0.2, 2.2, _mat_red, VIS_DETAIL)
	_add_box_mesh(root, "Window", Vector3(0.5, 2.0, 3.82), Vector3(4.6, 2.0, 0.12), _mat_glass, VIS_DETAIL)
	_add_label3d(root, "Sign", Vector3(0, 4.8, 3.95), "صالون الأناقة\nBarber Shop", Color(0.90, 0.96, 1.0), 30, 36.0)

	_role_stations.append({
		"role": "barber",
		"district": district,
		"label": "الحلاق",
		"position": pos + Vector3(0.5, 0.0, 4.6).rotated(Vector3.UP, yaw),
		"yaw": yaw,
		"lines": [
			"نعيماً مقدماً! الصالون جاهز لخدمتك.",
			"حلاقة عصرية وتهذيب أنيق على الطريقة السودانية."
		],
	})


func _build_stadium(pos: Vector3) -> void:
	var root := _make_landmark_root("DafforiStadium", pos, 0.0, Vector2(68.0, 48.0), "stadium")
	_add_box_mesh(root, "Pitch", Vector3(0, 0.06, 0), Vector3(54.0, 0.08, 34.0), _mat_green, VIS_BUILDING)
	_add_box_mesh(root, "CenterLine", Vector3(0, 0.12, 0), Vector3(0.35, 0.04, 33.5), _mat_white, VIS_DETAIL)
	_add_static_box(root, "NorthStand", Vector3(0, 2.2, -20.0), Vector3(58.0, 4.4, 5.5), _mat_concrete, VIS_BUILDING)
	_add_static_box(root, "SouthStand", Vector3(0, 2.2, 20.0), Vector3(58.0, 4.4, 5.5), _mat_concrete, VIS_BUILDING)
	for lx in [-26.0, 26.0]:
		for lz in [-18.0, 18.0]:
			_add_cylinder_mesh(root, "FloodMast_%d_%d" % [int(lx), int(lz)], Vector3(lx, 7.5, lz), 0.35, 15.0, _mat_steel, VIS_BUILDING)
			_add_box_mesh(root, "FloodLight_%d_%d" % [int(lx), int(lz)], Vector3(lx, 15.1, lz), Vector3(2.4, 1.0, 1.0), _mat_lamp_glow, VIS_BUILDING)
	_add_label3d(root, "Sign", Vector3(0, 6.2, -23.0), "ملعب دافوري الشبابي\nAl-Azhari Youth Stadium", Color(0.82, 1.0, 0.84), 42, 65.0, PI)
	_landmark_minimap_points.append({"pos": pos, "tag": "S", "color": Color(0.45, 0.92, 0.45)})


func _make_landmark_root(n_name: String, pos: Vector3, yaw: float, footprint: Vector2, b_type: String) -> Node3D:
	var root := Node3D.new()
	root.name = n_name
	root.position = pos
	root.rotation.y = yaw
	_landmarks_root.add_child(root)
	var rot_size := Vector2(footprint.y, footprint.x) if absf(sin(yaw)) > 0.7 else footprint
	_reserve_footprint(pos, rot_size, n_name, b_type)
	_built_buildings_count += 1
	return root


func _build_eight_district_cities_web() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261118
	var blocks: Array[Dictionary] = [
		{"district": "South Al-Azhari Extension", "x0": 16.0, "x1": 208.0, "z0": 158.0, "z1": 188.0, "step_x": 30.0, "step_z": 32.0, "styles": [0, 1, 5, 2], "min_f": 1, "max_f": 2, "compact": true},
		{"district": "South Corniche Infill", "x0": -102.0, "x1": -14.0, "z0": 158.0, "z1": 188.0, "step_x": 30.0, "step_z": 32.0, "styles": [0, 1, 5, 2], "min_f": 1, "max_f": 3, "compact": true},
		{"district": "South Al-Azhari Extension", "x0": 16.0, "x1": 208.0, "z0": 212.0, "z1": 244.0, "step_x": 32.0, "step_z": 34.0, "styles": [0, 1, 5, 2], "min_f": 1, "max_f": 2, "compact": true},
		{"district": "Nile Corniche & Marina District", "x0": -98.0, "x1": -20.0, "z0": -310.0, "z1": -230.0, "step_x": 36.0, "step_z": 38.0, "styles": [1, 2, 3, 4], "min_f": 2, "max_f": 4},
		{"district": "Nile Corniche & Marina District", "x0": -98.0, "x1": -20.0, "z0": 228.0, "z1": 310.0, "step_x": 36.0, "step_z": 38.0, "styles": [1, 2, 3, 5], "min_f": 2, "max_f": 4},
		{"district": "Central Commercial & Market Boulevard", "x0": 24.0, "x1": 200.0, "z0": -310.0, "z1": -225.0, "step_x": 36.0, "step_z": 38.0, "styles": [2, 3, 4, 1], "min_f": 2, "max_f": 4},
		{"district": "Sports & Youth District", "x0": 24.0, "x1": 240.0, "z0": 235.0, "z1": 310.0, "step_x": 38.0, "step_z": 38.0, "styles": [0, 1, 2, 3, 5], "min_f": 1, "max_f": 3},
	]
	var b_idx := 0
	var spawned_since_yield := 0
	for blk in blocks:
		var styles: Array = blk["styles"]
		var is_compact: bool = bool(blk.get("compact", false))
		var x: float = blk["x0"] + (12.0 if is_compact else 14.0)
		while x <= blk["x1"] - (10.0 if is_compact else 12.0):
			var z: float = blk["z0"] + 14.0
			while z <= blk["z1"] - (10.0 if is_compact else 12.0):
				var jx := x + rng.randf_range(-1.4, 1.4) if is_compact else x + rng.randf_range(-2.8, 2.8)
				var jz := z + rng.randf_range(-1.2, 1.2) if is_compact else z + rng.randf_range(-2.8, 2.8)
				if Vector2(jx, jz).length() <= WEB_DISTRICT_RADIUS:
					var w := rng.randf_range(11.0, 14.5) if is_compact else rng.randf_range(12.5, 19.5)
					var d := rng.randf_range(10.5, 13.0) if is_compact else rng.randf_range(11.5, 17.5)
					var yaw_choices: Array[float] = [0.0, PI * 0.5, PI, -PI * 0.5]
					var yaw: float = yaw_choices[rng.randi_range(0, 3)]
					var rot_w := d if absf(sin(yaw)) > 0.7 else w
					var rot_d := w if absf(sin(yaw)) > 0.7 else d
					var pad := 3.2 if is_compact else 4.8
					var rect := Rect2(jx - rot_w * 0.5 - pad, jz - rot_d * 0.5 - pad, rot_w + pad * 2.0, rot_d + pad * 2.0)
					if _is_rect_clear(rect):
						var style: int = styles[rng.randi_range(0, styles.size() - 1)]
						var floors := rng.randi_range(blk["min_f"], blk["max_f"])
						var mat_main := _palette_mats[rng.randi_range(0, _palette_mats.size() - 1)]
						var mat_trim := _trim_mats[rng.randi_range(0, _trim_mats.size() - 1)]
						b_idx += 1
						_spawn_varied_building(b_idx, style, mat_main, mat_trim, Vector3(jx, 0.0, jz), yaw, Vector2(w, d), floors)
						_blocked_rects.append(rect)
						_building_records.append({
							"name": "CityBld_%d" % b_idx,
							"type": "district_style_%d" % style,
							"pos": Vector3(jx, 0.0, jz),
							"size": Vector2(rot_w, rot_d),
						})
						_built_buildings_count += 1
						spawned_since_yield += 1
						if spawned_since_yield >= WEB_YIELD_BATCH:
							spawned_since_yield = 0
							await get_tree().process_frame
							if not is_inside_tree():
								return
				z += blk["step_z"]
			x += blk["step_x"]


func _build_eight_district_cities() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261118

	# Generate varied blocks across all outer East & West bank zones (every candidate checked against _blocked_rects)
	var blocks: Array[Dictionary] = [
		# Southern Al-Azhari Extension infill (fills the southern dirt expanse between z=148 connector & z=200 avenue, plus south of z=200!)
		{"district": "South Al-Azhari Extension", "x0": 16.0, "x1": 208.0, "z0": 158.0, "z1": 188.0, "step_x": 30.0, "step_z": 32.0, "styles": [0, 1, 5, 2], "min_f": 1, "max_f": 2, "compact": true},
		{"district": "South Corniche Infill", "x0": -102.0, "x1": -14.0, "z0": 158.0, "z1": 188.0, "step_x": 30.0, "step_z": 32.0, "styles": [0, 1, 5, 2], "min_f": 1, "max_f": 3, "compact": true},
		{"district": "South Al-Azhari Extension", "x0": 16.0, "x1": 208.0, "z0": 212.0, "z1": 244.0, "step_x": 32.0, "step_z": 34.0, "styles": [0, 1, 5, 2], "min_f": 1, "max_f": 2, "compact": true},
		{"district": "South Civic Infill", "x0": 236.0, "x1": 552.0, "z0": 158.0, "z1": 188.0, "step_x": 34.0, "step_z": 32.0, "styles": [0, 1, 2, 5], "min_f": 1, "max_f": 3, "compact": true},
		# Nile Corniche & Marina District (East bank north & south of core)
		{"district": "Nile Corniche & Marina District", "x0": -98.0, "x1": -20.0, "z0": -530.0, "z1": -230.0, "step_x": 36.0, "step_z": 38.0, "styles": [1, 2, 3, 4], "min_f": 2, "max_f": 4},
		{"district": "Nile Corniche & Marina District", "x0": -98.0, "x1": -20.0, "z0": 228.0, "z1": 530.0, "step_x": 36.0, "step_z": 38.0, "styles": [1, 2, 3, 5], "min_f": 2, "max_f": 4},
		# West Bank Modern Villas (West bank north & mid)
		{"district": "West Bank Modern Villas", "x0": -610.0, "x1": -288.0, "z0": -535.0, "z1": -225.0, "step_x": 40.0, "step_z": 40.0, "styles": [0, 1, 5, 4], "min_f": 1, "max_f": 3},
		{"district": "West Bank Modern Villas", "x0": -610.0, "x1": -288.0, "z0": -175.0, "z1": 170.0, "step_x": 40.0, "step_z": 40.0, "styles": [0, 1, 5, 2], "min_f": 1, "max_f": 2},
		{"district": "West Bank Modern Villas", "x0": -610.0, "x1": -288.0, "z0": 230.0, "z1": 535.0, "step_x": 40.0, "step_z": 40.0, "styles": [0, 1, 3, 5], "min_f": 1, "max_f": 3},
		# Engineering & Infrastructure Zone (NE East Bank)
		{"district": "Engineering & Infrastructure Zone", "x0": 245.0, "x1": 605.0, "z0": -535.0, "z1": -225.0, "step_x": 42.0, "step_z": 42.0, "styles": [3, 4, 1, 2], "min_f": 2, "max_f": 4},
		# Central Commercial & Market Boulevard (NE inner + SE mid)
		{"district": "Central Commercial & Market Boulevard", "x0": 24.0, "x1": 200.0, "z0": -530.0, "z1": -225.0, "step_x": 36.0, "step_z": 38.0, "styles": [2, 3, 4, 1], "min_f": 2, "max_f": 4},
		{"district": "Central Commercial & Market Boulevard", "x0": 245.0, "x1": 380.0, "z0": -175.0, "z1": -22.0, "step_x": 40.0, "step_z": 40.0, "styles": [2, 3, 4], "min_f": 2, "max_f": 4},
		# Civic & Emergency Quarter (East Bank Mid-South)
		{"district": "Civic & Emergency Quarter", "x0": 245.0, "x1": 605.0, "z0": 24.0, "z1": 175.0, "step_x": 42.0, "step_z": 42.0, "styles": [1, 3, 4, 2], "min_f": 2, "max_f": 3},
		# Sports & Youth District (South East Bank)
		{"district": "Sports & Youth District", "x0": 24.0, "x1": 605.0, "z0": 235.0, "z1": 535.0, "step_x": 38.0, "step_z": 38.0, "styles": [0, 1, 2, 3, 5], "min_f": 1, "max_f": 3},
		# Highway Gateways (Northern & Southern rims)
		{"district": "Northern & Southern Highway Gateways", "x0": -540.0, "x1": 540.0, "z0": -635.0, "z1": -582.0, "step_x": 48.0, "step_z": 44.0, "styles": [2, 4, 5], "min_f": 1, "max_f": 3},
		{"district": "Northern & Southern Highway Gateways", "x0": -540.0, "x1": 540.0, "z0": 582.0, "z1": 635.0, "step_x": 48.0, "step_z": 44.0, "styles": [0, 2, 5], "min_f": 1, "max_f": 3},
	]

	var b_idx := 0
	var shop_counter := 0
	for blk in blocks:
		var styles: Array = blk["styles"]
		var is_compact: bool = bool(blk.get("compact", false))
		var x: float = blk["x0"] + (12.0 if is_compact else 14.0)
		while x <= blk["x1"] - (10.0 if is_compact else 12.0):
			var z: float = blk["z0"] + (14.0 if is_compact else 14.0)
			while z <= blk["z1"] - (10.0 if is_compact else 12.0):
				var jx := x + rng.randf_range(-1.4, 1.4) if is_compact else x + rng.randf_range(-2.8, 2.8)
				var jz := z + rng.randf_range(-1.2, 1.2) if is_compact else z + rng.randf_range(-2.8, 2.8)
				var w := rng.randf_range(11.0, 14.5) if is_compact else rng.randf_range(12.5, 19.5)
				var d := rng.randf_range(10.5, 13.0) if is_compact else rng.randf_range(11.5, 17.5)
				var yaw_choices: Array[float] = [0.0, PI * 0.5, PI, -PI * 0.5]
				var yaw: float = yaw_choices[rng.randi_range(0, 3)]
				var rot_w := d if absf(sin(yaw)) > 0.7 else w
				var rot_d := w if absf(sin(yaw)) > 0.7 else d
				var pad := 3.2 if is_compact else 4.8
				var rect := Rect2(jx - rot_w * 0.5 - pad, jz - rot_d * 0.5 - pad, rot_w + pad * 2.0, rot_d + pad * 2.0)
				if _is_rect_clear(rect):
					var style: int = styles[rng.randi_range(0, styles.size() - 1)]
					var floors := rng.randi_range(blk["min_f"], blk["max_f"])
					var mat_main := _palette_mats[rng.randi_range(0, _palette_mats.size() - 1)]
					var mat_trim := _trim_mats[rng.randi_range(0, _trim_mats.size() - 1)]
					b_idx += 1
					_spawn_varied_building(b_idx, style, mat_main, mat_trim, Vector3(jx, 0.0, jz), yaw, Vector2(w, d), floors)
					_blocked_rects.append(rect)
					_building_records.append({
						"name": "CityBld_%d" % b_idx,
						"type": "district_style_%d" % style,
						"pos": Vector3(jx, 0.0, jz),
						"size": Vector2(rot_w, rot_d),
					})
					_built_buildings_count += 1

					# Add Shopkeeper NPCs outside selected ground-floor colonnade shops (style == 2)
					if style == 2 and shop_counter < 10 and (b_idx % 4 == 0):
						shop_counter += 1
						var front_world := Vector3(jx, 0.0, jz) + Vector3(0.0, 0.0, d * 0.5 + 1.8).rotated(Vector3.UP, yaw)
						_role_stations.append({
							"role": "vendor",
							"district": blk["district"],
							"label": "بائع السوق",
							"position": front_world,
							"yaw": yaw,
							"lines": [
								"تفضل يا زول، البضاعة طازجة والأسعار ممتازة!",
								"عندنا كل المستلزمات اليومية لأهل %s." % blk["district"]
							],
						})
				z += blk["step_z"]
			x += blk["step_x"]


func _is_rect_clear(rect: Rect2) -> bool:
	if rect.position.x < -675.0 or rect.end.x > 675.0 or rect.position.y < -675.0 or rect.end.y > 675.0:
		return false
	for br in _blocked_rects:
		if rect.intersects(br):
			return false
	return true


func _spawn_varied_building(idx: int, style: int, mat_main: Material, mat_trim: Material, pos: Vector3, yaw: float, fp: Vector2, floors: int) -> void:
	var root := Node3D.new()
	root.name = "CityBld_%d_S%d" % [idx, style]
	root.position = pos
	root.rotation.y = yaw
	_city_buildings_root.add_child(root)

	var h: float = float(floors) * 3.3
	var w: float = fp.x
	var d: float = fp.y

	match style:
		0:
			# Courtyard House (حوش سوداني تقليدي)
			var wall_h := 2.4
			_add_static_box(root, "MainWing", Vector3(0, h * 0.5, -d * 0.22), Vector3(w * 0.88, h, d * 0.48), mat_main, VIS_BUILDING)
			_add_static_box(root, "YardLeft", Vector3(-w * 0.45, wall_h * 0.5, d * 0.14), Vector3(0.45, wall_h, d * 0.65), mat_main, VIS_BUILDING)
			_add_static_box(root, "YardRight", Vector3(w * 0.45, wall_h * 0.5, d * 0.14), Vector3(0.45, wall_h, d * 0.65), mat_main, VIS_BUILDING)
			_add_static_box(root, "YardFrontL", Vector3(-w * 0.28, wall_h * 0.5, d * 0.46), Vector3(w * 0.34, wall_h, 0.45), mat_main, VIS_BUILDING)
			_add_static_box(root, "YardFrontR", Vector3(w * 0.28, wall_h * 0.5, d * 0.46), Vector3(w * 0.34, wall_h, 0.45), mat_main, VIS_BUILDING)
			# Authentic side-hinged Sudanese steel double courtyard gate (`بوابة حوش سودانية`)
			var gate_door := InteractiveDoor.new()
			gate_door.name = "CourtyardGate"
			gate_door.door_label = "بوابة الحوش"
			gate_door.door_style = InteractiveDoor.DoorStyle.COURTYARD_DOUBLE_GATE
			gate_door.opening_width = clampf(w * 0.24, 2.55, 3.10)
			gate_door.opening_height = 2.35
			gate_door.wall_thickness = 0.45
			gate_door.has_pillars = true
			gate_door.has_lintel_beam = true
			gate_door.is_open = false
			gate_door.open_angle_deg = 86.0
			gate_door.vis_range_end = 95.0
			gate_door.position = Vector3(0.0, 0.0, d * 0.46)
			root.add_child(gate_door)
		1:
			# Flat-Roof Modern Villa with upper terrace & overhanging slab (supported by columns in OuterCityDetailBuilder)
			_add_static_box(root, "LowerBox", Vector3(0, h * 0.35, 0), Vector3(w, h * 0.7, d), mat_main, VIS_BUILDING)
			_add_static_box(root, "UpperBox", Vector3(-w * 0.12, h * 0.85, -d * 0.1), Vector3(w * 0.68, h * 0.42, d * 0.72), mat_trim, VIS_BUILDING)
			_add_box_mesh(root, "RoofSlab", Vector3(0, h * 1.07, 0), Vector3(w * 0.78, 0.32, d * 0.82), _mat_white, VIS_BUILDING)
		2:
			# Arched Colonnade Shopfront
			_add_static_box(root, "ShopCore", Vector3(0, h * 0.5, -d * 0.12), Vector3(w, h, d * 0.76), mat_main, VIS_BUILDING)
			_add_box_mesh(root, "ArcadeRoof", Vector3(0, 3.2, d * 0.34), Vector3(w, 0.45, d * 0.28), mat_trim, VIS_BUILDING)
			for cx in [-w * 0.38, 0.0, w * 0.38]:
				_add_static_box(root, "Col_%d" % int(cx * 10), Vector3(cx, 1.6, d * 0.44), Vector3(0.55, 3.2, 0.55), mat_trim, VIS_DETAIL)
			_add_box_mesh(root, "SignBand", Vector3(0, 3.7, d * 0.49), Vector3(w * 0.88, 0.65, 0.16), _mat_blue, VIS_DETAIL)
		3:
			# Stepped Apartment Block with enclosed 3-sided safety balcony railings (1.05m)
			_add_static_box(root, "BaseBlock", Vector3(0, h * 0.42, 0), Vector3(w, h * 0.84, d), mat_main, VIS_BUILDING)
			_add_static_box(root, "Penthouse", Vector3(0, h * 0.96, 0), Vector3(w * 0.65, h * 0.28, d * 0.68), mat_trim, VIS_BUILDING)
			for fy in range(1, floors):
				var wy := float(fy) * 3.1 - 1.3
				_add_city_balcony_enclosure(root, fy, w * 0.72, 1.15, wy, d * 0.50)
				_add_box_mesh(root, "Win_%d" % fy, Vector3(0, wy + 0.8, d * 0.505), Vector3(w * 0.64, 1.1, 0.1), _mat_glass, VIS_DETAIL)
		4:
			# Corner Tower Building
			_add_static_box(root, "Wing", Vector3(w * 0.12, h * 0.38, 0), Vector3(w * 0.76, h * 0.76, d * 0.88), mat_main, VIS_BUILDING)
			_add_static_box(root, "CornerTower", Vector3(-w * 0.32, h * 0.62, d * 0.16), Vector3(w * 0.36, h * 1.24, d * 0.56), mat_trim, VIS_BUILDING)
			_add_box_mesh(root, "TowerCrown", Vector3(-w * 0.32, h * 1.26, d * 0.16), Vector3(w * 0.40, 0.38, d * 0.60), _mat_white, VIS_BUILDING)
		_:
			# Shaded Veranda House (فرندة مظللة)
			_add_static_box(root, "HouseCore", Vector3(0, h * 0.5, -d * 0.12), Vector3(w * 0.94, h, d * 0.74), mat_main, VIS_BUILDING)
			_add_box_mesh(root, "VerandaDeck", Vector3(0, 0.18, d * 0.34), Vector3(w * 0.94, 0.36, d * 0.26), _mat_curb, VIS_DETAIL)
			_add_box_mesh(root, "VerandaAwning", Vector3(0, 3.05, d * 0.36), Vector3(w * 0.96, 0.22, d * 0.30), _mat_wood, VIS_DETAIL)
			for vx in [-w * 0.38, -w * 0.12, w * 0.12, w * 0.38]:
				_add_cylinder_mesh(root, "VerandaPost_%d" % int(vx * 10), Vector3(vx, 1.6, d * 0.45), 0.14, 2.8, mat_trim, VIS_DETAIL)

	# Upgrade EVERY outer/southern building with framed Sudanese doors, barred windows on all 4 sides,
	# 1.05m rooftop parapets + spouts + water tanks, slab columns, and Sudanese courtyard walls/Rakouba/Zeer
	# merged into 1 single multi-surface ArrayMesh (`MergedBuildingDetails`, vis = 130.0m)!
	OuterCityDetailBuilder.enhance_city_building(root, idx, style, w, d, h, floors, mat_main, mat_trim)


func _register_core_work_stations() -> void:
	# Existing core shops & stations in scenes/main.tscn so core neighborhood stays lively with role NPCs
	_role_stations.append({
		"role": "vendor",
		"district": "Al-Azhari Historic Core",
		"label": "بائع دكان عماري سعود",
		"position": Vector3(17.5, 0.0, 12.2),
		"yaw": 0.0,
		"lines": [
			"مرحباً في بقالة عماري سعود! كل حاجة متوفرة وطازجة.",
			"عصائر باردة، سناكس، ومستلزمات البيت في خدمتك."
		],
	})
	_role_stations.append({
		"role": "vendor",
		"district": "Al-Azhari Historic Core",
		"label": "بائع الدكان المركزي",
		"position": Vector3(-22.0, 0.0, -34.0),
		"yaw": 0.0,
		"lines": [
			"أهلاً يا زول في دكان الحلة!",
			"تفضل شاي أو قهوة سودانية أصيلة."
		],
	})
	_role_stations.append({
		"role": "vendor",
		"district": "Al-Azhari Historic Core",
		"label": "عامل محطة الوقود",
		"position": Vector3(68.0, 0.0, -40.0),
		"yaw": -PI * 0.5,
		"lines": [
			"أهلاً في طرمبة الأزهري! اضغط [E] لتعبئة الوقود أو إصلاح المركبة.",
			"نخدم جميع المركبات والحافلات على مدار اليوم."
		],
	})
	_role_stations.append({
		"role": "police",
		"district": "Al-Azhari Historic Core",
		"label": "شرطي الصينية المركزية",
		"position": Vector3(14.5, 0.0, -14.5),
		"yaw": -PI * 0.25,
		"lines": [
			"شرطة المرور في خدمتكم. الصينية سالكة في كل الاتجاهات.",
			"القيادة الآمنة تحمي الجميع في شوارع الخرطوم."
		],
	})


func _palette_safe(i: int) -> StandardMaterial3D:
	return _palette_mats[i % _palette_mats.size()]


func _add_static_box(parent: Node3D, n_name: String, pos: Vector3, size_v: Vector3, mat: Material, vis_end: float) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = n_name
	sb.position = pos
	parent.add_child(sb)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size_v
	bm.material = mat
	mi.mesh = bm
	mi.visibility_range_end = vis_end
	sb.add_child(mi)

	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size_v
	col.shape = bs
	sb.add_child(col)
	return sb


func _add_box_mesh(parent: Node3D, n_name: String, pos: Vector3, size_v: Vector3, mat: Material, vis_end: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n_name
	mi.position = pos
	var bm := BoxMesh.new()
	bm.size = size_v
	bm.material = mat
	mi.mesh = bm
	mi.visibility_range_end = vis_end
	# Decorative details, trim, windows, and road stripes skip directional shadow pass
	if vis_end <= VIS_DETAIL + 5.0 or size_v.y <= 0.45 or size_v.z <= 0.25 or size_v.x <= 0.25:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_cylinder_mesh(parent: Node3D, n_name: String, pos: Vector3, radius: float, height: float, mat: Material, vis_end: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n_name
	mi.position = pos
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	cm.material = mat
	mi.mesh = cm
	mi.visibility_range_end = vis_end
	if vis_end <= VIS_DETAIL + 5.0 or height <= 0.5:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_static_cylinder(parent: Node3D, n_name: String, pos: Vector3, radius: float, height: float, mat: Material, vis_end: float) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = n_name
	sb.position = pos
	parent.add_child(sb)

	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 20
	cm.material = mat
	mi.mesh = cm
	mi.visibility_range_end = vis_end
	sb.add_child(mi)

	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = radius
	cs.height = height
	col.shape = cs
	sb.add_child(col)
	return sb


func _add_label3d(parent: Node3D, n_name: String, pos: Vector3, text_str: String, color: Color, font_sz: int, vis_end: float, rot_y: float = 0.0) -> void:
	var lbl := Label3D.new()
	lbl.name = n_name
	lbl.position = pos
	lbl.rotation.y = rot_y
	lbl.text = text_str
	lbl.font_size = font_sz
	lbl.modulate = color
	lbl.outline_size = 6
	lbl.visibility_range_end = vis_end
	parent.add_child(lbl)


static var _city_balcony_cache: Dictionary = {}

func _add_city_balcony_enclosure(parent: Node3D, fy: int, bw: float, bd: float, wy: float, wall_z: float) -> void:
	# Quantize width to 0.5m buckets so procedural apartments share cached ArrayMeshes cleanly
	var qw := roundf(bw * 2.0) * 0.5
	var qd := roundf(bd * 2.0) * 0.5
	var key := "cb_%.1f_%.1f" % [qw, qd]
	var mesh: ArrayMesh = _city_balcony_cache.get(key) as ArrayMesh
	if mesh == null:
		var b := InteriorMeshBatcher.new()
		var mat_conc := _mat_white
		var mat_iron := InteriorMeshBatcher.get_color_mat("city_balc_iron", Color(0.15, 0.19, 0.23), 0.42, 0.65)
		var total_h := 1.05
		var parapet_h := 0.42
		# Floor slab (z in [0, qd])
		b.add_box(Vector3(0.0, 0.0, qd * 0.5), Vector3(qw, 0.22, qd), mat_conc)
		# Front parapet (+Z edge) + Left (-X) + Right (+X) parapets
		b.add_box(Vector3(0.0, 0.11 + parapet_h * 0.5, qd - 0.06), Vector3(qw, parapet_h, 0.12), mat_conc)
		b.add_box(Vector3(-qw * 0.5 + 0.06, 0.11 + parapet_h * 0.5, qd * 0.5), Vector3(0.12, parapet_h, qd), mat_conc)
		b.add_box(Vector3(qw * 0.5 - 0.06, 0.11 + parapet_h * 0.5, qd * 0.5), Vector3(0.12, parapet_h, qd), mat_conc)
		# Top & mid wrought-iron handrails (1.05m & 0.72m above floor top y=0.11)
		var y_top := 0.11 + total_h
		var y_mid := 0.11 + 0.72
		var x0 := -qw * 0.5 + 0.05
		var x1 := qw * 0.5 - 0.05
		var zf := qd - 0.05
		b.add_bar(Vector3(x0, y_top, zf), Vector3(x1, y_top, zf), 0.048, 0.042, mat_iron)
		b.add_bar(Vector3(x0, y_mid, zf), Vector3(x1, y_mid, zf), 0.030, 0.026, mat_iron)
		b.add_bar(Vector3(x0, y_top, 0.04), Vector3(x0, y_top, zf), 0.048, 0.042, mat_iron)
		b.add_bar(Vector3(x1, y_top, 0.04), Vector3(x1, y_top, zf), 0.048, 0.042, mat_iron)
		# Vertical balusters along front & sides
		var n_front := maxi(3, int(round(qw / 0.48)))
		for i in range(n_front + 1):
			var bx := lerpf(x0, x1, float(i) / float(n_front))
			b.add_box(Vector3(bx, 0.11 + parapet_h + (total_h - parapet_h) * 0.5, zf), Vector3(0.026, total_h - parapet_h, 0.026), mat_iron)
		for sx: float in [x0, x1]:
			for sz_t: float in [0.35, 0.70]:
				b.add_box(Vector3(sx, 0.11 + parapet_h + (total_h - parapet_h) * 0.5, qd * sz_t), Vector3(0.026, total_h - parapet_h, 0.026), mat_iron)
		mesh = b.commit()
		_city_balcony_cache[key] = mesh

	var sb := StaticBody3D.new()
	sb.name = "Balcony_%d" % fy
	sb.add_to_group("balcony_railings")
	sb.position = Vector3(0.0, wy, wall_z)
	parent.add_child(sb)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visibility_range_end = VIS_DETAIL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sb.add_child(mi)

	# Deck + 3-sided 1.05m fall-protection BoxShape3D colliders
	InteriorMeshBatcher.add_box_collider(sb, "DeckCol", Vector3(0.0, 0.0, qd * 0.5), Vector3(qw, 0.22, qd))
	InteriorMeshBatcher.add_box_collider(sb, "FrontRailCol", Vector3(0.0, 0.11 + 0.525, qd - 0.06), Vector3(qw, 1.05, 0.14))
	InteriorMeshBatcher.add_box_collider(sb, "LeftRailCol", Vector3(-qw * 0.5 + 0.06, 0.11 + 0.525, qd * 0.5), Vector3(0.14, 1.05, qd))
	InteriorMeshBatcher.add_box_collider(sb, "RightRailCol", Vector3(qw * 0.5 - 0.06, 0.11 + 0.525, qd * 0.5), Vector3(0.14, 1.05, qd))


static var _city_roofkit_cache: Dictionary = {}

func _add_city_rooftop_kit(parent: Node3D, roof_ctr: Vector3, rw: float, rd: float, seed_idx: int) -> void:
	var c_idx := posmod(seed_idx, 3)
	var key := "rk_%d" % c_idx
	var mesh: ArrayMesh = _city_roofkit_cache.get(key) as ArrayMesh
	if mesh == null:
		var b := InteriorMeshBatcher.new()
		SudaneseRooftopBuilder.add_water_tank_to_batcher(b, Vector3(-1.35, 0.0, -0.55), 0.62, 1.24, c_idx)
		var mat_pole := InteriorMeshBatcher.get_color_mat("rf_dish_pole", Color(0.28, 0.30, 0.34), 0.45, 0.65)
		var mat_dish := InteriorMeshBatcher.get_color_mat("rf_dish_white", Color(0.92, 0.93, 0.94), 0.36, 0.12)
		var mat_pvc := InteriorMeshBatcher.get_color_mat("rf_pvc", Color(0.76, 0.78, 0.80), 0.42, 0.10)
		# Compact satellite dish on mast pole
		var dp := Vector3(1.45, 0.0, 0.45)
		b.add_cylinder(dp + Vector3(0.0, 0.48, 0.0), 0.03, 0.035, 0.96, mat_pole, 6)
		b.add_sphere(dp + Vector3(0.0, 0.98, 0.0), 0.44, mat_dish, Vector3(1.0, 0.28, 1.0), 8, 4)
		# Pair of protruding rainwater spouts (مزاريب)
		b.add_bar(Vector3(-2.6, 0.14, 0.0), Vector3(-3.05, 0.04, 0.0), 0.07, 0.07, mat_pvc)
		b.add_bar(Vector3(2.6, 0.14, 0.0), Vector3(3.05, 0.04, 0.0), 0.07, 0.07, mat_pvc)
		mesh = b.commit()
		_city_roofkit_cache[key] = mesh

	var mi := MeshInstance3D.new()
	mi.name = "RooftopWaterTankKit"
	mi.position = roof_ctr
	mi.mesh = mesh
	mi.visibility_range_end = 110.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
