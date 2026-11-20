extends CharacterBody3D
class_name NPCInteractive

## Interactive Sudanese neighborhood NPC with Arabic dialogue, 3D voice clips,
## 20s approach greeting cooldown, and Follow Companion mode (including riding vehicles).

const TALK_RANGE: float = 4.0
const GREET_COOLDOWN_SEC: float = 20.0
const FOLLOW_STOP_DIST: float = 2.2
const FOLLOW_RUN_DIST: float = 4.8
const BASE_HIPS_Y: float = 0.88

enum NPCBehaviorRole {
	PATROL,
	MARKET_VENDOR_CHEER,
	MARKET_TALKING,
	SEATED_IDLE,
	CARRYING_GOODS,
	MOURNER_CRYING,
	SICK_PATIENT,
	DEAD_LYING,
	COOKING,
	DANCING,
}

const ROLE_CLIP_SETS: Dictionary = {
	NPCBehaviorRole.MARKET_VENDOR_CHEER: ["Cheering", "Yelling", "Pointing", "Wave_Hello"],
	NPCBehaviorRole.MARKET_TALKING: ["Talking", "Arguing", "Pointing", "Idle_LookAround"],
	NPCBehaviorRole.SEATED_IDLE: ["Sit_Idle", "Sit_Talking", "Sit_Clap"],
	NPCBehaviorRole.CARRYING_GOODS: ["Carrying", "Carrying_Walk"],
	NPCBehaviorRole.MOURNER_CRYING: ["Crying", "Sad_Idle", "Kneeling_Pray"],
	NPCBehaviorRole.SICK_PATIENT: ["Injured_Idle", "Dizzy_Idle", "Agony"],
	NPCBehaviorRole.DEAD_LYING: ["Laying_Dead_Idle"],
	NPCBehaviorRole.COOKING: ["Cooking_Stir", "Chopping"],
	NPCBehaviorRole.DANCING: ["Dance_1", "Dance_2"],
}

@export var npc_name: String = "ود الحلة"
@export var npc_behavior_role: NPCBehaviorRole = NPCBehaviorRole.PATROL:
	set(value):
		npc_behavior_role = value
		_role_clip_idx = 0
		_role_cycle_timer = 0.0
		if is_node_ready():
			apply_behavior_role_animation(true)
@export var dialogue_lines: PackedStringArray = PackedStringArray([
	"أهلاً وسهلاً يا زول! نورت حي الأزهري.",
	"كيف أمورك؟ الجو الليلة سمح شديد في الخرطوم.",
	"لو محتاج أي حاجة في الحلة أنا قريب هنا."
])
@export var patrol_points: PackedVector3Array = PackedVector3Array()
@export var walk_speed: float = 1.85
@export var robe_color: Color = Color(0.95, 0.94, 0.90, 1.0):
	set(value):
		robe_color = value
		_apply_outfit()
@export var has_turban: bool = true:
	set(value):
		has_turban = value
		_apply_outfit()
@export var is_female_thobe: bool = false:
	set(value):
		is_female_thobe = value
		_apply_outfit()
@export var model_keyword: String = ""
@export var explicit_model_path: String = ""
@export var target_height: float = 1.72
@export var height_variation: float = 1.0

@export var following_peer_id: int = 0
@export var ai_activation_radius: float = 0.0 # 0 = always active; >0 = distance-culled outer-block NPC (~110m)
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var sync_speed: float = 0.0
@export var sync_seated: bool = false

