extends Node
class_name NetworkManager

## Dual-transport Multiplayer Manager:
## - WebSocketMultiplayerPeer (port 7778 / `/ws` proxy) for cross-platform PC + iPhone Safari Web players
## - ENetMultiplayerPeer (port 7777) auxiliary desktop listener

const DEFAULT_PORT: int = 7777
const WS_PORT: int = 7778
const DEFAULT_IP: String = "127.0.0.1"
const MAX_CLIENTS: int = 16
const SERVER_URL_CFG_PATH: String = "user://server_url.cfg"
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

const PLAYER_COLORS: Array[Color] = [
	Color(0.94, 0.92, 0.86, 1.0), # Classic White Jalabiya
	Color(0.24, 0.48, 0.72, 1.0), # Nile Blue
	Color(0.76, 0.48, 0.28, 1.0), # Desert Ochre
	Color(0.20, 0.50, 0.34, 1.0), # Sudan Green
	Color(0.68, 0.26, 0.24, 1.0), # Terracotta Maroon
	Color(0.54, 0.46, 0.34, 1.0), # Warm Sand
]

@onready var players_container: Node3D = $"../Players"
@onready var overview_camera: Camera3D = $"../OverviewCamera"

@onready var startup_overlay: Control = $"../NetworkHUD/StartupOverlay"
@onready var host_button: Button = $"../NetworkHUD/StartupOverlay/Card/Margin/VBox/HostButton"
@onready var ip_input: LineEdit = $"../NetworkHUD/StartupOverlay/Card/Margin/VBox/JoinRow/IpInput"
@onready var join_button: Button = $"../NetworkHUD/StartupOverlay/Card/Margin/VBox/JoinRow/JoinButton"
@onready var status_label: Label = $"../NetworkHUD/StartupOverlay/Card/Margin/VBox/StatusRow/StatusLabel"
@onready var player_count_label: Label = $"../NetworkHUD/StartupOverlay/Card/Margin/VBox/StatusRow/PlayerCountLabel"

@onready var top_bar: Control = $"../NetworkHUD/TopBar"
@onready var top_status_label: Label = $"../NetworkHUD/TopBar/Margin/HBox/TopStatusLabel"
@onready var top_count_label: Label = $"../NetworkHUD/TopBar/Margin/HBox/TopCountLabel"
@onready var time_button: Button = $"../NetworkHUD/TopBar/Margin/HBox/TimeButton"
@onready var mobile_toggle_button: Button = $"../NetworkHUD/TopBar/Margin/HBox/MobileToggleButton"
@onready var disconnect_button: Button = $"../NetworkHUD/TopBar/Margin/HBox/DisconnectButton"
@onready var minimap_panel: Control = $"../NetworkHUD/MinimapPanel"
@onready var toast_label: Label = $"../NetworkHUD/ToastLabel"
@onready var prompt_label: Label = $"../NetworkHUD/PromptLabel"
@onready var subtitle_panel: PanelContainer = $"../NetworkHUD/SubtitlePanel"
@onready var subtitle_label: Label = $"../NetworkHUD/SubtitlePanel/Margin/SubtitleLabel"

var _target_ip: String = DEFAULT_IP
var _target_endpoint: String = "%s:%d" % [DEFAULT_IP, WS_PORT]
var _spawn_index: int = 0
var _spawned_players: Dictionary = {}
var _mobile_ui_on: bool = false
var _toast_timer: float = 0.0
var _subtitle_timer: float = 0.0


