extends Node3D

@export var spin_speed: float = 3.6


func _process(delta: float) -> void:
	rotate_y(spin_speed * delta)
