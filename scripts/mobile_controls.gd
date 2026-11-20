extends CanvasLayer
class_name MobileControls

## Cross-platform virtual touch controls (thumbstick, jump/horn, interact/drive, talk, follow, radio).
## Supports multi-touch on Android and optional mouse emulation for testing on PC.

const MOUSE_TOUCH_INDEX: int = -99
const STICK_MAX_RADIUS: float = 56.0
const STICK_DEADZONE: float = 0.12

@onready var root_control: Control = $Root
@onready var thumbstick: Control = $Root/Thumbstick
@onready var jump_button: Control = $Root/JumpButton
@onready var interact_button: Control = $Root/InteractButton
@onready var radio_button: Control = $Root/RadioButton
@onready var talk_button: Control = $Root/TalkButton
@onready var follow_button: Control = $Root/FollowButton

var enabled: bool = false:
	set(value):
		enabled = value
		visible = enabled
		if not enabled:
			_reset_inputs()

var _driving_mode: bool = false
var _near_vehicle: bool = false
var _near_npc: bool = false
var _npc_following: bool = false

var _stick_touch_index: int = -1
var _look_touch_index: int = -1
var _jump_touch_index: int = -1
var _interact_touch_index: int = -1
var _radio_touch_index: int = -1
var _talk_touch_index: int = -1
var _follow_touch_index: int = -1

var _stick_knob_offset: Vector2 = Vector2.ZERO
var _move_vector: Vector2 = Vector2.ZERO
var _look_delta: Vector2 = Vector2.ZERO
var _jump_queued: bool = false
var _horn_queued: bool = false
var _interact_queued: bool = false
var _radio_queued: bool = false
var _talk_queued: bool = false
var _follow_queued: bool = false

var _jump_held: bool = false
var _interact_held: bool = false
var _radio_held: bool = false
var _talk_held: bool = false
var _follow_held: bool = false


func _ready() -> void:
	thumbstick.draw.connect(_on_thumbstick_draw)
	jump_button.draw.connect(_on_jump_button_draw)
	interact_button.draw.connect(_on_interact_button_draw)
	radio_button.draw.connect(_on_radio_button_draw)
	talk_button.draw.connect(_on_talk_button_draw)
	follow_button.draw.connect(_on_follow_button_draw)
	visible = enabled


func set_context_state(driving: bool, near_vehicle: bool, near_npc: bool = false, npc_following: bool = false) -> void:
	var changed := (
		_driving_mode != driving
		or _near_vehicle != near_vehicle
		or _near_npc != near_npc
		or _npc_following != npc_following
	)
	if not changed:
		return
	_driving_mode = driving
	_near_vehicle = near_vehicle
	_near_npc = near_npc
	_npc_following = npc_following
	if is_node_ready():
		radio_button.visible = driving
		talk_button.visible = near_npc and not driving
		follow_button.visible = near_npc and not driving
		jump_button.queue_redraw()
		interact_button.queue_redraw()
		radio_button.queue_redraw()
		talk_button.queue_redraw()
		follow_button.queue_redraw()


func get_move_vector() -> Vector2:
	if not enabled:
		return Vector2.ZERO
	return _move_vector


func consume_look_delta() -> Vector2:
	if not enabled:
		_look_delta = Vector2.ZERO
		return Vector2.ZERO
	var delta := _look_delta
	_look_delta = Vector2.ZERO
	return delta


func consume_jump() -> bool:
	if not enabled or _driving_mode:
		_jump_queued = false
		return false
	var triggered := _jump_queued
	_jump_queued = false
	return triggered


func consume_horn() -> bool:
	if not enabled or not _driving_mode:
		_horn_queued = false
		return false
	var triggered := _horn_queued
	_horn_queued = false
	return triggered


func consume_interact() -> bool:
	if not enabled:
		_interact_queued = false
		return false
	var triggered := _interact_queued
	_interact_queued = false
	return triggered


func consume_radio() -> bool:
	if not enabled or not _driving_mode:
		_radio_queued = false
		return false
	var triggered := _radio_queued
	_radio_queued = false
	return triggered


