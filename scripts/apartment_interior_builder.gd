extends Node3D
class_name ApartmentInteriorBuilder

## High-FPS Multi-Story Apartment Upper-Floor Subdivision & Balcony Railing Builder for Godot 4.7.2.
##
## 1. Subdivides each upper floor (Floor_1 @ y=3.50, Floor_2 @ y=6.90, 17.6m x 9.6m) into:
##    - Central Landing Hallway (2.0m wide) connecting East switchback stair doorway (x=+9, z=0)
##      to Front Balcony Door (x=0, z=+5) and 3 distinct residential apartments with raised thresholds
##    - Apt A (North Suite: Living Hall, Master Bedroom, Kitchen, Bathroom)
##    - Apt B (South-West Suite: Living Room, Bedroom, Kitchenette)
##    - Apt C (South-East Suite: Living Room, Bedroom, Bathroom)
##    - All partition walls, raised thresholds (أعتاب الأبواب), door frames, rugs, sofas, beds,
##      wardrobes, kitchen counters/sinks/stoves/fridges & bathroom fixtures merged into 1 cached ArrayMesh!
## 2. Encloses ALL 4 exterior balconies (BalconyDeck_1/2 & SideBalconyDeck_1/2) on ALL THREE open edges
##    with sturdy 1.05m-tall Sudanese concrete-parapet + wrought-iron railings & matching BoxShape3D colliders!

@export var floor_elevations: PackedFloat32Array = PackedFloat32Array([3.50, 6.90])
@export var ceiling_height: float = 3.30
@export var vis_range_interior: float = 90.0
@export var vis_range_balcony: float = 135.0

static var _interior_mesh_cache: Dictionary = {}
static var _balcony_mesh_cache: Dictionary = {}
var _built: bool = false


func _ready() -> void:
	add_to_group("apartment_interiors")
	build_apartments()


func build_apartments() -> void:
	if _built:
		return
	_built = true

	var col_body := StaticBody3D.new()
	col_body.name = "ApartmentInteriorCollision"
	add_child(col_body)

	var balc_col_body := StaticBody3D.new()
	balc_col_body.name = "BalconyRailingCollision"
	balc_col_body.add_to_group("balcony_railings")
	add_child(balc_col_body)

	# 1. Build Subdivided Furnished Upper Floors (Floor 1 & Floor 2)
	var int_key := "apt_floors_%d_%.2f" % [floor_elevations.size(), ceiling_height]
	var cached_int := _interior_mesh_cache.get(int_key) as ArrayMesh
	var bi: InteriorMeshBatcher = null if cached_int != null else InteriorMeshBatcher.new()

	for fi in range(floor_elevations.size()):
		var fy := floor_elevations[fi]
		_build_single_apartment_floor(bi, col_body, fi, fy)

	var int_mesh: ArrayMesh
	if cached_int != null:
		int_mesh = cached_int
	else:
		int_mesh = bi.commit()
		_interior_mesh_cache[int_key] = int_mesh

	var int_mi := MeshInstance3D.new()
	int_mi.name = "MergedApartmentInteriors"
	int_mi.mesh = int_mesh
	int_mi.visibility_range_end = vis_range_interior
	int_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(int_mi)

	# 2. Build 3-Sided 1.05m Concrete+Iron Balcony Enclosures on ALL 4 exterior balconies
	var balc_key := "apt_balconies_%d" % floor_elevations.size()
	var cached_balc := _balcony_mesh_cache.get(balc_key) as ArrayMesh
	var bb: InteriorMeshBatcher = null if cached_balc != null else InteriorMeshBatcher.new()

	for fi in range(floor_elevations.size()):
		var fy := floor_elevations[fi]
		# Front BalconyDeck: pos=(0, fy+0.06, 6.0), size=(5.2, 0.16, 2.0) -> x in [-2.6, +2.6], z in [5.0, 7.0]
		_add_balcony_enclosure(
			bb, balc_col_body, "FrontBalcony_%d" % (fi + 1),
			Vector3(-2.60, fy + 0.06, 5.05), Vector3(2.60, fy + 0.06, 6.96),
			"front" # Open on -Z (wall side), enclosed on +Z (front), -X (left), +X (right)
		)
		# Side BalconyDeck: pos=(-9.9, fy+0.06, 1.8), size=(1.8, 0.16, 4.4) -> x in [-10.8, -9.0], z in [-0.4, +4.0]
		_add_balcony_enclosure(
			bb, balc_col_body, "SideBalcony_%d" % (fi + 1),
			Vector3(-10.76, fy + 0.06, -0.36), Vector3(-9.05, fy + 0.06, 3.96),
			"west" # Open on +X (wall side), enclosed on -X (outer west), -Z (north), +Z (south)
		)

	var balc_mesh: ArrayMesh
	if cached_balc != null:
		balc_mesh = cached_balc
	else:
		balc_mesh = bb.commit()
		_balcony_mesh_cache[balc_key] = balc_mesh

	var balc_mi := MeshInstance3D.new()
	balc_mi.name = "MergedBalconyRailings"
	balc_mi.mesh = balc_mesh
	balc_mi.visibility_range_end = vis_range_balcony
	balc_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(balc_mi)


