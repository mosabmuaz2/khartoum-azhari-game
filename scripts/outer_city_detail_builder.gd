extends RefCounted
class_name OuterCityDetailBuilder

## High-FPS Outer & Southern Neighborhood Architectural Detail & Street-Life Builder for Godot 4.7.2.
##
## 1. Upgrades every procedural city building (Styles 0..5) so ZERO buildings are plain windowless/doorless boxes:
##    - Framed enterable Sudanese doors (InteractiveDoor) on every house, villa, shop, and tower
##    - Barred Sudanese windows (شبابيك بإطارات حديدية) across front, side, and rear walls on every floor
##    - 1.05m rooftop parapet walls (سترة سطح), rainwater spouts (مزاريب), and ribbed poly water tanks
##    - Proper concrete support columns under every overhanging roof slab
##    - 2.3m Sudanese perimeter courtyard walls (أسوار الحوش) with concrete pillars, street gates,
##      shaded courtyard Rakouba (راكوبة), and clay Zeer water stand (زير ماء فخاري) on residential houses
##    - All static visual details per building merged into 1 multi-surface ArrayMesh (vis = 130.0m)!
## 2. Populates southern & outer neighborhood secondary streets with merged corner grocery kiosks,
##    shaded raksha stops, utility poles + overhead power lines, trash bins, parked vehicles,
##    MultiMesh Neem/Acacia shade trees, and distance-culled (~110m) ambient NPC stations.

const VIS_OUTER_DETAIL: float = 130.0


