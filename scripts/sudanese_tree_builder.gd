extends Node3D
class_name SudaneseTreeBuilder

## Organic Multi-Part Sudanese Tree Generator & Prefab Controller (`res://scripts/sudanese_tree_builder.gd`).
## Replaces blocky BoxMesh trees with authentic Khartoum species:
## - 0: Shady Street Neem Tree (`شجر النيم`) — tapered trunk, 4 angled branches, 9 ruffled olive/forest leaf clusters
## - 1: Nile Acacia / Sunut (`شجر السنط`) — curved forked trunk, wide layered flat-topped umbrella canopy
## - 2: Date Palm (`النخيل`) — 10-segment curved ringed trunk, date clusters, crown of 14 arched curved palm fronds
## - 3: Repaired 4K Realistic Tree (`island_tree_02.gltf`) — sunk root, alpha-scissor 0.35 + alpha-to-coverage + wind sway
##
## All variants share cached GPU `ArrayMesh`es and use lightweight trunk-only `CylinderShape3D` collision.

enum TreeSpecies {
	NEEM = 0,
	ACACIA = 1,
	DATE_PALM = 2,
	REALISTIC_4K = 3,
}

const PATH_REALISTIC_4K_TREE: String = "res://assets/models/foliage/island_tree_02/island_tree_02.gltf"

@export var species: TreeSpecies = TreeSpecies.NEEM
@export var variant_seed: int = 0
@export var height_scale: float = 1.0
@export var add_trunk_collider: bool = true
@export var vis_range_end: float = 150.0

static var _mesh_cache: Dictionary = {}
static var _bark_mat_cache: Dictionary = {}
static var _canopy_mat_cache: Dictionary = {}


func _ready() -> void:
	_build_tree_instance()


func _build_tree_instance() -> void:
	if species == TreeSpecies.REALISTIC_4K:
		_build_realistic_4k_tree()
		return

	var v_idx: int = absi(variant_seed + int(round(global_position.x * 0.37 + global_position.z * 0.53))) % 3
	var pair := get_species_meshes(species, v_idx)
	var trunk_mesh: ArrayMesh = pair["trunk"]
	var canopy_mesh: ArrayMesh = pair["canopy"]
	var canopy_inner: ArrayMesh = pair.get("canopy_inner") as ArrayMesh

	var trunk_mi := MeshInstance3D.new()
	trunk_mi.name = "TrunkBranches"
	trunk_mi.mesh = trunk_mesh
	trunk_mi.material_override = get_bark_material(species)
	trunk_mi.visibility_range_end = minf(vis_range_end, 150.0)
	trunk_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	trunk_mi.scale = Vector3.ONE * height_scale
	add_child(trunk_mi)

	var canopy_mi := MeshInstance3D.new()
	canopy_mi.name = "FoliageCanopy"
	canopy_mi.mesh = canopy_mesh
	canopy_mi.material_override = get_canopy_material(species)
	canopy_mi.visibility_range_end = minf(vis_range_end, 150.0)
	canopy_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	canopy_mi.scale = Vector3.ONE * height_scale
	add_child(canopy_mi)

	if canopy_inner != null and canopy_inner.get_surface_count() > 0:
		var inner_mi := MeshInstance3D.new()
		inner_mi.name = "FoliageInner"
		inner_mi.mesh = canopy_inner
		inner_mi.material_override = get_canopy_material(species)
		inner_mi.visibility_range_end = minf(vis_range_end, 115.0)
		# Inner overlapping clusters never need to cast duplicate shadows
		inner_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inner_mi.scale = Vector3.ONE * height_scale
		add_child(inner_mi)

	if add_trunk_collider:
		var col_r: float = (0.24 if species == TreeSpecies.DATE_PALM else 0.26) * height_scale
		var col_h: float = (3.0 if species == TreeSpecies.DATE_PALM else 2.4) * height_scale
		_attach_trunk_collider(col_r, col_h)


