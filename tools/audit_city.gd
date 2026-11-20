extends SceneTree

## Headless 3-Pass City, Role-NPC, Animation & Grounding Audit (`tools/audit_city.gd`).
## Run with: Godot_v4.7.2-stable_win64.exe --headless --path . -s tools/audit_city.gd

func _initialize() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if not packed:
		push_error("[AUDIT] Failed to load res://scenes/main.tscn")
		quit(1)
		return

	var main_inst := packed.instantiate()
	root.add_child(main_inst)

	# Allow _ready(), call_deferred spawns, and physics settle frames to run
	for _i in range(6):
		await process_frame
		await physics_frame

	print("============================================================")
	print("[AUDIT PASS 1] INFRASTRUCTURE, CLEARANCE & LANDMARKS")
	print("============================================================")

	var builders := get_nodes_in_group("city_mega_builder")
	if builders.is_empty():
		push_error("[AUDIT] CityMegaBuilder node not found!")
		quit(1)
		return

	var builder := builders[0]
	var records: Array = builder.get_building_records()
	var ramp_audits: Array = builder.get_ramp_audits()
	var tunnel_audits: Array = builder.get_tunnel_audits()
	var bakeries := get_nodes_in_group("automated_bakeries")

	var mosques_found: Array[String] = []
	for node_path in [
		"Neighborhood/Buildings/MosqueAzhari",
		"CityExpansion/MegaLandmarks/Mosque_NileGrand",
		"CityExpansion/MegaLandmarks/Mosque_WestHeritage",
		"CityExpansion/MegaLandmarks/Mosque_AlNoor",
	]:
		if main_inst.get_node_or_null(node_path) != null:
			mosques_found.append(node_path.get_file())

	# Check pairwise building overlaps among generated buildings & landmarks
	var building_overlaps := 0
	var b_rects: Array[Rect2] = []
	for rec in records:
		var p: Vector3 = rec["pos"]
		var sz: Vector2 = rec["size"]
		b_rects.append(Rect2(p.x - sz.x * 0.5, p.z - sz.y * 0.5, sz.x, sz.y))
	for i in range(b_rects.size()):
		for j in range(i + 1, b_rects.size()):
			if b_rects[i].intersects(b_rects[j]):
				building_overlaps += 1
				push_error("[AUDIT] Building overlap: %s vs %s" % [records[i]["name"], records[j]["name"]])

	# Check Nile channel & core protection
	var nile_water_rect := Rect2(-235.0, -700.0, 90.0, 1400.0)
	var core_rect := Rect2(-132.0, -132.0, 264.0, 264.0)
	var zone_conflicts := 0
	for i in range(b_rects.size()):
		var r := b_rects[i]
		if r.intersects(nile_water_rect):
			zone_conflicts += 1
			push_error("[AUDIT] Building in Nile water: %s" % records[i]["name"])
		if r.intersects(core_rect):
			zone_conflicts += 1
			push_error("[AUDIT] Building intrudes into original core: %s" % records[i]["name"])

	var max_ramp_angle := 0.0
	for ra in ramp_audits:
		max_ramp_angle = maxf(max_ramp_angle, float(ra["angle_deg"]))
		if float(ra["angle_deg"]) > 12.0:
			push_error("[AUDIT] Ramp angle > 12 deg: %s (%.2f)" % [ra["name"], ra["angle_deg"]])

	var min_tunnel_clearance := 999.0
	for ta in tunnel_audits:
		min_tunnel_clearance = minf(min_tunnel_clearance, float(ta["clearance"]))
		if float(ta["clearance"]) < 6.0 or float(ta["width"]) < 14.0:
			push_error("[AUDIT] Tunnel below spec: %s" % str(ta))

	print("Buildings generated/landmarks: %d" % records.size())
	print("Mosques present (%d): %s" % [mosques_found.size(), ", ".join(mosques_found)])
	print("Automated bakeries in group: %d" % bakeries.size())
	print("Ramps audited: %d (max angle = %.2f deg)" % [ramp_audits.size(), max_ramp_angle])
	print("Tunnels audited: %d (min clearance = %.2fm)" % [tunnel_audits.size(), min_tunnel_clearance])
	print("Building overlaps: %d | Core/Water conflicts: %d" % [building_overlaps, zone_conflicts])

	print("============================================================")
	print("[AUDIT PASS 2] ROLE NPCs, MIXAMO ANIMATION & GROUNDING")
	print("============================================================")

	var role_spawners := get_nodes_in_group("role_npc_spawner")
	var role_counts: Dictionary = {}
	var role_total := 0
	var anim_active_ok := 0
	var anim_inactive := 0
	var bone_gear_ok := 0
	var bright_tex_ok := 0

	if not role_spawners.is_empty():
		var r_npcs: Array = role_spawners[0].get_role_npcs()
		role_total = r_npcs.size()
		for npc in r_npcs:
			var r_name := str(npc.get_meta("npc_role", "unknown"))
			role_counts[r_name] = int(role_counts.get(r_name, 0)) + 1
			var at := _find_anim_tree(npc)
			if at and at.active:
				anim_active_ok += 1
			else:
				anim_inactive += 1
			if _has_bone_attachment(npc):
				bone_gear_ok += 1
			if _has_bright_textured_mesh(npc):
				bright_tex_ok += 1

	# Also check roaming CrowdSpawner NPCs
	var all_npcs := get_nodes_in_group("npcs")
	var crowd_anim_ok := 0
	var crowd_anim_bad := 0
	for n in all_npcs:
		var at := _find_anim_tree(n)
		if at and at.active:
			crowd_anim_ok += 1
		else:
			crowd_anim_bad += 1

	print("Role NPCs spawned: %d | Roles: %s" % [role_total, str(role_counts)])
	print("Role NPCs AnimationTree active: %d/%d (inactive=%d)" % [anim_active_ok, role_total, anim_inactive])
	print("Role NPCs BoneAttachment gear: %d/%d | Bright textured mesh: %d/%d" % [bone_gear_ok, role_total, bright_tex_ok, role_total])
	print("All NPCs (Role + Crowd) active AnimationTree: %d/%d (inactive=%d)" % [crowd_anim_ok, all_npcs.size(), crowd_anim_bad])

	# Grounding audit on all live vehicles in scene (parked, AI traffic, buses)
	var live_vehicles := get_nodes_in_group("vehicles")
	var veh_ground_issues := 0
	for vnode in live_vehicles:
		var v3 := vnode as Node3D
		if v3:
			var min_y := _compute_world_mesh_min_y(v3)
			var dy := min_y - v3.global_position.y
			if dy < -0.15 or dy > 0.25:
				veh_ground_issues += 1
				print("[AUDIT] Vehicle ground warning: %s rel_min_y=%.3f (pos.y=%.3f)" % [v3.name, dy, v3.global_position.y])
	print("Live vehicles audited: %d (ground warnings=%d)" % [live_vehicles.size(), veh_ground_issues])

	# Check visibility_range_end usage on MegaBuildings & MegaLandmarks
	var vis_capped := _count_vis_capped(main_inst.get_node("CityExpansion"))
	print("CityExpansion GeometryInstances with visibility_range_end > 0: %d" % vis_capped)

	var total_failures := building_overlaps + zone_conflicts + anim_inactive + crowd_anim_bad
	if mosques_found.size() < 4 or bakeries.size() < 6 or max_ramp_angle > 12.0 or min_tunnel_clearance < 6.0:
		total_failures += 1

	print("============================================================")
	print("[AUDIT SUMMARY] failures=%d | vehicle_ground_warnings=%d" % [total_failures, veh_ground_issues])
	print("============================================================")
	main_inst.queue_free()
	await process_frame
	quit(1 if total_failures > 0 else 0)