static func enhance_city_building(
	root: Node3D,
	idx: int,
	style: int,
	w: float,
	d: float,
	h: float,
	floors: int,
	mat_main: Material,
	mat_trim: Material
) -> void:
	var b := InteriorMeshBatcher.new()
	var col_body := StaticBody3D.new()
	col_body.name = "BuildingDetailCol"
	root.add_child(col_body)

	var mat_frame := InteriorMeshBatcher.get_color_mat("oc_win_frame", Color(0.28, 0.18, 0.12), 0.78)
	var mat_glass := InteriorMeshBatcher.get_color_mat("oc_win_glass", Color(0.16, 0.30, 0.42), 0.22, 0.18)
	var mat_iron := InteriorMeshBatcher.get_color_mat("oc_iron", Color(0.16, 0.19, 0.22), 0.44, 0.65)
	var mat_shutter := InteriorMeshBatcher.get_color_mat("oc_shutter_%d" % (idx % 3), [
		Color(0.18, 0.42, 0.32), Color(0.20, 0.38, 0.54), Color(0.48, 0.28, 0.16)
	][idx % 3], 0.72)
	var mat_coping := InteriorMeshBatcher.get_color_mat("oc_coping", Color(0.78, 0.74, 0.68), 0.86)
	var mat_pvc := InteriorMeshBatcher.get_color_mat("oc_pvc", Color(0.76, 0.78, 0.80), 0.45, 0.10)
	var mat_wood := InteriorMeshBatcher.get_pbr_mat("oc_wood", "res://assets/textures/wood", Color(0.56, 0.38, 0.22), 0.80, Vector3(0.8, 0.8, 0.8))
	var mat_thatch := InteriorMeshBatcher.get_color_mat("oc_thatch", Color(0.74, 0.60, 0.36), 0.94)
	var mat_clay := InteriorMeshBatcher.get_color_mat("oc_clay", Color(0.66, 0.34, 0.22), 0.84)

	match style:
		0:
			# Courtyard House (حوش سوداني تقليدي)
			# MainWing: pos=(0, h*0.5, -d*0.22), size=(w*0.88, h, d*0.48)
			var mw := w * 0.88
			var md := d * 0.48
			var mz := -d * 0.22
			# Framed house entrance door on front of MainWing
			_spawn_building_door(root, "HouseDoor", "باب البيت", InteractiveDoor.DoorStyle.WOOD_SINGLE_DOOR, Vector3(0.0, 0.0, mz + md * 0.5 + 0.04), 1.24, 2.24, 0.28, false)
			# Barred windows on front, sides, and back of MainWing across all floors
			_add_facade_windows(b, Vector3(0.0, 0.0, mz), mw, md, h, floors, true, mat_frame, mat_glass, mat_iron, mat_shutter)
			# 1.05m rooftop parapet + rainwater spouts + ribbed poly water tank
			_add_rooftop_parapet_and_tank(b, Vector3(0.0, h, mz), mw, md, idx, mat_main, mat_coping, mat_pvc)
			# Concrete courtyard pillars + coping along existing Hosh walls + shaded Rakouba & clay Zeer!
			_add_courtyard_pillars_and_props(b, col_body, w * 0.90, d * 0.65, d * 0.14, d * 0.46, 2.4, mat_trim, mat_coping, mat_wood, mat_thatch, mat_clay, mat_iron)

		1:
			# Flat-Roof Modern Villa with upper terrace, overhanging slab + SUPPORT COLUMNS + Courtyard Hosh!
			# LowerBox: (0, h*0.35, 0), size=(w, h*0.7, d); UpperBox: (-w*0.12, h*0.85, -d*0.1), size=(w*0.68, h*0.42, d*0.72)
			# RoofSlab: (0, h*1.07, 0), size=(w*0.78, 0.32, d*0.82)
			var lower_h := h * 0.70
			var roof_y := h * 1.07 + 0.16
			# Framed villa double entrance door on front face
			_spawn_building_door(root, "VillaEntranceDoor", "باب الفيلا", InteractiveDoor.DoorStyle.WOOD_DOUBLE_DOOR, Vector3(0.0, 0.0, d * 0.5 + 0.04), 1.65, 2.40, 0.30, false)
			# Barred windows on all 4 facades of LowerBox + UpperBox
			_add_facade_windows(b, Vector3.ZERO, w, d, lower_h, maxi(1, floors - 1), true, mat_frame, mat_glass, mat_iron, mat_shutter)
			_add_facade_windows(b, Vector3(-w * 0.12, lower_h, -d * 0.10), w * 0.68, d * 0.72, h * 0.42, 1, false, mat_frame, mat_glass, mat_iron, mat_shutter)
			# 4 Concrete Support Columns directly underneath the overhanging RoofSlab corners (zero floating overhang!)
			var slab_bot_y := h * 1.07 - 0.16
			var col_h := maxf(0.5, slab_bot_y - lower_h)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var cx := sx * (w * 0.36)
					var cz := sz * (d * 0.38)
					b.add_box(Vector3(cx, lower_h + col_h * 0.5, cz), Vector3(0.36, col_h, 0.36), mat_trim)
			# 1.05m rooftop parapet + spouts + water tank on RoofSlab
			_add_rooftop_parapet_and_tank(b, Vector3(0.0, roof_y, 0.0), w * 0.78, d * 0.82, idx, mat_trim, mat_coping, mat_pvc)
			# Perimeter Sudanese courtyard wall (2.3m) with street gate, Rakouba & Zeer around villa!
			_add_perimeter_courtyard_enclosure(root, b, col_body, w + 3.2, d + 3.4, 2.30, mat_main, mat_trim, mat_coping, mat_wood, mat_thatch, mat_clay, mat_iron)

		2:
			# Arched Colonnade Shopfront
			# ShopCore: (0, h*0.5, -d*0.12), size=(w, h, d*0.76)
			var sd := d * 0.76
			var sz := -d * 0.12
			# Ground-floor roll-up shop shutter door (InteractiveDoor)
			_spawn_building_door(root, "ShopShutter", "باب الدكان", InteractiveDoor.DoorStyle.SHOP_ROLLUP_SHUTTER, Vector3(0.0, 0.0, sz + sd * 0.5 + 0.05), clampf(w * 0.24, 2.4, 3.2), 2.55, 0.28, false)
			# Barred windows across upper floors & side/back walls
			_add_facade_windows(b, Vector3(0.0, 0.0, sz), w, sd, h, floors, true, mat_frame, mat_glass, mat_iron, mat_shutter)
			# 1.05m rooftop parapet + spouts + water tank
			_add_rooftop_parapet_and_tank(b, Vector3(0.0, h, sz), w, sd, idx, mat_main, mat_coping, mat_pvc)

		3:
			# Stepped Apartment Block
			# BaseBlock: (0, h*0.42, 0), size=(w, h*0.84, d); Penthouse: (0, h*0.96, 0), size=(w*0.65, h*0.28, d*0.68)
			var base_h := h * 0.84
			# Ground-floor framed double entrance door
			_spawn_building_door(root, "AptEntranceDoor", "باب العمارة", InteractiveDoor.DoorStyle.WOOD_DOUBLE_DOOR, Vector3(0.0, 0.0, d * 0.5 + 0.04), 1.65, 2.45, 0.32, false)
			# Barred Sudanese windows on Left, Right, Back & Ground Front flanks
			_add_facade_windows(b, Vector3.ZERO, w, d, base_h, floors, true, mat_frame, mat_glass, mat_iron, mat_shutter, true)
			# 1.05m rooftop parapet on both BaseBlock roof rim & Penthouse crown + spouts + tank
			_add_rooftop_parapet_and_tank(b, Vector3(0.0, h * 1.10, 0.0), w * 0.65, d * 0.68, idx, mat_trim, mat_coping, mat_pvc)
			_add_parapet_only(b, Vector3(0.0, base_h, 0.0), w, d, mat_main, mat_coping, mat_pvc)

		4:
			# Corner Tower Building (previously 100% blank!)
			# Wing: (w*0.12, h*0.38, 0), size=(w*0.76, h*0.76, d*0.88)
			# CornerTower: (-w*0.32, h*0.62, d*0.16), size=(w*0.36, h*1.24, d*0.56)
			var wing_w := w * 0.76
			var wing_h := h * 0.76
			var wing_d := d * 0.88
			var tow_w := w * 0.36
			var tow_h := h * 1.24
			var tow_d := d * 0.56
			# Framed ground-floor double entrance door on the Wing front facade
			_spawn_building_door(root, "TowerEntranceDoor", "مدخل المبنى", InteractiveDoor.DoorStyle.WOOD_DOUBLE_DOOR, Vector3(w * 0.16, 0.0, wing_d * 0.5 + 0.04), 1.60, 2.42, 0.32, false)
			# Barred windows on Wing AND CornerTower across all floors!
			_add_facade_windows(b, Vector3(w * 0.12, 0.0, 0.0), wing_w, wing_d, wing_h, floors, true, mat_frame, mat_glass, mat_iron, mat_shutter)
			_add_facade_windows(b, Vector3(-w * 0.32, 0.0, d * 0.16), tow_w, tow_d, tow_h, floors + 1, false, mat_frame, mat_glass, mat_iron, mat_shutter)
			# 1.05m rooftop parapets + spouts + water tank on Wing roof
			_add_rooftop_parapet_and_tank(b, Vector3(w * 0.12, wing_h, 0.0), wing_w, wing_d, idx, mat_main, mat_coping, mat_pvc)
			_add_parapet_only(b, Vector3(-w * 0.32, tow_h + 0.19, d * 0.16), tow_w, tow_d, mat_trim, mat_coping, mat_pvc)

		_:
			# Shaded Veranda House (فرندة مظللة) + Courtyard Hosh Walls!
			# HouseCore: (0, h*0.5, -d*0.12), size=(w*0.94, h, d*0.74)
			var cw := w * 0.94
			var cd := d * 0.74
			var cz := -d * 0.12
			_spawn_building_door(root, "VerandaHouseDoor", "باب البيت", InteractiveDoor.DoorStyle.WOOD_SINGLE_DOOR, Vector3(0.0, 0.36, cz + cd * 0.5 + 0.04), 1.28, 2.26, 0.28, false)
			_add_facade_windows(b, Vector3(0.0, 0.0, cz), cw, cd, h, floors, true, mat_frame, mat_glass, mat_iron, mat_shutter)
			_add_rooftop_parapet_and_tank(b, Vector3(0.0, h, cz), cw, cd, idx, mat_main, mat_coping, mat_pvc)
			# Perimeter Sudanese courtyard wall (2.3m) with street gate, Rakouba & Zeer!
			_add_perimeter_courtyard_enclosure(root, b, col_body, w + 3.0, d + 3.2, 2.30, mat_main, mat_trim, mat_coping, mat_wood, mat_thatch, mat_clay, mat_iron)

	# Commit 1 single multi-surface ArrayMesh for ALL building details (windows, parapets, spouts, tanks, courtyard props)!
	if not b.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "MergedBuildingDetails"
		mi.mesh = b.commit()
		mi.visibility_range_end = VIS_OUTER_DETAIL
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


