extends Node3D
class_name AssetPackLoader

## High-performance Recursive Asset Loader & Architectural Replacer for Al-Azhari:
## 1. Replaces old procedural buildings cleanly when user-exported `.glb` buildings
##    (`mosque`, `apartment`, `compound`/`house`/`jalous`, `dukkan`/`shop`, `rakouba`, `tea_stall`)
##    exist under `res://assets/models/`, attaching trimesh collisions ONLY to main building meshes.
## 2. Batches repeated foliage/rocks into `MultiMeshInstance3D` nodes with fixed alpha-scissor (0.30)
##    + wind sway (`FoliageWind`), trunk `CylinderShape3D` colliders, and distance culling.
## 3. Places furniture, tools, and shop props using `SmartWorldOrganizer` (>= 3.5m doorway clearance).
## 4. Spawns 12 animated scurrying `MouseAI` rodents with zero heavy colliders.

const MOUSE_NPC_SCENE: PackedScene = preload("res://scenes/mouse_npc.tscn")

const WORLD_AMBIANCE_EXISTING_PROPS: Array[String] = [
	"props/fish.glb",
	"props/barrel/barrel.gltf",
	"props/bench/bench.gltf",
	"props/bucket/bucket.gltf",
	"props/cart/coffeecart_01.gltf",
	"props/crate/crate.gltf",
	"props/lantern/lantern.gltf",
	"props/plant/plant.gltf",
	"props/pot/pot.gltf",
	"props/stool/stool.gltf",
	"props/table/table.gltf",
	"props/tire/tire.gltf",
]

var loaded_models: Array[Dictionary] = []
var replaced_building_count: int = 0
var wind_foliage_count: int = 0
var rock_count: int = 0
var furniture_count: int = 0
var tool_count: int = 0
var mouse_count: int = 0
var multimesh_batch_count: int = 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 474099
	if OS.has_feature("web"):
		call_deferred("_load_web_progressive")
		return
	var discovered := _scan_models_recursive("res://assets/models")
	var by_role: Dictionary = {
		"foliage_tree": [],
		"foliage_shrub": [],
		"rock": [],
		"bed": [],
		"sofa": [],
		"armchair": [],
		"chair": [],
		"table": [],
		"shelf": [],
		"tool": [],
		"building": [],
		"vehicle": [],
		"prop": [],
	}

	for path in discovered:
		var role := _classify_model(path)
		if role == "ignore" or role == "rodent" or role == "building" or role == "vehicle":
			# Single-image SAM 3D building/vehicle blobs are skipped so crisp enterable .tscn buildings & vehicles stay intact
			continue
		if by_role.has(role):
			by_role[role].append(path)

	_place_foliage(by_role["foliage_tree"], by_role["foliage_shrub"])
	_place_sudanese_avenue_trees()
	_place_rocks(by_role["rock"])
	_place_furniture(by_role)
	_place_tools(by_role["tool"])
	_place_misc_props(by_role["prop"])
	_spawn_mice()


func _load_web_progressive() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var discovered := _scan_models_recursive("res://assets/models")
	var by_role: Dictionary = {
		"foliage_tree": [],
		"foliage_shrub": [],
		"rock": [],
		"bed": [],
		"sofa": [],
		"armchair": [],
		"chair": [],
		"table": [],
		"shelf": [],
		"tool": [],
		"building": [],
		"vehicle": [],
		"prop": [],
	}
	for path in discovered:
		var role := _classify_model(path)
		if role == "ignore" or role == "rodent" or role == "building" or role == "vehicle":
			continue
		if by_role.has(role):
			by_role[role].append(path)

	_place_foliage(by_role["foliage_tree"], by_role["foliage_shrub"])
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_place_sudanese_avenue_trees()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_place_rocks(by_role["rock"])
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_place_furniture(by_role)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_place_misc_props(by_role["prop"])
	get_tree().call_group("network_hud", "_apply_safari_web_graphics_profile")


