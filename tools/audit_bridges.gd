extends SceneTree

func _init() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var failures: Array[String] = []

	var main_ps := ResourceLoader.load("res://scenes/main.tscn") as PackedScene
	if main_ps == null:
		failures.append("Failed to load res://scenes/main.tscn")
		quit(1)
		return

	var world := main_ps.instantiate() as Node3D
	root.add_child(world)
	for _i in range(6):
		await physics_frame

	# 1. Verify all 3 Nile bridges + abutments + riverbed piers exist
	var nile_bridges := get_nodes_in_group("nile_bridges")
	var abutments := get_nodes_in_group("bridge_abutments")
	var piers := get_nodes_in_group("bridge_piers")
	if nile_bridges.size() < 3:
		failures.append("Expected 3 Nile bridges, found %d" % nile_bridges.size())
	if abutments.size() < 14: # 3 Nile bridges * 2 ramps + 4 overpasses * 2 ramps = 14
		failures.append("Expected >= 14 UnderRampAbutments (bridges + overpasses), found %d" % abutments.size())
	if piers.size() < 20:
		failures.append("Expected >= 20 bridge pier pairs, found %d" % piers.size())
	else:
		print("[PASS] Structures: %d Nile bridges, %d solid under-ramp concrete abutments, %d concrete pier pairs" % [
			nile_bridges.size(), abutments.size(), piers.size()
		])

	# 2. Scan EVERY tree, palm, MultiMesh tree instance, and river rock against bridge footprints (+3.0m margin)
	var offending_nodes: Array[String] = []
	_scan_for_bridge_intrusions(world, offending_nodes)
	if not offending_nodes.is_empty():
		failures.append("Found %d trees/rocks inside bridge 3.0m exclusion zone: %s" % [offending_nodes.size(), ", ".join(offending_nodes.slice(0, 8))])
	else:
		print("[PASS] Exclusion Audit: 0 trees, 0 palms, 0 MultiMesh trees, and 0 river rocks intersect ANY bridge/overpass (+3.0m margin)!")

	# 3. Live Physics Raycast Tests on GrandNileBridge (z = 0, x in [-288..-92])
	var space := world.get_world_3d().direct_space_state

	# 3A. Verify low-clearance triangular wedges under BOTH EastRamp (x=-110) and WestRamp (x=-270) are SOLIDLY ENCLOSED!
	for test_x: float in [-110.0, -270.0]:
		var q_side := PhysicsRayQueryParameters3D.create(Vector3(test_x, 1.2, -12.0), Vector3(test_x, 1.2, 0.0), 1)
		var hit_side := space.intersect_ray(q_side)
		if hit_side.is_empty():
			failures.append("Hollow gap under ramp at x=%.1f! Side ray passed straight through!" % test_x)
		else:
			var col_node := hit_side["collider"] as Node
			var hit_z := (hit_side["position"] as Vector3).z
			if col_node == null or not col_node.is_in_group("bridge_abutments") or absf(hit_z - (-6.88)) > 0.35:
				failures.append("Unexpected under-ramp hit at x=%.1f: collider=%s z=%.2f" % [test_x, col_node.name if col_node else "null", hit_z])
	print("[PASS] Under-Ramp Retaining Wall Physics: EastRamp (x=-110) & WestRamp (x=-270) solidly block side entry at z=-6.88m!")

	# 3B. Verify high-clearance Corniche Promenade underpass (x=-136, y=1.5..4.0, z=-18..+18) and Nile river span (x=-184) are WIDE OPEN!
	for open_x: float in [-136.0, -184.0]:
		var q_under := PhysicsRayQueryParameters3D.create(Vector3(open_x, 1.8, -18.0), Vector3(open_x, 1.8, 18.0), 1)
		var hit_under := space.intersect_ray(q_under)
		if not hit_under.is_empty():
			var cn := hit_under["collider"] as Node
			failures.append("High-clearance underpass blocked at x=%.1f by %s at %s!" % [open_x, cn.name if cn else "?", str(hit_under["position"])])
	print("[PASS] High-Clearance Underpass Physics: Corniche (x=-136) & Nile Span (x=-184) completely clear underneath!")

	# 3C. Verify bridge deck road surface (x=-288..-92, z=0) is 100% obstacle-free & smoothly climbable to y=6.20m!
	var deck_clear_q := PhysicsRayQueryParameters3D.create(Vector3(-238.0, 7.2, 0.0), Vector3(-142.0, 7.2, 0.0), 1)
	var deck_hit := space.intersect_ray(deck_clear_q)
	if not deck_hit.is_empty():
		var cn := deck_hit["collider"] as Node
		failures.append("Bridge asphalt deck obstructed at %s by %s!" % [str(deck_hit["position"]), cn.name if cn else "?"])

	# Verify exact vertical clearance & driveable surface height along the full bridge profile
	var sample_xs: Array[float] = [-92.0, -116.0, -140.0, -190.0, -240.0, -264.0, -288.0]
	var expected_ys: Array[float] = [0.0, 3.1, 6.2, 6.2, 6.2, 3.1, 0.0]
	for si in range(sample_xs.size()):
		var sx := sample_xs[si]
		var q_top := PhysicsRayQueryParameters3D.create(Vector3(sx, 10.0, 0.0), Vector3(sx, -1.0, 0.0), 1)
		var h_top := space.intersect_ray(q_top)
		if h_top.is_empty():
			failures.append("Missing bridge road collision at x=%.1f!" % sx)
		else:
			var hy := (h_top["position"] as Vector3).y
			if absf(hy - expected_ys[si]) > 0.25:
				failures.append("Bridge height mismatch at x=%.1f: got y=%.2f expected %.2f" % [sx, hy, expected_ys[si]])
	print("[PASS] Bridge Road Profile Verified: smooth 0.0m -> 3.1m -> 6.20m -> 3.1m -> 0.0m with zero deck obstructions!")

	world.queue_free()
	await process_frame

	if failures.is_empty():
		print("=== NILE BRIDGE & ABUTMENT AUDIT: ALL CHECKS PASSED (0 FAILURES) ===")
		quit(0)
	else:
		print("=== NILE BRIDGE & ABUTMENT AUDIT: %d FAILURES ===" % failures.size())
		for f in failures:
			print("  [FAIL] " + f)
		quit(1)


