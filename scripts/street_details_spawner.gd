extends Node3D
class_name StreetDetailsSpawner

## Populates Al-Azhari streets with gritty Khartoum micro-details:
## weathered Arabic wall posters/flyers, trash bins with scattered litter/cans/boxes,
## stacked cement blocks, tires near the banshar, tangled power cables, and street signs.

var _poster_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	if OS.has_feature("web"):
		call_deferred("_spawn_web_progressive")
		return
	_build_poster_materials()
	_spawn_wall_posters()
	_spawn_trash_clusters()
	_spawn_cement_block_piles()
	_spawn_street_signs()
	_spawn_tangled_wires()
	_spawn_carryable_props()
	_apply_culling_and_shadow_budget(self)


func _spawn_web_progressive() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_poster_materials()
	_spawn_wall_posters()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_spawn_trash_clusters()
	_spawn_cement_block_piles()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_spawn_street_signs()
	_spawn_carryable_props()
	_apply_culling_and_shadow_budget(self)


func _apply_culling_and_shadow_budget(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if gi.visibility_range_end <= 0.0:
			gi.visibility_range_end = 42.0
			if gi is MeshInstance3D:
				var mi := gi as MeshInstance3D
				if mi.mesh is QuadMesh or mi.mesh is BoxMesh and (mi.mesh as BoxMesh).size.y < 0.25:
					gi.visibility_range_end = 28.0
	elif node is Label3D:
		(node as GeometryInstance3D).visibility_range_end = 28.0
	for child in node.get_children():
		_apply_culling_and_shadow_budget(child)


func _build_poster_materials() -> void:
	var palettes: Array[Array] = [
		[Color(0.95, 0.90, 0.72), Color(0.78, 0.22, 0.18)],
		[Color(0.86, 0.93, 0.96), Color(0.14, 0.44, 0.74)],
		[Color(0.94, 0.88, 0.78), Color(0.16, 0.52, 0.28)],
		[Color(0.96, 0.84, 0.52), Color(0.24, 0.18, 0.16)],
	]
	for p in palettes:
		var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
		var base_col: Color = p[0]
		var accent_col: Color = p[1]
		for y in range(96):
			for x in range(64):
				var noise := ((x * 37 + y * 91) % 19) / 190.0
				var col := base_col.darkened(noise)
				if y < 22:
					col = accent_col.darkened(noise * 0.5)
				elif y > 84 and ((x + y) % 11 < 3):
					# Torn weathered bottom edge
					col = Color(0.76, 0.68, 0.54, 0.0)
				img.set_pixel(x, y, col)
		var tex := ImageTexture.create_from_image(img)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.roughness = 0.9
		_poster_materials.append(mat)


func _spawn_wall_posters() -> void:
	var poster_specs := [
		{"pos": Vector3(17.5, 1.85, -12.90), "rot_y": 0.0, "text": "عروض\nدكان الأزهري"},
		{"pos": Vector3(24.9, 1.95, -12.90), "rot_y": 0.0, "text": "مخبز الخرطوم\nعيش سخن"},
		{"pos": Vector3(32.3, 1.85, -12.90), "rot_y": 0.0, "text": "فول وطعمية\nفطور سوداني"},
		{"pos": Vector3(54.5, 1.85, -12.90), "rot_y": 0.0, "text": "بنشر الأزهري\nلحام لساتك"},
		{"pos": Vector3(-14.8, 1.75, 24.0), "rot_y": PI * 0.5, "text": "دروس تقوية\nرياضيات"},
		{"pos": Vector3(14.8, 1.75, 42.0), "rot_y": -PI * 0.5, "text": "صيانة\nمكيفات وثلاجات"},
		{"pos": Vector3(12.0, 1.80, -8.32), "rot_y": 0.0, "text": "مهرجان\nالأزهري الرياضي"},
		{"pos": Vector3(-12.0, 1.80, -8.32), "rot_y": 0.0, "text": "مواصلات\nالأزهري - السوق"},
	]
	for idx in range(poster_specs.size()):
		var spec: Dictionary = poster_specs[idx]
		var holder := Node3D.new()
		holder.position = spec["pos"]
		holder.rotation.y = spec["rot_y"]
		holder.rotation.z = randf_range(-0.06, 0.06)

		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.75, 1.05)
		quad.mesh = qm
		quad.material_override = _poster_materials[idx % _poster_materials.size()]
		holder.add_child(quad)

		var lbl := Label3D.new()
		lbl.text = spec["text"]
		lbl.font_size = 24
		lbl.outline_size = 5
		lbl.position = Vector3(0.0, -0.05, 0.02)
		lbl.modulate = Color(0.12, 0.12, 0.14, 1.0)
		holder.add_child(lbl)
		add_child(holder)


