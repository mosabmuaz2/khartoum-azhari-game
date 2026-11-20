extends Node3D
class_name MarketInteriorBuilder

## High-FPS Sudanese Food & Grocery Market Interior Builder for Godot 4.7.2.
## Stocks shops & indoor markets with multi-tier shelves, spacious aisles (>= 2.2m clearance),
## burlap sacks (sugar/flour/sorghum), produce crates (tomatoes/bananas/oranges/onions/greens),
## stacked cooking oil bottles, canned goods, spice jars, bread baskets, scales, cash registers,
## and Arabic shop signs — all merged into 1 static-cached multi-surface ArrayMesh!

enum MarketMode {
	COMMERCIAL_STRIP = 0,
	GROCERY_SHOP = 1,
	APARTMENT_GROUND_SHOPS = 2,
}

@export var market_mode: MarketMode = MarketMode.COMMERCIAL_STRIP
@export var floor_y: float = 0.10
@export var vis_range_end: float = 85.0

static var _mesh_cache: Dictionary = {}
var _built: bool = false


func _ready() -> void:
	add_to_group("market_interiors")
	build_market()


func build_market() -> void:
	if _built:
		return
	_built = true

	var col_body := StaticBody3D.new()
	col_body.name = "MarketGoodsCollision"
	add_child(col_body)

	var cache_key := "mkt_%d_%.2f" % [int(market_mode), floor_y]
	var cached := _mesh_cache.get(cache_key) as ArrayMesh
	var b: InteriorMeshBatcher = null if cached != null else InteriorMeshBatcher.new()

	match market_mode:
		MarketMode.COMMERCIAL_STRIP:
			_build_commercial_strip_markets(b, col_body)
		MarketMode.GROCERY_SHOP:
			_build_amary_grocery_shop(b, col_body)
		MarketMode.APARTMENT_GROUND_SHOPS:
			_build_apartment_ground_shops(b, col_body)

	var final_mesh: ArrayMesh
	if cached != null:
		final_mesh = cached
	else:
		final_mesh = b.commit()
		_mesh_cache[cache_key] = final_mesh

	var mi := MeshInstance3D.new()
	mi.name = "MergedMarketGoods"
	mi.mesh = final_mesh
	mi.visibility_range_end = vis_range_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_commercial_strip_markets(b: InteriorMeshBatcher, col_body: StaticBody3D) -> void:
	# 6 bays centered at x = -18.5, -11.1, -3.7, +3.7, +11.1, +18.5 (each 7.1m wide, z in [-3.2, +3.2])
	# Bays 0 (Dukkan), 1 (Bakery), 2 (Restaurant/Produce) are connected via wide >=2.4m interior passages!
	var bay_xs: Array[float] = [-18.5, -11.1, -3.7, 3.7, 11.1, 18.5]
	var hanging_signs: Array[Dictionary] = [
		{"x": -18.5, "text": "سوق المواد الغذائية\nبقالة وتموينات"},
		{"x": -11.1, "text": "خضار وفواكه ومخبز طازج"},
		{"x": -3.7, "text": "سوق الحبوب والبهارات"},
		{"x": 3.7, "text": "صيدلية ومستلزمات صحية"},
		{"x": 11.1, "text": "صالون ومستلزمات عناية"},
		{"x": 18.5, "text": "مستلزمات سيارات وبنشر"},
	]

	for i in range(bay_xs.size()):
		var cx := bay_xs[i]
		# Hanging Arabic interior sign above wide front aisle
		_add_hanging_sign(b, Vector3(cx, 3.05, 1.85), String(hanging_signs[i]["text"]))

		if i <= 2:
			# FULL FOOD & GROCERY MARKET BAYS (wide open front aisle z in [+0.4, +3.2] = 2.8m clearance!)
			# Back multi-tier wall shelf stocked with oil bottles, cans, spice jars
			_add_stocked_shelf(b, Vector3(cx, floor_y, -2.85), 5.6, 2.25, 0.52, i)
			# Side wall produce/grocery displays (tucked cleanly against outer & front window walls so z in [0.1, 2.3] walkway is >= 2.2m wide!)
			if i == 0:
				_add_produce_crate_row(b, col_body, "StripProduce_L", Vector3(cx - 2.95, floor_y, 0.4), true, 3)
				_add_burlap_sacks_cluster(b, col_body, "StripSacks_0", Vector3(cx + 2.45, floor_y, -1.65))
			elif i == 1:
				_add_bread_display(b, col_body, "StripBread_1", Vector3(cx - 2.55, floor_y, -1.65))
				_add_produce_crate_row(b, col_body, "StripProduce_1", Vector3(cx + 2.65, floor_y, -1.65), false, 2)
			else:
				_add_burlap_sacks_cluster(b, col_body, "StripSacks_2", Vector3(cx - 2.45, floor_y, -1.65))
				_add_produce_crate_row(b, col_body, "StripProduce_R", Vector3(cx + 2.95, floor_y, 0.4), false, 3)
			# Counter scale, cash register & bread basket on the repositioned counter (z = -0.65)
			_add_counter_props(b, Vector3(cx, floor_y + 1.04, -0.65), i == 1)
		else:
			# Other strip bays: well-stocked back wall shelves & clean counter props
			_add_stocked_shelf(b, Vector3(cx, floor_y, -2.85), 5.4, 2.15, 0.52, i)
			_add_counter_props(b, Vector3(cx, floor_y + 1.04, -0.65), false)


