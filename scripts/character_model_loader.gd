extends RefCounted
class_name CharacterModelLoader

## Scans res://assets/models/characters/ recursively per folder.
## Selects the clean photo-textured `.glb` character model in each folder,
## binds its folder texture (`*_0.png` / `.jpg`), and enforces on every surface:
## - `vertex_color_use_as_albedo = false` (prevents pitch-black vertex colors)
## - `albedo_color = Color(1.0, 1.0, 1.0, 1.0)`
## - `metallic = 0.0`, `roughness = 0.85`
## - `shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL`
## - `cull_mode = BaseMaterial3D.CULL_DISABLED`

const CHARACTERS_ROOT: String = "res://assets/models/characters"
const MODEL_EXTENSIONS: Array[String] = ["fbx", "glb", "gltf"]
const REJECT_NAME_TOKENS: Array[String] = ["person_0", "0person", "person", "split", "part", "body_", "seg"]

# Single lightweight shared Mixamo rig preloaded for Web (keeps Safari RAM < 300 MB);
# PC Host loads all 11 characters lazily on demand via CHARACTER_PATHS.
const DEFAULT_PLAYER_SCENE: PackedScene = preload("res://assets/models/characters/ود الحلة (الشخصية الرئيسية  معتز)/11_MainHero_Mutaz_Man.fbx")
const DEFAULT_PLAYER_TEXTURE: Texture2D = preload("res://assets/models/characters/ود الحلة (الشخصية الرئيسية  معتز)/11_MainHero_Mutaz_Man_0.png")

const CHARACTER_PATHS: Array[String] = [
	"res://assets/models/characters/السواق (سائق ركشة أو أمجاد)/01_Driver_Dreiver.fbx",
	"res://assets/models/characters/الشابة الأنيقة بالتوب العصري (الجميلات)/02_YoungWoman_Mama2.fbx",
	"res://assets/models/characters/الطالبة الجامعية (الطالبات)/03_UniversityStudent_Girl.fbx",
	"res://assets/models/characters/الطفل/04_Child_Kid.fbx",
	"res://assets/models/characters/العم الطيب  العم بشير (بالجلابية والعِمّة والمركوب)/05_Elder_Oldman.fbx",
	"res://assets/models/characters/الغني (تاجر أو شخص ميسور الحال)/06_Merchant_Richman.fbx",
	"res://assets/models/characters/المسكين (شخصية محتاجة أو بسيطة)/07_SimpleMan_Homeless.fbx",
	"res://assets/models/characters/خالتو نفيسة (ست الشاي بالتوب السوداني)/08_TeaLady_Nafisa.fbx",
	"res://assets/models/characters/سيدة الحي بالتوب السوداني (الحريم والنسوان)/09_NeighborhoodLady_Mama.fbx",
	"res://assets/models/characters/طالبة المدرسة بالزي السوداني الموحد/10_SchoolGirl_Student.fbx",
	"res://assets/models/characters/ود الحلة (الشخصية الرئيسية  معتز)/11_MainHero_Mutaz_Man.fbx",
]

const CHARACTER_TEXTURE_PATHS: Array[String] = [
	"res://assets/models/characters/السواق (سائق ركشة أو أمجاد)/01_Driver_Dreiver_0.png",
	"res://assets/models/characters/الشابة الأنيقة بالتوب العصري (الجميلات)/02_YoungWoman_Mama2_0.png",
	"res://assets/models/characters/الطالبة الجامعية (الطالبات)/03_UniversityStudent_Girl_0.png",
	"res://assets/models/characters/الطفل/04_Child_Kid_0.png",
	"res://assets/models/characters/العم الطيب  العم بشير (بالجلابية والعِمّة والمركوب)/05_Elder_Oldman_0.png",
	"res://assets/models/characters/الغني (تاجر أو شخص ميسور الحال)/06_Merchant_Richman_0.png",
	"res://assets/models/characters/المسكين (شخصية محتاجة أو بسيطة)/07_SimpleMan_Homeless_0.png",
	"res://assets/models/characters/خالتو نفيسة (ست الشاي بالتوب السوداني)/08_TeaLady_Nafisa_0.png",
	"res://assets/models/characters/سيدة الحي بالتوب السوداني (الحريم والنسوان)/09_NeighborhoodLady_Mama_0.png",
	"res://assets/models/characters/طالبة المدرسة بالزي السوداني الموحد/10_SchoolGirl_Student_0.png",
	"res://assets/models/characters/ود الحلة (الشخصية الرئيسية  معتز)/11_MainHero_Mutaz_Man_0.png",
]