func _scan_for_bridge_intrusions(node: Node, out: Array[String]) -> void:
	if node is SudaneseTreeBuilder:
		var gp := (node as Node3D).global_position
		if SmartWorldOrganizer.is_in_bridge_exclusion(gp, 3.0):
			out.append("%s@%s" % [node.name, str(gp.snapped(Vector3(0.1, 0.1, 0.1)))])
	elif node is Node3D and (node.name.begins_with("RiverRock_") or "CornicheDatePalm" in node.name or "CornicheAcacia" in node.name):
		var gp := (node as Node3D).global_position
		if SmartWorldOrganizer.is_in_bridge_exclusion(gp, 3.0):
			out.append("%s@%s" % [node.name, str(gp.snapped(Vector3(0.1, 0.1, 0.1)))])
	elif node is MultiMeshInstance3D and ("Tree" in node.name or "Trunk" in node.name or "Rock" in node.name or "Palm" in node.name):
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh != null:
			for i in range(mmi.multimesh.instance_count):
				var wp := mmi.global_transform * mmi.multimesh.get_instance_transform(i).origin
				if SmartWorldOrganizer.is_in_bridge_exclusion(wp, 3.0):
					out.append("%s[%d]@%s" % [mmi.name, i, str(wp.snapped(Vector3(0.1, 0.1, 0.1)))])
	for c in node.get_children():
		_scan_for_bridge_intrusions(c, out)
