extends SceneTree

const BUILDING_SCENES: Array[String] = [
	"res://scenes/buildings/interactive_compound.tscn",
	"res://scenes/buildings/sudanese_house.tscn",
	"res://scenes/buildings/closed_house.tscn",
	"res://scenes/buildings/interactive_mosque.tscn",
	"res://scenes/buildings/mosque_azhari.tscn",
	"res://scenes/buildings/apartment_building.tscn",
	"res://scenes/buildings/interactive_apartment.tscn",
	"res://scenes/buildings/commercial_strip.tscn",
	"res://scenes/buildings/interactive_dukkan.tscn",
	"res://scenes/buildings/amary_saud_shop.tscn",
]


func _init() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var failures: Array[String] = []
	var total_doors: int = 0
	var total_gates: int = 0
	var total_wood: int = 0
	var total_shutters: int = 0

	for spath in BUILDING_SCENES:
		var ps := ResourceLoader.load(spath) as PackedScene
		if ps == null:
			failures.append("Failed to load scene: " + spath)
			continue
		var inst := ps.instantiate()
		root.add_child(inst)
		await physics_frame
		await physics_frame
		await physics_frame

		var doors: Array[InteractiveDoor] = []
		_collect_doors(inst, doors)
		if doors.is_empty():
			failures.append("No InteractiveDoor nodes found in " + spath)
			inst.queue_free()
			await process_frame
			continue

		for d in doors:
			total_doors += 1
			if not d.is_in_group("interactive_doors"):
				failures.append("%s/%s missing interactive_doors group" % [spath.get_file(), d.name])

			var door_meshes: Array[MeshInstance3D] = []
			_collect_meshes(d, door_meshes)
			if door_meshes.size() > 7:
				failures.append("%s/%s has %d MeshInstance3D nodes (expected <= 7 merged meshes)" % [spath.get_file(), d.name, door_meshes.size()])
			if d.is_physics_processing():
				failures.append("%s/%s is still running _physics_process while idle!" % [spath.get_file(), d.name])

			if d.door_style == InteractiveDoor.DoorStyle.SHOP_ROLLUP_SHUTTER:
				total_shutters += 1
				var rf := d.get_node_or_null("StaticFrame/RollerHousingBox") as MeshInstance3D
				if rf == null or rf.mesh == null or rf.mesh.get_surface_count() < 1:
					failures.append("%s/%s shutter missing merged StaticFrame/RollerHousingBox" % [spath.get_file(), d.name])
				if d.shutter_body == null:
					failures.append("%s/%s shutter missing AnimatableBody3D" % [spath.get_file(), d.name])
				elif d.shutter_body.sync_to_physics:
					failures.append("%s/%s shutter sync_to_physics should sleep (false) when idle" % [spath.get_file(), d.name])
				elif d.shutter_body.get_node_or_null("MergedCurtainMesh") == null:
					failures.append("%s/%s shutter missing MergedCurtainMesh" % [spath.get_file(), d.name])
				if d._clasp_visuals.size() < 2:
					failures.append("%s/%s shutter missing twin padlock clasps" % [spath.get_file(), d.name])
			else:
				var sf_merged := d.get_node_or_null("StaticFrame/MergedFrameMesh") as MeshInstance3D
				if sf_merged == null or sf_merged.mesh == null or sf_merged.mesh.get_surface_count() < 1:
					failures.append("%s/%s missing StaticFrame/MergedFrameMesh" % [spath.get_file(), d.name])
				if d.open_angle_deg < 85.0 or d.open_angle_deg > 88.0:
					failures.append("%s/%s open_angle_deg=%.1f out of [85, 88]" % [spath.get_file(), d.name, d.open_angle_deg])
				if d.hinge_left == null or d.leaf_body_left == null:
					failures.append("%s/%s missing Hinge_Left / LeafBody_Left" % [spath.get_file(), d.name])
				else:
					var bl := d.leaf_body_left
					var vl := bl.get_node_or_null("LeafVisuals") as Node3D
					var cl := bl.get_node_or_null("LeafCollision") as CollisionShape3D
					if bl.sync_to_physics:
						failures.append("%s/%s LeafBody_Left sync_to_physics should sleep (false) when idle" % [spath.get_file(), d.name])
					elif bl.position.length() > 0.005:
						failures.append("%s/%s LeafBody_Left drifted off hinge axis (pos=%s)" % [spath.get_file(), d.name, str(bl.position)])
					elif vl == null or cl == null or vl.position.x <= 0.15 or cl.position.x <= 0.15:
						failures.append("%s/%s LeafVisuals/LeafCollision not offset by +half-width" % [spath.get_file(), d.name])
					else:
						# Verify merged leaf meshes + hardware shadow disabled
						var main_m := vl.get_node_or_null("LeafMainMesh") as MeshInstance3D
						var hw_m := vl.get_node_or_null("LeafHardwareMesh") as MeshInstance3D
						if main_m == null or main_m.mesh == null or hw_m == null or hw_m.mesh == null:
							failures.append("%s/%s missing merged LeafMainMesh / LeafHardwareMesh" % [spath.get_file(), d.name])
						elif hw_m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
							failures.append("%s/%s LeafHardwareMesh still casts shadows!" % [spath.get_file(), d.name])
						# Verify strictly INWARD swing (-Z in local door space) when fully open!
						var prev_open := d.is_open
						var prev_lock := d.is_locked
						d.is_locked = false
						d.is_open = true
						d._current_angle_rad = deg_to_rad(d.open_angle_deg)
						d._apply_kinematic_poses(0.0)
						await physics_frame
						var open_tip_l := (d.hinge_left.transform * bl.transform) * Vector3(vl.position.x * 2.0, 0.0, 0.0)
						if open_tip_l.z > -0.5:
							failures.append("%s/%s LeafBody_Left did NOT open inward! tip_z=%.3f" % [spath.get_file(), d.name, open_tip_l.z])
						if d.hinge_right != null and d.leaf_body_right != null:
							var br := d.leaf_body_right
							var vr := br.get_node_or_null("LeafVisuals") as Node3D
							var cr := br.get_node_or_null("LeafCollision") as CollisionShape3D
							if br.sync_to_physics or br.position.length() > 0.005 or vr == null or cr == null or vr.position.x >= -0.15:
								failures.append("%s/%s invalid LeafBody_Right" % [spath.get_file(), d.name])
							else:
								var open_tip_r := (d.hinge_right.transform * br.transform) * Vector3(vr.position.x * 2.0, 0.0, 0.0)
								if open_tip_r.z > -0.5:
									failures.append("%s/%s LeafBody_Right did NOT open inward! tip_z=%.3f" % [spath.get_file(), d.name, open_tip_r.z])
						d.is_open = prev_open
						d.is_locked = prev_lock
						d._current_angle_rad = deg_to_rad(d.open_angle_deg) if (prev_open and not prev_lock) else 0.0
						d._apply_kinematic_poses(0.0)

				if d.door_style in [InteractiveDoor.DoorStyle.COURTYARD_DOUBLE_GATE, InteractiveDoor.DoorStyle.COURTYARD_SINGLE_GATE]:
					total_gates += 1
					if d._bolt_visuals.is_empty():
						failures.append("%s/%s gate missing animated sliding bolt (ترباس)" % [spath.get_file(), d.name])
					elif d._bolt_visuals[0].cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
						failures.append("%s/%s sliding bolt still casts shadows!" % [spath.get_file(), d.name])
				else:
					total_wood += 1

		print("[PASS] %s: %d InteractiveDoors verified (merged meshes, idle sleep, inward 86 deg)" % [spath.get_file(), doors.size()])
		inst.queue_free()
		await process_frame

	# Interactive rattle & sliding bolt test on closed_house LockedCourtyardGate
	var ch_ps := ResourceLoader.load("res://scenes/buildings/closed_house.tscn") as PackedScene
	var ch := ch_ps.instantiate()
	root.add_child(ch)
	await process_frame
	var lgate := ch.get_node_or_null("LockedCourtyardGate") as InteractiveDoor
	if lgate == null or not lgate.is_locked:
		failures.append("closed_house LockedCourtyardGate missing or not locked")
	else:
		var msg_locked := lgate.toggle_open()
		if lgate.is_open or lgate._rattle_timer <= 0.0:
			failures.append("Locked gate did not rattle or opened while locked!")
		if not lgate.is_physics_processing() or not lgate.leaf_body_left.sync_to_physics:
			failures.append("Locked gate did not wake physics/sync_to_physics during rattle!")
		var bolt_locked_pos := lgate._bolt_visuals[0].position
		var msg_unlock := lgate.toggle_lock()
		for _i in range(25):
			await physics_frame
		var bolt_unlocked_pos := lgate._bolt_visuals[0].position
		var msg_open := lgate.toggle_open()
		if not lgate.is_physics_processing() or not lgate.leaf_body_left.sync_to_physics:
			failures.append("Unlocked gate did not wake sync_to_physics when opening!")
		for _i in range(85):
			await physics_frame
		if bolt_locked_pos.distance_to(bolt_unlocked_pos) < 0.08:
			failures.append("Sliding bolt did not animate on [K] unlock")
		elif not lgate.is_open or lgate.leaf_body_left.rotation.y < deg_to_rad(80.0):
			failures.append("Unlocked gate did not swing open inward cleanly")
		elif lgate.is_physics_processing() or lgate.leaf_body_left.sync_to_physics:
			failures.append("Opened gate did not go back to sleep after settling!")
		else:
			print("[PASS] Locked rattle + [K] sliding bolt animation (delta=%.3fm) + [E] inward swing + auto-sleep verified: '%s' -> '%s' -> '%s'" % [
				bolt_locked_pos.distance_to(bolt_unlocked_pos), msg_locked, msg_unlock, msg_open
			])
	ch.queue_free()
	await process_frame

	print("[INFO] Audited %d total InteractiveDoors (%d courtyard gates, %d wooden building/room doors, %d shop shutters)" % [
		total_doors, total_gates, total_wood, total_shutters
	])
	if failures.is_empty():
		print("=== DOOR AUDIT SUMMARY: ALL CHECKS PASSED (0 FAILURES) ===")
		quit(0)
	else:
		print("=== DOOR AUDIT SUMMARY: %d FAILURES ===" % failures.size())
		for f in failures:
			print("  [FAIL] " + f)
		quit(1)


func _collect_doors(n: Node, out: Array[InteractiveDoor]) -> void:
	if n is InteractiveDoor:
		out.append(n as InteractiveDoor)
	for c in n.get_children():
		_collect_doors(c, out)


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_meshes(c, out)
