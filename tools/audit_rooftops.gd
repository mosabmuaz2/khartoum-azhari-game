extends SceneTree

const ROOF_SCENES: Array[String] = [
	"res://scenes/buildings/sudanese_house.tscn",
	"res://scenes/buildings/interactive_compound.tscn",
	"res://scenes/buildings/closed_house.tscn",
	"res://scenes/buildings/apartment_building.tscn",
	"res://scenes/buildings/interactive_apartment.tscn",
]


func _init() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var failures: Array[String] = []

	for spath in ROOF_SCENES:
		var ps := ResourceLoader.load(spath) as PackedScene
		if ps == null:
			failures.append("Failed to load " + spath)
			continue
		var inst := ps.instantiate() as Node3D
		root.add_child(inst)
		await physics_frame
		await physics_frame

		var rb := inst.get_node_or_null("SudaneseRooftop") as SudaneseRooftopBuilder
		if rb == null:
			failures.append("%s missing SudaneseRooftop node" % spath.get_file())
		else:
			var ms := rb.get_node_or_null("MergedRoofStructure") as MeshInstance3D
			var mp := rb.get_node_or_null("MergedRoofProps") as MeshInstance3D
			var rc := rb.get_node_or_null("RooftopCollision") as StaticBody3D
			if ms == null or not (ms.mesh is ArrayMesh) or mp == null or not (mp.mesh is ArrayMesh):
				failures.append("%s missing MergedRoofStructure / MergedRoofProps ArrayMeshes" % spath.get_file())
			elif not is_equal_approx(mp.visibility_range_end, 110.0):
				failures.append("%s MergedRoofProps visibility_range_end=%.1f != 110.0" % [spath.get_file(), mp.visibility_range_end])
			elif rc == null or rc.get_child_count() < 5:
				failures.append("%s missing solid RooftopCollision shapes" % spath.get_file())
			else:
				# Verify all parapet colliders are >= 1.05m tall
				var parapet_ok := true
				for ch in rc.get_children():
					if ch is CollisionShape3D and ch.name.begins_with("Parapet"):
						var bs := (ch as CollisionShape3D).shape as BoxShape3D
						if bs == null or bs.size.y < 1.05:
							parapet_ok = false
							failures.append("%s/%s parapet height %.2f < 1.05m" % [spath.get_file(), ch.name, bs.size.y if bs else 0.0])
				if rb.has_penthouse_hood:
					var rdoor := rb.get_node_or_null("RoofAccessDoor") as InteractiveDoor
					if rdoor == null or not rdoor.is_open:
						failures.append("%s missing open RoofAccessDoor inside penthouse hood" % spath.get_file())
				if parapet_ok:
					print("[PASS] %s: 1.05m parapet + merged tanks/props (%d surfaces, vis=110m) + %d colliders verified!" % [
						spath.get_file(), mp.mesh.get_surface_count(), rc.get_child_count()
					])

		inst.queue_free()
		await process_frame

	# Live Physics Test 1: Sudanese House stair climb -> walk smoothly through parapet gap onto roof (NO JUMP) -> parapet fall protection!
	await _test_house_roof_and_parapets(failures)

	# Live Physics Test 2: Apartment top landing -> walk smoothly through framed penthouse & open RoofAccessDoor -> parapet fall protection!
	await _test_apartment_roof_and_parapets(failures)

	if failures.is_empty():
		print("=== ROOFTOP & WATER TANKS AUDIT: ALL CHECKS PASSED (0 FAILURES) ===")
		quit(0)
	else:
		print("=== ROOFTOP & WATER TANKS AUDIT: %d FAILURES ===" % failures.size())
		for f in failures:
			print("  [FAIL] " + f)
		quit(1)


func _make_player(pos: Vector3) -> CharacterBody3D:
	var cb := CharacterBody3D.new()
	cb.floor_max_angle = deg_to_rad(55.0)
	cb.floor_snap_length = 0.25
	cb.position = pos
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.72
	cs.shape = cap
	cs.position = Vector3(0.0, 0.86, 0.0)
	cb.add_child(cs)
	return cb


