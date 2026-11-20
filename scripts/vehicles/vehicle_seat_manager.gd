extends Node
class_name VehicleSeatManager

## Unified Passenger Seating, Exit Point & Automatic Door Animation Manager
## (`res://scripts/vehicles/vehicle_seat_manager.gd`).
## Attached to every vehicle `.tscn` scene in Al-Azhari (Khartoum).
##
## Features:
## - Ordered passenger `Marker3D` seats under `../Seats` (`Seat_1_*`, `Seat_2_*`, ...)
## - Ground-level side exit markers under `../ExitPoints` (`Exit_Left`, `Exit_Right`)
## - Configurable `sit_height_offset` (-0.48), `sit_back_offset` (0.14), `seated_character_scale` (0.82)
## - Disables `AnimationTree`, `CollisionShape3D`, `NavigationAgent3D`, and physics while seated
## - Hides `Label3D` nametags & floating green status indicators while seated
## - Matches shared Mixamo/AnimationPlayer `"sit"` clip if valid, and applies skeleton-space
##   direction-aligned procedural leg bend (`Quaternion(current_dir, target_dir)` via
##   `set_bone_global_pose_override`) so thighs aim forward and shins bend cleanly down to the floor,
##   clearing overrides and restoring scale/AnimationTree cleanly on exit
## - Automatic `create_tween()` door open/close animations when `*Door*` meshes exist.

@export var sit_height_offset: float = -0.48
@export var sit_back_offset: float = 0.14
@export var seated_character_scale: float = 0.82
@export var door_open_angle_deg: float = 65.0
@export var door_swing_duration: float = 0.35
@export var door_pause_duration: float = 0.40

const FLOATING_INDICATOR_KEYWORDS: Array[String] = [
	"speaking",
	"wave",
	"status",
	"indicator",
	"ring",
	"icon",
	"marker",
	"arrow",
	"follow",
]

var _vehicle: Node3D = null
var _seats_container: Node3D = null
var _exit_points_container: Node3D = null
var _seats: Array[Marker3D] = []
var _exit_left: Marker3D = null
var _exit_right: Marker3D = null

var _occupied_seats: Dictionary = {}
var _passenger_to_seat: Dictionary = {}

var _doors: Array[Node3D] = []
var _door_base_rot_y: Dictionary = {}
var _door_tweens: Dictionary = {}
var _seat_to_door: Dictionary = {}
var _driver_door: Node3D = null


func _ready() -> void:
	_vehicle = get_parent() as Node3D
	_discover_seats_and_exits()
	call_deferred("_discover_doors")


func refresh_mappings() -> void:
	_discover_seats_and_exits()
	_discover_doors()


func _discover_seats_and_exits() -> void:
	_seats.clear()
	if _vehicle == null:
		return

	_seats_container = _vehicle.get_node_or_null("Seats") as Node3D
	if _seats_container != null:
		for ch in _seats_container.get_children():
			if ch is Marker3D:
				_seats.append(ch as Marker3D)

	_exit_points_container = _vehicle.get_node_or_null("ExitPoints") as Node3D
	if _exit_points_container != null:
		_exit_left = _exit_points_container.get_node_or_null("Exit_Left") as Marker3D
		_exit_right = _exit_points_container.get_node_or_null("Exit_Right") as Marker3D


func _discover_doors() -> void:
	_doors.clear()
	_door_base_rot_y.clear()
	_seat_to_door.clear()
	_driver_door = null
	if _vehicle == null:
		return

	_collect_door_nodes(_vehicle)
	if _doors.is_empty():
		return

	for d in _doors:
		_door_base_rot_y[d] = d.rotation.y

	var drv_pos: Vector3 = _vehicle.get("driver_seat_offset") if "driver_seat_offset" in _vehicle else Vector3(-0.4, 0.8, -0.3)
	_driver_door = _find_best_door_for_pos(drv_pos)

	for seat in _seats:
		_seat_to_door[seat] = _find_best_door_for_pos(seat.position)


