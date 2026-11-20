extends Node3D
class_name NileRiverEnvironment

## Nile River Visual & Terrain Environment Manager (`scripts/nile_river_environment.gd`).
## Manages:
## - Shared realistic `nile_water.gdshader` `ShaderMaterial` with dual-scrolling `NoiseTexture2D`
##   normal maps applied seamlessly across the entire 1,400m Nile River
## - Deep riverbed (`y = -4.2m`) and gently sloped underwater sandy shore banks
## - `NileWaterZone` (`Area3D`, group `"nile_water_zones"`) covering the river volume up to `WATER_SURFACE_Y`
## - Natural sloped Nile islands & sandbars (`Node3D` group `"NileIslands"`) with grass, reeds,
##   and palm/acacia trees from existing project `.gltf` assets
## - Varied 3D shoreline & island rocks/boulders with `StaticBody3D` collisions.

const WATER_SURFACE_Y: float = 0.20
const RIVERBED_Y: float = -4.20
const RIVER_CENTER_X: float = -190.0
const RIVER_WIDTH: float = 90.0
const RIVER_HALF_LEN: float = 700.0

const SHADER_WATER: Shader = preload("res://shaders/nile_water.gdshader")
const TEX_SAND_ALB: Texture2D = preload("res://assets/textures/sand_dirt/albedo.jpg")
const TEX_SAND_NOR: Texture2D = preload("res://assets/textures/sand_dirt/normal.jpg")
const TEX_SAND_RGH: Texture2D = preload("res://assets/textures/sand_dirt/roughness.jpg")

const PATH_ISLAND_TREE: String = "res://assets/models/foliage/island_tree_02/island_tree_02.gltf"
const PATH_QUIVER_TREE: String = "res://assets/models/foliage/quiver_tree_01/quiver_tree_01.gltf"
const PATH_SHRUB: String = "res://assets/models/foliage/shrub_01/shrub_01.gltf"
const PATH_REED_BUSH: String = "res://assets/models/foliage/wild_rooibos_bush/wild_rooibos_bush.gltf"
const PATH_ROCKS: Array[String] = [
	"res://assets/models/rocks/boulder_01/boulder_01.gltf",
	"res://assets/models/rocks/namaqualand_rocks_01/namaqualand_rocks_01.gltf",
	"res://assets/models/rocks/namaqualand_stones_01/namaqualand_stones_01.gltf",
]

var water_material: ShaderMaterial = null
var water_zone: Area3D = null
var islands_root: Node3D = null
var rocks_root: Node3D = null
var _island_count: int = 0
var _rock_count: int = 0

var _mat_sand: StandardMaterial3D
var _mat_grass: StandardMaterial3D
var _mat_reed: StandardMaterial3D
var _mat_rock_fallback: StandardMaterial3D


func _ready() -> void:
	add_to_group("nile_river_environment")
	_init_materials()
	water_material = create_nile_water_material()
	_upgrade_existing_nile_river_scene()
	_build_deep_riverbed_and_sloped_banks()
	_build_water_surface_extensions()
	_build_water_zone_area()
	_build_nile_islands()
	_scatter_river_rocks()
	print("[NileRiverEnvironment] Upgraded 1400m Nile: shader active, riverbed=%.1fm, %d islands, %d rocks, NileWaterZone active." % [
		RIVERBED_Y, _island_count, _rock_count
	])


func get_water_surface_y() -> float:
	return WATER_SURFACE_Y


