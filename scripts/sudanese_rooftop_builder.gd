extends Node3D
class_name SudaneseRooftopBuilder

## High-FPS Khartoum Rooftop & Water Tank Assembly Builder for Godot 4.7.2.
##
## Features:
## - 1.05m-tall perimeter parapet wall (سترة السطح) with matching StaticBody3D safety collision
## - Automatic clean doorway/walkway opening (>= 1.35m) at the exterior stair top landing with low threshold
## - Optional framed roof-access penthouse (بيت الدرج) with working InteractiveDoor (defaults open for smooth walk-through)
## - Detailed Sudanese poly water tank assemblies: 0.45m 4-legged painted steel stand with cross-braces,
##   ribbed/corrugated cylindrical poly tank (Sudan blue / white / black), molded screw-lid, overflow vent & PVC supply pipes
## - Protruding rainwater spouts (مزاريب المياه), angled white satellite dishes on poles, outdoor AC compressor units,
##   wooden clothesline poles with strung lines, and traditional wooden rope Angareeb (عنقريب)
## - All static geometry merged into cached multi-surface ArrayMeshes (props visibility_range_end = 110.0).

enum RoofPreset {
	SUDANESE_HOUSE = 0,
	CLOSED_HOUSE = 1,
	APARTMENT_BUILDING = 2,
}

@export var roof_preset: RoofPreset = RoofPreset.SUDANESE_HOUSE
@export var roof_width: float = 10.4
@export var roof_depth: float = 8.4
@export var roof_y: float = 3.80
@export var roof_center: Vector3 = Vector3(0.0, 0.0, -4.0)
@export var parapet_height: float = 1.05
@export var has_stair_entry: bool = true
@export var entry_gap_z: float = -6.825
@export var entry_gap_width: float = 1.40
@export var has_penthouse_hood: bool = false
@export var wall_tint: Color = Color(0.95, 0.87, 0.73)
@export var vis_range_props: float = 110.0
@export var vis_range_structure: float = 240.0

static var _struct_cache: Dictionary = {}
static var _props_cache: Dictionary = {}
var _built: bool = false


func _ready() -> void:
	add_to_group("sudanese_rooftops")
	build_rooftop()


