extends Node3D
class_name RoleNPCSpawner

## Places stationary, role-dressed Mixamo `.fbx` NPCs across every district work station:
## Doctors & Pharmacists, Civil/Site Engineers, Shopkeepers/Vendors, Automated Bakery Bakers,
## Police Officers & Firefighters, Barbers, and Boat Dock Masters.
## Uses existing `res://scenes/npc.tscn` + `MixamoAnimationController` (`Idle` / `Talk`, zero A-Pose).

const NPC_SCENE: PackedScene = preload("res://scenes/npc.tscn")
const VIS_NPC: float = 280.0

var _role_npcs: Array[Node] = []
var _shared_mats: Dictionary = {}


func _ready() -> void:
	if OS.has_feature("web"):
		# Web keeps 0 ambient role NPCs so only multiplayer players use the shared rig
		return
	add_to_group("role_npc_spawner")
	_init_uniform_materials()
	call_deferred("_spawn_all_role_npcs")


func get_role_npcs() -> Array[Node]:
	return _role_npcs


func _init_uniform_materials() -> void:
	_shared_mats["lab_coat"] = _make_mat(Color(0.98, 0.99, 1.0, 1.0), 0.72)
	_shared_mats["stethoscope"] = _make_mat(Color(0.14, 0.16, 0.20, 1.0), 0.45)
	_shared_mats["badge_med"] = _make_mat(Color(0.88, 0.16, 0.16, 1.0), 0.5)
	_shared_mats["badge_pharm"] = _make_mat(Color(0.16, 0.72, 0.28, 1.0), 0.5)
	_shared_mats["hardhat_yellow"] = _make_mat(Color(0.98, 0.78, 0.12, 1.0), 0.35)
	_shared_mats["hivis_vest"] = _make_mat(Color(0.96, 0.50, 0.10, 1.0), 0.6)
	_shared_mats["reflector"] = _make_mat(Color(0.92, 0.96, 0.36, 1.0), 0.25, true)
	_shared_mats["blueprint"] = _make_mat(Color(0.86, 0.93, 0.99, 1.0), 0.8)
	_shared_mats["police_navy"] = _make_mat(Color(0.13, 0.21, 0.36, 1.0), 0.78)
	_shared_mats["badge_gold"] = _make_mat(Color(0.95, 0.78, 0.22, 1.0), 0.3)
	_shared_mats["fire_red"] = _make_mat(Color(0.82, 0.14, 0.12, 1.0), 0.65)
	_shared_mats["baker_white"] = _make_mat(Color(0.97, 0.96, 0.93, 1.0), 0.82)
	_shared_mats["vendor_apron"] = _make_mat(Color(0.24, 0.46, 0.34, 1.0), 0.85)
	_shared_mats["barber_vest"] = _make_mat(Color(0.22, 0.24, 0.28, 1.0), 0.75)
	_shared_mats["dock_vest"] = _make_mat(Color(0.95, 0.42, 0.12, 1.0), 0.65)


