extends SceneTree

func _init() -> void:
	call_deferred("_measure")


func _measure() -> void:
	var ps := ResourceLoader.load("res://scenes/main.tscn") as PackedScene
	var main := ps.instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame
	await process_frame

	var stats := {
		"mesh_instances": 0,
		"door_mesh_instances": 0,
		"door_count": 0,
		"door_active_physics_proc": 0,
		"multimesh_instances": 0,
		"total_physics_bodies": 0,
		"animatable_bodies": 0,
		"animatable_sync_active": 0,
		"shadow_casting_meshes": 0,
		"tree_nodes": 0,
	}
	_walk(main, false, stats)
	print("=== PERF METRICS ===")
	for k in stats.keys():
		print("  %s: %d" % [k, stats[k]])

	# Also inspect island_tree_02 and quiver_tree_01 mesh surface triangle counts
	for p in [
		"res://assets/models/foliage/island_tree_02/island_tree_02.gltf",
		"res://assets/models/foliage/quiver_tree_01/quiver_tree_01.gltf",
	]:
		var tp := ResourceLoader.load(p) as PackedScene
		if tp != null:
			var inst := tp.instantiate()
			var tris := _count_tris(inst)
			print("  asset_tris[%s]: %d" % [p.get_file(), tris])
			inst.free()

	main.queue_free()
	await process_frame
	quit(0)


func _walk(n: Node, inside_door: bool, stats: Dictionary) -> void:
	var in_d := inside_door
	if n is InteractiveDoor:
		in_d = true
		stats["door_count"] += 1
		if n.is_physics_processing():
			stats["door_active_physics_proc"] += 1
	if n is SudaneseTreeBuilder:
		stats["tree_nodes"] += 1
	if n is MeshInstance3D:
		stats["mesh_instances"] += 1
		if in_d:
			stats["door_mesh_instances"] += 1
		if (n as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			stats["shadow_casting_meshes"] += 1
	elif n is MultiMeshInstance3D:
		stats["multimesh_instances"] += 1
	if n is PhysicsBody3D:
		stats["total_physics_bodies"] += 1
		if n is AnimatableBody3D:
			stats["animatable_bodies"] += 1
			if (n as AnimatableBody3D).sync_to_physics:
				stats["animatable_sync_active"] += 1
	for c in n.get_children():
		_walk(c, in_d, stats)


func _count_tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m := (n as MeshInstance3D).mesh
		for si in range(m.get_surface_count()):
			var arrs := m.surface_get_arrays(si)
			var idx: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
			if not idx.is_empty():
				t += idx.size() / 3
			else:
				var v: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
				t += v.size() / 3
	for c in n.get_children():
		t += _count_tris(c)
	return t