func _spawn_trash_clusters() -> void:
	var spots: Array[Vector3] = [
		Vector3(11.5, 0.0, -10.8),
		Vector3(39.5, 0.0, -10.8),
		Vector3(12.5, 0.0, 14.5),
		Vector3(-10.5, 0.0, 13.5),
		Vector3(73.0, 0.0, -14.5),
	]
	var bin_mat := StandardMaterial3D.new()
	bin_mat.albedo_color = Color(0.24, 0.34, 0.28, 1.0)
	bin_mat.metallic = 0.45
	bin_mat.roughness = 0.7

	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.90, 0.86, 0.76, 1.0)
	paper_mat.roughness = 0.95

	var can_mat := StandardMaterial3D.new()
	can_mat.albedo_color = Color(0.78, 0.22, 0.18, 1.0)
	can_mat.metallic = 0.6
	can_mat.roughness = 0.4

	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(0.68, 0.54, 0.36, 1.0)
	box_mat.roughness = 0.92

	var rng := RandomNumberGenerator.new()
	rng.seed = 9091

	for spot in spots:
		var cluster := Node3D.new()
		cluster.position = spot

		# Metal trash barrel with collision
		var bin_body := StaticBody3D.new()
		var bin_mesh := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.34
		cm.bottom_radius = 0.32
		cm.height = 0.92
		cm.radial_segments = 12
		bin_mesh.mesh = cm
		bin_mesh.material_override = bin_mat
		bin_mesh.position.y = 0.46
		bin_body.add_child(bin_mesh)

		var bin_col := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = 0.34
		cs.height = 0.92
		bin_col.shape = cs
		bin_col.position.y = 0.46
		bin_body.add_child(bin_col)
		cluster.add_child(bin_body)

		# Cardboard box next to bin
		var card := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, 0.38, 0.44)
		card.mesh = bm
		card.material_override = box_mat
		card.position = Vector3(0.62, 0.19, 0.18)
		card.rotation.y = rng.randf_range(-0.6, 0.6)
		cluster.add_child(card)

		# Scattered newspapers & crushed cans
		for _i in range(5):
			var paper := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(rng.randf_range(0.22, 0.36), 0.012, rng.randf_range(0.18, 0.30))
			paper.mesh = pm
			paper.material_override = paper_mat
			paper.position = Vector3(rng.randf_range(-1.1, 1.1), 0.015, rng.randf_range(-1.0, 1.0))
			paper.rotation.y = rng.randf_range(0.0, TAU)
			cluster.add_child(paper)

		for _j in range(3):
			var can := MeshInstance3D.new()
			var can_m := CylinderMesh.new()
			can_m.top_radius = 0.04
			can_m.bottom_radius = 0.04
			can_m.height = 0.11
			can_m.radial_segments = 8
			can.mesh = can_m
			can.material_override = can_mat
			can.position = Vector3(rng.randf_range(-1.0, 1.0), 0.04, rng.randf_range(-1.0, 1.0))
			can.rotation = Vector3(PI * 0.5, rng.randf_range(0.0, TAU), 0.0)
			cluster.add_child(can)

		add_child(cluster)


