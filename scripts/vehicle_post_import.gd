@tool
extends EditorScenePostImport

## Post-import processor for vehicle pack FBX models (`assets/models/vehicles/pack/`).
## Enforces bright PBR shading (`vertex_color_use_as_albedo = false`, `metallic = 0.0`,
## `roughness = 0.75`) and semi-transparent glass (`a = 0.25`) on window surfaces.


func _post_import(scene: Node) -> Object:
	_process_node(scene)
	return scene


func _process_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s_idx in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s_idx)
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					var mname := bm.resource_name.to_lower()
					bm.vertex_color_use_as_albedo = false
					bm.metallic = 0.0
					bm.roughness = 0.75
					if "window" in mname or "glass" in mname:
						bm.albedo_color = Color(0.85, 0.93, 1.0, 0.12)
						bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						bm.cull_mode = BaseMaterial3D.CULL_DISABLED
						bm.roughness = 0.10

	for ch in node.get_children():
		_process_node(ch)
