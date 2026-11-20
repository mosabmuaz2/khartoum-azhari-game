extends SceneTree

func _init() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var failures: Array[String] = []

	# 1. Verify shaders compile cleanly
	for spath in ["res://shaders/tree_wind.gdshader", "res://shaders/tree_canopy_wind.gdshader"]:
		var sh := ResourceLoader.load(spath) as Shader
		if sh == null:
			failures.append("Shader failed to load: " + spath)
		else:
			print("[PASS] Shader loaded cleanly: %s" % spath)

	# 2. Verify imported 4K island_tree_02.gltf materials & surfaces
	var it_packed := ResourceLoader.load("res://assets/models/foliage/island_tree_02/island_tree_02.gltf") as PackedScene
	if it_packed == null:
		failures.append("island_tree_02.gltf failed to load")
	else:
		var it := it_packed.instantiate()
		var mi := _find_first_mesh(it)
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() < 3:
			failures.append("island_tree_02 missing expected 3 surfaces")
		else:
			var leaf_verified := false
			var bark_verified := 0
			for si in range(mi.mesh.get_surface_count()):
				var std := mi.mesh.surface_get_material(si) as StandardMaterial3D
				if std == null:
					failures.append("island_tree_02 surface %d is not StandardMaterial3D" % si)
					continue
				var mn := std.resource_name.to_lower()
				var tp := std.albedo_texture.resource_path.to_lower() if std.albedo_texture != null else ""
				if "leaves" in mn:
					if not ("leaves_rgba" in tp):
						failures.append("island_tree_02 leaves surface missing RGBA leaf texture: " + tp)
					elif std.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
						failures.append("island_tree_02 leaves transparency not ALPHA_SCISSOR")
					elif not is_equal_approx(std.alpha_scissor_threshold, 0.45):
						failures.append("island_tree_02 leaves alpha_scissor_threshold=%.2f != 0.45" % std.alpha_scissor_threshold)
					elif std.alpha_antialiasing_mode != BaseMaterial3D.ALPHA_ANTIALIASING_OFF:
						failures.append("island_tree_02 leaves alpha_antialiasing_mode should be OFF for fast gl_compatibility")
					elif std.cull_mode != BaseMaterial3D.CULL_DISABLED:
						failures.append("island_tree_02 leaves cull_mode not CULL_DISABLED")
					elif std.backlight_enabled:
						failures.append("island_tree_02 leaves backlight should be disabled for performance")
					else:
						leaf_verified = true
						print("[PASS] island_tree_02 leaf surface: ALPHA_SCISSOR=0.45, AA_OFF, CULL_DISABLED, rough=%.2f, backlight=OFF, tex=%s" % [std.roughness, tp.get_file()])
				else:
					if std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						failures.append("island_tree_02 bark surface %s not opaque" % mn)
					else:
						bark_verified += 1
			if not leaf_verified or bark_verified < 2:
				failures.append("island_tree_02 surface check incomplete: leaf=%s bark=%d" % [str(leaf_verified), bark_verified])
		it.free()

	# 3. Verify quiver_tree_01.gltf materials (opaque 3D succulent leaves, no broken BLEND on JPG)
	var qt_packed := ResourceLoader.load("res://assets/models/foliage/quiver_tree_01/quiver_tree_01.gltf") as PackedScene
	if qt_packed == null:
		failures.append("quiver_tree_01.gltf failed to load")
	else:
		var qt := qt_packed.instantiate()
		var qmi := _find_first_mesh(qt)
		if qmi != null and qmi.mesh != null:
			for si in range(qmi.mesh.get_surface_count()):
				var std := qmi.mesh.surface_get_material(si) as StandardMaterial3D
				if std != null and std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					failures.append("quiver_tree_01 surface %s should be opaque (JPG texture)" % std.resource_name)
			print("[PASS] quiver_tree_01 surfaces opaque & clean (%d surfaces)" % qmi.mesh.get_surface_count())
		qt.free()

	# 4. Verify all 4 Sudanese tree prefabs build organic meshes + trunk-only colliders + wind sway
	for ppath in [
		"res://scenes/foliage/neem_tree.tscn",
		"res://scenes/foliage/acacia_tree.tscn",
		"res://scenes/foliage/date_palm.tscn",
		"res://scenes/foliage/realistic_4k_tree.tscn",
	]:
		var ps := ResourceLoader.load(ppath) as PackedScene
		if ps == null:
			failures.append("Prefab failed to load: " + ppath)
			continue
		var inst := ps.instantiate() as Node3D
		root.add_child(inst)
		await process_frame
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(inst, meshes)
		var has_box := false
		var has_wind_shader := false
		for m in meshes:
			if m.mesh is BoxMesh:
				has_box = true
			if m.material_override is ShaderMaterial:
				has_wind_shader = true
			for si in range(m.get_surface_override_material_count()):
				if m.get_surface_override_material(si) is ShaderMaterial:
					has_wind_shader = true
		var col := inst.get_node_or_null("TrunkCollider/CollisionShape3D") as CollisionShape3D
		if col == null:
			# Search child CollisionShape3D under TrunkCollider
			var tc := inst.get_node_or_null("TrunkCollider")
			if tc != null and tc.get_child_count() > 0:
				col = tc.get_child(0) as CollisionShape3D
		if has_box:
			failures.append("Prefab contains BoxMesh: " + ppath)
		elif not has_wind_shader:
			failures.append("Prefab missing wind ShaderMaterial: " + ppath)
		elif col == null or not (col.shape is CylinderShape3D):
			failures.append("Prefab missing trunk CylinderShape3D collider: " + ppath)
		else:
			print("[PASS] Prefab %s: %d meshes, wind sway active, trunk-only cylinder collider" % [ppath.get_file(), meshes.size()])
		inst.queue_free()
		await process_frame

	# 5. Verify zero BoxMesh trees remain in nile_river.tscn and house scenes
	for spath in [
		"res://scenes/nile_river.tscn",
		"res://scenes/buildings/interactive_compound.tscn",
		"res://scenes/buildings/sudanese_house.tscn",
		"res://scenes/buildings/closed_house.tscn",
	]:
		var ps := ResourceLoader.load(spath) as PackedScene
		var inst := ps.instantiate()
		root.add_child(inst)
		await process_frame
		var bad_boxes: Array[String] = []
		var organic_trees: Array[String] = []
		_scan_scene_trees(inst, bad_boxes, organic_trees)
		if not bad_boxes.is_empty():
			failures.append("%s still has BoxMesh trees: %s" % [spath, ", ".join(bad_boxes)])
		elif organic_trees.is_empty():
			failures.append("%s has 0 organic SudaneseTreeBuilder trees" % spath)
		else:
			print("[PASS] %s: 0 BoxMesh trees, %d organic Sudanese trees active (%s)" % [spath.get_file(), organic_trees.size(), ", ".join(organic_trees.slice(0, 4))])
		inst.queue_free()
		await process_frame

	if failures.is_empty():
		print("=== TREE AUDIT SUMMARY: ALL CHECKS PASSED (0 FAILURES) ===")
		quit(0)
	else:
		print("=== TREE AUDIT SUMMARY: %d FAILURES ===" % failures.size())
		for f in failures:
			print("  [FAIL] " + f)
		quit(1)


func _find_first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var f := _find_first_mesh(c)
		if f != null:
			return f
	return null


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_meshes(c, out)


func _scan_scene_trees(n: Node, bad_boxes: Array[String], organic_trees: Array[String]) -> void:
	if n is SudaneseTreeBuilder:
		organic_trees.append(n.name)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var ln := n.name.to_lower()
		var pn := n.get_parent().name.to_lower() if n.get_parent() != null else ""
		if mi.mesh is BoxMesh and ("tree" in ln or "palm" in ln or "tree" in pn or "palm" in pn):
			bad_boxes.append(n.name)
	for c in n.get_children():
		_scan_scene_trees(c, bad_boxes, organic_trees)
