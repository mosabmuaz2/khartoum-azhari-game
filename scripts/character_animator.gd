extends Node
class_name CharacterAnimator

## Dual-Mode Limb Articulation Controller for Player (Host), Named NPCs, Crowd Clones, and Traffic Drivers.
## Mode 1 ("skeleton"): Drives Skeleton3D hip/thigh/knee strides, counter-swinging upper/lower arms, spine twist, and idle breathing.
## Mode 2 ("shader"): Attaches `res://shaders/character_limb_anim.gdshader` to unrigged single-mesh .glb characters
##                    while keeping materials brightly lit (`vertex_color_use_as_albedo = false`, `albedo_color = Color(1,1,1,1)`, `metallic = 0.0`).

const LIMB_SHADER_PATH: String = "res://shaders/character_limb_anim.gdshader"
const LIMB_SHADER_RES: Shader = preload("res://shaders/character_limb_anim.gdshader")

var mode: String = "shader" # "mixamo_tree", "anim_player", "skeleton", or "shader"
var mixamo_ctrl: MixamoAnimationController = null
var anim_player: AnimationPlayer = null
var skeleton: Skeleton3D = null
var bone_map: Dictionary = {}
var shader_materials: Array[ShaderMaterial] = []
var standard_materials: Array[StandardMaterial3D] = []
var target_pivot: Node3D = null

var _walk_phase: float = 0.0
var _idle_time: float = 0.0
var _cur_walk_amt: float = 0.0
var _cur_run_amt: float = 0.0


static func get_limb_shader() -> Shader:
	return LIMB_SHADER_RES


static func attach(pivot: Node3D, model_root: Node3D, fallback_tex: Texture2D) -> CharacterAnimator:
	var anim := CharacterAnimator.new()
	anim.name = "CharacterAnimator"
	anim.target_pivot = pivot
	anim._idle_time = randf() * TAU
	anim._walk_phase = randf() * TAU

	var ap := _find_animation_player(model_root)
	var skel := _find_skeleton(model_root)
	var bones := _map_skeleton_bones(skel) if skel != null else {}
	if skel != null:
		var mx := MixamoAnimationController.attach_to_rig(pivot, model_root, ap)
		if mx != null and mx.shared_library_loaded:
			anim.mode = "mixamo_tree"
			anim.mixamo_ctrl = mx
			anim.anim_player = mx.anim_player
			anim.skeleton = skel
			anim.bone_map = bones
			_apply_materials_recursive(model_root, fallback_tex, false, anim)
	if anim.mode != "mixamo_tree":
		if ap != null and ap.get_animation_list().size() > 0:
			anim.mode = "anim_player"
			anim.anim_player = ap
			_apply_materials_recursive(model_root, fallback_tex, false, anim)
		elif skel != null and (bones.has("l_thigh") or bones.has("l_arm")):
			anim.mode = "skeleton"
			anim.skeleton = skel
			anim.bone_map = bones
			_apply_materials_recursive(model_root, fallback_tex, false, anim)
		else:
			anim.mode = "shader"
			_apply_materials_recursive(model_root, fallback_tex, true, anim)

	pivot.set_meta("character_animator", anim)
	pivot.add_child(anim)
	# Apply initial non-T-pose idle posture immediately on spawn
	anim.update_animation(0.016, 0.0, false, false, false)
	return anim


func _exit_tree() -> void:
	shader_materials.clear()
	standard_materials.clear()
	bone_map.clear()
	mixamo_ctrl = null
	anim_player = null
	skeleton = null
	target_pivot = null


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for ch in node.get_children():
		var found := _find_animation_player(ch)
		if found != null:
			return found
	return null


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for ch in node.get_children():
		var found := _find_skeleton(ch)
		if found != null:
			return found
	return null


