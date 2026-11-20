extends CharacterBody3D
class_name VehicleController

## Arcade-physics CharacterBody3D vehicle controller for Khartoum's Raksha & Boks.
## Full SFX (engine pitch 0.80..2.0, horn, skid, door/ignition, 3D radio + static click)
## and VFX (exhaust smoke, sand tire dust, SpotLight3D headlights, bright brake lights).

@export var vehicle_name: String = "Raksha"
@export var max_speed: float = 15.5
@export var reverse_speed: float = 6.5
@export var acceleration: float = 15.0
@export var deceleration: float = 10.0
@export var brake_strength: float = 24.0
@export var turn_speed: float = 3.0
@export var is_three_wheeler: bool = false
@export var driver_seat_offset: Vector3 = Vector3(0.0, 0.42, -0.15)
@export var passenger_seat_offset: Vector3 = Vector3(0.0, 0.22, 0.52)
@export var exit_offset: Vector3 = Vector3(-1.7, 0.25, 0.0)
@export var camera_distance: float = 5.8
@export var max_fuel_liters: float = 60.0
@export var fuel_liters: float = 48.0
@export var fuel_consumption_per_sec: float = 0.28
@export var is_bus: bool = false
@export var pack_model_scene: PackedScene = null
@export var pack_model_path: String = ""
@export var pack_target_length: float = 0.0
@export var pack_paint_color: Color = Color(0.96, 0.95, 0.92, 1.0)
@export var pack_stripe_color: Color = Color(0.14, 0.42, 0.72, 1.0)

@export var driver_peer_id: int = 0
@export var passenger_peer_id: int = 0
@export var bus_ai_active: bool = false
@export var ai_autopilot_active: bool = false
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var sync_speed: float = 0.0
@export var sync_steer: float = 0.0

@onready var body_visuals: Node3D = $BodyVisuals

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _current_speed: float = 0.0
var _current_steer: float = 0.0
var _input_throttle: float = 0.0
var _input_steer: float = 0.0
var _wheel_spin_nodes: Array[Node3D] = []
var _front_steer_pivots: Array[Node3D] = []

var _engine_player: AudioStreamPlayer3D = null
var _horn_player: AudioStreamPlayer3D = null
var _radio_player: AudioStreamPlayer3D = null
var _skid_player: AudioStreamPlayer3D = null
var _door_player: AudioStreamPlayer3D = null
var _ignition_player: AudioStreamPlayer3D = null
var _radio_click_player: AudioStreamPlayer3D = null

var _exhaust_smoke: GPUParticles3D = null
var _dust_left: GPUParticles3D = null
var _dust_right: GPUParticles3D = null
var _headlights: Array[SpotLight3D] = []
var _headlight_mats: Array[StandardMaterial3D] = []
var _taillight_mats: Array[StandardMaterial3D] = []
var _reverselight_mats: Array[StandardMaterial3D] = []
var _steering_wheel_node: Node3D = null
var seat_manager: VehicleSeatManager = null
var visual_ground_offset: float = 0.0
var _handbrake_down: bool = false
var headlights_on: bool = false

var _radio_track_idx: int = -1
var _horn_cooldown: float = 0.0
var _spawn_position: Vector3 = Vector3.ZERO
var _spawn_yaw: float = 0.0
var _attached_vehicle_glb: Node3D = null