func build_rooftop() -> void:
	if _built:
		return
	_built = true

	var col_body := StaticBody3D.new()
	col_body.name = "RooftopCollision"
	col_body.add_to_group("rooftop_parapets")
	add_child(col_body)

	var cache_key := "rf_%d_%.2f_%.2f_%.2f_%.2f_%s_%.2f_%.2f_%s_%s" % [
		int(roof_preset), roof_width, roof_depth, roof_y, parapet_height,
		str(has_stair_entry), entry_gap_z, entry_gap_width, str(has_penthouse_hood),
		wall_tint.to_html(false)
	]

	var cached_s := _struct_cache.get(cache_key) as ArrayMesh
	var cached_p := _props_cache.get(cache_key) as ArrayMesh
	var bs: InteriorMeshBatcher = null if cached_s != null else InteriorMeshBatcher.new()
	var bp: InteriorMeshBatcher = null if cached_p != null else InteriorMeshBatcher.new()

	var mat_wall := InteriorMeshBatcher.get_pbr_mat(
		"rf_wall_" + wall_tint.to_html(false),
		"res://assets/textures/plaster",
		wall_tint,
		0.88,
		Vector3(0.45, 0.45, 0.45)
	)
	var mat_coping := InteriorMeshBatcher.get_color_mat("rf_coping", Color(0.76, 0.72, 0.65), 0.85)
	var mat_thresh := InteriorMeshBatcher.get_color_mat("rf_thresh", Color(0.68, 0.65, 0.60), 0.72)

	# ------------------------------------------------------------------
	# 1. PERIMETER 1.05m PARAPET WALLS (سترة السطح) + CLEAN STAIR ENTRYWAY
	# ------------------------------------------------------------------
	var hw := roof_width * 0.5
	var hd := roof_depth * 0.5
	var cx := roof_center.x
	var cz := roof_center.z
	var pt := 0.24
	var ph := parapet_height
	var x_w := cx - hw + pt * 0.5
	var x_e := cx + hw - pt * 0.5
	var z_n := cz - hd + pt * 0.5
	var z_s := cz + hd - pt * 0.5

	# North, South, West full parapets
	_add_parapet_seg(bs, col_body, "ParapetN", Vector3(cx, roof_y, z_n), Vector3(roof_width, ph, pt), mat_wall, mat_coping)
	_add_parapet_seg(bs, col_body, "ParapetS", Vector3(cx, roof_y, z_s), Vector3(roof_width, ph, pt), mat_wall, mat_coping)
	_add_parapet_seg(bs, col_body, "ParapetW", Vector3(x_w, roof_y, cz), Vector3(pt, ph, roof_depth - pt * 2.0), mat_wall, mat_coping)

	# East parapet (+X): automatically cut clean >=1.35m doorway gap at exterior stair top landing
	var z_min := cz - hd + pt
	var z_max := cz + hd - pt
	if has_stair_entry:
		var g_half := maxf(0.68, entry_gap_width * 0.5)
		var g_lo := clampf(entry_gap_z - g_half, z_min + 0.15, z_max - 1.35)
		var g_hi := clampf(entry_gap_z + g_half, g_lo + 1.30, z_max - 0.15)

		if g_lo - z_min > 0.10:
			var len_n := g_lo - z_min
			_add_parapet_seg(bs, col_body, "ParapetE_N", Vector3(x_e, roof_y, (z_min + g_lo) * 0.5), Vector3(pt, ph, len_n), mat_wall, mat_coping)
		if z_max - g_hi > 0.10:
			var len_s := z_max - g_hi
			_add_parapet_seg(bs, col_body, "ParapetE_S", Vector3(x_e, roof_y, (g_hi + z_max) * 0.5), Vector3(pt, ph, len_s), mat_wall, mat_coping)

		# Low beveled concrete threshold across the stair entry gap (walk straight over, no jumping!)
		if bs != null:
			bs.add_box(Vector3(x_e, roof_y + 0.015, (g_lo + g_hi) * 0.5), Vector3(pt + 0.10, 0.030, g_hi - g_lo), mat_thresh)

		# Optional Framed Roof-Access Penthouse Hood (بيت الدرج) with working InteractiveDoor (starts open!)
		if has_penthouse_hood:
			_add_penthouse_entry_hood(bs, col_body, x_e, roof_y, (g_lo + g_hi) * 0.5, g_hi - g_lo, mat_wall, mat_coping)
	else:
		_add_parapet_seg(bs, col_body, "ParapetE", Vector3(x_e, roof_y, cz), Vector3(pt, ph, roof_depth - pt * 2.0), mat_wall, mat_coping)

	# ------------------------------------------------------------------
	# 2. RAINWATER SPOUTS (مزاريب المياه) ALONG OUTER PARAPET EDGES
	# ------------------------------------------------------------------
	if bp != null:
		var mat_pvc := InteriorMeshBatcher.get_color_mat("rf_pvc", Color(0.76, 0.78, 0.80), 0.42, 0.10)
		var spout_z_offsets: Array[float] = [-hd * 0.55, hd * 0.55]
		for sz_off in spout_z_offsets:
			# West edge spouts pointing -X
			_add_rainwater_spout(bp, Vector3(cx - hw, roof_y + 0.14, cz + sz_off), -1.0, 0.0, mat_pvc)
			# East edge spouts pointing +X (skip if near stair gap)
			if not has_stair_entry or absf((cz + sz_off) - entry_gap_z) > 1.6:
				_add_rainwater_spout(bp, Vector3(cx + hw, roof_y + 0.14, cz + sz_off), 1.0, 0.0, mat_pvc)
		var spout_x_offsets: Array[float] = [-hw * 0.52, hw * 0.52]
		for sx_off in spout_x_offsets:
			_add_rainwater_spout(bp, Vector3(cx + sx_off, roof_y + 0.14, cz - hd), 0.0, -1.0, mat_pvc)
			_add_rainwater_spout(bp, Vector3(cx + sx_off, roof_y + 0.14, cz + hd), 0.0, 1.0, mat_pvc)

	# ------------------------------------------------------------------
	# 3. PRESET-SPECIFIC ROOFTOP WATER TANKS, PENTHOUSE & KHARTOUM PROPS
	# ------------------------------------------------------------------
	match roof_preset:
		RoofPreset.SUDANESE_HOUSE:
			# Primary Sudan-Blue ribbed poly water tank on 0.45m 4-legged painted steel stand
			_add_water_tank_assembly(bp, col_body, "HouseWaterTank", Vector3(cx - 3.1, roof_y, cz - 2.0), 0.68, 1.32, 0)
			# Angled white satellite dish on bolted steel pole (South-East corner, clear of North-East stair entry!)
			_add_satellite_dish(bp, col_body, "HouseSatDish", Vector3(cx + 3.6, roof_y, cz + 2.6), -0.65)
			# Wooden clothesline poles with strung lines & hanging laundry
			_add_clothesline(bp, col_body, "HouseClothesline", Vector3(cx - 2.6, roof_y, cz + 2.2), Vector3(cx + 1.8, roof_y, cz + 2.2))
			# Traditional wooden rope Angareeb (عنقريب) for cool Khartoum evening rooftop seating!
			_add_rooftop_angareeb(bp, col_body, "HouseRoofAngareeb", Vector3(cx + 0.4, roof_y, cz - 1.6), 0.0)
			# Outdoor AC compressor unit tucked near South parapet
			_add_ac_compressor(bp, col_body, "HouseACUnit", Vector3(cx - 3.8, roof_y, cz + 3.1), 0.0)

		RoofPreset.CLOSED_HOUSE:
			# White ribbed poly water tank on 0.45m steel stand
			_add_water_tank_assembly(bp, col_body, "ClosedWaterTank", Vector3(cx - 3.2, roof_y, cz - 1.6), 0.64, 1.25, 1)
			# Satellite dish on pole + clothesline + evening Angareeb
			_add_satellite_dish(bp, col_body, "ClosedSatDish", Vector3(cx + 3.1, roof_y, cz - 1.8), -0.50)
			_add_clothesline(bp, col_body, "ClosedClothesline", Vector3(cx - 2.2, roof_y, cz + 2.1), Vector3(cx + 2.4, roof_y, cz + 2.1))
			_add_rooftop_angareeb(bp, col_body, "ClosedAngareeb", Vector3(cx + 0.6, roof_y, cz - 1.4), PI * 0.5)

		RoofPreset.APARTMENT_BUILDING:
			# RoofTankTop on top of existing PenthouseTower (pos=(1.2, 11.6, -1.8), size=(3.8, 2.4, 3.6) -> top y=12.80)
			_add_water_tank_assembly(bp, col_body, "AptTankTop", Vector3(1.2, 12.80, -1.8), 0.72, 1.38, 0)
			# Row of 3 apartment poly water tanks (Sudan Blue, Clean White, UV Black) on 0.45m steel stands
			_add_water_tank_assembly(bp, col_body, "AptTankBlue", Vector3(-6.2, roof_y, -2.6), 0.68, 1.32, 0)
			_add_water_tank_assembly(bp, col_body, "AptTankWhite", Vector3(-3.8, roof_y, -2.6), 0.64, 1.28, 1)
			_add_water_tank_assembly(bp, col_body, "AptTankBlack", Vector3(5.4, roof_y, -2.8), 0.66, 1.30, 2)
			# 3 angled white satellite dishes on steel mast poles
			_add_satellite_dish(bp, col_body, "AptDish_1", Vector3(-5.8, roof_y, 3.2), -0.45)
			_add_satellite_dish(bp, col_body, "AptDish_2", Vector3(-2.6, roof_y, 3.4), -0.75)
			_add_satellite_dish(bp, col_body, "AptDish_3", Vector3(4.8, roof_y, 3.3), -0.55)
			# Outdoor rooftop AC compressor units near the central penthouse & South parapet
			_add_ac_compressor(bp, col_body, "AptAC_1", Vector3(-0.95, roof_y, -2.2), -PI * 0.5)
			_add_ac_compressor(bp, col_body, "AptAC_2", Vector3(-0.95, roof_y, -0.9), -PI * 0.5)
			_add_ac_compressor(bp, col_body, "AptAC_3", Vector3(3.35, roof_y, -2.2), PI * 0.5)
			# Wooden clothesline poles & strung lines on the open West roof zone
			_add_clothesline(bp, col_body, "AptClothesline", Vector3(-7.4, roof_y, 0.2), Vector3(-2.4, roof_y, 0.2))
			# Traditional evening Angareeb on the quiet South-East roof corner
			_add_rooftop_angareeb(bp, col_body, "AptAngareeb", Vector3(2.2, roof_y, 2.8), 0.0)

	# ------------------------------------------------------------------
	# 4. COMMIT MERGED STATIC-CACHED ARRAYMESHES
	# ------------------------------------------------------------------
	var s_mesh: ArrayMesh
	if cached_s != null:
		s_mesh = cached_s
	else:
		s_mesh = bs.commit()
		_struct_cache[cache_key] = s_mesh

	var mi_s := MeshInstance3D.new()
	mi_s.name = "MergedRoofStructure"
	mi_s.mesh = s_mesh
	mi_s.visibility_range_end = vis_range_structure
	mi_s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi_s)

	var p_mesh: ArrayMesh
	if cached_p != null:
		p_mesh = cached_p
	else:
		p_mesh = bp.commit()
		_props_cache[cache_key] = p_mesh

	var mi_p := MeshInstance3D.new()
	mi_p.name = "MergedRoofProps"
	mi_p.mesh = p_mesh
	mi_p.visibility_range_end = vis_range_props
	mi_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi_p)