static func _map_skeleton_bones(skel: Skeleton3D) -> Dictionary:
	var bmap := {}
	if skel == null:
		return bmap
	for i in range(skel.get_bone_count()):
		var bname := skel.get_bone_name(i).to_lower()
		var is_left := ("left" in bname or ".l" in bname or "_l" in bname)
		var is_right := ("right" in bname or ".r" in bname or "_r" in bname)
		if "thigh" in bname or "upleg" in bname or "upperleg" in bname:
			if is_left:
				bmap["l_thigh"] = i
			elif is_right:
				bmap["r_thigh"] = i
		elif "calf" in bname or "leg" in bname or "shin" in bname or "knee" in bname:
			if is_left and not bmap.has("l_knee"):
				bmap["l_knee"] = i
			elif is_right and not bmap.has("r_knee"):
				bmap["r_knee"] = i
		elif "forearm" in bname or "lowerarm" in bname or "elbow" in bname:
			if is_left:
				bmap["l_forearm"] = i
			elif is_right:
				bmap["r_forearm"] = i
		elif "arm" in bname or "shoulder" in bname:
			if is_left and not bmap.has("l_arm"):
				bmap["l_arm"] = i
			elif is_right and not bmap.has("r_arm"):
				bmap["r_arm"] = i
		elif "spine" in bname or "chest" in bname:
			if not bmap.has("spine"):
				bmap["spine"] = i
		elif "head" in bname or "neck" in bname:
			if not bmap.has("head"):
				bmap["head"] = i
	return bmap


static func _apply_materials_recursive(node: Node, fallback_tex: Texture2D, use_limb_shader: bool, anim: CharacterAnimator) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.visibility_range_end = 95.0
		if mi.mesh != null:
			var mesh_aabb := mi.get_aabb()
			var surf_count := mi.mesh.get_surface_count()
			for s_idx in range(surf_count):
				var orig := mi.get_active_material(s_idx)
				var tex: Texture2D = fallback_tex
				if orig is BaseMaterial3D and (orig as BaseMaterial3D).albedo_texture != null:
					tex = (orig as BaseMaterial3D).albedo_texture

				# Always prepare a brightly lit StandardMaterial3D reference
				var std_mat := StandardMaterial3D.new()
				std_mat.albedo_texture = tex
				std_mat.vertex_color_use_as_albedo = false
				std_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
				std_mat.metallic = 0.0
				std_mat.roughness = 0.85
				std_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				std_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
				std_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				std_mat.backlight_enabled = true
				std_mat.backlight = Color(0.35, 0.33, 0.30, 1.0)
				if tex != null:
					std_mat.emission_enabled = true
					std_mat.emission_texture = tex
					std_mat.emission_energy_multiplier = 0.24
				anim.standard_materials.append(std_mat)

				var shd := get_limb_shader()
				if use_limb_shader and shd != null:
					var smat := ShaderMaterial.new()
					smat.shader = shd
					if tex != null:
						smat.set_shader_parameter("albedo_texture", tex)
					smat.set_shader_parameter("albedo_color", Color(1.0, 1.0, 1.0, 1.0))
					smat.set_shader_parameter("vertex_color_use_as_albedo", false)
					smat.set_shader_parameter("metallic", 0.0)
					smat.set_shader_parameter("roughness", 0.85)
					smat.set_shader_parameter("backlight", Color(0.35, 0.33, 0.30, 1.0))
					smat.set_shader_parameter("aabb_min", mesh_aabb.position)
					smat.set_shader_parameter("aabb_size", mesh_aabb.size)
					mi.set_surface_override_material(s_idx, smat)
					anim.shader_materials.append(smat)
				else:
					mi.set_surface_override_material(s_idx, std_mat)

	for ch in node.get_children():
		_apply_materials_recursive(ch, fallback_tex, use_limb_shader, anim)