static func create_nile_water_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = SHADER_WATER

	var noise_a := FastNoiseLite.new()
	noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_a.seed = 104729
	noise_a.frequency = 0.032
	noise_a.fractal_octaves = 4
	var tex_a := NoiseTexture2D.new()
	tex_a.width = 256
	tex_a.height = 256
	tex_a.seamless = true
	tex_a.as_normal_map = true
	tex_a.bump_strength = 6.8
	tex_a.noise = noise_a

	var noise_b := FastNoiseLite.new()
	noise_b.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_b.seed = 209317
	noise_b.frequency = 0.048
	noise_b.fractal_octaves = 3
	var tex_b := NoiseTexture2D.new()
	tex_b.width = 256
	tex_b.height = 256
	tex_b.seamless = true
	tex_b.as_normal_map = true
	tex_b.bump_strength = 5.4
	tex_b.noise = noise_b

	sm.set_shader_parameter("normal_map_a", tex_a)
	sm.set_shader_parameter("normal_map_b", tex_b)
	sm.set_shader_parameter("shallow_water_color", Color(0.56, 0.52, 0.36, 0.80))
	sm.set_shader_parameter("mid_water_color", Color(0.10, 0.44, 0.50, 0.90))
	sm.set_shader_parameter("deep_water_color", Color(0.03, 0.19, 0.30, 0.96))
	sm.set_shader_parameter("sky_reflect_color", Color(0.88, 0.80, 0.70, 1.0))
	sm.set_shader_parameter("foam_color", Color(0.95, 0.97, 0.99, 1.0))
	sm.set_shader_parameter("flow_speed", 0.28)
	sm.set_shader_parameter("normal_strength", 0.74)
	sm.set_shader_parameter("wave_height", 0.048)
	sm.set_shader_parameter("depth_fade_distance", 3.6)
	sm.set_shader_parameter("foam_depth", 0.72)
	return sm


func _init_materials() -> void:
	_mat_sand = StandardMaterial3D.new()
	_mat_sand.albedo_color = Color(0.90, 0.76, 0.54, 1.0)
	_mat_sand.albedo_texture = TEX_SAND_ALB
	_mat_sand.normal_enabled = true
	_mat_sand.normal_texture = TEX_SAND_NOR
	_mat_sand.roughness = 0.94
	_mat_sand.roughness_texture = TEX_SAND_RGH
	_mat_sand.uv1_scale = Vector3(8.0, 8.0, 1.0)

	_mat_grass = StandardMaterial3D.new()
	_mat_grass.albedo_color = Color(0.28, 0.50, 0.22, 1.0)
	_mat_grass.albedo_texture = TEX_SAND_ALB
	_mat_grass.roughness = 0.90
	_mat_grass.uv1_scale = Vector3(6.0, 6.0, 1.0)

	_mat_reed = StandardMaterial3D.new()
	_mat_reed.albedo_color = Color(0.24, 0.48, 0.20, 1.0)
	_mat_reed.roughness = 0.85

	_mat_rock_fallback = StandardMaterial3D.new()
	_mat_rock_fallback.albedo_color = Color(0.46, 0.43, 0.39, 1.0)
	_mat_rock_fallback.roughness = 0.92


func _upgrade_existing_nile_river_scene() -> void:
	var main_root := _find_main_root()
	if main_root == null:
		return
	var nile := main_root.get_node_or_null("Neighborhood/NileRiver") as Node3D
	if nile == null:
		return

	# Replace central WaterSurface with a clean subdivided PlaneMesh at WATER_SURFACE_Y using shared ShaderMaterial
	var ws := nile.get_node_or_null("WaterSurface") as MeshInstance3D
	if ws != null:
		var pm := PlaneMesh.new()
		pm.size = Vector2(RIVER_WIDTH, 500.0)
		pm.subdivide_width = 16
		pm.subdivide_depth = 48
		pm.material = water_material
		ws.mesh = pm
		ws.material_override = water_material
		ws.position = Vector3(-52.0, WATER_SURFACE_Y, 0.0)
		ws.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ws.visibility_range_end = 750.0

	# Move existing central RiverBedCollider down to RIVERBED_Y (-4.2m) so characters enter deep water
	var rbc := nile.get_node_or_null("RiverBedCollider") as StaticBody3D
	if rbc != null:
		rbc.position = Vector3(-52.0, RIVERBED_Y - 0.10, 0.0)


