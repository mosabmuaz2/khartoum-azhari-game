extends Node3D
class_name FoliageWind

## High-FPS Foliage Wind & Material Optimizer for Godot 4.7.2 (GL Compatibility).
## - Uses fast `TRANSPARENCY_ALPHA_SCISSOR` (`alpha_scissor_threshold = 0.45`, no ALPHA_TO_COVERAGE)
## - Disables costly backlight pass while preserving vibrant foliage & gentle breeze sway.

const WIND_CUTOUT_SHADER_PATH: String = "res://shaders/tree_wind.gdshader"
const WIND_OPAQUE_SHADER_PATH: String = "res://shaders/tree_canopy_wind.gdshader"

const LEAF_ALPHA_SCISSOR: float = 0.45

static var _cached_cutout_shader: Shader = null
static var _cached_opaque_shader: Shader = null


static func _ensure_shaders() -> void:
	if _cached_cutout_shader == null and ResourceLoader.exists(WIND_CUTOUT_SHADER_PATH):
		_cached_cutout_shader = ResourceLoader.load(WIND_CUTOUT_SHADER_PATH) as Shader
	if _cached_opaque_shader == null and ResourceLoader.exists(WIND_OPAQUE_SHADER_PATH):
		_cached_opaque_shader = ResourceLoader.load(WIND_OPAQUE_SHADER_PATH) as Shader


static func apply_to_tree(target_root: Node, strength: float = 0.11, speed: float = 1.45, phase: float = 0.0) -> void:
	_ensure_shaders()
	if _cached_cutout_shader == null or _cached_opaque_shader == null:
		return
	_apply_recursive(target_root, strength, speed, phase)


static func fix_standard_material(std: StandardMaterial3D, is_leaf_surface: bool, has_alpha_tex: bool = true) -> void:
	if std == null:
		return
	std.metallic = 0.0
	std.backlight_enabled = false
	std.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
	if is_leaf_surface:
		std.cull_mode = BaseMaterial3D.CULL_DISABLED
		std.roughness = 0.85
		if has_alpha_tex:
			std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			std.alpha_scissor_threshold = LEAF_ALPHA_SCISSOR
			std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		else:
			std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	else:
		std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		std.roughness = 0.90


static func create_canopy_wind_material(
	base_color: Color = Color(1.0, 1.0, 1.0, 1.0),
	use_vcolor: bool = true,
	strength: float = 0.09,
	speed: float = 1.45,
	min_sway_h: float = 1.4,
	phase: float = 0.0
) -> ShaderMaterial:
	_ensure_shaders()
	var smat := ShaderMaterial.new()
	smat.shader = _cached_opaque_shader
	smat.set_shader_parameter("albedo_color", base_color)
	smat.set_shader_parameter("use_vertex_color", use_vcolor)
	smat.set_shader_parameter("roughness_val", 0.85)
	smat.set_shader_parameter("metallic_val", 0.0)
	smat.set_shader_parameter("wind_strength", strength)
	smat.set_shader_parameter("wind_speed", speed)
	smat.set_shader_parameter("min_sway_height", min_sway_h)
	smat.set_shader_parameter("phase_offset", phase)
	return smat


static func convert_material(orig_mat: Material, strength: float = 0.11, speed: float = 1.45, phase: float = 0.0) -> ShaderMaterial:
	_ensure_shaders()
	var is_bark := false
	var is_leaf := false
	var has_alpha_tex := false

	if orig_mat is StandardMaterial3D:
		var std := orig_mat as StandardMaterial3D
		var mname := std.resource_name.to_lower()
		var tpath := std.albedo_texture.resource_path.to_lower() if std.albedo_texture != null else ""

		is_bark = (
			"trunk" in mname
			or "bark" in mname
			or "branch" in mname
			or "twig" in mname
			or mname == "island_tree_02"
		)
		has_alpha_tex = (
			tpath.ends_with(".png")
			or tpath.ends_with(".webp")
			or "rgba" in tpath
			or "alpha" in tpath
		)
		is_leaf = (not is_bark) and (
			"leaf" in mname
			or "leaves" in mname
			or "foliage" in mname
			or "shrub" in mname
			or "bush" in mname
			or has_alpha_tex
			or std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		)
		fix_standard_material(std, is_leaf, has_alpha_tex)

		var use_cutout := is_leaf and has_alpha_tex
		var smat := ShaderMaterial.new()
		smat.shader = _cached_cutout_shader if use_cutout else _cached_opaque_shader
		smat.set_shader_parameter("wind_strength", strength if is_leaf else 0.0)
		smat.set_shader_parameter("wind_speed", speed)
		smat.set_shader_parameter("phase_offset", phase)
		smat.set_shader_parameter("min_sway_height", 0.65 if is_leaf else 1.4)

		var col := std.albedo_color
		col.a = 1.0
		smat.set_shader_parameter("albedo_color", col)
		smat.set_shader_parameter("roughness_val", 0.85 if is_leaf else 0.90)
		smat.set_shader_parameter("metallic_val", 0.0)
		smat.set_shader_parameter("normal_strength", std.normal_scale if std.normal_enabled else 0.0)
		smat.set_shader_parameter("uv_scale", Vector2(std.uv1_scale.x, std.uv1_scale.y))
		smat.set_shader_parameter("uv_offset", Vector2(std.uv1_offset.x, std.uv1_offset.y))

		if std.albedo_texture != null:
			smat.set_shader_parameter("has_albedo_tex", true)
			smat.set_shader_parameter("texture_albedo", std.albedo_texture)
		if std.normal_enabled and std.normal_texture != null:
			smat.set_shader_parameter("has_normal_tex", true)
			smat.set_shader_parameter("normal_tex", std.normal_texture)
		if std.roughness_texture != null:
			smat.set_shader_parameter("has_roughness_tex", true)
			smat.set_shader_parameter("roughness_tex", std.roughness_texture)
		if use_cutout:
			smat.set_shader_parameter("use_alpha_cutout", true)
			smat.set_shader_parameter("alpha_scissor", LEAF_ALPHA_SCISSOR)
		else:
			smat.set_shader_parameter("use_vertex_color", std.vertex_color_use_as_albedo)
		return smat

	var fallback := ShaderMaterial.new()
	fallback.shader = _cached_opaque_shader
	fallback.set_shader_parameter("wind_strength", strength)
	fallback.set_shader_parameter("wind_speed", speed)
	fallback.set_shader_parameter("phase_offset", phase)
	return fallback


static func _apply_recursive(node: Node, strength: float, speed: float, phase: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var surf_count := mi.mesh.get_surface_count()
			for s_idx in range(surf_count):
				var smat := convert_material(mi.get_active_material(s_idx), strength, speed, phase)
				mi.set_surface_override_material(s_idx, smat)

	for child in node.get_children():
		_apply_recursive(child, strength, speed, phase)