static func _spawn_building_door(
	parent: Node3D,
	dname: String,
	label: String,
	style: InteractiveDoor.DoorStyle,
	pos: Vector3,
	ow: float,
	oh: float,
	wt: float,
	with_pillars: bool
) -> void:
	var door := InteractiveDoor.new()
	door.name = dname
	door.door_label = label
	door.door_style = style
	door.opening_width = ow
	door.opening_height = oh
	door.wall_thickness = wt
	door.has_pillars = with_pillars
	door.has_lintel_beam = with_pillars
	door.open_angle_deg = 86.0
	door.is_open = false
	door.build_recessed_frame = true
	door.vis_range_end = 95.0
	door.position = pos
	parent.add_child(door)


static func _add_facade_windows(
	b: InteriorMeshBatcher,
	base_ctr: Vector3,
	w: float,
	d: float,
	h: float,
	floors: int,
	has_front_door_ground: bool,
	mat_frame: Material,
	mat_glass: Material,
	mat_iron: Material,
	mat_shutter: Material,
	skip_upper_front: bool = false
) -> void:
	var n_fl := maxi(1, floors)
	var fl_h := h / float(n_fl)
	var n_x := clampi(int(w / 4.8), 2, 4)
	var n_z := clampi(int(d / 4.8), 1, 3)

	for fi in range(n_fl):
		var wy := base_ctr.y + float(fi) * fl_h + minf(1.75, fl_h * 0.56)
		if wy + 0.72 > base_ctr.y + h - 0.15:
			continue
		# Front (+Z) & Back (-Z) walls
		for side_z: float in [1.0, -1.0]:
			if side_z > 0.0 and skip_upper_front and fi > 0:
				continue
			var wz := base_ctr.z + side_z * (d * 0.5 + 0.04)
			var rot_y := 0.0 if side_z > 0.0 else PI
			for xi in range(n_x):
				var wx := base_ctr.x + lerpf(-w * 0.36, w * 0.36, float(xi) / float(maxi(1, n_x - 1)))
				# Keep clear of ground-floor center entrance door
				if side_z > 0.0 and fi == 0 and has_front_door_ground and absf(wx - base_ctr.x) < 1.85:
					continue
				_add_barred_window(b, Vector3(wx, wy, wz), rot_y, 1.35, 1.15, mat_frame, mat_glass, mat_iron, mat_shutter)
		# Left (-X) & Right (+X) walls
		for side_x: float in [-1.0, 1.0]:
			var wx := base_ctr.x + side_x * (w * 0.5 + 0.04)
			var rot_y := -PI * 0.5 if side_x < 0.0 else PI * 0.5
			for zi in range(n_z):
				var t := 0.5 if n_z == 1 else float(zi) / float(n_z - 1)
				var wz := base_ctr.z + lerpf(-d * 0.32, d * 0.32, t)
				_add_barred_window(b, Vector3(wx, wy, wz), rot_y, 1.25, 1.10, mat_frame, mat_glass, mat_iron, mat_shutter)


static func _add_barred_window(
	b: InteriorMeshBatcher,
	pos: Vector3,
	rot_y: float,
	ww: float,
	wh: float,
	mat_frame: Material,
	mat_glass: Material,
	mat_iron: Material,
	mat_shutter: Material
) -> void:
	var basis := Basis(Vector3.UP, rot_y)
	# Recessed dark glass + wooden perimeter frame + stone sill
	b.add_box(pos, Vector3(ww, wh, 0.06), mat_glass, rot_y)
	b.add_box(pos + basis * Vector3(0.0, wh * 0.5 + 0.04, 0.02), Vector3(ww + 0.16, 0.08, 0.10), mat_frame, rot_y)
	b.add_box(pos + basis * Vector3(0.0, -wh * 0.5 - 0.05, 0.05), Vector3(ww + 0.24, 0.10, 0.16), mat_frame, rot_y)
	for sx: float in [-ww * 0.5 - 0.04, ww * 0.5 + 0.04]:
		b.add_box(pos + basis * Vector3(sx, 0.0, 0.02), Vector3(0.08, wh + 0.04, 0.10), mat_frame, rot_y)
	# Wrought-iron security grille bars (شباك حديد سوداني)
	for bx in [-ww * 0.28, 0.0, ww * 0.28]:
		b.add_box(pos + basis * Vector3(bx, 0.0, 0.045), Vector3(0.026, wh, 0.026), mat_iron, rot_y)
	b.add_box(pos + basis * Vector3(0.0, 0.0, 0.045), Vector3(ww, 0.026, 0.026), mat_iron, rot_y)
	# Painted open wooden shutters flanking both sides
	for side: float in [-1.0, 1.0]:
		b.add_box(pos + basis * Vector3(side * (ww * 0.5 + 0.24), 0.0, 0.05), Vector3(0.32, wh, 0.04), mat_shutter, rot_y)