func _build_deep_riverbed_and_sloped_banks() -> void:
	var bed_root := Node3D.new()
	bed_root.name = "NileRiverbedAndBanks"
	add_child(bed_root)

	# North [-700..-250] and South [+250..+700] deep riverbed slabs (top face = RIVERBED_Y = -4.2m)
	for seg in [Vector2(-475.0, 450.0), Vector2(475.0, 450.0)]:
		_add_static_box(bed_root, "RiverBed_%d" % int(seg.x), Vector3(RIVER_CENTER_X, RIVERBED_Y - 0.25, seg.x), Vector3(RIVER_WIDTH + 6.0, 0.5, seg.y), _mat_sand, 650.0)

	# Gently sloped underwater sandy banks along BOTH East (x=-145..-159) and West (x=-235..-221) shores
	# Rise = 4.2m over Run = 14.0m (~16.7 deg) so swimmers can easily walk out onto sandy shores & depth shader blends cleanly
	var rise := absf(RIVERBED_Y)
	var run := 14.0
	var hyp := sqrt(rise * rise + run * run)
	var angle := atan2(rise, run)
	var thickness := 0.45

	# East underwater sloped shore bank (slopes down from x=-145, y=0.0 to x=-159, y=-4.2)
	var east_bank := StaticBody3D.new()
	east_bank.name = "EastUnderwaterSlope"
	east_bank.position = Vector3(-145.0 - run * 0.5, -rise * 0.5 - thickness * 0.5 * cos(angle), 0.0)
	east_bank.rotation.z = angle
	bed_root.add_child(east_bank)
	_fill_box_body(east_bank, Vector3(hyp, thickness, RIVER_HALF_LEN * 2.0), _mat_sand, 650.0)

	# West underwater sloped shore bank (slopes down from x=-235, y=0.0 to x=-221, y=-4.2)
	var west_bank := StaticBody3D.new()
	west_bank.name = "WestUnderwaterSlope"
	west_bank.position = Vector3(-235.0 + run * 0.5, -rise * 0.5 - thickness * 0.5 * cos(angle), 0.0)
	west_bank.rotation.z = -angle
	bed_root.add_child(west_bank)
	_fill_box_body(west_bank, Vector3(hyp, thickness, RIVER_HALF_LEN * 2.0), _mat_sand, 650.0)


func _build_water_surface_extensions() -> void:
	# Seamless North [-700..-250] and South [+250..+700] subdivided water planes sharing water_material
	for seg in [Vector2(-475.0, 450.0), Vector2(475.0, 450.0)]:
		var mi := MeshInstance3D.new()
		mi.name = "NileWaterSurface_%d" % int(seg.x)
		var pm := PlaneMesh.new()
		pm.size = Vector2(RIVER_WIDTH, seg.y)
		pm.subdivide_width = 16
		pm.subdivide_depth = 44
		pm.material = water_material
		mi.mesh = pm
		mi.material_override = water_material
		mi.position = Vector3(RIVER_CENTER_X, WATER_SURFACE_Y, seg.x)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 750.0
		add_child(mi)


func _build_water_zone_area() -> void:
	water_zone = Area3D.new()
	water_zone.name = "NileWaterZone"
	water_zone.add_to_group("nile_water_zones")
	water_zone.collision_layer = 0
	water_zone.collision_mask = 15
	water_zone.monitoring = true
	water_zone.monitorable = true
	water_zone.set_meta("water_surface_y", WATER_SURFACE_Y)

	var zone_h := WATER_SURFACE_Y - (RIVERBED_Y - 1.0)
	water_zone.position = Vector3(RIVER_CENTER_X, WATER_SURFACE_Y - zone_h * 0.5, 0.0)
	add_child(water_zone)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(RIVER_WIDTH + 2.0, zone_h, RIVER_HALF_LEN * 2.0)
	cs.shape = bs
	water_zone.add_child(cs)

	water_zone.body_entered.connect(_on_water_body_entered)
	water_zone.body_exited.connect(_on_water_body_exited)


func _on_water_body_entered(body: Node3D) -> void:
	if body != null and body.has_method("enter_water"):
		body.enter_water(WATER_SURFACE_Y, water_zone)


func _on_water_body_exited(body: Node3D) -> void:
	if body != null and body.has_method("exit_water"):
		body.exit_water(water_zone)


