extends Node

## Central Data-Driven Mission & Jobs System (`scripts/mission_manager.gd`).
## Autoload singleton (`MissionManager`) powering 12 distinct missions across the 1,400m x 1,400m
## Al-Azhari / Khartoum map: 7 Small Quick Jobs + 5 Large Multi-Stage Missions.
## Strictly preserves locked core scripts (`player.gd`, `character_model_loader.gd`,
## `mixamo_animation_controller.gd`, `network_manager.gd`).

signal mission_started(mission: Dictionary)
signal mission_step_updated(mission: Dictionary, step_index: int, step_data: Dictionary)
signal mission_completed(mission: Dictionary, reward_sdg: int, reward_xp: int, summary_text: String)
signal mission_failed(mission: Dictionary, reason: String)
signal mission_cancelled()
signal stats_changed(sdg: int, xp: int, level: int)
signal nearby_giver_changed(giver_info: Dictionary)
signal hud_banner_requested(text: String, accent_color: Color)

const DAFFAR_SCENE_PATH: String = "res://scenes/daffar.tscn"
const DAFFAR_SCENE: PackedScene = preload("res://scenes/daffar.tscn")

var sdg_cash: int = 5000
var xp: int = 0
var level: int = 1
var completed_counts: Dictionary = {}

var _catalog: Array[Dictionary] = []
var active_mission: Dictionary = {}
var active_step_index: int = -1
var active_steps: Array[Dictionary] = []
var mission_time_left: float = 0.0
var mission_elapsed: float = 0.0
var cargo_integrity: float = 100.0
var daffori_goals: int = 0
var _last_vehicle_speed: float = 0.0
var _hold_progress: float = 0.0

var _nearby_giver: Dictionary = {}
var _giver_scan_timer: float = 0.0

# Runtime 3D helper nodes placed inside active main scene
var _world_container: Node3D = null
var _beacon_root: Node3D = null
var _beacon_ring: MeshInstance3D = null
var _beacon_pillar: MeshInstance3D = null
var _beacon_diamond: MeshInstance3D = null
var _beacon_label: Label3D = null
var _beacon_pulse_t: float = 0.0

var _car_wash_root: Node3D = null
var _car_wash_mist: MeshInstance3D = null
var _car_wash_timer: float = 0.0

var _mission_props_root: Node3D = null
var _mission_ball: Node3D = null
var _ball_vel: Vector3 = Vector3.ZERO
var _ferry_boat: Node3D = null
var _ferry_boarding_active: bool = false
var _ferry_target_idx: int = 0
var _ferry_waypoints: Array[Vector3] = []
var _spawned_convoy_truck: Node3D = null

var _sfx_player: AudioStreamPlayer = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_mission_catalog()
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "MissionSFX"
	add_child(_sfx_player)


func get_all_missions() -> Array[Dictionary]:
	return _catalog


func get_small_missions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in _catalog:
		if str(m.get("category", "")) == "small":
			out.append(m)
	return out


func get_large_missions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in _catalog:
		if str(m.get("category", "")) == "large":
			out.append(m)
	return out


func is_mission_active() -> bool:
	return not active_mission.is_empty() and active_step_index >= 0 and active_step_index < active_steps.size()


func get_current_step() -> Dictionary:
	if not is_mission_active():
		return {}
	return active_steps[active_step_index]


func get_active_waypoint() -> Dictionary:
	if not is_mission_active():
		return {}
	var step := active_steps[active_step_index]
	return {
		"position": step.get("position", Vector3.ZERO),
		"label": str(step.get("short_label", step.get("title", "هدف المهمة"))),
		"color": active_mission.get("color", Color(1.0, 0.82, 0.22)),
		"step_index": active_step_index,
		"step_total": active_steps.size(),
	}


func get_distance_to_waypoint() -> float:
	if not is_mission_active():
		return 0.0
	var p := _get_local_player()
	if not p:
		return 0.0
	var target: Vector3 = active_steps[active_step_index].get("position", Vector3.ZERO)
	return p.global_position.distance_to(target)


func get_nearby_giver() -> Dictionary:
	return _nearby_giver