func update_animation(delta: float, horiz_speed: float, seated: bool = false, driving: bool = false, airborne: bool = false, crouch_amt: float = 0.0, slide_amt: float = 0.0, carry_amt: float = 0.0, pickup_bend_amt: float = 0.0, talking: bool = false) -> void:
	_idle_time += delta
	var target_walk := clampf(horiz_speed / 2.1, 0.0, 1.0) if (horiz_speed > 0.1 and not seated and slide_amt < 0.2) else 0.0
	var target_run := clampf((horiz_speed - 3.2) / 3.5, 0.0, 1.0) if (horiz_speed > 3.2 and not seated and slide_amt < 0.2) else 0.0

	_cur_walk_amt = lerpf(_cur_walk_amt, target_walk, clampf(delta * 10.0, 0.0, 1.0))
	_cur_run_amt = lerpf(_cur_run_amt, target_run, clampf(delta * 10.0, 0.0, 1.0))

	if horiz_speed > 0.1 and not seated and slide_amt < 0.2:
		var freq := lerpf(3.4, 5.2, _cur_run_amt)
		_walk_phase += delta * maxf(horiz_speed, 1.2) * freq
	else:
		# Smoothly return limbs toward neutral stance
		_walk_phase = lerp_angle(_walk_phase, 0.0, clampf(delta * 6.0, 0.0, 1.0))

	if mode == "mixamo_tree" and mixamo_ctrl != null:
		mixamo_ctrl.update_state(delta, horiz_speed, not airborne, crouch_amt > 0.3, slide_amt > 0.1, pickup_bend_amt > 0.1, seated, driving, talking)
		return
	elif mode == "anim_player" and anim_player != null:
		_update_anim_player(horiz_speed)
	elif mode == "skeleton" and skeleton != null:
		_update_skeleton_pose(seated, driving, airborne, crouch_amt, slide_amt, carry_amt, pickup_bend_amt)
	else:
		for smat in shader_materials:
			if smat != null:
				smat.set_shader_parameter("walk_phase", _walk_phase)
				smat.set_shader_parameter("walk_amount", _cur_walk_amt)
				smat.set_shader_parameter("run_amount", _cur_run_amt)
				smat.set_shader_parameter("idle_time", _idle_time)
				smat.set_shader_parameter("is_seated", 1.0 if seated else 0.0)
				smat.set_shader_parameter("is_driving", 1.0 if driving else 0.0)
				smat.set_shader_parameter("is_airborne", 1.0 if airborne else 0.0)
				smat.set_shader_parameter("crouch_amount", clampf(crouch_amt, 0.0, 1.0))
				smat.set_shader_parameter("slide_amount", clampf(slide_amt, 0.0, 1.0))
				smat.set_shader_parameter("carry_amount", clampf(carry_amt, 0.0, 1.0))
				smat.set_shader_parameter("pickup_bend", clampf(pickup_bend_amt, 0.0, 1.0))

	# Vertical cadence bounce on pivot without rigid "stone-statue" side-tilting
	if target_pivot != null:
		if seated:
			target_pivot.position = Vector3(0.0, -0.16, 0.0)
			target_pivot.rotation = Vector3.ZERO
		elif slide_amt > 0.1:
			target_pivot.position = Vector3(0.0, -0.24 * slide_amt, 0.0)
			target_pivot.rotation = Vector3(0.32 * slide_amt, 0.0, 0.0)
		elif airborne:
			target_pivot.position = Vector3(0.0, 0.06, 0.0)
			target_pivot.rotation = Vector3(-0.08, 0.0, 0.0)
		else:
			var bob := absf(sin(_walk_phase)) * (0.042 * _cur_walk_amt + 0.032 * _cur_run_amt)
			var forward_lean := -0.05 * _cur_walk_amt - 0.10 * _cur_run_amt - 0.12 * crouch_amt - 0.25 * pickup_bend_amt
			target_pivot.position = Vector3(0.0, bob - 0.12 * crouch_amt, 0.0)
			target_pivot.rotation = Vector3(forward_lean, 0.0, 0.0)