func _ready() -> void:
	add_to_group("network_hud")

	ip_input.text = DEFAULT_IP
	_mobile_ui_on = OS.has_feature("web") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()
	sync_mobile_ui_button(_mobile_ui_on)
	mobile_toggle_button.focus_mode = Control.FOCUS_NONE
	disconnect_button.focus_mode = Control.FOCUS_NONE
	if time_button:
		time_button.focus_mode = Control.FOCUS_NONE
		time_button.pressed.connect(_on_time_button_pressed)

	join_button.text = "انضمام للمدينة (Join)"
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	mobile_toggle_button.pressed.connect(_on_mobile_toggle_pressed)

	players_container.child_entered_tree.connect(_on_players_changed)
	players_container.child_exiting_tree.connect(_on_players_changed)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	_set_connected_ui(false, "Offline")
	_refresh_player_count()

	if OS.has_feature("web"):
		host_button.visible = false
		_apply_safari_web_graphics_profile()
		call_deferred("_apply_safari_web_graphics_profile")
		var ws_url := str(Engine.get_meta("web_auto_join_url", ""))
		if ws_url.is_empty():
			ws_url = _detect_web_ws_url()
		ip_input.text = ws_url
		call_deferred("_on_join_pressed")
	elif OS.has_feature("ios"):
		host_button.visible = false
		var ws_url := str(Engine.get_meta("ios_auto_join_url", Engine.get_meta("web_auto_join_url", "")))
		if ws_url.is_empty():
			ws_url = load_server_url()
		ws_url = normalize_ws_url(ws_url, true)
		ip_input.text = ws_url
		if not ws_url.is_empty():
			call_deferred("_on_join_pressed")
		else:
			_set_status("الصق رابط الخادم (https://....trycloudflare.com) ثم اضغط انضمام")
	else:
		call_deferred("_handle_cli_multiplayer_args")


func _handle_cli_multiplayer_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--auto-host":
			_on_host_pressed()
		elif arg.begins_with("--auto-host="):
			_start_host_on_port(int(arg.substr(12)))
		elif arg.begins_with("--auto-join="):
			ip_input.text = arg.substr(12)
			_on_join_pressed()
		elif arg.begins_with("--verify-exit="):
			var wait_sec := clampf(float(arg.substr(14)), 2.0, 30.0)
			_run_cli_verify_timer(wait_sec)


func _run_cli_verify_timer(wait_sec: float) -> void:
	var elapsed := 0.0
	var printed := false
	while elapsed < wait_sec:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
		if not printed and players_container.get_child_count() >= 3:
			var names: Array[String] = []
			for ch in players_container.get_children():
				if not ch.is_queued_for_deletion():
					names.append(String(ch.name))
			names.sort()
			var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
			print("[VerifyMP] self_id=%d count=%d players=%s" % [my_id, names.size(), str(names)])
			printed = true
			if my_id != 1:
				await get_tree().create_timer(1.0).timeout
				get_tree().quit(0)
				return
			await get_tree().create_timer(3.0).timeout
			get_tree().quit(0)
			return
	var names: Array[String] = []
	for ch in players_container.get_children():
		if not ch.is_queued_for_deletion():
			names.append(String(ch.name))
	names.sort()
	var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	print("[VerifyMP] self_id=%d count=%d players=%s" % [my_id, names.size(), str(names)])
	get_tree().quit(0)


func _apply_safari_web_graphics_profile() -> void:
	if not OS.has_feature("web"):
		return
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = 0.60
	Engine.max_fps = 30
	var root_scene := get_parent()
	if root_scene == null:
		return
	var sun := root_scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = false
	_cap_web_node_visibility(root_scene, false, false)


func _cap_web_node_visibility(node: Node, in_building_subtree: bool = false, in_prop_subtree: bool = false) -> void:
	var nname := node.name
	var is_terrain_or_road := nname in ["MegaTerrain", "MegaRoads", "Ground", "Roads"]
	if is_terrain_or_road:
		return
	var next_bld := in_building_subtree or (nname in ["Buildings", "CityBuildings", "MegaLandmarks", "MegaInfrastructure"])
	var next_prop := in_prop_subtree or (nname in ["StreetProps", "OuterStreetLife", "AssetPackLoader", "RoleNPCSpawner", "WorldAmbiance"])
	if node is Light3D:
		(node as Light3D).shadow_enabled = false
	elif node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if next_prop:
			if gi.visibility_range_end <= 0.0 or gi.visibility_range_end > 65.0:
				gi.visibility_range_end = 65.0
		elif next_bld:
			if gi.visibility_range_end <= 0.0 or gi.visibility_range_end > 140.0:
				gi.visibility_range_end = 140.0
		elif gi.visibility_range_end >= 200.0:
			gi.visibility_range_end = 140.0
		elif gi.visibility_range_end > 65.0 and gi.visibility_range_end < 200.0:
			gi.visibility_range_end = 65.0
	for ch in node.get_children():
		_cap_web_node_visibility(ch, next_bld, next_prop)