func _build_mission_catalog() -> void:
	_catalog = [
		# ===================== 7 SMALL QUICK JOBS =====================
		{
			"id": "small_taxi_dropoff",
			"category": "small",
			"title": "توصيل ركاب (تاكسي / بص)",
			"subtitle": "Passenger Taxi/Bus Drop-off",
			"description": "اصطحب الركاب المنتظرين من المحطة وأوصلهم إلى وجهتهم قبل انتهاء الوقت.",
			"reward_sdg": 2400,
			"reward_xp": 95,
			"time_limit": 130.0,
			"roles": ["vendor", "barber"],
			"color": Color(1.0, 0.82, 0.18),
			"repeatable": true,
		},
		{
			"id": "small_bread_delivery",
			"category": "small",
			"title": "توزيع الخبز الساخن",
			"subtitle": "Hot Bread Delivery",
			"description": "استلم أقفاص الخبز الطازج من أقرب مخبز آلي ووزّعها على الأكشاك والمقاهي.",
			"reward_sdg": 2200,
			"reward_xp": 90,
			"time_limit": 145.0,
			"roles": ["baker"],
			"color": Color(0.98, 0.62, 0.22),
			"repeatable": true,
		},
		{
			"id": "small_pharmacy_delivery",
			"category": "small",
			"title": "توصيل دواء عاجل",
			"subtitle": "Urgent Pharmacy Delivery",
			"description": "استلم الدواء العاجل من الصيدلية المناوبة وأوصله فوراً لمنزل المريض.",
			"reward_sdg": 2600,
			"reward_xp": 110,
			"time_limit": 120.0,
			"roles": ["doctor", "pharmacist"],
			"color": Color(0.24, 0.88, 0.54),
			"repeatable": true,
		},
		{
			"id": "small_bridge_patrol",
			"category": "small",
			"title": "بلاغ شرطة / إطفاء الجسر",
			"subtitle": "Bridge Patrol & Hazard Response",
			"description": "استجب للبلاغ الطارئ أعلى جسر النيل الكبير أو الكبري العلوي وقم بتأمين الموقع.",
			"reward_sdg": 3000,
			"reward_xp": 130,
			"time_limit": 130.0,
			"roles": ["police", "firefighter"],
			"color": Color(0.28, 0.62, 1.0),
			"repeatable": true,
		},
		{
			"id": "small_car_wash",
			"category": "small",
			"title": "غسيل وتلميع السيارات",
			"subtitle": "Car Wash Valet Service",
			"description": "قد مركبتك عبر بوابة الرش الآلي في مغسلة الخرطوم لتنظيفها وتعبئة وقودها بالكامل.",
			"reward_sdg": 1800,
			"reward_xp": 75,
			"time_limit": 140.0,
			"roles": ["vendor", "barber"],
			"color": Color(0.24, 0.84, 0.96),
			"repeatable": true,
		},
		{
			"id": "small_nile_ferry",
			"category": "small",
			"title": "عَبّارة النيل للركاب",
			"subtitle": "Nile Ferry River Crossing",
			"description": "انطلق بالقارب من المرسى الشرقي واعبر نهر النيل إلى الضفة الغربية ثم عد بسلام.",
			"reward_sdg": 2800,
			"reward_xp": 120,
			"time_limit": 150.0,
			"roles": ["dock_master"],
			"color": Color(0.18, 0.72, 0.98),
			"repeatable": true,
		},
		{
			"id": "small_daffori_hattrick",
			"category": "small",
			"title": "تحدي هاتريك الدافوري",
			"subtitle": "Daffori Football Hat-Trick",
			"description": "سجّل 3 أهداف متتالية في ملعب دافوري الأزهري! اقترب من الكرة أو اضغط [E] للتسديد.",
			"reward_sdg": 2500,
			"reward_xp": 115,
			"time_limit": 120.0,
			"roles": ["barber", "vendor"],
			"color": Color(0.45, 0.94, 0.36),
			"repeatable": true,
		},
		# ===================== 5 LARGE MULTI-STAGE MISSIONS =====================
		{
			"id": "large_engineer_inspection",
			"category": "large",
			"title": "جولة كبير المهندسين",
			"subtitle": "Chief Engineer's Infrastructure Inspection",
			"description": "استلم المخططات من مكتب الهندسة، افحص جسر النيل الكبير وجميع الأنفاق الأربعة المضيئة، ثم عُد بالتقرير.",
			"reward_sdg": 12000,
			"reward_xp": 450,
			"time_limit": 420.0,
			"roles": ["engineer"],
			"color": Color(0.98, 0.76, 0.16),
			"repeatable": true,
		},
		{
			"id": "large_cargo_convoy",
			"category": "large",
			"title": "قافلة الإمداد الكبرى",
			"subtitle": "Cross-Nile Heavy Cargo Convoy",
			"description": "قُد شاحنة الدفار المحمّلة من السوق المركزي عبر النفق الشمالي وجسر النيل إلى مستودع الضفة الغربية بأقل أضرار.",
			"reward_sdg": 15000,
			"reward_xp": 520,
			"time_limit": 360.0,
			"roles": ["vendor", "engineer"],
			"color": Color(0.94, 0.50, 0.18),
			"repeatable": true,
		},
		{
			"id": "large_khartoum_rally",
			"category": "large",
			"title": "رالي الخرطوم الكبرى (15 نقطة)",
			"subtitle": "Grand Khartoum Street & Tunnel Rally",
			"description": "سباق سرعة عبر 15 نقطة مرور تشمل الكورنيش والجسور العلوية والأنفاق الأربعة (فردي أو مع الأصدقاء أونلاين).",
			"reward_sdg": 20000,
			"reward_xp": 700,
			"time_limit": 360.0,
			"roles": ["police", "engineer"],
			"color": Color(1.0, 0.32, 0.42),
			"repeatable": true,
		},
		{
			"id": "large_bridge_emergency",
			"category": "large",
			"title": "حالة طوارئ شاملة",
			"subtitle": "Multi-Agency Bridge Emergency",
			"description": "استجابة متعددة الجهات: استلم البلاغ، أمّن جسر النيل، أخمد الخطر على الطريق، ثم أوصل الإمدادات للمركز الصحي.",
			"reward_sdg": 16000,
			"reward_xp": 580,
			"time_limit": 320.0,
			"roles": ["police", "firefighter", "doctor"],
			"color": Color(0.98, 0.26, 0.24),
			"repeatable": true,
		},
		{
			"id": "large_mosques_supply",
			"category": "large",
			"title": "قافلة تجهيز الجوامع الأربعة",
			"subtitle": "Mosques & Community Supply Run",
			"description": "استلم مستلزمات الإنارة والصيانة من السوق التجاري وأوصلها إلى الجوامع الأربعة في الضفتين الشرقية والغربية.",
			"reward_sdg": 14000,
			"reward_xp": 500,
			"time_limit": 380.0,
			"roles": ["baker", "vendor", "doctor"],
			"color": Color(0.28, 0.88, 0.56),
			"repeatable": true,
		},
	]


func find_mission_by_id(mission_id: String) -> Dictionary:
	for m in _catalog:
		if str(m.get("id", "")) == mission_id:
			return m
	return {}


func start_mission(mission_id: String) -> bool:
	var m := find_mission_by_id(mission_id)
	if m.is_empty():
		return false

	_cleanup_mission_runtime()
	_ensure_world_nodes()

	active_mission = m.duplicate(true)
	active_steps = _generate_steps_for_mission(mission_id)
	if active_steps.is_empty():
		active_mission = {}
		return false

	active_step_index = 0
	mission_time_left = float(m.get("time_limit", 180.0))
	mission_elapsed = 0.0
	cargo_integrity = 100.0
	daffori_goals = 0
	_hold_progress = 0.0
	_ferry_boarding_active = false

	_setup_special_mission_props(mission_id)
	_update_beacon_for_current_step()
	_play_chime(1.0)

	mission_started.emit(active_mission)
	mission_step_updated.emit(active_mission, active_step_index, active_steps[active_step_index])
	hud_banner_requested.emit("بدأت المهمة: %s" % str(active_mission["title"]), active_mission.get("color", Color.GOLD))

	if mission_id == "large_khartoum_rally" and _is_online_multiplayer():
		_rpc_announce_rally.rpc("بدأ رالي الخرطوم الكبرى (15 نقطة)! انطلق نحو الكورنيش!")

	return true


func cancel_mission() -> void:
	if not is_mission_active():
		return
	var title_txt: String = str(active_mission.get("title", ""))
	_cleanup_mission_runtime()
	active_mission = {}
	active_steps.clear()
	active_step_index = -1
	mission_cancelled.emit()
	hud_banner_requested.emit("تم إلغاء المهمة: %s" % title_txt, Color(0.95, 0.55, 0.32))


func accept_nearby_giver_mission() -> bool:
	if _nearby_giver.is_empty():
		return false
	var m_id: String = str(_nearby_giver.get("mission_id", ""))
	if m_id == "":
		return false
	return start_mission(m_id)