func _spawn_cement_block_piles() -> void:
	var block_mat := StandardMaterial3D.new()
	block_mat.albedo_color = Color(0.56, 0.55, 0.53, 1.0)
	block_mat.roughness = 0.95

	var pile_positions: Array[Vector3] = [
		Vector3(-10.2, 0.0, 36.0),
		Vector3(56.0, 0.0, 16.0),
		Vector3(-42.0, 0.0, -9.5),
	]
	for ppos in pile_positions:
		var pile := StaticBody3D.new()
		pile.position = ppos
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.5, 0.9, 1.1)
		col.shape = bs
		col.position = Vector3(0.0, 0.45, 0.0)
		pile.add_child(col)

		for row in range(3):
			for bx in range(3):
				for bz in range(2):
					var block := MeshInstance3D.new()
					var bm := BoxMesh.new()
					bm.size = Vector3(0.42, 0.22, 0.22)
					block.mesh = bm
					block.material_override = block_mat
					block.position = Vector3((bx - 1) * 0.46, 0.11 + row * 0.24, (bz - 0.5) * 0.28)
					pile.add_child(block)
		add_child(pile)


func _spawn_street_signs() -> void:
	var signs := [
		{"pos": Vector3(-11.0, 0.0, -11.0), "rot_y": 0.4, "text": "شارع الأزهري الرئيسي"},
		{"pos": Vector3(60.5, 0.0, -9.5), "rot_y": -0.2, "text": "سوق السمك ->"},
		{"pos": Vector3(60.5, 0.0, 9.5), "rot_y": 0.2, "text": "ميدان دافوري ->"},
		{"pos": Vector3(10.5, 0.0, 10.5), "rot_y": -0.6, "text": "ست الشاي - الأزهري"},
	]
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.42, 0.44, 0.46, 1.0)
	post_mat.metallic = 0.5

	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.10, 0.45, 0.26, 1.0)
	board_mat.roughness = 0.5

	for s in signs:
		var root := StaticBody3D.new()
		root.position = s["pos"]
		root.rotation.y = s["rot_y"]

		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.05
		pm.bottom_radius = 0.06
		pm.height = 2.8
		pm.radial_segments = 8
		post.mesh = pm
		post.material_override = post_mat
		post.position.y = 1.4
		root.add_child(post)

		var col := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = 0.08
		cs.height = 2.8
		col.shape = cs
		col.position.y = 1.4
		root.add_child(col)

		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.85, 0.48, 0.06)
		board.mesh = bm
		board.material_override = board_mat
		board.position.y = 2.55
		root.add_child(board)

		var lbl := Label3D.new()
		lbl.text = s["text"]
		lbl.font_size = 32
		lbl.outline_size = 6
		lbl.position = Vector3(0.0, 2.55, 0.04)
		root.add_child(lbl)

		var lbl_back := Label3D.new()
		lbl_back.text = s["text"]
		lbl_back.font_size = 32
		lbl_back.outline_size = 6
		lbl_back.position = Vector3(0.0, 2.55, -0.04)
		lbl_back.rotation.y = PI
		root.add_child(lbl_back)

		add_child(root)


func _spawn_tangled_wires() -> void:
	# Extra sagging/angled power drop lines running from utility poles to shops & compounds.
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.09, 0.09, 0.10, 1.0)
	wire_mat.roughness = 0.9

	var spans: Array[Array] = [
		[Vector3(12.0, 6.2, -8.5), Vector3(16.0, 4.1, -13.0)],
		[Vector3(12.0, 6.0, -8.5), Vector3(26.0, 4.1, -13.0)],
		[Vector3(44.0, 6.2, -8.5), Vector3(36.0, 4.1, -13.0)],
		[Vector3(44.0, 6.0, -8.5), Vector3(48.0, 4.1, -13.0)],
		[Vector3(-12.0, 6.2, -8.5), Vector3(-14.5, 5.2, -15.0)],
		[Vector3(12.0, 6.1, -8.5), Vector3(16.6, 2.8, 13.6)],
	]
	for span in spans:
		var a: Vector3 = span[0]
		var b: Vector3 = span[1]
		var mid := (a + b) * 0.5
		var dist := a.distance_to(b)
		var wire := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.018
		cm.height = dist
		cm.radial_segments = 6
		wire.mesh = cm
		wire.material_override = wire_mat
		add_child(wire)
		wire.global_position = mid
		wire.look_at(b, Vector3.UP)
		wire.rotate_object_local(Vector3.RIGHT, PI * 0.5)