func _collect_door_nodes(node: Node) -> void:
	for ch in node.get_children():
		if ch is Node3D:
			var lname := ch.name.to_lower()
			if ("door" in lname) and not ("seat" in lname) and not ("exit" in lname):
				_doors.append(ch as Node3D)
		_collect_door_nodes(ch)


func _find_best_door_for_pos(local_pos: Vector3) -> Node3D:
	if _doors.is_empty() or _vehicle == null:
		return null
	var want_left := local_pos.x < -0.05
	var want_front := local_pos.z < 0.15
	var best: Node3D = null
	var best_score := -9999.0
	var inv_v := _vehicle.global_transform.affine_inverse()

	for d in _doors:
		var ln := d.name.to_lower()
		var d_local := inv_v * d.global_position
		var score := -d_local.distance_to(local_pos)
		if want_left and (ln.ends_with("_fl") or ln.ends_with("_rl") or "left" in ln or d_local.x < 0.0):
			score += 4.0
		elif (not want_left) and (ln.ends_with("_fr") or ln.ends_with("_rr") or "right" in ln or "sliding" in ln or d_local.x >= 0.0):
			score += 4.0
		if want_front and ("_fl" in ln or "_fr" in ln or "front" in ln):
			score += 2.0
		elif (not want_front) and ("_rl" in ln or "_rr" in ln or "rear" in ln or "sliding" in ln):
			score += 2.0
		if score > best_score:
			best_score = score
			best = d
	return best


func get_seat_count() -> int:
	return _seats.size()


func get_occupied_count() -> int:
	_prune_invalid_passengers()
	return _occupied_seats.size()


func has_free_seat() -> bool:
	return _find_first_free_seat() != null


func is_passenger_seated(passenger: Node3D) -> bool:
	if passenger == null or not is_instance_valid(passenger):
		return false
	return _passenger_to_seat.has(passenger)


func get_seat_for_passenger(passenger: Node3D) -> Marker3D:
	if not is_passenger_seated(passenger):
		return null
	return _passenger_to_seat[passenger] as Marker3D


func get_exit_marker_for_seat(seat: Marker3D) -> Marker3D:
	if seat != null and seat.position.x < -0.05:
		return _exit_left if _exit_left != null else _exit_right
	return _exit_right if _exit_right != null else _exit_left


func get_exit_global_position_for_seat(seat: Marker3D) -> Vector3:
	var em := get_exit_marker_for_seat(seat)
	if em != null:
		return em.global_position
	if _vehicle != null:
		var side_x := -1.9 if (seat != null and seat.position.x < -0.05) else 1.9
		return _vehicle.to_global(Vector3(side_x, 0.05, 0.0))
	return Vector3.ZERO


func board_passenger(passenger: Node3D, reparent_to_seat: bool = true) -> bool:
	if passenger == null or not is_instance_valid(passenger):
		return false
	_prune_invalid_passengers()
	if is_passenger_seated(passenger):
		return false

	var seat := _find_first_free_seat()
	if seat == null:
		return false

	var rec: Dictionary = {
		"passenger": passenger,
		"original_parent": passenger.get_parent(),
		"original_scale": passenger.scale,
		"was_physics": passenger.is_physics_processing(),
		"colliders": [] as Array[CollisionShape3D],
		"nav_agents": [] as Array[NavigationAgent3D],
		"hidden_nodes": [] as Array[Dictionary],
		"anim_trees": [] as Array[Dictionary],
		"anim_player": null,
		"skeleton": null,
		"used_procedural_sit": false,
		"reparented": reparent_to_seat,
	}

	_disable_passenger_components(passenger, rec, passenger)

	if reparent_to_seat:
		passenger.set_physics_process(false)
		if passenger.get_parent() != seat:
			passenger.reparent(seat, false)
		passenger.position = Vector3(0.0, sit_height_offset, sit_back_offset)
		passenger.rotation = Vector3.ZERO
		passenger.scale = (rec["original_scale"] as Vector3) * seated_character_scale
		if "visuals" in passenger and passenger.visuals is Node3D:
			(passenger.visuals as Node3D).rotation = Vector3.ZERO
		if "velocity" in passenger:
			passenger.velocity = Vector3.ZERO

		_disable_animation_trees(passenger, rec)
		_apply_sitting_pose(passenger, seat, rec)

	_occupied_seats[seat] = rec
	_passenger_to_seat[passenger] = seat
	trigger_door_for_seat(seat)
	return true


