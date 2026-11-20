extends CharacterBody3D
class_name PlayerController

## Articulated third-person cross-platform player controller for Khartoum Al-Azhari.
## Supports PC (WASD + Shift + Space + E + H + R + T + F) and Mobile Touch UI.

const WALK_SPEED: float = 5.6
const SPRINT_SPEED: float = 9.4
const SWIM_SPEED: float = 4.4
const FAST_SWIM_SPEED: float = 7.0
const SWIM_CHEST_HEIGHT: float = 1.12
const SWIM_FLOAT_OFFSET: float = 1.24
const ACCELERATION: float = 15.0
const DECELERATION: float = 17.0
const JUMP_VELOCITY: float = 5.6
const TURN_SPEED: float = 13.0
const MOUSE_SENSITIVITY: float = 0.0028
const TOUCH_SENSITIVITY: float = 0.0045
const MIN_PITCH_RAD: float = deg_to_rad(-65.0)
const MAX_PITCH_RAD: float = deg_to_rad(25.0)
const VEHICLE_INTERACT_RADIUS: float = 3.4
const NPC_INTERACT_RADIUS: float = 4.0
const BASE_HIPS_Y: float = 0.88

@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var sync_speed: float = 0.0
@export var sync_on_floor: bool = true
@export var sync_driving: bool = false
@export var character_index: int = 10:
	set(value):
		character_index = value
		if is_node_ready() and _loaded_character_index != character_index:
			_setup_player_glb_model()
			_setup_anim_binder()
@export var sync_anim_state: String = "Idle"
@export var player_color: Color = Color(0.94, 0.92, 0.86, 1.0):
	set(value):
		player_color = value
		_apply_player_color()
@export var display_name: String = "Player":
	set(value):
		display_name = value
		if is_node_ready() and name_label:
			name_label.text = display_name

@onready var body_collider: CollisionShape3D = $CollisionShape3D
@onready var visuals: Node3D = $Visuals
@onready var hips: Node3D = $Visuals/Hips
@onready var torso_mesh: MeshInstance3D = $Visuals/Hips/TorsoMesh
@onready var left_sleeve_mesh: MeshInstance3D = $Visuals/Hips/LeftArmPivot/ArmMesh
@onready var right_sleeve_mesh: MeshInstance3D = $Visuals/Hips/RightArmPivot/ArmMesh
@onready var left_arm_pivot: Node3D = $Visuals/Hips/LeftArmPivot
@onready var right_arm_pivot: Node3D = $Visuals/Hips/RightArmPivot
@onready var left_leg_pivot: Node3D = $Visuals/Hips/LeftLegPivot
@onready var right_leg_pivot: Node3D = $Visuals/Hips/RightLegPivot
@onready var name_label: Label3D = $Visuals/NameLabel
@onready var interact_ray: RayCast3D = $Visuals/InteractRay
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var mobile_controls: MobileControls = $MobileControls

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pitch: float = deg_to_rad(-18.0)
var _mobile_ui_active: bool = false
var _anim_time: float = 0.0
var _idle_time: float = 0.0
var _last_step_index: int = 0
var _current_vehicle: VehicleController = null
var _last_prompt: String = ""
var _footstep_player: AudioStreamPlayer3D = null
var _action_sfx_player: AudioStreamPlayer3D = null
var _was_on_floor: bool = true
var _air_time: float = 0.0
var _interaction_ring: MeshInstance3D = null
var _ring_pulse_time: float = 0.0
var _glb_pivot: Node3D = null
var _loaded_character_index: int = -1
var _net_sync_accum: float = 0.0
const NET_SYNC_INTERVAL: float = 1.0 / 15.0
var _prev_k_down: bool = false
var _prev_g_down: bool = false
var _prev_c_down: bool = false
var _prev_b_down: bool = false
var _prev_l_down: bool = false
var _had_drive_input: bool = false
var _riding_seat_marker: Marker3D = null

# Advanced locomotion state: Crouch, Sprint-Slide, Carryable Props, Bus Passenger & Swimming
enum LocomotionState { ON_FOOT, SWIMMING, DRIVING, PASSENGER, RIDING_DONKEY }
var locomotion_state: LocomotionState = LocomotionState.ON_FOOT
var is_swimming: bool = false
var _in_water_zone: bool = false
var _water_surface_y: float = 0.20
var _active_water_zones: Array[Area3D] = []
var _swim_splash: GPUParticles3D = null
var _swim_cycle: float = 0.0
var _swim_tilt: float = 0.0
var _swim_anim_player: AnimationPlayer = null
var _swim_anim_tree: AnimationTree = null
var _swim_skeleton: Skeleton3D = null
var _swim_using_clip: bool = false

const JUMP_VARIATIONS: Array[String] = [
	"Jump_Standard",
	"Jump_Running",
	"Jump_Flip",
	"Jump_High",
]
var _anim_binder: CharacterAnimationAutoBinder = null
var last_jump_clip: String = ""
var _jump_anim_active: bool = false
var _landing_anim_timer: float = 0.0

var is_crouching: bool = false
var _crouch_amount: float = 0.0
var _slide_timer: float = 0.0
var _slide_dir: Vector3 = Vector3.ZERO
var _slide_dust: GPUParticles3D = null
var carried_prop: CarryableProp = null
var _pickup_bend_timer: float = 0.0
var _riding_bus_passenger: VehicleController = null
var _riding_donkey: AnimalAI = null
var _donkey_rider_skeleton: Skeleton3D = null
var is_praying: bool = false
var _prayer_timer: float = 0.0
var _active_prayer_zone: Area3D = null


func _enter_tree() -> void:
	var sname := str(name)
	if sname.begins_with("Player_") and sname.substr(7).is_valid_int():
		set_multiplayer_authority(sname.substr(7).to_int())
	elif sname.is_valid_int():
		set_multiplayer_authority(sname.to_int())


func _exit_tree() -> void:
	for p in [_footstep_player, _action_sfx_player]:
		if p != null:
			p.stop()
			p.stream = null


func _has_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()


func _ready() -> void:
	add_to_group("players")
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.35
	_setup_player_glb_model()
	_setup_anim_binder()
	_apply_player_color()
	_setup_footstep_audio()
	_setup_slide_dust()
	_setup_swim_splash()
	if name_label:
		name_label.text = display_name

	if sync_position != Vector3.ZERO:
		global_position = sync_position
	visuals.rotation.y = sync_yaw

	spring_arm.add_excluded_object(get_rid())

	var is_local := _has_authority()
	if not is_local:
		camera.current = false
		mobile_controls.enabled = false
		set_process_unhandled_input(false)
		return

	add_to_group("local_player")
	spring_arm.rotation.x = _pitch
	camera.make_current()
	call_deferred("_activate_local_camera")
	_setup_interaction_ring()
	set_mobile_ui_enabled(DisplayServer.is_touchscreen_available())


func get_current_vehicle() -> VehicleController:
	return _current_vehicle


func _activate_local_camera() -> void:
	if _has_authority() and camera:
		camera.make_current()


func set_mobile_ui_enabled(active: bool) -> void:
	if not _has_authority():
		return
	_mobile_ui_active = active
	mobile_controls.enabled = active
	get_tree().call_group("network_hud", "sync_mobile_ui_button", active)
	if active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_mobile_ui_enabled() -> bool:
	return _mobile_ui_active


func _unhandled_input(event: InputEvent) -> void:
	if not _has_authority():
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				elif not _mobile_ui_active:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif key_event.keycode == KEY_M:
				set_mobile_ui_enabled(not _mobile_ui_active)
		return

	if _mobile_ui_active:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if carried_prop != null and is_instance_valid(carried_prop):
				throw_carried_prop()
				return
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mm := event as InputEventMouseMotion
			_rotate_camera(mm.relative, MOUSE_SENSITIVITY)


func _physics_process(delta: float) -> void:
	if not _has_authority():
		if _current_vehicle != null and is_instance_valid(_current_vehicle):
			global_position = _current_vehicle.get_seat_global_position()
			visuals.rotation.y = _current_vehicle.rotation.y
		else:
			global_position = global_position.lerp(sync_position, clampf(delta * 18.0, 0.0, 1.0))
			visuals.rotation.y = lerp_angle(visuals.rotation.y, sync_yaw, clampf(delta * 18.0, 0.0, 1.0))
		var remote_seated := sync_anim_state == "Sit" or sync_driving
		var remote_grounded := (sync_anim_state != "Jump") and sync_on_floor
		var remote_speed := sync_speed
		if sync_anim_state == "Run" and remote_speed < 6.2:
			remote_speed = 8.0
		elif sync_anim_state == "Walk" and remote_speed < 1.0:
			remote_speed = 3.5
		elif sync_anim_state == "Idle":
			remote_speed = 0.0
		_update_procedural_animation(delta, remote_speed, remote_grounded, sync_driving, remote_seated)
		return

	if _mobile_ui_active:
		var touch_look := mobile_controls.consume_look_delta()
		if touch_look.length_squared() > 0.0:
			_rotate_camera(touch_look, TOUCH_SENSITIVITY)

	var target_arm_len := 4.6
	if _current_vehicle != null:
		target_arm_len = _current_vehicle.camera_distance
	elif _riding_bus_passenger != null:
		target_arm_len = 3.8
	elif _riding_donkey != null:
		target_arm_len = 4.2
	spring_arm.spring_length = lerpf(spring_arm.spring_length, target_arm_len, clampf(delta * 8.0, 0.0, 1.0))

	if _current_vehicle != null:
		if is_swimming:
			_exit_swimming_state()
		if _jump_anim_active or _landing_anim_timer > 0.0:
			_jump_anim_active = false
			_landing_anim_timer = 0.0
			if _anim_binder != null and _anim_binder.is_override_active():
				_anim_binder.resume_animation_tree()
		locomotion_state = LocomotionState.DRIVING
		_process_driving(delta)
	elif _riding_bus_passenger != null:
		if is_swimming:
			_exit_swimming_state()
		if _jump_anim_active or _landing_anim_timer > 0.0:
			_jump_anim_active = false
			_landing_anim_timer = 0.0
			if _anim_binder != null and _anim_binder.is_override_active():
				_anim_binder.resume_animation_tree()
		locomotion_state = LocomotionState.PASSENGER
		_process_bus_passenger(delta)
	elif _riding_donkey != null:
		if is_swimming:
			_exit_swimming_state()
		locomotion_state = LocomotionState.RIDING_DONKEY
		_process_riding_donkey(delta)
	else:
		_update_water_swimming_state()
		if is_swimming:
			locomotion_state = LocomotionState.SWIMMING
			_process_swimming(delta)
		else:
			locomotion_state = LocomotionState.ON_FOOT
			_process_on_foot(delta)

	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_net_sync_accum += delta
		if _net_sync_accum >= NET_SYNC_INTERVAL:
			_net_sync_accum = 0.0
			_sync_player_state.rpc(global_position, visuals.rotation.y, sync_speed, sync_on_floor, sync_driving, sync_anim_state)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync_player_state(pos: Vector3, yaw: float, speed: float, on_floor: bool, driving: bool, anim_state: String) -> void:
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	sync_position = pos
	sync_yaw = yaw
	sync_speed = speed
	sync_on_floor = on_floor
	sync_driving = driving
	sync_anim_state = anim_state