func _build_single_apartment_floor(b: InteriorMeshBatcher, col_body: StaticBody3D, fi: int, fy: float) -> void:
	var h := ceiling_height
	var mat_wall := InteriorMeshBatcher.get_pbr_mat("ap_wall", "res://assets/textures/plaster", Color(0.95, 0.91, 0.84), 0.86, Vector3(0.5, 0.5, 0.5))
	var mat_tile_bath := InteriorMeshBatcher.get_pbr_mat("ap_bath_tile", "res://assets/textures/ceramic_tiles", Color(0.84, 0.92, 0.94), 0.35, Vector3(0.7, 0.7, 0.7))
	var mat_wood_dk := InteriorMeshBatcher.get_pbr_mat("ap_wood_dk", "res://assets/textures/wood", Color(0.45, 0.27, 0.16), 0.68, Vector3(0.9, 0.9, 0.9))
	var mat_wood_lt := InteriorMeshBatcher.get_pbr_mat("ap_wood_lt", "res://assets/textures/wood", Color(0.68, 0.48, 0.28), 0.70, Vector3(0.9, 0.9, 0.9))
	var mat_thresh := InteriorMeshBatcher.get_color_mat("ap_thresh", Color(0.76, 0.73, 0.68), 0.48, 0.05)
	var mat_sofa_a := InteriorMeshBatcher.get_color_mat("ap_sofa_a", Color(0.22, 0.38, 0.48), 0.88)
	var mat_sofa_b := InteriorMeshBatcher.get_color_mat("ap_sofa_b", Color(0.58, 0.24, 0.20), 0.88)
	var mat_linen := InteriorMeshBatcher.get_color_mat("ap_linen", Color(0.94, 0.93, 0.88), 0.90)
	var mat_blanket := InteriorMeshBatcher.get_color_mat("ap_blanket", Color(0.24, 0.44, 0.34), 0.90)
	var mat_counter := InteriorMeshBatcher.get_color_mat("ap_counter", Color(0.32, 0.32, 0.34), 0.42, 0.12)
	var mat_white := InteriorMeshBatcher.get_color_mat("ap_white", Color(0.94, 0.95, 0.96), 0.34, 0.08)
	var mat_steel := InteriorMeshBatcher.get_color_mat("ap_steel", Color(0.68, 0.72, 0.76), 0.32, 0.75)
	var mat_rug_a := InteriorMeshBatcher.get_sudanese_rug_mat(0)
	var mat_rug_b := InteriorMeshBatcher.get_sudanese_rug_mat(1)

	# Raised marble threshold at East exterior switchback doorway (x = +8.85, z = 0) & Front balcony door (x = 0, z = +4.85)
	if b != null:
		b.add_box(Vector3(8.85, fy + 0.016, 0.0), Vector3(0.34, 0.032, 1.56), mat_thresh)
		b.add_box(Vector3(0.0, fy + 0.016, 4.85), Vector3(1.48, 0.032, 0.34), mat_thresh)

	# ==========================================================================
	# CENTRAL LANDING HALLWAY (z in [-1.0, +1.0], x in [-4.6, +8.82], plus balcony branch x in [-1.0, +1.0], z in [+1.0, +4.82])
	# Keeps 2.0m clear corridor width so players and patrol NPCs move freely!
	# ==========================================================================
	# North Hallway Wall (z = -1.0, x in [-8.82, +8.82]) with Apt A entrance doorway at x in [+2.4, +3.7] (1.3m wide!)
	_add_partition_with_door_x(b, col_body, "F%d_HallN" % fi, fy, h, -1.0, -8.82, 8.82, 2.4, 3.7, mat_wall, mat_wood_dk, mat_thresh)

	# South-West Hallway Wall (z = +1.0, x in [-8.82, -1.0]) with Apt B entrance doorway at x in [-3.8, -2.5]
	_add_partition_with_door_x(b, col_body, "F%d_HallSW" % fi, fy, h, 1.0, -8.82, -1.0, -3.8, -2.5, mat_wall, mat_wood_dk, mat_thresh)

	# South-East Hallway Wall (z = +1.0, x in [+1.0, +8.82]) with Apt C entrance doorway at x in [+2.4, +3.7]
	_add_partition_with_door_x(b, col_body, "F%d_HallSE" % fi, fy, h, 1.0, 1.0, 8.82, 2.4, 3.7, mat_wall, mat_wood_dk, mat_thresh)

	# Balcony Corridor Side Walls (x = -1.0 and x = +1.0, z in [+1.0, +4.82]) separating Apt B & Apt C from balcony hall
	_add_solid_wall_z(b, col_body, "F%d_BalcCorL" % fi, fy, h, -1.0, 1.0, 4.82, mat_wall)
	_add_solid_wall_z(b, col_body, "F%d_BalcCorR" % fi, fy, h, 1.0, 1.0, 4.82, mat_wall)

	# ==========================================================================
	# APARTMENT A — NORTH SUITE (z in [-4.82, -1.0], x in [-8.82, +8.82])
	# Subdivided into: Living Hall (x: +0.8..+8.82), Master Bedroom (x: -4.4..+0.8),
	# Kitchen (x: -8.82..-4.4, z: -4.82..-2.7), Bathroom (x: -8.82..-4.4, z: -2.7..-1.0)
	# ==========================================================================
	# Partition: Living Hall <-> Bedroom (x = +0.8, doorway z in [-2.3, -1.2])
	_add_partition_with_door_z(b, col_body, "F%d_AptA_LivBed" % fi, fy, h, 0.8, -4.82, -1.0, -2.3, -1.2, mat_wall, mat_wood_dk, mat_thresh)
	# Partition: Bedroom <-> Kitchen/Bath (x = -4.4, doorway z in [-4.3, -3.3] into kitchen, [-2.3, -1.3] into bath)
	_add_partition_with_door_z(b, col_body, "F%d_AptA_BedKit" % fi, fy, h, -4.4, -4.82, -2.7, -4.2, -3.2, mat_wall, mat_wood_dk, mat_thresh)
	_add_partition_with_door_z(b, col_body, "F%d_AptA_BedBath" % fi, fy, h, -4.4, -2.7, -1.0, -2.35, -1.35, mat_wall, mat_wood_dk, mat_thresh)
	# Partition: Kitchen <-> Bathroom (z = -2.7, x in [-8.82, -4.4])
	_add_solid_wall_x(b, col_body, "F%d_AptA_KitBath" % fi, fy, h, -2.7, -8.82, -4.4, mat_wall)

	# Furnish Apt A Living Hall (x: +0.8..+8.82, z: -4.82..-1.0)
	if b != null:
		b.add_box(Vector3(5.6, fy + 0.012, -2.95), Vector3(3.4, 0.02, 2.3), mat_rug_a)
	_add_apt_sofa(b, col_body, "F%d_A_Sofa1" % fi, Vector3(5.6, fy, -4.28), 2.3, 0.0, mat_wood_dk, mat_sofa_a)
	_add_apt_sofa(b, col_body, "F%d_A_Sofa2" % fi, Vector3(8.15, fy, -2.95), 1.8, -PI * 0.5, mat_wood_dk, mat_sofa_a)
	_add_apt_table(b, col_body, "F%d_A_Table" % fi, Vector3(5.6, fy, -2.95), 1.15, 0.68, mat_wood_lt)

	# Furnish Apt A Master Bedroom (x: -4.4..+0.8, z: -4.82..-1.0)
	if b != null:
		b.add_box(Vector3(-1.8, fy + 0.012, -2.9), Vector3(2.2, 0.02, 1.8), mat_rug_b)
	_add_apt_bed(b, col_body, "F%d_A_Bed" % fi, Vector3(-1.8, fy, -3.72), 0.0, mat_wood_dk, mat_linen, mat_blanket)
	_add_apt_wardrobe(b, col_body, "F%d_A_Wardrobe" % fi, Vector3(0.32, fy, -3.75), -PI * 0.5, mat_wood_dk, mat_wood_lt)

	# Furnish Apt A Kitchen (x: -8.82..-4.4, z: -4.82..-2.7)
	_add_apt_kitchen(b, col_body, "F%d_A_Kitchen" % fi, Vector3(-6.8, fy, -4.42), 3.2, mat_wood_lt, mat_counter, mat_white, mat_steel)

	# Furnish Apt A Bathroom (x: -8.82..-4.4, z: -2.7..-1.0)
	_add_apt_bathroom(b, col_body, "F%d_A_Bath" % fi, Vector3(-7.6, fy, -1.85), mat_tile_bath, mat_white, mat_steel)

	# ==========================================================================
	# APARTMENT B — SOUTH-WEST SUITE (x in [-8.82, -1.0], z in [+1.0, +4.82])
	# Subdivided at x = -4.8 into Living Room (East: -4.8..-1.0) & Bedroom (West: -8.82..-4.8)
	# ==========================================================================
	_add_partition_with_door_z(b, col_body, "F%d_AptB_Div" % fi, fy, h, -4.8, 1.0, 4.82, 1.4, 2.4, mat_wall, mat_wood_dk, mat_thresh)
	if b != null:
		b.add_box(Vector3(-2.9, fy + 0.012, 3.15), Vector3(2.4, 0.02, 2.0), mat_rug_b)
	_add_apt_sofa(b, col_body, "F%d_B_Sofa" % fi, Vector3(-1.58, fy, 3.15), 2.0, -PI * 0.5, mat_wood_dk, mat_sofa_b)
	_add_apt_table(b, col_body, "F%d_B_Table" % fi, Vector3(-2.95, fy, 3.15), 0.95, 0.62, mat_wood_lt)
	# Bedroom West side
	_add_apt_bed(b, col_body, "F%d_B_Bed" % fi, Vector3(-7.55, fy, 3.55), PI * 0.5, mat_wood_dk, mat_linen, mat_blanket)
	_add_apt_wardrobe(b, col_body, "F%d_B_Wardrobe" % fi, Vector3(-8.32, fy, 1.85), PI * 0.5, mat_wood_dk, mat_wood_lt)

	# ==========================================================================
	# APARTMENT C — SOUTH-EAST SUITE (x in [+1.0, +8.82], z in [+1.0, +4.82])
	# Subdivided at x = +4.8 into Living Room (West: +1.0..+4.8) & Bedroom (East: +4.8..+8.82)
	# ==========================================================================
	_add_partition_with_door_z(b, col_body, "F%d_AptC_Div" % fi, fy, h, 4.8, 1.0, 4.82, 1.4, 2.4, mat_wall, mat_wood_dk, mat_thresh)
	if b != null:
		b.add_box(Vector3(2.9, fy + 0.012, 3.15), Vector3(2.4, 0.02, 2.0), mat_rug_a)
	_add_apt_sofa(b, col_body, "F%d_C_Sofa" % fi, Vector3(1.58, fy, 3.15), 2.0, PI * 0.5, mat_wood_dk, mat_sofa_a)
	_add_apt_table(b, col_body, "F%d_C_Table" % fi, Vector3(2.95, fy, 3.15), 0.95, 0.62, mat_wood_lt)
	# Bedroom East side
	_add_apt_bed(b, col_body, "F%d_C_Bed" % fi, Vector3(7.55, fy, 3.55), -PI * 0.5, mat_wood_dk, mat_linen, mat_blanket)
	_add_apt_wardrobe(b, col_body, "F%d_C_Wardrobe" % fi, Vector3(8.32, fy, 1.85), -PI * 0.5, mat_wood_dk, mat_wood_lt)

	# Warm interior lighting (2 compact non-shadow OmniLight3Ds per floor illuminating hallway & suites)
	for lx: float in [-3.8, 3.8]:
		var ol := OmniLight3D.new()
		ol.name = "AptFloorLight_%d_%.0f" % [fi, lx]
		ol.position = Vector3(lx, fy + h - 0.35, 0.0)
		ol.light_color = Color(1.0, 0.93, 0.78)
		ol.light_energy = 1.25
		ol.omni_range = 10.5
		ol.shadow_enabled = false
		add_child(ol)