func _scan_models_recursive(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var entries := ResourceLoader.list_directory(dir_path)
	entries.sort()
	for entry in entries:
		if entry.begins_with("."):
			continue
		var full := "%s/%s" % [dir_path, entry]
		if entry.ends_with("/"):
			var sub := full.trim_suffix("/")
			if sub.ends_with("/characters") or sub.ends_with("/textures"):
				continue
			out.append_array(_scan_models_recursive(sub))
		else:
			var low := entry.to_lower()
			if low.ends_with(".glb") or low.ends_with(".gltf") or low.ends_with(".fbx"):
				var rel := full.replace("res://assets/models/", "").to_lower()
				if rel in WORLD_AMBIANCE_EXISTING_PROPS:
					continue
				out.append(full)
	return out


func _classify_model(res_path: String) -> String:
	var low := res_path.to_lower()
	if "/characters/" in low:
		return "ignore"
	if "mouse" in low or "rat" in low or "rodent" in low:
		return "rodent"
	if "tree" in low or "palm" in low or "acacia" in low or "neem" in low or "quiver" in low:
		return "foliage_tree"
	if "bush" in low or "shrub" in low or "plant" in low or "foliage" in low:
		return "foliage_shrub"
	if "rock" in low or "stone" in low or "boulder" in low or "pebble" in low:
		return "rock"
	if "bed" in low or "mattress" in low:
		return "bed"
	if "sofa" in low or "couch" in low:
		return "sofa"
	if "armchair" in low:
		return "armchair"
	if "chair" in low or "stool" in low or "bench" in low:
		return "chair"
	if "table" in low or "desk" in low or "console" in low or "nightstand" in low:
		return "table"
	if "shelf" in low or "bookshelf" in low or "cabinet" in low or "wardrobe" in low or "commode" in low:
		return "shelf"
	if "tool" in low or "hammer" in low or "wrench" in low or "bolt" in low or "drill" in low or "vice" in low:
		return "tool"
	if "/buildings/" in low or "compound" in low or "house" in low or "jalous" in low or "apartment" in low or "mosque" in low or "masjid" in low or "dukkan" in low or "shop" in low or "rakouba" in low or "tea_stall" in low:
		return "building"
	if "/vehicles/" in low or "amjad" in low or "boks" in low or "karo" in low or "raksha" in low:
		return "vehicle"
	return "prop"


func _building_target_height(path: String) -> float:
	var low := path.to_lower()
	if "mosque" in low or "masjid" in low:
		return 14.2
	if "apartment" in low:
		return 11.2
	if "compound" in low or "house" in low or "jalous" in low:
		return 4.1
	if "dukkan" in low or "shop" in low:
		return 3.9
	if "rakouba" in low or "tea_stall" in low or "stall" in low:
		return 2.6
	return 4.0


func _replace_procedural_buildings(buildings: Array) -> void:
	if buildings.is_empty():
		return
	var proc_root := get_node_or_null("../Neighborhood/Buildings")
	var slot_map: Array[Dictionary] = [
		{"keys": ["masjid", "mosque"], "node": "MosqueAzhari", "pos": Vector3(-28.0, 0.0, -28.0), "yaw": 0.0},
		{"keys": ["apartment"], "node": "ApartmentWest", "pos": Vector3(-20.0, 0.0, 24.0), "yaw": PI * 0.5},
		{"keys": ["apartment"], "node": "ApartmentEast", "pos": Vector3(20.0, 0.0, 42.0), "yaw": -PI * 0.5},
		{"keys": ["compound", "house", "jalous"], "node": "HouseSW", "pos": Vector3(-44.0, 0.0, 26.0), "yaw": 0.0},
		{"keys": ["compound", "house", "jalous"], "node": "HouseSE", "pos": Vector3(38.0, 0.0, 26.0), "yaw": 0.0},
		{"keys": ["jalous", "compound", "house"], "node": "HouseNorth", "pos": Vector3(36.0, 0.0, -40.0), "yaw": PI},
		{"keys": ["dukkan", "shop"], "node": "CommercialStrip", "pos": Vector3(36.0, 0.0, -16.5), "yaw": 0.0},
	]

	var used_paths: Dictionary = {}
	for slot in slot_map:
		var match_path := ""
		var keys: Array = slot["keys"]
		for k in keys:
			for bp in buildings:
				if String(k) in String(bp).to_lower():
					match_path = String(bp)
					break
			if not match_path.is_empty():
				break
		if match_path.is_empty():
			continue

		var h := _building_target_height(match_path)
		var holder := _instantiate_grounded(match_path, h, slot["pos"], float(slot["yaw"]), 180.0, true, false, true)
		if holder == null:
			continue
		holder.name = "Replaced_%s" % String(slot["node"])

		if proc_root != null:
			var old_b := proc_root.get_node_or_null(String(slot["node"]))
			if old_b != null:
				# Preserve AdhanPlayer (360m / 15s / 1200s) when replacing MosqueAzhari
				var adhan := old_b.get_node_or_null("AdhanPlayer")
				if adhan != null:
					adhan.reparent(holder)
				old_b.queue_free()

		used_paths[match_path] = true
		replaced_building_count += 1

	# Place any remaining standalone shelters/rakouba/tea_stall buildings cleanly
	var extra_lots: Array[Vector3] = [
		Vector3(58.0, 0.0, 32.0),
		Vector3(17.9, 0.0, 17.8),
		Vector3(-56.0, 0.0, -34.0),
		Vector3(-66.0, 0.0, 42.0),
	]
	var extra_idx := 0
	for bp in buildings:
		if used_paths.has(bp):
			continue
		var p_vec := Vector3(17.9, 0.0, 17.8) if "tea" in String(bp).to_lower() else extra_lots[extra_idx % extra_lots.size()]
		extra_idx += 1
		if SmartWorldOrganizer.is_spot_valid(p_vec, 1.0, false):
			var h := _building_target_height(String(bp))
			_instantiate_grounded(String(bp), h, p_vec, 0.0, 150.0, true, false, true)


func _extract_mesh_entries(node: Node, accum_xform: Transform3D, out_entries: Array[Dictionary]) -> void:
	var cur_xform := accum_xform
	if node is Node3D:
		cur_xform = accum_xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out_entries.append({"mesh": mi.mesh, "xform": cur_xform, "mi": mi})
	for child in node.get_children():
		_extract_mesh_entries(child, cur_xform, out_entries)


func _spawn_multimesh_batch(
	res_path: String,
	transforms: Array[Transform3D],
	vis_dist: float,
	cast_shadows: bool,
	wind_strength: float,
	wind_speed: float
) -> bool:
	if transforms.is_empty() or not ResourceLoader.exists(res_path):
		return false
	var packed := ResourceLoader.load(res_path) as PackedScene
	if packed == null:
		return false
	var template := packed.instantiate() as Node3D
	if template == null:
		return false

	var aabb := CharacterModelLoader._compute_mesh_aabb(template)
	var base_norm := Transform3D.IDENTITY
	if aabb.size.y > 0.001:
		var s := 1.0 / aabb.size.y
		var cx := (aabb.position.x + aabb.size.x * 0.5) * s
		var cz := (aabb.position.z + aabb.size.z * 0.5) * s
		var by := aabb.position.y * s
		base_norm = Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(-cx, -by, -cz))

	var entries: Array[Dictionary] = []
	for child in template.get_children():
		_extract_mesh_entries(child, Transform3D.IDENTITY, entries)
	if entries.is_empty() and template is MeshInstance3D:
		entries.append({"mesh": (template as MeshInstance3D).mesh, "xform": Transform3D.IDENTITY, "mi": template})

	var batch_root := Node3D.new()
	batch_root.name = "MM_%s" % res_path.get_file().get_basename()
	add_child(batch_root)

	for e_idx in range(entries.size()):
		var entry: Dictionary = entries[e_idx]
		var orig_mesh: Mesh = entry["mesh"]
		var mi: MeshInstance3D = entry["mi"]
		var sub_xform: Transform3D = base_norm * (entry["xform"] as Transform3D)

		var render_mesh := orig_mesh
		if wind_strength > 0.0:
			var dup := orig_mesh.duplicate() as Mesh
			for s_idx in range(dup.get_surface_count()):
				var smat := FoliageWind.convert_material(mi.get_active_material(s_idx), wind_strength, wind_speed, float(e_idx) * 0.5)
				dup.surface_set_material(s_idx, smat)
			render_mesh = dup

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = render_mesh
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i] * sub_xform)

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Sub_%d" % e_idx
		mmi.multimesh = mm
		mmi.visibility_range_end = vis_dist
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch_root.add_child(mmi)

	template.queue_free()
	multimesh_batch_count += 1
	return true


