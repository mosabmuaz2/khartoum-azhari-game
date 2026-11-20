extends CharacterBody3D
class_name PedestrianAI

## AI Pedestrian strolling along Al-Azhari sidewalks in traditional Sudanese attire.
## Runs AI movement on the server (or offline preview) and syncs across ENet clients.

@export var patrol_points: PackedVector3Array = PackedVector3Array()
@export var walk_speed: float = 1.9
@export var robe_color: Color = Color(0.95, 0.94, 0.90, 1.0):
	set(value):
		robe_color = value
		_apply_robe_color()
@export var has_turban: bool = true:
	set(value):
		has_turban = value
		if is_node_ready() and imma_mesh:
			imma_mesh.visible = has_turban

@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var sync_moving: bool = false

@onready var visuals: Node3D = $Visuals
@onready var hips: Node3D = $Visuals/Hips
@onready var robe_top: MeshInstance3D = $Visuals/Hips/RobeTop
@onready var robe_skirt: MeshInstance3D = $Visuals/Hips/RobeSkirt
@onready var left_sleeve: MeshInstance3D = $Visuals/Hips/LeftArmPivot/ArmMesh
@onready var right_sleeve: MeshInstance3D = $Visuals/Hips/RightArmPivot/ArmMesh
@onready var imma_mesh: MeshInstance3D = $Visuals/Hips/HeadPivot/Imma
@onready var left_arm_pivot: Node3D = $Visuals/Hips/LeftArmPivot
@onready var right_arm_pivot: Node3D = $Visuals/Hips/RightArmPivot
@onready var left_leg_pivot: Node3D = $Visuals/Hips/LeftLegPivot
@onready var right_leg_pivot: Node3D = $Visuals/Hips/RightLegPivot
@onready var ray_left: RayCast3D = $Visuals/RayLeft
@onready var ray_right: RayCast3D = $Visuals/RayRight

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _waypoint_idx: int = 0
var _wait_timer: float = 0.0
var _anim_time: float = 0.0


func _ready() -> void:
	add_to_group("interactable")
	if not has_meta("interact_message"):
		set_meta("interact_message", "Al-Azhari Neighbor: Salam Alaykum!")

	_apply_robe_color()
	if imma_mesh:
		imma_mesh.visible = has_turban

	sync_position = global_position
	sync_yaw = visuals.rotation.y
	_anim_time = randf() * TAU


func _physics_process(delta: float) -> void:
	var runs_ai := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if not runs_ai:
		global_position = global_position.lerp(sync_position, clampf(delta * 14.0, 0.0, 1.0))
		visuals.rotation.y = lerp_angle(visuals.rotation.y, sync_yaw, clampf(delta * 14.0, 0.0, 1.0))
		_animate_walk(delta, sync_moving)
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if patrol_points.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		sync_moving = false
		_animate_walk(delta, false)
		return

	if _wait_timer > 0.0:
		_wait_timer -= delta
		velocity.x = lerpf(velocity.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		move_and_slide()
		sync_position = global_position
		sync_yaw = visuals.rotation.y
		sync_moving = false
		_animate_walk(delta, false)
		return

	var target := patrol_points[_waypoint_idx]
	var to_target := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if to_target.length() < 1.1:
		_waypoint_idx = (_waypoint_idx + 1) % patrol_points.size()
		_wait_timer = randf_range(0.4, 1.4)
		return

	var desired_dir := to_target.normalized()

	# Simple whisker raycast obstacle avoidance around players, vehicles, and poles.
	var hit_l := ray_left.is_colliding()
	var hit_r := ray_right.is_colliding()
	if hit_l and not hit_r:
		desired_dir = desired_dir.rotated(Vector3.UP, -0.85)
	elif hit_r and not hit_l:
		desired_dir = desired_dir.rotated(Vector3.UP, 0.85)
	elif hit_l and hit_r:
		desired_dir = desired_dir.rotated(Vector3.UP, 1.4)

	velocity.x = lerpf(velocity.x, desired_dir.x * walk_speed, clampf(delta * 8.0, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, desired_dir.z * walk_speed, clampf(delta * 8.0, 0.0, 1.0))

	var target_yaw := atan2(-desired_dir.x, -desired_dir.z)
	visuals.rotation.y = lerp_angle(visuals.rotation.y, target_yaw, clampf(delta * 7.0, 0.0, 1.0))

	move_and_slide()

	var horiz := Vector2(velocity.x, velocity.z).length()
	sync_position = global_position
	sync_yaw = visuals.rotation.y
	sync_moving = horiz > 0.3
	_animate_walk(delta, sync_moving)


func _animate_walk(delta: float, moving: bool) -> void:
	if moving:
		_anim_time += delta * (walk_speed * 2.4)
		var swing := sin(_anim_time) * 0.55
		left_leg_pivot.rotation.x = swing
		right_leg_pivot.rotation.x = -swing
		left_arm_pivot.rotation.x = -swing * 0.7
		right_arm_pivot.rotation.x = swing * 0.7
		hips.position.y = 0.88 + absf(cos(_anim_time)) * 0.03
	else:
		left_leg_pivot.rotation.x = lerpf(left_leg_pivot.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		right_leg_pivot.rotation.x = lerpf(right_leg_pivot.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		left_arm_pivot.rotation.x = lerpf(left_arm_pivot.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		right_arm_pivot.rotation.x = lerpf(right_arm_pivot.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		hips.position.y = lerpf(hips.position.y, 0.88, clampf(delta * 8.0, 0.0, 1.0))


func _apply_robe_color() -> void:
	if not is_node_ready() or robe_top == null:
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
