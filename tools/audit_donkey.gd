extends SceneTree

func _init() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var failures: Array[String] = []

	# 1. Instantiate donkey.tscn & verify anatomy, attached tail, saddle, bridle, reins & markers
	var dps := ResourceLoader.load("res://scenes/animals/donkey.tscn") as PackedScene
	if dps == null:
		failures.append("Failed to load res://scenes/animals/donkey.tscn")
		quit(1)
		return

	var donkey := dps.instantiate() as AnimalAI
	var ground := StaticBody3D.new()
	var gcs := CollisionShape3D.new()
	var gbs := BoxShape3D.new()
	gbs.size = Vector3(60.0, 0.2, 60.0)
	gcs.shape = gbs
	gcs.position = Vector3(0.0, -0.1, 0.0)
	ground.add_child(gcs)
	root.add_child(ground)
	root.add_child(donkey)
	await process_frame
	await physics_frame

	if not donkey.is_in_group("rideable_donkeys") or not donkey.is_rideable():
		failures.append("Donkey not registered as rideable_donkeys!")

	# Verify required hierarchy nodes
	for req in [
		"BodyRoot", "BodyRoot/DonkeyTorsoMesh", "BodyRoot/SaddleAssembly", "BodyRoot/Seat_Mount",
		"BodyRoot/KaroHitchPoint", "BodyRoot/TailPivot", "BodyRoot/TailPivot/TailUpper",
		"BodyRoot/TailPivot/TailTipPivot", "BodyRoot/TailPivot/TailTipPivot/TailLower",
		"BodyRoot/NeckPivot", "BodyRoot/NeckPivot/HeadPivot", "BodyRoot/NeckPivot/HeadPivot/DonkeyHeadAndBridleMesh",
		"BodyRoot/NeckPivot/HeadPivot/Ear_L", "BodyRoot/NeckPivot/HeadPivot/Ear_R",
		"BodyRoot/Leg_FL", "BodyRoot/Leg_FL/Knee_FL", "BodyRoot/Leg_FR", "BodyRoot/Leg_FR/Knee_FR",
		"BodyRoot/Leg_RL", "BodyRoot/Leg_RL/Hock_RL", "BodyRoot/Leg_RR", "BodyRoot/Leg_RR/Hock_RR",
		"Exit_Left", "Exit_Right", "Rein_L", "Rein_R"
	]:
		if donkey.get_node_or_null(req) == null:
			failures.append("Donkey missing required node: " + req)

	# Verify tail is firmly attached to rear hip socket (zero floating gap!)
	var tail_piv := donkey.get_node_or_null("BodyRoot/TailPivot") as Node3D
	var tail_tip := donkey.get_node_or_null("BodyRoot/TailPivot/TailTipPivot") as Node3D
	if tail_piv != null and tail_tip != null:
		if tail_piv.position.z > 0.62 or tail_piv.position.z < 0.45:
			failures.append("TailPivot not anchored in rear hip socket! pos=%s" % str(tail_piv.position))
		if tail_tip.position.length() > 0.30:
			failures.append("TailTipPivot detached from TailUpper! pos=%s" % str(tail_tip.position))
		else:
			print("[PASS] Donkey attached TailPivot=%s -> TailTipPivot=%s (firmly rooted in rear hip socket)" % [str(tail_piv.position), str(tail_tip.position)])

	# Verify saddle & bridle multi-surface ArrayMeshes
	var sad := donkey.get_node_or_null("BodyRoot/SaddleAssembly") as MeshInstance3D
	var hd := donkey.get_node_or_null("BodyRoot/NeckPivot/HeadPivot/DonkeyHeadAndBridleMesh") as MeshInstance3D
	if sad == null or not (sad.mesh is ArrayMesh) or sad.mesh.get_surface_count() < 4:
		failures.append("Donkey SaddleAssembly missing multi-surface Bardaa + girth strap")
	if hd == null or not (hd.mesh is ArrayMesh) or hd.mesh.get_surface_count() < 5:
		failures.append("Donkey HeadAndBridleMesh missing sculpted muzzle/eyes/leather bridle")
	else:
		print("[PASS] Donkey SaddleAssembly (%d surfaces) + HeadAndBridleMesh (%d surfaces) + dynamic Rein_L/Rein_R verified!" % [
			sad.mesh.get_surface_count(), hd.mesh.get_surface_count()
		])

	# 2. Verify Karo cart hitching + player mount, Ride_Donkey animation, WASD trot gait, & dismount!
	var mock_cart := Node3D.new()
	mock_cart.name = "MockKaroCart"
	mock_cart.position = Vector3(0.0, 0.0, 2.0)
	root.add_child(mock_cart)
	donkey.hitched_cart = mock_cart

	var pps := ResourceLoader.load("res://scenes/player.tscn") as PackedScene
	var player := pps.instantiate() as PlayerController
	player.position = Vector3(1.5, 0.05, 0.0)
	root.add_child(player)
	await process_frame
	await physics_frame

	var mounted := player.mount_donkey(donkey)
	await process_frame
	await physics_frame
	if not mounted or not donkey.is_mounted():
		failures.append("player.mount_donkey(donkey) failed!")
	else:
		if not player.body_collider.disabled:
			failures.append("Player body_collider was NOT disabled while riding donkey!")
		if player.name_label != null and player.name_label.visible:
			failures.append("Player overhead name_label was NOT hidden while riding donkey!")
		var active_clip := player._anim_binder.get_current_clip_name() if player._anim_binder != null else ""
		if active_clip != "Ride_Donkey":
			failures.append("Expected Ride_Donkey animation clip while riding, got '%s'" % active_clip)

		# Verify lowered & centered Seat_Mount position
		var sm_pos := donkey.seat_mount.position
		if not sm_pos.is_equal_approx(Vector3(0.0, 0.08, -0.01)):
			failures.append("Seat_Mount position mismatch: got %s expected (0, 0.08, -0.01)" % str(sm_pos))

		# Verify live hand-tracked reins & outward leg straddle while mounted!
		await process_frame
		await physics_frame
		donkey._update_donkey_reins()
		var hands := player.get_hand_global_positions()
		if not hands.has("left") or not hands.has("right"):
			failures.append("player.get_hand_global_positions() did not return LeftHand/RightHand bone positions!")
		else:
			var bit_l := (donkey.get_node("BodyRoot/NeckPivot/HeadPivot/BitRing_L") as Marker3D).global_position
			var rein_l := donkey.get_node("Rein_L") as MeshInstance3D
			var expected_mid_l := (bit_l + (hands["left"] as Vector3)) * 0.5
			var rein_err := rein_l.global_position.distance_to(expected_mid_l)
			if rein_err > 0.03:
				failures.append("Rein_L did not connect BitRing_L to rider LeftHand! err=%.3fm" % rein_err)
			else:
				print("[PASS] Reins Track Rider Hands: LeftHand=%s RightHand=%s (Rein_L err=%.4fm)" % [
					str((hands["left"] as Vector3).snapped(Vector3(0.01,0.01,0.01))),
					str((hands["right"] as Vector3).snapped(Vector3(0.01,0.01,0.01))),
					rein_err
				])

		var skel := player._donkey_rider_skeleton
		if skel == null:
			failures.append("Rider skeleton not cached for leg straddle!")
		else:
			var l_knee_idx := player._find_rider_bone(skel, ["mixamorig_LeftLeg", "LeftLeg"])
			var r_knee_idx := player._find_rider_bone(skel, ["mixamorig_RightLeg", "RightLeg"])
			if l_knee_idx >= 0 and r_knee_idx >= 0:
				var l_knee_local := donkey.to_local(skel.global_transform * skel.get_bone_global_pose(l_knee_idx).origin)
				var r_knee_local := donkey.to_local(skel.global_transform * skel.get_bone_global_pose(r_knee_idx).origin)
				var spread := r_knee_local.x - l_knee_local.x
				if spread < 0.36:
					failures.append("Rider legs not straddling saddle wide enough! L_x=%.3f R_x=%.3f spread=%.3f" % [l_knee_local.x, r_knee_local.x, spread])
				else:
					print("[PASS] Natural Leg Straddle: LeftKnee_x=%.3fm, RightKnee_x=%.3fm (spread=%.3fm around 0.54m saddle)" % [
						l_knee_local.x, r_knee_local.x, spread
					])

		# Drive donkey forward + steer + trot for 40 frames
		var start_pos := donkey.global_position
		var start_cart_pos := mock_cart.global_position
		var max_leg_diff := 0.0
		var max_tail_sway := 0.0
		for _i in range(40):
			donkey.set_rider_inputs(1.0, 0.35, true)
			await process_frame
			var leg_fl := (donkey.get_node("BodyRoot/Leg_FL") as Node3D).rotation.x
			var leg_fr := (donkey.get_node("BodyRoot/Leg_FR") as Node3D).rotation.x
			max_leg_diff = maxf(max_leg_diff, absf(leg_fl - leg_fr))
			max_tail_sway = maxf(max_tail_sway, absf(tail_piv.rotation.z))

		var moved_dist := start_pos.distance_to(donkey.global_position)
		var cart_moved := start_cart_pos.distance_to(mock_cart.global_position)
		if moved_dist < 1.2:
			failures.append("Donkey did not trot forward under rider input! dist=%.2f" % moved_dist)
		elif max_leg_diff < 0.25:
			failures.append("Donkey 4-leg diagonal gait did not animate! max_leg_diff=%.3f" % max_leg_diff)
		elif max_tail_sway < 0.05:
			failures.append("Donkey tail pendulum sway did not animate! max_tail_sway=%.3f" % max_tail_sway)
		elif cart_moved < 0.8:
			failures.append("Hitched Karo cart did not follow donkey! cart_moved=%.2f" % cart_moved)
		else:
			print("[PASS] Riding Test: Ride_Donkey clip active, trotted %.2fm, diagonal leg diff=%.2f rad, tail sway=%.2f rad, Karo cart towed %.2fm!" % [
				moved_dist, max_leg_diff, max_tail_sway, cart_moved
			])

		# Test clean dismount!
		player.dismount_donkey()
		await process_frame
		if donkey.is_mounted() or player.body_collider.disabled:
			failures.append("Player dismount_donkey() did not restore collider/unmounted state!")
		elif player.name_label != null and not player.name_label.visible:
			failures.append("Player name_label was not restored after dismount!")
		elif player.global_position.distance_to(donkey.global_position) < 0.70:
			failures.append("Player did not dismount cleanly to side exit! dist=%.2f" % player.global_position.distance_to(donkey.global_position))
		else:
			print("[PASS] Dismount Test: collider & nametag restored, safe side exit dist=%.2fm!" % player.global_position.distance_to(donkey.global_position))

	player.queue_free()
	donkey.queue_free()
	mock_cart.queue_free()
	ground.queue_free()
	await process_frame

	if failures.is_empty():
		print("=== DONKEY OVERHAUL AUDIT: ALL CHECKS PASSED (0 FAILURES) ===")
		quit(0)
	else:
		print("=== DONKEY OVERHAUL AUDIT: %d FAILURES ===" % failures.size())
		for f in failures:
			print("  [FAIL] " + f)
		quit(1)