func _build_amary_grocery_shop(b: InteriorMeshBatcher, col_body: StaticBody3D) -> void:
	# Interior footprint: x in [-4.0, +4.0], z in [-3.0, +3.0], MainCounter moved back to z = -0.75 (3.5m clear aisle!)
	_add_hanging_sign(b, Vector3(0.0, 3.05, 1.85), "سوق المواد الغذائية - عماري سعود\nخضار وفواكه • بقالة • تموينات")
	# Fully stocked back shelf (z = -2.70)
	_add_stocked_shelf(b, Vector3(0.0, floor_y, -2.68), 6.2, 2.28, 0.52, 0)
	# Left wall angled fruit & vegetable crates (x = -3.45, z in [0.1, 2.3])
	_add_produce_crate_row(b, col_body, "AmaryProduceL", Vector3(-3.45, floor_y, 1.25), true, 3)
	# Right wall burlap grain/sugar/flour sacks & oil jugs (x = +3.25, z in [0.4, 2.3])
	_add_burlap_sacks_cluster(b, col_body, "AmarySacksR", Vector3(3.15, floor_y, 1.35))
	# Right back spice & canned goods side rack
	_add_bread_display(b, col_body, "AmaryBreadR", Vector3(3.35, floor_y, -1.65))
	# Counter brass scale, cash register & spice jars on repositioned counter (z = -0.75)
	_add_counter_props(b, Vector3(0.0, floor_y + 1.08, -0.75), true)


func _build_apartment_ground_shops(b: InteriorMeshBatcher, col_body: StaticBody3D) -> void:
	# Two ground-floor grocery/produce shops centered at x = -5.5 and x = +5.5, z in [-4.6, +4.8]
	for si in range(2):
		var cx := -5.5 if si == 0 else 5.5
		var label := "بقالة العمارة — مواد غذائية" if si == 0 else "خضار وفواكه طازجة"
		_add_hanging_sign(b, Vector3(cx, 2.85, 3.45), label)
		# Back multi-tier wall shelf
		_add_stocked_shelf(b, Vector3(cx, floor_y, -4.35), 5.6, 2.20, 0.52, si)
		# Side produce crates & burlap sacks along the outer wall (leaving wide >=2.4m entry aisle!)
		var wall_x := -8.25 if si == 0 else 8.25
		_add_produce_crate_row(b, col_body, "AptShopProduce_%d" % si, Vector3(wall_x, floor_y, 0.8), si == 0, 3)
		_add_burlap_sacks_cluster(b, col_body, "AptShopSacks_%d" % si, Vector3(cx + (1.8 if si == 0 else -1.8), floor_y, -1.2))
		_add_counter_props(b, Vector3(cx, floor_y + 1.00, 1.2), si == 1)