# ==============================================================================
# PARAPET & ROOF-ACCESS PENTHOUSE HOOD (بيت الدرج)
# ==============================================================================
func _add_parapet_seg(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, base_ctr: Vector3, size: Vector3, mat_wall: Material, mat_coping: Material) -> void:
	var ctr := base_ctr + Vector3(0.0, size.y * 0.5, 0.0)
	if b != null:
		b.add_box(ctr, size, mat_wall)
		# Overhanging concrete coping cap along top of parapet
		b.add_box(base_ctr + Vector3(0.0, size.y + 0.03, 0.0), Vector3(size.x + 0.06, 0.06, size.z + 0.06), mat_coping)
	InteriorMeshBatcher.add_box_collider(col_body, cname + "_Col", ctr, Vector3(size.x, size.y + 0.06, size.z))


func _add_penthouse_entry_hood(b: InteriorMeshBatcher, col_body: StaticBody3D, x_parapet: float, ry: float, z_ctr: float, gap_w: float, mat_wall: Material, mat_coping: Material) -> void:
	# Framed walk-through roof-access penthouse archway (بيت الدرج) protruding 1.25m inward onto the roof
	# Completely hollow inside (z in [z_ctr - gap_w/2, z_ctr + gap_w/2]) so climbing stairs walks straight onto roof!
	var hood_d := 1.25
	var hood_h := 2.55
	var wall_t := 0.22
	var x_ctr := x_parapet - hood_d * 0.5
	var z_n := z_ctr - gap_w * 0.5 - wall_t * 0.5
	var z_s := z_ctr + gap_w * 0.5 + wall_t * 0.5
	var total_z := gap_w + wall_t * 2.0

	if b != null:
		# North & South flanking penthouse walls
		b.add_box(Vector3(x_ctr, ry + hood_h * 0.5, z_n), Vector3(hood_d, hood_h, wall_t), mat_wall)
		b.add_box(Vector3(x_ctr, ry + hood_h * 0.5, z_s), Vector3(hood_d, hood_h, wall_t), mat_wall)
		# Transom wall above doorway on East side (above 2.20m)
		var transom_h := hood_h - 2.20
		b.add_box(Vector3(x_parapet, ry + 2.20 + transom_h * 0.5, z_ctr), Vector3(0.24, transom_h, gap_w), mat_wall)
		# Concrete roof canopy slab + coping trim
		b.add_box(Vector3(x_ctr, ry + hood_h + 0.10, z_ctr), Vector3(hood_d + 0.30, 0.20, total_z + 0.26), mat_coping)
	InteriorMeshBatcher.add_box_collider(col_body, "PenthouseHood_N", Vector3(x_ctr, ry + hood_h * 0.5, z_n), Vector3(hood_d, hood_h, wall_t))
	InteriorMeshBatcher.add_box_collider(col_body, "PenthouseHood_S", Vector3(x_ctr, ry + hood_h * 0.5, z_s), Vector3(hood_d, hood_h, wall_t))

	# Working InteractiveDoor (starts OPEN so player & NPCs walk straight onto roof, can close/lock with [E]/[K]!)
	var door := InteractiveDoor.new()
	door.name = "RoofAccessDoor"
	door.door_label = "باب بيت الدرج (السطح)"
	door.door_style = InteractiveDoor.DoorStyle.WOOD_SINGLE_DOOR
	door.opening_width = minf(1.36, gap_w - 0.04)
	door.opening_height = 2.18
	door.wall_thickness = 0.24
	door.open_angle_deg = 86.0
	door.is_open = true
	door.build_recessed_frame = true
	door.vis_range_end = 95.0
	# Rotate +90 deg around Y so local -Z (inward swing) points -X into the roof penthouse!
	door.position = Vector3(x_parapet, ry, z_ctr)
	door.rotation.y = PI * 0.5
	add_child(door)


