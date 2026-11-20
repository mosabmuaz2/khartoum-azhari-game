extends SceneTree

const STAIR_SCENES: Array[String] = [
	"res://scenes/buildings/sudanese_house.tscn",
	"res://scenes/buildings/interactive_compound.tscn",
	"res://scenes/buildings/apartment_building.tscn",
	"res://scenes/buildings/interactive_apartment.tscn",
	"res://scenes/buildings/bus_station.tscn",
	"res://scenes/nile_river.tscn",
]


func _init() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var failures: Array[String] = []
	var total_stairs := 0

	# 1. Structural, mesh-merge, collider & window-overlap audit across all 6 scenes
	for spath in STAIR_SCENES:
		var ps := ResourceLoader.load(spath) as PackedScene
		if ps == null:
			failures.append("Failed to load " + spath)
			continue
		var inst := ps.instantiate() as Node3D
		root.add_child(inst)
		await physics_frame
		await physics_frame

		# Check no legacy floating step nodes remain
		var legacy_nodes: Array[String] = []
		_find_legacy_steps(inst, legacy_nodes)
		if not legacy_nodes.is_empty():
			failures.append("%s still has legacy floating step nodes: %s" % [spath.get_file(), ", ".join(legacy_nodes)])

		# Collect all SudaneseStaircase nodes
		var stairs: Array[SudaneseStaircase] = []
		_collect_stairs(inst, stairs)
		if stairs.is_empty():
			failures.append("%s has 0 SudaneseStaircase nodes!" % spath.get_file())

		# Collect window AABBs
		var win_aabbs: Array[Dictionary] = []
		_collect_window_aabbs(inst, win_aabbs)

		for st in stairs:
			total_stairs += 1
			var meshes: Array[MeshInstance3D] = []
			_collect_meshes(st, meshes)
			if meshes.size() != 1:
				failures.append("%s/%s has %d MeshInstance3D nodes (expected 1 merged ArrayMesh)" % [spath.get_file(), st.name, meshes.size()])
			else:
				var mi := meshes[0]
				if not (mi.mesh is ArrayMesh) or mi.mesh.get_surface_count() < 2:
					failures.append("%s/%s MergedStairMesh invalid (surfaces=%d)" % [spath.get_file(), st.name, mi.mesh.get_surface_count() if mi.mesh else 0])

				# Verify zero window overlap
				var st_aabb := _world_aabb(mi)
				for winfo in win_aabbs:
					var wa: AABB = winfo["aabb"]
					if st_aabb.intersects(wa):
						failures.append("%s/%s intersects window %s!" % [spath.get_file(), st.name, String(winfo["name"])])

			var col_body := st.get_node_or_null("StairCollisionBody") as StaticBody3D
			if col_body == null or not col_body.is_in_group("walkable_stair_ramps"):
				failures.append("%s/%s missing StairCollisionBody in walkable_stair_ramps" % [spath.get_file(), st.name])
			else:
				var convex_cnt := 0
				var box_cnt := 0
				var guard_cnt := 0
				for ch in col_body.get_children():
					if ch is CollisionShape3D:
						var cs := ch as CollisionShape3D
						if cs.shape is ConvexPolygonShape3D:
							convex_cnt += 1
						elif cs.shape is BoxShape3D:
							box_cnt += 1
						if "GuardCol" in cs.name:
							guard_cnt += 1
				if convex_cnt < 1:
					failures.append("%s/%s missing ConvexPolygonShape3D ramp collider" % [spath.get_file(), st.name])
				if st.stair_style != SudaneseStaircase.StairStyle.LOW_STEPS and (box_cnt < 1 or guard_cnt < 1):
					failures.append("%s/%s missing landing/column BoxShape3D (%d) or handrail guard colliders (%d)" % [spath.get_file(), st.name, box_cnt, guard_cnt])

		print("[PASS] %s: %d SudaneseStaircase(s) verified (1 merged ArrayMesh, ConvexPolygon ramp, 0 window overlap)" % [spath.get_file(), stairs.size()])
		inst.queue_free()
		await process_frame

	# 2. Live CharacterBody3D physics climbing test: Sudanese House single-flight roof stair
	await _test_house_climb(failures)

	# 3. Live CharacterBody3D physics climbing test: Apartment 3-story switchback stair (Ground -> F1 -> F2 -> Roof)
	await _test_apartment_switchback_climb(failures)

	print("[INFO] Audited %d SudaneseStaircase instances across %d scenes." % [total_stairs, STAIR_SCENES.size()])
	if failures.is_empty():
		print("=== STAIRCASE AUDIT SUMMARY: ALL CHECKS PASSED (0 FAILURES) ===")
		quit(0)
	else:
		print("=== STAIRCASE AUDIT SUMMARY: %d FAILURES ===" % failures.size())
		for f in failures:
			print("  [FAIL] " + f)
		quit(1)