static func _add_parapet_only(
	b: InteriorMeshBatcher,
	roof_ctr: Vector3,
	rw: float,
	rd: float,
	mat_wall: Material,
	mat_coping: Material,
	mat_pvc: Material
) -> void:
	var ph := 1.05
	var pt := 0.22
	var ry := roof_ctr.y
	# 4 perimeter parapet walls + coping caps
	for sz: float in [-rd * 0.5 + pt * 0.5, rd * 0.5 - pt * 0.5]:
		b.add_box(Vector3(roof_ctr.x, ry + ph * 0.5, roof_ctr.z + sz), Vector3(rw, ph, pt), mat_wall)
		b.add_box(Vector3(roof_ctr.x, ry + ph + 0.03, roof_ctr.z + sz), Vector3(rw + 0.06, 0.06, pt + 0.06), mat_coping)
	for sx: float in [-rw * 0.5 + pt * 0.5, rw * 0.5 - pt * 0.5]:
		b.add_box(Vector3(roof_ctr.x + sx, ry + ph * 0.5, roof_ctr.z), Vector3(pt, ph, rd - pt * 2.0), mat_wall)
		b.add_box(Vector3(roof_ctr.x + sx, ry + ph + 0.03, roof_ctr.z), Vector3(pt + 0.06, 0.06, rd - pt * 1.6), mat_coping)
	# Protruding rainwater spouts (مزاريب المياه) on all 4 outer sides
	for sx_side: float in [-1.0, 1.0]:
		var x_edge := roof_ctr.x + sx_side * (rw * 0.5)
		b.add_bar(Vector3(x_edge, ry + 0.14, roof_ctr.z), Vector3(x_edge + sx_side * 0.45, ry + 0.04, roof_ctr.z), 0.07, 0.07, mat_pvc)
	for sz_side: float in [-1.0, 1.0]:
		var z_edge := roof_ctr.z + sz_side * (rd * 0.5)
		b.add_bar(Vector3(roof_ctr.x, ry + 0.14, z_edge), Vector3(roof_ctr.x, ry + 0.04, z_edge + sz_side * 0.45), 0.07, 0.07, mat_pvc)


static func _add_rooftop_parapet_and_tank(
	b: InteriorMeshBatcher,
	roof_ctr: Vector3,
	rw: float,
	rd: float,
	idx: int,
	mat_wall: Material,
	mat_coping: Material,
	mat_pvc: Material
) -> void:
	_add_parapet_only(b, roof_ctr, rw, rd, mat_wall, mat_coping, mat_pvc)
	var tank_pos := Vector3(roof_ctr.x - rw * 0.22, roof_ctr.y, roof_ctr.z - rd * 0.18)
	SudaneseRooftopBuilder.add_water_tank_to_batcher(b, tank_pos, 0.58, 1.18, idx % 3)


static func _add_courtyard_pillars_and_props(
	b: InteriorMeshBatcher,
	col_body: StaticBody3D,
	cw: float,
	cd: float,
	yard_z_ctr: float,
	front_z: float,
	wall_h: float,
	mat_pillar: Material,
	mat_coping: Material,
	mat_wood: Material,
	mat_thatch: Material,
	mat_clay: Material,
	mat_iron: Material
) -> void:
	# Concrete pillars & coping caps crowning the courtyard walls
	for sx: float in [-cw * 0.5, cw * 0.5]:
		for pz: float in [front_z, yard_z_ctr]:
			b.add_box(Vector3(sx, wall_h * 0.5 + 0.10, pz), Vector3(0.56, wall_h + 0.20, 0.56), mat_pillar)
			b.add_box(Vector3(sx, wall_h + 0.24, pz), Vector3(0.64, 0.08, 0.64), mat_coping)
	# Shaded Sudanese Rakouba (راكوبة) pergola tucked inside the left courtyard corner
	var rx := -cw * 0.28
	var rz := front_z - 2.35
	_add_rakouba_and_zeer(b, col_body, Vector3(rx, 0.0, rz), Vector3(cw * 0.28, 0.0, front_z - 1.6), mat_wood, mat_thatch, mat_clay, mat_iron)