@onready var body_collider: CollisionShape3D = $CollisionShape3D
@onready var visuals: Node3D = $Visuals
@onready var hips: Node3D = $Visuals/Hips
@onready var robe_top: MeshInstance3D = $Visuals/Hips/RobeTop
@onready var robe_skirt: MeshInstance3D = $Visuals/Hips/RobeSkirt
@onready var left_sleeve: MeshInstance3D = $Visuals/Hips/LeftArmPivot/ArmMesh
@onready var right_sleeve: MeshInstance3D = $Visuals/Hips/RightArmPivot/ArmMesh
@onready var imma_mesh: MeshInstance3D = $Visuals/Hips/HeadPivot/Imma
@onready var thobe_wrap: MeshInstance3D = $Visuals/Hips/HeadPivot/ThobeWrap
@onready var left_arm_pivot: Node3D = $Visuals/Hips/LeftArmPivot
@onready var right_arm_pivot: Node3D = $Visuals/Hips/RightArmPivot
@onready var left_leg_pivot: Node3D = $Visuals/Hips/LeftLegPivot
@onready var right_leg_pivot: Node3D = $Visuals/Hips/RightLegPivot
@onready var name_label: Label3D = $Visuals/NameLabel
@onready var ray_left: RayCast3D = $Visuals/RayLeft
@onready var ray_right: RayCast3D = $Visuals/RayRight
@onready var voice_player: AudioStreamPlayer3D = $VoicePlayer

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _waypoint_idx: int = 0
var _wait_timer: float = 0.0
var _anim_time: float = 0.0
var _greet_cooldown: float = 0.0
var _player_was_near: bool = false
var _line_idx: int = 0
var _riding_vehicle: VehicleController = null
var _spawn_position: Vector3 = Vector3.ZERO
var _glb_pivot: Node3D = null
var _speaking_wave: Node3D = null
var _wave_time: float = 0.0
var _approach_timer: float = 0.0
var _anim_binder: CharacterAnimationAutoBinder = null
var _role_clip_idx: int = 0
var _role_cycle_timer: float = 0.0


func _ready() -> void:
	if OS.has_feature("web"):
		# Web keeps 0 ambient NPCs so Safari RAM stays under 300 MB
		queue_free()
		return
	add_to_group("npcs")
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.42
	_spawn_position = global_position
	_setup_glb_model()
	_setup_anim_binder()
	_setup_speaking_wave()
	_apply_outfit()
	_update_name_label()
	sync_position = global_position
	sync_yaw = visuals.rotation.y
	_anim_time = randf() * TAU
	_approach_timer = randf() * 0.25
	if npc_behavior_role != NPCBehaviorRole.PATROL:
		call_deferred("apply_behavior_role_animation", true)


func reset_npc() -> void:
	following_peer_id = 0
	_riding_vehicle = null
	if body_collider:
		body_collider.disabled = false
	global_position = _spawn_position
	velocity = Vector3.ZERO
	sync_position = _spawn_position
	sync_speed = 0.0
	sync_seated = false
	_update_name_label()


func is_following_peer(peer_id: int) -> bool:
	return following_peer_id == peer_id and peer_id > 0


func talk_interact() -> void:
	_trigger_voice_and_subtitle(false)