func _add_trunk_collider(pos: Vector3, height: float) -> void:
	var sb := StaticBody3D.new()
	sb.name = "TrunkCollider"
	sb.position = pos
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.28
	cyl.height = minf(2.4, height * 0.50)
	cs.shape = cyl
	cs.position = Vector3(0.0, cyl.height * 0.5, 0.0)
	sb.add_child(cs)
	add_child(sb)


func _instantiate_grounded(
	res_path: String,
	target_height: float,
	pos: Vector3,
	yaw: float,
	vis_dist: float,
	cast_shadows: bool,
	box_collider: bool,
	building_trimesh: bool = false
) -> Node3D:
	if not ResourceLoader.exists(res_path):
		return null
	var packed := ResourceLoader.load(res_path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null

	var holder := Node3D.new()
	holder.name = "Pack_%s_%d" % [res_path.get_file().get_basename(), loaded_models.size()]
	holder.add_child(inst)

	var aabb := CharacterModelLoader._compute_mesh_aabb(inst)
	var scaled_size := Vector3.ONE * target_height
	if aabb.size.y > 0.001:
		var s := target_height / aabb.size.y
		inst.scale = Vector3.ONE * s
		var cx := (aabb.position.x + aabb.size.x * 0.5) * s
		var cz := (aabb.position.z + aabb.size.z * 0.5) * s
		var bottom_y := aabb.position.y * s
		inst.position = Vector3(-cx, -bottom_y, -cz)
		scaled_size = aabb.size * s

	_apply_culling_flags(inst, vis_dist, cast_shadows)

	if building_trimesh:
		_attach_building_trimesh_only(inst)
	elif box_collider:
		var sb := StaticBody3D.new()
		sb.name = "BoxCollider"
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(maxf(0.3, scaled_size.x * 0.92), maxf(0.3, scaled_size.y * 0.95), maxf(0.3, scaled_size.z * 0.92))
		cs.shape = bs
		cs.position = Vector3(0.0, bs.size.y * 0.5, 0.0)
		sb.add_child(cs)
		holder.add_child(sb)

	holder.position = pos
	holder.rotation.y = yaw
	add_child(holder)

	loaded_models.append({"path": res_path, "node": holder})
	return holder


func _attach_building_trimesh_only(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			mi.create_trimesh_collision()
	for child in node.get_children():
		_attach_building_trimesh_only(child)


func _apply_culling_flags(node: Node, vis_dist: float, cast_shadows: bool) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.visibility_range_end = vis_dist
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_culling_flags(child, vis_dist, cast_shadows)


func _place_foliage(trees: Array, shrubs: Array) -> void:
	var tree_spots := SmartWorldOrganizer.get_tree_spots()
	# Add curated main-avenue, plaza & park spots for the repaired 4K realistic trees (all clearance-checked)
	var extra_4k_candidates: Array[Vector3] = [
		Vector3(-22.0, 0.0, -13.5),
		Vector3(-34.0, 0.0, -13.5),
		Vector3(14.5, 0.0, 11.8),
		Vector3(-14.5, 0.0, 18.5),
		Vector3(24.0, 0.0, 12.2),
		Vector3(46.0, 0.0, 12.2),
		Vector3(-48.0, 0.0, -13.5),
		Vector3(-56.0, 0.0, 13.5),
		Vector3(76.0, 0.0, -12.5),
		Vector3(88.0, 0.0, 18.5),
		Vector3(16.0, 0.0, -34.0),
		Vector3(-16.0, 0.0, -48.0),
		Vector3(-14.0, 0.0, 48.0),
		Vector3(14.0, 0.0, -56.0),
		Vector3(78.0, 0.0, 38.0),
		Vector3(-56.0, 0.0, -42.0),
	]
	for cand in SmartWorldOrganizer.filter_valid_spots(extra_4k_candidates, 0.85):
		var too_close := false
		for ex in tree_spots:
			if ex.distance_to(cand) < 4.5:
				too_close = true
				break
		if not too_close:
			tree_spots.append(cand)

	if not trees.is_empty():
		var primary_4k: String = ""
		for tp in trees:
			if "island_tree_02" in String(tp).to_lower():
				primary_4k = String(tp)
				break
		var by_model: Dictionary = {}
		for i in range(tree_spots.size()):
			# Favor repaired 4K island_tree_02 along main avenues & plazas (~75%) mixed with quiver_tree_01 (~25%)
			var res_path: String = primary_4k if (not primary_4k.is_empty() and (i % 4 != 3)) else String(trees[i % trees.size()])
			var scale_mul := _rng.randf_range(0.88, 1.24)
			var h := (4.6 if "quiver" in res_path.to_lower() else 5.5) * scale_mul
			var yaw := _rng.randf_range(0.0, TAU)
			# Sink trunk root -0.14m below terrain so base sits naturally in soil with zero gap/pedestal
			var grounded_pos := tree_spots[i] + Vector3(0.0, -0.14, 0.0)
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * h), grounded_pos)
			if not by_model.has(res_path):
				by_model[res_path] = []
			(by_model[res_path] as Array).append(xf)
			_add_trunk_collider(tree_spots[i], h)
			wind_foliage_count += 1

		for res_path in by_model.keys():
			var xfs: Array[Transform3D] = []
			for x in by_model[res_path]:
				xfs.append(x)
			_spawn_multimesh_batch(res_path, xfs, 140.0, true, 0.11, 1.45)

	var shrub_spots := SmartWorldOrganizer.get_shrub_spots()
	if not shrubs.is_empty():
		var by_shrub: Dictionary = {}
		for i in range(shrub_spots.size()):
			var res_path: String = shrubs[i % shrubs.size()]
			var h := 1.15 * _rng.randf_range(0.85, 1.25)
			var yaw := _rng.randf_range(0.0, TAU)
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * h), shrub_spots[i])
			if not by_shrub.has(res_path):
				by_shrub[res_path] = []
			(by_shrub[res_path] as Array).append(xf)
			wind_foliage_count += 1

		for res_path in by_shrub.keys():
			var xfs: Array[Transform3D] = []
			for x in by_shrub[res_path]:
				xfs.append(x)
			_spawn_multimesh_batch(res_path, xfs, 55.0, false, 0.09, 1.65)