func _ready() -> void:
	add_to_group("vehicles")
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.35
	acceleration = maxf(acceleration, 18.0)
	max_speed = maxf(max_speed, 16.0)
	reverse_speed = maxf(reverse_speed, 7.5)
	turn_speed = maxf(turn_speed, 3.0)

	# Align vehicle box collider bottom face cleanly to y = 0.02m ground clearance (never sink -0.25m)
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		var bs := col.shape as BoxShape3D
		col.position.y = bs.size.y * 0.5 + 0.02
	if absf(global_position.y) < 0.25:
		global_position.y = 0.0

	_spawn_position = global_position
	_spawn_yaw = rotation.y
	sync_position = global_position
	sync_yaw = rotation.y

	var pack_res := VehiclePackSetup.apply_to_vehicle(self)
	if not (pack_res["wheel_spin_nodes"] as Array).is_empty():
		_wheel_spin_nodes.clear()
		for w in pack_res["wheel_spin_nodes"]:
			_wheel_spin_nodes.append(w)
	if not (pack_res["front_steer_pivots"] as Array).is_empty():
		_front_steer_pivots.clear()
		for fp in pack_res["front_steer_pivots"]:
			_front_steer_pivots.append(fp)
	for hm in pack_res["headlight_mats"]:
		_headlight_mats.append(hm)
	for tm in pack_res["taillight_mats"]:
		_taillight_mats.append(tm)
	for rm in pack_res["reverselight_mats"]:
		_reverselight_mats.append(rm)
	_steering_wheel_node = pack_res["steering_wheel"]

	_collect_wheel_nodes()
	_align_visuals_to_ground()
	seat_manager = get_node_or_null("VehicleSeatManager") as VehicleSeatManager
	if seat_manager != null:
		seat_manager.refresh_mappings()
	_setup_audio()
	_setup_vfx()


func _exit_tree() -> void:
	for p in [_engine_player, _horn_player, _radio_player, _skid_player, _door_player, _ignition_player, _radio_click_player]:
		if p != null:
			p.stop()
			p.stream = null


func reset_vehicle() -> void:
	exit_all_passengers()
	driver_peer_id = 0
	set_multiplayer_authority(1)
	_current_speed = 0.0
	_current_steer = 0.0
	_input_throttle = 0.0
	_input_steer = 0.0
	velocity = Vector3.ZERO
	global_position = _spawn_position
	rotation = Vector3(0.0, _spawn_yaw, 0.0)
	sync_position = _spawn_position
	sync_yaw = _spawn_yaw
	sync_speed = 0.0
	sync_steer = 0.0
	_radio_track_idx = -1
	headlights_on = false
	if _engine_player and _engine_player.playing:
		_engine_player.stop()
	if _skid_player and _skid_player.playing:
		_skid_player.stop()
	if _radio_player and _radio_player.playing:
		_radio_player.stop()
	_update_vfx(0.0, 0.0, false)


func set_drive_inputs(throttle: float, steer: float, handbrake: bool = false) -> void:
	_input_throttle = clampf(throttle, -1.0, 1.0)
	_input_steer = clampf(steer, -1.0, 1.0)
	_handbrake_down = handbrake


func _align_visuals_to_ground() -> void:
	# Compute combined visual AABB across body_visuals and wheel nodes so tires rest cleanly on road (y = 0.0)
	var vis_aabb := _compute_combined_visual_aabb()
	var shift_y := 0.0
	if vis_aabb.size.y > 0.05:
		shift_y = -vis_aabb.position.y
	visual_ground_offset = shift_y

	if absf(shift_y) > 0.002:
		if body_visuals != null:
			body_visuals.position.y += shift_y
		for ch in get_children():
			if ch is Node3D and (ch as Node3D).visible and (ch.name.begins_with("FrontSteer") or ch.name.begins_with("RearWheel")):
				(ch as Node3D).position.y += shift_y
		driver_seat_offset.y += shift_y
		passenger_seat_offset.y += shift_y
		for mname in ["DriverSeat", "PassengerSeat"]:
			var mk := get_node_or_null(mname) as Marker3D
			if mk != null:
				mk.position = driver_seat_offset if mname == "DriverSeat" else passenger_seat_offset
		var seats_node := get_node_or_null("Seats") as Node3D
		if seats_node != null:
			for s in seats_node.get_children():
				if s is Marker3D:
					(s as Marker3D).position.y += shift_y


func get_seat_manager() -> VehicleSeatManager:
	if seat_manager == null:
		seat_manager = get_node_or_null("VehicleSeatManager") as VehicleSeatManager
	return seat_manager


func board_passenger(passenger: Node3D, reparent_to_seat: bool = true) -> bool:
	var sm := get_seat_manager()
	if sm != null:
		return sm.board_passenger(passenger, reparent_to_seat)
	return false


