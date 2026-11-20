extends Node3D
class_name CrowdSpawner

## Scans res://assets/models/characters/ and spawns 55+ distinct clones (5x per folder)
## of every .glb/.gltf character model found, normalizing height/speed and assigning
## patrols across main avenues, side alleys, apartment upper landings/balconies,
## bus stations, the Amary/Sa'ud shop, kiosks, and the Nile Corniche promenade.

const CLONES_PER_MODEL: int = 5
const NPC_SCENE: PackedScene = preload("res://scenes/npc.tscn")

const SUDANESE_MALE_NAMES: Array[String] = [
	"أحمد", "محمد", "عمر", "عثمان", "خالد", "طارق", "حسن", "ياسر",
	"عباس", "إبراهيم", "مصطفى", "صلاح", "نادر", "كمال", "فيصل", "هشام",
	"عوض", "بابكر", "التيجاني", "عبدالله", "مبارك", "الهادي"
]
const SUDANESE_FEMALE_NAMES: Array[String] = [
	"فاطمة", "آمنة", "حاجة مريم", "زينب", "سلمى", "عائشة", "سمية", "هدى",
	"رابحة", "إنعام", "سعاد", "كوثر"
]
const SUDANESE_KID_NAMES: Array[String] = [
	"أنس", "بلال", "معاذ", "ريان", "مازن", "عمار"
]

const DIALOGUE_POOL: Array[String] = [
	"السلام عليكم يا زول! كيف أخبارك؟",
	"الحمد لله، الحلة في الأزهري الليلة هادية وسمحة.",
	"الجو دافي وشمس الخرطوم منورة الشارع.",
	"شوف كورنيش النيل ومواقف البصات، الحركة ما شاء الله.",
	"ربنا يبارك فيك ويحفظ حي الأزهري وأهله.",
	"لو ماشي بالبص ولا الركشة خلي بالك من المطبات!",
	"محل العماري والصعوط فاتح جنب السوق، والأكشاك ملانة بارد."
]

# Patrol loops spanning main avenues, side alleys, apartment upper floors/balconies, bus stops, and Nile Corniche
const PATROL_LOOPS: Array[Array] = [
	# Main market & Amary/Sa'ud shop sidewalk
	[Vector3(10, 0, -10), Vector3(32, 0, -10), Vector3(52, 0, -10), Vector3(26, 0, -9.5)],
	[Vector3(14, 0, -9), Vector3(44, 0, -9), Vector3(58, 0, -9), Vector3(30, 0, -10)],
	# Mosque plaza & Central Bus Station queue (clear of kiosks by >= 3.5m)
	[Vector3(-10, 0, -10), Vector3(-28, 0, -10), Vector3(-36, 0, -24), Vector3(-12, 0, -11.5)],
	[Vector3(-9.5, 0, -30), Vector3(-9.5, 0, -22), Vector3(-11, 0, -25), Vector3(-9.5, 0, -34)],
	# Tea stall & Gas Station sidewalk
	[Vector3(10, 0, 10), Vector3(24, 0, 10), Vector3(24, 0, 24), Vector3(10, 0, 20)],
	[Vector3(44, 0, 11), Vector3(58, 0, 11), Vector3(58, 0, 18), Vector3(44, 0, 18)],
	# ApartmentWest courtyard & sidewalk
	[Vector3(-10, 0, 10), Vector3(-28, 0, 10), Vector3(-28, 0, 26), Vector3(-10, 0, 24)],
	# Fish Market & East Bus Station (3.5m+ clear of Kiosk_2)
	[Vector3(70, 0, -11), Vector3(96, 0, -11), Vector3(96, 0, -24), Vector3(72, 0, -22)],
	[Vector3(56, 0, 11.5), Vector3(71, 0, 11.5), Vector3(71, 0, 15.5), Vector3(56, 0, 15.5)],
	# Side alleys (زقاقات وشوارع فرعية)
	[Vector3(60, 0, -24), Vector3(60, 0, 10), Vector3(66, 0, 10), Vector3(66, 0, -24)],
	[Vector3(-60, 0, -20), Vector3(-60, 0, 18), Vector3(-54, 0, 18), Vector3(-54, 0, -20)],
	[Vector3(8, 0, -32), Vector3(8, 0, -62), Vector3(-8, 0, -62), Vector3(-8, 0, -32)],
	[Vector3(8, 0, 26), Vector3(8, 0, 62), Vector3(-8, 0, 62), Vector3(-8, 0, 26)],
	[Vector3(-76, 0, -62), Vector3(-36, 0, -62), Vector3(-36, 0, -66), Vector3(-76, 0, -66)],
	[Vector3(36, 0, 62), Vector3(78, 0, 62), Vector3(78, 0, 66), Vector3(36, 0, 66)],
	# Nile Corniche Promenade (شارع النيل)
	[Vector3(-135, 0, -45), Vector3(-135, 0, -10), Vector3(-137, 0, 25), Vector3(-135, 0, -15)],
	[Vector3(-136, 0, 15), Vector3(-136, 0, 65), Vector3(-138, 0, 40), Vector3(-136, 0, 20)],
	# Apartment Residents living on Upper Floors / Balconies / Landings (ApartmentWest at -20, 0, 24 rotated +90 deg)
	[Vector3(-15.0, 3.55, 24.0), Vector3(-19.5, 3.55, 24.0), Vector3(-19.5, 3.55, 21.0), Vector3(-15.0, 3.55, 24.0)],
	# ApartmentEast Upper Floor Resident (ApartmentEast at 20, 0, 42 rotated -90 deg)
	[Vector3(15.0, 3.55, 42.0), Vector3(19.5, 3.55, 42.0), Vector3(19.5, 3.55, 45.0), Vector3(15.0, 3.55, 42.0)],
]