func _find_anim_tree(node: Node) -> AnimationTree:
	if node is AnimationTree:
		return node as AnimationTree
	for c in node.get_children():
		var found := _find_anim_tree(c)
		if found:
			return found
	return null


func _has_bone_attachment(node: Node) -> bool:
	if node is BoneAttachment3D:
		return true
	for c in node.get_children():
		if _has_bone_attachment(c):
			return true
	return false


func _has_bright_textured_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh and not (mi.get_parent() is BoneAttachment3D):
			for s in range(mi.get_surface_override_material_count()):
				var mat := mi.get_surface_override_material(s) as StandardMaterial3D
				if mat and mat.albedo_texture != null and mat.metallic < 0.05:
					return true
			for s in range(mi.mesh.get_surface_count()):
				var smat := mi.mesh.surface_get_material(s) as StandardMaterial3D
				if smat and smat.albedo_texture != null and smat.metallic < 0.05:
					return true
	for c in node.get_children():
		if _has_bright_textured_mesh(c):
			return true
	return false


func _compute_world_mesh_min_y(node: Node) -> float:
	var min_y := 999.0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.visible and mi.mesh:
			var n_lower := mi.name.to_lower()
			if not ("dust" in n_lower or "smoke" in n_lower or "shadow" in n_lower):
				var aabb := mi.mesh.get_aabb()
				var xf := mi.global_transform
				for corner_idx in range(8):
					var cx := aabb.position.x + (aabb.size.x if (corner_idx & 1) else 0.0)
					var cy := aabb.position.y + (aabb.size.y if (corner_idx & 2) else 0.0)
					var cz := aabb.position.z + (aabb.size.z if (corner_idx & 4) else 0.0)
					min_y = minf(min_y, (xf * Vector3(cx, cy, cz)).y)
	for c in node.get_children():
		min_y = minf(min_y, _compute_world_mesh_min_y(c))
	return min_y


func _count_vis_capped(node: Node) -> int:
	if not node:
		return 0
	var count := 0
	if node is GeometryInstance3D:
		if (node as GeometryInstance3D).visibility_range_end > 0.0:
			count += 1
	for c in node.get_children():
		count += _count_vis_capped(c)
	return count