func _process_driving(delta: float) -> void:
	if not is_instance_valid(_current_vehicle):
		_current_vehicle = null
		body_collider.disabled = false
		return

	var kb_forward := Input.get_axis("move_backward", "move_forward")
	if absf(kb_forward) < 0.05:
		var fwd_k := 1.0 if (Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) else 0.0
		var rev_k := 1.0 if (Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) else 0.0
		kb_forward = fwd_k - rev_k
	var kb_steer := Input.get_axis("move_right", "move_left")
	if absf(kb_steer) < 0.05:
		var left_k := 1.0 if (Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)) else 0.0
		var right_k := 1.0 if (Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) else 0.0
		kb_steer = left_k - right_k
	var stick := mobile_controls.get_move_vector()

	var throttle := kb_forward if absf(kb_forward) > 0.05 else -stick.y
	var steer := kb_steer if absf(kb_steer) > 0.05 else -stick.x
	var handbrake := Input.is_action_pressed("jump") or Input.is_physical_key_pressed(KEY_SPACE)
	if absf(throttle) > 0.01 or absf(steer) > 0.01 or handbrake:
		_had_drive_input = true
		_current_vehicle.set_drive_inputs(throttle, steer, handbrake)
	elif _had_drive_input:
		_had_drive_input = false
		_current_vehicle.set_drive_inputs(0.0, 0.0, false)

	var l_down := Input.is_physical_key_pressed(KEY_L)
	if l_down and not _prev_l_down:
		_current_vehicle.toggle_headlights()
	_prev_l_down = l_down

	if Input.is_action_just_pressed("horn") or mobile_controls.consume_horn():
		_current_vehicle.trigger_horn.rpc()

	if Input.is_action_just_pressed("radio_toggle") or mobile_controls.consume_radio():
		_current_vehicle.cycle_radio()

	global_position = _current_vehicle.get_seat_global_position()
	visuals.rotation.y = _current_vehicle.rotation.y
	velocity = Vector3.ZERO

	if camera_pivot != null:
		camera_pivot.position = camera_pivot.position.lerp(Vector3(0.0, 1.52, 0.0), clampf(delta * 10.0, 0.0, 1.0))

	sync_position = global_position
	sync_yaw = visuals.rotation.y
	sync_speed = 0.0
	sync_on_floor = true
	sync_driving = true
	sync_anim_state = "Sit"

	_update_procedural_animation(delta, 0.0, true, true, true)
	if _interaction_ring:
		_interaction_ring.visible = false
	mobile_controls.set_context_state(true, false, false, false)

	var gas_st := GasStationController.find_station_for_position(get_tree(), _current_vehicle.global_position)
	var near_pump := (gas_st != null) or _current_vehicle.is_near_fuel_pump()
	var fuel_txt := _current_vehicle.get_fuel_hud_text()
	if near_pump:
		_set_prompt("[E] تعبئة وقود السيارة  |  [L] الأضواء  |  %s  |  [H] Horn  |  [R] %s" % [fuel_txt, _current_vehicle.get_current_radio_label()])
	else:
		_set_prompt("[E] نزول  |  [L] الأضواء  |  %s  |  [H] Horn  |  [R] %s" % [fuel_txt, _current_vehicle.get_current_radio_label()])

	var b_down := Input.is_physical_key_pressed(KEY_B)
	if b_down and not _prev_b_down and near_pump:
		if gas_st != null:
			gas_st.refuel_active_or_nearest_vehicle(self)
		else:
			_current_vehicle.refuel_vehicle(_current_vehicle.max_fuel_liters)
	_prev_b_down = b_down

	if Input.is_action_just_pressed("interact") or mobile_controls.consume_interact():
		if near_pump and _current_vehicle.get_fuel_percentage() < 99.5:
			if gas_st != null:
				gas_st.refuel_active_or_nearest_vehicle(self)
			else:
				_current_vehicle.refuel_vehicle(_current_vehicle.max_fuel_liters)
			return
		var peer_id := _get_local_peer_id()
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			_current_vehicle.request_exit.rpc_id(1, peer_id)
		else:
			_current_vehicle.request_exit(peer_id)


func _process_bus_passenger(delta: float) -> void:
	if not is_instance_valid(_riding_bus_passenger):
		exit_bus_as_passenger()
		return
	if _riding_seat_marker != null and is_instance_valid(_riding_seat_marker):
		global_position = _riding_seat_marker.global_position
	else:
		global_position = _riding_bus_passenger.to_global(_riding_bus_passenger.passenger_seat_offset)
	visuals.rotation.y = _riding_bus_passenger.rotation.y
	velocity = Vector3.ZERO
	sync_position = global_position
	sync_yaw = visuals.rotation.y
	sync_speed = 0.0
	sync_on_floor = true
	sync_driving = true
	sync_anim_state = "Sit"
	_update_procedural_animation(delta, 0.0, true, false, true)
	_set_prompt("🚌 راكب في بص الوالي (الأزهري - السوق العربي)  |  [E] النزول من البص  |  [G] قيادة البص")

	if Input.is_action_just_pressed("interact") or mobile_controls.consume_interact():
		exit_bus_as_passenger()
		return

	var g_down := Input.is_physical_key_pressed(KEY_G)
	if g_down and not _prev_g_down:
		var bus_ref := _riding_bus_passenger
		exit_bus_as_passenger()
		var bus_sys := _get_bus_system()
		if bus_sys and bus_ref:
			bus_sys.take_over_bus_driving(bus_ref, _get_local_peer_id())
	_prev_g_down = g_down


func board_bus_as_passenger(bus: VehicleController) -> void:
	if bus == null:
		return
	if carried_prop != null:
		drop_carried_prop()
	var sm := bus.get_seat_manager()
	if sm != null:
		if not sm.board_passenger(self, false):
			get_tree().call_group("network_hud", "show_toast", "🚌 البص ممتلئ حالياً!")
			return
		_riding_seat_marker = sm.get_seat_for_passenger(self)
	else:
		_riding_seat_marker = null
	_riding_bus_passenger = bus
	bus.passenger_peer_id = _get_local_peer_id()
	body_collider.disabled = true
	spring_arm.add_excluded_object(bus.get_rid())
	global_position = _riding_seat_marker.global_position if _riding_seat_marker != null else bus.to_global(bus.passenger_seat_offset)
	visuals.rotation.y = bus.rotation.y
	get_tree().call_group("network_hud", "show_toast", "🚌 ركبت بص الوالي كراكب — استمتع بالمشوار!")


func exit_bus_as_passenger() -> void:
	if _riding_bus_passenger != null and is_instance_valid(_riding_bus_passenger):
		_riding_bus_passenger.passenger_peer_id = 0
		var sm := _riding_bus_passenger.get_seat_manager()
		if sm != null and sm.is_passenger_seated(self):
			var seat := sm.get_seat_for_passenger(self)
			var exit_pos := sm.get_exit_global_position_for_seat(seat)
			sm.exit_passenger(self)
			global_position = exit_pos
		else:
			global_position = _riding_bus_passenger.get_safe_exit_position()
	_riding_seat_marker = null
	_riding_bus_passenger = null
	velocity = Vector3.ZERO
	body_collider.disabled = false
	_set_prompt("")