func _generate_steps_for_mission(mission_id: String) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	match mission_id:
		"small_taxi_dropoff":
			var stops: Array[Dictionary] = [
				{"name": "محطة الأزهري المركزية", "pos": Vector3(12.0, 0.0, -52.0)},
				{"name": "موقف الكورنيش الشمالي", "pos": Vector3(-104.0, 0.0, -210.0)},
				{"name": "سوق الشرق التجاري", "pos": Vector3(290.0, 0.0, -185.0)},
				{"name": "محطة الضفة الغربية", "pos": Vector3(-282.0, 0.0, -20.0)},
				{"name": "موقف حي الشباب والملعب", "pos": Vector3(145.0, 0.0, 345.0)},
				{"name": "موقف المستشفى المركزي", "pos": Vector3(292.0, 0.0, 78.0)},
			]
			var start_i: int = _rng.randi_range(0, stops.size() - 1)
			var dest_i: int = (start_i + _rng.randi_range(1, stops.size() - 1)) % stops.size()
			var s_stop: Dictionary = stops[start_i]
			var d_stop: Dictionary = stops[dest_i]
			steps.append({
				"title": "اصطحب الراكب من %s" % str(s_stop["name"]),
				"short_label": "راكب منتظر",
				"position": s_stop["pos"],
				"radius": 6.5,
				"mode": "reach",
			})
			steps.append({
				"title": "أوصل الراكب إلى %s" % str(d_stop["name"]),
				"short_label": str(d_stop["name"]),
				"position": d_stop["pos"],
				"radius": 7.0,
				"mode": "reach",
			})

		"small_bread_delivery":
			var bakeries: Array[Dictionary] = [
				{"name": "مخبز الأزهري الآلي", "pos": Vector3(26.5, 0.0, -11.0)},
				{"name": "مخبز الكورنيش الآلي", "pos": Vector3(-76.0, 0.0, -220.0)},
				{"name": "مخبز السوق التجاري الآلي", "pos": Vector3(295.0, 0.0, -234.0)},
				{"name": "مخبز حي الشباب الآلي", "pos": Vector3(155.0, 0.0, 234.0)},
				{"name": "مخبز الضفة الغربية الآلي", "pos": Vector3(-335.0, 0.0, 115.0)},
				{"name": "مخبز المنطقة الهندسية الآلي", "pos": Vector3(475.0, 0.0, -234.0)},
			]
			var b_pick: Dictionary = _pick_nearest_point(bakeries)
			steps.append({
				"title": "استلم أقفاص الخبز الساخن من %s" % str(b_pick["name"]),
				"short_label": "المخبز الآلي",
				"position": b_pick["pos"],
				"radius": 6.5,
				"mode": "reach",
			})
			steps.append({
				"title": "أوصل الخبز إلى ركن الشاي والمقهى (وسط الحي)",
				"short_label": "مقهى الأزهري",
				"position": Vector3(16.6, 0.0, 16.6),
				"radius": 6.5,
				"mode": "reach",
			})
			steps.append({
				"title": "أوصل الدفعة الثانية إلى دكان الكورنيش",
				"short_label": "كشك الكورنيش",
				"position": Vector3(-106.0, 0.0, 155.0),
				"radius": 7.0,
				"mode": "reach",
			})

		"small_pharmacy_delivery":
			var pharms: Array[Dictionary] = [
				{"name": "صيدلية الشفاء المناوبة", "pos": Vector3(304.0, 0.0, -145.0)},
				{"name": "صيدلية المستشفى المركزي", "pos": Vector3(300.0, 0.0, 78.0)},
				{"name": "صيدلية عيادة الضفة الغربية", "pos": Vector3(-472.0, 0.0, -90.0)},
			]
			var p_pick: Dictionary = _pick_nearest_point(pharms)
			var houses: Array[Dictionary] = [
				{"name": "حوش الأسرة الجنوبي", "pos": Vector3(-44.0, 0.0, 34.0)},
				{"name": "فيلا الضفة الغربية", "pos": Vector3(-345.0, 0.0, -28.0)},
				{"name": "منزل حي الشباب", "pos": Vector3(88.0, 0.0, 265.0)},
			]
			var h_pick: Dictionary = houses[_rng.randi_range(0, houses.size() - 1)]
			steps.append({
				"title": "استلم الطرد الدوائي العاجل من %s" % str(p_pick["name"]),
				"short_label": "الصيدلية المناوبة",
				"position": p_pick["pos"],
				"radius": 6.5,
				"mode": "reach",
			})
			steps.append({
				"title": "أوصل الدواء العاجل إلى %s" % str(h_pick["name"]),
				"short_label": str(h_pick["name"]),
				"position": h_pick["pos"],
				"radius": 7.0,
				"mode": "reach",
			})

		"small_bridge_patrol":
			var incidents: Array[Dictionary] = [
				{"name": "منتصف جسر النيل الكبير", "pos": Vector3(-190.0, 6.2, 0.0)},
				{"name": "الكبري العلوي الشرقي", "pos": Vector3(400.0, 6.2, 0.0)},
				{"name": "جسر النيل الشمالي", "pos": Vector3(-190.0, 6.2, -360.0)},
			]
			var inc: Dictionary = incidents[_rng.randi_range(0, incidents.size() - 1)]
			steps.append({
				"title": "توجه بسرعة إلى البلاغ في %s" % str(inc["name"]),
				"short_label": "بلاغ طارئ",
				"position": inc["pos"],
				"radius": 8.0,
				"mode": "hold",
				"hold_seconds": 2.0,
			})

		"small_car_wash":
			steps.append({
				"title": "قد سيارتك إلى بوابة مغسلة الخرطوم الآلية",
				"short_label": "مغسلة السيارات",
				"position": Vector3(188.0, 0.0, -28.0),
				"radius": 6.5,
				"mode": "car_wash",
				"hold_seconds": 2.5,
			})

		"small_nile_ferry":
			steps.append({
				"title": "توجّه إلى مرسى النيل الشرقي للصعود إلى العبّارة",
				"short_label": "مرسى النيل الشرقي",
				"position": Vector3(-144.0, 0.45, -90.0),
				"radius": 6.5,
				"mode": "ferry_board",
			})
			steps.append({
				"title": "أبحر بالعبّارة عبر النيل إلى مرسى الضفة الغربية",
				"short_label": "مرسى الضفة الغربية",
				"position": Vector3(-228.0, 0.45, -110.0),
				"radius": 9.5,
				"mode": "ferry_sail",
			})
			steps.append({
				"title": "عُد بالركاب إلى مرسى النيل الشرقي",
				"short_label": "العودة للمرسى الشرقي",
				"position": Vector3(-152.0, 0.45, -90.0),
				"radius": 9.5,
				"mode": "ferry_sail",
			})

		"small_daffori_hattrick":
			steps.append({
				"title": "سجّل 3 أهداف (هاتريك) في ملعب دافوري الأزهري! (اقترب من الكرة أو اضغط [E])",
				"short_label": "مرمى الدافوري",
				"position": Vector3(103.5, 0.5, 34.0),
				"radius": 5.0,
				"mode": "daffori",
			})

		"large_engineer_inspection":
			steps = [
				{"title": "استلم المخططات الهندسية من مركز الهندسة والإنشاءات", "short_label": "مركز الهندسة", "position": Vector3(472.0, 0.0, -95.0), "radius": 7.5, "mode": "reach"},
				{"title": "افحص جسر النيل الكبير (أعلى الجسر)", "short_label": "جسر النيل الكبير", "position": Vector3(-190.0, 6.2, 0.0), "radius": 9.0, "mode": "reach"},
				{"title": "افحص النفق الأول المضيء (النفق الشمالي)", "short_label": "النفق الشمالي", "position": Vector3(0.0, -6.8, -200.0), "radius": 9.0, "mode": "reach"},
				{"title": "افحص النفق الثاني المضيء (النفق الأوسط)", "short_label": "النفق الأوسط", "position": Vector3(220.0, -6.8, 200.0), "radius": 9.0, "mode": "reach"},
				{"title": "افحص النفق الثالث المضيء (النفق الشرقي)", "short_label": "النفق الشرقي", "position": Vector3(400.0, -6.8, 200.0), "radius": 9.0, "mode": "reach"},
				{"title": "افحص النفق الرابع المضيء (نفق الضفة الغربية)", "short_label": "النفق الغربي", "position": Vector3(-420.0, -6.8, 200.0), "radius": 9.0, "mode": "reach"},
				{"title": "عُد بتقرير الفحص إلى مركز الهندسة والإنشاءات", "short_label": "تسليم التقرير", "position": Vector3(472.0, 0.0, -95.0), "radius": 8.0, "mode": "reach"},
			]

		"large_cargo_convoy":
			steps = [
				{"title": "حمّل شحنة الإمداد من السوق المركزي (شاحنة الدفار جاهزة بجانبك)", "short_label": "تحميل الشحنة", "position": Vector3(36.0, 0.0, -6.0), "radius": 8.5, "mode": "reach"},
				{"title": "اعبر النفق الشمالي المضيء بحذر", "short_label": "النفق الشمالي", "position": Vector3(0.0, -6.8, -200.0), "radius": 10.0, "mode": "reach"},
				{"title": "اعبر جسر النيل الكبير نحو الضفة الغربية", "short_label": "جسر النيل الكبير", "position": Vector3(-190.0, 6.2, 0.0), "radius": 10.0, "mode": "reach"},
				{"title": "اسلك شارع كورنيش الضفة الغربية", "short_label": "كورنيش الغرب", "position": Vector3(-268.0, 0.0, -120.0), "radius": 10.0, "mode": "reach"},
				{"title": "سلّم القافلة في مستودع الضفة الغربية بأمان", "short_label": "مستودع الضفة الغربية", "position": Vector3(-472.0, 0.0, -155.0), "radius": 10.0, "mode": "reach"},
			]

		"large_khartoum_rally":
			var rally_pts: Array[Array] = [
				["نقطة 1: انطلاق صينية الأزهري", Vector3(0.0, 0.0, -35.0)],
				["نقطة 2: مدخل النفق الشمالي", Vector3(-68.0, -0.5, -200.0)],
				["نقطة 3: قلب النفق الشمالي", Vector3(0.0, -6.8, -200.0)],
				["نقطة 4: طريق السوق التجاري", Vector3(135.0, 0.0, -200.0)],
				["نقطة 5: الكبري العلوي الهندسي", Vector3(220.0, 6.2, -200.0)],
				["نقطة 6: الكبري العلوي الشمالي", Vector3(220.0, 6.2, -360.0)],
				["نقطة 7: صينية الشمال المركزية", Vector3(0.0, 0.0, -360.0)],
				["نقطة 8: جسر النيل الشمالي", Vector3(-190.0, 6.2, -360.0)],
				["نقطة 9: الكبري العلوي للضفة الغربية", Vector3(-420.0, 6.2, -200.0)],
				["نقطة 10: نفق الضفة الغربية", Vector3(-420.0, -6.8, 200.0)],
				["نقطة 11: جسر النيل الكبير", Vector3(-190.0, 6.2, 0.0)],
				["نقطة 12: الكبري العلوي الشرقي", Vector3(400.0, 6.2, 0.0)],
				["نقطة 13: النفق الشرقي المضيء", Vector3(400.0, -6.8, 200.0)],
				["نقطة 14: النفق الجنوبي الأوسط", Vector3(220.0, -6.8, 200.0)],
				["نقطة 15: خط النهاية - صينية الأزهري!", Vector3(0.0, 0.0, 22.0)],
			]
			for rp in rally_pts:
				steps.append({
					"title": str(rp[0]),
					"short_label": str(rp[0]),
					"position": rp[1],
					"radius": 11.5,
					"mode": "reach",
				})

		"large_bridge_emergency":
			steps = [
				{"title": "استلم إشارة الطوارئ من قسم الشرطة المركزي", "short_label": "قسم الشرطة", "position": Vector3(296.0, 0.0, 145.0), "radius": 8.0, "mode": "reach"},
				{"title": "أمّن موقع الحادث في منتصف جسر النيل الكبير", "short_label": "تأمين الجسر", "position": Vector3(-190.0, 6.2, 0.0), "radius": 9.0, "mode": "hold", "hold_seconds": 2.0},
				{"title": "أخمد الحريق على مطلع الجسر الشرقي", "short_label": "إطفاء الخطر", "position": Vector3(-120.0, 3.1, 0.0), "radius": 8.5, "mode": "hold", "hold_seconds": 2.5},
				{"title": "أوصل حقيبة الإسعافات العاجلة إلى المركز الصحي الرئيسي", "short_label": "المركز الصحي", "position": Vector3(298.0, 0.0, 78.0), "radius": 8.5, "mode": "reach"},
			]

		"large_mosques_supply":
			steps = [
				{"title": "حمّل مستلزمات الإنارة والصيانة من السوق التجاري", "short_label": "مستودع الإمداد", "position": Vector3(285.0, 0.0, -165.0), "radius": 8.0, "mode": "reach"},
				{"title": "سلّم حزمة المسجد الأول: مسجد الأزهري", "short_label": "مسجد الأزهري", "position": Vector3(-28.0, 0.0, -12.0), "radius": 8.5, "mode": "reach"},
				{"title": "سلّم حزمة المسجد الثاني: مسجد النيل الكبير", "short_label": "مسجد النيل الكبير", "position": Vector3(-92.0, 0.0, -285.0), "radius": 9.5, "mode": "reach"},
				{"title": "سلّم حزمة المسجد الثالث: مسجد النور", "short_label": "مسجد النور", "position": Vector3(145.0, 0.0, -256.0), "radius": 9.0, "mode": "reach"},
				{"title": "اعبر النيل وسلّم حزمة المسجد الرابع: مسجد التراث الغربي", "short_label": "مسجد التراث الغربي", "position": Vector3(-326.0, 0.0, -90.0), "radius": 9.5, "mode": "reach"},
			]

	return steps