func _update_anim_player(horiz_speed: float) -> void:
	var list := anim_player.get_animation_list()
	if list.is_empty():
		return
	var desired := list[0]
	for a_name in list:
		var low := a_name.to_lower()
		if horiz_speed > 3.5 and ("run" in low or "sprint" in low):
			desired = a_name
			break
		elif horiz_speed > 0.15 and ("walk" in low or "move" in low):
			desired = a_name
			break
		elif horiz_speed <= 0.15 and ("idle" in low or "stand" in low):
			desired = a_name
			break
	if anim_player.current_animation != desired:
		anim_player.play(desired)


func _update_skeleton_pose(seated: bool, driving: bool, airborne: bool, crouch_amt: float = 0.0, slide_amt: float = 0.0, carry_amt: float = 0.0, pickup_bend_amt: float = 0.0) -> void:
	var stride := sin(_walk_phase) * (0.58 * _cur_walk_amt + 0.32 * _cur_run_amt) - 0.55 * crouch_amt
	var knee_l := maxf(0.0, -cos(_walk_phase)) * (0.65 * _cur_walk_amt + 0.45 * _cur_run_amt) + 0.85 * crouch_amt
	var knee_r := maxf(0.0, cos(_walk_phase)) * (0.65 * _cur_walk_amt + 0.45 * _cur_run_amt) + 0.85 * crouch_amt
	var arm_swing := -stride * 0.85
	# Lower arms from T-pose down to natural sides by ~70 degrees (1.18 rad) on Z-axis
	var tpose_lower_rad := deg_to_rad(68.0)

	if carry_amt > 0.1:
		arm_swing = -0.92
	elif pickup_bend_amt > 0.1:
		arm_swing = -1.15

	if seated:
		stride = -1.32
		knee_l = 1.32
		knee_r = 1.32
		arm_swing = -0.88 if driving else -0.35
	elif slide_amt > 0.1:
		stride = -1.05
		knee_l = 0.35
		knee_r = 1.15
	elif airborne:
		stride = -0.45
		knee_l = 0.55
		knee_r = 0.55
		if carry_amt < 0.1:
			arm_swing = -0.55

	if bone_map.has("l_thigh"):
		skeleton.set_bone_pose_rotation(int(bone_map["l_thigh"]), Quaternion(Vector3.RIGHT, stride))
	if bone_map.has("r_thigh"):
		skeleton.set_bone_pose_rotation(int(bone_map["r_thigh"]), Quaternion(Vector3.RIGHT, -stride if (not seated and slide_amt < 0.1) else stride))
	if bone_map.has("l_knee"):
		skeleton.set_bone_pose_rotation(int(bone_map["l_knee"]), Quaternion(Vector3.RIGHT, knee_l))
	if bone_map.has("r_knee"):
		skeleton.set_bone_pose_rotation(int(bone_map["r_knee"]), Quaternion(Vector3.RIGHT, knee_r))
	if bone_map.has("l_arm"):
		var q_l := Quaternion(Vector3.FORWARD, tpose_lower_rad) * Quaternion(Vector3.RIGHT, arm_swing)
		skeleton.set_bone_pose_rotation(int(bone_map["l_arm"]), q_l)
	if bone_map.has("r_arm"):
		var r_swing := (-arm_swing if (not seated and carry_amt < 0.1 and pickup_bend_amt < 0.1) else arm_swing)
		var q_r := Quaternion(Vector3.FORWARD, -tpose_lower_rad) * Quaternion(Vector3.RIGHT, r_swing)
		skeleton.set_bone_pose_rotation(int(bone_map["r_arm"]), q_r)
	if bone_map.has("spine") and not seated:
		var twist := sin(_walk_phase) * 0.08 * _cur_walk_amt
		skeleton.set_bone_pose_rotation(int(bone_map["spine"]), Quaternion(Vector3.UP, twist))
	if bone_map.has("head") and _cur_walk_amt < 0.2:
		var look := sin(_idle_time * 0.85) * 0.15
		skeleton.set_bone_pose_rotation(int(bone_map["head"]), Quaternion(Vector3.UP, look))