func _process_on_foot(delta: float) -> void:
	if _pickup_bend_timer > 0.0:
		_pickup_bend_timer = maxf(0.0, _pickup_bend_timer - delta)

	if _landing_anim_timer > 0.0:
		_landing_anim_timer = maxf(0.0, _landing_anim_timer - delta)
		if _landing_anim_timer <= 0.0 and _anim_binder != null and _anim_binder.get_current_clip_name() == "Landing":
			_anim_binder.resume_animation_tree()

	var on_floor_now := is_on_floor()
	if not on_floor_now:
		velocity.y -= gravity * delta
		_air_time += delta
		if _jump_anim_active and _anim_binder != null and not _anim_binder.is_one_shot_playing():
			if _anim_binder.has_clip("Falling_Idle"):
				_anim_binder.play_state("Falling_Idle", 0.14, 1.0)
	else:
		if not _was_on_floor:
			if _air_time > 0.14:
				_play_land_thud()
			if _jump_anim_active or _air_time > 0.22:
				_jump_anim_active = false
				if _anim_binder != null and _anim_binder.has_clip("Landing") and _air_time > 0.22:
					_anim_binder.play_one_shot("Landing", 0.06, 1.25, true)
					_landing_anim_timer = 0.28
				elif _anim_binder != null and _anim_binder.is_override_active():
					_anim_binder.resume_animation_tree()
		_air_time = 0.0

	var kb_input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var stick_input := mobile_controls.get_move_vector()
	var input_vec := kb_input if kb_input.length_squared() > 0.01 else stick_input
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()

	# If player is currently praying in a mosque, moving or jumping gracefully ends the prayer sequence
	if is_praying:
		_prayer_timer += delta
		if input_vec.length() > 0.18 or Input.is_action_just_pressed("jump") or _prayer_timer > 14.0:
			stop_mosque_prayer(true)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			input_vec = Vector2.ZERO

	var sprinting := Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT) or stick_input.length() > 0.86

	# Crouch / Bend (`C` or `Ctrl`) & Sprint-Slide (`C` or `Ctrl` while sprinting)
	var c_down := Input.is_physical_key_pressed(KEY_C) or Input.is_key_pressed(KEY_CTRL)
	if c_down and not _prev_c_down and on_floor_now:
		var cur_horiz := Vector2(velocity.x, velocity.z).length()
		if sprinting and cur_horiz > WALK_SPEED + 0.8 and _slide_timer <= 0.0:
			trigger_sprint_slide()
		else:
			set_crouch(not is_crouching)
	_prev_c_down = c_down

	var jump_triggered := Input.is_action_just_pressed("jump") or mobile_controls.consume_jump()
	if jump_triggered and on_floor_now:
		if is_crouching:
			set_crouch(false)
		_slide_timer = 0.0
		_landing_anim_timer = 0.0
		velocity.y = JUMP_VELOCITY + 0.8
		_play_jump_whoosh()
		var cur_horiz_for_jump := Vector2(velocity.x, velocity.z).length()
		trigger_random_jump_animation(sprinting or cur_horiz_for_jump > WALK_SPEED * 0.75)
	_was_on_floor = on_floor_now

	var cam_basis := camera_pivot.global_transform.basis
	var forward := -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()
	var move_dir := right * input_vec.x + forward * (-input_vec.y)

	if _slide_timer > 0.0:
		_slide_timer = maxf(0.0, _slide_timer - delta)
		var slide_spd := lerpf(WALK_SPEED, SPRINT_SPEED * 1.38, _slide_timer / 0.72)
		velocity.x = _slide_dir.x * slide_spd
		velocity.z = _slide_dir.z * slide_spd
		if _slide_dust:
			_slide_dust.emitting = on_floor_now
	else:
		if _slide_dust:
			_slide_dust.emitting = false
		var target_speed := (WALK_SPEED * 0.58) if is_crouching else (SPRINT_SPEED if sprinting else WALK_SPEED)
		if move_dir.length_squared() > 0.001:
			move_dir = move_dir.normalized()
			var desired_speed := target_speed * clampf(input_vec.length(), 0.25, 1.0)
			velocity.x = lerpf(velocity.x, move_dir.x * desired_speed, clampf(delta * ACCELERATION, 0.0, 1.0))
			velocity.z = lerpf(velocity.z, move_dir.z * desired_speed, clampf(delta * ACCELERATION, 0.0, 1.0))
			var target_yaw := atan2(-move_dir.x, -move_dir.z)
			visuals.rotation.y = lerp_angle(visuals.rotation.y, target_yaw, clampf(delta * TURN_SPEED, 0.0, 1.0))
			if on_floor_now:
				_apply_step_up_assist(move_dir)
		else:
			velocity.x = lerpf(velocity.x, 0.0, clampf(delta * DECELERATION, 0.0, 1.0))
			velocity.z = lerpf(velocity.z, 0.0, clampf(delta * DECELERATION, 0.0, 1.0))

	_crouch_amount = lerpf(_crouch_amount, 1.0 if (is_crouching or _slide_timer > 0.0) else 0.0, clampf(delta * 12.0, 0.0, 1.0))
	if camera_pivot:
		camera_pivot.position.y = lerpf(1.52, 0.96, _crouch_amount)

	move_and_slide()

	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor()

	sync_position = global_position
	sync_yaw = visuals.rotation.y
	sync_speed = horiz_speed
	sync_on_floor = grounded
	sync_driving = false
	if not grounded:
		sync_anim_state = "Jump"
	elif horiz_speed > 5.8:
		sync_anim_state = "Run"
	elif horiz_speed > 0.25:
		sync_anim_state = "Walk"
	else:
		sync_anim_state = "Idle"

	_update_procedural_animation(delta, horiz_speed, grounded, false)

	var nearby_gas_station := GasStationController.find_station_for_position(get_tree(), global_position)
	var nearby_bus := _find_nearby_bus()
	var nearby_vehicle := _find_nearby_vehicle()
	var nearby_npc := _find_nearby_npc()
	var nearby_donkey := _find_nearby_donkey()
	var nearby_door := _find_nearby_door()
	var prayer_zone := _find_active_prayer_zone()
	var nearby_prop := _find_nearby_carryable_prop() if nearby_gas_station == null else null
	var peer_id := _get_local_peer_id()
	var npc_following := nearby_npc != null and nearby_npc.is_following_peer(peer_id)

	_update_interaction_ring(delta, nearby_vehicle if nearby_vehicle != null else nearby_bus, nearby_npc)
	mobile_controls.set_context_state(false, (nearby_vehicle != null or nearby_bus != null or nearby_donkey != null), nearby_npc != null, npc_following)

	var prompts: Array[String] = []
	if is_praying:
		prompts.append("[E] إنهاء الصلاة  |  تحرك للوقوف")
	elif nearby_gas_station != null:
		prompts.append("[E] تعبئة وقود السيارة")
	elif nearby_vehicle != null:
		if nearby_vehicle.is_bus:
			prompts.append("[E] قيادة البص (%s)  |  [G] ركوب كراكب" % nearby_vehicle.vehicle_name)
		else:
			prompts.append("[E] قيادة %s" % nearby_vehicle.vehicle_name)
	elif nearby_donkey != null:
		prompts.append("[E] ركوب %s" % nearby_donkey.donkey_name)
	elif nearby_door != null:
		prompts.append(nearby_door.get_interaction_prompt())
	elif prayer_zone != null:
		var m_title := str(prayer_zone.get_meta("mosque_title", "المسجد"))
		prompts.append("[E] أداء الصلاة في %s" % m_title)

	if carried_prop != null and is_instance_valid(carried_prop):
		prompts.append("تحمل %s: [G] وضع  |  [Left Click] رمي" % carried_prop.prop_label)
	elif nearby_prop != null and (nearby_vehicle == null or not nearby_vehicle.is_bus):
		prompts.append("[G] حمل / رفع %s (Aufheben)" % nearby_prop.prop_label)

	if nearby_npc != null:
		prompts.append("[T] كلام مع %s" % nearby_npc.npc_name)
		prompts.append("[F] %s" % ("توقف" if npc_following else "اتبعني"))
	_set_prompt("  |  ".join(prompts))

	if Input.is_action_just_pressed("interact") or mobile_controls.consume_interact():
		if is_praying:
			_play_ui_chime()
			stop_mosque_prayer(true)
		elif nearby_gas_station != null:
			_play_ui_chime()
			nearby_gas_station.refuel_active_or_nearest_vehicle(self)
		elif nearby_vehicle != null:
			if carried_prop != null:
				drop_carried_prop()
			if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
				nearby_vehicle.request_enter.rpc_id(1, peer_id)
			else:
				nearby_vehicle.request_enter(peer_id)
		elif nearby_donkey != null:
			_play_ui_chime()
			mount_donkey(nearby_donkey)
		elif nearby_door != null:
			_play_ui_chime()
			_handle_world_interact()
		elif prayer_zone != null:
			_play_ui_chime()
			start_mosque_prayer(prayer_zone)
		else:
			_play_ui_chime()
			_handle_world_interact()

	var g_down := Input.is_physical_key_pressed(KEY_G)
	if g_down and not _prev_g_down:
		if nearby_bus != null and carried_prop == null:
			_play_ui_chime()
			board_bus_as_passenger(nearby_bus)
		elif carried_prop != null and is_instance_valid(carried_prop):
			drop_carried_prop()
		elif nearby_prop != null:
			pick_up_prop(nearby_prop)
	_prev_g_down = g_down

	var k_down := Input.is_physical_key_pressed(KEY_K)
	if k_down and not _prev_k_down and nearby_door != null:
		_play_ui_chime()
		get_tree().call_group("network_hud", "show_toast", nearby_door.toggle_lock())
	_prev_k_down = k_down

	if nearby_npc != null:
		if Input.is_action_just_pressed("talk") or mobile_controls.consume_talk():
			_play_ui_chime()
			nearby_npc.talk_interact()
		if Input.is_action_just_pressed("follow") or mobile_controls.consume_follow():
			_play_ui_chime()
			if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
				nearby_npc.request_toggle_follow.rpc_id(1, peer_id)
			else:
				nearby_npc.request_toggle_follow(peer_id)


func set_crouch(active: bool) -> void:
	is_crouching = active
	if body_collider and body_collider.shape is CapsuleShape3D:
		var cap := body_collider.shape as CapsuleShape3D
		cap.height = 1.05 if active else 1.75
		body_collider.position.y = 0.525 if active else 0.875


func trigger_sprint_slide() -> void:
	_slide_timer = 0.72
	var fwd := -visuals.global_transform.basis.z
	fwd.y = 0.0
	_slide_dir = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD
	set_crouch(true)
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if _action_sfx_player and audio_mgr and audio_mgr.tire_skid_stream:
		_action_sfx_player.stream = audio_mgr.tire_skid_stream
		_action_sfx_player.pitch_scale = 1.25
		_action_sfx_player.play()
		get_tree().create_timer(0.45).timeout.connect(func() -> void:
			if is_instance_valid(_action_sfx_player):
				_action_sfx_player.stop()
		)
	get_tree().call_group("network_hud", "show_toast", "💨 انزلاق سريع (Sprint-Slide)")