func _pick_nearest_point(points: Array[Dictionary]) -> Dictionary:
	var p := _get_local_player()
	if not p or points.is_empty():
		return points[0]
	var best: Dictionary = points[0]
	var best_d: float = p.global_position.distance_squared_to(best["pos"])
	for item in points:
		var d: float = p.global_position.distance_squared_to(item["pos"])
		if d < best_d:
			best_d = d
			best = item
	return best


func _process(delta: float) -> void:
	_ensure_world_nodes()
	_animate_beacon(delta)
	_update_car_wash_vfx(delta)

	_giver_scan_timer -= delta
	if _giver_scan_timer <= 0.0:
		_giver_scan_timer = 0.25
		_scan_nearby_role_npc()

	if not is_mission_active():
		return

	mission_elapsed += delta
	if mission_time_left > 0.0:
		mission_time_left = maxf(0.0, mission_time_left - delta)
		if mission_time_left <= 0.0:
			_fail_mission("انتهى الوقت المحدد للمهمة!")
			return

	_track_cargo_damage_if_convoy()
	_process_active_step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if is_mission_active():
			var step := active_steps[active_step_index]
			var mode: String = str(step.get("mode", "reach"))
			if mode == "daffori":
				_try_kick_mission_ball(18.0)
				return
		if not _nearby_giver.is_empty() and not is_mission_active():
			var p := _get_local_player()
			if p and _get_player_vehicle(p) == null:
				if accept_nearby_giver_mission():
					get_viewport().set_input_as_handled()