func consume_talk() -> bool:
	if not enabled:
		_talk_queued = false
		return false
	var triggered := _talk_queued
	_talk_queued = false
	return triggered


func consume_follow() -> bool:
	if not enabled:
		_follow_queued = false
		return false
	var triggered := _follow_queued
	_follow_queued = false
	return triggered


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_handle_pointer_press(touch.index, touch.position, touch.pressed)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_handle_pointer_move(drag.index, drag.position, drag.relative)
	elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_handle_pointer_press(MOUSE_TOUCH_INDEX, mb.position, mb.pressed)
		elif event is InputEventMouseMotion:
			if _stick_touch_index == MOUSE_TOUCH_INDEX or _look_touch_index == MOUSE_TOUCH_INDEX:
				var mm := event as InputEventMouseMotion
				_handle_pointer_move(MOUSE_TOUCH_INDEX, mm.position, mm.relative)


func _handle_pointer_press(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if radio_button.visible and radio_button.get_global_rect().grow(10.0).has_point(pos) and _radio_touch_index == -1:
			_radio_touch_index = index
			_radio_held = true
			_radio_queued = true
			radio_button.queue_redraw()
			return

		if talk_button.visible and talk_button.get_global_rect().grow(10.0).has_point(pos) and _talk_touch_index == -1:
			_talk_touch_index = index
			_talk_held = true
			_talk_queued = true
			talk_button.queue_redraw()
			return

		if follow_button.visible and follow_button.get_global_rect().grow(10.0).has_point(pos) and _follow_touch_index == -1:
			_follow_touch_index = index
			_follow_held = true
			_follow_queued = true
			follow_button.queue_redraw()
			return

		if jump_button.get_global_rect().grow(10.0).has_point(pos) and _jump_touch_index == -1:
			_jump_touch_index = index
			_jump_held = true
			if _driving_mode:
				_horn_queued = true
			else:
				_jump_queued = true
			jump_button.queue_redraw()
			return

		if interact_button.get_global_rect().grow(10.0).has_point(pos) and _interact_touch_index == -1:
			_interact_touch_index = index
			_interact_held = true
			_interact_queued = true
			interact_button.queue_redraw()
			return

		if thumbstick.get_global_rect().grow(40.0).has_point(pos) and _stick_touch_index == -1:
			_stick_touch_index = index
			_update_thumbstick(pos)
			return

		var viewport_size := get_viewport().get_visible_rect().size
		if pos.x >= viewport_size.x * 0.45 and pos.y > 72.0 and _look_touch_index == -1:
			_look_touch_index = index
	else:
		if index == _stick_touch_index:
			_stick_touch_index = -1
			_stick_knob_offset = Vector2.ZERO
			_move_vector = Vector2.ZERO
			thumbstick.queue_redraw()
		if index == _look_touch_index:
			_look_touch_index = -1
		if index == _jump_touch_index:
			_jump_touch_index = -1
			_jump_held = false
			jump_button.queue_redraw()
		if index == _interact_touch_index:
			_interact_touch_index = -1
			_interact_held = false
			interact_button.queue_redraw()
		if index == _radio_touch_index:
			_radio_touch_index = -1
			_radio_held = false
			radio_button.queue_redraw()
		if index == _talk_touch_index:
			_talk_touch_index = -1
			_talk_held = false
			talk_button.queue_redraw()
		if index == _follow_touch_index:
			_follow_touch_index = -1
			_follow_held = false
			follow_button.queue_redraw()


func _handle_pointer_move(index: int, pos: Vector2, relative: Vector2) -> void:
	if index == _stick_touch_index:
		_update_thumbstick(pos)
	elif index == _look_touch_index:
		_look_delta += relative


func _update_thumbstick(pos: Vector2) -> void:
	var center := thumbstick.get_global_rect().get_center()
	var offset := pos - center
	var dist := offset.length()
	if dist > STICK_MAX_RADIUS:
		offset = offset.normalized() * STICK_MAX_RADIUS
	_stick_knob_offset = offset

	var norm := offset / STICK_MAX_RADIUS
	if norm.length() < STICK_DEADZONE:
		_move_vector = Vector2.ZERO
	else:
		_move_vector = norm
	thumbstick.queue_redraw()


func _reset_inputs() -> void:
	_stick_touch_index = -1
	_look_touch_index = -1
	_jump_touch_index = -1
	_interact_touch_index = -1
	_radio_touch_index = -1
	_talk_touch_index = -1
	_follow_touch_index = -1
	_stick_knob_offset = Vector2.ZERO
	_move_vector = Vector2.ZERO
	_look_delta = Vector2.ZERO
	_jump_queued = false
	_horn_queued = false
	_interact_queued = false
	_radio_queued = false
	_talk_queued = false
	_follow_queued = false
	_jump_held = false
	_interact_held = false
	_radio_held = false
	_talk_held = false
	_follow_held = false
	if is_node_ready():
		thumbstick.queue_redraw()
		jump_button.queue_redraw()
		interact_button.queue_redraw()
		radio_button.queue_redraw()
		talk_button.queue_redraw()
		follow_button.queue_redraw()


func _on_thumbstick_draw() -> void:
	var center := thumbstick.size * 0.5
	var base_radius := minf(thumbstick.size.x, thumbstick.size.y) * 0.44
	thumbstick.draw_circle(center, base_radius, Color(0.10, 0.08, 0.06, 0.35))
	thumbstick.draw_arc(center, base_radius, 0.0, TAU, 48, Color(1.0, 0.88, 0.72, 0.55), 2.5, true)
	var knob_color := Color(1.0, 0.85, 0.62, 0.85) if _stick_touch_index != -1 else Color(1.0, 0.92, 0.80, 0.65)
	thumbstick.draw_circle(center + _stick_knob_offset, 28.0, knob_color)


func _on_jump_button_draw() -> void:
	var label := "HORN" if _driving_mode else "JUMP"
	var accent := Color(0.95, 0.78, 0.20, 0.85) if _driving_mode else Color(0.95, 0.64, 0.28, 0.78)
	_draw_action_circle(jump_button, label, _jump_held, accent)


func _on_interact_button_draw() -> void:
	var label := "EXIT" if _driving_mode else ("DRIVE" if _near_vehicle else "USE")
	var accent := Color(0.88, 0.36, 0.26, 0.85) if _driving_mode else (Color(0.24, 0.76, 0.46, 0.88) if _near_vehicle else Color(0.28, 0.68, 0.62, 0.78))
	_draw_action_circle(interact_button, label, _interact_held, accent)


func _on_radio_button_draw() -> void:
	_draw_action_circle(radio_button, "RADIO", _radio_held, Color(0.32, 0.72, 0.92, 0.85))


func _on_talk_button_draw() -> void:
	_draw_action_circle(talk_button, "TALK", _talk_held, Color(0.95, 0.76, 0.32, 0.88))


func _on_follow_button_draw() -> void:
	var label := "STOP" if _npc_following else "FOLLOW"
	var accent := Color(0.84, 0.40, 0.30, 0.88) if _npc_following else Color(0.30, 0.78, 0.50, 0.88)
	_draw_action_circle(follow_button, label, _follow_held, accent)


func _draw_action_circle(ctrl: Control, label: String, pressed: bool, accent: Color) -> void:
	var center := ctrl.size * 0.5
	var radius := minf(ctrl.size.x, ctrl.size.y) * 0.45
	var fill := accent if pressed else Color(0.10, 0.08, 0.06, 0.46)
	ctrl.draw_circle(center, radius, fill)
	ctrl.draw_arc(center, radius, 0.0, TAU, 40, accent, 2.5, true)

	var font := ThemeDB.fallback_font
	if font:
		var font_size := 14
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := center + Vector2(-text_size.x * 0.5, text_size.y * 0.25)
		ctrl.draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.96, 0.90, 0.95))