func exit_passenger(passenger: Node3D) -> bool:
	var sm := get_seat_manager()
	if sm != null:
		return sm.exit_passenger(passenger)
	return false


func exit_all_passengers() -> void:
	var sm := get_seat_manager()
	if sm != null:
		sm.exit_all_passengers()


func get_speed_mps() -> float:
	return _current_speed


func _compute_combined_visual_aabb() -> AABB:
	var combined := AABB()
	var first := true
	var root_inv := global_transform.affine_inverse()
	var roots: Array[Node] = []
	if body_visuals != null:
		roots.append(body_visuals)
	for ch in get_children():
		if ch is Node3D and (ch as Node3D).visible and (ch.name.begins_with("FrontSteer") or ch.name.begins_with("RearWheel")):
			roots.append(ch)
	while not roots.is_empty():
		var cur: Node = roots.pop_back()
		if cur is Node3D and not (cur as Node3D).visible:
			continue
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null and not (mi.name.begins_with("Exhaust") or mi.name.begins_with("Dust")):
				var ma := (root_inv * mi.global_transform) * mi.get_aabb()
				if first:
					combined = ma
					first = false
				else:
					combined = combined.merge(ma)
		for c in cur.get_children():
			roots.append(c)
	return combined


func toggle_headlights() -> void:
	headlights_on = not headlights_on
	_update_vfx(_current_speed, _current_steer, false)
	if _is_local_driver():
		get_tree().call_group("network_hud", "show_toast", "💡 الأضواء الأمامية: %s" % ("تشغيل" if headlights_on else "إطفاء"))


func is_occupied() -> bool:
	return driver_peer_id != 0


func get_seat_global_position() -> Vector3:
	return to_global(driver_seat_offset)


func get_passenger_seat_global_position() -> Vector3:
	return to_global(passenger_seat_offset)


func get_passenger_exit_position() -> Vector3:
	return _find_clear_position([
		Vector3(-exit_offset.x, exit_offset.y, 0.5),
		Vector3(exit_offset.x, exit_offset.y, 0.7),
		Vector3(0.0, 0.25, 2.8),
	])


func get_safe_exit_position() -> Vector3:
	return _find_clear_position([
		exit_offset,
		Vector3(-exit_offset.x, exit_offset.y, exit_offset.z),
		Vector3(0.0, 0.25, 2.6),
		Vector3(0.0, 0.25, -2.6),
	])


func _find_clear_position(candidates: Array[Vector3]) -> Vector3:
	var space_state := get_world_3d().direct_space_state
	for offset in candidates:
		var target := to_global(offset)
		var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3(0.0, 0.9, 0.0),
			target + Vector3(0.0, 0.9, 0.0),
			1
		)
		query.exclude = [get_rid()]
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			return target
	return global_position + Vector3(0.0, 1.8, 0.0)


func cycle_radio() -> void:
	var audio_mgr := get_node_or_null("/root/AudioManager")
	var count: int = audio_mgr.get_radio_count() if audio_mgr else 0
	if count <= 0:
		get_tree().call_group("network_hud", "show_toast", "No radio tracks in assets/audio/radio/")
		return
	var next_idx := _radio_track_idx + 1
	if next_idx >= count:
		next_idx = -1
	set_radio_track.rpc(next_idx)


func get_current_radio_label() -> String:
	if _radio_track_idx < 0:
		return "Radio: OFF"
	var audio_mgr := get_node_or_null("/root/AudioManager")
	var info: Dictionary = audio_mgr.get_radio_track(_radio_track_idx) if audio_mgr else {}
	if info.is_empty():
		return "Radio: OFF"
	return "Radio: %s" % String(info["name"])


func get_fuel_percentage() -> float:
	return clampf((fuel_liters / maxf(max_fuel_liters, 1.0)) * 100.0, 0.0, 100.0)


func get_fuel_hud_text() -> String:
	return "⛽ الوقود: %d%% (%.1f / %.0f لتر)" % [roundi(get_fuel_percentage()), fuel_liters, max_fuel_liters]