func _process_active_step(delta: float) -> void:
	var p := _get_local_player()
	if not p:
		return

	var step := active_steps[active_step_index]
	var target: Vector3 = step.get("position", Vector3.ZERO)
	var radius: float = float(step.get("radius", 7.0))
	var mode: String = str(step.get("mode", "reach"))
	var dist := p.global_position.distance_to(target)

	match mode:
		"reach":
			if dist <= radius:
				_advance_step()
		"hold":
			if dist <= radius:
				_hold_progress += delta
				if _hold_progress >= float(step.get("hold_seconds", 2.0)):
					_hold_progress = 0.0
					_advance_step()
			else:
				_hold_progress = maxf(0.0, _hold_progress - delta * 0.5)
		"car_wash":
			if dist <= radius:
				_car_wash_timer = 2.0
				_hold_progress += delta
				if _hold_progress >= float(step.get("hold_seconds", 2.5)):
					_hold_progress = 0.0
					var veh := _get_player_vehicle(p)
					if veh and "fuel_liters" in veh and "max_fuel_liters" in veh:
						veh.fuel_liters = veh.max_fuel_liters
					hud_banner_requested.emit("تم غسيل وتلميع المركبة وتعبئة الوقود 100%!", Color(0.32, 0.90, 1.0))
					_advance_step()
			else:
				_hold_progress = maxf(0.0, _hold_progress - delta * 0.5)
		"ferry_board":
			if dist <= radius:
				_start_nile_ferry_ride(p)
				_advance_step()
		"ferry_sail":
			_process_nile_ferry_sail(p, target, radius, delta)
		"daffori":
			_process_daffori_ball(p, delta)


func _advance_step() -> void:
	_play_chime(1.18)
	active_step_index += 1
	if active_step_index >= active_steps.size():
		_complete_mission()
		return
	_update_beacon_for_current_step()
	var step := active_steps[active_step_index]
	mission_step_updated.emit(active_mission, active_step_index, step)
	hud_banner_requested.emit("الخطوة %d/%d: %s" % [active_step_index + 1, active_steps.size(), str(step["title"])], active_mission.get("color", Color.GOLD))


func _complete_mission() -> void:
	var m := active_mission.duplicate(true)
	var m_id: String = str(m.get("id", ""))
	var base_sdg: int = int(m.get("reward_sdg", 2000))
	var base_xp: int = int(m.get("reward_xp", 100))

	if m_id == "large_cargo_convoy" and cargo_integrity >= 85.0:
		base_sdg += 2500

	sdg_cash += base_sdg
	xp += base_xp
	level = 1 + int(xp / 500)
	completed_counts[m_id] = int(completed_counts.get(m_id, 0)) + 1

	var summary := "مبروك! اكتملت «%s» (+%d SDG | +%d XP)" % [str(m["title"]), base_sdg, base_xp]
	if m_id == "large_khartoum_rally":
		summary += " | الزمن: %.1f ث" % mission_elapsed
		if _is_online_multiplayer():
			_rpc_announce_rally.rpc("أنهى لاعب رالي الخرطوم الكبرى في %.1f ثانية!" % mission_elapsed)

	_cleanup_mission_runtime()
	active_mission = {}
	active_steps.clear()
	active_step_index = -1

	_play_chime(1.35)
	stats_changed.emit(sdg_cash, xp, level)
	mission_completed.emit(m, base_sdg, base_xp, summary)
	hud_banner_requested.emit(summary, Color(0.32, 0.96, 0.52))


func _fail_mission(reason: String) -> void:
	var m := active_mission.duplicate(true)
	_cleanup_mission_runtime()
	active_mission = {}
	active_steps.clear()
	active_step_index = -1
	_play_chime(0.68)
	mission_failed.emit(m, reason)
	hud_banner_requested.emit("فشلت المهمة: %s" % reason, Color(0.98, 0.30, 0.26))


func _track_cargo_damage_if_convoy() -> void:
	if str(active_mission.get("id", "")) != "large_cargo_convoy":
		return
	var p := _get_local_player()
	if not p:
		return
	var veh := _get_player_vehicle(p)
	if not veh:
		return
	var spd: float = veh.velocity.length() if "velocity" in veh else 0.0
	if _last_vehicle_speed > 8.5 and (_last_vehicle_speed - spd) > 6.5:
		cargo_integrity = maxf(0.0, cargo_integrity - 12.0)
		hud_banner_requested.emit("انتبه! اصطدام الشاحنة — سلامة الشحنة: %d%%" % int(cargo_integrity), Color(1.0, 0.55, 0.20))
		if cargo_integrity <= 10.0:
			_fail_mission("تضررت شحنة القافلة بالكامل!")
			return
	_last_vehicle_speed = spd