static func _add_perimeter_courtyard_enclosure(
	root: Node3D,
	b: InteriorMeshBatcher,
	col_body: StaticBody3D,
	cw: float,
	cd: float,
	wall_h: float,
	mat_wall: Material,
	mat_pillar: Material,
	mat_coping: Material,
	mat_wood: Material,
	mat_thatch: Material,
	mat_clay: Material,
	mat_iron: Material
) -> void:
	var wt := 0.34
	var hw := cw * 0.5
	var hd := cd * 0.5
	var gate_w := 2.85
	var front_seg_w := maxf(1.2, (cw - gate_w) * 0.5)
	# Back, Left, Right, Front-Left, Front-Right 2.3m Hosh walls + solid collision
	b.add_box(Vector3(0.0, wall_h * 0.5, -hd), Vector3(cw, wall_h, wt), mat_wall)
	b.add_box(Vector3(0.0, wall_h + 0.04, -hd), Vector3(cw + 0.08, 0.08, wt + 0.08), mat_coping)
	InteriorMeshBatcher.add_box_collider(col_body, "HoshBack", Vector3(0.0, wall_h * 0.5, -hd), Vector3(cw, wall_h, wt))

	for sx: float in [-hw, hw]:
		b.add_box(Vector3(sx, wall_h * 0.5, 0.0), Vector3(wt, wall_h, cd), mat_wall)
		b.add_box(Vector3(sx, wall_h + 0.04, 0.0), Vector3(wt + 0.08, 0.08, cd + 0.08), mat_coping)
		InteriorMeshBatcher.add_box_collider(col_body, "HoshSide_%.0f" % sx, Vector3(sx, wall_h * 0.5, 0.0), Vector3(wt, wall_h, cd))

	for side: float in [-1.0, 1.0]:
		var fx := side * (gate_w * 0.5 + front_seg_w * 0.5)
		b.add_box(Vector3(fx, wall_h * 0.5, hd), Vector3(front_seg_w, wall_h, wt), mat_wall)
		b.add_box(Vector3(fx, wall_h + 0.04, hd), Vector3(front_seg_w + 0.06, 0.08, wt + 0.08), mat_coping)
		InteriorMeshBatcher.add_box_collider(col_body, "HoshFront_%.0f" % side, Vector3(fx, wall_h * 0.5, hd), Vector3(front_seg_w, wall_h, wt))

	# Concrete corner & mid pillars
	for sx: float in [-hw, hw]:
		for sz: float in [-hd, 0.0, hd]:
			b.add_box(Vector3(sx, wall_h * 0.5 + 0.10, sz), Vector3(0.52, wall_h + 0.20, 0.52), mat_pillar)
			b.add_box(Vector3(sx, wall_h + 0.24, sz), Vector3(0.60, 0.08, 0.60), mat_coping)

	# Street courtyard gate (InteractiveDoor)
	_spawn_building_door(root, "HoshStreetGate", "بوابة الحوش", InteractiveDoor.DoorStyle.COURTYARD_DOUBLE_GATE, Vector3(0.0, 0.0, hd), gate_w, 2.28, wt, true)

	# Shaded Rakouba & Clay Zeer inside front yard
	_add_rakouba_and_zeer(b, col_body, Vector3(-hw + 2.1, 0.0, hd - 1.35), Vector3(hw - 1.4, 0.0, hd - 1.05), mat_wood, mat_thatch, mat_clay, mat_iron)


static func _add_rakouba_and_zeer(
	b: InteriorMeshBatcher,
	col_body: StaticBody3D,
	rak_pos: Vector3,
	zeer_pos: Vector3,
	mat_wood: Material,
	mat_thatch: Material,
	mat_clay: Material,
	mat_iron: Material
) -> void:
	# Shaded Sudanese Rakouba (راكوبة: 4 wooden posts + thatched shade canopy + bench)
	var rw := 2.8
	var rd := 2.0
	var rh := 2.35
	for px: float in [-rw * 0.45, rw * 0.45]:
		for pz: float in [-rd * 0.45, rd * 0.45]:
			b.add_cylinder(rak_pos + Vector3(px, rh * 0.5, pz), 0.055, 0.065, rh, mat_wood, 6)
	b.add_box(rak_pos + Vector3(0.0, rh + 0.06, 0.0), Vector3(rw + 0.25, 0.14, rd + 0.25), mat_thatch)
	b.add_box(rak_pos + Vector3(0.0, 0.42, 0.0), Vector3(1.55, 0.08, 0.55), mat_wood)
	InteriorMeshBatcher.add_box_collider(col_body, "RakoubaBench", rak_pos + Vector3(0.0, 0.25, 0.0), Vector3(1.6, 0.5, 0.6))

	# Traditional Clay Zeer Water Jar on Iron Stand (زير ماء فخاري)
	b.add_cylinder(zeer_pos + Vector3(0.0, 0.36, 0.0), 0.24, 0.28, 0.04, mat_iron, 8)
	for li in range(3):
		var ang := float(li) * TAU / 3.0
		b.add_cylinder(zeer_pos + Vector3(cos(ang) * 0.22, 0.20, sin(ang) * 0.22), 0.02, 0.02, 0.40, mat_iron, 5)
	b.add_sphere(zeer_pos + Vector3(0.0, 0.58, 0.0), 0.26, mat_clay, Vector3(1.0, 1.12, 1.0), 8, 5)
	b.add_cylinder(zeer_pos + Vector3(0.0, 0.88, 0.0), 0.19, 0.19, 0.04, mat_wood, 8)
	InteriorMeshBatcher.add_box_collider(col_body, "ZeerStandCol", zeer_pos + Vector3(0.0, 0.45, 0.0), Vector3(0.55, 0.9, 0.55))