func _make_mat(col: Color, rough: float, emissive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = 0.0
	if emissive:
		m.emission_enabled = true
		m.emission = col * 0.45
	return m


func _spawn_all_role_npcs() -> void:
	var builders := get_tree().get_nodes_in_group("city_mega_builder")
	var stations: Array[Dictionary] = []
	if not builders.is_empty() and builders[0].has_method("get_role_work_stations"):
		stations = builders[0].get_role_work_stations()

	var models := CharacterModelLoader.scan_character_models()
	if models.is_empty():
		push_warning("[RoleNPCSpawner] No character models found in assets/models/characters/")
		return

	var male_keys := ["Man", "dreiver", "ritchman", "Oldman", "homeless"]
	var mixed_keys := ["Man", "mama2", "studentgirl", "dreiver", "ritchman", "Oldman", "mama"]

	var idx := 0
	var is_web := OS.has_feature("web")
	var base_vis := 65.0 if is_web else VIS_NPC
	var active_stations: Array[Dictionary] = stations
	if is_web and stations.size() > 8:
		# On Web/iPhone Safari, keep the 8 nearest role stations around the central hub (10 crowd + 8 role = 18 max ambient NPCs)
		active_stations = stations.duplicate()
		active_stations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa: Vector3 = a.get("position", Vector3.ZERO)
			var pb: Vector3 = b.get("position", Vector3.ZERO)
			return pa.length_squared() < pb.length_squared()
		)
		active_stations.resize(8)

	for st in active_stations:
		idx += 1
		var role: String = str(st.get("role", "vendor"))
		var pos: Vector3 = st.get("position", Vector3.ZERO)
		var yaw: float = float(st.get("yaw", 0.0))
		var label_txt: String = str(st.get("label", "موظف"))
		var lines: PackedStringArray = PackedStringArray(st.get("lines", ["مرحباً بك في الأزهري!"]))

		var kw := _pick_keyword(role, idx, male_keys, mixed_keys)
		var model_path := CharacterModelLoader.find_model_path(kw)
		if model_path == "":
			model_path = models[idx % models.size()]["path"]

		var npc: CharacterBody3D = NPC_SCENE.instantiate()
		npc.name = "RoleNPC_%s_%d" % [role.capitalize(), idx]
		npc.position = pos
		var st_patrol: PackedVector3Array = st.get("patrol_points", PackedVector3Array())
		npc.patrol_points = st_patrol
		npc.walk_speed = float(st.get("walk_speed", 0.0))
		npc.npc_name = label_txt
		npc.dialogue_lines = lines
		npc.model_keyword = kw
		npc.explicit_model_path = model_path
		npc.height_variation = 0.0
		var act_radius: float = float(st.get("ai_activation_radius", 0.0))
		if "ai_activation_radius" in npc:
			npc.ai_activation_radius = act_radius
		if st.has("behavior_role") and "npc_behavior_role" in npc:
			npc.npc_behavior_role = int(st["behavior_role"])
		npc.set_meta("npc_role", role)
		npc.set_meta("station_district", str(st.get("district", "")))

		add_child(npc)
		_role_npcs.append(npc)

		# Apply stationary facing & throttled network sync
		if "visuals" in npc and npc.visuals:
			npc.visuals.rotation.y = yaw
		if "sync_yaw" in npc:
			npc.sync_yaw = yaw
		var net_sync := npc.get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
		if net_sync:
			net_sync.replication_interval = 0.6

		var vis_cap := minf(base_vis, act_radius + 15.0) if act_radius > 0.0 else base_vis
		_apply_visibility_cap(npc, vis_cap)
		_attach_role_uniform(npc, role)
		_add_role_nameplate(npc, label_txt)

	set_meta("role_npcs_spawned", _role_npcs.size())
	print("[RoleNPCSpawner] Spawned %d stationary role-dressed Mixamo NPCs." % _role_npcs.size())


func _pick_keyword(role: String, idx: int, male_keys: Array, mixed_keys: Array) -> String:
	match role:
		"doctor", "pharmacist":
			var med_keys := ["Man", "mama2", "studentgirl", "ritchman"]
			return med_keys[idx % med_keys.size()]
		"police", "firefighter", "engineer":
			return male_keys[idx % 3]
		"baker", "vendor", "barber", "dock_master":
			return mixed_keys[idx % mixed_keys.size()]
		"elder":
			return "Oldman"
		"pedestrian":
			return mixed_keys[idx % mixed_keys.size()]
		_:
			return mixed_keys[idx % mixed_keys.size()]