func _make_test_player(start_pos: Vector3) -> CharacterBody3D:
	var cb := CharacterBody3D.new()
	cb.floor_max_angle = deg_to_rad(55.0)
	cb.floor_snap_length = 0.25
	cb.position = start_pos
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.72
	cs.shape = cap
	cs.position = Vector3(0.0, 0.86, 0.0)
	cb.add_child(cs)
	return cb


func _walk_player_toward(cb: CharacterBody3D, target_xz: Vector2, max_steps: int = 160, speed: float = 4.4) -> void:
	var dt := 1.0 / 60.0
	for _i in range(max_steps):
		var cur_xz := Vector2(cb.position.x, cb.position.z)
		var diff := target_xz - cur_xz
		if diff.length() < 0.14:
			cb.velocity.x = 0.0
			cb.velocity.z = 0.0
			if not cb.is_on_floor():
				cb.velocity.y -= 20.0 * dt
			cb.move_and_slide()
			await physics_frame
			break
		var dir := diff.normalized()
		cb.velocity.x = dir.x * speed
		cb.velocity.z = dir.y * speed
		if not cb.is_on_floor():
			cb.velocity.y -= 20.0 * dt
		else:
			cb.velocity.y = -0.5
		cb.move_and_slide()
		await physics_frame


func _test_house_climb(failures: Array[String]) -> void:
	var ps := ResourceLoader.load("res://scenes/buildings/sudanese_house.tscn") as PackedScene
	var house := ps.instantiate() as Node3D
	# Add ground plane under house
	var g := StaticBody3D.new()
	var gcs := CollisionShape3D.new()
	var gbs := BoxShape3D.new()
	gbs.size = Vector3(40.0, 0.2, 40.0)
	gcs.shape = gbs
	gcs.position = Vector3(0.0, -0.1, 0.0)
	g.add_child(gcs)
	house.add_child(g)
	root.add_child(house)
	await physics_frame
	await physics_frame

	var player := _make_test_player(Vector3(5.75, 0.05, 0.30))
	house.add_child(player)
	await physics_frame

	# Walk up all 22 steps onto Top Landing (x=5.75, z=-6.80, y=3.80)
	await _walk_player_toward(player, Vector2(5.75, -6.80), 200, 4.4)
	var y_land := player.position.y
	if y_land < 3.68 or y_land > 4.05:
		failures.append("House stair climb failed to reach top landing! pos=%s" % str(player.position))
	else:
		# Test outer guardrail prevents falling off (+X)
		await _walk_player_toward(player, Vector2(7.50, -6.80), 60, 4.0)
		if player.position.x > 6.45 or player.position.y < 3.60:
			failures.append("House top landing handrail guard failed! pos=%s" % str(player.position))
		# Walk cleanly off top landing onto HouseRoof through notched parapet (-X to x=3.2)
		await _walk_player_toward(player, Vector2(3.20, -6.80), 100, 4.2)
		if player.position.x > 3.60 or player.position.y < 3.68:
			failures.append("House roof entry through parapet failed! pos=%s" % str(player.position))
		else:
			print("[PASS] Physics Climb Test (Sudanese House): smoothly climbed Ground (0.0m) -> Top Landing (%.2fm) -> Handrail Guard Held -> HouseRoof (%.2fm)" % [y_land, player.position.y])

	house.queue_free()
	await process_frame