func _detect_web_ws_url() -> String:
	if OS.has_feature("web"):
		var origin_val = JavaScriptBridge.eval("window.location.origin", true)
		var origin := str(origin_val).strip_edges()
		if origin.begins_with("https://"):
			return origin.replace("https://", "wss://") + "/ws"
		elif origin.begins_with("http://"):
			return origin.replace("http://", "ws://") + "/ws"
	return "ws://%s:%d" % [DEFAULT_IP, WS_PORT]


static func normalize_ws_url(raw_input: String, force_wss: bool = false) -> String:
	var s := raw_input.strip_edges()
	if s.is_empty():
		return ""

	var low := s.to_lower()
	var had_wss := low.begins_with("https://") or low.begins_with("wss://")
	var had_http := low.begins_with("http://")
	var had_ws := low.begins_with("ws://")

	for prefix in ["https://", "http://", "wss://", "ws://", "enet://"]:
		if s.to_lower().begins_with(prefix):
			s = s.substr(prefix.length())
			break

	s = s.strip_edges()
	if force_wss or had_wss or had_http:
		while s.ends_with("/"):
			s = s.left(s.length() - 1)
		if s.to_lower().ends_with("/ws"):
			s = s.left(s.length() - 3)
		while s.ends_with("/"):
			s = s.left(s.length() - 1)
		if s.is_empty():
			return ""
		var scheme := "ws" if (had_http and not force_wss) else "wss"
		return "%s://%s/ws" % [scheme, s]

	if had_ws or ":" in s or "/" in s:
		return "ws://%s" % s
	return "ws://%s:%d" % [s, WS_PORT]


static func save_server_url(raw_url: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("network", "server_url", raw_url.strip_edges())
	cfg.save(SERVER_URL_CFG_PATH)


static func load_server_url() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SERVER_URL_CFG_PATH) == OK:
		return str(cfg.get_value("network", "server_url", "")).strip_edges()
	return ""


func _apply_mobile_ui_to_local_player() -> void:
	if _mobile_ui_on:
		get_tree().call_group("local_player", "set_mobile_ui_enabled", true)
		sync_mobile_ui_button(true)


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and toast_label:
			toast_label.visible = false
	if _subtitle_timer > 0.0:
		_subtitle_timer -= delta
		if _subtitle_timer <= 0.0 and subtitle_panel:
			subtitle_panel.visible = false


func show_toast(message: String) -> void:
	if toast_label == null:
		return
	toast_label.text = message
	toast_label.visible = true
	_toast_timer = 2.6


func show_subtitle(message: String) -> void:
	if subtitle_panel == null or subtitle_label == null:
		return
	subtitle_label.text = message
	subtitle_panel.visible = true
	_subtitle_timer = 4.2


func set_context_prompt(text: String) -> void:
	if prompt_label == null:
		return
	prompt_label.text = text
	prompt_label.visible = not text.is_empty()


func sync_mobile_ui_button(active: bool) -> void:
	_mobile_ui_on = active
	if mobile_toggle_button:
		mobile_toggle_button.text = "Mobile UI: ON" if active else "Mobile UI: OFF"


func sync_time_button(label: String) -> void:
	if time_button:
		time_button.text = "Time: %s" % label


func _on_time_button_pressed() -> void:
	get_tree().call_group("time_controller", "cycle_time_of_day")


func _on_host_pressed() -> void:
	_start_host_on_port(WS_PORT)


func _start_host_on_port(port: int) -> void:
	_cleanup_peer()

	# Single cross-platform WebSocket server on port 7778 (shared by PC Host & all Web/Desktop clients)
	var ws_peer := WebSocketMultiplayerPeer.new()
	var ws_err := ws_peer.create_server(port)
	print("[WS] create_server(%d) -> err=%d" % [port, ws_err])
	if ws_err != OK:
		_set_status("Failed to host WebSocket on port %d (err %d)" % [port, ws_err])
		return

	multiplayer.multiplayer_peer = ws_peer
	_spawn_index = 0
	_spawned_players.clear()
	if overview_camera:
		overview_camera.current = false
	var host_pos := _next_spawn_pos()
	_spawned_players[1] = {"pos": host_pos, "char_idx": 10}
	_spawn_player_local(1, host_pos, 10)
	_set_connected_ui(true, "Hosting (WS :%d)" % port)
	_refresh_player_count()
	call_deferred("_apply_mobile_ui_to_local_player")