# ==============================================================================
# DETAILED SUDANESE ROOFTOP WATER TANK ASSEMBLY (STAND + RIBBED TANK + PIPES)
# ==============================================================================
static func add_water_tank_to_batcher(b: InteriorMeshBatcher, base_pos: Vector3, radius: float, height: float, color_idx: int) -> void:
	if b == null:
		return
	var stand_h := 0.45
	var mat_steel := InteriorMeshBatcher.get_color_mat("rf_tank_steel", Color(0.20, 0.24, 0.28), 0.44, 0.68)
	var mat_pvc := InteriorMeshBatcher.get_color_mat("rf_pvc", Color(0.76, 0.78, 0.80), 0.42, 0.10)
	var mat_lid := InteriorMeshBatcher.get_color_mat("rf_tank_lid", Color(0.14, 0.16, 0.18), 0.50, 0.08)
	var mat_valve := InteriorMeshBatcher.get_color_mat("rf_valve_red", Color(0.78, 0.16, 0.14), 0.40, 0.35)

	var tank_cols: Array[Color] = [
		Color(0.08, 0.39, 0.72), # Realistic Sudan Blue poly-tank
		Color(0.90, 0.92, 0.93), # Sun-reflective White poly-tank
		Color(0.14, 0.16, 0.18), # UV-resistant Black poly-tank
	]
	var c_idx := posmod(color_idx, tank_cols.size())
	var mat_tank := InteriorMeshBatcher.get_color_mat("rf_tank_body_%d" % c_idx, tank_cols[c_idx], 0.38, 0.06)
	var mat_rib := InteriorMeshBatcher.get_color_mat("rf_tank_rib_%d" % c_idx, tank_cols[c_idx].darkened(0.12), 0.42, 0.06)

	# 1. Painted Steel Support Stand (4 legs + lower & upper perimeter tie-beams + crossbars)
	var leg_off := radius * 0.82
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.add_box(base_pos + Vector3(sx * leg_off, stand_h * 0.5, sz * leg_off), Vector3(0.065, stand_h, 0.065), mat_steel)
			b.add_box(base_pos + Vector3(sx * leg_off, 0.02, sz * leg_off), Vector3(0.14, 0.04, 0.14), mat_steel)
	# Perimeter tie-beams at y=0.16 and top support frame at y=0.43
	var span := leg_off * 2.0 + 0.065
	for ty: float in [0.16, stand_h - 0.025]:
		b.add_box(base_pos + Vector3(0.0, ty, -leg_off), Vector3(span, 0.045, 0.045), mat_steel)
		b.add_box(base_pos + Vector3(0.0, ty, leg_off), Vector3(span, 0.045, 0.045), mat_steel)
		b.add_box(base_pos + Vector3(-leg_off, ty, 0.0), Vector3(0.045, 0.045, span), mat_steel)
		b.add_box(base_pos + Vector3(leg_off, ty, 0.0), Vector3(0.045, 0.045, span), mat_steel)
	# Slatted steel deck beams under tank bottom
	for bx in [-leg_off * 0.45, 0.0, leg_off * 0.45]:
		b.add_box(base_pos + Vector3(bx, stand_h - 0.02, 0.0), Vector3(0.05, 0.04, span), mat_steel)

	# 2. Ribbed / Corrugated Cylindrical Poly-Tank Body + Tapered Shoulder
	var tank_base_y := base_pos.y + stand_h
	var body_h := height * 0.84
	b.add_cylinder(Vector3(base_pos.x, tank_base_y + body_h * 0.5, base_pos.z), radius, radius, body_h, mat_tank, 14)
	# 5 raised horizontal stiffening rib rings around cylinder
	for ri in range(5):
		var ry := tank_base_y + 0.14 + float(ri) * ((body_h - 0.24) / 4.0)
		b.add_cylinder(Vector3(base_pos.x, ry, base_pos.z), radius + 0.032, radius + 0.032, 0.055, mat_rib, 14)
	# Domed upper shoulder
	var sh_h := height * 0.16
	b.add_cylinder(Vector3(base_pos.x, tank_base_y + body_h + sh_h * 0.5, base_pos.z), radius * 0.72, radius, sh_h, mat_tank, 14)

	# 3. Molded Top Screw-Lid (غطاء علوي)
	var top_y := tank_base_y + height
	b.add_cylinder(Vector3(base_pos.x, top_y + 0.045, base_pos.z), 0.22, 0.24, 0.09, mat_rib, 10)
	b.add_cylinder(Vector3(base_pos.x, top_y + 0.105, base_pos.z), 0.24, 0.24, 0.045, mat_lid, 10)

	# 4. PVC Supply Pipe running down into roof slab + red shutoff valve + top overflow vent pipe
	var pipe_x := base_pos.x + radius + 0.12
	var pipe_z := base_pos.z
	# Horizontal outlet from tank lower sidewall to vertical riser
	b.add_cylinder(Vector3(base_pos.x + radius + 0.05, tank_base_y + 0.12, pipe_z), 0.028, 0.028, 0.16, mat_pvc, 6, 0.0, PI * 0.5)
	# Vertical PVC drop pipe straight into roof slab
	var drop_h := stand_h + 0.14
	b.add_cylinder(Vector3(pipe_x, base_pos.y + drop_h * 0.5, pipe_z), 0.028, 0.028, drop_h, mat_pvc, 6)
	# Roof slab flange collar & shutoff valve handle
	b.add_cylinder(Vector3(pipe_x, base_pos.y + 0.025, pipe_z), 0.06, 0.07, 0.05, mat_pvc, 6)
	b.add_box(Vector3(pipe_x + 0.05, tank_base_y + 0.12, pipe_z), Vector3(0.10, 0.025, 0.025), mat_valve)
	# Upper overflow vent pipe (J-hook breather at shoulder)
	var ov_x := base_pos.x - radius - 0.08
	var ov_y := tank_base_y + body_h - 0.06
	b.add_cylinder(Vector3(base_pos.x - radius - 0.03, ov_y, pipe_z), 0.020, 0.020, 0.14, mat_pvc, 6, 0.0, PI * 0.5)
	b.add_cylinder(Vector3(ov_x, ov_y - 0.09, pipe_z), 0.020, 0.020, 0.18, mat_pvc, 6)