# ==============================================================================
# 3-SIDED BALCONY ENCLOSURE (1.05m CONCRETE PARAPET + WROUGHT-IRON BARS + COLLISION)
# ==============================================================================
func _add_balcony_enclosure(
	b: InteriorMeshBatcher,
	col_body: StaticBody3D,
	prefix: String,
	p_min: Vector3,
	p_max: Vector3,
	open_side: String
) -> void:
	var y_base := p_min.y
	var total_h := 1.05
	var parapet_h := 0.42
	var mat_conc := InteriorMeshBatcher.get_pbr_mat("balc_conc", "res://assets/textures/plaster", Color(0.92, 0.87, 0.78), 0.86, Vector3(0.5, 0.5, 0.5))
	var mat_iron := InteriorMeshBatcher.get_color_mat("balc_iron", Color(0.14, 0.18, 0.22), 0.40, 0.68)

	# Build segments for the 3 open exterior edges
	var segs: Array[Array] = []
	if open_side == "front":
		# Open on -Z (wall); enclose +Z (front), -X (left), +X (right)
		segs.append([Vector3(p_min.x, y_base, p_max.z), Vector3(p_max.x, y_base, p_max.z), "Front"])
		segs.append([Vector3(p_min.x, y_base, p_min.z), Vector3(p_min.x, y_base, p_max.z), "Left"])
		segs.append([Vector3(p_max.x, y_base, p_min.z), Vector3(p_max.x, y_base, p_max.z), "Right"])
	else:
		# Open on +X (wall); enclose -X (outer west), -Z (north), +Z (south)
		segs.append([Vector3(p_min.x, y_base, p_min.z), Vector3(p_min.x, y_base, p_max.z), "Outer"])
		segs.append([Vector3(p_min.x, y_base, p_min.z), Vector3(p_max.x, y_base, p_min.z), "North"])
		segs.append([Vector3(p_min.x, y_base, p_max.z), Vector3(p_max.x, y_base, p_max.z), "South"])

	for seg in segs:
		var a: Vector3 = seg[0]
		var c: Vector3 = seg[1]
		var tag: String = String(seg[2])
		var span := a.distance_to(c)
		var ctr := (a + c) * 0.5
		var dx := absf(c.x - a.x)
		var dz := absf(c.z - a.z)
		if b != null:
			# Low concrete parapet wall (0.42m) + coping cap
			b.add_box(ctr + Vector3(0.0, parapet_h * 0.5, 0.0), Vector3(maxf(0.12, dx + 0.10), parapet_h, maxf(0.12, dz + 0.10)), mat_conc)
			# Painted Sudanese wrought-iron top handrail (at 1.05m) & mid rail (at 0.72m)
			b.add_bar(a + Vector3(0.0, total_h, 0.0), c + Vector3(0.0, total_h, 0.0), 0.052, 0.045, mat_iron)
			b.add_bar(a + Vector3(0.0, 0.72, 0.0), c + Vector3(0.0, 0.72, 0.0), 0.032, 0.028, mat_iron)
			# Vertical wrought-iron balusters every ~0.38m + corner posts
			var n_bars := maxi(2, int(round(span / 0.38)))
			for bi_idx in range(n_bars + 1):
				var t := float(bi_idx) / float(n_bars)
				var bp := a.lerp(c, t)
				var bw := 0.046 if (bi_idx == 0 or bi_idx == n_bars) else 0.024
				var bh := total_h - parapet_h + 0.04
				b.add_box(bp + Vector3(0.0, parapet_h + bh * 0.5 - 0.02, 0.0), Vector3(bw, bh, bw), mat_iron)
		# Solid 1.05m tall BoxShape3D fall-protection collider along entire edge
		InteriorMeshBatcher.add_box_collider(
			col_body, "%s_%sCol" % [prefix, tag],
			ctr + Vector3(0.0, total_h * 0.5, 0.0),
			Vector3(maxf(0.14, dx + 0.10), total_h, maxf(0.14, dz + 0.10))
		)


