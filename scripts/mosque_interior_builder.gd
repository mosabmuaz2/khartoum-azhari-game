extends Node3D
class_name MosqueInteriorBuilder

## High-FPS Sudanese Mosque Interior Builder for Godot 4.7.2.
## Generates a rich, authentic prayer hall merged into 1 static-cached multi-surface ArrayMesh:
## - Patterned burgundy-emerald Islamic prayer carpet with horizontal white/gold Saf lines facing Qibla (-Z)
## - Recessed arched ornamental Mihrab with golden accent OmniLight3D
## - Detailed stepped wooden Minbar with side handrails, carved panels & gilded canopy dome
## - Side-wall wooden Quran bookshelves stocked with colorful Qurans/books + X-frame Quran stands
## - Framed Arabic calligraphy plaques (لوحات آيات وأسماء الله الحسنى)
## - Hanging brass chandeliers + entrance wooden shoe racks (جزّامات)
## - Interactive Area3D MosquePrayerZone (group "mosque_prayer_zones") for [E] Kneeling_Pray prayer sequence.

@export var hall_width: float = 17.4
@export var hall_depth: float = 15.4
@export var hall_height: float = 5.3
@export var floor_y: float = 0.10
@export var mosque_title: String = "مسجد الأزهري"
@export var add_internal_pillars: bool = false
@export var vis_range_end: float = 95.0

static var _mesh_cache: Dictionary = {}
var _built: bool = false


func _ready() -> void:
	add_to_group("mosque_interiors")
	build_interior()