func _on_join_pressed() -> void:
	_cleanup_peer()

	var is_ios := OS.has_feature("ios")
	var raw := ip_input.text.strip_edges()
	if raw.is_empty():
		if OS.has_feature("web"):
			raw = _detect_web_ws_url()
		elif is_ios:
			raw = load_server_url()
		else:
			raw = DEFAULT_IP
		ip_input.text = raw

	if OS.has_feature("web") and raw == DEFAULT_IP:
		raw = _detect_web_ws_url()
		ip_input.text = raw

	var ws_url := normalize_ws_url(raw, is_ios)
	if ws_url.is_empty():
		_set_status("الرجاء إدخال رابط الخادم (https://....trycloudflare.com)")
		return

	if is_ios:
		ip_input.text = ws_url
		save_server_url(ws_url)

	_target_ip = raw
	_target_endpoint = ws_url

	var ws_client := WebSocketMultiplayerPeer.new()
	var err := ws_client.create_client(ws_url)
	if err != OK:
		_set_status("Failed to connect to %s (err %d)" % [ws_url, err])
		return

	multiplayer.multiplayer_peer = ws_client
	_set_connecting_state(true, "Connecting to %s..." % ws_url)
	_start_ws_connect_timeout(ws_client, ws_url)


func _start_ws_connect_timeout(ws_client: WebSocketMultiplayerPeer, ws_url: String) -> void:
	await get_tree().create_timer(10.0).timeout
	if not is_inside_tree():
		return
	if multiplayer.multiplayer_peer == ws_client and ws_client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_cleanup_peer()
		_set_connected_ui(false, "Connection timeout after 10s (%s)" % ws_url)
		_refresh_player_count()


func _on_disconnect_pressed() -> void:
	_cleanup_peer()
	_set_connected_ui(false, "Disconnected")
	_refresh_player_count()


func _on_mobile_toggle_pressed() -> void:
	_mobile_ui_on = not _mobile_ui_on
	sync_mobile_ui_button(_mobile_ui_on)
	get_tree().call_group("local_player", "set_mobile_ui_enabled", _mobile_ui_on)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		var spawn_pos := _next_spawn_pos()
		var char_idx := (10 + id - 1) % maxi(CharacterModelLoader.get_character_count(), 1)
		_spawned_players[id] = {"pos": spawn_pos, "char_idx": char_idx}
		_spawn_player_local(id, spawn_pos, char_idx)

		# Broadcast the newly joined player to ALL connected peers (including the new peer)
		spawn_player_rpc.rpc(id, spawn_pos, char_idx)

		# Send every existing player (including Host ID 1) directly to the newly joined peer
		for existing_id_var in _spawned_players.keys():
			var existing_id: int = int(existing_id_var)
			if existing_id == id:
				continue
			var info: Dictionary = _spawned_players[existing_id]
			var ex_pos: Vector3 = info["pos"]
			var ex_node := players_container.get_node_or_null("Player_%d" % existing_id) as Node3D
			if ex_node != null and is_instance_valid(ex_node):
				ex_pos = ex_node.global_position
			spawn_player_rpc.rpc_id(id, existing_id, ex_pos, int(info["char_idx"]))
	call_deferred("_refresh_player_count")


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		_spawned_players.erase(id)
		for node in get_tree().get_nodes_in_group("npcs"):
			var npc := node as NPCInteractive
			if npc and npc.following_peer_id == id:
				npc.apply_follow.rpc(0)
		for node in get_tree().get_nodes_in_group("vehicles"):
			var veh := node as VehicleController
			if veh and veh.driver_peer_id == id:
				veh.apply_driver.rpc(0)
		_despawn_player_local(id)
		despawn_player_rpc.rpc(id)
	call_deferred("_refresh_player_count")


func _on_connected_to_server() -> void:
	if overview_camera:
		overview_camera.current = false
	_set_connected_ui(true, "Connected (%s)" % _target_endpoint)
	_request_world_players.rpc_id(1)
	call_deferred("_refresh_player_count")
	call_deferred("_apply_mobile_ui_to_local_player")