func _place_sudanese_avenue_trees() -> void:
	# Scatter organic multi-part Neem, Acacia/Sunut & Date Palms across Khartoum avenues, plazas & parks
	# using lightweight MultiMeshInstance3D batches + lower-trunk-only CylinderShape3D colliders.
	var neem_spots_raw: Array[Vector3] = [
		Vector3(-26.0, 0.0, 12.2), Vector3(-42.0, 0.0, 12.2), Vector3(-54.0, 0.0, 12.2),
		Vector3(32.0, 0.0, 12.2),  Vector3(54.0, 0.0, 12.2),  Vector3(70.0, 0.0, 12.2),
		Vector3(-12.2, 0.0, -28.0), Vector3(-12.2, 0.0, -44.0), Vector3(-12.2, 0.0, 38.0),
		Vector3(12.2, 0.0, -28.0),  Vector3(12.2, 0.0, -44.0),  Vector3(12.2, 0.0, 56.0),
		Vector3(96.0, 0.0, -14.0),  Vector3(114.0, 0.0, -14.0), Vector3(114.0, 0.0, 14.0),
		Vector3(132.0, 0.0, 14.0),  Vector3(132.0, 0.0, -14.0), Vector3(165.0, 0.0, 14.0),
		Vector3(165.0, 0.0, -14.0), Vector3(195.0, 0.0, 14.0),  Vector3(195.0, 0.0, -14.0),
		Vector3(245.0, 0.0, 14.0),  Vector3(245.0, 0.0, -14.0), Vector3(280.0, 0.0, 14.0),
		Vector3(280.0, 0.0, -14.0), Vector3(14.0, 0.0, 95.0),   Vector3(-14.0, 0.0, 95.0),
		Vector3(14.0, 0.0, 145.0),  Vector3(-14.0, 0.0, 145.0), Vector3(14.0, 0.0, -95.0),
		Vector3(-14.0, 0.0, -95.0), Vector3(14.0, 0.0, -155.0), Vector3(-14.0, 0.0, -155.0),
	]
	var acacia_spots_raw: Array[Vector3] = [
		Vector3(-82.0, 0.0, -16.0), Vector3(-98.0, 0.0, -16.0), Vector3(-114.0, 0.0, -16.0),
		Vector3(-82.0, 0.0, 16.0),  Vector3(-98.0, 0.0, 16.0),  Vector3(-114.0, 0.0, 16.0),
		Vector3(-270.0, 0.0, -16.0), Vector3(-310.0, 0.0, -16.0), Vector3(-350.0, 0.0, -16.0),
		Vector3(-270.0, 0.0, 16.0),  Vector3(-310.0, 0.0, 16.0),  Vector3(-350.0, 0.0, 16.0),
		Vector3(82.0, 0.0, 48.0),   Vector3(104.0, 0.0, 48.0),  Vector3(-68.0, 0.0, 48.0),
	]
	var palm_spots_raw: Array[Vector3] = [
		Vector3(-124.0, 0.0, -35.0), Vector3(-124.0, 0.0, -68.0), Vector3(-124.0, 0.0, 35.0),
		Vector3(-124.0, 0.0, 68.0),  Vector3(-124.0, 0.0, 110.0), Vector3(-124.0, 0.0, -110.0),
		Vector3(-258.0, 0.0, -45.0), Vector3(-258.0, 0.0, 45.0),  Vector3(-258.0, 0.0, -120.0),
		Vector3(-258.0, 0.0, 120.0), Vector3(14.0, 0.0, 210.0),   Vector3(-14.0, 0.0, 210.0),
		Vector3(14.0, 0.0, -210.0),  Vector3(-14.0, 0.0, -210.0),
	]

	_spawn_sudanese_species_multimesh(SudaneseTreeBuilder.TreeSpecies.NEEM, SmartWorldOrganizer.filter_valid_spots(neem_spots_raw, 0.8), 0.92, 1.18, 150.0)
	_spawn_sudanese_species_multimesh(SudaneseTreeBuilder.TreeSpecies.ACACIA, SmartWorldOrganizer.filter_valid_spots(acacia_spots_raw, 0.8), 0.90, 1.18, 150.0)
	_spawn_sudanese_species_multimesh(SudaneseTreeBuilder.TreeSpecies.DATE_PALM, SmartWorldOrganizer.filter_valid_spots(palm_spots_raw, 0.8), 0.94, 1.20, 150.0)


