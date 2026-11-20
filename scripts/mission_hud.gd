extends CanvasLayer
class_name MissionHUD

## Arabic-labeled Interactive Mission Board (`[M]`), Active Objective Banner,
## Live Distance/Progress/Timer readout, NPC Giver `[E]` prompt, and Reward Toast.

@onready var wallet_label: Label = $Root/WalletPanel/Margin/HBox/WalletLabel
@onready var open_board_btn: Button = $Root/WalletPanel/Margin/HBox/OpenBoardButton

@onready var objective_panel: PanelContainer = $Root/ObjectivePanel
@onready var obj_title_label: Label = $Root/ObjectivePanel/Margin/VBox/HeaderRow/ObjTitle
@onready var obj_step_label: Label = $Root/ObjectivePanel/Margin/VBox/HeaderRow/ObjStep
@onready var obj_desc_label: Label = $Root/ObjectivePanel/Margin/VBox/ObjDesc
@onready var obj_meta_label: Label = $Root/ObjectivePanel/Margin/VBox/FooterRow/ObjMeta
@onready var obj_cancel_btn: Button = $Root/ObjectivePanel/Margin/VBox/FooterRow/CancelBtn

@onready var giver_panel: PanelContainer = $Root/GiverPromptPanel
@onready var giver_label: Label = $Root/GiverPromptPanel/Margin/GiverLabel

@onready var toast_panel: PanelContainer = $Root/ToastPanel
@onready var toast_label: Label = $Root/ToastPanel/Margin/ToastLabel

@onready var board_overlay: Control = $Root/MissionBoardOverlay
@onready var board_wallet_label: Label = $Root/MissionBoardOverlay/BoardPanel/Margin/VBox/TopRow/BoardWallet
@onready var board_close_btn: Button = $Root/MissionBoardOverlay/BoardPanel/Margin/VBox/TopRow/CloseBtn
@onready var small_list: VBoxContainer = $Root/MissionBoardOverlay/BoardPanel/Margin/VBox/Columns/SmallCol/SmallScroll/SmallList
@onready var large_list: VBoxContainer = $Root/MissionBoardOverlay/BoardPanel/Margin/VBox/Columns/LargeCol/LargeScroll/LargeList

var _toast_timer: float = 0.0
var _refresh_timer: float = 0.0
var _mm: Node = null


func _ready() -> void:
	_mm = get_node_or_null("/root/MissionManager")
	objective_panel.visible = false
	giver_panel.visible = false
	toast_panel.visible = false
	board_overlay.visible = false

	open_board_btn.pressed.connect(toggle_board)
	board_close_btn.pressed.connect(close_board)
	obj_cancel_btn.pressed.connect(_on_cancel_pressed)

	if _mm:
		_mm.mission_started.connect(_on_mission_changed)
		_mm.mission_step_updated.connect(_on_step_updated)
		_mm.mission_completed.connect(_on_mission_completed)
		_mm.mission_failed.connect(_on_mission_failed)
		_mm.mission_cancelled.connect(_on_mission_cancelled)
		_mm.stats_changed.connect(_on_stats_changed)
		_mm.nearby_giver_changed.connect(_on_nearby_giver_changed)
		_mm.hud_banner_requested.connect(show_toast)
		_update_wallet_display()
		_rebuild_mission_board()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	if ke.keycode == KEY_M:
		toggle_board()
		get_viewport().set_input_as_handled()
	elif ke.keycode == KEY_ESCAPE and board_overlay.visible:
		close_board()
		get_viewport().set_input_as_handled()


func toggle_board() -> void:
	if board_overlay.visible:
		close_board()
	else:
		open_board()


func open_board() -> void:
	_rebuild_mission_board()
	board_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_board() -> void:
	board_overlay.visible = false
	if not get_tree().get_nodes_in_group("local_player").is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			toast_panel.visible = false

	if not _mm:
		return

	_refresh_timer += delta
	if _refresh_timer >= 0.12:
		_refresh_timer = 0.0
		_update_active_objective_panel()


func _update_wallet_display() -> void:
	if not _mm:
		return
	var txt := "💰 %d SDG   |   ⭐ Lv.%d (%d XP)" % [int(_mm.sdg_cash), int(_mm.level), int(_mm.xp)]
	wallet_label.text = txt
	board_wallet_label.text = txt