func exit_passenger(passenger: Node3D) -> bool:
	if passenger == null or not is_instance_valid(passenger):
		return false
	if not _passenger_to_seat.has(passenger):
		return false

	var seat := _passenger_to_seat[passenger] as Marker3D
	var rec: Dictionary = _occupied_seats.get(seat, {})
	_passenger_to_seat.erase(passenger)
	if seat != null:
		_occupied_seats.erase(seat)

	trigger_door_for_seat(seat)
	var exit_world := get_exit_global_position_for_seat(seat)

	if bool(rec.get("reparented", true)):
		var skel := rec.get("skeleton") as Skeleton3D
		if skel != null and is_instance_valid(skel):
			skel.clear_bones_global_pose_override()

		var binder := CharacterAnimationAutoBinder.find_on_character(passenger)
		if binder != null and binder.is_override_active():
			binder.resume_animation_tree()

		var ap := rec.get("anim_player") as AnimationPlayer
		if ap != null and is_instance_valid(ap) and ap.is_playing():
			ap.stop()

		_restore_animation_trees(rec)

		var orig_parent := rec.get("original_parent") as Node
		var target_parent: Node = orig_parent if (orig_parent != null and is_instance_valid(orig_parent)) else get_tree().current_scene
		if target_parent != null and passenger.get_parent() != target_parent:
			passenger.reparent(target_parent, true)
		passenger.scale = rec.get("original_scale", Vector3.ONE) as Vector3
		passenger.global_position = exit_world
		passenger.rotation = Vector3(0.0, _vehicle.rotation.y if _vehicle != null else 0.0, 0.0)
		if "velocity" in passenger:
			passenger.velocity = Vector3.ZERO
		if bool(rec.get("was_physics", true)):
			passenger.set_physics_process(true)

	_restore_passenger_components(rec)
	return true


func exit_all_passengers() -> void:
	var passengers: Array = _passenger_to_seat.keys().duplicate()
	for p in passengers:
		if p is Node3D and is_instance_valid(p):
			exit_passenger(p as Node3D)


func trigger_driver_door() -> void:
	if _driver_door != null and is_instance_valid(_driver_door):
		_animate_door(_driver_door, true)


func trigger_door_for_seat(seat: Marker3D) -> void:
	if seat == null:
		return
	var door := _seat_to_door.get(seat) as Node3D
	if door == null or not is_instance_valid(door):
		return
	var is_left := seat.position.x < -0.05
	_animate_door(door, is_left)