func pick_up_prop(prop: CarryableProp) -> void:
	if prop == null or prop.is_carried:
		return
	_pickup_bend_timer = 0.36
	carried_prop = prop
	prop.pick_up(visuals)
	_play_ui_chime()
	get_tree().call_group("network_hud", "show_toast", "حملت: %s ([G] وضع | [Left Click] رمي)" % prop.prop_label)


func drop_carried_prop() -> void:
	if carried_prop == null or not is_instance_valid(carried_prop):
		carried_prop = null
		return
	var fwd := -visuals.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var drop_pos := global_position + fwd * 0.95 + Vector3(0.0, 0.45, 0.0)
	carried_prop.drop_object(drop_pos, velocity)
	carried_prop = null


func throw_carried_prop() -> void:
	if carried_prop == null or not is_instance_valid(carried_prop):
		carried_prop = null
		return
	var cam_fwd := -camera.global_transform.basis.z if camera != null else -visuals.global_transform.basis.z
	carried_prop.throw_object(cam_fwd, velocity)
	_play_jump_whoosh()
	carried_prop = null


func _apply_step_up_assist(move_dir: Vector3) -> void:
	# Smoothly steps over stair treads and low curbs (up to 0.45m high) without snagging
	var space := get_world_3d().direct_space_state
	var low_from := global_position + Vector3(0.0, 0.14, 0.0)
	var low_to := low_from + move_dir * 0.52
	var q_low := PhysicsRayQueryParameters3D.create(low_from, low_to, 1)
	q_low.exclude = [get_rid()]
	var hit_low := space.intersect_ray(q_low)
	if hit_low.is_empty():
		return
	# Do not bump vertically on smooth walkable stair ramps (normal.y > 0.55 -> slope < 56 deg)
	if (hit_low.get("normal", Vector3.ZERO) as Vector3).y > 0.55:
		return
	var high_from := global_position + Vector3(0.0, 0.52, 0.0)
	var high_to := high_from + move_dir * 0.56
	var q_high := PhysicsRayQueryParameters3D.create(high_from, high_to, 1)
	q_high.exclude = [get_rid()]
	var hit_high := space.intersect_ray(q_high)
	if hit_high.is_empty():
		global_position.y += 0.08


func _setup_slide_dust() -> void:
	var vfx_mgr := get_node_or_null("/root/VFXManager")
	if vfx_mgr:
		_slide_dust = vfx_mgr.create_dust_particles(self, Vector3(0.0, 0.08, 0.25))


func _get_bus_system() -> BusSystem:
	var nodes := get_tree().get_nodes_in_group("bus_system")
	return nodes[0] as BusSystem if not nodes.is_empty() else null


func _find_nearby_bus() -> VehicleController:
	var bus_sys := _get_bus_system()
	if bus_sys == null:
		return null
	return bus_sys.find_nearby_bus(global_position, 5.6)


func _find_nearby_carryable_prop() -> CarryableProp:
	var closest: CarryableProp = null
	var best_dist := 2.8
	for node in get_tree().get_nodes_in_group("carryable_props"):
		var cp := node as CarryableProp
		if cp == null or cp.is_carried:
			continue
		var d := global_position.distance_to(cp.global_position)
		if d <= best_dist:
			best_dist = d
			closest = cp
	return closest



func _on_vehicle_driver_changed(vehicle: VehicleController, prev_driver: int, new_driver: int) -> void:
	var my_id := _get_local_peer_id()
	if new_driver == my_id and new_driver > 0:
		_current_vehicle = vehicle
		if _glb_pivot != null:
			_glb_pivot.visible = true
		if hips != null:
			hips.visible = true
		if camera != null and _has_authority():
			camera.fov = 70.0
			camera.make_current()
		if camera_pivot != null:
			camera_pivot.position = Vector3(0.0, 1.52, 0.0)
		body_collider.disabled = true
		spring_arm.add_excluded_object(vehicle.get_rid())
		global_position = vehicle.get_seat_global_position()
		visuals.rotation.y = vehicle.rotation.y
		if _has_authority():
			get_tree().call_group("network_hud", "show_toast", "قيادة %s ([L] الأضواء | [H] بوري | [R] راديو | [E] نزول)" % vehicle.vehicle_name)
	elif prev_driver == my_id and new_driver == 0 and _current_vehicle == vehicle:
		if _glb_pivot != null:
			_glb_pivot.visible = true
		if hips != null:
			hips.visible = true
		if camera != null and _has_authority():
			camera.fov = 70.0
			camera.make_current()
		if camera_pivot != null:
			camera_pivot.position = Vector3(0.0, 1.52, 0.0)
		_current_vehicle = null
		_prev_l_down = false
		spring_arm.spring_length = 4.6
		global_position = vehicle.get_safe_exit_position()
		velocity = Vector3.ZERO
		body_collider.disabled = false
		if _has_authority():
			_set_prompt("")


func _find_nearby_vehicle() -> VehicleController:
	var closest: VehicleController = null
	var best_dist := VEHICLE_INTERACT_RADIUS
	for node in get_tree().get_nodes_in_group("vehicles"):
		var veh := node as VehicleController
		if veh == null or veh.is_occupied():
			continue
		var dist := global_position.distance_to(veh.global_position)
		if dist <= best_dist:
			best_dist = dist
			closest = veh
	return closest



func _find_nearby_npc() -> NPCInteractive:
	var closest: NPCInteractive = null
	var best_dist := NPC_INTERACT_RADIUS
	for node in get_tree().get_nodes_in_group("npcs"):
		var npc := node as NPCInteractive
		if npc == null:
			continue
		var dist := global_position.distance_to(npc.global_position)
		if dist <= best_dist:
			best_dist = dist
			closest = npc
	return closest



func _find_nearby_door() -> InteractiveDoor:
	var closest: InteractiveDoor = null
	var best_dist := 3.4
	for node in get_tree().get_nodes_in_group("interactive_doors"):
		var d := node as InteractiveDoor
		if d == null:
			continue
		var dist := global_position.distance_to(d.global_position)
		if dist <= best_dist:
			best_dist = dist
			closest = d
	return closest


func _find_active_prayer_zone() -> Area3D:
	for node in get_tree().get_nodes_in_group("mosque_prayer_zones"):
		var area := node as Area3D
		if area == null or not is_instance_valid(area):
			continue
		if area.overlaps_body(self):
			return area
		# Fallback geometric bounds check inside local Area3D box
		var cs := area.get_node_or_null("ZoneShape") as CollisionShape3D
		if cs != null and cs.shape is BoxShape3D:
			var half := (cs.shape as BoxShape3D).size * 0.5
			var lp := area.to_local(global_position + Vector3(0.0, 0.85, 0.0))
			if absf(lp.x) <= half.x and absf(lp.y) <= half.y and absf(lp.z) <= half.z:
				return area
	return null


func start_mosque_prayer(zone: Area3D) -> void:
	if zone == null:
		return
	if carried_prop != null:
		drop_carried_prop()
	if is_crouching:
		set_crouch(false)
	is_praying = true
	_prayer_timer = 0.0
	_active_prayer_zone = zone
	velocity = Vector3.ZERO
	# Face the mosque Qibla wall (-Z in mosque space)
	var q_local: Vector3 = zone.get_meta("qibla_local_dir", Vector3(0.0, 0.0, -1.0))
	var q_world := (zone.global_transform.basis * q_local)
	q_world.y = 0.0
	if q_world.length_squared() > 0.01:
		q_world = q_world.normalized()
		visuals.rotation.y = atan2(-q_world.x, -q_world.z)
	if _anim_binder == null:
		_setup_anim_binder()
	if _anim_binder != null:
		if not _anim_binder.is_bound:
			_anim_binder.bind_character(self)
		if _anim_binder.has_clip("Kneeling_Pray"):
			_anim_binder.play_state("Kneeling_Pray", 0.20, 1.0)
	var m_title := str(zone.get_meta("mosque_title", "المسجد"))
	if _has_authority():
		get_tree().call_group("network_hud", "show_toast", "🕌 بدأت الصلاة في %s (اضغط [E] أو تحرك للإنهاء)" % m_title)


func stop_mosque_prayer(show_toast: bool = true) -> void:
	if not is_praying:
		return
	is_praying = false
	_prayer_timer = 0.0
	_active_prayer_zone = null
	if _anim_binder != null and _anim_binder.is_override_active():
		_anim_binder.resume_animation_tree()
	if show_toast and _has_authority():
		get_tree().call_group("network_hud", "show_toast", "🕌 تقبّل الله صلاتك")


func _find_nearby_donkey() -> AnimalAI:
	var closest: AnimalAI = null
	var best_dist := 3.2
	for node in get_tree().get_nodes_in_group("rideable_donkeys"):
		var d := node as AnimalAI
		if d == null or not is_instance_valid(d) or not d.is_rideable() or d.is_mounted():
			continue
		var dist := global_position.distance_to(d.global_position)
		if dist <= best_dist:
			best_dist = dist
			closest = d
	return closest


func mount_donkey(donkey: AnimalAI) -> bool:
	if donkey == null or not is_instance_valid(donkey) or _riding_donkey != null:
		return false
	if not donkey.mount_rider(self):
		return false
	if is_praying:
		stop_mosque_prayer(false)
	if is_crouching:
		set_crouch(false)
	if carried_prop != null:
		drop_carried_prop()
	_riding_donkey = donkey
	velocity = Vector3.ZERO
	if body_collider:
		body_collider.disabled = true
	if name_label:
		name_label.visible = false
	global_position = donkey.get_seat_mount_global_position()
	visuals.rotation.y = donkey.rotation.y
	if _anim_binder == null:
		_setup_anim_binder()
	if _anim_binder != null:
		if not _anim_binder.is_bound:
			_anim_binder.bind_character(self)
		if _anim_binder.has_clip("Ride_Donkey"):
			_anim_binder.play_state("Ride_Donkey", 0.16, 1.0)
	_donkey_rider_skeleton = _find_rider_skeleton(visuals)
	_apply_donkey_leg_straddle()
	if _has_authority():
		get_tree().call_group("network_hud", "show_toast", "🫏 ركبت %s ([WASD] توجيه | [Shift] هرولة | [E] نزول)" % donkey.donkey_name)
	return true