func _setup_special_mission_props(mission_id: String) -> void:
	_ensure_world_nodes()
	if not _mission_props_root:
		return
	for c in _mission_props_root.get_children():
		c.queue_free()

	if mission_id == "small_bridge_patrol" or mission_id == "large_bridge_emergency":
		# Place glowing roadside hazard cones & fire/flare beacon on bridge
		var hazard_pos: Vector3 = active_steps[0]["position"] if mission_id == "small_bridge_patrol" else Vector3(-120.0, 3.1, 0.0)
		_spawn_hazard_scene(hazard_pos)
	elif mission_id == "small_daffori_hattrick":
		_spawn_daffori_pitch_props()
	elif mission_id == "large_cargo_convoy":
		_spawn_convoy_daffar_if_needed()


func _spawn_hazard_scene(pos: Vector3) -> void:
	var h_root := Node3D.new()
	h_root.name = "MissionHazard"
	h_root.position = pos
	_mission_props_root.add_child(h_root)

	var mat_fire := StandardMaterial3D.new()
	mat_fire.albedo_color = Color(1.0, 0.42, 0.10, 0.9)
	mat_fire.emission_enabled = true
	mat_fire.emission = Color(1.0, 0.36, 0.06)
	mat_fire.emission_energy_multiplier = 2.6

	var mat_cone := StandardMaterial3D.new()
	mat_cone.albedo_color = Color(0.98, 0.44, 0.08, 1.0)
	mat_cone.roughness = 0.6

	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.95
	fm.height = 1.8
	fm.material = mat_fire
	flame.mesh = fm
	flame.position = Vector3(0.0, 0.9, 0.0)
	h_root.add_child(flame)

	for offset in [Vector3(-2.4, 0.35, -2.0), Vector3(2.4, 0.35, -2.0), Vector3(-2.4, 0.35, 2.0), Vector3(2.4, 0.35, 2.0)]:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.28
		cm.height = 0.7
		cm.material = mat_cone
		cone.mesh = cm
		cone.position = offset
		h_root.add_child(cone)


func _spawn_daffori_pitch_props() -> void:
	var g_root := Node3D.new()
	g_root.name = "DafforiGoalSetup"
	_mission_props_root.add_child(g_root)

	var mat_post := StandardMaterial3D.new()
	mat_post.albedo_color = Color(0.98, 0.98, 0.98)
	mat_post.emission_enabled = true
	mat_post.emission = Color(0.3, 0.95, 0.45)
	mat_post.emission_energy_multiplier = 0.6

	# Goal posts at x = 103.5, z in [30.5..37.5]
	for pz in [30.5, 37.5]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.1
		pm.bottom_radius = 0.1
		pm.height = 2.6
		pm.material = mat_post
		post.mesh = pm
		post.position = Vector3(103.5, 1.3, pz)
		g_root.add_child(post)
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.22, 7.2)
	bm.material = mat_post
	bar.mesh = bm
	bar.position = Vector3(103.5, 2.6, 34.0)
	g_root.add_child(bar)

	# Kickable glowing football at penalty spot (92.0, 0.28, 34.0)
	_mission_ball = Node3D.new()
	_mission_ball.name = "MissionFootball"
	_mission_ball.position = Vector3(92.0, 0.28, 34.0)
	g_root.add_child(_mission_ball)
	var ball_mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	var mat_ball := StandardMaterial3D.new()
	mat_ball.albedo_color = Color(1.0, 0.98, 0.90)
	mat_ball.emission_enabled = true
	mat_ball.emission = Color(0.95, 0.85, 0.25)
	mat_ball.emission_energy_multiplier = 0.55
	sm.material = mat_ball
	ball_mi.mesh = sm
	_mission_ball.add_child(ball_mi)
	_ball_vel = Vector3.ZERO


func _try_kick_mission_ball(power: float) -> void:
	if not _mission_ball or not is_instance_valid(_mission_ball):
		return
	var p := _get_local_player()
	if not p:
		return
	if p.global_position.distance_to(_mission_ball.global_position) > 3.6:
		return
	var to_goal := Vector3(104.0, 0.28, 34.0) - _mission_ball.global_position
	to_goal.y = 0.0
	var dir := to_goal.normalized() if to_goal.length() > 0.2 else Vector3.RIGHT
	_ball_vel = dir * power
	_play_chime(1.1)


func _process_daffori_ball(p: Node3D, delta: float) -> void:
	if not _mission_ball or not is_instance_valid(_mission_ball):
		return
	# Dribble kick when player touches ball
	var d_ball := p.global_position.distance_to(_mission_ball.global_position)
	if d_ball < 1.35:
		var push_dir := _mission_ball.global_position - p.global_position
		push_dir.y = 0.0
		if push_dir.length() < 0.05:
			push_dir = Vector3.RIGHT
		_ball_vel = push_dir.normalized() * 13.5

	if _ball_vel.length() > 0.08:
		_mission_ball.position += _ball_vel * delta
		_ball_vel = _ball_vel.lerp(Vector3.ZERO, clampf(delta * 2.2, 0.0, 1.0))

	# Goal scored detection (x >= 102.5 and z in [30.2..37.8])
	var bp := _mission_ball.position
	if bp.x >= 102.5 and bp.z >= 30.2 and bp.z <= 37.8:
		daffori_goals += 1
		_play_chime(1.25 + float(daffori_goals) * 0.08)
		hud_banner_requested.emit("هدف دافوري! (%d / 3)" % daffori_goals, Color(0.45, 0.98, 0.42))
		_mission_ball.position = Vector3(92.0, 0.28, 34.0 + _rng.randf_range(-2.2, 2.2))
		_ball_vel = Vector3.ZERO
		if daffori_goals >= 3:
			_advance_step()
	elif bp.distance_to(Vector3(92.0, 0.28, 34.0)) > 26.0:
		# Reset out-of-bounds ball cleanly to penalty spot
		_mission_ball.position = Vector3(92.0, 0.28, 34.0)
		_ball_vel = Vector3.ZERO


func _start_nile_ferry_ride(p: Node3D) -> void:
	_ferry_boarding_active = true
	if _ferry_boat and is_instance_valid(_ferry_boat):
		_ferry_boat.queue_free()

	_ferry_boat = Node3D.new()
	_ferry_boat.name = "MissionNileFerry"
	_ferry_boat.position = Vector3(-150.0, 0.35, -90.0)
	_mission_props_root.add_child(_ferry_boat)

	var mat_hull := StandardMaterial3D.new()
	mat_hull.albedo_color = Color(0.18, 0.46, 0.78)
	var mat_deck := StandardMaterial3D.new()
	mat_deck.albedo_color = Color(0.86, 0.72, 0.48)
	var mat_roof := StandardMaterial3D.new()
	mat_roof.albedo_color = Color(0.98, 0.96, 0.90)

	var hull := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(3.2, 0.85, 7.6)
	hm.material = mat_hull
	hull.mesh = hm
	_ferry_boat.add_child(hull)

	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(2.8, 0.2, 6.8)
	dm.material = mat_deck
	deck.mesh = dm
	deck.position = Vector3(0.0, 0.45, 0.0)
	_ferry_boat.add_child(deck)

	var canopy := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(2.6, 0.18, 4.2)
	cm.material = mat_roof
	canopy.mesh = cm
	canopy.position = Vector3(0.0, 2.25, -0.4)
	_ferry_boat.add_child(canopy)

	p.global_position = _ferry_boat.global_position + Vector3(0.0, 0.85, 0.0)
	hud_banner_requested.emit("انطلقت عبّارة النيل! اضغط [W] للقيادة نحو المرسى المقابل", Color(0.28, 0.84, 1.0))