func is_near_fuel_pump(max_dist: float = 6.8) -> bool:
	for pump in get_tree().get_nodes_in_group("fuel_pumps"):
		if pump is Node3D and global_position.distance_to((pump as Node3D).global_position) <= max_dist:
			return true
	return false


func refuel_vehicle(add_liters: float = 15.0) -> String:
	var added := minf(max_fuel_liters - fuel_liters, add_liters)
	if added <= 0.05:
		fuel_liters = max_fuel_liters
		return "⛽ التنك ملان ١٠٠٪ (%.1f لتر)" % fuel_liters
	fuel_liters = minf(max_fuel_liters, fuel_liters + add_liters)
	var cost_sdg := roundi(added * 1200.0)
	if _radio_click_player and _radio_click_player.stream:
		_radio_click_player.play()
	var msg := "⛽ تم تعبئة الوقود (%s): %.1f / %.0f لتر (+%d جنيه)" % [vehicle_name, fuel_liters, max_fuel_liters, cost_sdg]
	get_tree().call_group("network_hud", "show_toast", msg)
	return msg


@rpc("any_peer", "call_local", "reliable")
func set_radio_track(idx: int) -> void:
	_radio_track_idx = idx
	if _radio_click_player and _radio_click_player.stream:
		_radio_click_player.play()
	if _radio_player == null:
		return
	if idx < 0:
		_radio_player.stop()
		if _is_local_driver():
			get_tree().call_group("network_hud", "show_toast", "Radio: OFF")
		return
	var audio_mgr := get_node_or_null("/root/AudioManager")
	var info: Dictionary = audio_mgr.get_radio_track(idx) if audio_mgr else {}
	if info.is_empty():
		_radio_track_idx = -1
		_radio_player.stop()
		return
	_radio_player.stream = info["stream"]
	_radio_player.play()
	if _is_local_driver():
		get_tree().call_group("network_hud", "show_toast", "Radio: %s" % String(info["name"]))