func dismount_donkey() -> void:
	if _riding_donkey == null:
		return
	var d_ref := _riding_donkey
	_riding_donkey = null
	if _donkey_rider_skeleton != null and is_instance_valid(_donkey_rider_skeleton):
		_donkey_rider_skeleton.clear_bones_global_pose_override()
	_donkey_rider_skeleton = null
	var exit_pos := global_position + Vector3(1.0, 0.05, 0.0)
	if is_instance_valid(d_ref):
		exit_pos = d_ref.dismount_rider()
	global_position = exit_pos
	velocity = Vector3.ZERO
	if body_collider:
		body_collider.disabled = false
	if name_label:
		name_label.visible = true
	if _anim_binder != null and _anim_binder.is_override_active():
		_anim_binder.resume_animation_tree()
	if _has_authority():
		_set_prompt("")
		get_tree().call_group("network_hud", "show_toast", "نزلت من الحمار")


func _process_riding_donkey(delta: float) -> void:
	if not is_instance_valid(_riding_donkey):
		dismount_donkey()
		return

	var kb_fwd := Input.get_axis("move_backward", "move_forward")
	var kb_steer := Input.get_axis("move_right", "move_left")
	var stick := mobile_controls.get_move_vector()
	var throttle := kb_fwd if absf(kb_fwd) > 0.05 else -stick.y
	var steer := kb_steer if absf(kb_steer) > 0.05 else -stick.x
	var trotting := Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT) or stick.length() > 0.86

	_riding_donkey.set_rider_inputs(throttle, steer, trotting)

	global_position = _riding_donkey.get_seat_mount_global_position()
	visuals.rotation.y = _riding_donkey.rotation.y
	velocity = Vector3.ZERO

	if camera_pivot != null:
		camera_pivot.position = camera_pivot.position.lerp(Vector3(0.0, 1.38, 0.0), clampf(delta * 10.0, 0.0, 1.0))

	if _anim_binder != null and _anim_binder.has_clip("Ride_Donkey") and _anim_binder.get_current_clip_name() != "Ride_Donkey":
		_anim_binder.play_state("Ride_Donkey", 0.16, 1.0)

	_apply_donkey_leg_straddle()
	_riding_donkey._update_donkey_reins()

	sync_position = global_position
	sync_yaw = visuals.rotation.y
	sync_speed = absf(_riding_donkey.get_current_speed_mps())
	sync_on_floor = true
	sync_driving = true
	sync_anim_state = "Sit"

	if _interaction_ring:
		_interaction_ring.visible = false
	mobile_controls.set_context_state(true, false, false, false)
	_set_prompt("[WASD] توجيه الحمار  |  [Shift] هرولة  |  [E] نزول")

	if Input.is_action_just_pressed("interact") or mobile_controls.consume_interact():
		_play_ui_chime()
		dismount_donkey()


func _find_rider_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for ch in node.get_children():
		var found := _find_rider_skeleton(ch)
		if found != null:
			return found
	return null


func _find_rider_bone(skel: Skeleton3D, candidates: Array[String]) -> int:
	if skel == null:
		return -1
	for cname in candidates:
		var idx := skel.find_bone(cname)
		if idx >= 0:
			return idx
	for i in range(skel.get_bone_count()):
		var bn := skel.get_bone_name(i).to_lower()
		for cname in candidates:
			if bn.ends_with(cname.to_lower()):
				return i
	return -1


func _apply_donkey_leg_straddle() -> void:
	if _donkey_rider_skeleton == null or not is_instance_valid(_donkey_rider_skeleton):
		_donkey_rider_skeleton = _find_rider_skeleton(visuals)
	var skel := _donkey_rider_skeleton
	if skel == null or _riding_donkey == null or not is_instance_valid(_riding_donkey):
		return

	# Transform between rider/donkey space (-Z forward, +Y up, -X left, +X right) and skeleton space
	var skel_basis := skel.global_transform.basis.orthonormalized()
	var rider_basis := visuals.global_transform.basis.orthonormalized()
	var rider_from_skel := rider_basis.inverse() * skel_basis
	var skel_from_rider := skel_basis.inverse() * rider_basis

	var leg_chains: Array[Dictionary] = [
		{
			"side": -1.0, # Left leg -> abduct outward toward -X
			"up": ["mixamorig_LeftUpLeg", "LeftUpLeg"] as Array[String],
			"low": ["mixamorig_LeftLeg", "LeftLeg"] as Array[String],
			"foot": ["mixamorig_LeftFoot", "LeftFoot"] as Array[String],
		},
		{
			"side": 1.0, # Right leg -> abduct outward toward +X
			"up": ["mixamorig_RightUpLeg", "RightUpLeg"] as Array[String],
			"low": ["mixamorig_RightLeg", "RightLeg"] as Array[String],
			"foot": ["mixamorig_RightFoot", "RightFoot"] as Array[String],
		},
	]

	var roll_angle := deg_to_rad(18.0)
	for chain in leg_chains:
		var side: float = float(chain["side"])
		var up_idx := _find_rider_bone(skel, chain["up"] as Array[String])
		var low_idx := _find_rider_bone(skel, chain["low"] as Array[String])
		var foot_idx := _find_rider_bone(skel, chain["foot"] as Array[String])
		if up_idx < 0 or low_idx < 0:
			continue

		# Read live Ride_Donkey animated poses before override so we layer straddle cleanly on top
		var gp_up := skel.get_bone_global_pose_no_override(up_idx)
		var gp_low := skel.get_bone_global_pose_no_override(low_idx)
		var thigh_vec := gp_low.origin - gp_up.origin
		if thigh_vec.length_squared() < 0.0001:
			continue

		# Rotate thigh outward by +/-18 deg around rider forward/Z axis (natural saddle straddle)
		var thigh_rider := (rider_from_skel * thigh_vec).normalized()
		var q_abduct := Quaternion(Vector3.BACK, side * roll_angle)
		var target_thigh_rider := (q_abduct * thigh_rider).normalized()
		# Guarantee outward leg clearance & downward saddle wrap even if clip has narrow knees
		target_thigh_rider.x = side * maxf(absf(target_thigh_rider.x), 0.36)
		target_thigh_rider.y = minf(target_thigh_rider.y, -0.52)
		target_thigh_rider = target_thigh_rider.normalized()

		var target_thigh_skel := (skel_from_rider * target_thigh_rider).normalized()
		var q_up_delta := Quaternion(thigh_vec.normalized(), target_thigh_skel)
		var new_up_basis := (Basis(q_up_delta) * gp_up.basis).orthonormalized()
		var new_gp_up := Transform3D(new_up_basis, gp_up.origin)
		skel.set_bone_global_pose_override(up_idx, new_gp_up, 1.0, true)

		# Position lower leg (knee) at the exact rotated end of the abducted thigh,
		# and angle shin gently downward along the donkey's flank so boots hang cleanly beside the blanket
		var new_low_origin := gp_up.origin + (Basis(q_up_delta) * thigh_vec)
		if foot_idx >= 0:
			var gp_foot := skel.get_bone_global_pose_no_override(foot_idx)
			var shin_vec := gp_foot.origin - gp_low.origin
			if shin_vec.length_squared() > 0.0001:
				var cur_shin_dir := (Basis(q_up_delta) * shin_vec).normalized()
				var target_shin_rider := Vector3(side * 0.16, -0.94, 0.30).normalized()
				var target_shin_skel := (skel_from_rider * target_shin_rider).normalized()
				var q_low_delta := Quaternion(cur_shin_dir, target_shin_skel)
				var new_low_basis := (Basis(q_low_delta) * Basis(q_up_delta) * gp_low.basis).orthonormalized()
				var new_gp_low := Transform3D(new_low_basis, new_low_origin)
				skel.set_bone_global_pose_override(low_idx, new_gp_low, 1.0, true)


func get_hand_global_positions() -> Dictionary:
	if _donkey_rider_skeleton == null or not is_instance_valid(_donkey_rider_skeleton):
		_donkey_rider_skeleton = _find_rider_skeleton(visuals)
	var skel := _donkey_rider_skeleton
	if skel == null:
		return {}
	var l_idx := _find_rider_bone(skel, ["mixamorig_LeftHand", "LeftHand", "mixamorig_LeftHandIndex1"])
	var r_idx := _find_rider_bone(skel, ["mixamorig_RightHand", "RightHand", "mixamorig_RightHandIndex1"])
	if l_idx < 0 or r_idx < 0:
		return {}
	var l_world := skel.global_transform * skel.get_bone_global_pose(l_idx).origin
	var r_world := skel.global_transform * skel.get_bone_global_pose(r_idx).origin
	return {"left": l_world, "right": r_world}


func _setup_player_glb_model() -> void:
	var path := CharacterModelLoader.get_model_path_by_index(character_index)
	if path.is_empty():
		path = CharacterModelLoader.find_model_path("Man")
	if path.is_empty():
		return
	var pivot := CharacterModelLoader.instantiate_normalized(path, 1.75, true)
	if pivot == null:
		return
	if _glb_pivot != null and is_instance_valid(_glb_pivot):
		_glb_pivot.queue_free()
	_glb_pivot = pivot
	_loaded_character_index = character_index
	visuals.add_child(_glb_pivot)
	if hips:
		hips.visible = false
		hips.queue_free()
		hips = null