func _apply_visibility_cap(root: Node, dist: float) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).visibility_range_end = dist
	for child in root.get_children():
		_apply_visibility_cap(child, dist)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _attach_role_uniform(npc: Node, role: String) -> void:
	var skel := _find_skeleton(npc)
	if not skel:
		return

	# Convert Skeleton3D global scale to meter-accurate bone attachment local scale
	var skel_scale := maxf(skel.global_basis.get_scale().y, 0.005)
	var inv := 1.0 / skel_scale

	var head_bone := _find_bone(skel, ["mixamorig_Head", "Head", "head"])
	var chest_bone := _find_bone(skel, ["mixamorig_Spine2", "Spine2", "mixamorig_Spine1", "Spine1"])
	var hand_bone := _find_bone(skel, ["mixamorig_RightHand", "RightHand"])

	match role:
		"doctor", "pharmacist":
			if chest_bone != "":
				var ba := _make_bone_attach(skel, chest_bone, inv, "MedCoatAttach")
				# Crisp white medical lab coat shell around torso & lower coat tails
				_add_gear_box(ba, "CoatBack", Vector3(0.0, -0.08, -0.095), Vector3(0.38, 0.62, 0.12), _shared_mats["lab_coat"])
				_add_gear_box(ba, "CoatFrontL", Vector3(-0.11, -0.09, 0.085), Vector3(0.15, 0.60, 0.11), _shared_mats["lab_coat"])
				_add_gear_box(ba, "CoatFrontR", Vector3(0.11, -0.09, 0.085), Vector3(0.15, 0.60, 0.11), _shared_mats["lab_coat"])
				_add_gear_box(ba, "SideL", Vector3(-0.175, -0.07, 0.0), Vector3(0.08, 0.56, 0.24), _shared_mats["lab_coat"])
				_add_gear_box(ba, "SideR", Vector3(0.175, -0.07, 0.0), Vector3(0.08, 0.56, 0.24), _shared_mats["lab_coat"])
				var badge_mat: Material = _shared_mats["badge_med"] if role == "doctor" else _shared_mats["badge_pharm"]
				_add_gear_box(ba, "ChestBadge", Vector3(0.11, 0.09, 0.145), Vector3(0.07, 0.06, 0.02), badge_mat)
				if role == "doctor":
					_add_gear_cyl(ba, "StethoNeck", Vector3(0.0, 0.19, 0.02), 0.11, 0.04, _shared_mats["stethoscope"])
					_add_gear_box(ba, "StethoDropL", Vector3(-0.07, 0.09, 0.13), Vector3(0.025, 0.20, 0.025), _shared_mats["stethoscope"])
					_add_gear_box(ba, "StethoDropR", Vector3(0.07, 0.09, 0.13), Vector3(0.025, 0.20, 0.025), _shared_mats["stethoscope"])
		"engineer":
			if head_bone != "":
				var hba := _make_bone_attach(skel, head_bone, inv, "HardHatAttach")
				_add_gear_cyl(hba, "HatCrown", Vector3(0.0, 0.14, 0.0), 0.135, 0.12, _shared_mats["hardhat_yellow"])
				_add_gear_cyl(hba, "HatBrim", Vector3(0.0, 0.085, 0.025), 0.165, 0.025, _shared_mats["hardhat_yellow"])
			if chest_bone != "":
				var cba := _make_bone_attach(skel, chest_bone, inv, "HiVisAttach")
				_add_gear_box(cba, "VestFront", Vector3(0.0, -0.02, 0.09), Vector3(0.36, 0.42, 0.11), _shared_mats["hivis_vest"])
				_add_gear_box(cba, "VestBack", Vector3(0.0, -0.02, -0.09), Vector3(0.36, 0.42, 0.11), _shared_mats["hivis_vest"])
				_add_gear_box(cba, "ReflectBand", Vector3(0.0, -0.07, 0.0), Vector3(0.38, 0.07, 0.295), _shared_mats["reflector"])
			if hand_bone != "":
				var rba := _make_bone_attach(skel, hand_bone, inv, "BlueprintAttach")
				_add_gear_cyl(rba, "BlueprintRoll", Vector3(0.0, 0.04, 0.08), 0.032, 0.42, _shared_mats["blueprint"], Vector3(PI * 0.5, 0.0, 0.0))
		"police":
			if head_bone != "":
				var hba := _make_bone_attach(skel, head_bone, inv, "PoliceCapAttach")
				_add_gear_cyl(hba, "CapCrown", Vector3(0.0, 0.14, -0.01), 0.135, 0.09, _shared_mats["police_navy"])
				_add_gear_box(hba, "CapVisor", Vector3(0.0, 0.095, 0.11), Vector3(0.18, 0.022, 0.10), _shared_mats["stethoscope"])
				_add_gear_box(hba, "CapBadge", Vector3(0.0, 0.135, 0.125), Vector3(0.04, 0.04, 0.02), _shared_mats["badge_gold"])
			if chest_bone != "":
				var cba := _make_bone_attach(skel, chest_bone, inv, "PoliceTunicAttach")
				_add_gear_box(cba, "Tunic", Vector3(0.0, -0.03, 0.0), Vector3(0.37, 0.48, 0.26), _shared_mats["police_navy"])
				_add_gear_box(cba, "GoldBadge", Vector3(0.10, 0.08, 0.14), Vector3(0.06, 0.06, 0.02), _shared_mats["badge_gold"])
		"firefighter":
			if head_bone != "":
				var hba := _make_bone_attach(skel, head_bone, inv, "FireHelmetAttach")
				_add_gear_cyl(hba, "HelmetCrown", Vector3(0.0, 0.14, 0.0), 0.145, 0.13, _shared_mats["fire_red"])
				_add_gear_cyl(hba, "HelmetBrim", Vector3(0.0, 0.08, -0.02), 0.18, 0.025, _shared_mats["hardhat_yellow"])
			if chest_bone != "":
				var cba := _make_bone_attach(skel, chest_bone, inv, "FireJacketAttach")
				_add_gear_box(cba, "Jacket", Vector3(0.0, -0.04, 0.0), Vector3(0.39, 0.52, 0.28), _shared_mats["fire_red"])
				_add_gear_box(cba, "Stripe", Vector3(0.0, -0.10, 0.0), Vector3(0.41, 0.07, 0.295), _shared_mats["reflector"])
		"baker":
			if head_bone != "":
				var hba := _make_bone_attach(skel, head_bone, inv, "BakerCapAttach")
				_add_gear_cyl(hba, "ChefToque", Vector3(0.0, 0.16, 0.0), 0.125, 0.16, _shared_mats["baker_white"])
			if chest_bone != "":
				var cba := _make_bone_attach(skel, chest_bone, inv, "ApronAttach")
				_add_gear_box(cba, "ApronFront", Vector3(0.0, -0.12, 0.115), Vector3(0.30, 0.62, 0.05), _shared_mats["baker_white"])
		"dock_master":
			if head_bone != "":
				var hba := _make_bone_attach(skel, head_bone, inv, "DockCapAttach")
				_add_gear_cyl(hba, "MarinaCap", Vector3(0.0, 0.14, 0.0), 0.13, 0.09, _shared_mats["police_navy"])
				_add_gear_box(hba, "CapPeak", Vector3(0.0, 0.095, 0.11), Vector3(0.17, 0.02, 0.09), _shared_mats["baker_white"])
			if chest_bone != "":
				var cba := _make_bone_attach(skel, chest_bone, inv, "LifeVestAttach")
				_add_gear_box(cba, "LifeVest", Vector3(0.0, -0.02, 0.0), Vector3(0.38, 0.40, 0.27), _shared_mats["dock_vest"])
		"barber":
			if chest_bone != "":
				var cba := _make_bone_attach(skel, chest_bone, inv, "BarberVestAttach")
				_add_gear_box(cba, "BarberApron", Vector3(0.0, -0.10, 0.11), Vector3(0.31, 0.56, 0.05), _shared_mats["barber_vest"])
				_add_gear_box(cba, "PocketTrim", Vector3(0.08, 0.06, 0.14), Vector3(0.08, 0.05, 0.02), _shared_mats["fire_red"])
		"elder", "pedestrian":
			# Everyday Sudanese neighborhood residents wear their natural model outfits without work vests
			return
		_:
			# Vendor / shopkeeper apron
			if chest_bone != "":
				var cba := _make_bone_attach(skel, chest_bone, inv, "VendorApronAttach")
				_add_gear_box(cba, "VendorApron", Vector3(0.0, -0.10, 0.11), Vector3(0.31, 0.55, 0.05), _shared_mats["vendor_apron"])