func _spawn_sudanese_species_multimesh(
	sp: SudaneseTreeBuilder.TreeSpecies,
	spots: Array[Vector3],
	min_s: float,
	max_s: float,
	vis_dist: float
) -> void:
	if spots.is_empty():
		return
	var pair := SudaneseTreeBuilder.get_species_meshes(sp, 0)
	var trunk_mesh: ArrayMesh = pair["trunk"]
	var canopy_mesh: ArrayMesh = pair["canopy"]
	var canopy_inner: ArrayMesh = pair.get("canopy_inner") as ArrayMesh

	var mm_trunk := MultiMesh.new()
	mm_trunk.transform_format = MultiMesh.TRANSFORM_3D
	mm_trunk.mesh = trunk_mesh
	mm_trunk.instance_count = spots.size()

	var mm_canopy := MultiMesh.new()
	mm_canopy.transform_format = MultiMesh.TRANSFORM_3D
	mm_canopy.mesh = canopy_mesh
	mm_canopy.instance_count = spots.size()

	var mm_inner: MultiMesh = null
	if canopy_inner != null and canopy_inner.get_surface_count() > 0:
		mm_inner = MultiMesh.new()
		mm_inner.transform_format = MultiMesh.TRANSFORM_3D
		mm_inner.mesh = canopy_inner
		mm_inner.instance_count = spots.size()

	for i in range(spots.size()):
		var sc := _rng.randf_range(min_s, max_s)
		var yaw := _rng.randf_range(0.0, TAU)
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), spots[i])
		mm_trunk.set_instance_transform(i, xf)
		mm_canopy.set_instance_transform(i, xf)
		if mm_inner != null:
			mm_inner.set_instance_transform(i, xf)
		_add_trunk_collider(spots[i], 4.8 * sc)
		wind_foliage_count += 1

	var root := Node3D.new()
	root.name = "MM_Sudanese_%d" % int(sp)
	add_child(root)

	var mmi_t := MultiMeshInstance3D.new()
	mmi_t.name = "Trunks"
	mmi_t.multimesh = mm_trunk
	mmi_t.material_override = SudaneseTreeBuilder.get_bark_material(sp)
	mmi_t.visibility_range_end = vis_dist
	mmi_t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mmi_t)

	var mmi_c := MultiMeshInstance3D.new()
	mmi_c.name = "Canopies"
	mmi_c.multimesh = mm_canopy
	mmi_c.material_override = SudaneseTreeBuilder.get_canopy_material(sp)
	mmi_c.visibility_range_end = vis_dist
	mmi_c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mmi_c)

	if mm_inner != null:
		var mmi_in := MultiMeshInstance3D.new()
		mmi_in.name = "CanopiesInner"
		mmi_in.multimesh = mm_inner
		mmi_in.material_override = SudaneseTreeBuilder.get_canopy_material(sp)
		mmi_in.visibility_range_end = minf(vis_dist, 115.0)
		mmi_in.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi_in)

	multimesh_batch_count += 1