func _setup_anim_binder() -> void:
	_anim_binder = CharacterAnimationAutoBinder.find_on_character(self)
	if _anim_binder == null:
		_anim_binder = CharacterAnimationAutoBinder.new()
		_anim_binder.name = "CharacterAnimationAutoBinder"
		_anim_binder.auto_bind_on_ready = false
		add_child(_anim_binder)
	if _glb_pivot != null:
		_anim_binder.bind_character(self)


func trigger_random_jump_animation(is_running: bool = false) -> String:
	if _anim_binder == null:
		_setup_anim_binder()
	if _anim_binder == null:
		return ""
	if not _anim_binder.is_bound:
		_anim_binder.bind_character(self)

	var available: Array[String] = []
	for cname in JUMP_VARIATIONS:
		if _anim_binder.has_clip(cname):
			available.append(cname)
	if available.is_empty():
		return ""

	var pool: Array[String] = []
	for cname in available:
		if cname != last_jump_clip or available.size() == 1:
			pool.append(cname)
	if is_running and pool.has("Jump_Running"):
		# Slight natural bias toward Jump_Running when sprinting while keeping all 4 variations active
		pool.append("Jump_Running")

	var chosen: String = pool[randi() % pool.size()]
	last_jump_clip = chosen
	_jump_anim_active = true
	_anim_binder.play_one_shot(chosen, 0.08, 1.08, false)
	return chosen


