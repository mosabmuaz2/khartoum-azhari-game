extends Node3D
class_name SudaneseHouseInterior

## High-FPS Authentic Sudanese Courtyard House Interior & Veranda Builder for Godot 4.7.2.
## - Clean, zero-overlap Diwan (living room) + Bedroom alcove + wide 2.4m entrance clearance
## - Patterned Sudanese woven rug, aligned wooden-frame sofas & armchairs, coffee table with Jebena set
## - Aligned wooden Angareeb/bed with mattress/pillows, nightstand with lamp, full wardrobe
## - Authentic Sudanese decor: flat-mounted colorful woven palm-leaf food covers (أطباق سعف ملونة),
##   flush framed calligraphy/Nile art, clay Zeer water jar (زير فخاري) on stand with lid & cup,
##   window curtains (ستائر), and corner potted plants — all merged into 1 cached multi-surface ArrayMesh!

@export var floor_y: float = 0.10
@export var vis_range_end: float = 82.0

static var _mesh_cache: Dictionary = {}
var _built: bool = false


func _ready() -> void:
	add_to_group("sudanese_house_interiors")
	build_interior()


func build_interior() -> void:
	if _built:
		return
	_built = true

	var col_body := StaticBody3D.new()
	col_body.name = "HouseInteriorCollision"
	add_child(col_body)

	var cache_key := "sudanese_house_int_%.2f" % floor_y
	var cached := _mesh_cache.get(cache_key) as ArrayMesh
	var b: InteriorMeshBatcher = null if cached != null else InteriorMeshBatcher.new()

	var mat_wall := InteriorMeshBatcher.get_pbr_mat("hi_wall", "res://assets/textures/plaster", Color(0.95, 0.89, 0.78), 0.88, Vector3(0.5, 0.5, 0.5))
	var mat_wood_dk := InteriorMeshBatcher.get_pbr_mat("hi_wood_dk", "res://assets/textures/wood", Color(0.42, 0.25, 0.14), 0.68, Vector3(0.9, 0.9, 0.9))
	var mat_wood_lt := InteriorMeshBatcher.get_pbr_mat("hi_wood_lt", "res://assets/textures/wood", Color(0.68, 0.48, 0.28), 0.72, Vector3(0.9, 0.9, 0.9))
	var mat_sofa := InteriorMeshBatcher.get_pbr_mat("hi_sofa", "res://assets/textures/fabric", Color(0.62, 0.22, 0.18), 0.90, Vector3(1.5, 1.5, 1.5))
	var mat_cushion := InteriorMeshBatcher.get_color_mat("hi_cush", Color(0.86, 0.68, 0.28), 0.88)
	var mat_linen := InteriorMeshBatcher.get_color_mat("hi_linen", Color(0.94, 0.92, 0.86), 0.90)
	var mat_blanket := InteriorMeshBatcher.get_color_mat("hi_blanket", Color(0.16, 0.40, 0.36), 0.90)
	var mat_rug := InteriorMeshBatcher.get_sudanese_rug_mat(0)
	var mat_rug_bed := InteriorMeshBatcher.get_sudanese_rug_mat(1)
	var mat_clay := InteriorMeshBatcher.get_color_mat("hi_clay", Color(0.66, 0.34, 0.22), 0.84)
	var mat_clay_dk := InteriorMeshBatcher.get_color_mat("hi_clay_dk", Color(0.32, 0.16, 0.10), 0.62)
	var mat_iron := InteriorMeshBatcher.get_color_mat("hi_iron", Color(0.18, 0.20, 0.22), 0.45, 0.68)
	var mat_brass := InteriorMeshBatcher.get_color_mat("hi_brass", Color(0.86, 0.70, 0.26), 0.30, 0.78)
	var mat_curtain := InteriorMeshBatcher.get_color_mat("hi_curtain", Color(0.78, 0.62, 0.34), 0.88)
	var mat_leaf := InteriorMeshBatcher.get_color_mat("hi_leaf", Color(0.16, 0.48, 0.20), 0.78)
	var mat_lamp := InteriorMeshBatcher.get_color_mat("hi_lamp", Color(1.0, 0.92, 0.72), 0.30, 0.0, Color(1.0, 0.88, 0.60), 1.8)

	# ------------------------------------------------------------------
	# 1. CLEAN BEDROOM PARTITION WALL (leaves wide 2.4m open entry corridor!)
	# Interior room spans x in [-4.82, +4.82], z in [-7.82, -0.18], front door at (0, 0)
	# Partition at x = -1.65, z in [-7.82, -4.62] -> open passage z in [-4.62, -0.18] (4.4m wide!)
	# ------------------------------------------------------------------
	if b != null:
		b.add_box(Vector3(-1.65, floor_y + 1.68, -6.22), Vector3(0.18, 3.36, 3.20), mat_wall)
		# Raised wooden entry threshold at front house doorway
		b.add_box(Vector3(0.0, floor_y + 0.016, -0.18), Vector3(1.52, 0.032, 0.24), mat_wood_dk)
	InteriorMeshBatcher.add_box_collider(col_body, "BedroomPartCol", Vector3(-1.65, floor_y + 1.68, -6.22), Vector3(0.20, 3.36, 3.20))

	# ------------------------------------------------------------------
	# 2. DIWAN / LIVING ROOM (الديوان) — East & Center (x in [-1.0, +4.7], z in [-7.7, -1.6])
	# Zero overlap: centered woven carpet, 3-seat sofa along East wall, 2-seat sofa along North wall,
	# 2 aligned armchairs on West side of rug, carved coffee table + Jebena coffee tray in center!
	# ------------------------------------------------------------------
	var diwan_ctr := Vector3(1.85, floor_y, -4.45)
	if b != null:
		# Patterned Sudanese woven Diwan carpet
		b.add_box(Vector3(diwan_ctr.x, floor_y + 0.012, diwan_ctr.z), Vector3(3.60, 0.022, 3.20), mat_rug)

	# 3-seat Sofa flush along East wall (x = +4.25, z = -4.45, facing -X toward table)
	_add_sofa(b, col_body, "DiwanSofaEast", Vector3(4.25, floor_y, -4.45), 2.35, -PI * 0.5, mat_wood_dk, mat_sofa, mat_cushion)
	# 2-seat Sofa flush along North wall (x = +1.85, z = -7.25, facing +Z toward table)
	_add_sofa(b, col_body, "DiwanSofaNorth", Vector3(1.85, floor_y, -7.25), 1.85, 0.0, mat_wood_dk, mat_sofa, mat_cushion)
	# Two neatly aligned armchairs facing +X on West edge of Diwan rug (well clear of bedroom partition!)
	_add_sofa(b, col_body, "DiwanChair_1", Vector3(-0.35, floor_y, -3.55), 0.88, PI * 0.5, mat_wood_dk, mat_sofa, mat_cushion)
	_add_sofa(b, col_body, "DiwanChair_2", Vector3(-0.35, floor_y, -5.35), 0.88, PI * 0.5, mat_wood_dk, mat_sofa, mat_cushion)

	# Central Carved Coffee Table + Traditional Sudanese Jebena Coffee Tray Set (جبنة وفناجين)
	if b != null:
		var tc := Vector3(1.85, floor_y, -4.45)
		b.add_box(tc + Vector3(0.0, 0.44, 0.0), Vector3(1.25, 0.06, 0.78), mat_wood_lt)
		b.add_box(tc + Vector3(0.0, 0.16, 0.0), Vector3(1.08, 0.04, 0.62), mat_wood_dk)
		for lx: float in [-0.54, 0.54]:
			for lz: float in [-0.32, 0.32]:
				b.add_box(tc + Vector3(lx, 0.22, lz), Vector3(0.06, 0.44, 0.06), mat_wood_dk)
		# Brass serving tray (صينية قهوة)
		b.add_cylinder(tc + Vector3(0.0, 0.48, 0.0), 0.28, 0.26, 0.025, mat_brass, 12)
		# Traditional Sudanese clay Jebena pot (جبنة سودانية)
		var jp := tc + Vector3(-0.08, 0.49, 0.0)
		b.add_sphere(jp + Vector3(0.0, 0.09, 0.0), 0.085, mat_clay_dk, Vector3(1.0, 0.92, 1.0), 8, 5)
		b.add_cylinder(jp + Vector3(0.0, 0.21, 0.0), 0.024, 0.036, 0.14, mat_clay_dk, 8)
		b.add_cylinder(jp + Vector3(0.0, 0.285, 0.0), 0.038, 0.024, 0.03, mat_clay_dk, 8)
		# 4 tiny porcelain coffee cups (فناجين قهوة) + sugar bowl
		for fi in range(4):
			var ang := float(fi) * 1.1 - 1.1
			var fp := tc + Vector3(0.12 + cos(ang) * 0.09, 0.51, sin(ang) * 0.11)
			b.add_cylinder(fp, 0.026, 0.020, 0.048, mat_linen, 6)
	InteriorMeshBatcher.add_box_collider(col_body, "DiwanTableCol", Vector3(1.85, floor_y + 0.24, -4.45), Vector3(1.28, 0.48, 0.80))

	# ------------------------------------------------------------------
	# 3. BEDROOM ALCOVE (غرفة النوم) — West Side (x in [-4.8, -1.75], z in [-7.8, -1.0])
	# Aligned Angareeb/Bed against West wall, nightstand + bedside lamp, wardrobe along West wall
	# ------------------------------------------------------------------
	if b != null:
		b.add_box(Vector3(-3.35, floor_y + 0.012, -5.85), Vector3(2.20, 0.02, 2.60), mat_rug_bed)
		# Wooden Bed / Angareeb (headboard against West wall x = -4.75, extending +X to -2.75)
		var bed_c := Vector3(-3.75, floor_y, -6.25)
		b.add_box(bed_c + Vector3(0.0, 0.28, 0.0), Vector3(1.96, 0.14, 1.42), mat_wood_dk)
		b.add_box(bed_c + Vector3(-0.96, 0.58, 0.0), Vector3(0.08, 0.88, 1.44), mat_wood_dk) # Headboard
		b.add_box(bed_c + Vector3(0.96, 0.40, 0.0), Vector3(0.08, 0.52, 1.44), mat_wood_dk)  # Footboard
		for lx: float in [-0.90, 0.90]:
			for lz: float in [-0.64, 0.64]:
				b.add_box(bed_c + Vector3(lx, 0.14, lz), Vector3(0.08, 0.28, 0.08), mat_wood_dk)
		# Mattress, folded blanket & twin pillows
		b.add_box(bed_c + Vector3(0.0, 0.44, 0.0), Vector3(1.86, 0.18, 1.34), mat_linen)
		b.add_box(bed_c + Vector3(0.35, 0.47, 0.0), Vector3(1.12, 0.16, 1.36), mat_blanket)
		b.add_box(bed_c + Vector3(-0.68, 0.58, -0.32), Vector3(0.38, 0.12, 0.52), mat_cushion)
		b.add_box(bed_c + Vector3(-0.68, 0.58, 0.32), Vector3(0.38, 0.12, 0.52), mat_cushion)

		# Nightstand + Bedside Lamp beside bed (x = -4.48, z = -7.32)
		var ns := Vector3(-4.48, floor_y, -7.32)
		b.add_box(ns + Vector3(0.0, 0.28, 0.0), Vector3(0.50, 0.56, 0.48), mat_wood_lt)
		b.add_cylinder(ns + Vector3(0.0, 0.68, 0.0), 0.05, 0.08, 0.22, mat_brass, 8)
		b.add_cylinder(ns + Vector3(0.0, 0.84, 0.0), 0.10, 0.15, 0.18, mat_lamp, 8)

		# Full Wooden Wardrobe (دولاب ملابس) flush against West wall near front (x = -4.45, z = -1.65)
		var wd := Vector3(-4.45, floor_y, -1.65)
		b.add_box(wd + Vector3(0.0, 1.02, 0.0), Vector3(0.62, 2.04, 1.48), mat_wood_dk)
		b.add_box(wd + Vector3(0.32, 1.02, -0.36), Vector3(0.02, 1.84, 0.66), mat_wood_lt)
		b.add_box(wd + Vector3(0.32, 1.02, 0.36), Vector3(0.02, 1.84, 0.66), mat_wood_lt)
		b.add_box(wd + Vector3(0.34, 1.02, -0.06), Vector3(0.025, 0.18, 0.025), mat_brass)
		b.add_box(wd + Vector3(0.34, 1.02, 0.06), Vector3(0.025, 0.18, 0.025), mat_brass)
	InteriorMeshBatcher.add_box_collider(col_body, "BedCol", Vector3(-3.75, floor_y + 0.32, -6.25), Vector3(2.02, 0.64, 1.48))
	InteriorMeshBatcher.add_box_collider(col_body, "NightstandCol", Vector3(-4.48, floor_y + 0.28, -7.32), Vector3(0.52, 0.56, 0.50))
	InteriorMeshBatcher.add_box_collider(col_body, "WardrobeCol", Vector3(-4.45, floor_y + 1.02, -1.65), Vector3(0.64, 2.04, 1.50))

	# ------------------------------------------------------------------
	# 4. AUTHENTIC SUDANESE WALL DECOR, CURTAINS & CORNER PLANTS (FLAT AGAINST WALLS!)
	# ------------------------------------------------------------------
	if b != null:
		# Colorful woven Sudanese palm-leaf food covers (أطباق سعف ملونة) mounted FLAT on East wall (x = +4.80)
		var tabaq_cols: Array[Color] = [
			Color(0.84, 0.18, 0.16), Color(0.92, 0.74, 0.18),
			Color(0.12, 0.54, 0.28), Color(0.16, 0.30, 0.66),
		]
		var tabaq_pts: Array[Vector3] = [
			Vector3(4.80, floor_y + 2.05, -4.45),
			Vector3(4.80, floor_y + 2.25, -5.25),
			Vector3(4.80, floor_y + 2.25, -3.65),
			Vector3(4.80, floor_y + 1.65, -4.95),
			Vector3(4.80, floor_y + 1.65, -3.95),
		]
		for ti in range(tabaq_pts.size()):
			var rad := 0.32 if ti == 0 else 0.22
			var m_out := InteriorMeshBatcher.get_color_mat("hi_tbq_%d" % (ti % 4), tabaq_cols[ti % 4], 0.85)
			var m_in := InteriorMeshBatcher.get_color_mat("hi_tbq_%d" % ((ti + 1) % 4), tabaq_cols[(ti + 1) % 4], 0.85)
			b.add_cylinder(tabaq_pts[ti], rad, rad, 0.035, m_out, 12, 0.0, PI * 0.5)
			b.add_cylinder(tabaq_pts[ti] + Vector3(-0.02, 0.0, 0.0), rad * 0.58, rad * 0.58, 0.025, m_in, 10, 0.0, PI * 0.5)

		# Framed Sudanese Calligraphy / Nile Art mounted FLUSH against North wall (z = -7.80)
		var frame_p := Vector3(1.85, floor_y + 2.08, -7.80)
		b.add_box(frame_p, Vector3(1.66, 0.96, 0.045), mat_wood_dk)
		b.add_box(frame_p + Vector3(0.0, 0.0, 0.022), Vector3(1.52, 0.82, 0.02), InteriorMeshBatcher.get_color_mat("hi_art_bg", Color(0.08, 0.34, 0.24), 0.72))
		b.add_box(frame_p + Vector3(0.0, 0.0, 0.034), Vector3(1.44, 0.74, 0.01), mat_brass)

		# Window Curtains (ستائر) framing West Window (x = -4.78, z = -4.0, width 1.68m)
		b.add_cylinder(Vector3(-4.74, floor_y + 2.42, -4.0), 0.02, 0.02, 2.25, mat_brass, 6, PI * 0.5, 0.0)
		b.add_box(Vector3(-4.76, floor_y + 1.56, -4.98), Vector3(0.08, 1.72, 0.38), mat_curtain)
		b.add_box(Vector3(-4.76, floor_y + 1.56, -3.02), Vector3(0.08, 1.72, 0.38), mat_curtain)

		# Corner Potted Plants (North-East & South-East corners inside Diwan)
		for ppos in [Vector3(4.25, floor_y, -7.25), Vector3(4.25, floor_y, -0.78)]:
			b.add_cylinder(ppos + Vector3(0.0, 0.22, 0.0), 0.20, 0.14, 0.44, mat_clay, 8)
			for li in range(5):
				var ang := float(li) * TAU / 5.0
				b.add_sphere(ppos + Vector3(cos(ang) * 0.14, 0.56 + float(li % 2) * 0.10, sin(ang) * 0.14), 0.16, mat_leaf, Vector3(1.2, 0.65, 1.2), 6, 4)

		# ------------------------------------------------------------------
		# 5. COURTYARD VERANDA ZEER WATER JAR (زير ماء فخاري) & VERANDA SEATING
		# ------------------------------------------------------------------
		var zp := Vector3(-3.55, 0.0, 1.05)
		# Iron tripod stand
		b.add_cylinder(zp + Vector3(0.0, 0.38, 0.0), 0.26, 0.30, 0.04, mat_iron, 10)
		for li in range(4):
			var ang := float(li) * PI * 0.5 + 0.4
			b.add_cylinder(zp + Vector3(cos(ang) * 0.24, 0.22, sin(ang) * 0.24), 0.02, 0.02, 0.44, mat_iron, 6)
		# Terracotta clay Zeer body + tapered neck + lid + metal drinking cup (كوز)
		b.add_sphere(zp + Vector3(0.0, 0.58, 0.0), 0.27, mat_clay, Vector3(1.0, 1.15, 1.0), 10, 6)
		b.add_cylinder(zp + Vector3(0.0, 0.88, 0.0), 0.18, 0.21, 0.12, mat_clay, 10)
		b.add_cylinder(zp + Vector3(0.0, 0.96, 0.0), 0.20, 0.20, 0.03, mat_wood_lt, 10)
		b.add_cylinder(zp + Vector3(0.0, 1.02, 0.0), 0.045, 0.04, 0.09, mat_brass, 8)

		# Two neat veranda wooden chairs & small tea table (clear of front door!)
		_add_veranda_chair(b, Vector3(-4.55, 0.0, 1.55), 0.45, mat_wood_dk, mat_cushion)
		_add_veranda_chair(b, Vector3(-2.45, 0.0, 1.55), -0.45, mat_wood_dk, mat_cushion)
		b.add_cylinder(Vector3(-3.50, 0.24, 1.85), 0.34, 0.34, 0.05, mat_wood_lt, 10)
		b.add_cylinder(Vector3(-3.50, 0.12, 1.85), 0.05, 0.08, 0.24, mat_wood_dk, 8)

	InteriorMeshBatcher.add_box_collider(col_body, "ZeerCol", Vector3(-3.55, 0.50, 1.05), Vector3(0.62, 1.0, 0.62))
	InteriorMeshBatcher.add_box_collider(col_body, "VerandaChairL", Vector3(-4.55, 0.42, 1.55), Vector3(0.62, 0.84, 0.62))
	InteriorMeshBatcher.add_box_collider(col_body, "VerandaChairR", Vector3(-2.45, 0.42, 1.55), Vector3(0.62, 0.84, 0.62))

	# Flush Arabic home calligraphy text on North Diwan wall frame
	var art_lbl := Label3D.new()
	art_lbl.name = "DiwanCalligraphyLabel"
	art_lbl.position = Vector3(1.85, floor_y + 2.08, -7.75)
	art_lbl.text = "مَا شَاءَ اللَّهُ لَا قُوَّةَ إِلَّا بِاللَّهِ\nدار عامر بالخير والبركة"
	art_lbl.font_size = 22
	art_lbl.outline_size = 4
	art_lbl.modulate = Color(0.98, 0.90, 0.62)
	art_lbl.pixel_size = 0.0042
	art_lbl.visibility_range_end = 36.0
	add_child(art_lbl)

	var final_mesh: ArrayMesh
	if cached != null:
		final_mesh = cached
	else:
		final_mesh = b.commit()
		_mesh_cache[cache_key] = final_mesh

	var mi := MeshInstance3D.new()
	mi.name = "MergedHouseInterior"
	mi.mesh = final_mesh
	mi.visibility_range_end = vis_range_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _add_sofa(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3, width: float, rot_y: float, mat_wood: Material, mat_fab: Material, mat_cush: Material) -> void:
	var depth := 0.78
	var basis := Basis(Vector3.UP, rot_y)
	if b != null:
		# Helper to transform local sofa point
		b.add_box(pos + basis * Vector3(0.0, 0.22, 0.0), Vector3(width, 0.14, depth), mat_wood, rot_y)
		b.add_box(pos + basis * Vector3(0.0, 0.36, 0.04), Vector3(width - 0.14, 0.16, depth - 0.14), mat_fab, rot_y)
		b.add_box(pos + basis * Vector3(0.0, 0.64, -depth * 0.5 + 0.10), Vector3(width - 0.10, 0.44, 0.16), mat_fab, rot_y)
		for sx: float in [-width * 0.5 + 0.06, width * 0.5 - 0.06]:
			b.add_box(pos + basis * Vector3(sx, 0.42, 0.0), Vector3(0.11, 0.48, depth), mat_wood, rot_y)
		# Decorative accent cushions
		var n_c := maxi(1, int(round(width / 0.75)))
		for ci in range(n_c):
			var cx := -width * 0.32 + (float(ci) + 0.5) * (width * 0.64 / float(n_c)) if n_c > 1 else 0.0
			b.add_box(pos + basis * Vector3(cx, 0.56, -depth * 0.5 + 0.22), Vector3(0.32, 0.26, 0.11), mat_cush, rot_y)
	# Axis-aligned collider matching sofa orientation
	var sz := Vector3(width, 0.84, depth) if absf(cos(rot_y)) > 0.5 else Vector3(depth, 0.84, width)
	InteriorMeshBatcher.add_box_collider(col_body, cname, pos + Vector3(0.0, 0.42, 0.0), sz)


func _add_veranda_chair(b: InteriorMeshBatcher, pos: Vector3, rot_y: float, mat_wood: Material, mat_cush: Material) -> void:
	var basis := Basis(Vector3.UP, rot_y)
	b.add_box(pos + basis * Vector3(0.0, 0.40, 0.0), Vector3(0.56, 0.07, 0.54), mat_wood, rot_y)
	b.add_box(pos + basis * Vector3(0.0, 0.46, 0.0), Vector3(0.50, 0.06, 0.48), mat_cush, rot_y)
	b.add_box(pos + basis * Vector3(0.0, 0.72, -0.24), Vector3(0.56, 0.54, 0.07), mat_wood, rot_y)
	for sx: float in [-0.24, 0.24]:
		for sz: float in [-0.22, 0.22]:
			b.add_box(pos + basis * Vector3(sx, 0.20, sz), Vector3(0.06, 0.40, 0.06), mat_wood, rot_y)