# ==============================================================================
# OUTER & SOUTHERN STREET LIFE: KIOSKS, RAKSHA STOPS, POWER LINES, TREES, PARKED CARS
# ==============================================================================
static func build_outer_street_life(
	parent: Node3D,
	blocked_rects: Array[Rect2],
	role_stations: Array[Dictionary]
) -> void:
	var life_root := Node3D.new()
	life_root.name = "OuterNeighborhoodStreetLife"
	life_root.add_to_group("outer_street_life")
	parent.add_child(life_root)

	# 1. Sector-merged Street Props: Corner Kiosks, Shaded Raksha Stops, Utility Poles + Power Lines,
	#    Trash Bins, and Parked Neighborhood Vehicles (1 ArrayMesh per sector, vis = 130.0m!)
	var sectors: Array[Dictionary] = [
		{
			"name": "SouthEastCore",
			"district": "South Al-Azhari Extension",
			"kiosks": [Vector3(20.0, 0.0, 156.0), Vector3(198.0, 0.0, 156.0), Vector3(112.0, 0.0, 294.0), Vector3(294.0, 0.0, 294.0)],
			"stops": [Vector3(14.0, 0.0, 272.0), Vector3(206.0, 0.0, 286.0)],
			"poles_line": [
				[Vector3(16.0, 0.0, 142.5), Vector3(204.0, 0.0, 142.5)],
				[Vector3(16.0, 0.0, 274.0), Vector3(384.0, 0.0, 274.0)],
				[Vector3(16.0, 0.0, 454.0), Vector3(384.0, 0.0, 454.0)],
			],
			"cars": [Vector3(46.0, 0.0, 152.5), Vector3(146.0, 0.0, 152.5), Vector3(86.0, 0.0, 286.0), Vector3(266.0, 0.0, 286.0), Vector3(172.0, 0.0, 466.0)],
		},
		{
			"name": "SouthWestCorniche",
			"district": "South Corniche & West Bank",
			"kiosks": [Vector3(-64.0, 0.0, 174.0), Vector3(-64.0, 0.0, 294.0), Vector3(-332.0, 0.0, 294.0), Vector3(-478.0, 0.0, 294.0)],
			"stops": [Vector3(-96.0, 0.0, 274.0), Vector3(-284.0, 0.0, 274.0)],
			"poles_line": [
				[Vector3(-96.0, 0.0, 274.0), Vector3(-16.0, 0.0, 274.0)],
				[Vector3(-544.0, 0.0, 274.0), Vector3(-284.0, 0.0, 274.0)],
				[Vector3(-544.0, 0.0, 454.0), Vector3(-284.0, 0.0, 454.0)],
			],
			"cars": [Vector3(-42.0, 0.0, 286.0), Vector3(-78.0, 0.0, 466.0), Vector3(-318.0, 0.0, 286.0), Vector3(-460.0, 0.0, 286.0)],
		},
		{
			"name": "NorthOuterBlocks",
			"district": "North Khartoum Extension",
			"kiosks": [Vector3(114.0, 0.0, -294.0), Vector3(314.0, 0.0, -294.0), Vector3(-344.0, 0.0, -294.0), Vector3(-484.0, 0.0, -294.0)],
			"stops": [Vector3(16.0, 0.0, -280.0), Vector3(-284.0, 0.0, -280.0)],
			"poles_line": [
				[Vector3(16.0, 0.0, -286.0), Vector3(384.0, 0.0, -286.0)],
				[Vector3(-544.0, 0.0, -286.0), Vector3(-284.0, 0.0, -286.0)],
			],
			"cars": [Vector3(78.0, 0.0, -274.0), Vector3(268.0, 0.0, -274.0), Vector3(-316.0, 0.0, -274.0)],
		},
	]

	var mat_kiosk := InteriorMeshBatcher.get_pbr_mat("ol_kiosk", "res://assets/textures/plaster", Color(0.92, 0.85, 0.72), 0.86, Vector3(0.4, 0.4, 0.4))
	var mat_green := InteriorMeshBatcher.get_color_mat("ol_green", Color(0.12, 0.48, 0.28), 0.58)
	var mat_blue := InteriorMeshBatcher.get_color_mat("ol_blue", Color(0.16, 0.42, 0.72), 0.58)
	var mat_red := InteriorMeshBatcher.get_color_mat("ol_red", Color(0.76, 0.18, 0.16), 0.55)
	var mat_yellow := InteriorMeshBatcher.get_color_mat("ol_yellow", Color(0.92, 0.74, 0.16), 0.52)
	var mat_white := InteriorMeshBatcher.get_color_mat("ol_white", Color(0.93, 0.93, 0.90), 0.42)
	var mat_pole := InteriorMeshBatcher.get_color_mat("ol_pole", Color(0.48, 0.46, 0.42), 0.86)
	var mat_wire := InteriorMeshBatcher.get_color_mat("ol_wire", Color(0.12, 0.12, 0.14), 0.65)
	var mat_tire := InteriorMeshBatcher.get_color_mat("ol_tire", Color(0.14, 0.14, 0.16), 0.88)
	var mat_glass := InteriorMeshBatcher.get_color_mat("ol_glass", Color(0.18, 0.30, 0.40), 0.20, 0.25)
	var mat_wood := InteriorMeshBatcher.get_pbr_mat("ol_wood", "res://assets/textures/wood", Color(0.56, 0.38, 0.22), 0.80, Vector3(0.8, 0.8, 0.8))

	var car_mats: Array[StandardMaterial3D] = [mat_white, mat_blue, mat_red, mat_yellow]
	var npc_idx := 0

	var is_web := OS.has_feature("web")
	for sec in sectors:
		if is_web and String(sec["name"]) == "NorthOuterBlocks":
			continue
		var snode := Node3D.new()
		snode.name = "Sector_" + String(sec["name"])
		life_root.add_child(snode)
		var scol := StaticBody3D.new()
		scol.name = "SectorCol"
		snode.add_child(scol)
		var b := InteriorMeshBatcher.new()

		# Corner Grocery Kiosks (دكان ناصية / كشك) + Trash Bins + Shopkeeper & Sitting Elder NPCs
		var kiosks: Array = sec["kiosks"]
		for ki in range(kiosks.size()):
			var kp: Vector3 = kiosks[ki]
			if SmartWorldOrganizer.is_in_bridge_exclusion(kp, 5.0):
				continue
			b.add_box(kp + Vector3(0.0, 1.45, 0.0), Vector3(3.8, 2.9, 3.0), mat_kiosk)
			b.add_box(kp + Vector3(0.0, 2.98, 0.35), Vector3(4.3, 0.18, 3.9), mat_green if (ki % 2 == 0) else mat_blue)
			b.add_box(kp + Vector3(0.0, 0.55, 1.65), Vector3(2.8, 1.05, 0.55), mat_wood)
			# Trash bin beside kiosk
			b.add_cylinder(kp + Vector3(2.35, 0.45, 1.1), 0.28, 0.24, 0.90, mat_green, 8)
			InteriorMeshBatcher.add_box_collider(scol, "KioskCol_%d" % ki, kp + Vector3(0.0, 1.45, 0.0), Vector3(3.9, 2.9, 3.4))

			var klbl := Label3D.new()
			klbl.position = kp + Vector3(0.0, 2.55, 1.56)
			klbl.text = "دكان وبقالة الناصية" if (ki % 2 == 0) else "كشك مواد غذائية"
			klbl.font_size = 28
			klbl.outline_size = 5
			klbl.modulate = Color(1.0, 0.96, 0.80)
			klbl.visibility_range_end = 55.0
			snode.add_child(klbl)

			# Register distance-culled (110m) Kiosk Shopkeeper + Sitting Elder!
			npc_idx += 1
			role_stations.append({
				"role": "vendor",
				"district": String(sec["district"]),
				"label": "بائع كشك الحي",
				"position": kp + Vector3(0.0, 0.0, 2.45),
				"yaw": 0.0,
				"ai_activation_radius": 110.0,
				"behavior_role": NPCInteractive.NPCBehaviorRole.MARKET_TALKING,
				"lines": ["أهلاً يا زول في دكان الناصية!", "عندنا عصائر باردة ومستلزمات يومية."],
			})
			if ki % 2 == 0:
				role_stations.append({
					"role": "elder",
					"district": String(sec["district"]),
					"label": "عمّنا في الحي",
					"position": kp + Vector3(-2.6, 0.0, 1.8),
					"yaw": 0.4,
					"ai_activation_radius": 110.0,
					"behavior_role": NPCInteractive.NPCBehaviorRole.SEATED_IDLE,
					"lines": ["السلام عليكم يا ولدي، الحي ده بقى عامر وجميل!", "اتفضل اشرب معانا كباية شاي تحت الضل."],
				})

		# Shaded Bus / Raksha Stops (موقف ركشة ومواصلات) + Waiting Pedestrian NPCs
		var stops: Array = sec["stops"]
		for si in range(stops.size()):
			var sp: Vector3 = stops[si]
			if SmartWorldOrganizer.is_in_bridge_exclusion(sp, 5.0):
				continue
			b.add_box(sp + Vector3(0.0, 0.10, 0.0), Vector3(5.2, 0.20, 2.2), mat_pole)
			b.add_box(sp + Vector3(0.0, 2.65, 0.0), Vector3(5.4, 0.16, 2.4), mat_green)
			for px: float in [-2.3, 2.3]:
				b.add_cylinder(sp + Vector3(px, 1.35, -0.85), 0.07, 0.08, 2.6, mat_pole, 6)
			b.add_box(sp + Vector3(0.0, 0.52, -0.55), Vector3(3.4, 0.12, 0.55), mat_wood)
			InteriorMeshBatcher.add_box_collider(scol, "StopCol_%d" % si, sp + Vector3(0.0, 0.6, -0.6), Vector3(5.2, 1.2, 1.0))

			# Register distance-culled (110m) walking neighborhood pedestrian near stop!
			role_stations.append({
				"role": "pedestrian",
				"district": String(sec["district"]),
				"label": "من أهل الحي",
				"position": sp + Vector3(0.0, 0.0, 1.8),
				"yaw": 0.0,
				"ai_activation_radius": 110.0,
				"patrol_points": PackedVector3Array([
					sp + Vector3(-16.0, 0.0, 1.8),
					sp + Vector3(16.0, 0.0, 1.8),
				]),
				"walk_speed": 1.65,
				"behavior_role": NPCInteractive.NPCBehaviorRole.PATROL,
				"lines": ["صباح الخير يا زول!", "الشارع الجديد ده سهّل المشوار كتير."],
			})

		# Utility Poles + Overhead Power Lines (أعمدة وأسلاك كهرباء) along secondary streets
		var lines: Array = sec["poles_line"]
		for li in range(lines.size()):
			var seg: Array = lines[li]
			var p_start: Vector3 = seg[0]
			var p_end: Vector3 = seg[1]
			var dist := p_start.distance_to(p_end)
			var n_poles := maxi(2, int(round(dist / 38.0)) + 1)
			var prev_pt := Vector3.ZERO
			for pi in range(n_poles):
				var pt := p_start.lerp(p_end, float(pi) / float(n_poles - 1))
				if SmartWorldOrganizer.is_in_bridge_exclusion(pt, 4.0):
					prev_pt = Vector3.ZERO
					continue
				# Utility pole + wooden top cross-arm
				b.add_cylinder(pt + Vector3(0.0, 3.8, 0.0), 0.11, 0.16, 7.6, mat_pole, 6)
				b.add_box(pt + Vector3(0.0, 7.25, 0.0), Vector3(0.14, 0.14, 1.65), mat_wood)
				InteriorMeshBatcher.add_box_collider(scol, "Pole_%d_%d" % [li, pi], pt + Vector3(0.0, 2.0, 0.0), Vector3(0.36, 4.0, 0.36))
				# Twin overhead power lines spanning from previous pole!
				if prev_pt != Vector3.ZERO:
					for wz: float in [-0.62, 0.62]:
						b.add_bar(prev_pt + Vector3(0.0, 7.32, wz), pt + Vector3(0.0, 7.32, wz), 0.025, 0.025, mat_wire)
				prev_pt = pt

		# Parked Sudanese Neighborhood Cars & Rakshas along secondary street curbs
		var cars: Array = sec["cars"]
		for ci in range(cars.size()):
			var cp: Vector3 = cars[ci]
			if SmartWorldOrganizer.is_in_bridge_exclusion(cp, 4.0):
				continue
			var cmat := car_mats[ci % car_mats.size()]
			if ci % 3 == 2:
				# Parked Sudanese Raksha (3-wheeler)
				b.add_box(cp + Vector3(0.0, 0.72, 0.0), Vector3(2.2, 0.85, 1.25), mat_yellow)
				b.add_box(cp + Vector3(-0.15, 1.38, 0.0), Vector3(1.5, 0.55, 1.20), mat_green)
				b.add_box(cp + Vector3(0.72, 1.15, 0.0), Vector3(0.08, 0.52, 1.05), mat_glass)
				for wx: float in [-0.72, 0.78]:
					b.add_cylinder(cp + Vector3(wx, 0.26, 0.0), 0.26, 0.26, 1.28 if wx < 0.0 else 0.22, mat_tire, 8, PI * 0.5, 0.0)
				InteriorMeshBatcher.add_box_collider(scol, "ParkedRaksha_%d" % ci, cp + Vector3(0.0, 0.85, 0.0), Vector3(2.3, 1.7, 1.35))
			else:
				# Parked Neighborhood Sedan / Pickup (Boks)
				b.add_box(cp + Vector3(0.0, 0.62, 0.0), Vector3(4.2, 0.78, 1.78), cmat)
				b.add_box(cp + Vector3(-0.20, 1.24, 0.0), Vector3(2.15, 0.62, 1.56), cmat)
				b.add_box(cp + Vector3(-0.20, 1.24, 0.0), Vector3(2.22, 0.44, 1.60), mat_glass)
				for wx: float in [-1.32, 1.32]:
					for wz: float in [-0.86, 0.86]:
						b.add_cylinder(cp + Vector3(wx, 0.34, wz), 0.34, 0.34, 0.24, mat_tire, 8, PI * 0.5, 0.0)
				InteriorMeshBatcher.add_box_collider(scol, "ParkedCar_%d" % ci, cp + Vector3(0.0, 0.80, 0.0), Vector3(4.3, 1.6, 1.85))

		if not b.is_empty():
			var mi := MeshInstance3D.new()
			mi.name = "MergedSectorStreetLife"
			mi.mesh = b.commit()
			mi.visibility_range_end = VIS_OUTER_DETAIL
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			snode.add_child(mi)

	# 2. Clusters of Shady Neem & Acacia Trees across Southern & Outer Blocks (2 single MultiMesh batches!)
	_spawn_outer_shade_trees(life_root, blocked_rects)