# ==============================================================================
# PARTITION WALLS WITH DOORWAYS, THRESHOLDS & FURNITURE HELPERS
# ==============================================================================
func _add_solid_wall_x(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, fy: float, h: float, z_pos: float, x0: float, x1: float, mat: Material) -> void:
	var w := absf(x1 - x0)
	var cx := (x0 + x1) * 0.5
	if b != null:
		b.add_box(Vector3(cx, fy + h * 0.5, z_pos), Vector3(w, h, 0.16), mat)
	InteriorMeshBatcher.add_box_collider(col_body, cname, Vector3(cx, fy + h * 0.5, z_pos), Vector3(w, h, 0.18))


func _add_solid_wall_z(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, fy: float, h: float, x_pos: float, z0: float, z1: float, mat: Material) -> void:
	var d := absf(z1 - z0)
	var cz := (z0 + z1) * 0.5
	if b != null:
		b.add_box(Vector3(x_pos, fy + h * 0.5, cz), Vector3(0.16, h, d), mat)
	InteriorMeshBatcher.add_box_collider(col_body, cname, Vector3(x_pos, fy + h * 0.5, cz), Vector3(0.18, h, d))


func _add_partition_with_door_x(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, fy: float, h: float, z_pos: float, x_min: float, x_max: float, door_x0: float, door_x1: float, mat_wall: Material, mat_frame: Material, mat_thresh: Material) -> void:
	var door_h := 2.25
	var lw := door_x0 - x_min
	var rw := x_max - door_x1
	var dw := door_x1 - door_x0
	var dcx := (door_x0 + door_x1) * 0.5
	if lw > 0.05:
		_add_solid_wall_x(b, col_body, cname + "_L", fy, h, z_pos, x_min, door_x0, mat_wall)
	if rw > 0.05:
		_add_solid_wall_x(b, col_body, cname + "_R", fy, h, z_pos, door_x1, x_max, mat_wall)
	if b != null:
		# Wall transom above doorway
		var top_h := maxf(0.2, h - door_h)
		b.add_box(Vector3(dcx, fy + door_h + top_h * 0.5, z_pos), Vector3(dw, top_h, 0.16), mat_wall)
		# Wooden door frame jambs + lintel + raised threshold (عتبة الباب)
		b.add_box(Vector3(door_x0 + 0.04, fy + door_h * 0.5, z_pos), Vector3(0.08, door_h, 0.22), mat_frame)
		b.add_box(Vector3(door_x1 - 0.04, fy + door_h * 0.5, z_pos), Vector3(0.08, door_h, 0.22), mat_frame)
		b.add_box(Vector3(dcx, fy + door_h - 0.04, z_pos), Vector3(dw, 0.08, 0.22), mat_frame)
		b.add_box(Vector3(dcx, fy + 0.016, z_pos), Vector3(dw, 0.032, 0.24), mat_thresh)