func _add_water_tank_assembly(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, base_pos: Vector3, radius: float, height: float, color_idx: int) -> void:
	add_water_tank_to_batcher(b, base_pos, radius, height, color_idx)
	InteriorMeshBatcher.add_box_collider(col_body, cname + "_Col", base_pos + Vector3(0.0, (0.45 + height) * 0.5, 0.0), Vector3(radius * 2.1, 0.45 + height, radius * 2.1))


# ==============================================================================
# AUTHENTIC KHARTOUM ROOFTOP PROPS: SPOUTS, DISHES, AC UNITS, CLOTHESLINE, ANGAREEB
# ==============================================================================
func _add_rainwater_spout(b: InteriorMeshBatcher, wall_pos: Vector3, dir_x: float, dir_z: float, mat_pvc: Material) -> void:
	var spout_len := 0.46
	var p0 := wall_pos + Vector3(dir_x * -0.05, 0.04, dir_z * -0.05)
	var p1 := wall_pos + Vector3(dir_x * spout_len, -0.06, dir_z * spout_len)
	b.add_bar(p0, p1, 0.075, 0.075, mat_pvc)
	# Exterior wall collar flange
	b.add_box(wall_pos + Vector3(dir_x * 0.02, 0.02, dir_z * 0.02), Vector3(0.14, 0.14, 0.14), mat_pvc)