func _process_nile_ferry_sail(p: Node3D, target: Vector3, radius: float, delta: float) -> void:
	if not _ferry_boat or not is_instance_valid(_ferry_boat):
		_start_nile_ferry_ride(p)
		return
	var to_t := target - _ferry_boat.global_position
	to_t.y = 0.0
	var dist := to_t.length()
	var move_speed := 15.0 if Input.is_action_pressed("move_forward") else 9.0
	if dist > 0.5:
		var dir := to_t.normalized()
		_ferry_boat.global_position += dir * move_speed * delta
		_ferry_boat.rotation.y = atan2(dir.x, dir.z)
	p.global_position = _ferry_boat.global_position + Vector3(0.0, 0.85, 0.0)
	if "velocity" in p:
		p.velocity = Vector3.ZERO
	if dist <= radius:
		if active_step_index == active_steps.size() - 1:
			# Disembark cleanly onto East Marina pier
			p.global_position = Vector3(-140.0, 0.6, -90.0)
		_advance_step()


func _spawn_convoy_daffar_if_needed() -> void:
	var p := _get_local_player()
	if p:
		var cur_v := _get_player_vehicle(p)
		if cur_v and "daffar" in cur_v.name.to_lower():
			return
	var main_root := _get_main_scene_root()
	if not main_root:
		return
	var packed: PackedScene = DAFFAR_SCENE
	if not packed:
		return
	var truck := packed.instantiate() as Node3D
	if not truck:
		return
	truck.name = "MissionConvoyDaffar"
	truck.position = Vector3(32.0, 0.0, -5.0)
	var veh_parent := main_root.get_node_or_null("Vehicles")
	if veh_parent:
		veh_parent.add_child(truck)
	else:
		main_root.add_child(truck)
	_spawned_convoy_truck = truck


func _scan_nearby_role_npc() -> void:
	var p := _get_local_player()
	if not p or _get_player_vehicle(p) != null:
		_set_nearby_giver({})
		return
	var spawners := get_tree().get_nodes_in_group("role_npc_spawner")
	if spawners.is_empty() or not spawners[0].has_method("get_role_npcs"):
		_set_nearby_giver({})
		return

	var best_npc: Node3D = null
	var best_dist: float = 4.6
	var r_npcs: Array = spawners[0].get_role_npcs()
	for npc_node in r_npcs:
		var n3 := npc_node as Node3D
		if not n3 or not is_instance_valid(n3):
			continue
		var d := p.global_position.distance_to(n3.global_position)
		if d < best_dist:
			best_dist = d
			best_npc = n3

	if not best_npc:
		_set_nearby_giver({})
		return

	var role: String = str(best_npc.get_meta("npc_role", "vendor"))
	var mission := _pick_mission_for_role(role)
	if mission.is_empty():
		_set_nearby_giver({})
		return

	_set_nearby_giver({
		"npc_name": str(best_npc.get("npc_name")) if "npc_name" in best_npc else role,
		"role": role,
		"mission_id": str(mission["id"]),
		"mission_title": str(mission["title"]),
		"reward_sdg": int(mission["reward_sdg"]),
	})


func _pick_mission_for_role(role: String) -> Dictionary:
	# Match role directly to primary signature mission
	var role_map: Dictionary = {
		"engineer": "large_engineer_inspection",
		"doctor": "small_pharmacy_delivery",
		"pharmacist": "small_pharmacy_delivery",
		"police": "small_bridge_patrol",
		"firefighter": "large_bridge_emergency",
		"baker": "small_bread_delivery",
		"dock_master": "small_nile_ferry",
		"barber": "small_daffori_hattrick",
		"vendor": "small_taxi_dropoff",
	}
	var target_id: String = str(role_map.get(role, "small_taxi_dropoff"))
	return find_mission_by_id(target_id)


func _set_nearby_giver(info: Dictionary) -> void:
	if str(_nearby_giver.get("mission_id", "")) == str(info.get("mission_id", "")) and str(_nearby_giver.get("npc_name", "")) == str(info.get("npc_name", "")):
		return
	_nearby_giver = info
	nearby_giver_changed.emit(_nearby_giver)


func _ensure_world_nodes() -> void:
	var main_root := _get_main_scene_root()
	if not main_root:
		return
	if _world_container and is_instance_valid(_world_container):
		return

	_world_container = Node3D.new()
	_world_container.name = "MissionWorldSystem"
	main_root.add_child(_world_container)

	_mission_props_root = Node3D.new()
	_mission_props_root.name = "ActiveMissionProps"
	_world_container.add_child(_mission_props_root)

	_build_car_wash_bay()
	_build_mission_beacon()


func _build_car_wash_bay() -> void:
	# Always-present Khartoum Car Wash Bay at verified open roadside lot (188.0, 0.0, -28.0)
	_car_wash_root = Node3D.new()
	_car_wash_root.name = "KhartoumCarWashBay"
	_car_wash_root.position = Vector3(188.0, 0.0, -28.0)
	_world_container.add_child(_car_wash_root)

	var mat_frame := StandardMaterial3D.new()
	mat_frame.albedo_color = Color(0.14, 0.56, 0.88)
	mat_frame.roughness = 0.45
	var mat_white := StandardMaterial3D.new()
	mat_white.albedo_color = Color(0.96, 0.98, 1.0)
	mat_white.roughness = 0.7
	var mat_mist := StandardMaterial3D.new()
	mat_mist.albedo_color = Color(0.45, 0.88, 1.0, 0.42)
	mat_mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_mist.emission_enabled = true
	mat_mist.emission = Color(0.35, 0.82, 1.0)

	# Concrete wash pad
	var pad := MeshInstance3D.new()
	var pbm := BoxMesh.new()
	pbm.size = Vector3(8.5, 0.08, 12.0)
	pbm.material = mat_white
	pad.mesh = pbm
	pad.position = Vector3(0.0, 0.04, 0.0)
	pad.visibility_range_end = 360.0
	_car_wash_root.add_child(pad)

	# Overhead blue spray gantry arch
	for sx in [-3.4, 3.4]:
		var sb := StaticBody3D.new()
		sb.position = Vector3(sx, 2.3, 0.0)
		_car_wash_root.add_child(sb)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 4.6, 1.2)
		bm.material = mat_frame
		mi.mesh = bm
		mi.visibility_range_end = 360.0
		sb.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.6, 4.6, 1.2)
		cs.shape = bs
		sb.add_child(cs)

	var top_beam := MeshInstance3D.new()
	var tbm := BoxMesh.new()
	tbm.size = Vector3(7.6, 0.85, 1.4)
	tbm.material = mat_frame
	top_beam.mesh = tbm
	top_beam.position = Vector3(0.0, 4.6, 0.0)
	top_beam.visibility_range_end = 360.0
	_car_wash_root.add_child(top_beam)

	_car_wash_mist = MeshInstance3D.new()
	var mbm := BoxMesh.new()
	mbm.size = Vector3(5.8, 3.8, 0.6)
	mbm.material = mat_mist
	_car_wash_mist.mesh = mbm
	_car_wash_mist.position = Vector3(0.0, 2.1, 0.0)
	_car_wash_mist.visible = false
	_car_wash_root.add_child(_car_wash_mist)

	var lbl := Label3D.new()
	lbl.text = "مغسلة الخرطوم الآلية\nCar Wash Bay"
	lbl.position = Vector3(0.0, 5.65, 0.0)
	lbl.font_size = 34
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.76, 0.96, 1.0)
	lbl.outline_size = 6
	lbl.visibility_range_end = 70.0
	_car_wash_root.add_child(lbl)


