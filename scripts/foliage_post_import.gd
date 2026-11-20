@tool
extends EditorScenePostImport

## Performance-Optimized Post-Import processor for imported foliage in Godot 4.7.2.
## - Uses fast `TRANSPARENCY_ALPHA_SCISSOR` (`alpha_scissor_threshold = 0.45`, no costly ALPHA_TO_COVERAGE)
## - Disables `backlight_enabled` for optimal GL Compatibility fillrate
## - Keeps bark & opaque 3D foliage strictly opaque (`TRANSPARENCY_DISABLED`)
## - Removes stray ground pedestal mesh nodes if present.

const PEDESTAL_KEYWORDS: Array[String] = [
	"pedestal", "ground_disc", "base_disc", "floor_plane", "stand_plate",
]


func _post_import(scene: Node) -> Object:
	var src_path := get_source_file()
	_process_node(scene, src_path)
	return scene


func _process_node(node: Node, src_path: String) -> void:
	var lname := node.name.to_lower()
	for kw in PEDESTAL_KEYWORDS:
		if kw in lname:
			node.free()
			return

	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s_idx in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s_idx)
				if mat is StandardMaterial3D:
					var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					_configure_surface_material(std, src_path)
					mi.mesh.surface_set_material(s_idx, std)

	for ch in node.get_children():
		_process_node(ch, src_path)


func _configure_surface_material(std: StandardMaterial3D, src_path: String) -> void:
	var mname := std.resource_name.to_lower()
	var tpath := std.albedo_texture.resource_path.to_lower() if std.albedo_texture != null else ""
	var src_low := src_path.to_lower()

	var is_bark := (
		"trunk" in mname
		or "bark" in mname
		or "branch" in mname
		or "twig" in mname
		or mname == "island_tree_02"
	)
	var is_leaf := (not is_bark) and (
		"leaf" in mname
		or "leaves" in mname
		or "foliage" in mname
		or "shrub" in src_low
		or "bush" in src_low
		or "rgba" in tpath
	)
	var has_alpha_tex := tpath.ends_with(".png") or tpath.ends_with(".webp") or "rgba" in tpath or "alpha" in tpath

	std.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	std.metallic = 0.0
	std.backlight_enabled = false
	std.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF

	if is_leaf:
		std.cull_mode = BaseMaterial3D.CULL_DISABLED
		std.roughness = 0.85
		if has_alpha_tex:
			std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			std.alpha_scissor_threshold = 0.45
			std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		else:
			std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	else:
		std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		std.cull_mode = BaseMaterial3D.CULL_BACK
		std.roughness = 0.90