@rpc("any_peer", "call_local", "reliable")
func request_enter(peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if driver_peer_id != 0:
		return
	apply_driver.rpc(peer_id)


@rpc("any_peer", "call_local", "reliable")
func request_exit(peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if driver_peer_id != peer_id:
		return
	apply_driver.rpc(0)


@rpc("any_peer", "call_local", "reliable")
func apply_driver(peer_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return

	var prev_driver := driver_peer_id
	driver_peer_id = peer_id
	_input_throttle = 0.0
	_input_steer = 0.0

	if driver_peer_id > 0:
		ai_autopilot_active = false
		bus_ai_active = false
		set_physics_process(true)
		fuel_liters = maxf(fuel_liters, max_fuel_liters * 0.5)
		for dname in ["DriverCharacter", "BusDriverNPC", "AIDriver"]:
			var dnode := find_child(dname, true, false) as Node3D
			if dnode != null:
				dnode.visible = false
				dnode.process_mode = Node.PROCESS_MODE_DISABLED
				if not is_bus:
					dnode.queue_free()

	var new_authority := peer_id if peer_id > 0 else 1
	set_multiplayer_authority(new_authority)

	if prev_driver == 0 and driver_peer_id > 0:
		headlights_on = true
		if seat_manager != null:
			seat_manager.trigger_driver_door()
		if _door_player and _door_player.stream:
			_door_player.play()
		if _ignition_player and _ignition_player.stream:
			get_tree().create_timer(0.14).timeout.connect(func() -> void:
				if is_instance_valid(_ignition_player) and driver_peer_id > 0:
					_ignition_player.play()
			)
	elif prev_driver > 0 and driver_peer_id == 0:
		headlights_on = false
		_handbrake_down = false
		if seat_manager != null:
			seat_manager.trigger_driver_door()
		if _door_player and _door_player.stream:
			_door_player.play()
		if _engine_player and _engine_player.playing:
			_engine_player.stop()
		if _skid_player and _skid_player.playing:
			_skid_player.stop()
		if _radio_player and _radio_player.playing:
			_radio_player.stop()
			_radio_track_idx = -1
	_update_vfx(_current_speed, _current_steer, false, false)

	get_tree().call_group("players", "_on_vehicle_driver_changed", self, prev_driver, peer_id)
	get_tree().call_group("npcs", "_on_driver_vehicle_changed", self, prev_driver, peer_id)


@rpc("any_peer", "call_local", "unreliable")
func trigger_horn() -> void:
	if _horn_cooldown > 0.0:
		return
	_horn_cooldown = 0.36
	if _horn_player and _horn_player.stream:
		_horn_player.play()
	get_tree().call_group("bird_flocks", "scatter_from", global_position, 30.0)
	if driver_peer_id > 0:
		get_tree().call_group("network_hud", "show_toast", "%s: Beep Beep!" % vehicle_name)


func _physics_process(delta: float) -> void:
	if _horn_cooldown > 0.0:
		_horn_cooldown -= delta

	if not multiplayer.has_multiplayer_peer() and driver_peer_id == 0:
		_update_engine_audio(0.0, 0.0, false)
		_update_vfx(0.0, 0.0, false)
		return

	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		global_position = global_position.lerp(sync_position, clampf(delta * 16.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, sync_yaw, clampf(delta * 16.0, 0.0, 1.0))
		_animate_visuals(delta, sync_speed, sync_steer)
		_update_engine_audio(sync_speed, sync_steer, false)
		_update_vfx(sync_speed, sync_steer, false)
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.5

	if driver_peer_id == 0:
		_input_throttle = 0.0
		_input_steer = 0.0
		_handbrake_down = false

	var braking_now := _handbrake_down
	var reversing_now := false
	if driver_peer_id > 0 and absf(_input_throttle) > 0.05 and fuel_liters > 0.01:
		fuel_liters = maxf(0.0, fuel_liters - fuel_consumption_per_sec * absf(_input_throttle) * delta)
	if _handbrake_down and driver_peer_id > 0:
		_current_speed = move_toward(_current_speed, 0.0, brake_strength * 1.45 * delta)
	elif absf(_input_throttle) > 0.05 and fuel_liters > 0.01:
		var target_speed := _input_throttle * (max_speed if _input_throttle > 0.0 else reverse_speed)
		var reversing_dir := (_input_throttle > 0.0 and _current_speed < -0.3) or (_input_throttle < 0.0 and _current_speed > 0.3)
		reversing_now = _current_speed < -0.25 or (_input_throttle < -0.05 and _current_speed <= 0.3)
		braking_now = reversing_dir or _input_throttle < -0.05
		var rate := brake_strength if reversing_dir else acceleration
		_current_speed = move_toward(_current_speed, target_speed, rate * delta)
	else:
		_current_speed = move_toward(_current_speed, 0.0, deceleration * delta)
		reversing_now = _current_speed < -0.25

	_current_steer = lerpf(_current_steer, _input_steer, clampf(delta * 10.0, 0.0, 1.0))

	if absf(_current_speed) > 0.35 and absf(_current_steer) > 0.01:
		var speed_factor := clampf(absf(_current_speed) / 4.5, 0.28, 1.0)
		var dir_sign := 1.0 if _current_speed >= 0.0 else -1.0
		rotate_y(_current_steer * turn_speed * speed_factor * dir_sign * delta)

	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	velocity.x = forward.x * _current_speed
	velocity.z = forward.z * _current_speed

	move_and_slide()
	align_vehicle_to_slope(delta)

	sync_position = global_position
	sync_yaw = rotation.y
	sync_speed = _current_speed
	sync_steer = _current_steer

	_animate_visuals(delta, _current_speed, _current_steer)
	_update_engine_audio(_current_speed, _current_steer, braking_now)
	_update_vfx(_current_speed, _current_steer, braking_now, reversing_now)


func align_vehicle_to_slope(delta: float) -> void:
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return

	# Compute 4-wheel raycast sample footprint (FL, FR, RL, RR) tailored to vehicle size
	var half_x := 0.55 if is_three_wheeler else (1.05 if is_bus else 0.78)
	var half_z := 0.85 if is_three_wheeler else (3.15 if is_bus else (1.95 if pack_target_length > 5.0 else 1.40))
	var wheel_offsets: Array[Vector3] = [
		Vector3(-half_x, 0.85, -half_z), # Front-Left
		Vector3( half_x, 0.85, -half_z), # Front-Right
		Vector3(-half_x, 0.85,  half_z), # Rear-Left
		Vector3( half_x, 0.85,  half_z), # Rear-Right
	]

	var exclude_rids: Array[RID] = [get_rid()]
	var normal_sum := Vector3.ZERO
	var hit_count := 0

	for off in wheel_offsets:
		var ray_from := to_global(off)
		var ray_to := to_global(off + Vector3(0.0, -2.4, 0.0))
		var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1, exclude_rids)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			if n.y > 0.35:
				normal_sum += n
				hit_count += 1

	var target_up := Vector3.UP
	if hit_count > 0:
		var avg_n := (normal_sum / float(hit_count)).normalized()
		# Clamp max tilt to 35 deg so abrupt curb hits never flip the vehicle
		if avg_n.angle_to(Vector3.UP) <= deg_to_rad(35.0):
			target_up = avg_n
		else:
			target_up = Vector3.UP.slerp(avg_n, deg_to_rad(35.0) / maxf(avg_n.angle_to(Vector3.UP), 0.001)).normalized()

	var cur_basis := global_transform.basis.orthonormalized()
	var fwd := -cur_basis.z
	var right := fwd.cross(target_up)
	if right.length_squared() < 0.0001:
		right = cur_basis.x
	right = right.normalized()
	var aligned_fwd := target_up.cross(right).normalized()
	var target_basis := Basis(right, target_up, -aligned_fwd).orthonormalized()
	global_transform.basis = cur_basis.slerp(target_basis, clampf(delta * 10.0, 0.0, 1.0)).orthonormalized()


func _update_engine_audio(speed: float, steer: float, braking: bool) -> void:
	if _engine_player == null or _engine_player.stream == null:
		return
	if driver_peer_id <= 0:
		if _engine_player.playing:
			_engine_player.stop()
		if _skid_player and _skid_player.playing:
			_skid_player.stop()
		return

	if not _engine_player.playing:
		_engine_player.play()
	var speed_ratio := clampf(absf(speed) / maxf(max_speed, 1.0), 0.0, 1.0)
	var throttle_boost := 0.14 * absf(_input_throttle)
	_engine_player.pitch_scale = clampf(lerpf(0.80, 1.92, speed_ratio) + throttle_boost, 0.80, 2.0)
	_engine_player.volume_db = lerpf(-12.0, -3.5, clampf(speed_ratio + absf(_input_throttle) * 0.35, 0.0, 1.0))

	if _skid_player and _skid_player.stream:
		var hard_brake := braking and absf(speed) > 4.8
		var sharp_drift := absf(steer) > 0.55 and absf(speed) > 6.2
		if hard_brake or sharp_drift:
			if not _skid_player.playing:
				_skid_player.play()
			_skid_player.volume_db = -8.0 if hard_brake else -13.0
		elif _skid_player.playing:
			_skid_player.stop()


func _update_vfx(speed: float, steer: float, braking: bool, reversing: bool = false) -> void:
	var occupied := driver_peer_id > 0
	var lights_lit := headlights_on
	for spot in _headlights:
		spot.visible = lights_lit
	for hmat in _headlight_mats:
		hmat.emission_enabled = true
		hmat.emission_energy_multiplier = 3.8 if lights_lit else 0.08

	var tail_energy := 0.15
	if occupied or lights_lit:
		tail_energy = 4.2 if braking else (1.1 if lights_lit else 0.75)
	for mat in _taillight_mats:
		mat.emission_energy_multiplier = tail_energy

	var rev_energy := 3.8 if (occupied and reversing) else 0.05
	for rmat in _reverselight_mats:
		rmat.emission_energy_multiplier = rev_energy

	if _exhaust_smoke:
		_exhaust_smoke.emitting = occupied
		if occupied:
			_exhaust_smoke.amount_ratio = clampf(0.30 + absf(_input_throttle) * 0.70, 0.30, 1.0)

	var on_dirt := _is_on_dirt_road(global_position)
	var kicking_dust := occupied and ((on_dirt and absf(speed) > 2.2) or (absf(steer) > 0.45 and absf(speed) > 4.2))
	if _dust_left:
		_dust_left.emitting = kicking_dust
	if _dust_right:
		_dust_right.emitting = kicking_dust


func _is_on_dirt_road(pos: Vector3) -> bool:
	# Main asphalt road is along X in [-7.5..7.5] or Z in [-7.5..7.5], plus roundabout radius ~13m.
	var dist_center := Vector2(pos.x, pos.z).length()
	if dist_center < 13.5:
		return false
	if absf(pos.x) < 7.5 or absf(pos.z) < 7.5:
		return false
	return true


func _animate_visuals(delta: float, speed: float, steer: float) -> void:
	var target_steer_rad := steer * deg_to_rad(32.0)
	for pivot in _front_steer_pivots:
		pivot.rotation.y = lerpf(pivot.rotation.y, target_steer_rad, clampf(delta * 12.0, 0.0, 1.0))

	if _steering_wheel_node != null and is_instance_valid(_steering_wheel_node):
		if is_three_wheeler:
			_steering_wheel_node.rotation.y = lerpf(_steering_wheel_node.rotation.y, target_steer_rad, clampf(delta * 12.0, 0.0, 1.0))
		else:
			_steering_wheel_node.rotation.z = lerpf(_steering_wheel_node.rotation.z, -steer * TAU, clampf(delta * 12.0, 0.0, 1.0))

	var wheel_rot_delta := -speed * delta * 2.4
	for wheel in _wheel_spin_nodes:
		wheel.rotate_x(wheel_rot_delta)

	if body_visuals:
		var roll_amount := -steer * clampf(absf(speed) / max_speed, 0.0, 1.0) * (0.11 if is_three_wheeler else 0.06)
		var pitch_amount := -_input_throttle * 0.035 if driver_peer_id != 0 else 0.0
		body_visuals.rotation.z = lerpf(body_visuals.rotation.z, roll_amount, clampf(delta * 8.0, 0.0, 1.0))
		body_visuals.rotation.x = lerpf(body_visuals.rotation.x, pitch_amount, clampf(delta * 8.0, 0.0, 1.0))


func _collect_wheel_nodes() -> void:
	for child in get_children():
		if not (child is Node3D) or not (child as Node3D).visible:
			continue
		if child.name.begins_with("FrontSteer"):
			if not _front_steer_pivots.has(child):
				_front_steer_pivots.append(child)
			for sub in child.get_children():
				if sub.name.contains("Wheel") and sub.visible and not _wheel_spin_nodes.has(sub):
					_wheel_spin_nodes.append(sub)
		elif child.name.contains("Wheel") and not _wheel_spin_nodes.has(child):
			_wheel_spin_nodes.append(child)


func _setup_audio() -> void:
	var audio_mgr := get_node_or_null("/root/AudioManager")

	_engine_player = AudioStreamPlayer3D.new()
	_engine_player.name = "EnginePlayer"
	if audio_mgr:
		_engine_player.stream = audio_mgr.get_vehicle_engine_stream(is_three_wheeler)
	_engine_player.max_distance = 48.0
	_engine_player.unit_size = 4.5
	_engine_player.volume_db = -12.0
	add_child(_engine_player)

	_horn_player = AudioStreamPlayer3D.new()
	_horn_player.name = "HornPlayer"
	if audio_mgr:
		_horn_player.stream = audio_mgr.get_vehicle_horn_stream(is_three_wheeler)
	_horn_player.max_distance = 65.0
	_horn_player.unit_size = 6.0
	_horn_player.volume_db = -2.5
	add_child(_horn_player)

	_skid_player = AudioStreamPlayer3D.new()
	_skid_player.name = "SkidPlayer"
	if audio_mgr:
		_skid_player.stream = audio_mgr.tire_skid_stream
	_skid_player.max_distance = 38.0
	_skid_player.unit_size = 3.5
	_skid_player.volume_db = -10.0
	add_child(_skid_player)

	_door_player = AudioStreamPlayer3D.new()
	_door_player.name = "DoorPlayer"
	if audio_mgr:
		_door_player.stream = audio_mgr.vehicle_door_stream
	_door_player.max_distance = 22.0
	_door_player.volume_db = -4.0
	add_child(_door_player)

	_ignition_player = AudioStreamPlayer3D.new()
	_ignition_player.name = "IgnitionPlayer"
	if audio_mgr:
		_ignition_player.stream = audio_mgr.vehicle_ignition_stream
	_ignition_player.max_distance = 28.0
	_ignition_player.volume_db = -4.0
	add_child(_ignition_player)

	_radio_player = AudioStreamPlayer3D.new()
	_radio_player.name = "RadioPlayer"
	_radio_player.max_distance = 34.0
	_radio_player.unit_size = 5.5
	_radio_player.volume_db = -3.5
	add_child(_radio_player)

	_radio_click_player = AudioStreamPlayer3D.new()
	_radio_click_player.name = "RadioClickPlayer"
	if audio_mgr:
		_radio_click_player.stream = audio_mgr.radio_click_stream
	_radio_click_player.max_distance = 16.0
	_radio_click_player.volume_db = -5.0
	add_child(_radio_click_player)


func _setup_vfx() -> void:
	var vfx_mgr := get_node_or_null("/root/VFXManager")
	if vfx_mgr:
		var tailpipe_pos := Vector3(0.32, 0.24, 1.24) if is_three_wheeler else Vector3(0.56, 0.34, 2.25)
		_exhaust_smoke = vfx_mgr.create_smoke_particles(self, tailpipe_pos, not is_three_wheeler)
		var wheel_x := 0.66 if is_three_wheeler else 0.92
		var wheel_z := 0.85 if is_three_wheeler else 1.45
		_dust_left = vfx_mgr.create_dust_particles(self, Vector3(-wheel_x, 0.12, wheel_z))
		_dust_right = vfx_mgr.create_dust_particles(self, Vector3(wheel_x, 0.12, wheel_z))

	# Front SpotLight3D headlight beam(s) pointing -Z
	var head_positions: Array[Vector3] = []
	if is_three_wheeler:
		head_positions.append(Vector3(0.0, 0.74, -1.25))
	else:
		head_positions.append(Vector3(-0.72, 0.76, -2.20))
		head_positions.append(Vector3(0.72, 0.76, -2.20))
	for pos in head_positions:
		var spot := SpotLight3D.new()
		spot.position = pos
		spot.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
		spot.light_color = Color(1.0, 0.94, 0.78, 1.0)
		spot.light_energy = 2.6 if is_three_wheeler else 2.2
		spot.spot_range = 28.0
		spot.spot_angle = 38.0
		spot.visible = false
		add_child(spot)
		_headlights.append(spot)

	# Collect existing taillights or create brake lights on Raksha
	if body_visuals:
		for child in body_visuals.get_children():
			if child is MeshInstance3D and child.name.begins_with("Taillight"):
				var mi := child as MeshInstance3D
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.88, 0.14, 0.12, 1.0)
				mat.emission_enabled = true
				mat.emission = Color(0.95, 0.12, 0.08, 1.0)
				mat.emission_energy_multiplier = 0.15
				mi.material_override = mat
				_taillight_mats.append(mat)

		if _taillight_mats.is_empty() and is_three_wheeler:
			for side_x in [-0.46, 0.46]:
				var tl := MeshInstance3D.new()
				tl.name = "Taillight" + ("L" if side_x < 0.0 else "R")
				var box := BoxMesh.new()
				box.size = Vector3(0.18, 0.14, 0.06)
				tl.mesh = box
				tl.position = Vector3(side_x, 0.62, 1.24)
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.88, 0.14, 0.12, 1.0)
				mat.emission_enabled = true
				mat.emission = Color(0.95, 0.12, 0.08, 1.0)
				mat.emission_energy_multiplier = 0.15
				tl.material_override = mat
				body_visuals.add_child(tl)
				_taillight_mats.append(mat)


func _is_local_driver() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return driver_peer_id == 1
	return driver_peer_id == multiplayer.get_unique_id()