func _place_rocks(rocks: Array) -> void:
	if rocks.is_empty():
		return
	var rock_spots := SmartWorldOrganizer.get_rock_spots()
	var by_rock: Dictionary = {}
	for i in range(rock_spots.size()):
		var res_path: String = rocks[i % rocks.size()]
		var low := res_path.to_lower()
		var base_h := 1.05 if "boulder" in low else (0.52 if "rocks" in low else 0.34)
		var h := base_h * _rng.randf_range(0.75, 1.35)
		var yaw := _rng.randf_range(0.0, TAU)
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * h), rock_spots[i])
		if not by_rock.has(res_path):
			by_rock[res_path] = []
		(by_rock[res_path] as Array).append(xf)
		rock_count += 1

	for res_path in by_rock.keys():
		var xfs: Array[Transform3D] = []
		for x in by_rock[res_path]:
			xfs.append(x)
		var vis := 110.0 if "boulder" in res_path.to_lower() else 85.0
		_spawn_multimesh_batch(res_path, xfs, vis, false, 0.0, 0.0)


func _place_furniture(by_role: Dictionary) -> void:
	var house_origins: Array[Dictionary] = [
		{"pos": Vector3(-44.0, 0.10, 26.0), "yaw": 0.0},
		{"pos": Vector3(38.0, 0.10, 26.0), "yaw": 0.0},
		{"pos": Vector3(36.0, 0.10, -40.0), "yaw": PI},
	]

	var beds: Array = by_role["bed"]
	var sofas: Array = by_role["sofa"]
	var armchairs: Array = by_role["armchair"]
	var chairs: Array = by_role["chair"]
	var tables: Array = by_role["table"]
	var shelves: Array = by_role["shelf"]

	for idx in range(house_origins.size()):
		var ho := house_origins[idx]
		var origin: Vector3 = ho["pos"]
		var hyaw: float = ho["yaw"]
		var rot := Basis(Vector3.UP, hyaw)

		# Neatly aligned along walls inside open rooms/courtyards (>= 3.5m clear of doorways)
		if not beds.is_empty():
			var bed_p := origin + rot * Vector3(-2.6, 0.0, -5.8)
			if _instantiate_grounded(beds[idx % beds.size()], 0.78, bed_p, hyaw, 28.0, false, true):
				furniture_count += 1
		if not sofas.is_empty():
			var sofa_p := origin + rot * Vector3(2.4, 0.0, -5.8)
			if _instantiate_grounded(sofas[idx % sofas.size()], 0.85, sofa_p, hyaw + PI, 28.0, false, true):
				furniture_count += 1
		if not armchairs.is_empty():
			var ac_p := origin + rot * Vector3(3.2, 0.0, -3.5)
			if _instantiate_grounded(armchairs[idx % armchairs.size()], 0.88, ac_p, hyaw - PI * 0.5, 28.0, false, false):
				furniture_count += 1
		if not shelves.is_empty():
			var sh_p := origin + rot * Vector3(-3.8, 0.0, -2.5)
			if _instantiate_grounded(shelves[idx % shelves.size()], 1.75, sh_p, hyaw + PI * 0.5, 28.0, false, true):
				furniture_count += 1
		if not tables.is_empty():
			var tbl_p := origin + rot * Vector3(2.6, 0.0, 5.2)  # Courtyard shade table away from gate
			if _instantiate_grounded(tables[idx % tables.size()], 0.74, tbl_p, hyaw, 28.0, false, true):
				furniture_count += 1
		if not chairs.is_empty():
			var c_l := origin + rot * Vector3(1.6, 0.0, 5.2)
			var c_r := origin + rot * Vector3(3.6, 0.0, 5.2)
			if _instantiate_grounded(chairs[0], 0.85, c_l, hyaw + PI * 0.5, 28.0, false, false):
				furniture_count += 1
			if _instantiate_grounded(chairs[1 % chairs.size()], 0.85, c_r, hyaw - PI * 0.5, 28.0, false, false):
				furniture_count += 1

	# Organized conversational grouping around ست الشاي tea stall
	var tea_group := SmartWorldOrganizer.get_tea_stall_group_spots()
	if not tables.is_empty():
		for tp in tea_group["tables"]:
			if SmartWorldOrganizer.is_spot_valid(tp, 0.6, false):
				_instantiate_grounded(tables[0], 0.74, tp, 0.0, 55.0, false, true)
				furniture_count += 1
	if not chairs.is_empty():
		for i in range(tea_group["chairs"].size()):
			var cs: Dictionary = tea_group["chairs"][i]
			if SmartWorldOrganizer.is_spot_valid(cs["pos"], 0.4, false):
				if _instantiate_grounded(chairs[i % chairs.size()], 0.84, cs["pos"], float(cs["yaw"]), 35.0, false, false):
					furniture_count += 1