func _update_active_objective_panel() -> void:
	if not _mm or not _mm.is_mission_active():
		objective_panel.visible = false
		return

	objective_panel.visible = true
	var m: Dictionary = _mm.active_mission
	var step: Dictionary = _mm.get_current_step()
	var step_idx: int = int(_mm.active_step_index)
	var total_steps: int = (_mm.active_steps as Array).size()
	var dist_m: float = float(_mm.get_distance_to_waypoint())
	var t_left: float = float(_mm.mission_time_left)
	var mins := int(t_left) / 60
	var secs := int(t_left) % 60

	obj_title_label.text = "🎯 " + str(m.get("title", "مهمة نشطة"))
	obj_step_label.text = "الخطوة %d / %d" % [step_idx + 1, total_steps]
	obj_desc_label.text = str(step.get("title", ""))

	var extra := ""
	var m_id: String = str(m.get("id", ""))
	if m_id == "large_cargo_convoy":
		extra = "   |   سلامة الشحنة: %d%%" % int(_mm.cargo_integrity)
	elif m_id == "small_daffori_hattrick":
		extra = "   |   الأهداف: %d / 3" % int(_mm.daffori_goals)
	elif m_id == "large_khartoum_rally":
		extra = "   |   الزمن: %.1f ث" % float(_mm.mission_elapsed)

	obj_meta_label.text = "المسافة: %d م   |   الوقت المتبقي: %02d:%02d%s" % [roundi(dist_m), mins, secs, extra]


func _rebuild_mission_board() -> void:
	if not _mm:
		return
	_update_wallet_display()

	for c in small_list.get_children():
		c.queue_free()
	for c in large_list.get_children():
		c.queue_free()

	var active_id := str(_mm.active_mission.get("id", "")) if _mm.is_mission_active() else ""

	for m in _mm.get_small_missions():
		small_list.add_child(_create_mission_card(m, active_id))
	for m in _mm.get_large_missions():
		large_list.add_child(_create_mission_card(m, active_id))


func _create_mission_card(m: Dictionary, active_id: String) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var is_current := (str(m["id"]) == active_id)
	style.bg_color = Color(0.20, 0.16, 0.10, 0.94) if is_current else Color(0.12, 0.11, 0.10, 0.88)
	var accent: Color = m.get("color", Color(0.95, 0.72, 0.24))
	style.border_color = accent if is_current else Color(accent.r, accent.g, accent.b, 0.55)
	style.set_border_width_all(2 if is_current else 1)
	style.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var head := HBoxContainer.new()
	vbox.add_child(head)

	var title_lbl := Label.new()
	title_lbl.text = str(m["title"])
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", accent.lightened(0.25))
	head.add_child(title_lbl)

	var done_n := int(_mm.completed_counts.get(str(m["id"]), 0))
	var reward_lbl := Label.new()
	var done_tag := (" ✓×%d" % done_n) if done_n > 0 else ""
	reward_lbl.text = "+%d SDG | +%d XP%s" % [int(m["reward_sdg"]), int(m["reward_xp"]), done_tag]
	reward_lbl.add_theme_font_size_override("font_size", 12)
	reward_lbl.add_theme_color_override("font_color", Color(0.86, 0.96, 0.72))
	head.add_child(reward_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = str(m["description"])
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.90, 0.88, 0.84))
	vbox.add_child(desc_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	var sub_lbl := Label.new()
	sub_lbl.text = str(m.get("subtitle", ""))
	sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.68, 0.66, 0.62))
	btn_row.add_child(sub_lbl)

	var m_id := str(m["id"])
	var action_btn := Button.new()
	if is_current:
		action_btn.text = "إلغاء المهمة"
		action_btn.pressed.connect(func() -> void:
			_mm.cancel_mission()
			_rebuild_mission_board()
		)
	else:
		action_btn.text = "ابدأ المهمة"
		action_btn.pressed.connect(func() -> void:
			_mm.start_mission(m_id)
			close_board()
		)
	btn_row.add_child(action_btn)

	return card


func show_toast(text: String, accent: Color = Color(1.0, 0.88, 0.45)) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", accent.lightened(0.25))
	toast_panel.visible = true
	_toast_timer = 4.5


func _on_mission_changed(_m: Dictionary) -> void:
	_update_active_objective_panel()
	if board_overlay.visible:
		_rebuild_mission_board()


func _on_step_updated(_m: Dictionary, _idx: int, _step: Dictionary) -> void:
	_update_active_objective_panel()


func _on_mission_completed(_m: Dictionary, _sdg: int, _xp: int, _summary: String) -> void:
	_update_wallet_display()
	_update_active_objective_panel()
	if board_overlay.visible:
		_rebuild_mission_board()


func _on_mission_failed(_m: Dictionary, _reason: String) -> void:
	_update_active_objective_panel()
	if board_overlay.visible:
		_rebuild_mission_board()


func _on_mission_cancelled() -> void:
	_update_active_objective_panel()
	if board_overlay.visible:
		_rebuild_mission_board()


func _on_stats_changed(_sdg: int, _xp: int, _lvl: int) -> void:
	_update_wallet_display()


func _on_nearby_giver_changed(info: Dictionary) -> void:
	if info.is_empty() or (_mm and _mm.is_mission_active()):
		giver_panel.visible = false
		return
	giver_label.text = "[E] %s — قبول مهمة: %s (+%d SDG)" % [
		str(info.get("npc_name", "موظف")),
		str(info.get("mission_title", "")),
		int(info.get("reward_sdg", 0)),
	]
	giver_panel.visible = true


func _on_cancel_pressed() -> void:
	if _mm:
		_mm.cancel_mission()