func _add_partition_with_door_z(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, fy: float, h: float, x_pos: float, z_min: float, z_max: float, door_z0: float, door_z1: float, mat_wall: Material, mat_frame: Material, mat_thresh: Material) -> void:
	var door_h := 2.25
	var lw := door_z0 - z_min
	var rw := z_max - door_z1
	var dw := door_z1 - door_z0
	var dcz := (door_z0 + door_z1) * 0.5
	if lw > 0.05:
		_add_solid_wall_z(b, col_body, cname + "_L", fy, h, x_pos, z_min, door_z0, mat_wall)
	if rw > 0.05:
		_add_solid_wall_z(b, col_body, cname + "_R", fy, h, x_pos, door_z1, z_max, mat_wall)
	if b != null:
		var top_h := maxf(0.2, h - door_h)
		b.add_box(Vector3(x_pos, fy + door_h + top_h * 0.5, dcz), Vector3(0.16, top_h, dw), mat_wall)
		b.add_box(Vector3(x_pos, fy + door_h * 0.5, door_z0 + 0.04), Vector3(0.22, door_h, 0.08), mat_frame)
		b.add_box(Vector3(x_pos, fy + door_h * 0.5, door_z1 - 0.04), Vector3(0.22, door_h, 0.08), mat_frame)
		b.add_box(Vector3(x_pos, fy + door_h - 0.04, dcz), Vector3(0.22, 0.08, dw), mat_frame)
		b.add_box(Vector3(x_pos, fy + 0.016, dcz), Vector3(0.24, 0.032, dw), mat_thresh)