func build_interior() -> void:
	if _built:
		return
	_built = true

	var col_body := StaticBody3D.new()
	col_body.name = "MosqueInteriorCollision"
	add_child(col_body)

	var cache_key := "mq_%.1f_%.1f_%.1f_%.2f_%s" % [hall_width, hall_depth, hall_height, floor_y, str(add_internal_pillars)]
	var cached := _mesh_cache.get(cache_key) as ArrayMesh
	var b: InteriorMeshBatcher = null if cached != null else InteriorMeshBatcher.new()

	var hw := hall_width * 0.5
	var hd := hall_depth * 0.5
	var qibla_z := -hd + 0.25
	var entry_z := hd - 0.35

	var mat_marble := InteriorMeshBatcher.get_pbr_mat("mq_marble", "res://assets/textures/ceramic_tiles", Color(0.95, 0.92, 0.85), 0.38, Vector3(0.5, 0.5, 0.5))
	var mat_emerald := InteriorMeshBatcher.get_color_mat("mq_emerald", Color(0.06, 0.36, 0.23), 0.55, 0.08)
	var mat_gold := InteriorMeshBatcher.get_color_mat("mq_gold", Color(0.86, 0.70, 0.26), 0.30, 0.78)
	var mat_wood_dk := InteriorMeshBatcher.get_pbr_mat("mq_wood_dk", "res://assets/textures/wood", Color(0.46, 0.28, 0.16), 0.65, Vector3(0.8, 0.8, 0.8))
	var mat_wood_lt := InteriorMeshBatcher.get_pbr_mat("mq_wood_lt", "res://assets/textures/wood", Color(0.68, 0.46, 0.26), 0.68, Vector3(0.8, 0.8, 0.8))
	var mat_cream := InteriorMeshBatcher.get_pbr_mat("mq_cream", "res://assets/textures/plaster", Color(0.96, 0.92, 0.84), 0.80, Vector3(0.4, 0.4, 0.4))
	var mat_glow := InteriorMeshBatcher.get_color_mat("mq_glow", Color(1.0, 0.94, 0.78), 0.25, 0.0, Color(1.0, 0.88, 0.62), 2.2)
	var mat_carpet := InteriorMeshBatcher.get_prayer_carpet_mat(maxf(4.0, round(hall_width / 1.45)), maxf(4.0, round((hall_depth - 2.2) / 1.85)))

	var book_mats: Array[StandardMaterial3D] = [
		InteriorMeshBatcher.get_color_mat("mq_bk_green", Color(0.08, 0.38, 0.20), 0.70),
		InteriorMeshBatcher.get_color_mat("mq_bk_red", Color(0.54, 0.12, 0.14), 0.70),
		InteriorMeshBatcher.get_color_mat("mq_bk_navy", Color(0.10, 0.18, 0.42), 0.70),
		InteriorMeshBatcher.get_color_mat("mq_bk_gold", Color(0.76, 0.58, 0.20), 0.55, 0.25),
		InteriorMeshBatcher.get_color_mat("mq_bk_teal", Color(0.09, 0.36, 0.40), 0.70),
	]
	var mat_page := InteriorMeshBatcher.get_color_mat("mq_page", Color(0.96, 0.94, 0.86), 0.88)
	var mat_shoe_a := InteriorMeshBatcher.get_color_mat("mq_shoe_a", Color(0.22, 0.14, 0.10), 0.75)
	var mat_shoe_b := InteriorMeshBatcher.get_color_mat("mq_shoe_b", Color(0.14, 0.15, 0.18), 0.75)

	# 1. Rich Patterned Prayer Carpet (سجاد الصلاة) with ornamental border & Saf rows facing -Z
	var carp_w := hall_width - 1.2
	var carp_d := hall_depth - 2.4
	var carp_z := -0.45
	if b != null:
		b.add_box(Vector3(0.0, floor_y + 0.014, carp_z), Vector3(carp_w, 0.024, carp_d), mat_carpet)
		# Marble entry threshold border strip at the entrance
		b.add_box(Vector3(0.0, floor_y + 0.018, entry_z - 0.15), Vector3(3.6, 0.036, 0.45), mat_marble)

	# 2. Optional Interior Mosque Arched Columns (for hollowed mosques)
	if add_internal_pillars and hall_width >= 14.0:
		var px := hw * 0.46
		var pz_list := [-hd * 0.30, hd * 0.30]
		for sx: float in [-1.0, 1.0]:
			for pz: float in pz_list:
				var ppos := Vector3(sx * px, floor_y + hall_height * 0.5, pz)
				if b != null:
					b.add_cylinder(ppos, 0.28, 0.31, hall_height, mat_cream, 10)
					b.add_box(Vector3(sx * px, floor_y + 0.22, pz), Vector3(0.76, 0.44, 0.76), mat_marble)
					b.add_box(Vector3(sx * px, floor_y + hall_height - 0.26, pz), Vector3(0.82, 0.36, 0.82), mat_gold)
				InteriorMeshBatcher.add_box_collider(col_body, "PillarCol_%.0f_%.0f" % [sx * 10, pz * 10], ppos, Vector3(0.62, hall_height, 0.62))

	# 3. Recessed Arched Ornamental Mihrab (المحراب) centered on Qibla wall (-Z)
	var mihrab_w := clampf(hall_width * 0.20, 2.5, 3.6)
	var mihrab_h := clampf(hall_height * 0.78, 3.6, 4.8)
	var mihrab_z := qibla_z + 0.32
	if b != null:
		# Outer marble surround frame
		b.add_box(Vector3(-mihrab_w * 0.5, floor_y + mihrab_h * 0.5, mihrab_z), Vector3(0.42, mihrab_h, 0.65), mat_marble)
		b.add_box(Vector3(mihrab_w * 0.5, floor_y + mihrab_h * 0.5, mihrab_z), Vector3(0.42, mihrab_h, 0.65), mat_marble)
		b.add_box(Vector3(0.0, floor_y + mihrab_h + 0.22, mihrab_z), Vector3(mihrab_w + 0.84, 0.46, 0.72), mat_emerald)
		b.add_box(Vector3(0.0, floor_y + mihrab_h + 0.48, mihrab_z), Vector3(mihrab_w + 0.94, 0.12, 0.78), mat_gold)
		# Recessed ornamental emerald/gold niche back panel
		b.add_box(Vector3(0.0, floor_y + mihrab_h * 0.46, qibla_z + 0.08), Vector3(mihrab_w - 0.32, mihrab_h * 0.92, 0.16), mat_emerald)
		b.add_box(Vector3(0.0, floor_y + mihrab_h * 0.44, qibla_z + 0.17), Vector3(mihrab_w - 0.72, mihrab_h * 0.76, 0.06), mat_cream)
		# Flanking fluted gold-capped colonnettes
		for side: float in [-1.0, 1.0]:
			var cx := side * (mihrab_w * 0.5 - 0.22)
			b.add_cylinder(Vector3(cx, floor_y + mihrab_h * 0.36, mihrab_z + 0.18), 0.10, 0.11, mihrab_h * 0.68, mat_gold, 8)
			b.add_box(Vector3(cx, floor_y + 0.12, mihrab_z + 0.18), Vector3(0.28, 0.24, 0.28), mat_marble)
		# Stepped pointed Islamic arch ribs crowning the niche
		var arch_base_y := floor_y + mihrab_h * 0.68
		var arch_span := mihrab_w * 0.46
		for ai in range(7):
			var t := float(ai) / 6.0
			var ang := lerpf(0.0, PI, t)
			var ax := -cos(ang) * arch_span
			var ay := arch_base_y + sin(ang) * (mihrab_h * 0.24) + (1.0 - absf(t - 0.5) * 2.0) * 0.18
			b.add_box(Vector3(ax, ay, mihrab_z + 0.12), Vector3(0.36, 0.24, 0.42), mat_gold if (ai % 2 == 0) else mat_emerald, 0.0, 0.0, (0.5 - t) * 1.1)
		# Imam prayer mat centered in Mihrab
		b.add_box(Vector3(0.0, floor_y + 0.025, mihrab_z + 0.65), Vector3(1.15, 0.02, 1.65), mat_emerald)
		b.add_box(Vector3(0.0, floor_y + 0.032, mihrab_z + 0.65), Vector3(1.02, 0.015, 1.50), mat_gold)
	InteriorMeshBatcher.add_box_collider(col_body, "MihrabColL", Vector3(-mihrab_w * 0.5, floor_y + mihrab_h * 0.5, mihrab_z), Vector3(0.46, mihrab_h, 0.70))
	InteriorMeshBatcher.add_box_collider(col_body, "MihrabColR", Vector3(mihrab_w * 0.5, floor_y + mihrab_h * 0.5, mihrab_z), Vector3(0.46, mihrab_h, 0.70))

	# Warm golden accent OmniLight inside the Mihrab
	var m_light := OmniLight3D.new()
	m_light.name = "MihrabAccentLight"
	m_light.position = Vector3(0.0, floor_y + mihrab_h * 0.62, mihrab_z + 0.55)
	m_light.light_color = Color(1.0, 0.86, 0.56)
	m_light.light_energy = 1.85
	m_light.omni_range = 7.5
	m_light.shadow_enabled = false
	add_child(m_light)

	# 4. Detailed Stepped Wooden Minbar (المنبر) right beside the Mihrab (+X side)
	var minbar_x := mihrab_w * 0.5 + 1.25
	var minbar_z_back := qibla_z + 0.35
	var minbar_w := 1.16
	var minbar_d := 2.45
	var n_msteps := 6
	var step_h := 0.23
	var step_d := 0.27
	if b != null:
		# Solid carved wooden base & stepped risers facing +Z (rising toward Qibla -Z)
		for si in range(n_msteps):
			var sh := float(si + 1) * step_h
			var sz := minbar_z_back + minbar_d - (float(si) + 0.5) * step_d
			b.add_box(Vector3(minbar_x, floor_y + sh * 0.5, sz), Vector3(minbar_w - 0.12, sh, step_d + 0.02), mat_wood_dk)
			b.add_box(Vector3(minbar_x, floor_y + sh + 0.015, sz), Vector3(minbar_w - 0.08, 0.03, step_d + 0.04), mat_wood_lt)
		# Top speaker platform (جلسة الخطيب) at back
		var plat_h := float(n_msteps) * step_h
		var plat_d := minbar_d - float(n_msteps) * step_d
		var plat_z := minbar_z_back + plat_d * 0.5
		b.add_box(Vector3(minbar_x, floor_y + plat_h * 0.5, plat_z), Vector3(minbar_w, plat_h, plat_d + 0.04), mat_wood_dk)
		# Carved side paneled cheeks + gold inlay trim
		for side: float in [-1.0, 1.0]:
			var sx := minbar_x + side * (minbar_w * 0.5 - 0.04)
			b.add_box(Vector3(sx, floor_y + plat_h * 0.5 + 0.25, minbar_z_back + minbar_d * 0.5), Vector3(0.08, plat_h + 0.50, minbar_d), mat_wood_dk)
			b.add_box(Vector3(sx + side * 0.042, floor_y + plat_h * 0.55, minbar_z_back + minbar_d * 0.45), Vector3(0.02, 0.65, minbar_d * 0.68), mat_gold)
			# Sloped wooden handrails climbing up both sides
			b.add_bar(
				Vector3(sx, floor_y + 0.92, minbar_z_back + minbar_d),
				Vector3(sx, floor_y + plat_h + 0.92, minbar_z_back + plat_d),
				0.06, 0.06, mat_wood_lt
			)
		# Entrance portal arch at front of Minbar
		var front_z := minbar_z_back + minbar_d
		for side: float in [-1.0, 1.0]:
			b.add_box(Vector3(minbar_x + side * (minbar_w * 0.5 - 0.05), floor_y + 1.12, front_z), Vector3(0.10, 2.24, 0.12), mat_wood_lt)
		b.add_box(Vector3(minbar_x, floor_y + 2.26, front_z), Vector3(minbar_w + 0.08, 0.22, 0.16), mat_gold)
		# 4 Canopy columns + carved top dome (قبة المنبر)
		var can_h := 1.65
		for sx_s: float in [-1.0, 1.0]:
			for sz_s: float in [-1.0, 1.0]:
				b.add_box(
					Vector3(minbar_x + sx_s * (minbar_w * 0.44), floor_y + plat_h + can_h * 0.5, plat_z + sz_s * (plat_d * 0.40)),
					Vector3(0.09, can_h, 0.09), mat_wood_lt
				)
		var can_top := floor_y + plat_h + can_h
		b.add_box(Vector3(minbar_x, can_top + 0.08, plat_z), Vector3(minbar_w + 0.14, 0.16, plat_d + 0.14), mat_wood_dk)
		b.add_sphere(Vector3(minbar_x, can_top + 0.22, plat_z), 0.44, mat_emerald, Vector3(1.0, 0.85, 1.0), 10, 6)
		b.add_cylinder(Vector3(minbar_x, can_top + 0.68, plat_z), 0.02, 0.05, 0.28, mat_gold, 6)
	InteriorMeshBatcher.add_box_collider(
		col_body, "MinbarCol",
		Vector3(minbar_x, floor_y + 1.05, minbar_z_back + minbar_d * 0.5),
		Vector3(minbar_w + 0.06, 2.1, minbar_d + 0.06)
	)

	# 5. Wooden Quran Bookshelves (أرفف مصاحف) along East & West walls + X-frame Quran Stands (كرسي مصحف)
	var shelf_z_positions: Array[float] = []
	if hall_depth >= 14.0:
		shelf_z_positions = [-hd * 0.52, 0.0, hd * 0.48]
	else:
		shelf_z_positions = [-hd * 0.25, hd * 0.30]

	for side: float in [-1.0, 1.0]:
		var sx := side * (hw - 0.34)
		for sz_idx in range(shelf_z_positions.size()):
			var sz := shelf_z_positions[sz_idx]
			if b != null:
				_add_quran_bookshelf(b, Vector3(sx, floor_y, sz), side < 0.0, mat_wood_dk, mat_wood_lt, book_mats)
			InteriorMeshBatcher.add_box_collider(col_body, "BookshelfCol_%s_%d" % ["W" if side < 0.0 else "E", sz_idx], Vector3(sx, floor_y + 0.92, sz), Vector3(0.42, 1.84, 1.65))

	# Wooden X-frame Quran stands (رحل / كرسي مصحف) with open Mushafs in the front row
	var stand_xs: Array[float] = [-mihrab_w * 0.5 - 1.35, -mihrab_w * 0.5 - 2.65, minbar_x + 1.45]
	for stx in stand_xs:
		if absf(stx) < hw - 1.2 and b != null:
			_add_quran_stand(b, Vector3(stx, floor_y, qibla_z + 1.45), mat_wood_lt, mat_page, mat_gold)

	# 6. Entrance Wooden Shoe Racks (جزّامات) flanking the South entrance doors
	for side: float in [-1.0, 1.0]:
		var rx := side * clampf(hw * 0.42, 2.5, 4.6)
		var rz := entry_z - 0.32
		if b != null:
			_add_shoe_rack(b, Vector3(rx, floor_y, rz), mat_wood_dk, mat_wood_lt, mat_shoe_a, mat_shoe_b)
		InteriorMeshBatcher.add_box_collider(col_body, "ShoeRackIn_%s" % ("L" if side < 0.0 else "R"), Vector3(rx, floor_y + 0.48, rz), Vector3(1.65, 0.96, 0.42))

	# 7. Hanging Brass Mosque Chandeliers (ثريات المسجد) + Warm Interior Lighting
	var chan_z_list: Array[float] = [-hd * 0.32, hd * 0.25]
	var chan_y := floor_y + hall_height - 1.15
	for ci in range(chan_z_list.size()):
		var cz := chan_z_list[ci]
		if b != null:
			_add_chandelier(b, Vector3(0.0, chan_y, cz), floor_y + hall_height, mat_gold, mat_glow)
		var clight := OmniLight3D.new()
		clight.name = "ChandelierLight_%d" % ci
		clight.position = Vector3(0.0, chan_y - 0.25, cz)
		clight.light_color = Color(1.0, 0.92, 0.74)
		clight.light_energy = 1.65
		clight.omni_range = maxf(13.0, hall_width * 0.92)
		clight.shadow_enabled = false
		add_child(clight)

	# 8. Framed Arabic Calligraphy Plaques (لوحات آيات وأسماء الله الحسنى) flat on Qibla wall
	var plaque_x := clampf(hw * 0.56, 3.0, 5.4)
	var plaque_y := floor_y + minf(3.35, hall_height * 0.62)
	var plaques: Array[Dictionary] = [
		{"pos": Vector3(-plaque_x, plaque_y, qibla_z + 0.08), "rot_y": 0.0, "text": "الله جلّ جلاله\nبسم الله الرحمن الرحيم", "w": 2.1, "h": 0.95},
		{"pos": Vector3(plaque_x, plaque_y, qibla_z + 0.08), "rot_y": 0.0, "text": "محمد رسول الله ﷺ\nإن الصلاة كانت على المؤمنين كتاباً موقوتاً", "w": 2.3, "h": 0.95},
		{"pos": Vector3(0.0, floor_y + minf(mihrab_h + 0.92, hall_height - 0.55), qibla_z + 0.08), "rot_y": 0.0, "text": "﴿ قَدْ نَرَىٰ تَقَلُّبَ وَجْهِكَ فِي السَّمَاءِ ﴾", "w": 3.4, "h": 0.65},
	]
	for pi in range(plaques.size()):
		var pq := plaques[pi]
		var ppos: Vector3 = pq["pos"]
		var pw: float = float(pq["w"])
		var ph: float = float(pq["h"])
		if b != null:
			b.add_box(ppos, Vector3(pw + 0.14, ph + 0.14, 0.05), mat_gold)
			b.add_box(ppos + Vector3(0.0, 0.0, 0.025), Vector3(pw, ph, 0.03), mat_emerald)
		var lbl := Label3D.new()
		lbl.name = "CalligraphyPlaque_%d" % pi
		lbl.position = ppos + Vector3(0.0, 0.0, 0.055)
		lbl.text = String(pq["text"])
		lbl.font_size = 28
		lbl.outline_size = 5
		lbl.modulate = Color(0.98, 0.89, 0.56)
		lbl.pixel_size = 0.0048
		lbl.visibility_range_end = 55.0
		add_child(lbl)

	# 9. Commit 1 single static-cached multi-surface ArrayMesh for the entire mosque interior!
	var final_mesh: ArrayMesh
	if cached != null:
		final_mesh = cached
	else:
		final_mesh = b.commit()
		_mesh_cache[cache_key] = final_mesh

	var mi := MeshInstance3D.new()
	mi.name = "MergedMosqueInterior"
	mi.mesh = final_mesh
	mi.visibility_range_end = vis_range_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# 10. Interactive Prayer / Prostration Zone (Area3D) covering the prayer carpet
	var zone := Area3D.new()
	zone.name = "MosquePrayerZone"
	zone.add_to_group("mosque_prayer_zones")
	zone.monitoring = true
	zone.monitorable = true
	zone.position = Vector3(0.0, floor_y + 1.1, carp_z)
	zone.set_meta("mosque_title", mosque_title)
	zone.set_meta("qibla_local_dir", Vector3(0.0, 0.0, -1.0))
	var zcs := CollisionShape3D.new()
	zcs.name = "ZoneShape"
	var zbs := BoxShape3D.new()
	zbs.size = Vector3(carp_w - 0.4, 2.2, carp_d - 0.6)
	zcs.shape = zbs
	zone.add_child(zcs)
	add_child(zone)