func _update_procedural_animation(delta: float, speed: float, grounded: bool, driving: bool, seated: bool = false) -> void:
	if _glb_pivot != null:
		if not driving and not seated and grounded and speed > 0.35 and _slide_timer <= 0.0:
			var is_sprinting := speed > WALK_SPEED + 1.1
			_anim_time += delta * (speed * 2.15)
			var step_index := floori(_anim_time / PI)
			if step_index != _last_step_index:
				_last_step_index = step_index
				_play_footstep(is_sprinting)
		# Keep CharacterAnimationAutoBinder in full control while jump/falling/landing/swim override is active
		if _anim_binder != null and _anim_binder.is_override_active():
			if grounded and speed > 1.8 and _anim_binder.get_current_clip_name() == "Landing":
				_landing_anim_timer = 0.0
				_anim_binder.resume_animation_tree()
			else:
				return
		if _glb_pivot.has_meta("character_animator"):
			var anim := _glb_pivot.get_meta("character_animator") as CharacterAnimator
			if anim != null:
				var seated_now := driving or seated or (_riding_bus_passenger != null)
				_glb_pivot.position.y = -0.82 if seated_now else 0.0
				var slide_amt := clampf(_slide_timer / 0.35, 0.0, 1.0)
				var carry_amt := 1.0 if (carried_prop != null and is_instance_valid(carried_prop)) else 0.0
				var bend_amt := sin(clampf(_pickup_bend_timer / 0.36, 0.0, 1.0) * PI)
				anim.update_animation(delta, speed, seated_now, driving, not grounded and not seated_now, _crouch_amount, slide_amt, carry_amt, bend_amt)
				return
		return
	if hips == null:
		return

	if driving:
		hips.position.y = lerpf(hips.position.y, 0.62, clampf(delta * 12.0, 0.0, 1.0))
		hips.rotation.x = lerpf(hips.rotation.x, deg_to_rad(-6.0), clampf(delta * 10.0, 0.0, 1.0))
		left_leg_pivot.rotation.x = lerpf(left_leg_pivot.rotation.x, deg_to_rad(78.0), clampf(delta * 12.0, 0.0, 1.0))
		right_leg_pivot.rotation.x = lerpf(right_leg_pivot.rotation.x, deg_to_rad(78.0), clampf(delta * 12.0, 0.0, 1.0))
		left_arm_pivot.rotation.x = lerpf(left_arm_pivot.rotation.x, deg_to_rad(48.0), clampf(delta * 12.0, 0.0, 1.0))
		right_arm_pivot.rotation.x = lerpf(right_arm_pivot.rotation.x, deg_to_rad(48.0), clampf(delta * 12.0, 0.0, 1.0))
		left_arm_pivot.rotation.z = lerpf(left_arm_pivot.rotation.z, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		right_arm_pivot.rotation.z = lerpf(right_arm_pivot.rotation.z, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		return

	if not grounded:
		hips.position.y = lerpf(hips.position.y, BASE_HIPS_Y, clampf(delta * 10.0, 0.0, 1.0))
		hips.rotation.x = lerpf(hips.rotation.x, deg_to_rad(-6.0), clampf(delta * 10.0, 0.0, 1.0))
		left_leg_pivot.rotation.x = lerpf(left_leg_pivot.rotation.x, 0.42, clampf(delta * 10.0, 0.0, 1.0))
		right_leg_pivot.rotation.x = lerpf(right_leg_pivot.rotation.x, -0.32, clampf(delta * 10.0, 0.0, 1.0))
		left_arm_pivot.rotation.x = lerpf(left_arm_pivot.rotation.x, 0.55, clampf(delta * 10.0, 0.0, 1.0))
		right_arm_pivot.rotation.x = lerpf(right_arm_pivot.rotation.x, 0.55, clampf(delta * 10.0, 0.0, 1.0))
		left_arm_pivot.rotation.z = lerpf(left_arm_pivot.rotation.z, -0.32, clampf(delta * 10.0, 0.0, 1.0))
		right_arm_pivot.rotation.z = lerpf(right_arm_pivot.rotation.z, 0.32, clampf(delta * 10.0, 0.0, 1.0))
		return

	if speed > 0.35:
		var is_sprinting := speed > WALK_SPEED + 1.1
		_anim_time += delta * (speed * 2.15)
		var step_index := floori(_anim_time / PI)
		if step_index != _last_step_index:
			_last_step_index = step_index
			_play_footstep(is_sprinting)

		var swing_amp := clampf(speed / SPRINT_SPEED, 0.28, 1.0) * (0.95 if is_sprinting else 0.68)
		var swing := sin(_anim_time) * swing_amp

		left_leg_pivot.rotation.x = swing
		right_leg_pivot.rotation.x = -swing
		left_arm_pivot.rotation.x = -swing * 0.85
		right_arm_pivot.rotation.x = swing * 0.85
		left_arm_pivot.rotation.z = lerpf(left_arm_pivot.rotation.z, -0.06, clampf(delta * 10.0, 0.0, 1.0))
		right_arm_pivot.rotation.z = lerpf(right_arm_pivot.rotation.z, 0.06, clampf(delta * 10.0, 0.0, 1.0))

		var bob := absf(cos(_anim_time)) * (0.065 if is_sprinting else 0.035)
		hips.position.y = BASE_HIPS_Y + bob
		hips.rotation.x = lerpf(hips.rotation.x, deg_to_rad(-8.5 if is_sprinting else -3.0), clampf(delta * 10.0, 0.0, 1.0))
	else:
		_idle_time += delta
		var breath := sin(_idle_time * 2.2) * 0.012
		hips.position.y = lerpf(hips.position.y, BASE_HIPS_Y + breath, clampf(delta * 10.0, 0.0, 1.0))
		hips.rotation.x = lerpf(hips.rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		left_leg_pivot.rotation.x = lerpf(left_leg_pivot.rotation.x, 0.0, clampf(delta * 12.0, 0.0, 1.0))
		right_leg_pivot.rotation.x = lerpf(right_leg_pivot.rotation.x, 0.0, clampf(delta * 12.0, 0.0, 1.0))
		left_arm_pivot.rotation.x = lerpf(left_arm_pivot.rotation.x, 0.0, clampf(delta * 12.0, 0.0, 1.0))
		right_arm_pivot.rotation.x = lerpf(right_arm_pivot.rotation.x, 0.0, clampf(delta * 12.0, 0.0, 1.0))
		left_arm_pivot.rotation.z = lerpf(left_arm_pivot.rotation.z, -0.05, clampf(delta * 10.0, 0.0, 1.0))
		right_arm_pivot.rotation.z = lerpf(right_arm_pivot.rotation.z, 0.05, clampf(delta * 10.0, 0.0, 1.0))


func _setup_footstep_audio() -> void:
	_footstep_player = AudioStreamPlayer3D.new()
	_footstep_player.name = "FootstepPlayer"
	_footstep_player.max_distance = 22.0
	_footstep_player.unit_size = 2.5
	_footstep_player.volume_db = -8.0
	add_child(_footstep_player)

	_action_sfx_player = AudioStreamPlayer3D.new()
	_action_sfx_player.name = "ActionSFXPlayer"
	_action_sfx_player.max_distance = 18.0
	_action_sfx_player.volume_db = -6.0
	add_child(_action_sfx_player)


func _play_footstep(sprinting: bool) -> void:
	if _footstep_player == null:
		return
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr == null:
		return
	var on_asphalt := _is_on_asphalt(global_position)
	var step_stream: AudioStream = audio_mgr.get_random_footstep_stream(on_asphalt)
	if step_stream == null:
		return
	_footstep_player.stream = step_stream
	_footstep_player.pitch_scale = randf_range(1.02, 1.15) if sprinting else randf_range(0.90, 1.04)
	_footstep_player.volume_db = -5.5 if sprinting else -9.0
	_footstep_player.play()


func _play_jump_whoosh() -> void:
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if _action_sfx_player and audio_mgr and audio_mgr.jump_whoosh_stream:
		_action_sfx_player.stream = audio_mgr.jump_whoosh_stream
		_action_sfx_player.pitch_scale = randf_range(0.96, 1.06)
		_action_sfx_player.play()


func _play_land_thud() -> void:
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if _action_sfx_player and audio_mgr and audio_mgr.land_thud_stream:
		_action_sfx_player.stream = audio_mgr.land_thud_stream
		_action_sfx_player.pitch_scale = randf_range(0.94, 1.05)
		_action_sfx_player.play()


func _play_ui_chime() -> void:
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr:
		audio_mgr.play_ui_chime()


func _is_on_asphalt(pos: Vector3) -> bool:
	var dist_center := Vector2(pos.x, pos.z).length()
	if dist_center >= 5.0 and dist_center <= 13.5:
		return true
	return absf(pos.x) < 6.4 or absf(pos.z) < 6.4


func _setup_interaction_ring() -> void:
	var vfx_mgr := get_node_or_null("/root/VFXManager")
	if vfx_mgr == null:
		return
	_interaction_ring = vfx_mgr.create_interaction_ring()
	_interaction_ring.top_level = true
	add_child(_interaction_ring)


func _update_interaction_ring(delta: float, nearby_vehicle: VehicleController, nearby_npc: NPCInteractive) -> void:
	if _interaction_ring == null:
		return
	var target: Node3D = nearby_vehicle if nearby_vehicle != null else nearby_npc
	if target == null:
		_interaction_ring.visible = false
		return

	_ring_pulse_time += delta * 4.2
	_interaction_ring.visible = true
	_interaction_ring.global_position = Vector3(target.global_position.x, 0.08, target.global_position.z)
	_interaction_ring.rotate_y(delta * 1.4)
	var base_scale := 1.75 if nearby_vehicle != null else 0.90
	var pulse := base_scale * (1.0 + 0.08 * sin(_ring_pulse_time))
	_interaction_ring.scale = Vector3(pulse, 0.25, pulse)
	var mat := _interaction_ring.material_override as StandardMaterial3D
	if mat:
		var col := Color(1.0, 0.80, 0.24, 0.85) if nearby_vehicle != null else Color(0.32, 0.92, 0.56, 0.85)
		mat.albedo_color = col
		mat.emission = col


func _rotate_camera(relative: Vector2, sensitivity: float) -> void:
	camera_pivot.rotate_y(-relative.x * sensitivity)
	_pitch = clampf(_pitch - relative.y * sensitivity, MIN_PITCH_RAD, MAX_PITCH_RAD)
	spring_arm.rotation.x = _pitch


func _handle_world_interact() -> void:
	var nearby_door := _find_nearby_door()
	if nearby_door != null:
		get_tree().call_group("network_hud", "show_toast", nearby_door.toggle_open())
		return
	if interact_ray and interact_ray.is_colliding():
		var collider := interact_ray.get_collider()
		if collider is InteractiveDoor:
			get_tree().call_group("network_hud", "show_toast", (collider as InteractiveDoor).toggle_open())
			return
		if collider and collider.has_meta("interactive_door"):
			var door_ref := collider.get_meta("interactive_door") as InteractiveDoor
			if door_ref != null:
				get_tree().call_group("network_hud", "show_toast", door_ref.toggle_open())
				return
		if collider and collider.has_meta("interact_message"):
			var msg := str(collider.get_meta("interact_message"))
			get_tree().call_group("network_hud", "show_toast", msg)
			return
	get_tree().call_group("network_hud", "show_toast", "Al-Azhari Neighborhood - Khartoum")


func _set_prompt(text: String) -> void:
	if text == _last_prompt:
		return
	_last_prompt = text
	get_tree().call_group("network_hud", "set_context_prompt", text)


func _get_local_peer_id() -> int:
	if str(name).is_valid_int():
		return str(name).to_int()
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1


func _apply_player_color() -> void:
	if not is_node_ready() or torso_mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = player_color
	mat.roughness = 0.8
	torso_mesh.material_override = mat
	if left_sleeve_mesh:
		left_sleeve_mesh.material_override = mat
	if right_sleeve_mesh:
		right_sleeve_mesh.material_override = mat


func _setup_swim_splash() -> void:
	var gp := GPUParticles3D.new()
	gp.name = "SwimSplashParticles"
	gp.amount = 28
	gp.lifetime = 0.65
	gp.emitting = false
	gp.one_shot = false
	gp.local_coords = false

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pmat.emission_ring_radius = 0.52
	pmat.emission_ring_inner_radius = 0.18
	pmat.emission_ring_height = 0.08
	pmat.direction = Vector3(0.0, 1.0, 0.0)
	pmat.spread = 52.0
	pmat.initial_velocity_min = 0.6
	pmat.initial_velocity_max = 1.6
	pmat.gravity = Vector3(0.0, -3.2, 0.0)
	pmat.scale_min = 0.08
	pmat.scale_max = 0.22
	pmat.color = Color(0.92, 0.97, 1.0, 0.78)
	gp.process_material = pmat

	var draw_mesh := SphereMesh.new()
	draw_mesh.radius = 0.14
	draw_mesh.height = 0.22
	draw_mesh.radial_segments = 8
	draw_mesh.rings = 4
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.92, 0.97, 1.0, 0.72)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.roughness = 0.25
	draw_mesh.material = dmat
	gp.draw_pass_1 = draw_mesh
	gp.position = Vector3(0.0, 1.15, 0.0)
	add_child(gp)
	_swim_splash = gp


func enter_water(surface_y: float, zone: Area3D = null) -> void:
	_water_surface_y = surface_y
	if zone != null and not _active_water_zones.has(zone):
		_active_water_zones.append(zone)
	_in_water_zone = true


func exit_water(zone: Area3D = null) -> void:
	if zone != null:
		_active_water_zones.erase(zone)
	_in_water_zone = not _active_water_zones.is_empty()
	if not _in_water_zone and is_swimming:
		_exit_swimming_state()


func _update_water_swimming_state() -> void:
	var inside := not _active_water_zones.is_empty()
	if not inside:
		for wz in get_tree().get_nodes_in_group("nile_water_zones"):
			var area := wz as Area3D
			if area != null and area.overlaps_body(self):
				_active_water_zones.append(area)
				_water_surface_y = float(area.get_meta("water_surface_y", 0.20))
				inside = true
				break
	_in_water_zone = inside

	if not _in_water_zone:
		if is_swimming:
			_exit_swimming_state()
		return

	var chest_y := global_position.y + SWIM_CHEST_HEIGHT
	if not is_swimming:
		if chest_y < _water_surface_y:
			_enter_swimming_state()
	else:
		# Smoothly exit swimming when wading onto sloped sandy island beaches or riverbanks
		if is_on_floor() and (global_position.y + 1.04) >= _water_surface_y:
			_exit_swimming_state()


func _enter_swimming_state() -> void:
	is_swimming = true
	is_crouching = false
	_crouch_amount = 0.0
	_slide_timer = 0.0
	_jump_anim_active = false
	_landing_anim_timer = 0.0
	_swim_cycle = 0.0
	_swim_tilt = 0.0
	_swim_using_clip = false
	velocity.y = clampf(velocity.y * 0.35, -3.2, 2.0)

	if _glb_pivot != null:
		_glb_pivot.rotation.x = 0.0
		_glb_pivot.position.y = 0.0
		_swim_skeleton = _find_node_of_type_skeleton(_glb_pivot)
		_swim_anim_tree = _find_node_of_type_anim_tree(_glb_pivot)
		_swim_anim_player = _find_node_of_type_anim_player(_glb_pivot)

		if _anim_binder == null:
			_setup_anim_binder()
		if _anim_binder != null and not _anim_binder.is_bound:
			_anim_binder.bind_character(self)

		if _anim_binder != null and (_anim_binder.has_clip("Swimming") or _anim_binder.has_clip("Treading_Water")):
			_swim_using_clip = true
			var initial_clip := "Treading_Water" if _anim_binder.has_clip("Treading_Water") else "Swimming"
			_anim_binder.play_state(initial_clip, 0.16, 1.0)
		else:
			if _swim_anim_tree != null:
				_swim_anim_tree.active = false
			if _swim_anim_player != null:
				var swim_clip := _find_swim_clip_name(_swim_anim_player)
				if swim_clip != "":
					_swim_using_clip = true
					_swim_anim_player.play(swim_clip)

	if _swim_splash != null:
		_swim_splash.emitting = true


func _exit_swimming_state() -> void:
	is_swimming = false
	_swim_tilt = 0.0
	if _swim_splash != null:
		_swim_splash.emitting = false
	if _anim_binder != null and _anim_binder.is_override_active():
		_anim_binder.resume_animation_tree()
	elif _swim_anim_player != null and is_instance_valid(_swim_anim_player) and _swim_using_clip:
		_swim_anim_player.stop()
	_swim_using_clip = false
	if _swim_skeleton != null and is_instance_valid(_swim_skeleton):
		_swim_skeleton.clear_bones_global_pose_override()
		_swim_skeleton.reset_bone_poses()
	if _glb_pivot != null:
		_glb_pivot.rotation.x = 0.0
		_glb_pivot.position.y = 0.0
	if _swim_anim_tree != null and is_instance_valid(_swim_anim_tree):
		_swim_anim_tree.active = true


func _process_swimming(delta: float) -> void:
	var kb_input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var stick_input := mobile_controls.get_move_vector()
	var input_vec := kb_input if kb_input.length_squared() > 0.01 else stick_input
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()

	var fast_swim := Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT) or stick_input.length() > 0.86
	var target_speed := FAST_SWIM_SPEED if fast_swim else SWIM_SPEED

	var cam_basis := camera_pivot.global_transform.basis
	var forward := -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()
	var move_dir := (right * input_vec.x - forward * input_vec.y)
	if move_dir.length_squared() > 0.001:
		move_dir = move_dir.normalized()

	var target_vx := move_dir.x * target_speed
	var target_vz := move_dir.z * target_speed
	velocity.x = move_toward(velocity.x, target_vx, 10.5 * delta)
	velocity.z = move_toward(velocity.z, target_vz, 10.5 * delta)

	# Smooth buoyancy keeping head & shoulders naturally above water_surface_y when idle
	var float_target_y := _water_surface_y - SWIM_FLOAT_OFFSET
	var dive_down := Input.is_physical_key_pressed(KEY_C) or Input.is_key_pressed(KEY_CTRL)
	var surface_hold := Input.is_action_pressed("jump") or Input.is_physical_key_pressed(KEY_SPACE) or mobile_controls.consume_jump()
	var jump_just := Input.is_action_just_pressed("jump")

	if dive_down:
		velocity.y = lerpf(velocity.y, -3.4, clampf(delta * 6.5, 0.0, 1.0))
	elif jump_just and global_position.y >= float_target_y - 0.42:
		# Crisp vault impulse to climb out onto docks, rocks, or sandy banks
		velocity.y = 7.4
	elif surface_hold:
		velocity.y = lerpf(velocity.y, 4.2, clampf(delta * 7.0, 0.0, 1.0))
	else:
		var bob := 0.045 * sin(_swim_cycle * 1.6)
		var depth_err := (float_target_y + bob) - global_position.y
		var target_vy := clampf(depth_err * 6.0, -3.2, 4.5)
		velocity.y = lerpf(velocity.y, target_vy, clampf(delta * 5.5, 0.0, 1.0))

	if move_dir.length_squared() > 0.001:
		var target_yaw := atan2(-move_dir.x, -move_dir.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_yaw, clampf(delta * 8.5, 0.0, 1.0))

	move_and_slide()

	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if _swim_splash != null:
		_swim_splash.position.y = clampf(_water_surface_y - global_position.y, 0.2, 1.65)
		_swim_splash.emitting = horiz_speed > 0.45 or absf(velocity.y) > 1.2

	sync_position = global_position
	sync_yaw = visuals.rotation.y
	sync_speed = horiz_speed
	sync_on_floor = false
	sync_driving = false
	sync_anim_state = "Jump"

	_update_swimming_animation(delta, horiz_speed, fast_swim, dive_down)
	if _interaction_ring:
		_interaction_ring.visible = false
	_set_prompt("🏊 سباحة في النيل: [WASD] حركة  |  [Shift] سباحة سريعة  |  [Space] صعود / خروج للشاطئ  |  [Ctrl / C] غوص")


func _update_swimming_animation(delta: float, horiz_speed: float, fast_swim: bool, dive_down: bool = false) -> void:
	var moving := horiz_speed > 0.35
	var cycle_rate := (8.4 if fast_swim else 6.0) if moving else 3.2
	_swim_cycle += delta * cycle_rate

	if _swim_using_clip:
		if _anim_binder != null and _anim_binder.is_bound:
			if dive_down and _anim_binder.has_clip("Diving"):
				_anim_binder.play_state("Diving", 0.16, 1.15)
			elif moving and _anim_binder.has_clip("Swimming"):
				_anim_binder.play_state("Swimming", 0.16, 1.35 if fast_swim else 1.0)
			elif _anim_binder.has_clip("Treading_Water"):
				_anim_binder.play_state("Treading_Water", 0.18, 1.0)
			elif _anim_binder.has_clip("Swimming"):
				_anim_binder.play_state("Swimming", 0.18, 0.75)
		return

	# Tilt forward horizontally (~75 deg) while swimming, return upright (0 deg) when treading water
	var target_tilt := deg_to_rad(-75.0) if moving else 0.0
	_swim_tilt = lerpf(_swim_tilt, target_tilt, clampf(delta * 6.5, 0.0, 1.0))

	if _glb_pivot != null:
		_glb_pivot.rotation.x = _swim_tilt
		_glb_pivot.position.y = lerpf(_glb_pivot.position.y, 0.92 if moving else 0.0, clampf(delta * 6.5, 0.0, 1.0))

	if _swim_skeleton != null and is_instance_valid(_swim_skeleton):
		var s := sin(_swim_cycle)
		var c := cos(_swim_cycle)
		var l_arm := _find_bone_any(_swim_skeleton, ["mixamorig_LeftArm", "LeftArm"])
		var r_arm := _find_bone_any(_swim_skeleton, ["mixamorig_RightArm", "RightArm"])
		var l_fore := _find_bone_any(_swim_skeleton, ["mixamorig_LeftForeArm", "LeftForeArm"])
		var r_fore := _find_bone_any(_swim_skeleton, ["mixamorig_RightForeArm", "RightForeArm"])
		var l_up := _find_bone_any(_swim_skeleton, ["mixamorig_LeftUpLeg", "LeftUpLeg"])
		var r_up := _find_bone_any(_swim_skeleton, ["mixamorig_RightUpLeg", "RightUpLeg"])
		var l_leg := _find_bone_any(_swim_skeleton, ["mixamorig_LeftLeg", "LeftLeg"])
		var r_leg := _find_bone_any(_swim_skeleton, ["mixamorig_RightLeg", "RightLeg"])

		if moving:
			# Alternating freestyle arm strokes + flutter-kick legs
			if l_arm >= 0:
				_swim_skeleton.set_bone_pose_rotation(l_arm, Quaternion.from_euler(Vector3(deg_to_rad(-95.0 + s * 68.0), 0.0, deg_to_rad(18.0))))
			if r_arm >= 0:
				_swim_skeleton.set_bone_pose_rotation(r_arm, Quaternion.from_euler(Vector3(deg_to_rad(-95.0 - s * 68.0), 0.0, deg_to_rad(-18.0))))
			if l_fore >= 0:
				_swim_skeleton.set_bone_pose_rotation(l_fore, Quaternion.from_euler(Vector3(deg_to_rad(-28.0 - maxf(0.0, c) * 35.0), 0.0, 0.0)))
			if r_fore >= 0:
				_swim_skeleton.set_bone_pose_rotation(r_fore, Quaternion.from_euler(Vector3(deg_to_rad(-28.0 - maxf(0.0, -c) * 35.0), 0.0, 0.0)))
			if l_up >= 0:
				_swim_skeleton.set_bone_pose_rotation(l_up, Quaternion.from_euler(Vector3(deg_to_rad(sin(_swim_cycle * 1.6) * 28.0), 0.0, 0.0)))
			if r_up >= 0:
				_swim_skeleton.set_bone_pose_rotation(r_up, Quaternion.from_euler(Vector3(deg_to_rad(-sin(_swim_cycle * 1.6) * 28.0), 0.0, 0.0)))
			if l_leg >= 0:
				_swim_skeleton.set_bone_pose_rotation(l_leg, Quaternion.from_euler(Vector3(deg_to_rad(16.0 + maxf(0.0, cos(_swim_cycle * 1.6)) * 22.0), 0.0, 0.0)))
			if r_leg >= 0:
				_swim_skeleton.set_bone_pose_rotation(r_leg, Quaternion.from_euler(Vector3(deg_to_rad(16.0 + maxf(0.0, -cos(_swim_cycle * 1.6)) * 22.0), 0.0, 0.0)))
		else:
			# Upright treading-water sculling arms & gentle bicycle kicks
			if l_arm >= 0:
				_swim_skeleton.set_bone_pose_rotation(l_arm, Quaternion.from_euler(Vector3(deg_to_rad(-24.0 + s * 16.0), 0.0, deg_to_rad(42.0 + c * 18.0))))
			if r_arm >= 0:
				_swim_skeleton.set_bone_pose_rotation(r_arm, Quaternion.from_euler(Vector3(deg_to_rad(-24.0 - s * 16.0), 0.0, deg_to_rad(-42.0 - c * 18.0))))
			if l_fore >= 0:
				_swim_skeleton.set_bone_pose_rotation(l_fore, Quaternion.from_euler(Vector3(deg_to_rad(-35.0), 0.0, 0.0)))
			if r_fore >= 0:
				_swim_skeleton.set_bone_pose_rotation(r_fore, Quaternion.from_euler(Vector3(deg_to_rad(-35.0), 0.0, 0.0)))
			if l_up >= 0:
				_swim_skeleton.set_bone_pose_rotation(l_up, Quaternion.from_euler(Vector3(deg_to_rad(-26.0 + s * 22.0), 0.0, 0.0)))
			if r_up >= 0:
				_swim_skeleton.set_bone_pose_rotation(r_up, Quaternion.from_euler(Vector3(deg_to_rad(-26.0 - s * 22.0), 0.0, 0.0)))
			if l_leg >= 0:
				_swim_skeleton.set_bone_pose_rotation(l_leg, Quaternion.from_euler(Vector3(deg_to_rad(36.0 + c * 20.0), 0.0, 0.0)))
			if r_leg >= 0:
				_swim_skeleton.set_bone_pose_rotation(r_leg, Quaternion.from_euler(Vector3(deg_to_rad(36.0 - c * 20.0), 0.0, 0.0)))
	elif hips != null:
		hips.rotation.x = _swim_tilt
		var swing := sin(_swim_cycle) * (0.95 if moving else 0.42)
		left_arm_pivot.rotation.x = -1.2 + swing
		right_arm_pivot.rotation.x = -1.2 - swing
		left_leg_pivot.rotation.x = -swing * 0.6
		right_leg_pivot.rotation.x = swing * 0.6


func _find_swim_clip_name(ap: AnimationPlayer) -> String:
	for aname in ap.get_animation_list():
		var low := String(aname).to_lower()
		if "swim" in low or "tread" in low:
			return String(aname)
	return ""


func _find_bone_any(skel: Skeleton3D, names: Array[String]) -> int:
	for bn in names:
		var idx := skel.find_bone(bn)
		if idx >= 0:
			return idx
	return -1


func _find_node_of_type_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var f := _find_node_of_type_skeleton(c)
		if f != null:
			return f
	return null


func _find_node_of_type_anim_tree(node: Node) -> AnimationTree:
	if node is AnimationTree:
		return node as AnimationTree
	for c in node.get_children():
		var f := _find_node_of_type_anim_tree(c)
		if f != null:
			return f
	return null


func _find_node_of_type_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var f := _find_node_of_type_anim_player(c)
		if f != null:
			return f
	return null