func _add_apt_sofa(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3, w: float, rot_y: float, mat_wood: Material, mat_fab: Material) -> void:
	var d := 0.76
	var basis := Basis(Vector3.UP, rot_y)
	if b != null:
		b.add_box(pos + basis * Vector3(0.0, 0.22, 0.0), Vector3(w, 0.14, d), mat_wood, rot_y)
		b.add_box(pos + basis * Vector3(0.0, 0.36, 0.04), Vector3(w - 0.12, 0.16, d - 0.14), mat_fab, rot_y)
		b.add_box(pos + basis * Vector3(0.0, 0.62, -d * 0.5 + 0.10), Vector3(w - 0.08, 0.42, 0.16), mat_fab, rot_y)
	var sz := Vector3(w, 0.80, d) if absf(cos(rot_y)) > 0.5 else Vector3(d, 0.80, w)
	InteriorMeshBatcher.add_box_collider(col_body, cname, pos + Vector3(0.0, 0.40, 0.0), sz)


func _add_apt_table(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3, w: float, d: float, mat: Material) -> void:
	if b != null:
		b.add_box(pos + Vector3(0.0, 0.44, 0.0), Vector3(w, 0.06, d), mat)
		for sx: float in [-w * 0.42, w * 0.42]:
			for sz: float in [-d * 0.40, d * 0.40]:
				b.add_box(pos + Vector3(sx, 0.22, sz), Vector3(0.06, 0.44, 0.06), mat)
	InteriorMeshBatcher.add_box_collider(col_body, cname, pos + Vector3(0.0, 0.24, 0.0), Vector3(w, 0.48, d))


