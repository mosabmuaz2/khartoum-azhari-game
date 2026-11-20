@tool
extends EditorScenePostImport

## Post-import processor for Mixamo FBX characters & animations in Godot 4.7.2.
## Enforces bright, double-sided matte PBR character materials (`metallic = 0.0`,
## `roughness = 0.85`, `cull_mode = BaseMaterial3D.CULL_DISABLED`, `albedo_color = Color(1,1,1,1)`,
## `vertex_color_use_as_albedo = false`), auto-binds folder `*_albedo.png` textures if dropped by
## Mixamo, and sets linear looping on idle/locomotion/swimming clips.

const LOOP_CLIPS: Array[String] = [
	"idle", "walking", "running", "crouch idle", "crouch walk",
	"sitting", "driving", "talking", "swimming", "treading",
]


func _post_import(scene: Node) -> Object:
	var src_path := get_source_file()
	var src_low := src_path.to_lower()
	var fallback_tex := _find_folder_albedo_texture(src_path)
	_process_node_recursive(scene, src_low, fallback_tex)
	return scene


func _find_folder_albedo_texture(src_path: String) -> Texture2D:
	if src_path.is_empty():
		return null
	var folder := src_path.get_base_dir()
	var stem := src_path.get_file().get_basename().to_lower()
	var d := DirAccess.open(folder)
	if d == null:
		return null
	var best_albedo := ""
	var any_png := ""
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if not d.current_is_dir():
			var ext := fn.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "webp"]:
				var low := fn.to_lower()
				var full := folder.path_join(fn)
				if low == stem + "_albedo.png" or ("albedo" in low and best_albedo.is_empty()):
					best_albedo = full
				elif low == stem + "_0.png" and best_albedo.is_empty():
					best_albedo = full
				elif any_png.is_empty():
					any_png = full
		fn = d.get_next()
	d.list_dir_end()
	var chosen := best_albedo if not best_albedo.is_empty() else any_png
	if not chosen.is_empty() and ResourceLoader.exists(chosen):
		return ResourceLoader.load(chosen) as Texture2D
	return null


func _process_node_recursive(node: Node, src_low: String, fallback_tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s_idx in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s_idx)
				var bm: StandardMaterial3D
				if mat is StandardMaterial3D:
					bm = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				else:
					bm = StandardMaterial3D.new()
					if mat is BaseMaterial3D:
						bm.albedo_texture = (mat as BaseMaterial3D).albedo_texture
				if bm.albedo_texture == null and fallback_tex != null:
					bm.albedo_texture = fallback_tex
				bm.vertex_color_use_as_albedo = false
				bm.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
				bm.metallic = 0.0
				bm.roughness = 0.85
				bm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				bm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
				bm.cull_mode = BaseMaterial3D.CULL_DISABLED
				bm.backlight_enabled = true
				bm.backlight = Color(0.35, 0.33, 0.30, 1.0)
				mi.mesh.surface_set_material(s_idx, bm)
	elif node is AnimationPlayer:
		var ap := node as AnimationPlayer
		var should_loop := false
		for kw in LOOP_CLIPS:
			if kw in src_low:
				should_loop = true
				break
		for a_name in ap.get_animation_list():
			if a_name == "RESET":
				continue
			var anim := ap.get_animation(a_name)
			if anim != null and should_loop:
				anim.loop_mode = Animation.LOOP_LINEAR

	for ch in node.get_children():
		_process_node_recursive(ch, src_low, fallback_tex)
