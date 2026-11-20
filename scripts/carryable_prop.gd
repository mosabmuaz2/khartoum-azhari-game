extends RigidBody3D
class_name CarryableProp

## Physical street object (crate, jerrycan, cardboard box, football, stone) that the player
## can bend down and pick up (`[G] حمل / رفع`), carry in their hands, drop (`[G]`), or throw (`Left Click`).

@export var prop_label: String = "صندوق خشب"
@export var hold_offset: Vector3 = Vector3(0.0, 1.08, -0.78)
@export var throw_impulse: float = 11.5

var is_carried: bool = false
var carrier_node: Node3D = null


func _ready() -> void:
	add_to_group("carryable_props")
	collision_layer = 2
	collision_mask = 7
	mass = 0.85


func pick_up(carrier: Node3D) -> void:
	if carrier == null:
		return
	is_carried = true
	carrier_node = carrier
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func drop_object(drop_pos: Vector3, carrier_vel: Vector3 = Vector3.ZERO) -> void:
	is_carried = false
	carrier_node = null
	global_position = drop_pos
	collision_layer = 2
	collision_mask = 7
	freeze = false
	linear_velocity = carrier_vel * 0.5 + Vector3(0.0, -0.5, 0.0)


func throw_object(throw_dir: Vector3, carrier_vel: Vector3 = Vector3.ZERO) -> void:
	is_carried = false
	carrier_node = null
	collision_layer = 2
	collision_mask = 7
	freeze = false
	linear_velocity = carrier_vel * 0.35
	apply_central_impulse(throw_dir.normalized() * throw_impulse + Vector3(0.0, 3.2, 0.0))


func _physics_process(_delta: float) -> void:
	if is_carried and carrier_node != null and is_instance_valid(carrier_node):
		var basis_rot := carrier_node.global_transform.basis
		global_position = carrier_node.global_position + basis_rot * hold_offset
		global_rotation = Vector3(0.0, carrier_node.global_rotation.y, 0.0)