func _ready() -> void:
	_spawn_crowd()


func _spawn_crowd() -> void:
	if OS.has_feature("web"):
		return
	var models := CharacterModelLoader.scan_character_models()
	if models.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 472026
	var clone_idx := 0
	var is_web := OS.has_feature("web")
	var clones_per_model := 1 if is_web else CLONES_PER_MODEL
	var max_web_crowd := 10

	for entry in models:
		if is_web and clone_idx >= max_web_crowd:
			break
		var model_path: String = String(entry["path"])
		var mname: String = String(entry["name"]).to_lower()
		var is_kid := mname.contains("kid")
		var is_female := mname.contains("woman") or mname.contains("mama") or mname.contains("girl")

		for c in range(clones_per_model):
			if is_web and clone_idx >= max_web_crowd:
				break
			var npc := NPC_SCENE.instantiate() as NPCInteractive
			npc.name = "Crowd_%d" % clone_idx

			var loop_idx := clone_idx % PATROL_LOOPS.size()
			var loop_pts: Array = PATROL_LOOPS[loop_idx]
			var p_array := PackedVector3Array()
			var is_elevated := (loop_pts[0] as Vector3).y > 1.0
			var jitter := Vector3.ZERO if is_elevated else Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
			for pt in loop_pts:
				p_array.append((pt as Vector3) + jitter)

			var start_pt: Vector3 = p_array[c % p_array.size()]
			npc.position = Vector3(start_pt.x, start_pt.y + 0.1, start_pt.z)
			npc.patrol_points = p_array
			npc.explicit_model_path = model_path
			npc.target_height = 1.30 if is_kid else 1.72
			npc.height_variation = rng.randf_range(0.94, 1.06)
			npc.walk_speed = rng.randf_range(1.40, 2.15)

			if is_kid:
				npc.npc_name = SUDANESE_KID_NAMES[clone_idx % SUDANESE_KID_NAMES.size()]
			elif is_female:
				npc.npc_name = SUDANESE_FEMALE_NAMES[clone_idx % SUDANESE_FEMALE_NAMES.size()]
			else:
				npc.npc_name = SUDANESE_MALE_NAMES[clone_idx % SUDANESE_MALE_NAMES.size()]

			var d1 := DIALOGUE_POOL[clone_idx % DIALOGUE_POOL.size()]
			var d2 := DIALOGUE_POOL[(clone_idx + 2) % DIALOGUE_POOL.size()]
			npc.dialogue_lines = PackedStringArray([d1, d2])

			var sync := npc.get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
			if sync:
				sync.replication_interval = 0.25

			add_child(npc)
			if is_web:
				_cap_npc_visibility(npc, 180.0)
			clone_idx += 1


func _cap_npc_visibility(node: Node, max_dist: float) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if gi.visibility_range_end <= 0.0 or gi.visibility_range_end > max_dist:
			gi.visibility_range_end = max_dist
	for ch in node.get_children():
		_cap_npc_visibility(ch, max_dist)
