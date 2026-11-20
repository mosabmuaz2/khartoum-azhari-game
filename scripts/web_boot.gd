extends Control

## Ultra-lightweight 2D instant-boot lobby (< 1 MB RAM).
## - Desktop: immediately transitions to res://scenes/main.tscn.
## - Web (iPhone Safari): dismisses splash in < 2s, shows Arabic title screen,
##   live WebSocket handshake check with 10s timeout, and direct scene transition
##   (avoids load_threaded_request stalls in single-threaded WebAssembly).

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const CONNECT_TIMEOUT_SEC: float = 10.0

@onready var title_label: Label = $Center/Card/Margin/VBox/TitleLabel
@onready var subtitle_label: Label = $Center/Card/Margin/VBox/SubtitleLabel
@onready var status_label: Label = $Center/Card/Margin/VBox/StatusLabel
@onready var progress_bar: ProgressBar = $Center/Card/Margin/VBox/ProgressBar
@onready var join_button: Button = $Center/Card/Margin/VBox/JoinButton

var _ws_url: String = "ws://127.0.0.1:7778"
var _http_origin: String = ""
var _connecting: bool = false
var _connect_elapsed: float = 0.0
var _ws_probe: WebSocketPeer = null
var _ios_url_input: LineEdit = null


func _ready() -> void:
	var is_web := OS.has_feature("web")
	var is_ios := OS.has_feature("ios")
	if not is_web and not is_ios:
		visible = false
		call_deferred("_enter_main_desktop")
		return

	title_label.text = "الخرطوم — حي الأزهري"
	subtitle_label.text = "Khartoum Al-Azhari Open-World Multiplayer"
	progress_bar.visible = false
	join_button.text = "دخول مدينة الأزهري (Join)"
	join_button.pressed.connect(_on_join_pressed)

	if is_web:
		get_viewport().scaling_3d_scale = 0.60
		Engine.max_fps = 30
		JavaScriptBridge.eval("if(window.hideBootOverlay){window.hideBootOverlay();}", true)
		_detect_endpoints()
		status_label.text = "جاهز للاتصال: %s" % _ws_url
		_probe_server_reachability()
	else:
		_setup_ios_url_input()


func _setup_ios_url_input() -> void:
	var vbox := $Center/Card/Margin/VBox as VBoxContainer
	var prompt_lbl := Label.new()
	prompt_lbl.text = "رابط الخادم (الصق رابط trycloudflare.com):"
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_ios_url_input = LineEdit.new()
	_ios_url_input.placeholder_text = "https://xxxx.trycloudflare.com"
	_ios_url_input.clear_button_enabled = true
	_ios_url_input.custom_minimum_size = Vector2(0, 44)
	_ios_url_input.text_submitted.connect(func(_new_text: String) -> void: _on_join_pressed())

	var saved_url := NetworkManager.load_server_url()
	if not saved_url.is_empty():
		_ios_url_input.text = saved_url
		_ws_url = NetworkManager.normalize_ws_url(saved_url, true)
		status_label.text = "جاهز للاتصال: %s" % _ws_url
	else:
		_ws_url = ""
		status_label.text = "الصق رابط الخادم (https://....trycloudflare.com) ثم اضغط دخول"

	var insert_idx := progress_bar.get_index()
	vbox.add_child(prompt_lbl)
	vbox.move_child(prompt_lbl, insert_idx)
	vbox.add_child(_ios_url_input)
	vbox.move_child(_ios_url_input, insert_idx + 1)


func _enter_main_desktop() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _detect_endpoints() -> void:
	if OS.has_feature("web"):
		var origin_val = JavaScriptBridge.eval("window.location.origin", true)
		var origin := str(origin_val).strip_edges()
		if origin.begins_with("https://"):
			_http_origin = origin
			_ws_url = origin.replace("https://", "wss://") + "/ws"
			return
		elif origin.begins_with("http://"):
			_http_origin = origin
			_ws_url = origin.replace("http://", "ws://") + "/ws"
			return
	_ws_url = "ws://127.0.0.1:7778"