func _add_satellite_dish(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3, yaw: float) -> void:
	if b != null:
		var mat_pole := InteriorMeshBatcher.get_color_mat("rf_dish_pole", Color(0.28, 0.30, 0.34), 0.45, 0.65)
		var mat_dish := InteriorMeshBatcher.get_color_mat("rf_dish_white", Color(0.92, 0.93, 0.94), 0.36, 0.12)
		var mat_lnb := InteriorMeshBatcher.get_color_mat("rf_dish_lnb", Color(0.16, 0.18, 0.20), 0.45, 0.35)
		# Concrete base + vertical mast pole
		b.add_box(pos + Vector3(0.0, 0.06, 0.0), Vector3(0.32, 0.12, 0.32), mat_pole)
		b.add_cylinder(pos + Vector3(0.0, 0.52, 0.0), 0.032, 0.036, 0.92, mat_pole, 6)
		# Tilted white parabolic reflector dish + offset LNB feed arm
		var dish_c := pos + Vector3(0.0, 1.02, 0.0)
		var fwd := Vector3(sin(yaw), 0.58, cos(yaw)).normalized()
		b.add_sphere(dish_c, 0.48, mat_dish, Vector3(1.0, 0.28, 1.0), 10, 5)
		b.add_bar(dish_c, dish_c + fwd * 0.56, 0.026, 0.026, mat_pole)
		b.add_sphere(dish_c + fwd * 0.58, 0.055, mat_lnb, Vector3.ONE, 6, 4)
	InteriorMeshBatcher.add_box_collider(col_body, cname + "_Col", pos + Vector3(0.0, 0.65, 0.0), Vector3(0.65, 1.30, 0.65))