func _find_bone(skel: Skeleton3D, candidates: Array[String]) -> String:
	for b in candidates:
		if skel.find_bone(b) >= 0:
			return b
	return ""


func _make_bone_attach(skel: Skeleton3D, bone_name: String, inv_scale: float, n_name: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.name = n_name
	ba.bone_name = bone_name
	ba.scale = Vector3.ONE * inv_scale
	skel.add_child(ba)
	return ba


func _add_gear_box(parent: Node3D, n_name: String, pos: Vector3, sz: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = n_name
	mi.position = pos
	var bm := BoxMesh.new()
	bm.size = sz
	bm.material = mat
	mi.mesh = bm
	mi.visibility_range_end = VIS_NPC
	parent.add_child(mi)


func _add_gear_cyl(parent: Node3D, n_name: String, pos: Vector3, rad: float, h: float, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.name = n_name
	mi.position = pos
	mi.rotation = rot
	var cm := CylinderMesh.new()
	cm.top_radius = rad
	cm.bottom_radius = rad
	cm.height = h
	cm.radial_segments = 14
	cm.material = mat
	mi.mesh = cm
	mi.visibility_range_end = VIS_NPC
	parent.add_child(mi)


func _add_role_nameplate(npc: Node3D, title_txt: String) -> void:
	var lbl := Label3D.new()
	lbl.name = "RoleTag"
	lbl.text = title_txt
	lbl.position = Vector3(0.0, 2.25, 0.0)
	lbl.font_size = 24
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(1.0, 0.96, 0.82, 1.0)
	lbl.outline_size = 5
	lbl.visibility_range_end = 36.0
	npc.add_child(lbl)
