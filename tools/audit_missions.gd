extends SceneTree

## Headless verification test for the 12-Mission System (`tools/audit_missions.gd`).
## Run with: Godot_v4.7.2-stable_win64.exe --headless --path . -s tools/audit_missions.gd

func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if not packed:
		push_error("[MISSION_AUDIT] Failed to load res://scenes/main.tscn")
		quit(1)
		return

	var main_inst := packed.instantiate()
	root.add_child(main_inst)
	current_scene = main_inst

	for _i in range(6):
		await process_frame
		await physics_frame

	var failures := 0
	var mm := root.get_node_or_null("MissionManager")
	if not mm:
		push_error("[MISSION_AUDIT] MissionManager autoload missing!")
		quit(1)
		return

	var hud := main_inst.get_node_or_null("MissionHUD")
	if not hud:
		push_error("[MISSION_AUDIT] MissionHUD node missing in main.tscn!")
		failures += 1

	var all_m: Array = mm.get_all_missions()
	var small_m: Array = mm.get_small_missions()
	var large_m: Array = mm.get_large_missions()
	print("============================================================")
	print("[MISSION AUDIT] Catalog: total=%d | small=%d | large=%d" % [all_m.size(), small_m.size(), large_m.size()])
	if all_m.size() < 12 or small_m.size() < 7 or large_m.size() < 5:
		push_error("[MISSION_AUDIT] Expected >=12 missions (7 small, 5 large)")
		failures += 1

	# Test Mission Board toggle & card generation
	if hud:
		hud.open_board()
		await process_frame
		var s_cards: int = hud.small_list.get_child_count()
		var l_cards: int = hud.large_list.get_child_count()
		print("Mission Board cards rendered: small=%d, large=%d" % [s_cards, l_cards])
		if s_cards != small_m.size() or l_cards != large_m.size():
			push_error("[MISSION_AUDIT] Mission Board card count mismatch!")
			failures += 1
		hud.close_board()

	# Verify CarWashBay has zero overlap with CityMegaBuilder buildings
	var builders := get_nodes_in_group("city_mega_builder")
	if not builders.is_empty():
		var car_wash_rect := Rect2(182.0, -36.0, 12.0, 16.0)
		var wash_overlap := 0
		for rec in builders[0].get_building_records():
			var bp: Vector3 = rec["pos"]
			var bsz: Vector2 = rec["size"]
			var br := Rect2(bp.x - bsz.x * 0.5, bp.z - bsz.y * 0.5, bsz.x, bsz.y)
			if car_wash_rect.intersects(br):
				wash_overlap += 1
				push_error("[MISSION_AUDIT] CarWash overlaps %s" % str(rec["name"]))
		print("CarWashBay clearance overlaps: %d" % wash_overlap)
		failures += wash_overlap

	# Start, inspect beacon + steps, and cancel every single one of the 12 missions
	var started_ok := 0
	for m in all_m:
		var m_id := str(m["id"])
		var ok: bool = mm.start_mission(m_id)
		await process_frame
		var wp: Dictionary = mm.get_active_waypoint()
		var steps_n: int = (mm.active_steps as Array).size()
		var beacon := main_inst.get_node_or_null("MissionWorldSystem/MissionBeacon") as Node3D
		if not ok or wp.is_empty() or steps_n <= 0 or not beacon or not beacon.visible:
			push_error("[MISSION_AUDIT] Mission failed to activate cleanly: %s" % m_id)
			failures += 1
		else:
			started_ok += 1
			if m_id == "large_khartoum_rally" and steps_n != 15:
				push_error("[MISSION_AUDIT] Rally should have 15 checkpoints, got %d" % steps_n)
				failures += 1
			if m_id == "large_engineer_inspection" and steps_n != 7:
				push_error("[MISSION_AUDIT] Engineer inspection should have 7 stages, got %d" % steps_n)
				failures += 1
		mm.cancel_mission()
		await process_frame

	print("All 12 missions start/beacon/cancel test: %d/%d passed" % [started_ok, all_m.size()])

	# Simulate complete mission run (rewards SDG + XP + level + HUD wallet update)
	var before_sdg: int = int(mm.sdg_cash)
	var before_xp: int = int(mm.xp)
	mm.start_mission("large_mosques_supply")
	var safety := 0
	while mm.is_mission_active() and safety < 20:
		mm._advance_step()
		safety += 1
	await process_frame
	var gained_sdg: int = int(mm.sdg_cash) - before_sdg
	var gained_xp: int = int(mm.xp) - before_xp
	print("Simulated completion (large_mosques_supply): +%d SDG, +%d XP, wallet='%s'" % [
		gained_sdg, gained_xp, hud.wallet_label.text if hud else ""
	])
	if gained_sdg != 14000 or gained_xp != 500 or mm.is_mission_active():
		push_error("[MISSION_AUDIT] Reward payout or completion state invalid!")
		failures += 1

	# Confirm role NPCs & Mixamo AnimationTrees remain 100% active
	var all_npcs := get_nodes_in_group("npcs")
	var active_anim := 0
	for n in all_npcs:
		var at := _find_anim_tree(n)
		if at and at.active:
			active_anim += 1
	print("NPC Mixamo AnimationTree active: %d/%d" % [active_anim, all_npcs.size()])
	if active_anim != all_npcs.size():
		failures += 1

	print("============================================================")
	print("[MISSION AUDIT SUMMARY] failures=%d" % failures)
	print("============================================================")

	main_inst.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


func _find_anim_tree(node: Node) -> AnimationTree:
	if node is AnimationTree:
		return node as AnimationTree
	for c in node.get_children():
		var found := _find_anim_tree(c)
		if found:
			return found
	return null