func _animate_door(door: Node3D, is_left_side: bool) -> void:
	if door == null or not is_instance_valid(door):
		return
	var prev_tw := _door_tweens.get(door) as Tween
	if prev_tw != null and prev_tw.is_valid():
		prev_tw.kill()

	var base_y: float = float(_door_base_rot_y.get(door, door.rotation.y))
	var sign_dir: float = 1.0 if is_left_side else -1.0
	var open_y: float = base_y + deg_to_rad(door_open_angle_deg * sign_dir)

	var tw := create_tween()
	tw.tween_property(door, "rotation:y", open_y, door_swing_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(door_pause_duration)
	tw.tween_property(door, "rotation:y", base_y, door_swing_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_door_tweens[door] = tw


func _find_first_free_seat() -> Marker3D:
	for seat in _seats:
		if not _occupied_seats.has(seat):
			return seat
	return null


func _prune_invalid_passengers() -> void:
	var dead_seats: Array[Marker3D] = []
	for seat in _occupied_seats.keys():
		var rec: Dictionary = _occupied_seats[seat]
		var p := rec.get("passenger") as Node3D
		if p == null or not is_instance_valid(p):
			dead_seats.append(seat)
	for s in dead_seats:
		_occupied_seats.erase(s)
	var dead_p: Array = []
	for p in _passenger_to_seat.keys():
		if p == null or not is_instance_valid(p):
			dead_p.append(p)
	for dp in dead_p:
		_passenger_to_seat.erase(dp)


func _disable_passenger_components(node: Node, rec: Dictionary, root_passenger: Node3D) -> void:
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if not cs.disabled:
			cs.disabled = true
			(rec["colliders"] as Array).append(cs)
	elif node is NavigationAgent3D:
		var na := node as NavigationAgent3D
		na.set_physics_process(false)
		na.set_process(false)
		(rec["nav_agents"] as Array).append(na)
	elif node is Label3D:
		var lbl := node as Label3D
		if lbl.visible:
			(rec["hidden_nodes"] as Array).append({"node": lbl, "was_visible": true})
			lbl.visible = false
	elif node is Node3D and node != root_passenger:
		var n3 := node as Node3D
		if _is_floating_status_indicator(n3):
			if n3.visible:
				(rec["hidden_nodes"] as Array).append({"node": n3, "was_visible": true})
				n3.visible = false
			return

	for ch in node.get_children():
		_disable_passenger_components(ch, rec, root_passenger)


func _is_floating_status_indicator(node: Node3D) -> bool:
	if node is Skeleton3D or node is BoneAttachment3D or node.get_parent() is BoneAttachment3D:
		return false
	var ln := node.name.to_lower()
	for kw in FLOATING_INDICATOR_KEYWORDS:
		if kw in ln:
			return true
	if node is MeshInstance3D and node.position.y > 1.85 and node.get_parent() != null and not (node.get_parent() is Skeleton3D):
		var mat := (node as MeshInstance3D).get_active_material(0) as BaseMaterial3D
		if mat != null and (mat.albedo_color.g > mat.albedo_color.r + 0.15 or mat.emission_enabled):
			return true
	return false


func _restore_passenger_components(rec: Dictionary) -> void:
	for cs in rec.get("colliders", []):
		if cs is CollisionShape3D and is_instance_valid(cs):
			(cs as CollisionShape3D).disabled = false
	for na in rec.get("nav_agents", []):
		if na is NavigationAgent3D and is_instance_valid(na):
			(na as NavigationAgent3D).set_physics_process(true)
			(na as NavigationAgent3D).set_process(true)
	for hinfo in rec.get("hidden_nodes", []):
		var n3 := hinfo.get("node") as Node3D
		if n3 != null and is_instance_valid(n3):
			n3.visible = bool(hinfo.get("was_visible", true))


func _disable_animation_trees(node: Node, rec: Dictionary) -> void:
	if node is AnimationTree:
		var at := node as AnimationTree
		(rec["anim_trees"] as Array).append({"tree": at, "was_active": at.active})
		at.active = false
	for ch in node.get_children():
		_disable_animation_trees(ch, rec)


func _restore_animation_trees(rec: Dictionary) -> void:
	for tinfo in rec.get("anim_trees", []):
		var at := tinfo.get("tree") as AnimationTree
		if at != null and is_instance_valid(at):
			at.active = bool(tinfo.get("was_active", true))


func _apply_sitting_pose(passenger: Node, seat: Marker3D, rec: Dictionary) -> void:
	var skel := _find_skeleton(passenger)
	rec["skeleton"] = skel

	# 1. Prefer CharacterAnimationAutoBinder's master humanoid `Sit_Idle` clip first
	var played_sit_clip := false
	var binder := CharacterAnimationAutoBinder.find_on_character(passenger)
	if binder != null:
		if not binder.is_bound:
			binder.bind_character(passenger)
		if binder.has_clip("Sit_Idle"):
			binder.play_state("Sit_Idle", 0.08, 1.0, true)
			if binder.anim_player != null:
				rec["anim_player"] = binder.anim_player
				binder.anim_player.advance(0.1)
			played_sit_clip = true

	# 2. Fallback: search AnimationPlayer(s) case-insensitively for a `"sit"` clip
	if not played_sit_clip:
		var aps: Array[AnimationPlayer] = []
		_collect_animation_players(passenger, aps)
		for ap in aps:
			var best_anim := _find_sit_animation_name(ap)
			if best_anim != "":
				rec["anim_player"] = ap
				ap.play(best_anim)
				ap.advance(0.1)
				played_sit_clip = true
				break

	# 3. Verify whether the clip actually bends legs cleanly for a car seat (thigh forward, shin down);
	#    if no clip exists or the clip leaves thighs straight down / shins sticking forward, apply
	#    skeleton-space direction-aligned procedural leg overrides cleanly!
	if skel != null:
		if (not played_sit_clip) or (not _is_skeleton_legs_bent_for_car(skel, seat)):
			rec["used_procedural_sit"] = true
			_apply_procedural_sit_pose(skel, seat)


func _find_sit_animation_name(ap: AnimationPlayer) -> String:
	var list := ap.get_animation_list()
	var fallback := ""
	for aname in list:
		var low := String(aname).to_lower()
		if low == "master/sit_idle":
			return String(aname)
	for aname in list:
		var low := String(aname).to_lower()
		if "sit" in low:
			if low == "mixamo/sit" or low == "sit" or low == "sitting" or low == "sit_idle" or low.ends_with("/sit_idle") or low.ends_with("/sit"):
				return String(aname)
			if fallback == "":
				fallback = String(aname)
	return fallback


func _is_skeleton_legs_bent_for_car(skeleton: Skeleton3D, seat: Marker3D) -> bool:
	var up_idx := _find_first_bone(skeleton, ["mixamorig_LeftUpLeg", "LeftUpLeg"])
	var low_idx := _find_first_bone(skeleton, ["mixamorig_LeftLeg", "LeftLeg"])
	var foot_idx := _find_first_bone(skeleton, ["mixamorig_LeftFoot", "LeftFoot"])
	if up_idx < 0 or low_idx < 0 or foot_idx < 0:
		return false
	var seat_from_skel: Basis = Basis.IDENTITY
	if seat != null and is_instance_valid(seat):
		seat_from_skel = seat.global_transform.basis.orthonormalized().inverse() * skeleton.global_transform.basis.orthonormalized()
	var up_p: Vector3 = skeleton.get_bone_global_pose(up_idx).origin
	var low_p: Vector3 = skeleton.get_bone_global_pose(low_idx).origin
	var foot_p: Vector3 = skeleton.get_bone_global_pose(foot_idx).origin
	var thigh_dir: Vector3 = (seat_from_skel * (low_p - up_p)).normalized()
	var shin_dir: Vector3 = (seat_from_skel * (foot_p - low_p)).normalized()
	# Require thighs pointing predominantly forward (-Z) and shins pointing predominantly downward (-Y)
	return thigh_dir.dot(Vector3(0.0, 0.08, -1.0).normalized()) > 0.72 and shin_dir.dot(Vector3(0.0, -1.0, -0.12).normalized()) > 0.72


func _apply_procedural_sit_pose(skeleton: Skeleton3D, seat: Marker3D = null) -> void:
	if skeleton == null:
		return
	skeleton.clear_bones_global_pose_override()

	# Transform seat-space target directions into skeleton-local space so Mixamo (PI-flipped)
	# and unflipped rigs both bend thighs forward (-Z in seat) and shins down (-Y in seat)
	var skel_from_seat: Basis = Basis.IDENTITY
	if seat != null and is_instance_valid(seat):
		skel_from_seat = skeleton.global_transform.basis.orthonormalized().inverse() * seat.global_transform.basis.orthonormalized()

	var target_thigh_dir: Vector3 = (skel_from_seat * Vector3(0.0, 0.08, -1.0)).normalized()
	var target_shin_dir: Vector3 = (skel_from_seat * Vector3(0.0, -1.0, -0.12)).normalized()

	var leg_chains: Array[Dictionary] = [
		{
			"up": ["mixamorig_LeftUpLeg", "LeftUpLeg"],
			"low": ["mixamorig_LeftLeg", "LeftLeg"],
			"foot": ["mixamorig_LeftFoot", "LeftFoot"],
		},
		{
			"up": ["mixamorig_RightUpLeg", "RightUpLeg"],
			"low": ["mixamorig_RightLeg", "RightLeg"],
			"foot": ["mixamorig_RightFoot", "RightFoot"],
		},
	]

	for chain in leg_chains:
		var up_idx := _find_first_bone(skeleton, chain["up"])
		var low_idx := _find_first_bone(skeleton, chain["low"])
		var foot_idx := _find_first_bone(skeleton, chain["foot"])
		if up_idx < 0 or low_idx < 0:
			continue

		# 1. Aim upper leg (UpLeg -> Leg) forward along Vector3(0.0, 0.08, -1.0)
		var up_pose: Transform3D = skeleton.get_bone_global_pose_no_override(up_idx)
		var low_pose: Transform3D = skeleton.get_bone_global_pose_no_override(low_idx)
		var thigh_vec: Vector3 = low_pose.origin - up_pose.origin
		var thigh_len: float = thigh_vec.length()
		if thigh_len < 0.0001:
			continue
		var cur_thigh_dir: Vector3 = thigh_vec / thigh_len
		var q_thigh := Quaternion(cur_thigh_dir, target_thigh_dir)
		var new_up_pose := Transform3D(Basis(q_thigh) * up_pose.basis, up_pose.origin)
		skeleton.set_bone_global_pose_override(up_idx, new_up_pose, 1.0, true)

		var new_knee_origin: Vector3 = up_pose.origin + (q_thigh * thigh_vec)

		# 2. Aim lower leg (Leg -> Foot) downward toward floor along Vector3(0.0, -1.0, -0.12)
		var foot_pose := Transform3D.IDENTITY
		var shin_len: float = 0.0
		var cur_shin_dir: Vector3 = target_thigh_dir
		if foot_idx >= 0:
			foot_pose = skeleton.get_bone_global_pose_no_override(foot_idx)
			var orig_shin_vec: Vector3 = foot_pose.origin - low_pose.origin
			shin_len = orig_shin_vec.length()
			if shin_len > 0.0001:
				cur_shin_dir = (q_thigh * orig_shin_vec).normalized()

		var rotated_low_basis: Basis = Basis(q_thigh) * low_pose.basis
		var q_shin := Quaternion(cur_shin_dir, target_shin_dir)
		var new_low_pose := Transform3D(Basis(q_shin) * rotated_low_basis, new_knee_origin)
		skeleton.set_bone_global_pose_override(low_idx, new_low_pose, 1.0, true)

		# 3. Keep foot cleanly connected to the end of the lower leg
		if foot_idx >= 0 and shin_len > 0.0001:
			var new_foot_origin: Vector3 = new_knee_origin + target_shin_dir * shin_len
			var new_foot_basis: Basis = Basis(q_shin) * (Basis(q_thigh) * foot_pose.basis)
			skeleton.set_bone_global_pose_override(foot_idx, Transform3D(new_foot_basis, new_foot_origin), 1.0, true)


func _find_first_bone(skeleton: Skeleton3D, names: Array) -> int:
	for bname in names:
		var idx := skeleton.find_bone(String(bname))
		if idx >= 0:
			return idx
	return -1


func _collect_animation_players(node: Node, out: Array[AnimationPlayer]) -> void:
	if node is AnimationPlayer:
		out.append(node as AnimationPlayer)
	for ch in node.get_children():
		_collect_animation_players(ch, out)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for ch in node.get_children():
		var found := _find_skeleton(ch)
		if found != null:
			return found
	return null