func _probe_server_reachability() -> void:
	if _http_origin.is_empty():
		return
	var http := HTTPRequest.new()
	http.timeout = 4.0
	add_child(http)
	http.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		if not _connecting:
			if response_code >= 200 and response_code < 400:
				status_label.text = "الخادم متصل — جاهز للدخول (%s)" % _ws_url
			else:
				status_label.text = "حالة الخادم HTTP %d (%s)" % [response_code, _ws_url]
		http.queue_free()
	)
	var err := http.request(_http_origin + "/")
	if err != OK:
		http.queue_free()


func _on_join_pressed() -> void:
	if _connecting:
		return

	if OS.has_feature("ios"):
		var raw_url := _ios_url_input.text.strip_edges() if _ios_url_input != null else ""
		var normalized := NetworkManager.normalize_ws_url(raw_url, true)
		if normalized.is_empty():
			status_label.text = "الرجاء إدخال رابط الخادم (https://....trycloudflare.com)"
			return
		_ws_url = normalized
		NetworkManager.save_server_url(_ws_url)
		if _ios_url_input != null:
			_ios_url_input.text = _ws_url
			_ios_url_input.editable = false
		Engine.set_meta("ios_auto_join_url", _ws_url)
	else:
		Engine.set_meta("web_auto_join_url", _ws_url)

	_connecting = true
	_connect_elapsed = 0.0
	join_button.disabled = true
	join_button.text = "جاري الاتصال..."
	status_label.text = "Connecting to %s..." % _ws_url
	progress_bar.visible = true
	progress_bar.value = 25.0

	# Verify WebSocket handshake first with a 10s timeout before switching to main.tscn
	_ws_probe = WebSocketPeer.new()
	var err := _ws_probe.connect_to_url(_ws_url)
	if err != OK:
		_fail_connection("WebSocket connect_to_url failed (err=%d) for %s" % [err, _ws_url])


func _process(delta: float) -> void:
	if not _connecting or _ws_probe == null:
		return

	_ws_probe.poll()
	var state := _ws_probe.get_ready_state()
	_connect_elapsed += delta
	progress_bar.value = clampf(25.0 + (_connect_elapsed / CONNECT_TIMEOUT_SEC) * 55.0, 25.0, 80.0)

	if state == WebSocketPeer.STATE_OPEN:
		_connecting = false
		_ws_probe.close(1000, "boot_handshake_ok")
		_ws_probe = null
		progress_bar.value = 100.0
		status_label.text = "Connected! Starting Al-Azhari..."
		_transition_to_main_direct()
		return

	if state == WebSocketPeer.STATE_CLOSED:
		var code := _ws_probe.get_close_code()
		var reason := _ws_probe.get_close_reason()
		_fail_connection("WebSocket closed during handshake (code=%d, reason=%s)" % [code, reason if not reason.is_empty() else "Host offline or 503"])
		return

	if _connect_elapsed >= CONNECT_TIMEOUT_SEC:
		_fail_connection("Connection timeout after 10s (state=%d) — check Host & Cloudflare /ws" % state)


func _transition_to_main_direct() -> void:
	# Yield one frame so status updates visibly, then load main.tscn directly (no threaded loader on Web)
	await get_tree().process_frame
	if get_tree() == null:
		_fail_connection("SceneTree unavailable")
		return
	if not ResourceLoader.exists(MAIN_SCENE_PATH):
		_fail_connection("Main scene missing from package: %s" % MAIN_SCENE_PATH)
		return
	var err := get_tree().change_scene_to_file(MAIN_SCENE_PATH)
	if err != OK:
		_fail_connection("Failed to open main scene (err=%d)" % err)


func _fail_connection(msg: String) -> void:
	_connecting = false
	if _ws_probe != null:
		_ws_probe.close(1000, "timeout_or_error")
		_ws_probe = null
	progress_bar.visible = false
	join_button.disabled = false
	join_button.text = "دخول مدينة الأزهري (Join)"
	if _ios_url_input != null:
		_ios_url_input.editable = true
	status_label.text = "خطأ في الاتصال: %s" % msg