func _build_realistic_4k_tree() -> void:
	if not ResourceLoader.exists(PATH_REALISTIC_4K_TREE):
		species = TreeSpecies.NEEM
		_build_tree_instance()
		return
	var packed := ResourceLoader.load(PATH_REALISTIC_4K_TREE) as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return

	var aabb := CharacterModelLoader._compute_mesh_aabb(inst)
	var target_h := 5.6 * height_scale
	if aabb.size.y > 0.001:
		var s := target_h / aabb.size.y
		inst.scale = Vector3.ONE * s
		var cx := (aabb.position.x + aabb.size.x * 0.5) * s
		var cz := (aabb.position.z + aabb.size.z * 0.5) * s
		var by := aabb.position.y * s
		inst.position = Vector3(-cx, -by - 0.14, -cz)

	FoliageWind.apply_to_tree(inst, 0.11, 1.45, float(variant_seed) * 0.7)
	_apply_vis_recursive(inst, minf(vis_range_end, 140.0))
	add_child(inst)

	if add_trunk_collider:
		_attach_trunk_collider(0.28 * height_scale, 2.5 * height_scale)


func _attach_trunk_collider(radius: float, height: float) -> void:
	var sb := StaticBody3D.new()
	sb.name = "TrunkCollider"
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	cs.position = Vector3(0.0, height * 0.5, 0.0)
	sb.add_child(cs)
	add_child(sb)