func _on_connection_failed() -> void:
	_cleanup_peer()
	_set_connected_ui(false, "Connection failed (%s)" % _target_endpoint)
	_refresh_player_count()


func _on_server_disconnected() -> void:
	_cleanup_peer()
	_set_connected_ui(false, "Server disconnected")
	_refresh_player_count()


func _on_players_changed(_node: Node) -> void:
	call_deferred("_refresh_player_count")
	call_deferred("_apply_mobile_ui_to_local_player")


func _next_spawn_pos() -> Vector3:
	var angle := float(_spawn_index) * (TAU / 6.0)
	var radius := 2.4 if _spawn_index > 0 else 0.0
	_spawn_index += 1
	return Vector3(cos(angle) * radius, 0.15, 8.2 + sin(angle) * radius)


@rpc("any_peer", "call_remote", "reliable")
func _request_world_players() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	for existing_id_var in _spawned_players.keys():
		var existing_id: int = int(existing_id_var)
		var info: Dictionary = _spawned_players[existing_id]
		var ex_pos: Vector3 = info["pos"]
		var ex_node := players_container.get_node_or_null("Player_%d" % existing_id) as Node3D
		if ex_node != null and is_instance_valid(ex_node):
			ex_pos = ex_node.global_position
		spawn_player_rpc.rpc_id(sender_id, existing_id, ex_pos, int(info["char_idx"]))


@rpc("authority", "call_remote", "reliable")
func spawn_player_rpc(peer_id: int, spawn_pos: Vector3, char_idx: int) -> void:
	_spawn_player_local(peer_id, spawn_pos, char_idx)


@rpc("authority", "call_remote", "reliable")
func despawn_player_rpc(peer_id: int) -> void:
	_despawn_player_local(peer_id)


func _despawn_player_local(peer_id: int) -> void:
	var player_node := players_container.get_node_or_null("Player_%d" % peer_id)
	if player_node:
		player_node.queue_free()
	call_deferred("_refresh_player_count")


func _spawn_player_local(peer_id: int, spawn_pos: Vector3, char_idx: int) -> void:
	var node_name := "Player_%d" % peer_id
	if players_container.get_node_or_null(node_name) != null:
		return

	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.name = node_name
	player.set_multiplayer_authority(peer_id)

	player.position = spawn_pos
	player.sync_position = spawn_pos
	player.sync_yaw = 0.0
	player.character_index = char_idx
	player.sync_anim_state = "Idle"
	player.player_color = PLAYER_COLORS[(peer_id - 1) % PLAYER_COLORS.size()]
	player.display_name = "Host" if peer_id == 1 else "Player %d" % peer_id

	players_container.add_child(player)
	call_deferred("_refresh_player_count")


func _cleanup_peer() -> void:
	_spawned_players.clear()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	for child in players_container.get_children():
		child.queue_free()

	for node in get_tree().get_nodes_in_group("vehicles"):
		var veh := node as VehicleController
		if veh:
			veh.reset_vehicle()

	get_tree().call_group("npcs", "reset_npc")
	if subtitle_panel:
		subtitle_panel.visible = false
	set_context_prompt("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if overview_camera:
		overview_camera.make_current()


func _set_connecting_state(connecting: bool, message: String) -> void:
	host_button.disabled = connecting
	join_button.disabled = connecting
	ip_input.editable = not connecting
	_set_status(message)


func _set_connected_ui(connected: bool, message: String) -> void:
	host_button.disabled = false
	join_button.disabled = false
	ip_input.editable = true
	startup_overlay.visible = not connected
	top_bar.visible = connected
	if minimap_panel:
		minimap_panel.visible = connected
	if connected:
		host_button.release_focus()
		join_button.release_focus()
		ip_input.release_focus()
	else:
		set_context_prompt("")
		if overview_camera:
			overview_camera.make_current()
	_set_status(message)


func _set_status(message: String) -> void:
	status_label.text = "Status: %s" % message
	top_status_label.text = message


func _refresh_player_count() -> void:
	var count := 0
	for child in players_container.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	player_count_label.text = "Players: %d" % count
	top_count_label.text = "Players: %d" % count