func _build_nile_islands() -> void:
	islands_root = Node3D.new()
	islands_root.name = "NileIslands"
	islands_root.add_to_group("NileIslands")
	add_child(islands_root)

	var shrub_scene: PackedScene = load(PATH_SHRUB) if ResourceLoader.exists(PATH_SHRUB) else null
	var reed_scene: PackedScene = load(PATH_REED_BUSH) if ResourceLoader.exists(PATH_REED_BUSH) else null

	# 6 scenic natural Nile islands & sandbars strictly clear of all 3 bridges (z=-360, 0, +360) and docks (z=-90, -110, +240)
	var specs: Array[Dictionary] = [
		{"name": "Island_AzhariSandbar", "pos": Vector3(-191.0, 0.0, 105.0),  "rx": 14.5, "rz": 26.0, "top_y": 1.25, "trees": 3, "reeds": 7},
		{"name": "Island_TutiSouth",     "pos": Vector3(-190.0, 0.0, -185.0), "rx": 16.5, "rz": 31.0, "top_y": 1.45, "trees": 4, "reeds": 8},
		{"name": "Island_MidSandbar",    "pos": Vector3(-184.0, 0.0, -280.0), "rx": 11.5, "rz": 19.0, "top_y": 0.95, "trees": 2, "reeds": 5},
		{"name": "Island_NorthOasis",    "pos": Vector3(-189.0, 0.0, -490.0), "rx": 17.5, "rz": 33.0, "top_y": 1.55, "trees": 4, "reeds": 7},
		{"name": "Island_SouthPalm",     "pos": Vector3(-193.0, 0.0, 295.0),  "rx": 15.0, "rz": 26.0, "top_y": 1.35, "trees": 3, "reeds": 6},
		{"name": "Island_FarSouthBar",   "pos": Vector3(-187.0, 0.0, 485.0),  "rx": 16.5, "rz": 32.0, "top_y": 1.40, "trees": 4, "reeds": 7},
	]

	var rng := RandomNumberGenerator.new()
	rng.seed = 905121

	for sp in specs:
		var isl := Node3D.new()
		isl.name = str(sp["name"])
		isl.position = sp["pos"]
		isl.add_to_group("NileIslands")
		islands_root.add_child(isl)
		_island_count += 1

		var rx: float = float(sp["rx"])
		var rz: float = float(sp["rz"])
		var top_y: float = float(sp["top_y"])

		# Build walkable sloped elliptical sandy mound rising smoothly from riverbed (-4.2m) up to +top_y
		var beach_body := StaticBody3D.new()
		beach_body.name = "SandyIslandBody"
		isl.add_child(beach_body)

		var beach_mesh := _build_sloped_island_mesh(rx, rz, RIVERBED_Y, top_y, 24)
		beach_mesh.surface_set_material(0, _mat_sand)
		var bmi := MeshInstance3D.new()
		bmi.name = "SandyBeachMesh"
		bmi.mesh = beach_mesh
		bmi.visibility_range_end = 650.0
		beach_body.add_child(bmi)

		var bcol := CollisionShape3D.new()
		var trimesh := beach_mesh.create_trimesh_shape()
		trimesh.backface_collision = true
		bcol.shape = trimesh
		beach_body.add_child(bcol)

		# Inner grassy crown slightly above the sandy beach
		var grass_mi := MeshInstance3D.new()
		grass_mi.name = "GrassCrown"
		var gm := CylinderMesh.new()
		gm.top_radius = 1.0
		gm.bottom_radius = 1.18
		gm.height = 0.24
		gm.radial_segments = 20
		gm.material = _mat_grass
		grass_mi.mesh = gm
		grass_mi.scale = Vector3(rx * 0.42, 1.0, rz * 0.42)
		grass_mi.position = Vector3(0.0, top_y - 0.02, 0.0)
		grass_mi.visibility_range_end = 520.0
		isl.add_child(grass_mi)

		# Place organic Date Palms, Nile Acacia/Sunut, and repaired 4K Realistic Trees on the island crown
		var t_count: int = int(sp["trees"])
		for ti in range(t_count):
			var ang := (TAU * float(ti) / float(max(t_count, 1))) + rng.randf_range(-0.35, 0.35)
			var dist_f := rng.randf_range(0.10, 0.36)
			var tx := cos(ang) * rx * dist_f
			var tz := sin(ang) * rz * dist_f
			var world_tpos := isl.position + Vector3(tx, top_y - 0.05, tz)
			if SmartWorldOrganizer.is_in_bridge_exclusion(world_tpos, 5.0):
				continue
			var tree := SudaneseTreeBuilder.new()
			tree.name = "IslandTree_%d" % ti
			var kind_mod := ti % 3
			if kind_mod == 0:
				tree.species = SudaneseTreeBuilder.TreeSpecies.DATE_PALM
			elif kind_mod == 1:
				tree.species = SudaneseTreeBuilder.TreeSpecies.ACACIA
			else:
				tree.species = SudaneseTreeBuilder.TreeSpecies.REALISTIC_4K
			tree.variant_seed = _island_count * 17 + ti
			tree.height_scale = rng.randf_range(0.92, 1.25)
			tree.vis_range_end = 150.0
			tree.position = Vector3(tx, top_y - 0.05, tz)
			tree.rotation.y = rng.randf_range(0.0, TAU)
			isl.add_child(tree)

		# Place shoreline reeds & bushes around the sandy perimeter
		var r_count: int = int(sp["reeds"])
		for ri in range(r_count):
			var rang := (TAU * float(ri) / float(max(r_count, 1))) + rng.randf_range(-0.25, 0.25)
			var rdist := rng.randf_range(0.40, 0.62)
			var bx := cos(rang) * rx * rdist
			var bz := sin(rang) * rz * rdist
			var by := _sample_island_height(rdist, RIVERBED_Y, top_y)
			var bscene := reed_scene if (ri % 2 == 0 and reed_scene != null) else shrub_scene
			if bscene != null:
				var bush := bscene.instantiate() as Node3D
				if bush != null:
					bush.name = "ShoreReed_%d" % ri
					bush.position = Vector3(bx, maxf(WATER_SURFACE_Y - 0.12, by - 0.08), bz)
					bush.rotation.y = rng.randf_range(0.0, TAU)
					bush.scale = Vector3.ONE * rng.randf_range(0.85, 1.55)
					FoliageWind.apply_to_tree(bush, 0.08, 1.65, float(ri) * 0.6)
					_apply_vis_range(bush, 95.0, false)
					isl.add_child(bush)

	# Also line scenic Nile East & West sandy banks with Acacia/Sunut & Date Palms (clear of bridges & docks)
	var bank_spots: Array[Dictionary] = [
		{"pos": Vector3(-135.5, 0.0, -520.0), "sp": SudaneseTreeBuilder.TreeSpecies.ACACIA},
		{"pos": Vector3(-135.5, 0.0, -430.0), "sp": SudaneseTreeBuilder.TreeSpecies.DATE_PALM},
		{"pos": Vector3(-135.5, 0.0, -290.0), "sp": SudaneseTreeBuilder.TreeSpecies.ACACIA},
		{"pos": Vector3(-135.5, 0.0, -195.0), "sp": SudaneseTreeBuilder.TreeSpecies.DATE_PALM},
		{"pos": Vector3(-135.5, 0.0, 145.0),  "sp": SudaneseTreeBuilder.TreeSpecies.ACACIA},
		{"pos": Vector3(-135.5, 0.0, 295.0),  "sp": SudaneseTreeBuilder.TreeSpecies.DATE_PALM},
		{"pos": Vector3(-135.5, 0.0, 445.0),  "sp": SudaneseTreeBuilder.TreeSpecies.ACACIA},
		{"pos": Vector3(-244.5, 0.0, -480.0), "sp": SudaneseTreeBuilder.TreeSpecies.DATE_PALM},
		{"pos": Vector3(-244.5, 0.0, -265.0), "sp": SudaneseTreeBuilder.TreeSpecies.ACACIA},
		{"pos": Vector3(-244.5, 0.0, -145.0), "sp": SudaneseTreeBuilder.TreeSpecies.DATE_PALM},
		{"pos": Vector3(-244.5, 0.0, 85.0),   "sp": SudaneseTreeBuilder.TreeSpecies.ACACIA},
		{"pos": Vector3(-244.5, 0.0, 225.0),  "sp": SudaneseTreeBuilder.TreeSpecies.DATE_PALM},
		{"pos": Vector3(-244.5, 0.0, 455.0),  "sp": SudaneseTreeBuilder.TreeSpecies.ACACIA},
	]
	for bi in range(bank_spots.size()):
		var bsp: Dictionary = bank_spots[bi]
		var bpos: Vector3 = bsp["pos"] as Vector3
		if SmartWorldOrganizer.is_in_bridge_exclusion(bpos, 5.0):
			continue
		var bt := SudaneseTreeBuilder.new()
		bt.name = "NileBankTree_%d" % bi
		bt.species = bsp["sp"]
		bt.variant_seed = 200 + bi
		bt.height_scale = rng.randf_range(0.95, 1.22)
		bt.vis_range_end = 150.0
		bt.position = bsp["pos"]
		bt.rotation.y = rng.randf_range(0.0, TAU)
		islands_root.add_child(bt)