# ==============================================================================
# MERGED 3D MARKET FIXTURES & FOOD GOODS HELPERS
# ==============================================================================
func _add_hanging_sign(b: InteriorMeshBatcher, pos: Vector3, text: String) -> void:
	if b != null:
		var mat_board := InteriorMeshBatcher.get_color_mat("mkt_sign_bg", Color(0.10, 0.34, 0.24), 0.65)
		var mat_trim := InteriorMeshBatcher.get_color_mat("mkt_sign_gold", Color(0.86, 0.70, 0.26), 0.40, 0.55)
		var mat_rod := InteriorMeshBatcher.get_color_mat("mkt_iron", Color(0.20, 0.22, 0.24), 0.45, 0.65)
		b.add_box(pos, Vector3(2.8, 0.56, 0.06), mat_board)
		b.add_box(pos + Vector3(0.0, 0.30, 0.0), Vector3(2.88, 0.06, 0.08), mat_trim)
		b.add_box(pos + Vector3(0.0, -0.30, 0.0), Vector3(2.88, 0.06, 0.08), mat_trim)
		for sx: float in [-1.15, 1.15]:
			b.add_cylinder(pos + Vector3(sx, 0.52, 0.0), 0.015, 0.015, 0.52, mat_rod, 6)
	var lbl := Label3D.new()
	lbl.position = pos + Vector3(0.0, 0.0, 0.045)
	lbl.text = text
	lbl.font_size = 26
	lbl.outline_size = 4
	lbl.modulate = Color(1.0, 0.96, 0.82)
	lbl.pixel_size = 0.0044
	lbl.visibility_range_end = 42.0
	add_child(lbl)


func _add_stocked_shelf(b: InteriorMeshBatcher, base_pos: Vector3, width: float, height: float, depth: float, seed_idx: int) -> void:
	if b == null:
		return
	var mat_wood := InteriorMeshBatcher.get_pbr_mat("mkt_wood", "res://assets/textures/wood", Color(0.58, 0.38, 0.22), 0.74, Vector3(0.8, 0.8, 0.8))
	var mat_steel := InteriorMeshBatcher.get_color_mat("mkt_steel", Color(0.32, 0.36, 0.40), 0.48, 0.55)
	var mat_oil := InteriorMeshBatcher.get_color_mat("mkt_oil", Color(0.95, 0.74, 0.12), 0.22, 0.05)
	var mat_cap := InteriorMeshBatcher.get_color_mat("mkt_cap_red", Color(0.82, 0.14, 0.12), 0.45)
	var can_mats: Array[StandardMaterial3D] = [
		InteriorMeshBatcher.get_color_mat("mkt_can_red", Color(0.82, 0.18, 0.15), 0.35, 0.35),
		InteriorMeshBatcher.get_color_mat("mkt_can_blue", Color(0.16, 0.38, 0.74), 0.35, 0.35),
		InteriorMeshBatcher.get_color_mat("mkt_can_green", Color(0.18, 0.58, 0.26), 0.35, 0.35),
		InteriorMeshBatcher.get_color_mat("mkt_can_orange", Color(0.90, 0.48, 0.12), 0.35, 0.35),
		InteriorMeshBatcher.get_color_mat("mkt_can_white", Color(0.92, 0.90, 0.84), 0.45, 0.15),
	]
	var spice_mats: Array[StandardMaterial3D] = [
		InteriorMeshBatcher.get_color_mat("mkt_sp_turm", Color(0.88, 0.62, 0.10), 0.72),
		InteriorMeshBatcher.get_color_mat("mkt_sp_chili", Color(0.76, 0.16, 0.10), 0.72),
		InteriorMeshBatcher.get_color_mat("mkt_sp_hibis", Color(0.48, 0.06, 0.12), 0.72),
		InteriorMeshBatcher.get_color_mat("mkt_sp_cumin", Color(0.56, 0.42, 0.22), 0.72),
	]

	# Steel uprights + 5 wooden shelf boards
	for ux: float in [-width * 0.49, 0.0, width * 0.49]:
		b.add_box(base_pos + Vector3(ux, height * 0.5, 0.0), Vector3(0.06, height, depth), mat_steel)
	for tier in range(5):
		var ty := 0.18 + float(tier) * 0.46
		b.add_box(base_pos + Vector3(0.0, ty, 0.0), Vector3(width, 0.04, depth), mat_wood)
		if tier >= 4:
			continue
		var cols := int(width / 0.36)
		for ci in range(cols):
			var gx := -width * 0.45 + (float(ci) + 0.5) * (width * 0.90 / float(cols))
			var kind := (ci + tier + seed_idx) % 4
			if kind == 0:
				# Golden cooking oil bottles (2-pack)
				for ox: float in [-0.06, 0.06]:
					b.add_cylinder(base_pos + Vector3(gx + ox, ty + 0.16, 0.06), 0.045, 0.052, 0.28, mat_oil, 6)
					b.add_cylinder(base_pos + Vector3(gx + ox, ty + 0.31, 0.06), 0.02, 0.025, 0.05, mat_cap, 6)
			elif kind == 1:
				# Stacked colorful canned goods
				var cmat := can_mats[(ci + tier) % can_mats.size()]
				for ox: float in [-0.07, 0.07]:
					b.add_cylinder(base_pos + Vector3(gx + ox, ty + 0.09, 0.08), 0.052, 0.052, 0.14, cmat, 6)
				b.add_cylinder(base_pos + Vector3(gx, ty + 0.23, 0.08), 0.052, 0.052, 0.14, cmat, 6)
			elif kind == 2:
				# Boxed groceries (tea, pasta, soap, biscuits)
				var bmat := can_mats[(ci * 2 + tier + 1) % can_mats.size()]
				b.add_box(base_pos + Vector3(gx, ty + 0.14, 0.06), Vector3(0.22, 0.24, 0.18), bmat)
			else:
				# Spice jars (كركدي، كركم، شطة، كمون)
				var smat := spice_mats[(ci + tier) % spice_mats.size()]
				for ox: float in [-0.065, 0.065]:
					b.add_cylinder(base_pos + Vector3(gx + ox, ty + 0.11, 0.08), 0.042, 0.048, 0.18, smat, 6)
					b.add_cylinder(base_pos + Vector3(gx + ox, ty + 0.21, 0.08), 0.044, 0.044, 0.03, mat_steel, 6)