func _apply_vis_recursive(node: Node, vis_end: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visibility_range_end = vis_end
	for ch in node.get_children():
		_apply_vis_recursive(ch, vis_end)


static func get_bark_material(sp: TreeSpecies) -> StandardMaterial3D:
	if _bark_mat_cache.has(sp):
		return _bark_mat_cache[sp] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.metallic = 0.0
	mat.roughness = 0.92
	_bark_mat_cache[sp] = mat
	return mat


static func get_canopy_material(sp: TreeSpecies) -> ShaderMaterial:
	if _canopy_mat_cache.has(sp):
		return _canopy_mat_cache[sp] as ShaderMaterial
	var strength := 0.15 if sp == TreeSpecies.DATE_PALM else (0.11 if sp == TreeSpecies.ACACIA else 0.09)
	var min_h := 3.8 if sp == TreeSpecies.DATE_PALM else (2.2 if sp == TreeSpecies.ACACIA else 1.8)
	var smat := FoliageWind.create_canopy_wind_material(
		Color(1.0, 1.0, 1.0, 1.0),
		true,
		strength,
		1.45,
		min_h,
		float(sp) * 1.3
	)
	_canopy_mat_cache[sp] = smat
	return smat


static func get_species_meshes(sp: TreeSpecies, variant: int = 0) -> Dictionary:
	var key := "%d_%d" % [int(sp), variant % 3]
	if _mesh_cache.has(key):
		return _mesh_cache[key] as Dictionary

	var rng := RandomNumberGenerator.new()
	rng.seed = 77100 + int(sp) * 997 + (variant % 3) * 131

	var result: Dictionary
	match sp:
		TreeSpecies.NEEM:
			result = _generate_neem_meshes(rng)
		TreeSpecies.ACACIA:
			result = _generate_acacia_meshes(rng)
		TreeSpecies.DATE_PALM:
			result = _generate_date_palm_meshes(rng)
		_:
			result = _generate_neem_meshes(rng)

	_mesh_cache[key] = result
	return result


# ==============================================================================
# 1. SHADY STREET NEEM TREE (`شجر النيم`)
#    Tapered cylindrical trunk + 4 angled secondary branches + 9 organic ruffled
#    olive/forest-green foliage clusters.
# ==============================================================================
static func _generate_neem_meshes(rng: RandomNumberGenerator) -> Dictionary:
	var st_bark := SurfaceTool.new()
	st_bark.begin(Mesh.PRIMITIVE_TRIANGLES)

	var bark_base := Color(0.34, 0.25, 0.18, 1.0)
	var bark_upper := Color(0.41, 0.31, 0.23, 1.0)

	# Main tapered trunk sunk -0.14m below ground up to y = 2.65m with natural lean
	var lean_x := rng.randf_range(-0.12, 0.12)
	var lean_z := rng.randf_range(-0.12, 0.12)
	var trunk_pts: Array[Vector3] = [
		Vector3(0.0, -0.14, 0.0),
		Vector3(lean_x * 0.25, 0.65, lean_z * 0.25),
		Vector3(lean_x * 0.60, 1.50, lean_z * 0.60),
		Vector3(lean_x * 0.90, 2.20, lean_z * 0.90),
		Vector3(lean_x, 2.75, lean_z),
	]
	var trunk_rads: Array[float] = [0.30, 0.23, 0.19, 0.16, 0.12]
	_add_tube(st_bark, trunk_pts, trunk_rads, 7, bark_base, bark_upper)

	var st_leaf_outer := SurfaceTool.new()
	st_leaf_outer.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_leaf_inner := SurfaceTool.new()
	st_leaf_inner.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 4 angled secondary branches splitting outward from upper trunk
	var branch_tips: Array[Vector3] = []
	var base_ang := rng.randf_range(0.0, TAU)
	for bi in range(4):
		var ang := base_ang + (TAU * float(bi) / 4.0) + rng.randf_range(-0.28, 0.28)
		var start_y := rng.randf_range(1.85, 2.45)
		var start_p := Vector3(lean_x * (start_y / 2.75), start_y, lean_z * (start_y / 2.75))
		var reach := rng.randf_range(1.25, 1.70)
		var mid_p := start_p + Vector3(cos(ang) * reach * 0.55, rng.randf_range(0.55, 0.85), sin(ang) * reach * 0.55)
		var tip_p := start_p + Vector3(cos(ang) * reach, rng.randf_range(1.05, 1.55), sin(ang) * reach)
		_add_tube(st_bark, [start_p, mid_p, tip_p], [0.11, 0.075, 0.042], 5, bark_base.lerp(bark_upper, 0.5), bark_upper)
		branch_tips.append(tip_p)

	# 9 overlapping low-poly ruffled foliage clusters (radial=8, rings=4):
	# 5 outer clusters cast shadows; 4 inner infill clusters skip shadow pass!
	var crown_top := Color(0.28, 0.49, 0.18, 1.0)
	var crown_mid := Color(0.19, 0.38, 0.14, 1.0)
	var crown_shade := Color(0.10, 0.22, 0.08, 1.0)

	for i in range(branch_tips.size()):
		var tip := branch_tips[i]
		var r := rng.randf_range(1.18, 1.48)
		_add_ruffled_cluster(st_leaf_outer, tip + Vector3(0.0, 0.25, 0.0), Vector3(r * 1.15, r * 0.82, r * 1.15), crown_top, crown_mid, crown_shade, rng.randf() * 50.0)

	for i in range(4):
		var ang := base_ang + (TAU * (float(i) + 0.5) / 4.0) + rng.randf_range(-0.2, 0.2)
		var rad := rng.randf_range(1.05, 1.45)
		var center := Vector3(lean_x + cos(ang) * rad, rng.randf_range(3.35, 3.95), lean_z + sin(ang) * rad)
		var r := rng.randf_range(1.05, 1.32)
		_add_ruffled_cluster(st_leaf_inner, center, Vector3(r * 1.12, r * 0.78, r * 1.12), crown_top, crown_mid, crown_shade, rng.randf() * 50.0)

	_add_ruffled_cluster(
		st_leaf_outer,
		Vector3(lean_x, 4.35, lean_z),
		Vector3(1.55, 1.05, 1.55),
		crown_top.lightened(0.08),
		crown_mid,
		crown_shade,
		rng.randf() * 50.0
	)

	st_bark.generate_normals()
	st_leaf_outer.generate_normals()
	st_leaf_inner.generate_normals()
	return {"trunk": st_bark.commit(), "canopy": st_leaf_outer.commit(), "canopy_inner": st_leaf_inner.commit()}


# ==============================================================================
# 2. NILE ACACIA / SUNUT TREE (`شجر السنط`)
# ==============================================================================
static func _generate_acacia_meshes(rng: RandomNumberGenerator) -> Dictionary:
	var st_bark := SurfaceTool.new()
	st_bark.begin(Mesh.PRIMITIVE_TRIANGLES)

	var bark_base := Color(0.28, 0.21, 0.16, 1.0)
	var bark_upper := Color(0.36, 0.28, 0.21, 1.0)

	var curve_ang := rng.randf_range(0.0, TAU)
	var cx := cos(curve_ang)
	var cz := sin(curve_ang)
	var trunk_pts: Array[Vector3] = [
		Vector3(0.0, -0.14, 0.0),
		Vector3(cx * 0.18, 0.75, cz * 0.18),
		Vector3(cx * 0.42, 1.55, cz * 0.42),
		Vector3(cx * 0.34, 2.35, cz * 0.34),
	]
	_add_tube(st_bark, trunk_pts, [0.28, 0.22, 0.18, 0.14], 7, bark_base, bark_upper)

	var st_leaf_outer := SurfaceTool.new()
	st_leaf_outer.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_leaf_inner := SurfaceTool.new()
	st_leaf_inner.begin(Mesh.PRIMITIVE_TRIANGLES)

	var fork_origin := trunk_pts[trunk_pts.size() - 1]
	var base_ang := rng.randf_range(0.0, TAU)
	var branch_tips: Array[Vector3] = []

	for bi in range(4):
		var ang := base_ang + (TAU * float(bi) / 4.0) + rng.randf_range(-0.30, 0.30)
		var reach := rng.randf_range(1.85, 2.45)
		var mid := fork_origin + Vector3(cos(ang) * reach * 0.52, rng.randf_range(0.55, 0.80), sin(ang) * reach * 0.52)
		var tip := fork_origin + Vector3(cos(ang) * reach, rng.randf_range(0.95, 1.35), sin(ang) * reach)
		_add_tube(st_bark, [fork_origin, mid, tip], [0.11, 0.075, 0.04], 5, bark_base.lerp(bark_upper, 0.5), bark_upper)
		branch_tips.append(tip)

	var top_col := Color(0.32, 0.45, 0.18, 1.0)
	var mid_col := Color(0.22, 0.35, 0.13, 1.0)
	var bot_col := Color(0.12, 0.21, 0.08, 1.0)

	for tip in branch_tips:
		var rx := rng.randf_range(1.55, 1.95)
		var ry := rng.randf_range(0.42, 0.56)
		_add_ruffled_cluster(st_leaf_outer, tip + Vector3(0.0, 0.18, 0.0), Vector3(rx, ry, rx), top_col, mid_col, bot_col, rng.randf() * 50.0)

	for bi in range(4):
		var ang := base_ang + (TAU * (float(bi) + 0.5) / 4.0) + rng.randf_range(-0.22, 0.22)
		var dist := rng.randf_range(1.25, 1.75)
		var pos := fork_origin + Vector3(cos(ang) * dist, rng.randf_range(1.25, 1.55), sin(ang) * dist)
		var rx := rng.randf_range(1.35, 1.65)
		_add_ruffled_cluster(st_leaf_inner, pos, Vector3(rx, 0.46, rx), top_col, mid_col, bot_col, rng.randf() * 50.0)

	_add_ruffled_cluster(
		st_leaf_outer,
		fork_origin + Vector3(0.0, 1.68, 0.0),
		Vector3(2.05, 0.52, 2.05),
		top_col.lightened(0.07),
		mid_col,
		bot_col,
		rng.randf() * 50.0
	)

	st_bark.generate_normals()
	st_leaf_outer.generate_normals()
	st_leaf_inner.generate_normals()
	return {"trunk": st_bark.commit(), "canopy": st_leaf_outer.commit(), "canopy_inner": st_leaf_inner.commit()}


# ==============================================================================
# 3. SUDANESE DATE PALM (`النخيل`)
# ==============================================================================
static func _generate_date_palm_meshes(rng: RandomNumberGenerator) -> Dictionary:
	var st_trunk := SurfaceTool.new()
	st_trunk.begin(Mesh.PRIMITIVE_TRIANGLES)

	var total_h := rng.randf_range(5.8, 6.8)
	var curve_ang := rng.randf_range(0.0, TAU)
	var lean_amt := rng.randf_range(0.32, 0.65)
	var segs: int = 8

	var pts: Array[Vector3] = []
	var rads: Array[float] = []
	var cols: Array[Color] = []

	var bark_dark := Color(0.31, 0.23, 0.15, 1.0)
	var bark_ridge := Color(0.46, 0.35, 0.23, 1.0)

	for si in range(segs):
		var t0 := float(si) / float(segs)
		var t1 := float(si + 1) / float(segs)
		var y0 := lerpf(-0.18, total_h, t0)
		var y1 := lerpf(-0.18, total_h, t1)
		var c0 := Vector3(cos(curve_ang) * lean_amt * sin(t0 * PI * 0.72), y0, sin(curve_ang) * lean_amt * sin(t0 * PI * 0.72))
		var c1 := Vector3(cos(curve_ang) * lean_amt * sin(t1 * PI * 0.72), y1, sin(curve_ang) * lean_amt * sin(t1 * PI * 0.72))
		var base_r := lerpf(0.28, 0.16, t0)
		var top_r := lerpf(0.28, 0.16, t1)
		var flare_r := top_r * 1.18
		pts.append(c0)
		rads.append(base_r)
		cols.append(bark_dark)
		pts.append(c1)
		rads.append(flare_r)
		cols.append(bark_ridge)

	_add_ringed_tube(st_trunk, pts, rads, cols, 7)

	var crown_pt := pts[pts.size() - 1]
	var date_col := Color(0.78, 0.50, 0.14, 1.0)
	for di in range(3):
		var dang := (TAU * float(di) / 3.0) + rng.randf_range(-0.2, 0.2)
		var dpos := crown_pt + Vector3(cos(dang) * 0.28, -0.26, sin(dang) * 0.28)
		_add_ruffled_cluster(st_trunk, dpos, Vector3(0.20, 0.28, 0.20), date_col, date_col.darkened(0.15), date_col.darkened(0.32), float(di) * 7.0)

	var st_fronds := SurfaceTool.new()
	st_fronds.begin(Mesh.PRIMITIVE_TRIANGLES)

	var frond_base := Color(0.16, 0.34, 0.12, 1.0)
	var frond_mid := Color(0.24, 0.48, 0.16, 1.0)
	var frond_tip := Color(0.36, 0.58, 0.22, 1.0)

	var phase0 := rng.randf_range(0.0, TAU)
	for fi in range(8):
		var az := phase0 + (TAU * float(fi) / 8.0) + rng.randf_range(-0.14, 0.14)
		var flen := rng.randf_range(2.35, 2.85)
		var arch_h := rng.randf_range(0.55, 0.85)
		var droop := rng.randf_range(0.85, 1.25)
		_add_arched_palm_frond(st_fronds, crown_pt + Vector3(0.0, -0.04, 0.0), az, flen, arch_h, droop, 0.38, frond_base, frond_mid, frond_tip)

	for fi in range(6):
		var az := phase0 + 0.38 + (TAU * float(fi) / 6.0) + rng.randf_range(-0.16, 0.16)
		var flen := rng.randf_range(1.85, 2.25)
		var arch_h := rng.randf_range(1.05, 1.42)
		var droop := rng.randf_range(0.35, 0.65)
		_add_arched_palm_frond(st_fronds, crown_pt + Vector3(0.0, 0.06, 0.0), az, flen, arch_h, droop, 0.34, frond_base, frond_mid, frond_tip)

	st_trunk.generate_normals()
	st_fronds.generate_normals()
	return {"trunk": st_trunk.commit(), "canopy": st_fronds.commit(), "canopy_inner": null}


# ==============================================================================
# GEOMETRY PRIMITIVE HELPERS
# ==============================================================================
static func _add_tube(st: SurfaceTool, pts: Array[Vector3], rads: Array[float], sides: int, col_a: Color, col_b: Color) -> void:
	var cols: Array[Color] = []
	for i in range(pts.size()):
		var t := float(i) / float(max(1, pts.size() - 1))
		cols.append(col_a.lerp(col_b, t))
	_add_ringed_tube(st, pts, rads, cols, sides)


static func _add_ringed_tube(st: SurfaceTool, pts: Array[Vector3], rads: Array[float], cols: Array[Color], sides: int) -> void:
	if pts.size() < 2:
		return
	var rings: Array[Array] = []
	for i in range(pts.size()):
		var p: Vector3 = pts[i]
		var tangent: Vector3
		if i == 0:
			tangent = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			tangent = (pts[i] - pts[i - 1]).normalized()
		else:
			tangent = (pts[i + 1] - pts[i - 1]).normalized()
		if tangent.length_squared() < 0.0001:
			tangent = Vector3.UP
		var ref_v := Vector3.RIGHT if absf(tangent.dot(Vector3.UP)) > 0.92 else Vector3.UP
		var side_x := tangent.cross(ref_v).normalized()
		var side_z := side_x.cross(tangent).normalized()
		var r: float = rads[i]
		var ring: Array[Vector3] = []
		for s in range(sides):
			var a := TAU * float(s) / float(sides)
			ring.append(p + (side_x * cos(a) + side_z * sin(a)) * r)
		rings.append(ring)

	for i in range(rings.size() - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var c0: Color = cols[i]
		var c1: Color = cols[i + 1]
		for s in range(sides):
			var sn := (s + 1) % sides
			var p00: Vector3 = r0[s]
			var p01: Vector3 = r0[sn]
			var p10: Vector3 = r1[s]
			var p11: Vector3 = r1[sn]
			# Outward-facing quad
			st.set_color(c0); st.add_vertex(p00)
			st.set_color(c0); st.add_vertex(p01)
			st.set_color(c1); st.add_vertex(p11)

			st.set_color(c0); st.add_vertex(p00)
			st.set_color(c1); st.add_vertex(p11)
			st.set_color(c1); st.add_vertex(p10)


static func _add_ruffled_cluster(
	st: SurfaceTool,
	center: Vector3,
	radii: Vector3,
	top_col: Color,
	mid_col: Color,
	bot_col: Color,
	noise_seed: float,
	radial_segments: int = 8,
	rings: int = 4
) -> void:
	# Compact low-poly organic ruffled sphere (`radial_segments = 8`, `rings = 4` = 48 tris/cluster)
	var grid: Array[Array] = []
	var col_grid: Array[Array] = []
	for ri in range(rings + 1):
		var phi := PI * float(ri) / float(rings)
		var y := cos(phi)
		var sin_p := sin(phi)
		var row_v: Array[Vector3] = []
		var row_c: Array[Color] = []
		for si in range(radial_segments):
			var theta := TAU * float(si) / float(radial_segments)
			var u := Vector3(sin_p * cos(theta), y, sin_p * sin(theta))
			var ruffle := 1.0 + 0.14 * sin(u.x * 5.7 + noise_seed) * cos(u.y * 6.3 - noise_seed * 0.7) + 0.07 * sin(u.z * 8.1 + noise_seed * 1.3)
			var p := center + Vector3(u.x * radii.x, u.y * radii.y, u.z * radii.z) * ruffle
			var h_t := clampf((u.y + 1.0) * 0.5, 0.0, 1.0)
			var col := bot_col.lerp(mid_col, clampf(h_t * 1.4, 0.0, 1.0)).lerp(top_col, clampf((h_t - 0.35) * 1.5, 0.0, 1.0))
			var dapple := 0.92 + 0.16 * clampf(0.5 + 0.5 * sin(u.x * 9.0 + u.z * 7.5 + noise_seed), 0.0, 1.0)
			row_v.append(p)
			row_c.append(Color(col.r * dapple, col.g * dapple, col.b * dapple, 1.0))
		grid.append(row_v)
		col_grid.append(row_c)

	for ri in range(rings):
		for si in range(radial_segments):
			var sn := (si + 1) % radial_segments
			var p00: Vector3 = grid[ri][si]
			var p01: Vector3 = grid[ri][sn]
			var p10: Vector3 = grid[ri + 1][si]
			var p11: Vector3 = grid[ri + 1][sn]
			var c00: Color = col_grid[ri][si]
			var c01: Color = col_grid[ri][sn]
			var c10: Color = col_grid[ri + 1][si]
			var c11: Color = col_grid[ri + 1][sn]
			if ri > 0:
				st.set_color(c00); st.add_vertex(p00)
				st.set_color(c11); st.add_vertex(p11)
				st.set_color(c01); st.add_vertex(p01)
			if ri < rings - 1:
				st.set_color(c00); st.add_vertex(p00)
				st.set_color(c10); st.add_vertex(p10)
				st.set_color(c11); st.add_vertex(p11)


static func _add_arched_palm_frond(
	st: SurfaceTool,
	origin: Vector3,
	azimuth: float,
	length: float,
	arch_height: float,
	tip_droop: float,
	max_half_width: float,
	col_base: Color,
	col_mid: Color,
	col_tip: Color
) -> void:
	# Multi-segment curved arched frond with V-folded leaflet wings (gives real 3D volume from all angles)
	var dir_xz := Vector3(cos(azimuth), 0.0, sin(azimuth))
	var side_xz := Vector3(-sin(azimuth), 0.0, cos(azimuth))
	var segs: int = 6

	var spine_pts: Array[Vector3] = []
	var left_pts: Array[Vector3] = []
	var right_pts: Array[Vector3] = []
	var seg_cols: Array[Color] = []

	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var dist := t * length
		# Smooth parabolic arch rising up then drooping naturally toward tip
		var y := arch_height * sin(t * PI * 0.78) - tip_droop * (t * t)
		var sp := origin + dir_xz * dist + Vector3(0.0, y, 0.0)
		# Frond width swells quickly then tapers cleanly to pointed tip
		var width_profile := sin(pow(t, 0.75) * PI)
		var hw := max_half_width * width_profile
		# V-fold droops leaflet edges slightly downward for authentic palm frond cross-section
		var v_drop := hw * 0.42
		spine_pts.append(sp)
		left_pts.append(sp - side_xz * hw + Vector3(0.0, -v_drop, 0.0))
		right_pts.append(sp + side_xz * hw + Vector3(0.0, -v_drop, 0.0))
		var c := col_base.lerp(col_mid, clampf(t * 1.5, 0.0, 1.0)).lerp(col_tip, clampf((t - 0.45) * 1.8, 0.0, 1.0))
		seg_cols.append(c)

	for i in range(segs):
		var s0: Vector3 = spine_pts[i]
		var s1: Vector3 = spine_pts[i + 1]
		var l0: Vector3 = left_pts[i]
		var l1: Vector3 = left_pts[i + 1]
		var r0: Vector3 = right_pts[i]
		var r1: Vector3 = right_pts[i + 1]
		var c0: Color = seg_cols[i]
		var c1: Color = seg_cols[i + 1]
		var edge0 := c0.darkened(0.08)
		var edge1 := c1.darkened(0.08)

		# Left wing quad
		st.set_color(c0); st.add_vertex(s0)
		st.set_color(edge0); st.add_vertex(l0)
		st.set_color(edge1); st.add_vertex(l1)

		st.set_color(c0); st.add_vertex(s0)
		st.set_color(edge1); st.add_vertex(l1)
		st.set_color(c1); st.add_vertex(s1)

		# Right wing quad
		st.set_color(c0); st.add_vertex(s0)
		st.set_color(edge1); st.add_vertex(r1)
		st.set_color(edge0); st.add_vertex(r0)

		st.set_color(c0); st.add_vertex(s0)
		st.set_color(c1); st.add_vertex(s1)
		st.set_color(edge1); st.add_vertex(r1)