func _add_apt_bed(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3, rot_y: float, mat_wood: Material, mat_linen: Material, mat_blanket: Material) -> void:
	var basis := Basis(Vector3.UP, rot_y)
	if b != null:
		b.add_box(pos + basis * Vector3(0.0, 0.26, 0.0), Vector3(1.52, 0.16, 2.02), mat_wood, rot_y)
		b.add_box(pos + basis * Vector3(0.0, 0.56, -0.98), Vector3(1.54, 0.86, 0.08), mat_wood, rot_y)
		b.add_box(pos + basis * Vector3(0.0, 0.42, 0.0), Vector3(1.44, 0.18, 1.92), mat_linen, rot_y)
		b.add_box(pos + basis * Vector3(0.0, 0.46, 0.36), Vector3(1.46, 0.15, 1.15), mat_blanket, rot_y)
		b.add_box(pos + basis * Vector3(-0.36, 0.56, -0.68), Vector3(0.52, 0.12, 0.34), mat_linen, rot_y)
		b.add_box(pos + basis * Vector3(0.36, 0.56, -0.68), Vector3(0.52, 0.12, 0.34), mat_linen, rot_y)
	var sz := Vector3(1.56, 0.65, 2.06) if absf(cos(rot_y)) > 0.5 else Vector3(2.06, 0.65, 1.56)
	InteriorMeshBatcher.add_box_collider(col_body, cname, pos + Vector3(0.0, 0.32, 0.0), sz)