func _add_ac_compressor(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3, rot_y: float) -> void:
	if b != null:
		var mat_case := InteriorMeshBatcher.get_color_mat("rf_ac_case", Color(0.86, 0.85, 0.81), 0.48, 0.18)
		var mat_grill := InteriorMeshBatcher.get_color_mat("rf_ac_grill", Color(0.14, 0.16, 0.18), 0.60, 0.35)
		var mat_steel := InteriorMeshBatcher.get_color_mat("rf_tank_steel", Color(0.20, 0.24, 0.28), 0.44, 0.68)
		var basis := Basis(Vector3.UP, rot_y)
		# Steel mounting feet
		for sx: float in [-0.34, 0.34]:
			b.add_box(pos + basis * Vector3(sx, 0.06, 0.0), Vector3(0.08, 0.12, 0.42), mat_steel, rot_y)
		# Main compressor housing + circular fan grille
		b.add_box(pos + basis * Vector3(0.0, 0.42, 0.0), Vector3(0.88, 0.62, 0.36), mat_case, rot_y)
		b.add_box(pos + basis * Vector3(-0.14, 0.42, 0.185), Vector3(0.44, 0.44, 0.025), mat_grill, rot_y)
		b.add_box(pos + basis * Vector3(0.28, 0.42, 0.185), Vector3(0.18, 0.44, 0.02), mat_steel, rot_y)
	var sz := Vector3(0.92, 0.78, 0.44) if absf(cos(rot_y)) > 0.5 else Vector3(0.44, 0.78, 0.92)
	InteriorMeshBatcher.add_box_collider(col_body, cname + "_Col", pos + Vector3(0.0, 0.39, 0.0), sz)