func _place_tools(tools: Array) -> void:
	if tools.is_empty():
		return
	var tool_spots := SmartWorldOrganizer.get_banshar_tool_spots()
	for i in range(tool_spots.size()):
		var spec := tool_spots[i]
		if SmartWorldOrganizer.is_spot_valid(spec["pos"], 0.3, false):
			var res_path: String = tools[i % tools.size()]
			if _instantiate_grounded(res_path, float(spec["h"]), spec["pos"], float(spec["yaw"]), 28.0, false, false):
				tool_count += 1


func _place_misc_props(props: Array) -> void:
	if props.is_empty():
		return
	var side_spots := SmartWorldOrganizer.get_dukkan_side_prop_spots()
	for i in range(props.size()):
		var sp := side_spots[i % side_spots.size()] if not side_spots.is_empty() else Vector3(14.5 + float(i) * 1.2, 0.0, -11.4)
		_instantiate_grounded(props[i], 1.1, sp, 0.0, 28.0, false, false)


func _spawn_mice() -> void:
	var mouse_spots: Array[Dictionary] = [
		{"pos": Vector3(-11.8, 0.0, -11.8), "a": Vector3(-13.8, 0.0, -12.0), "b": Vector3(-10.2, 0.0, -11.0), "cover": Vector3(-14.5, 0.0, -12.8)},
		{"pos": Vector3(11.8, 0.0, 11.8), "a": Vector3(10.5, 0.0, 11.4), "b": Vector3(13.8, 0.0, 12.6), "cover": Vector3(14.6, 0.0, 13.8)},
		{"pos": Vector3(33.8, 0.0, -10.8), "a": Vector3(31.2, 0.0, -10.9), "b": Vector3(35.8, 0.0, -10.6), "cover": Vector3(34.5, 0.0, -12.4)},
		{"pos": Vector3(-36.2, 0.0, 12.2), "a": Vector3(-39.0, 0.0, 12.5), "b": Vector3(-34.2, 0.0, 12.2), "cover": Vector3(-38.0, 0.0, 14.8)},
		{"pos": Vector3(58.2, 0.0, -10.8), "a": Vector3(56.0, 0.0, -11.0), "b": Vector3(59.8, 0.0, -10.5), "cover": Vector3(57.2, 0.0, -13.5)},
		{"pos": Vector3(18.5, 0.0, -24.5), "a": Vector3(15.5, 0.0, -24.6), "b": Vector3(22.0, 0.0, -24.5), "cover": Vector3(16.0, 0.0, -23.0)},
		{"pos": Vector3(31.0, 0.0, -24.5), "a": Vector3(28.0, 0.0, -24.6), "b": Vector3(34.5, 0.0, -24.5), "cover": Vector3(31.5, 0.0, -23.0)},
		{"pos": Vector3(82.5, 0.0, -29.0), "a": Vector3(80.5, 0.0, -29.8), "b": Vector3(85.2, 0.0, -28.0), "cover": Vector3(80.0, 0.0, -31.5)},
		{"pos": Vector3(92.0, 0.0, -25.5), "a": Vector3(90.0, 0.0, -26.5), "b": Vector3(94.2, 0.0, -24.2), "cover": Vector3(93.8, 0.0, -28.0)},
		{"pos": Vector3(-28.0, 0.0, 26.0), "a": Vector3(-30.5, 0.0, 23.0), "b": Vector3(-27.0, 0.0, 29.5), "cover": Vector3(-31.8, 0.0, 26.0)},
		{"pos": Vector3(28.0, 0.0, -34.0), "a": Vector3(24.5, 0.0, -34.2), "b": Vector3(31.0, 0.0, -33.5), "cover": Vector3(26.5, 0.0, -36.5)},
		{"pos": Vector3(49.0, 0.0, -24.5), "a": Vector3(45.5, 0.0, -24.5), "b": Vector3(52.5, 0.0, -24.4), "cover": Vector3(50.5, 0.0, -22.5)},
	]

	for i in range(mouse_spots.size()):
		var spec := mouse_spots[i]
		var m := MOUSE_NPC_SCENE.instantiate() as MouseAI
		m.name = "StreetMouse_%d" % i
		m.position = spec["pos"]
		m.wall_edge_a = spec["a"]
		m.wall_edge_b = spec["b"]
		m.cover_pos = spec["cover"]
		add_child(m)
		mouse_count += 1