func _walk_toward(cb: CharacterBody3D, target_xz: Vector2, max_steps: int, speed: float = 4.4) -> void:
	var dt := 1.0 / 60.0
	for _i in range(max_steps):
		var cur := Vector2(cb.position.x, cb.position.z)
		var diff := target_xz - cur
		if diff.length() < 0.16:
			cb.velocity.x = 0.0
			cb.velocity.z = 0.0
			cb.move_and_slide()
			await physics_frame
			break
		var d := diff.normalized()
		cb.velocity.x = d.x * speed
		cb.velocity.z = d.y * speed
		cb.velocity.y = -0.5 if cb.is_on_floor() else cb.velocity.y - 20.0 * dt
		cb.move_and_slide()
		await physics_frame


func _test_house_roof_and_parapets(failures: Array[String]) -> void:
	var ps := ResourceLoader.load("res://scenes/buildings/sudanese_house.tscn") as PackedScene
	var house := ps.instantiate() as Node3D
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

	var p := _make_player(Vector3(5.75, 0.05, 0.30))
	house.add_child(p)
	await physics_frame
	# Climb stairs onto top landing (z=-6.82) -> walk straight through 1.40m parapet gap onto roof center (x=0.0, z=-4.0) WITHOUT jumping!
	await _walk_toward(p, Vector2(5.75, -6.82), 200)
	await _walk_toward(p, Vector2(2.50, -6.82), 110)
	var entered := p.position.x < 3.0 and p.position.y >= 3.72
	# Push hard against North, South, West & East (away from gap) parapets!
	await _walk_toward(p, Vector2(2.50, -9.80), 80)
	var held_n := p.position.z > -8.15 and p.position.y >= 3.70
	await _walk_toward(p, Vector2(0.0, -3.5), 110)
	await _walk_toward(p, Vector2(0.0, 2.0), 110)
	var held_s := p.position.z < 0.15 and p.position.y >= 3.70
	await _walk_toward(p, Vector2(-7.0, -3.5), 140)
	var held_w := p.position.x > -5.15 and p.position.y >= 3.70
	await _walk_toward(p, Vector2(7.0, -3.5), 220)
	var held_e := p.position.x < 5.15 and p.position.y >= 3.70

	if not (entered and held_n and held_s and held_w and held_e):
		failures.append("House roof entry/parapet test failed! entered=%s N=%s S=%s W=%s E=%s pos=%s" % [
			str(entered), str(held_n), str(held_s), str(held_w), str(held_e), str(p.position)
		])
	else:
		print("[PASS] Physics Test (Sudanese House Roof): Stair -> Parapet Opening (no jump!) + All 4 Parapets Held!")
	house.queue_free()
	await process_frame


func _test_apartment_roof_and_parapets(failures: Array[String]) -> void:
	var ps := ResourceLoader.load("res://scenes/buildings/apartment_building.tscn") as PackedScene
	var apt := ps.instantiate() as Node3D
	root.add_child(apt)
	await physics_frame
	await physics_frame

	# Start on ExteriorSwitchbackStaircase Roof Landing (x=9.75, y=10.48, z=0.0)
	var p := _make_player(Vector3(9.75, 10.48, 0.0))
	apt.add_child(p)
	await physics_frame
	# Walk straight through framed بيت الدرج penthouse & open RoofAccessDoor onto RoofSlab (x=6.0, z=0.0) WITHOUT jumping!
	await _walk_toward(p, Vector2(6.0, 0.0), 140)
	var entered := p.position.x < 6.5 and p.position.y >= 10.35
	# Test North, South, West & East parapets (away from doorway)
	await _walk_toward(p, Vector2(6.0, -7.0), 140)
	var held_n := p.position.z > -5.15 and p.position.y >= 10.35
	await _walk_toward(p, Vector2(6.0, 7.0), 220)
	var held_s := p.position.z < 5.15 and p.position.y >= 10.35
	await _walk_toward(p, Vector2(11.0, 3.0), 120)
	var held_e := p.position.x < 9.15 and p.position.y >= 10.35
	await _walk_toward(p, Vector2(-11.0, 1.5), 360)
	var held_w := p.position.x > -9.15 and p.position.y >= 10.35

	if not (entered and held_n and held_s and held_e and held_w):
		failures.append("Apartment roof penthouse/parapet test failed! entered=%s N=%s S=%s E=%s W=%s pos=%s" % [
			str(entered), str(held_n), str(held_s), str(held_e), str(held_w), str(p.position)
		])
	else:
		print("[PASS] Physics Test (Apartment Roof): Top Landing -> Penthouse Hood & Open Door (no jump!) + All 4 Parapets Held!")
	apt.queue_free()
	await process_frame