func _add_clothesline(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, p0: Vector3, p1: Vector3) -> void:
	var h := 1.85
	if b != null:
		var mat_wood := InteriorMeshBatcher.get_pbr_mat("rf_cl_wood", "res://assets/textures/wood", Color(0.56, 0.38, 0.22), 0.80, Vector3(1.0, 1.0, 1.0))
		var mat_line := InteriorMeshBatcher.get_color_mat("rf_cl_line", Color(0.86, 0.84, 0.78), 0.75)
		var mat_conc := InteriorMeshBatcher.get_color_mat("rf_coping", Color(0.76, 0.72, 0.65), 0.85)
		var cloth_mats: Array[StandardMaterial3D] = [
			InteriorMeshBatcher.get_color_mat("rf_cloth_w", Color(0.95, 0.94, 0.90), 0.90),
			InteriorMeshBatcher.get_color_mat("rf_cloth_b", Color(0.22, 0.48, 0.74), 0.90),
			InteriorMeshBatcher.get_color_mat("rf_cloth_g", Color(0.82, 0.28, 0.24), 0.90),
		]
		var perp := Vector3.UP.cross((p1 - p0).normalized()).normalized()
		for pt in [p0, p1]:
			b.add_box(pt + Vector3(0.0, 0.10, 0.0), Vector3(0.26, 0.20, 0.26), mat_conc)
			b.add_box(pt + Vector3(0.0, h * 0.5, 0.0), Vector3(0.075, h, 0.075), mat_wood)
			# T-crossbar at top
			b.add_bar(pt + Vector3(0.0, h - 0.05, 0.0) - perp * 0.35, pt + Vector3(0.0, h - 0.05, 0.0) + perp * 0.35, 0.06, 0.06, mat_wood)
		# Two parallel strung lines
		for side: float in [-0.28, 0.28]:
			b.add_bar(p0 + Vector3(0.0, h - 0.04, 0.0) + perp * side, p1 + Vector3(0.0, h - 0.04, 0.0) + perp * side, 0.014, 0.014, mat_line)
		# 3 folded hanging laundry cloths along one line
		for ci in range(3):
			var t := 0.24 + float(ci) * 0.26
			var cp := p0.lerp(p1, t) + perp * 0.28 + Vector3(0.0, h - 0.42, 0.0)
			var rot_y := atan2(p1.x - p0.x, p1.z - p0.z)
			b.add_box(cp, Vector3(0.05, 0.72, 0.58), cloth_mats[ci % cloth_mats.size()], rot_y)
	InteriorMeshBatcher.add_box_collider(col_body, cname + "_P0", p0 + Vector3(0.0, h * 0.5, 0.0), Vector3(0.24, h, 0.24))
	InteriorMeshBatcher.add_box_collider(col_body, cname + "_P1", p1 + Vector3(0.0, h * 0.5, 0.0), Vector3(0.24, h, 0.24))


func _add_rooftop_angareeb(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3, rot_y: float) -> void:
	var basis := Basis(Vector3.UP, rot_y)
	if b != null:
		var mat_wood := InteriorMeshBatcher.get_pbr_mat("rf_ang_wood", "res://assets/textures/wood", Color(0.50, 0.30, 0.16), 0.75, Vector3(1.0, 1.0, 1.0))
		var mat_rope := InteriorMeshBatcher.get_color_mat("rf_ang_rope", Color(0.84, 0.76, 0.58), 0.94)
		var mat_pillow := InteriorMeshBatcher.get_color_mat("rf_ang_pil", Color(0.76, 0.24, 0.18), 0.88)
		# 4 wooden legs + side frame rails
		for lx: float in [-0.90, 0.90]:
			for lz: float in [-0.46, 0.46]:
				b.add_cylinder(pos + basis * Vector3(lx, 0.22, lz), 0.036, 0.030, 0.44, mat_wood, 6)
		b.add_box(pos + basis * Vector3(0.0, 0.40, -0.46), Vector3(1.86, 0.08, 0.06), mat_wood, rot_y)
		b.add_box(pos + basis * Vector3(0.0, 0.40, 0.46), Vector3(1.86, 0.08, 0.06), mat_wood, rot_y)
		b.add_box(pos + basis * Vector3(-0.90, 0.40, 0.0), Vector3(0.06, 0.08, 0.96), mat_wood, rot_y)
		b.add_box(pos + basis * Vector3(0.90, 0.40, 0.0), Vector3(0.06, 0.08, 0.96), mat_wood, rot_y)
		# Woven rope sleeping deck + evening pillow
		b.add_box(pos + basis * Vector3(0.0, 0.42, 0.0), Vector3(1.74, 0.045, 0.86), mat_rope, rot_y)
		b.add_box(pos + basis * Vector3(-0.68, 0.50, 0.0), Vector3(0.32, 0.13, 0.62), mat_pillow, rot_y)
	var sz := Vector3(1.92, 0.56, 1.02) if absf(cos(rot_y)) > 0.5 else Vector3(1.02, 0.56, 1.92)
	InteriorMeshBatcher.add_box_collider(col_body, cname + "_Col", pos + Vector3(0.0, 0.28, 0.0), sz)