func _build_mission_beacon() -> void:
	_beacon_root = Node3D.new()
	_beacon_root.name = "MissionBeacon"
	_beacon_root.visible = false
	_world_container.add_child(_beacon_root)

	var mat_pillar := StandardMaterial3D.new()
	mat_pillar.albedo_color = Color(1.0, 0.85, 0.22, 0.26)
	mat_pillar.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_pillar.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_pillar.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mat_ring := StandardMaterial3D.new()
	mat_ring.albedo_color = Color(1.0, 0.86, 0.24, 0.85)
	mat_ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_beacon_pillar = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 1.8
	pm.bottom_radius = 2.6
	pm.height = 80.0
	pm.radial_segments = 20
	pm.material = mat_pillar
	_beacon_pillar.mesh = pm
	_beacon_pillar.position = Vector3(0.0, 40.0, 0.0)
	_beacon_root.add_child(_beacon_pillar)

	_beacon_ring = MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 2.4
	rm.outer_radius = 3.2
	rm.material = mat_ring
	_beacon_ring.mesh = rm
	_beacon_ring.position = Vector3(0.0, 0.35, 0.0)
	_beacon_root.add_child(_beacon_ring)

	_beacon_diamond = MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(1.1, 1.1, 1.1)
	dm.material = mat_ring
	_beacon_diamond.mesh = dm
	_beacon_diamond.position = Vector3(0.0, 4.2, 0.0)
	_beacon_diamond.rotation = Vector3(PI * 0.25, 0.0, PI * 0.25)
	_beacon_root.add_child(_beacon_diamond)

	_beacon_label = Label3D.new()
	_beacon_label.position = Vector3(0.0, 6.0, 0.0)
	_beacon_label.font_size = 38
	_beacon_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_beacon_label.outline_size = 8
	_beacon_label.modulate = Color(1.0, 0.94, 0.65)
	_beacon_root.add_child(_beacon_label)


func _update_beacon_for_current_step() -> void:
	_ensure_world_nodes()
	if not _beacon_root or not is_mission_active():
		if _beacon_root:
			_beacon_root.visible = false
		return

	var step := active_steps[active_step_index]
	var pos: Vector3 = step.get("position", Vector3.ZERO)
	var accent: Color = active_mission.get("color", Color(1.0, 0.84, 0.22))
	_beacon_root.position = pos
	_beacon_root.visible = true

	var p_mat := _beacon_pillar.mesh.surface_get_material(0) as StandardMaterial3D
	if p_mat:
		p_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.26)
	var r_mat := _beacon_ring.mesh.surface_get_material(0) as StandardMaterial3D
	if r_mat:
		r_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.88)
	_beacon_label.text = str(step.get("short_label", "هدف المهمة"))
	_beacon_label.modulate = accent.lightened(0.35)


func _animate_beacon(delta: float) -> void:
	if not _beacon_root or not _beacon_root.visible:
		return
	_beacon_pulse_t += delta
	var s := 1.0 + 0.14 * sin(_beacon_pulse_t * 3.8)
	_beacon_ring.scale = Vector3(s, 1.0, s)
	_beacon_diamond.rotation.y += delta * 2.2
	_beacon_diamond.position.y = 4.2 + 0.45 * sin(_beacon_pulse_t * 2.8)


func _update_car_wash_vfx(delta: float) -> void:
	if not _car_wash_mist or not is_instance_valid(_car_wash_mist):
		return
	if _car_wash_timer > 0.0:
		_car_wash_timer = maxf(0.0, _car_wash_timer - delta)
		_car_wash_mist.visible = true
	else:
		_car_wash_mist.visible = false


func _cleanup_mission_runtime() -> void:
	if _beacon_root and is_instance_valid(_beacon_root):
		_beacon_root.visible = false
	if _mission_props_root and is_instance_valid(_mission_props_root):
		for c in _mission_props_root.get_children():
			c.queue_free()
	_mission_ball = null
	_ferry_boat = null
	_ferry_boarding_active = false
	if _spawned_convoy_truck and is_instance_valid(_spawned_convoy_truck):
		var p := _get_local_player()
		if not p or _get_player_vehicle(p) != _spawned_convoy_truck:
			_spawned_convoy_truck.queue_free()
	_spawned_convoy_truck = null


func _play_chime(pitch: float) -> void:
	if not _sfx_player:
		return
	var am := get_node_or_null("/root/AudioManager")
	if am and "interact_chime_stream" in am and am.interact_chime_stream != null:
		_sfx_player.stream = am.interact_chime_stream
		_sfx_player.pitch_scale = pitch
		_sfx_player.volume_db = -6.0
		_sfx_player.play()


func _get_local_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("local_player")
	if players.is_empty():
		return null
	return players[0] as Node3D


func _get_player_vehicle(player: Node3D) -> Node3D:
	if player and player.has_method("get_current_vehicle"):
		return player.get_current_vehicle() as Node3D
	return null


func _get_main_scene_root() -> Node3D:
	var scene := get_tree().current_scene
	if scene is Node3D:
		return scene as Node3D
	for c in get_tree().root.get_children():
		if c is Node3D and c.name == "Main":
			return c as Node3D
	return null


func _is_online_multiplayer() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0


@rpc("any_peer", "call_local", "reliable")
func _rpc_announce_rally(message: String) -> void:
	hud_banner_requested.emit(message, Color(1.0, 0.42, 0.48))