const CHARACTER_ALIASES: Array[Array] = [
	["01_driver_dreiver", "dreiver"],
	["02_youngwoman_mama2", "mama2object_0", "mama2"],
	["03_universitystudent_girl", "studentgirlobject_0", "studentgirl"],
	["04_child_kid", "kid"],
	["05_elder_oldman", "oldman"],
	["06_merchant_richman", "ritchman"],
	["07_simpleman_homeless", "homeless"],
	["08_tealady_nafisa", "teewoman"],
	["09_neighborhoodlady_mama", "mama"],
	["10_schoolgirl_student", "shoolkidobject_0", "shoolkid", "schoolgirl"],
	["11_mainhero_mutaz_man", "man"],
]


static func get_character_count() -> int:
	return CHARACTER_PATHS.size()


static func get_model_path_by_index(index: int) -> String:
	if CHARACTER_PATHS.is_empty():
		return ""
	var clamped := posmod(index, CHARACTER_PATHS.size())
	return CHARACTER_PATHS[clamped]


static func scan_character_models() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for i in range(CHARACTER_PATHS.size()):
		var p: String = CHARACTER_PATHS[i]
		results.append({
			"index": i,
			"name": p.get_file().get_basename(),
			"folder": p.get_base_dir().get_file(),
			"path": p,
			"texture": CHARACTER_TEXTURE_PATHS[i],
			"aliases": CHARACTER_ALIASES[i],
		})
	return results