static func _spawn_outer_shade_trees(parent: Node3D, blocked_rects: Array[Rect2]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 994721
	var neem_spots: Array[Vector3] = []
	var acacia_spots: Array[Vector3] = []

	# Sample grid across southern & outer blocks, keeping clear of roads, buildings, tunnels & bridges
	var xs: Array[float] = [-520, -455, -380, -315, -75, -35, 45, 95, 165, 265, 345, 455, 520]
	var zs: Array[float] = [-490, -415, -245, -165, 155, 245, 315, 415, 495]
	var is_web := OS.has_feature("web")
	for x in xs:
		for z in zs:
			if is_web and Vector2(x, z).length() > 320.0:
				continue
			var p := Vector3(x + rng.randf_range(-8.0, 8.0), 0.0, z + rng.randf_range(-8.0, 8.0))
			if SmartWorldOrganizer.is_in_bridge_exclusion(p, 6.0):
				continue
			var r := Rect2(p.x - 2.4, p.z - 2.4, 4.8, 4.8)
			var blocked := false
			for br in blocked_rects:
				if r.intersects(br):
					blocked = true
					break
			if blocked:
				continue
			if (neem_spots.size() + acacia_spots.size()) % 2 == 0:
				neem_spots.append(p)
			else:
				acacia_spots.append(p)

	_batch_tree_species(parent, "OuterNeemTrees", SudaneseTreeBuilder.TreeSpecies.NEEM, neem_spots, rng)
	_batch_tree_species(parent, "OuterAcaciaTrees", SudaneseTreeBuilder.TreeSpecies.ACACIA, acacia_spots, rng)


static func _batch_tree_species(parent: Node3D, bname: String, sp: SudaneseTreeBuilder.TreeSpecies, spots: Array[Vector3], rng: RandomNumberGenerator) -> void:
	if spots.is_empty():
		return
	var pair := SudaneseTreeBuilder.get_species_meshes(sp, 0)
	var mm_t := MultiMesh.new()
	mm_t.transform_format = MultiMesh.TRANSFORM_3D
	mm_t.mesh = pair["trunk"]
	mm_t.instance_count = spots.size()

	var mm_c := MultiMesh.new()
	mm_c.transform_format = MultiMesh.TRANSFORM_3D
	mm_c.mesh = pair["canopy"]
	mm_c.instance_count = spots.size()

	for i in range(spots.size()):
		var sc := rng.randf_range(0.92, 1.22)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * sc), spots[i])
		mm_t.set_instance_transform(i, xf)
		mm_c.set_instance_transform(i, xf)

	var holder := Node3D.new()
	holder.name = bname
	parent.add_child(holder)

	var mmi_t := MultiMeshInstance3D.new()
	mmi_t.multimesh = mm_t
	mmi_t.material_override = SudaneseTreeBuilder.get_bark_material(sp)
	mmi_t.visibility_range_end = VIS_OUTER_DETAIL
	mmi_t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mmi_t)

	var mmi_c := MultiMeshInstance3D.new()
	mmi_c.multimesh = mm_c
	mmi_c.material_override = SudaneseTreeBuilder.get_canopy_material(sp)
	mmi_c.visibility_range_end = VIS_OUTER_DETAIL
	mmi_c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mmi_c)