func _add_quran_bookshelf(b: InteriorMeshBatcher, base_pos: Vector3, on_west_wall: bool, mat_dk: Material, mat_lt: Material, book_mats: Array[StandardMaterial3D]) -> void:
	var h := 1.82
	var depth := 0.36
	var width := 1.56
	var face_x: float = 1.0 if on_west_wall else -1.0
	# Back panel & side uprights
	b.add_box(base_pos + Vector3(-face_x * (depth * 0.44), h * 0.5, 0.0), Vector3(0.04, h, width), mat_dk)
	for sz: float in [-width * 0.48, width * 0.48]:
		b.add_box(base_pos + Vector3(0.0, h * 0.5, sz), Vector3(depth, h, 0.06), mat_dk)
	# 5 horizontal shelves + rows of colorful Qurans & Islamic books
	for tier in range(5):
		var ty := 0.10 + float(tier) * 0.42
		b.add_box(base_pos + Vector3(0.0, ty, 0.0), Vector3(depth, 0.04, width), mat_lt)
		if tier < 4:
			for bi in range(11):
				var bz := -width * 0.42 + float(bi) * 0.125
				var bh := 0.24 + float((bi * 3 + tier) % 3) * 0.03
				var bmat := book_mats[(bi + tier * 2) % book_mats.size()]
				b.add_box(base_pos + Vector3(face_x * 0.03, ty + 0.02 + bh * 0.5, bz), Vector3(0.22, bh, 0.085), bmat)