static func _scan_recursive(dir_path: String, out: Array[Dictionary]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	var seen: Dictionary = {}
	var candidates: Array[Dictionary] = []
	var folder_tex := _find_folder_texture(dir_path, dir)

	for raw_file in dir.get_files():
		var clean_name := raw_file
		if clean_name.ends_with(".import"):
			clean_name = clean_name.substr(0, clean_name.length() - 7)
		var ext := clean_name.get_extension().to_lower()
		if ext in MODEL_EXTENSIONS and not seen.has(clean_name):
			seen[clean_name] = true
			candidates.append({
				"name": clean_name.get_basename(),
				"folder": dir_path.get_file(),
				"path": "%s/%s" % [dir_path, clean_name],
				"texture": folder_tex,
			})

	if not candidates.is_empty():
		var chosen := _select_clean_textured_in_folder(candidates)
		if not chosen.is_empty():
			var aliases: Array[String] = []
			for c in candidates:
				var clow := String(c["name"]).to_lower()
				var skip_alias := false
				for tok in REJECT_NAME_TOKENS:
					if clow.contains(tok):
						skip_alias = true
						break
				if not skip_alias and not aliases.has(clow):
					aliases.append(clow)
			chosen["aliases"] = aliases
			out.append(chosen)

	for sub_dir in dir.get_directories():
		if not sub_dir.begins_with("."):
			_scan_recursive("%s/%s" % [dir_path, sub_dir], out)


static func _find_folder_texture(dir_path: String, dir: DirAccess, prefer_stem: String = "") -> String:
	var exact_png := ""
	var primary_png := ""
	var any_png := ""
	var fallback_img := ""
	var pref_low := prefer_stem.to_lower()
	for raw_file in dir.get_files():
		var clean_name := raw_file
		if clean_name.ends_with(".import"):
			clean_name = clean_name.substr(0, clean_name.length() - 7)
		var low := clean_name.to_lower()
		var full := "%s/%s" % [dir_path, clean_name]
		if not pref_low.is_empty() and (low == pref_low + "_0.png" or low == pref_low + ".png"):
			exact_png = full
		elif low.ends_with("_0.png"):
			primary_png = full
		elif low.ends_with(".png"):
			any_png = full
		elif low.ends_with(".jpg") or low.ends_with(".jpeg") or low.ends_with(".webp"):
			if fallback_img.is_empty():
				fallback_img = full
	if not exact_png.is_empty():
		return exact_png
	if not primary_png.is_empty():
		return primary_png
	if not any_png.is_empty():
		return any_png
	return fallback_img


static func _select_clean_textured_in_folder(candidates: Array[Dictionary]) -> Dictionary:
	# Strictly select ONE primary character model per folder using deterministic rules:
	# 1. Prefer a clean rigged Mixamo .fbx if added in the folder.
	# 2. Reject partial/corrupted exports (`person_0`, `0person`, `person`, `split`, `part`, `body_`, `seg`)
	#    and inspect GLB JSON headers to ensure `TEXCOORD_0` UVs and `images`/`baseColorTexture` exist.
	var best_entry: Dictionary = {}
	var best_score: float = -9999.0
	for entry in candidates:
		var mpath: String = String(entry["path"])
		var lname: String = String(entry["name"]).to_lower()
		var ext: String = mpath.get_extension().to_lower()
		var score: float = 0.0
		var rejected: bool = false
		for tok in REJECT_NAME_TOKENS:
			if lname.contains(tok):
				rejected = true
				score -= 500.0
				break
		if ext == "fbx" and not rejected:
			score += 1000.0
		elif ext == "glb":
			var info := _inspect_glb_json(mpath)
			if not info.get("valid_json", false):
				rejected = true
				score -= 400.0
			if not info.get("has_uv", false):
				rejected = true
				score -= 300.0
			if not info.get("has_tex", false):
				score -= 50.0
			if info.get("has_uv", false) and info.get("has_tex", false):
				score += 100.0
		if not rejected:
			score += 200.0
		if lname.contains("object_0"):
			score -= 1.0 # Prefer non-suffixed primary base filename when tied
		if score > best_score:
			best_score = score
			best_entry = entry
	return best_entry if not best_entry.is_empty() else candidates[0]


static func _inspect_glb_json(res_path: String) -> Dictionary:
	var result := {"valid_json": false, "has_uv": false, "has_tex": false}
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null or f.get_length() < 20:
		return result
	var magic := f.get_32()
	if magic != 0x46546C67: # "glTF"
		return result
	var _ver := f.get_32()
	var _total_len := f.get_32()
	var jlen := f.get_32()
	var jtype := f.get_32()
	if jtype != 0x4E4F534A or jlen <= 0 or jlen > 2000000:
		return result
	var json_str := f.get_buffer(jlen).get_string_from_utf8()
	var parsed = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		return result
	var gltf := parsed as Dictionary
	result["valid_json"] = true
	var meshes: Array = gltf.get("meshes", [])
	if not meshes.is_empty():
		var prims: Array = meshes[0].get("primitives", [])
		if not prims.is_empty():
			var attrs: Dictionary = prims[0].get("attributes", {})
			result["has_uv"] = attrs.has("TEXCOORD_0")
	var imgs: Array = gltf.get("images", [])
	var mats: Array = gltf.get("materials", [])
	var has_btex := false
	for m in mats:
		if m is Dictionary and m.has("pbrMetallicRoughness"):
			var pbr: Dictionary = m["pbrMetallicRoughness"]
			if pbr.has("baseColorTexture"):
				has_btex = true
				break
	result["has_tex"] = (not imgs.is_empty()) or has_btex
	return result


static func find_model_path(keyword: String) -> String:
	var models := scan_character_models()
	var kw := keyword.to_lower()
	var alias := kw.replace("man", "") if kw == "ritchman" else kw
	for entry in models:
		var nm := String(entry["name"]).to_lower()
		var al: Array = entry.get("aliases", [])
		if nm == kw or al.has(kw) or (alias != kw and al.has(alias)):
			return String(entry["path"])
	for entry in models:
		var nm := String(entry["name"]).to_lower()
		var al: Array = entry.get("aliases", [])
		if nm.begins_with(kw) or (alias != kw and nm.begins_with(alias)):
			return String(entry["path"])
		for a in al:
			var sa := String(a)
			if sa.begins_with(kw) or (alias != kw and sa.begins_with(alias)):
				return String(entry["path"])
	for entry in models:
		var nm := String(entry["name"]).to_lower()
		var fld := String(entry["folder"]).to_lower()
		var al: Array = entry.get("aliases", [])
		if nm.contains(kw) or fld.contains(kw) or (alias != kw and nm.contains(alias)):
			return String(entry["path"])
		for a in al:
			var sa := String(a)
			if sa.contains(kw) or (alias != kw and sa.contains(alias)):
				return String(entry["path"])
	return ""


static func instantiate_normalized(model_path: String, target_height: float = 1.75, face_flip_y: bool = true) -> Node3D:
	var packed: PackedScene = null
	var fallback_tex: Texture2D = null

	if OS.has_feature("web"):
		# Web keeps 1 lightweight shared player rig in RAM so Safari stays under 300 MB
		packed = DEFAULT_PLAYER_SCENE
		fallback_tex = DEFAULT_PLAYER_TEXTURE
	else:
		var manifest_idx := CHARACTER_PATHS.find(model_path)
		if manifest_idx == CHARACTER_PATHS.size() - 1:
			packed = DEFAULT_PLAYER_SCENE
			fallback_tex = DEFAULT_PLAYER_TEXTURE
		elif manifest_idx >= 0:
			if ResourceLoader.exists(model_path):
				packed = ResourceLoader.load(model_path) as PackedScene
			var tpath: String = CHARACTER_TEXTURE_PATHS[manifest_idx]
			if ResourceLoader.exists(tpath):
				fallback_tex = ResourceLoader.load(tpath) as Texture2D
		elif not model_path.is_empty() and ResourceLoader.exists(model_path):
			packed = ResourceLoader.load(model_path) as PackedScene

	if packed == null:
		return null

	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null

	var pivot := Node3D.new()
	pivot.name = "GLBCharacterPivot"
	pivot.add_child(inst)

	if fallback_tex == null and not model_path.is_empty():
		var folder_dir := model_path.get_base_dir()
		var model_stem := model_path.get_file().get_basename()
		var d := DirAccess.open(folder_dir)
		if d != null:
			var tpath := _find_folder_texture(folder_dir, d, model_stem)
			if not tpath.is_empty() and ResourceLoader.exists(tpath):
				fallback_tex = ResourceLoader.load(tpath) as Texture2D

	CharacterAnimator.attach(pivot, inst, fallback_tex)

	var bounds := _compute_mesh_aabb(inst)
	if bounds.size.y > 0.0001:
		var scale_factor := target_height / bounds.size.y
		inst.scale = Vector3.ONE * scale_factor
		var center_x := (bounds.position.x + bounds.size.x * 0.5) * scale_factor
		var center_z := (bounds.position.z + bounds.size.z * 0.5) * scale_factor
		var min_y := bounds.position.y * scale_factor
		if face_flip_y:
			inst.rotation.y = PI
			inst.position = Vector3(center_x, -min_y, center_z)
		else:
			inst.position = Vector3(-center_x, -min_y, -center_z)
	else:
		inst.scale = Vector3.ONE * target_height
		if face_flip_y:
			inst.rotation.y = PI
		inst.position = Vector3(0.0, target_height * 0.5, 0.0)

	return pivot


static func _repair_character_materials_recursive(node: Node, fallback_tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.visibility_range_end = 90.0
		if mi.mesh != null:
			var surf_count := mi.mesh.get_surface_count()
			for s_idx in range(surf_count):
				var orig := mi.get_active_material(s_idx)
				var mat := StandardMaterial3D.new()
				var tex: Texture2D = fallback_tex
				if orig is BaseMaterial3D and (orig as BaseMaterial3D).albedo_texture != null:
					tex = (orig as BaseMaterial3D).albedo_texture
				mat.albedo_texture = tex
				mat.vertex_color_use_as_albedo = false
				mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
				mat.metallic = 0.0
				mat.roughness = 0.85
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mat.backlight_enabled = true
				mat.backlight = Color(0.35, 0.33, 0.30, 1.0)
				mi.set_surface_override_material(s_idx, mat)

	for ch in node.get_children():
		_repair_character_materials_recursive(ch, fallback_tex)


static func _compute_mesh_aabb(node: Node) -> AABB:
	var has_bounds := false
	var combined := AABB()
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if not mi.visible or mi.is_queued_for_deletion():
				continue
			var aabb := mi.get_aabb()
			var transformed := mi.transform * aabb
			if not has_bounds:
				combined = transformed
				has_bounds = true
			else:
				combined = combined.merge(transformed)
		var sub := _compute_mesh_aabb(child)
		if sub.size != Vector3.ZERO:
			if child is Node3D:
				sub = (child as Node3D).transform * sub
			if not has_bounds:
				combined = sub
				has_bounds = true
			else:
				combined = combined.merge(sub)
	return combined if has_bounds else AABB()
