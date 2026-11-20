extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var main_ps := load("res://scenes/main.tscn") as PackedScene
	if not main_ps:
		printerr("[AUDIT FAIL] Cannot load res://scenes/main.tscn")
		quit(1)
		return

	var main_inst := main_ps.instantiate()
	root.add_child(main_inst)
	# Allow deferred RoleNPCSpawner & scene setups to run
	for _i in range(4):
		await process_frame

	# 1. Verify CityMegaBuilder triplanar materials
	var builders := get_nodes_in_group("city_mega_builder")
	if builders.is_empty():
		failures.append("No city_mega_builder found in scene")
	else:
		var cmb := builders[0]
		var pmats: Array = cmb.get("_palette_mats")
		if pmats.is_empty():
			failures.append("CityMegaBuilder._palette_mats is empty")
		else:
			var non_triplanar := 0
			for m in pmats:
				if m is StandardMaterial3D:
					var sm := m as StandardMaterial3D
					if not sm.uv1_triplanar or sm.uv1_scale.x > 0.65:
						non_triplanar += 1
			if non_triplanar > 0:
				failures.append("CityMegaBuilder has %d palette mats without proper uv1_triplanar scale" % non_triplanar)

		var mat_conc = cmb.get("_mat_concrete")
		if mat_conc is StandardMaterial3D and not (mat_conc as StandardMaterial3D).uv1_triplanar:
			failures.append("CityMegaBuilder._mat_concrete missing uv1_triplanar")

		# 2. Verify SecondaryNeighborhoodStreets exists and is merged into 1 ArrayMesh
		var roads_root := cmb.get_node_or_null("MegaRoads")
		var sec_streets := roads_root.get_node_or_null("SecondaryNeighborhoodStreets") as MeshInstance3D if roads_root else null
		if not sec_streets or not (sec_streets.mesh is ArrayMesh) or (sec_streets.mesh as ArrayMesh).get_surface_count() < 2:
			failures.append("SecondaryNeighborhoodStreets missing or not a merged multi-surface ArrayMesh")
		else:
			print("[AUDIT OK] SecondaryNeighborhoodStreets merged ArrayMesh surfaces=%d vis=%.1f" % [
				(sec_streets.mesh as ArrayMesh).get_surface_count(), sec_streets.visibility_range_end
			])

		# 3. Verify EVERY CityBld_* has InteractiveDoor + MergedBuildingDetails (ArrayMesh, vis=130.0)
		var bld_root := cmb.get_node_or_null("MegaBuildings")
		var total_blds := 0
		var south_infill_blds := 0
		var missing_doors := 0
		var missing_details := 0
		var missing_courtyard_gates := 0
		if bld_root:
			for ch in bld_root.get_children():
				if ch.name.begins_with("CityBld_"):
					total_blds += 1
					var p: Vector3 = (ch as Node3D).position
					if p.z >= 136.0 and p.z <= 232.0:
						south_infill_blds += 1
					var door_count := 0
					var has_gate := false
					for sub in ch.get_children():
						if sub is InteractiveDoor:
							door_count += 1
							if sub.name == "CourtyardGate" or sub.name == "HoshStreetGate":
								has_gate = true
					if door_count == 0:
						missing_doors += 1
					if (ch.name.ends_with("_S0") or ch.name.ends_with("_S1") or ch.name.ends_with("_S5")) and not has_gate:
						missing_courtyard_gates += 1
					var det := ch.get_node_or_null("MergedBuildingDetails") as MeshInstance3D
					if not det or not (det.mesh is ArrayMesh) or (det.mesh as ArrayMesh).get_surface_count() == 0 or not is_equal_approx(det.visibility_range_end, 130.0):
						missing_details += 1
		if total_blds < 120:
			failures.append("Expected >= 120 CityBld_* buildings, found %d" % total_blds)
		if south_infill_blds < 8:
			failures.append("Expected >= 8 Southern Al-Azhari Extension infill buildings (z in [136..232]), found %d" % south_infill_blds)
		if missing_doors > 0:
			failures.append("%d CityBld_* buildings have ZERO InteractiveDoor" % missing_doors)
		if missing_courtyard_gates > 0:
			failures.append("%d residential CityBld_* (Styles 0/1/5) missing CourtyardGate" % missing_courtyard_gates)
		if missing_details > 0:
			failures.append("%d CityBld_* buildings missing MergedBuildingDetails (ArrayMesh vis=130)" % missing_details)
		print("[AUDIT INFO] CityBld_* total=%d south_infill=%d missing_doors=%d missing_gates=%d missing_details=%d" % [
			total_blds, south_infill_blds, missing_doors, missing_courtyard_gates, missing_details
		])

		# 4. Verify OuterNeighborhoodStreetLife sectors + MultiMesh trees
		var street_life := bld_root.get_node_or_null("OuterNeighborhoodStreetLife") if bld_root else null
		if not street_life:
			failures.append("OuterNeighborhoodStreetLife missing under MegaBuildings")
		else:
			var sector_meshes := 0
			for sname in ["Sector_SouthEastCore", "Sector_SouthWestCorniche", "Sector_NorthOuterBlocks"]:
				var sn := street_life.get_node_or_null(sname)
				var smi := sn.get_node_or_null("MergedSectorStreetLife") as MeshInstance3D if sn else null
				if smi and smi.mesh is ArrayMesh and (smi.mesh as ArrayMesh).get_surface_count() > 0 and is_equal_approx(smi.visibility_range_end, 130.0):
					sector_meshes += 1
				else:
					failures.append("Missing or invalid MergedSectorStreetLife in %s" % sname)
			var outer_tree_count := 0
			for tname in ["OuterNeemTrees", "OuterAcaciaTrees"]:
				var tn := street_life.get_node_or_null(tname)
				if not tn:
					failures.append("Missing %s under OuterNeighborhoodStreetLife" % tname)
				else:
					for mmi in tn.get_children():
						if mmi is MultiMeshInstance3D and (mmi as MultiMeshInstance3D).multimesh:
							outer_tree_count += (mmi as MultiMeshInstance3D).multimesh.instance_count
							break
			print("[AUDIT OK] OuterNeighborhoodStreetLife sectors=%d/3 outer_shade_trees=%d" % [sector_meshes, outer_tree_count])
			if outer_tree_count < 20:
				failures.append("Expected >= 20 outer Neem/Acacia shade trees, found %d" % outer_tree_count)

	# 5. Verify ClosedHouse instances anywhere in main.tscn have HouseFrontDoor + triplanar brick
	var closed_list := _find_nodes_by_prefix(main_inst, "ClosedHouse")
	var closed_houses := closed_list.size()
	var closed_missing_door := 0
	for n in closed_list:
		if not (n.get_node_or_null("HouseFrontDoor") is InteractiveDoor):
			closed_missing_door += 1
	if closed_houses == 0:
		failures.append("Expected ClosedHouse instances in main.tscn, found 0")
	if closed_missing_door > 0:
		failures.append("%d ClosedHouse nodes missing HouseFrontDoor" % closed_missing_door)
	print("[AUDIT OK] ClosedHouse nodes=%d (missing doors=%d)" % [closed_houses, closed_missing_door])

	# Verify brick materials on all 5 core building scenes have uv1_triplanar = true
	for spath in [
		"res://scenes/buildings/closed_house.tscn",
		"res://scenes/buildings/commercial_strip.tscn",
		"res://scenes/buildings/interactive_compound.tscn",
		"res://scenes/buildings/interactive_dukkan.tscn",
		"res://scenes/buildings/sudanese_house.tscn",
	]:
		var txt := FileAccess.get_file_as_string(spath)
		if txt.find("uv1_triplanar = true") < 0:
			failures.append("%s missing uv1_triplanar = true on brick/plaster materials" % spath)

	# 6. Verify distance-culled outer ambient NPCs (110m radius)
	var spawners := get_nodes_in_group("role_npc_spawner")
	var culled_outer_npcs := 0
	var outer_vendors := 0
	var outer_elders := 0
	var outer_pedestrians := 0
	if not spawners.is_empty():
		var npcs: Array = spawners[0].get_role_npcs()
		for npc in npcs:
			if "ai_activation_radius" in npc and is_equal_approx(float(npc.ai_activation_radius), 110.0):
				culled_outer_npcs += 1
				var r := str(npc.get_meta("npc_role", ""))
				if r == "vendor":
					outer_vendors += 1
				elif r == "elder":
					outer_elders += 1
				elif r == "pedestrian":
					outer_pedestrians += 1
	print("[AUDIT INFO] Distance-culled (110m) outer NPCs=%d (vendors=%d elders=%d pedestrians=%d)" % [
		culled_outer_npcs, outer_vendors, outer_elders, outer_pedestrians
	])
	if culled_outer_npcs < 15:
		failures.append("Expected >= 15 distance-culled (110m) outer ambient NPCs, found %d" % culled_outer_npcs)

	if failures.is_empty():
		print("[AUDIT PASS] Outer & southern neighborhood overhaul verified with 0 failures!")
		quit(0)
	else:
		for f in failures:
			printerr("[AUDIT FAIL] %s" % f)
		quit(1)


func _find_nodes_by_prefix(node: Node, prefix: String) -> Array[Node]:
	var out: Array[Node] = []
	if node.name.begins_with(prefix):
		out.append(node)
	for ch in node.get_children():
		out.append_array(_find_nodes_by_prefix(ch, prefix))
	return out