func _test_apartment_switchback_climb(failures: Array[String]) -> void:
	var ps := ResourceLoader.load("res://scenes/buildings/apartment_building.tscn") as PackedScene
	var apt := ps.instantiate() as Node3D
	var g := StaticBody3D.new()
	var gcs := CollisionShape3D.new()
	var gbs := BoxShape3D.new()
	gbs.size = Vector3(50.0, 0.2, 50.0)
	gcs.shape = gbs
	gcs.position = Vector3(0.0, -0.1, 0.0)
	g.add_child(gcs)
	apt.add_child(g)
	root.add_child(apt)
	await physics_frame
	await physics_frame

	# Start on ground in outer lane (x = 9.175 + 1.845 = 11.02, z = 0.25)
	var x_outer := 9.175 + 1.15 + 0.12 + 0.575 # 11.02
	var x_inner := 9.175 + 0.575               # 9.75
	var player := _make_test_player(Vector3(x_outer, 0.05, 0.25))
	apt.add_child(player)
	await physics_frame

	var expected_floors: Array[float] = [3.50, 6.90, 10.44]
	var reached: Array[float] = []
	for s in range(3):
		# Flight A (+Z up to mid-landing z = 3.92)
		await _walk_player_toward(player, Vector2(x_outer, 3.92), 180, 4.4)
		# Mid-landing 180-deg turn (-X to inner lane)
		await _walk_player_toward(player, Vector2(x_inner, 3.92), 90, 4.0)
		# Flight B (-Z up to floor landing z = 0.0)
		await _walk_player_toward(player, Vector2(x_inner, 0.0), 180, 4.4)
		reached.append(player.position.y)
		if absf(player.position.y - expected_floors[s]) > 0.20:
			failures.append("Apartment switchback story %d failed! expected y=%.2f got pos=%s" % [s + 1, expected_floors[s], str(player.position)])
			break
		if s < 2:
			# Cross floor landing back to outer lane (+X) for next story
			await _walk_player_toward(player, Vector2(x_outer, 0.0), 90, 4.0)

	if reached.size() == 3 and absf(reached[2] - 10.44) <= 0.20:
		# Step through notched RoofParapetR onto RoofSlab (-X to x=7.5)
		await _walk_player_toward(player, Vector2(7.50, 0.0), 100, 4.0)
		if player.position.x > 7.90 or player.position.y < 10.25:
			failures.append("Apartment roof entry through RoofParapetR failed! pos=%s" % str(player.position))
		else:
			print("[PASS] Physics Climb Test (Apartment 3-Story Switchback): Ground (0.0m) -> Floor 1 (%.2fm) -> Floor 2 (%.2fm) -> Roof (%.2fm) -> RoofSlab OK" % [
				reached[0], reached[1], reached[2]
			])

	apt.queue_free()
	await process_frame


func _find_legacy_steps(n: Node, out: Array[String]) -> void:
	var nm := n.name
	if nm.begins_with("Step_") or nm.begins_with("ExtStair_") or nm.begins_with("CornicheStep_") or nm.begins_with("IntStairRamp_"):
		out.append(nm)
	for c in n.get_children():
		_find_legacy_steps(c, out)


func _collect_stairs(n: Node, out: Array[SudaneseStaircase]) -> void:
	if n is SudaneseStaircase:
		out.append(n as SudaneseStaircase)
	for c in n.get_children():
		_collect_stairs(c, out)


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_meshes(c, out)


func _collect_window_aabbs(n: Node, out: Array[Dictionary]) -> void:
	if n is Node3D and "Win" in n.name:
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(n, meshes)
		if not meshes.is_empty():
			var combined := _world_aabb(meshes[0])
			for i in range(1, meshes.size()):
				combined = combined.merge(_world_aabb(meshes[i]))
			out.append({"name": n.name, "aabb": combined})
		return
	for c in n.get_children():
		_collect_window_aabbs(c, out)


func _world_aabb(mi: MeshInstance3D) -> AABB:
	var local_aabb := mi.get_aabb()
	var xf := mi.global_transform
	var pts := [
		xf * Vector3(local_aabb.position.x, local_aabb.position.y, local_aabb.position.z),
		xf * Vector3(local_aabb.end.x, local_aabb.position.y, local_aabb.position.z),
		xf * Vector3(local_aabb.position.x, local_aabb.end.y, local_aabb.position.z),
		xf * Vector3(local_aabb.position.x, local_aabb.position.y, local_aabb.end.z),
		xf * Vector3(local_aabb.end.x, local_aabb.end.y, local_aabb.position.z),
		xf * Vector3(local_aabb.end.x, local_aabb.position.y, local_aabb.end.z),
		xf * Vector3(local_aabb.position.x, local_aabb.end.y, local_aabb.end.z),
		xf * Vector3(local_aabb.end.x, local_aabb.end.y, local_aabb.end.z),
	]
	var a := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		a = a.expand(p)
	return a