@rpc("any_peer", "call_local", "reliable")
func request_toggle_follow(peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var next_peer := 0 if following_peer_id == peer_id else peer_id
	apply_follow.rpc(next_peer)


@rpc("any_peer", "call_local", "reliable")
func apply_follow(peer_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return

	following_peer_id = peer_id
	_update_name_label()

	if following_peer_id == 0:
		if _riding_vehicle != null and is_instance_valid(_riding_vehicle):
			_exit_vehicle(_riding_vehicle)
		_show_npc_subtitle("%s: في أمان الله، أنا قاعد هنا." % npc_name)
	else:
		# Check if target player is already inside a vehicle.
		var target_player := _find_player_by_peer_id(following_peer_id)
		if target_player and target_player.get_current_vehicle() != null:
			_board_vehicle(target_player.get_current_vehicle())
		_trigger_voice_and_subtitle(false, "أبشر يا زول! أنا ماشي معاك.")


func _on_driver_vehicle_changed(vehicle: VehicleController, prev_driver: int, new_driver: int) -> void:
	if following_peer_id <= 0:
		return
	if new_driver == following_peer_id and new_driver > 0:
		_board_vehicle(vehicle)
	elif prev_driver == following_peer_id and new_driver == 0 and _riding_vehicle == vehicle:
		_exit_vehicle(vehicle)


func _board_vehicle(vehicle: VehicleController) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if _riding_vehicle == vehicle:
		return
	if vehicle.get_seat_manager() != null:
		if not vehicle.board_passenger(self, true):
			_show_npc_subtitle("%s: السيارة ممتلئة، بنتظرك هنا!" % npc_name)
			return
		_riding_vehicle = vehicle
		velocity = Vector3.ZERO
		return
	_riding_vehicle = vehicle
	body_collider.disabled = true
	global_position = vehicle.get_passenger_seat_global_position()
	visuals.rotation.y = vehicle.rotation.y
	velocity = Vector3.ZERO


func _exit_vehicle(vehicle: VehicleController) -> void:
	var v := vehicle if (vehicle != null and is_instance_valid(vehicle)) else _riding_vehicle
	_riding_vehicle = null
	if v != null and is_instance_valid(v):
		if v.get_seat_manager() != null and v.get_seat_manager().is_passenger_seated(self):
			v.exit_passenger(self)
			velocity = Vector3.ZERO
			return
		global_position = v.get_passenger_exit_position()
	velocity = Vector3.ZERO
	body_collider.disabled = false


var _dist_cull_timer: float = 0.0
var _dist_sleeping: bool = false


func _is_player_within_activation_radius() -> bool:
	if ai_activation_radius <= 0.0 or following_peer_id > 0:
		return true
	var r2 := ai_activation_radius * ai_activation_radius
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return true
	for p in players:
		var p3 := p as Node3D
		if p3 != null and is_instance_valid(p3):
			if global_position.distance_squared_to(p3.global_position) <= r2:
				return true
	return false


func _physics_process(delta: float) -> void:
	if ai_activation_radius > 0.0 and following_peer_id == 0 and _riding_vehicle == null:
		_dist_cull_timer -= delta
		if _dist_cull_timer <= 0.0:
			_dist_cull_timer = 0.45
			var should_wake := _is_player_within_activation_radius()
			if should_wake == _dist_sleeping:
				_dist_sleeping = not should_wake
				if visuals != null:
					visuals.visible = should_wake
				if body_collider != null:
					body_collider.disabled = _dist_sleeping
		if _dist_sleeping:
			velocity = Vector3.ZERO
			return

	if _greet_cooldown > 0.0:
		_greet_cooldown -= delta

	_update_speaking_wave(delta)
	_approach_timer -= delta
	if _approach_timer <= 0.0:
		_approach_timer = 0.22
		_check_local_player_approach()

	var runs_ai := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if not runs_ai:
		if _riding_vehicle != null and is_instance_valid(_riding_vehicle):
			global_position = _riding_vehicle.get_passenger_seat_global_position()
			visuals.rotation.y = _riding_vehicle.rotation.y
			_animate_pose(delta, 0.0, true)
		else:
			global_position = global_position.lerp(sync_position, clampf(delta * 14.0, 0.0, 1.0))
			visuals.rotation.y = lerp_angle(visuals.rotation.y, sync_yaw, clampf(delta * 14.0, 0.0, 1.0))
			_animate_pose(delta, sync_speed, sync_seated)
		return

	if _riding_vehicle != null and is_instance_valid(_riding_vehicle):
		global_position = _riding_vehicle.get_passenger_seat_global_position()
		visuals.rotation.y = _riding_vehicle.rotation.y
		velocity = Vector3.ZERO
		sync_position = global_position
		sync_yaw = visuals.rotation.y
		sync_speed = 0.0
		sync_seated = true
		_animate_pose(delta, 0.0, true)
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if following_peer_id > 0:
		if _anim_binder != null and _anim_binder.is_override_active():
			_anim_binder.resume_animation_tree()
		_process_follow_ai(delta)
	elif _role_allows_patrol():
		_process_patrol_ai(delta)
	else:
		velocity.x = lerpf(velocity.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, clampf(delta * 10.0, 0.0, 1.0))

	move_and_slide()

	var horiz := Vector2(velocity.x, velocity.z).length()
	sync_position = global_position
	sync_yaw = visuals.rotation.y
	sync_speed = horiz
	sync_seated = (npc_behavior_role == NPCBehaviorRole.SEATED_IDLE and following_peer_id == 0)
	_animate_pose(delta, horiz, sync_seated)


func _process_follow_ai(delta: float) -> void:
	var target_player := _find_player_by_peer_id(following_peer_id)
	if target_player == null:
		velocity.x = lerpf(velocity.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		return

	var to_player := Vector3(
		target_player.global_position.x - global_position.x,
		0.0,
		target_player.global_position.z - global_position.z
	)
	var dist := to_player.length()
	if dist <= FOLLOW_STOP_DIST:
		velocity.x = lerpf(velocity.x, 0.0, clampf(delta * 12.0, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, clampf(delta * 12.0, 0.0, 1.0))
		var face_yaw := atan2(-to_player.x, -to_player.z) if dist > 0.2 else visuals.rotation.y
		visuals.rotation.y = lerp_angle(visuals.rotation.y, face_yaw, clampf(delta * 6.0, 0.0, 1.0))
		return

	var desired_dir := to_player.normalized()
	desired_dir = _apply_obstacle_avoidance(desired_dir)
	var follow_speed := 6.8 if dist > FOLLOW_RUN_DIST else 4.2
	velocity.x = lerpf(velocity.x, desired_dir.x * follow_speed, clampf(delta * 10.0, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, desired_dir.z * follow_speed, clampf(delta * 10.0, 0.0, 1.0))
	var target_yaw := atan2(-desired_dir.x, -desired_dir.z)
	visuals.rotation.y = lerp_angle(visuals.rotation.y, target_yaw, clampf(delta * 9.0, 0.0, 1.0))


func _process_patrol_ai(delta: float) -> void:
	if patrol_points.is_empty():
		velocity.x = lerpf(velocity.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		return

	if _wait_timer > 0.0:
		_wait_timer -= delta
		velocity.x = lerpf(velocity.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		return

	var target := patrol_points[_waypoint_idx]
	var to_target := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if to_target.length() < 1.1:
		_waypoint_idx = (_waypoint_idx + 1) % patrol_points.size()
		_wait_timer = randf_range(0.8, 2.4)
		return

	var desired_dir := _apply_obstacle_avoidance(to_target.normalized())
	velocity.x = lerpf(velocity.x, desired_dir.x * walk_speed, clampf(delta * 8.0, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, desired_dir.z * walk_speed, clampf(delta * 8.0, 0.0, 1.0))
	var target_yaw := atan2(-desired_dir.x, -desired_dir.z)
	visuals.rotation.y = lerp_angle(visuals.rotation.y, target_yaw, clampf(delta * 7.0, 0.0, 1.0))


func _apply_obstacle_avoidance(desired_dir: Vector3) -> Vector3:
	for k in get_tree().get_nodes_in_group("kiosks"):
		var kn := k as Node3D
		if kn == null:
			continue
		var delta_xz := Vector3(global_position.x - kn.global_position.x, 0.0, global_position.z - kn.global_position.z)
		var d2 := delta_xz.length_squared()
		if d2 > 0.001 and d2 < (3.5 * 3.5):
			var away := delta_xz.normalized()
			if desired_dir.dot(away) < 0.25:
				return (desired_dir + away * 1.6).normalized()
	var hit_l := ray_left.is_colliding()
	var hit_r := ray_right.is_colliding()
	if hit_l and not hit_r:
		return desired_dir.rotated(Vector3.UP, -0.85)
	if hit_r and not hit_l:
		return desired_dir.rotated(Vector3.UP, 0.85)
	if hit_l and hit_r:
		return desired_dir.rotated(Vector3.UP, 1.35)
	return desired_dir


func _check_local_player_approach() -> void:
	var local_players := get_tree().get_nodes_in_group("local_player")
	if local_players.is_empty():
		_player_was_near = false
		return
	var local_player := local_players[0] as Node3D
	if local_player == null:
		return
	var dist := global_position.distance_to(local_player.global_position)
	var is_near := dist <= TALK_RANGE
	if is_near and not _player_was_near and _greet_cooldown <= 0.0:
		_trigger_voice_and_subtitle(true)
	_player_was_near = is_near


func _trigger_voice_and_subtitle(is_auto_greet: bool, override_text: String = "") -> void:
	_greet_cooldown = GREET_COOLDOWN_SEC

	var audio_mgr := get_node_or_null("/root/AudioManager")
	var clip: AudioStream = audio_mgr.get_random_npc_clip() if audio_mgr else null
	if clip and voice_player:
		if not (is_auto_greet and voice_player.playing):
			voice_player.stream = clip
			voice_player.pitch_scale = randf_range(0.95, 1.05)
			voice_player.play()

	var text := override_text
	if text.is_empty() and not dialogue_lines.is_empty():
		text = dialogue_lines[_line_idx % dialogue_lines.size()]
		_line_idx = (_line_idx + 1) % dialogue_lines.size()
	elif text.is_empty():
		text = "أهلاً بك في الأزهري!"

	_show_npc_subtitle("%s: %s" % [npc_name, text])


func _show_npc_subtitle(full_text: String) -> void:
	get_tree().call_group("network_hud", "show_subtitle", full_text)


func _setup_anim_binder() -> void:
	_anim_binder = CharacterAnimationAutoBinder.find_on_character(self)
	if _anim_binder == null:
		_anim_binder = CharacterAnimationAutoBinder.new()
		_anim_binder.name = "CharacterAnimationAutoBinder"
		_anim_binder.auto_bind_on_ready = false
		add_child(_anim_binder)
	if _glb_pivot != null:
		_anim_binder.bind_character(self)


func _role_allows_patrol() -> bool:
	return npc_behavior_role in [
		NPCBehaviorRole.PATROL,
		NPCBehaviorRole.CARRYING_GOODS,
		NPCBehaviorRole.SICK_PATIENT,
	]


func apply_behavior_role_animation(force_immediate: bool = false, horiz_speed: float = 0.0) -> String:
	if _anim_binder == null:
		_setup_anim_binder()
	if _anim_binder == null:
		return ""
	if not _anim_binder.is_bound:
		_anim_binder.bind_character(self)
	if not _anim_binder.is_bound:
		return ""

	if npc_behavior_role == NPCBehaviorRole.PATROL or following_peer_id > 0:
		if _anim_binder.is_override_active():
			_anim_binder.resume_animation_tree()
		return ""

	if npc_behavior_role == NPCBehaviorRole.CARRYING_GOODS:
		var clip := "Carrying_Walk" if (horiz_speed > 0.25 and _anim_binder.has_clip("Carrying_Walk")) else "Carrying"
		if _anim_binder.play_state(clip, 0.16, 1.0, force_immediate):
			return clip
		return ""

	if npc_behavior_role == NPCBehaviorRole.SICK_PATIENT:
		if horiz_speed > 0.20 and _anim_binder.has_clip("Injured_Walk"):
			if _anim_binder.play_state("Injured_Walk", 0.18, 0.92, force_immediate):
				return "Injured_Walk"

	var clips: Array = ROLE_CLIP_SETS.get(npc_behavior_role, [])
	if clips.is_empty():
		return ""

	var chosen: String = String(clips[_role_clip_idx % clips.size()])
	if not _anim_binder.has_clip(chosen):
		for cand in clips:
			if _anim_binder.has_clip(String(cand)):
				chosen = String(cand)
				break
	if _anim_binder.play_state(chosen, 0.20, 1.0, force_immediate):
		return chosen
	return ""


func _animate_pose(delta: float, speed: float, seated: bool) -> void:
	if _glb_pivot != null:
		if npc_behavior_role != NPCBehaviorRole.PATROL and following_peer_id == 0 and _riding_vehicle == null:
			_role_cycle_timer -= delta
			if _role_cycle_timer <= 0.0:
				var clips: Array = ROLE_CLIP_SETS.get(npc_behavior_role, [])
				if clips.size() > 1 and npc_behavior_role != NPCBehaviorRole.CARRYING_GOODS:
					_role_clip_idx = (_role_clip_idx + 1) % clips.size()
				_role_cycle_timer = randf_range(5.0, 9.5)
				apply_behavior_role_animation(false, speed)
			elif npc_behavior_role in [NPCBehaviorRole.CARRYING_GOODS, NPCBehaviorRole.SICK_PATIENT]:
				apply_behavior_role_animation(false, speed)
			if _anim_binder != null and _anim_binder.is_override_active():
				return
		elif _anim_binder != null and _anim_binder.is_override_active() and _riding_vehicle == null:
			_anim_binder.resume_animation_tree()

		if _glb_pivot.has_meta("character_animator"):
			var anim := _glb_pivot.get_meta("character_animator") as CharacterAnimator
			if anim != null:
				var is_talking := voice_player != null and voice_player.playing
				anim.update_animation(delta, speed, seated, false, false, 0.0, 0.0, 0.0, 0.0, is_talking)
				return
		return

	if seated:
		if hips == null:
			return
		hips.position.y = lerpf(hips.position.y, 0.62, clampf(delta * 12.0, 0.0, 1.0))
		left_leg_pivot.rotation.x = lerpf(left_leg_pivot.rotation.x, deg_to_rad(75.0), clampf(delta * 12.0, 0.0, 1.0))
		right_leg_pivot.rotation.x = lerpf(right_leg_pivot.rotation.x, deg_to_rad(75.0), clampf(delta * 12.0, 0.0, 1.0))
		left_arm_pivot.rotation.x = lerpf(left_arm_pivot.rotation.x, deg_to_rad(28.0), clampf(delta * 12.0, 0.0, 1.0))
		right_arm_pivot.rotation.x = lerpf(right_arm_pivot.rotation.x, deg_to_rad(28.0), clampf(delta * 12.0, 0.0, 1.0))
		return

	if hips == null:
		return
	if speed > 0.35:
		_anim_time += delta * (speed * 2.2)
		var swing := sin(_anim_time) * clampf(speed / 4.5, 0.45, 0.9)
		left_leg_pivot.rotation.x = swing
		right_leg_pivot.rotation.x = -swing
		left_arm_pivot.rotation.x = -swing * 0.75
		right_arm_pivot.rotation.x = swing * 0.75
		hips.position.y = BASE_HIPS_Y + absf(cos(_anim_time)) * 0.035
	else:
		left_leg_pivot.rotation.x = lerpf(left_leg_pivot.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		right_leg_pivot.rotation.x = lerpf(right_leg_pivot.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		left_arm_pivot.rotation.x = lerpf(left_arm_pivot.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		right_arm_pivot.rotation.x = lerpf(right_arm_pivot.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		hips.position.y = lerpf(hips.position.y, BASE_HIPS_Y, clampf(delta * 8.0, 0.0, 1.0))


func _find_player_by_peer_id(peer_id: int) -> PlayerController:
	var expected_name := "Player_%d" % peer_id
	for p in get_tree().get_nodes_in_group("players"):
		if str(p.name) == expected_name or str(p.name) == str(peer_id) or p.get_multiplayer_authority() == peer_id:
			return p as PlayerController
	return null


func _update_name_label() -> void:
	if not is_node_ready() or name_label == null:
		return
	if following_peer_id > 0:
		name_label.text = "%s (رفيقك)" % npc_name
		name_label.modulate = Color(0.55, 1.0, 0.65, 1.0)
	else:
		name_label.text = npc_name
		name_label.modulate = Color(1.0, 0.94, 0.78, 1.0)


func _setup_glb_model() -> void:
	var path := explicit_model_path
	if path.is_empty() and not model_keyword.is_empty():
		path = CharacterModelLoader.find_model_path(model_keyword)
	if path.is_empty():
		return
	var final_height := target_height * height_variation
	var pivot := CharacterModelLoader.instantiate_normalized(path, final_height, true)
	if pivot == null:
		return
	_glb_pivot = pivot
	visuals.add_child(_glb_pivot)
	if hips:
		hips.visible = false
		hips.queue_free()
		hips = null
	if name_label:
		name_label.position.y = final_height + 0.38


func _setup_speaking_wave() -> void:
	var vfx_mgr := get_node_or_null("/root/VFXManager")
	if vfx_mgr == null:
		return
	_speaking_wave = vfx_mgr.create_speaking_wave()
	_speaking_wave.position = Vector3(0.0, target_height * height_variation + 0.70, 0.0)
	visuals.add_child(_speaking_wave)


func _update_speaking_wave(delta: float) -> void:
	if _speaking_wave == null or voice_player == null:
		return
	var is_talking := voice_player.playing
	_speaking_wave.visible = is_talking
	if not is_talking:
		return
	_wave_time += delta * 12.0
	for i in range(_speaking_wave.get_child_count()):
		var bar := _speaking_wave.get_child(i) as Node3D
		if bar:
			bar.scale.y = 0.5 + 0.9 * absf(sin(_wave_time + float(i) * 0.9))


func _apply_outfit() -> void:
	if not is_node_ready() or _glb_pivot != null or robe_top == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = robe_color
	mat.roughness = 0.85
	robe_top.material_override = mat
	if robe_skirt:
		robe_skirt.material_override = mat
	if left_sleeve:
		left_sleeve.material_override = mat
	if right_sleeve:
		right_sleeve.material_override = mat
	if thobe_wrap:
		thobe_wrap.material_override = mat
		thobe_wrap.visible = is_female_thobe
	if imma_mesh:
		imma_mesh.visible = has_turban and not is_female_thobe