func _add_produce_crate_row(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3, on_left_wall: bool, count: int) -> void:
	var crate_len := 0.74
	var total_z := float(count) * (crate_len + 0.08)
	if b != null:
		var mat_crate := InteriorMeshBatcher.get_pbr_mat("mkt_crate", "res://assets/textures/wood", Color(0.68, 0.50, 0.30), 0.85, Vector3(1.0, 1.0, 1.0))
		var produce_mats: Array[StandardMaterial3D] = [
			InteriorMeshBatcher.get_color_mat("mkt_tomato", Color(0.84, 0.16, 0.12), 0.42),
			InteriorMeshBatcher.get_color_mat("mkt_banana", Color(0.95, 0.82, 0.18), 0.52),
			InteriorMeshBatcher.get_color_mat("mkt_orange", Color(0.94, 0.48, 0.08), 0.48),
			InteriorMeshBatcher.get_color_mat("mkt_greens", Color(0.16, 0.56, 0.20), 0.72),
			InteriorMeshBatcher.get_color_mat("mkt_onion", Color(0.76, 0.54, 0.32), 0.65),
		]
		# Slanted wooden stand base
		b.add_box(pos + Vector3(0.0, 0.30, 0.0), Vector3(0.62, 0.60, total_z), mat_crate)
		var tilt := 0.22 if on_left_wall else -0.22
		for i in range(count):
			var cz := -total_z * 0.5 + (float(i) + 0.5) * (total_z / float(count))
			var cpos := pos + Vector3(0.0, 0.68, cz)
			b.add_box(cpos, Vector3(0.58, 0.18, crate_len), mat_crate, 0.0, 0.0, tilt)
			var pmat := produce_mats[i % produce_mats.size()]
			# Heap of fruits/vegetables inside crate
			for fx in [-0.14, 0.0, 0.14]:
				for fz in [-0.20, 0.0, 0.20]:
					b.add_sphere(cpos + Vector3(fx, 0.12, fz), 0.095, pmat, Vector3(1.0, 0.78, 1.0), 6, 4)
	InteriorMeshBatcher.add_box_collider(col_body, cname, pos + Vector3(0.0, 0.42, 0.0), Vector3(0.66, 0.84, total_z))


func _add_burlap_sacks_cluster(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3) -> void:
	if b != null:
		var mat_burlap := InteriorMeshBatcher.get_color_mat("mkt_burlap", Color(0.72, 0.58, 0.38), 0.94)
		var mat_sugar := InteriorMeshBatcher.get_color_mat("mkt_sugar", Color(0.95, 0.94, 0.90), 0.88)
		var mat_sorghum := InteriorMeshBatcher.get_color_mat("mkt_sorghum", Color(0.86, 0.74, 0.48), 0.90)
		var mat_flour := InteriorMeshBatcher.get_color_mat("mkt_flour", Color(0.94, 0.90, 0.80), 0.92)
		var fill_mats := [mat_sugar, mat_sorghum, mat_flour]
		var offsets: Array[Vector3] = [
			Vector3(-0.28, 0.0, -0.22),
			Vector3(0.28, 0.0, -0.18),
			Vector3(0.0, 0.0, 0.26),
		]
		for si in range(offsets.size()):
			var sp := pos + offsets[si]
			b.add_cylinder(sp + Vector3(0.0, 0.34, 0.0), 0.22, 0.27, 0.68, mat_burlap, 8)
			# Rolled burlap cuff + visible grain/sugar/flour mound on top
			b.add_cylinder(sp + Vector3(0.0, 0.68, 0.0), 0.235, 0.22, 0.08, mat_burlap, 8)
			b.add_sphere(sp + Vector3(0.0, 0.70, 0.0), 0.19, fill_mats[si], Vector3(1.0, 0.45, 1.0), 7, 4)
	InteriorMeshBatcher.add_box_collider(col_body, cname, pos + Vector3(0.0, 0.38, 0.0), Vector3(1.12, 0.76, 1.05))