func _add_apt_wardrobe(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3, rot_y: float, mat_dk: Material, mat_lt: Material) -> void:
	if b != null:
		b.add_box(pos + Vector3(0.0, 1.0, 0.0), Vector3(1.40, 2.0, 0.58), mat_dk, rot_y)
		b.add_box(pos + Basis(Vector3.UP, rot_y) * Vector3(0.0, 1.0, 0.30), Vector3(1.30, 1.84, 0.02), mat_lt, rot_y)
	var sz := Vector3(1.42, 2.0, 0.60) if absf(cos(rot_y)) > 0.5 else Vector3(0.60, 2.0, 1.42)
	InteriorMeshBatcher.add_box_collider(col_body, cname, pos + Vector3(0.0, 1.0, 0.0), sz)


func _add_apt_kitchen(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3, w: float, mat_cab: Material, mat_top: Material, mat_white: Material, mat_steel: Material) -> void:
	if b != null:
		# Lower kitchen cabinets + stone countertop + sink + stove burners
		b.add_box(pos + Vector3(0.0, 0.44, 0.0), Vector3(w, 0.88, 0.62), mat_cab)
		b.add_box(pos + Vector3(0.0, 0.90, 0.0), Vector3(w + 0.04, 0.06, 0.66), mat_top)
		b.add_box(pos + Vector3(-0.65, 0.935, 0.0), Vector3(0.56, 0.02, 0.42), mat_steel) # Sink basin
		b.add_box(pos + Vector3(0.55, 0.94, 0.0), Vector3(0.62, 0.04, 0.48), mat_white)   # Stove top
		# Overhead wall cabinets
		b.add_box(pos + Vector3(0.0, 2.02, -0.10), Vector3(w - 0.2, 0.68, 0.38), mat_cab)
		# Tall refrigerator beside counter
		b.add_box(pos + Vector3(-w * 0.5 - 0.42, 0.92, 0.04), Vector3(0.72, 1.84, 0.70), mat_white)
	InteriorMeshBatcher.add_box_collider(col_body, cname + "_Cnt", pos + Vector3(0.0, 0.46, 0.0), Vector3(w, 0.92, 0.66))
	InteriorMeshBatcher.add_box_collider(col_body, cname + "_Fridge", pos + Vector3(-w * 0.5 - 0.42, 0.92, 0.04), Vector3(0.74, 1.84, 0.72))


func _add_apt_bathroom(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3, mat_tile: Material, mat_white: Material, mat_steel: Material) -> void:
	if b != null:
		# Tiled bathroom floor mat
		b.add_box(pos + Vector3(0.95, 0.012, 0.0), Vector3(4.1, 0.02, 1.5), mat_tile)
		# Vanity sink & mirror
		b.add_box(pos + Vector3(-0.45, 0.42, -0.52), Vector3(0.78, 0.84, 0.46), mat_white)
		b.add_box(pos + Vector3(-0.45, 1.38, -0.74), Vector3(0.68, 0.78, 0.04), mat_steel)
		# Toilet
		b.add_box(pos + Vector3(0.55, 0.24, -0.52), Vector3(0.42, 0.48, 0.54), mat_white)
		b.add_box(pos + Vector3(0.55, 0.62, -0.68), Vector3(0.42, 0.42, 0.20), mat_white)
		# Shower tray & chrome rail
		b.add_box(pos + Vector3(-0.95, 0.06, 0.35), Vector3(0.92, 0.12, 0.85), mat_white)
		b.add_cylinder(pos + Vector3(-1.05, 1.45, 0.35), 0.02, 0.02, 1.2, mat_steel, 6)
	InteriorMeshBatcher.add_box_collider(col_body, cname + "_Vanity", pos + Vector3(-0.45, 0.42, -0.52), Vector3(0.80, 0.84, 0.48))