func _spawn_carryable_props() -> void:
	var specs := [
		{"kind": "crate",    "label": "صندوق خشب",      "pos": Vector3(13.2, 0.35, -10.6)},
		{"kind": "jerrycan", "label": "جركانة بنزين",    "pos": Vector3(14.0, 0.35, -10.6)},
		{"kind": "box",      "label": "كرتونة بضاعة",    "pos": Vector3(20.5, 0.35, -10.6)},
		{"kind": "crate",    "label": "صندوق خضار",     "pos": Vector3(18.0, 0.35, -10.8)},
		{"kind": "ball",     "label": "كورة دافوري",     "pos": Vector3(10.5, 0.35, 11.5)},
		{"kind": "jerrycan", "label": "جركانة موية",     "pos": Vector3(16.0, 0.35, 13.5)},
		{"kind": "box",      "label": "كرتونة شاي",      "pos": Vector3(18.8, 0.35, 15.2)},
		{"kind": "stone",    "label": "حجر طوب",        "pos": Vector3(-11.5, 0.35, 12.2)},
		{"kind": "jerrycan", "label": "جركانة بنشر",     "pos": Vector3(56.5, 0.35, -11.0)},
		{"kind": "jerrycan", "label": "جركانة زيت",     "pos": Vector3(57.8, 0.35, -11.0)},
		{"kind": "crate",    "label": "صندوق عدة",      "pos": Vector3(55.5, 0.35, -11.0)},
		{"kind": "box",      "label": "كرتونة عماري",    "pos": Vector3(28.5, 0.35, 12.8)},
		{"kind": "crate",    "label": "صندوق سمك",      "pos": Vector3(76.5, 0.35, -16.5)},
		{"kind": "ball",     "label": "كورة قدم",       "pos": Vector3(88.0, 0.35, 28.0)},
		{"kind": "crate",    "label": "صندوق مركب",     "pos": Vector3(-135.5, 0.35, -12.0)},
		{"kind": "jerrycan", "label": "جركانة صياد",     "pos": Vector3(-135.5, 0.35, 14.0)},
	]

	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.68, 0.48, 0.28, 1.0)
	mat_wood.roughness = 0.85

	var mat_jerry := StandardMaterial3D.new()
	mat_jerry.albedo_color = Color(0.92, 0.72, 0.14, 1.0)
	mat_jerry.roughness = 0.45

	var mat_box := StandardMaterial3D.new()
	mat_box.albedo_color = Color(0.76, 0.60, 0.40, 1.0)
	mat_box.roughness = 0.9

	var mat_ball := StandardMaterial3D.new()
	mat_ball.albedo_color = Color(0.95, 0.95, 0.95, 1.0)
	mat_ball.roughness = 0.5

	var mat_stone := StandardMaterial3D.new()
	mat_stone.albedo_color = Color(0.64, 0.44, 0.32, 1.0)
	mat_stone.roughness = 0.95

	for idx in range(specs.size()):
		var s: Dictionary = specs[idx]
		var prop := CarryableProp.new()
		prop.name = "CarryableProp_%d" % idx
		prop.prop_label = s["label"]
		prop.position = s["pos"]

		var mi := MeshInstance3D.new()
		var col := CollisionShape3D.new()
		var kind: String = s["kind"]

		if kind == "ball":
			var sm := SphereMesh.new()
			sm.radius = 0.22
			sm.height = 0.44
			mi.mesh = sm
			mi.material_override = mat_ball
			var ss := SphereShape3D.new()
			ss.radius = 0.22
			col.shape = ss
		elif kind == "jerrycan":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.28, 0.44, 0.34)
			mi.mesh = bm
			mi.material_override = mat_jerry
			var bs := BoxShape3D.new()
			bs.size = bm.size
			col.shape = bs
		elif kind == "stone":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.32, 0.22, 0.24)
			mi.mesh = bm
			mi.material_override = mat_stone
			var bs := BoxShape3D.new()
			bs.size = bm.size
			col.shape = bs
		elif kind == "box":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.46, 0.36, 0.42)
			mi.mesh = bm
			mi.material_override = mat_box
			var bs := BoxShape3D.new()
			bs.size = bm.size
			col.shape = bs
		else:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.52, 0.38, 0.44)
			mi.mesh = bm
			mi.material_override = mat_wood
			var bs := BoxShape3D.new()
			bs.size = bm.size
			col.shape = bs

		prop.add_child(mi)
		prop.add_child(col)
		add_child(prop)