func _build_sloped_island_mesh(rx: float, rz: float, bottom_y: float, top_y: float, segs: int) -> ArrayMesh:
	# Multi-ring radial elliptical mound with smooth cosine-sloped sandy beaches from riverbed to plateau
	var rings: Array[Vector2] = [
		Vector2(0.00, top_y + 0.12),
		Vector2(0.32, top_y + 0.06),
		Vector2(0.52, top_y * 0.72),
		Vector2(0.68, WATER_SURFACE_Y + 0.22),
		Vector2(0.82, WATER_SURFACE_Y - 0.65),
		Vector2(1.00, bottom_y),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for r_i in range(rings.size() - 1):
		var r0: float = rings[r_i].x
		var y0: float = rings[r_i].y
		var r1: float = rings[r_i + 1].x
		var y1: float = rings[r_i + 1].y
		for s in range(segs):
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float((s + 1) % segs) / float(segs)
			var p00 := Vector3(cos(a0) * rx * r0, y0, sin(a0) * rz * r0)
			var p10 := Vector3(cos(a1) * rx * r0, y0, sin(a1) * rz * r0)
			var p01 := Vector3(cos(a0) * rx * r1, y1, sin(a0) * rz * r1)
			var p11 := Vector3(cos(a1) * rx * r1, y1, sin(a1) * rz * r1)

			var uv00 := Vector2(p00.x * 0.08, p00.z * 0.08)
			var uv10 := Vector2(p10.x * 0.08, p10.z * 0.08)
			var uv01 := Vector2(p01.x * 0.08, p01.z * 0.08)
			var uv11 := Vector2(p11.x * 0.08, p11.z * 0.08)

			if r0 > 0.001:
				st.set_uv(uv00); st.add_vertex(p00)
				st.set_uv(uv11); st.add_vertex(p11)
				st.set_uv(uv10); st.add_vertex(p10)
			st.set_uv(uv00); st.add_vertex(p00)
			st.set_uv(uv01); st.add_vertex(p01)
			st.set_uv(uv11); st.add_vertex(p11)

	st.generate_normals()
	return st.commit()


func _sample_island_height(norm_r: float, bottom_y: float, top_y: float) -> float:
	if norm_r <= 0.32:
		return top_y + 0.06
	if norm_r <= 0.68:
		var t := (norm_r - 0.32) / 0.36
		return lerpf(top_y + 0.06, WATER_SURFACE_Y + 0.22, t)
	var t2 := clampf((norm_r - 0.68) / 0.32, 0.0, 1.0)
	return lerpf(WATER_SURFACE_Y + 0.22, bottom_y, t2)


func _scatter_river_rocks() -> void:
	rocks_root = Node3D.new()
	rocks_root.name = "NileRiverRocks"
	add_child(rocks_root)

	var rock_scenes: Array[PackedScene] = []
	for rp in PATH_ROCKS:
		if ResourceLoader.exists(rp):
			var ps := load(rp) as PackedScene
			if ps != null:
				rock_scenes.append(ps)

	var rng := RandomNumberGenerator.new()
	rng.seed = 447812

	# 1. Shoreline rocks along East (x ~ -148..-155) & West (x ~ -232..-225) shallow banks (skipping bridge piers & docks)
	var z_pos := -620.0
	while z_pos <= 620.0:
		var near_bridge := absf(z_pos) < 28.0 or absf(z_pos + 360.0) < 28.0 or absf(z_pos - 360.0) < 28.0
		var near_dock := absf(z_pos + 90.0) < 22.0 or absf(z_pos + 110.0) < 22.0 or absf(z_pos - 240.0) < 22.0
		if not near_bridge and not near_dock:
			var side := -1.0 if (rng.randi() % 2 == 0) else 1.0
			var rx := (-149.5 - rng.randf_range(0.0, 5.5)) if side > 0.0 else (-230.5 + rng.randf_range(0.0, 5.5))
			var sc := rng.randf_range(0.95, 2.35)
			_spawn_rock(rock_scenes, Vector3(rx, WATER_SURFACE_Y - 0.45, z_pos + rng.randf_range(-8.0, 8.0)), sc, rng)
		z_pos += 36.0

	# 2. Rocks & boulders ringing each Nile island shoreline (generating realistic white water foam rings)
	if islands_root != null:
		for isl in islands_root.get_children():
			var isl3 := isl as Node3D
			if isl3 == null or not isl3.is_in_group("NileIslands"):
				continue
			for k in range(4):
				var a := TAU * float(k) / 4.0 + rng.randf_range(-0.4, 0.4)
				var offset := Vector3(cos(a) * rng.randf_range(9.5, 13.5), WATER_SURFACE_Y - 0.35, sin(a) * rng.randf_range(15.0, 22.0))
				_spawn_rock(rock_scenes, isl3.position + offset, rng.randf_range(1.1, 2.4), rng)


func _spawn_rock(rock_scenes: Array[PackedScene], world_pos: Vector3, scale_f: float, rng: RandomNumberGenerator) -> void:
	if SmartWorldOrganizer.is_in_bridge_exclusion(world_pos, 3.5):
		return
	var sb := StaticBody3D.new()
	sb.name = "RiverRock_%d" % _rock_count
	sb.position = world_pos
	sb.rotation = Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(0.0, TAU), rng.randf_range(-0.18, 0.18))
	rocks_root.add_child(sb)
	_rock_count += 1

	var col_radius := 0.85 * scale_f
	if not rock_scenes.is_empty():
		var r_inst := rock_scenes[rng.randi_range(0, rock_scenes.size() - 1)].instantiate() as Node3D
		if r_inst != null:
			r_inst.scale = Vector3.ONE * scale_f
			_apply_vis_range(r_inst, 110.0, false)
			sb.add_child(r_inst)
	else:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = col_radius
		sm.height = col_radius * 1.4
		sm.material = _mat_rock_fallback
		mi.mesh = sm
		mi.visibility_range_end = 110.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sb.add_child(mi)

	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = col_radius
	cs.shape = ss
	cs.position = Vector3(0.0, col_radius * 0.35, 0.0)
	sb.add_child(cs)


func _add_static_box(parent: Node3D, n_name: String, pos: Vector3, sz: Vector3, mat: Material, vis_end: float) -> void:
	var sb := StaticBody3D.new()
	sb.name = n_name
	sb.position = pos
	parent.add_child(sb)
	_fill_box_body(sb, sz, mat, vis_end)


func _fill_box_body(sb: StaticBody3D, sz: Vector3, mat: Material, vis_end: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	bm.material = mat
	mi.mesh = bm
	mi.visibility_range_end = vis_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sb.add_child(mi)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	sb.add_child(cs)


func _apply_vis_range(node: Node, dist: float, cast_shadows: bool = true) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.visibility_range_end = dist
		if not cast_shadows:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_apply_vis_range(c, dist, cast_shadows)


func _find_main_root() -> Node3D:
	var cur: Node = self
	while cur != null:
		if cur.get_node_or_null("Neighborhood/NileRiver") != null:
			return cur as Node3D
		cur = cur.get_parent()
	return get_tree().current_scene as Node3D