func _add_bread_display(b: InteriorMeshBatcher, col_body: StaticBody3D, cname: String, pos: Vector3) -> void:
	if b != null:
		var mat_wicker := InteriorMeshBatcher.get_color_mat("mkt_wicker", Color(0.74, 0.56, 0.30), 0.88)
		var mat_bread := InteriorMeshBatcher.get_color_mat("mkt_bread", Color(0.84, 0.60, 0.28), 0.82)
		b.add_box(pos + Vector3(0.0, 0.36, 0.0), Vector3(0.88, 0.72, 0.66), mat_wicker)
		for bx in [-0.24, 0.0, 0.24]:
			for bz in [-0.14, 0.14]:
				b.add_sphere(pos + Vector3(bx, 0.78, bz), 0.12, mat_bread, Vector3(0.85, 0.55, 1.35), 6, 4)
	InteriorMeshBatcher.add_box_collider(col_body, cname, pos + Vector3(0.0, 0.42, 0.0), Vector3(0.92, 0.84, 0.70))


func _add_counter_props(b: InteriorMeshBatcher, top_pos: Vector3, with_bread_basket: bool) -> void:
	if b == null:
		return
	var mat_brass := InteriorMeshBatcher.get_color_mat("mkt_brass", Color(0.84, 0.68, 0.24), 0.32, 0.75)
	var mat_reg := InteriorMeshBatcher.get_color_mat("mkt_cashreg", Color(0.18, 0.20, 0.24), 0.45, 0.35)
	var mat_screen := InteriorMeshBatcher.get_color_mat("mkt_reg_scr", Color(0.20, 0.78, 0.45), 0.30, 0.0, Color(0.20, 0.78, 0.45), 0.9)
	# Counter scale (ميزان)
	var sc := top_pos + Vector3(-0.95, 0.0, 0.0)
	b.add_box(sc + Vector3(0.0, 0.06, 0.0), Vector3(0.32, 0.12, 0.26), mat_brass)
	b.add_cylinder(sc + Vector3(0.0, 0.20, 0.0), 0.025, 0.03, 0.20, mat_brass, 6)
	b.add_cylinder(sc + Vector3(0.0, 0.32, 0.0), 0.18, 0.14, 0.04, mat_brass, 8)
	# Cash register (كاشير)
	var rg := top_pos + Vector3(0.95, 0.0, 0.0)
	b.add_box(rg + Vector3(0.0, 0.09, 0.0), Vector3(0.42, 0.18, 0.36), mat_reg)
	b.add_box(rg + Vector3(0.0, 0.24, -0.05), Vector3(0.36, 0.16, 0.20), mat_reg)
	b.add_box(rg + Vector3(0.0, 0.26, 0.055), Vector3(0.22, 0.08, 0.02), mat_screen)
	if with_bread_basket:
		var mat_wicker := InteriorMeshBatcher.get_color_mat("mkt_wicker", Color(0.74, 0.56, 0.30), 0.88)
		var mat_bread := InteriorMeshBatcher.get_color_mat("mkt_bread", Color(0.84, 0.60, 0.28), 0.82)
		b.add_cylinder(top_pos + Vector3(0.0, 0.07, 0.0), 0.24, 0.19, 0.14, mat_wicker, 8)
		b.add_sphere(top_pos + Vector3(-0.07, 0.16, 0.0), 0.09, mat_bread, Vector3(0.9, 0.6, 1.2), 6, 4)
		b.add_sphere(top_pos + Vector3(0.08, 0.16, 0.02), 0.09, mat_bread, Vector3(0.9, 0.6, 1.2), 6, 4)