func _add_quran_stand(b: InteriorMeshBatcher, pos: Vector3, mat_wood: Material, mat_page: Material, mat_gold: Material) -> void:
	# X-frame folding wooden Rehal (كرسي مصحف) + open Mushaf
	b.add_box(pos + Vector3(0.0, 0.22, 0.0), Vector3(0.46, 0.035, 0.44), mat_wood, 0.0, 0.62, 0.0)
	b.add_box(pos + Vector3(0.0, 0.22, 0.0), Vector3(0.46, 0.035, 0.44), mat_wood, 0.0, -0.62, 0.0)
	b.add_box(pos + Vector3(0.0, 0.34, -0.07), Vector3(0.36, 0.025, 0.16), mat_page, 0.0, 0.35, 0.0)
	b.add_box(pos + Vector3(0.0, 0.34, 0.07), Vector3(0.36, 0.025, 0.16), mat_page, 0.0, -0.35, 0.0)
	b.add_box(pos + Vector3(0.0, 0.32, 0.0), Vector3(0.38, 0.02, 0.04), mat_gold)


func _add_shoe_rack(b: InteriorMeshBatcher, pos: Vector3, mat_dk: Material, mat_lt: Material, mat_sa: Material, mat_sb: Material) -> void:
	var w := 1.60
	var h := 0.92
	var d := 0.38
	for sx: float in [-w * 0.48, w * 0.48]:
		b.add_box(pos + Vector3(sx, h * 0.5, 0.0), Vector3(0.06, h, d), mat_dk)
	for tier in range(3):
		var ty := 0.12 + float(tier) * 0.34
		b.add_box(pos + Vector3(0.0, ty, 0.0), Vector3(w, 0.04, d), mat_lt)
		for pair in range(4):
			var px := -0.58 + float(pair) * 0.38
			var smat := mat_sa if ((pair + tier) % 2 == 0) else mat_sb
			b.add_box(pos + Vector3(px - 0.05, ty + 0.06, 0.02), Vector3(0.09, 0.07, 0.24), smat)
			b.add_box(pos + Vector3(px + 0.06, ty + 0.06, 0.02), Vector3(0.09, 0.07, 0.24), smat)


func _add_chandelier(b: InteriorMeshBatcher, center: Vector3, ceiling_y: float, mat_gold: Material, mat_glow: Material) -> void:
	var rod_h := maxf(0.4, ceiling_y - center.y)
	b.add_cylinder(Vector3(center.x, center.y + rod_h * 0.5, center.z), 0.03, 0.03, rod_h, mat_gold, 6)
	b.add_cylinder(center, 0.18, 0.12, 0.28, mat_gold, 8)
	# Two concentric brass rings with glowing lamp globes
	for ring_idx in range(2):
		var r := 1.05 if ring_idx == 0 else 0.58
		var ry := center.y - 0.05 + float(ring_idx) * 0.28
		var n_lamps := 8 if ring_idx == 0 else 4
		for li in range(n_lamps):
			var ang := float(li) * TAU / float(n_lamps)
			var lx := center.x + cos(ang) * r
			var lz := center.z + sin(ang) * r
			b.add_bar(Vector3(center.x, ry, center.z), Vector3(lx, ry, lz), 0.03, 0.03, mat_gold)
			b.add_sphere(Vector3(lx, ry + 0.09, lz), 0.11, mat_glow, Vector3.ONE, 8, 5)
