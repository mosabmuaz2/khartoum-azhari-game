extends Node
class_name MixamoAnimationController

## Universal Shared Mixamo AnimationLibrary & Multi-State AnimationTree Controller.
## Loads the 12 Mixamo clips from `res://assets/animations/mixamo/` into one shared
## `AnimationLibrary` ("mixamo") compatible with Godot 4.7.2 `SkeletonProfileHumanoid` retargeting,
## and drives an `AnimationTree` (AnimationNodeStateMachine + BlendSpace1D, 0.15s crossfades)
## for Idle, Walk, Run, RunToStop, Jump, CrouchIdle, CrouchWalk, Slide, PickUp, Sit, Drive, Talk.

const MIXAMO_ANIM_DIR: String = "res://assets/animations/mixamo"
const CROSSFADE_SEC: float = 0.15

const HUMANOID_TO_MIXAMO: Dictionary = {
	"Hips": "mixamorig_Hips",
	"Spine": "mixamorig_Spine",
	"Chest": "mixamorig_Spine1",
	"UpperChest": "mixamorig_Spine2",
	"Neck": "mixamorig_Neck",
	"Head": "mixamorig_Head",
	"LeftShoulder": "mixamorig_LeftShoulder",
	"LeftUpperArm": "mixamorig_LeftArm",
	"LeftLowerArm": "mixamorig_LeftForeArm",
	"LeftHand": "mixamorig_LeftHand",
	"RightShoulder": "mixamorig_RightShoulder",
	"RightUpperArm": "mixamorig_RightArm",
	"RightLowerArm": "mixamorig_RightForeArm",
	"RightHand": "mixamorig_RightHand",
	"LeftUpperLeg": "mixamorig_LeftUpLeg",
	"LeftLowerLeg": "mixamorig_LeftLeg",
	"LeftFoot": "mixamorig_LeftFoot",
	"LeftToes": "mixamorig_LeftToeBase",
	"RightUpperLeg": "mixamorig_RightUpLeg",
	"RightLowerLeg": "mixamorig_RightLeg",
	"RightFoot": "mixamorig_RightFoot",
	"RightToes": "mixamorig_RightToeBase",
}

# Clip scenes -> standardized state/track names + looping flag (preloaded for Web index.pck bundling)
const CLIP_SPECS: Array[Dictionary] = [
	{"scene": preload("res://assets/animations/mixamo/Idle.fbx"),          "track": "Idle",       "loop": true},
	{"scene": preload("res://assets/animations/mixamo/Walking.fbx"),       "track": "Walk",       "loop": true},
	{"scene": preload("res://assets/animations/mixamo/Running.fbx"),       "track": "Run",        "loop": true},
	{"scene": preload("res://assets/animations/mixamo/Run To Stop.fbx"),   "track": "RunToStop",  "loop": false},
	{"scene": preload("res://assets/animations/mixamo/Jump.fbx"),          "track": "Jump",       "loop": false},
	{"scene": preload("res://assets/animations/mixamo/Crouch Idle.fbx"),   "track": "CrouchIdle", "loop": true},
	{"scene": preload("res://assets/animations/mixamo/Crouch Walk.fbx"),   "track": "CrouchWalk", "loop": true},
	{"scene": preload("res://assets/animations/mixamo/Running Slide.fbx"), "track": "Slide",      "loop": false},
	{"scene": preload("res://assets/animations/mixamo/Picking Up.fbx"),    "track": "PickUp",     "loop": false},
	{"scene": preload("res://assets/animations/mixamo/Sitting.fbx"),       "track": "Sit",        "loop": true},
	{"scene": preload("res://assets/animations/mixamo/Driving.fbx"),       "track": "Drive",      "loop": true},
	{"scene": preload("res://assets/animations/mixamo/Talking.fbx"),       "track": "Talk",       "loop": true},
]

static var _cached_shared_library: AnimationLibrary = null

var anim_player: AnimationPlayer = null
var anim_tree: AnimationTree = null
var state_playback: AnimationNodeStateMachinePlayback = null
var shared_library_loaded: bool = false
var current_state: String = "Idle"

var _pending_model_root: Node3D = null
var _prev_speed: float = 0.0
var _run_to_stop_timer: float = 0.0
var _pickup_timer: float = 0.0
var _slide_timer: float = 0.0


static func build_shared_library() -> AnimationLibrary:
	if _cached_shared_library != null and _cached_shared_library.get_animation_list().size() > 0:
		return _cached_shared_library
	var lib := AnimationLibrary.new()
	for spec in CLIP_SPECS:
		var packed := spec["scene"] as PackedScene
		var track_name: String = spec["track"]
		var is_loop: bool = spec["loop"]
		if packed == null:
			continue
		var temp_inst := packed.instantiate()
		var src_ap := _find_anim_player(temp_inst)
		if src_ap != null:
			var list := src_ap.get_animation_list()
			for a_key in list:
				if a_key == "RESET":
					continue
				var clip := src_ap.get_animation(a_key)
				if clip != null:
					var dup := clip.duplicate(true) as Animation
					dup.loop_mode = Animation.LOOP_LINEAR if is_loop else Animation.LOOP_NONE
					lib.add_animation(track_name, dup)
					break
		temp_inst.free()
	_cached_shared_library = lib
	return lib


static func attach_to_rig(pivot: Node3D, model_root: Node3D, fallback_ap: AnimationPlayer = null) -> MixamoAnimationController:
	var ctrl := MixamoAnimationController.new()
	ctrl.name = "MixamoAnimationController"

	var ap := fallback_ap if fallback_ap != null else _find_anim_player(model_root)
	var skel := _find_skeleton(model_root)
	if skel == null:
		ctrl.queue_free()
		return null

	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = "MixamoAnimPlayer"
		skel.get_parent().add_child(ap)

	ctrl.anim_player = ap

	var shared_lib := build_shared_library()
	if shared_lib.get_animation_list().size() > 0:
		var adapted := _adapt_library_for_skeleton(shared_lib, model_root, skel)
		ctrl.shared_library_loaded = true
		if ap.has_animation_library("mixamo"):
			ap.remove_animation_library("mixamo")
		ap.add_animation_library("mixamo", adapted)
		ctrl._build_animation_tree(model_root, ap)
	elif ap.get_animation_list().size() > 0:
		ctrl._build_fallback_state_machine(model_root, ap)

	pivot.add_child(ctrl)
	return ctrl


static func _resolve_bone_name(skel: Skeleton3D, track_bone: String) -> String:
	if track_bone.is_empty():
		return ""
	if skel.find_bone(track_bone) != -1:
		return track_bone
	var prefixed := "mixamorig_" + track_bone
	if skel.find_bone(prefixed) != -1:
		return prefixed
	var mapped: String = HUMANOID_TO_MIXAMO.get(track_bone, "")
	if not mapped.is_empty() and skel.find_bone(mapped) != -1:
		return mapped
	var stripped := track_bone.replace("mixamorig_", "")
	if skel.find_bone(stripped) != -1:
		return stripped
	return ""


static func _adapt_library_for_skeleton(src_lib: AnimationLibrary, model_root: Node3D, skel: Skeleton3D) -> AnimationLibrary:
	var out := AnimationLibrary.new()
	var skel_path := String(model_root.get_path_to(skel))
	if skel_path.is_empty() or skel_path == ".":
		skel_path = String(skel.name)

	var hips_bone := _resolve_bone_name(skel, "mixamorig_Hips")
	if hips_bone.is_empty():
		hips_bone = skel.get_bone_name(0) if skel.get_bone_count() > 0 else "Hips"
	var hips_idx := skel.find_bone(hips_bone)
	var hips_rest_origin: Vector3 = skel.get_bone_rest(hips_idx).origin if hips_idx >= 0 else Vector3(0.0, 0.95, 0.0)
	var hips_rest_y_signed: float = hips_rest_origin.y

	# Compute true distance from lowest foot/toe bone up to Hips in skeleton rest space
	# (works identically whether FBX origin is at the feet OR centered at the hips, and at 0.01x or 1.0x scale)
	var min_bone_y: float = hips_rest_y_signed
	for bi in range(skel.get_bone_count()):
		var by: float = skel.get_bone_global_rest(bi).origin.y
		if by < min_bone_y:
			min_bone_y = by
	var hips_above_feet: float = hips_rest_y_signed - min_bone_y
	if hips_above_feet < 0.0005:
		hips_above_feet = absf(hips_rest_y_signed) if absf(hips_rest_y_signed) > 0.0005 else 0.95

	for anim_key in src_lib.get_animation_list():
		var src_anim := src_lib.get_animation(anim_key)
		if src_anim == null:
			continue
		var anim := src_anim.duplicate(true) as Animation

		# Determine source Hips reference height to match character rest skeleton scale
		var clip_hips_y0 := 0.98
		for ti in range(anim.get_track_count()):
			if anim.track_get_type(ti) == Animation.TYPE_POSITION_3D:
				var raw_p := String(anim.track_get_path(ti))
				if raw_p.ends_with(":mixamorig_Hips") or raw_p.ends_with(":Hips"):
					if anim.track_get_key_count(ti) > 0:
						clip_hips_y0 = maxf(absf(anim.track_get_key_value(ti, 0).y), 0.001)
					break
		var pos_scale := hips_above_feet / clip_hips_y0

		for ti in range(anim.get_track_count() - 1, -1, -1):
			var raw_path := String(anim.track_get_path(ti))
			var colon := raw_path.find(":")
			var bone_sub := raw_path.substr(colon + 1) if colon >= 0 else ""
			var target_bone := _resolve_bone_name(skel, bone_sub)
			if target_bone.is_empty():
				anim.remove_track(ti)
				continue

			anim.track_set_path(ti, NodePath("%s:%s" % [skel_path, target_bone]))
			if anim.track_get_type(ti) == Animation.TYPE_POSITION_3D:
				if target_bone == hips_bone:
					var kc := anim.track_get_key_count(ti)
					for ki in range(kc):
						var v: Vector3 = anim.track_get_key_value(ti, ki)
						var target_y: float = hips_rest_y_signed + (v.y - clip_hips_y0) * pos_scale
						anim.track_set_key_value(ti, ki, Vector3(hips_rest_origin.x, target_y, hips_rest_origin.z))
				else:
					anim.remove_track(ti)

		out.add_animation(anim_key, anim)
	return out


func _ready() -> void:
	call_deferred("_activate_tree")


func _exit_tree() -> void:
	anim_player = null
	anim_tree = null
	state_playback = null
	_pending_model_root = null


func _activate_tree() -> void:
	if not is_inside_tree() or anim_tree == null or anim_player == null or _pending_model_root == null:
		return
	if not anim_tree.is_inside_tree() or not anim_player.is_inside_tree():
		return
	anim_tree.root_node = anim_tree.get_path_to(_pending_model_root)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.active = true
	state_playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if state_playback != null:
		if shared_library_loaded:
			anim_tree.set("parameters/Locomotion/blend_position", 0.0)
			if current_state in ["Idle", "Walk", "Run"]:
				state_playback.start(&"Locomotion")
			else:
				state_playback.start(StringName(current_state))
		else:
			state_playback.start(&"Idle")
	anim_tree.advance(0.05)


func _build_animation_tree(model_root: Node3D, ap: AnimationPlayer) -> void:
	_pending_model_root = model_root
	var tree := AnimationTree.new()
	tree.name = "MixamoAnimTree"
	model_root.add_child(tree)
	tree.root_node = tree.get_path_to(model_root)
	tree.anim_player = tree.get_path_to(ap)

	var sm := AnimationNodeStateMachine.new()

	# Locomotion BlendSpace1D: 0.0 -> Idle, 0.5 -> Walk, 1.0 -> Run
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 1.0
	bs.value_label = "speed"

	var idle_pt := AnimationNodeAnimation.new()
	idle_pt.animation = &"mixamo/Idle"
	bs.add_blend_point(idle_pt, 0.0, -1, &"Idle")

	var walk_pt := AnimationNodeAnimation.new()
	walk_pt.animation = &"mixamo/Walk"
	bs.add_blend_point(walk_pt, 0.45, -1, &"Walk")

	var run_pt := AnimationNodeAnimation.new()
	run_pt.animation = &"mixamo/Run"
	bs.add_blend_point(run_pt, 1.0, -1, &"Run")

	sm.add_node(&"Locomotion", bs, Vector2(0, 0))

	var state_names: Array[String] = [
		"Idle", "Walk", "Run", "RunToStop", "Jump",
		"CrouchIdle", "CrouchWalk", "Slide", "PickUp", "Sit", "Drive", "Talk"
	]
	for s_name in state_names:
		var node := AnimationNodeAnimation.new()
		node.animation = StringName("mixamo/%s" % s_name)
		sm.add_node(StringName(s_name), node)

	# Wire smooth 0.15s crossfades between Locomotion/Idle and all action/stance states
	var start_tr := AnimationNodeStateMachineTransition.new()
	start_tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", &"Locomotion", start_tr)

	for s_name in state_names:
		var tr_to := AnimationNodeStateMachineTransition.new()
		tr_to.xfade_time = CROSSFADE_SEC
		sm.add_transition(&"Locomotion", StringName(s_name), tr_to)

		var tr_back := AnimationNodeStateMachineTransition.new()
		tr_back.xfade_time = CROSSFADE_SEC
		sm.add_transition(StringName(s_name), &"Locomotion", tr_back)

		for other in state_names:
			if other != s_name:
				var tr_cross := AnimationNodeStateMachineTransition.new()
				tr_cross.xfade_time = CROSSFADE_SEC
				sm.add_transition(StringName(s_name), StringName(other), tr_cross)

	tree.tree_root = sm
	tree.active = false
	anim_tree = tree


func _build_fallback_state_machine(model_root: Node3D, ap: AnimationPlayer) -> void:
	_pending_model_root = model_root
	var tree := AnimationTree.new()
	tree.name = "MixamoFallbackTree"
	model_root.add_child(tree)
	tree.root_node = tree.get_path_to(model_root)
	tree.anim_player = tree.get_path_to(ap)
	var sm := AnimationNodeStateMachine.new()
	var list := ap.get_animation_list()
	if not list.is_empty():
		var a0 := AnimationNodeAnimation.new()
		a0.animation = StringName(list[0])
		sm.add_node(&"Idle", a0)
		var st := AnimationNodeStateMachineTransition.new()
		st.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		sm.add_transition(&"Start", &"Idle", st)
	tree.tree_root = sm
	tree.active = false
	anim_tree = tree


func update_state(
	delta: float,
	horiz_speed: float,
	grounded: bool = true,
	crouching: bool = false,
	sliding: bool = false,
	picking_up: bool = false,
	seated: bool = false,
	driving: bool = false,
	talking: bool = false
) -> void:
	if _run_to_stop_timer > 0.0:
		_run_to_stop_timer = maxf(0.0, _run_to_stop_timer - delta)
	if _pickup_timer > 0.0:
		_pickup_timer = maxf(0.0, _pickup_timer - delta)
	if _slide_timer > 0.0:
		_slide_timer = maxf(0.0, _slide_timer - delta)

	# Trigger RunToStop when decelerating rapidly from a sprint
	if _prev_speed > 6.5 and horiz_speed < 1.2 and grounded and not crouching and not sliding and not seated:
		_run_to_stop_timer = 0.45
	if picking_up:
		_pickup_timer = 0.65
	if sliding:
		_slide_timer = 0.6

	_prev_speed = horiz_speed

	var desired_state := "Idle"
	if driving:
		desired_state = "Drive"
	elif seated:
		desired_state = "Sit"
	elif not grounded:
		desired_state = "Jump"
	elif _slide_timer > 0.0 or sliding:
		desired_state = "Slide"
	elif _pickup_timer > 0.0 or picking_up:
		desired_state = "PickUp"
	elif _run_to_stop_timer > 0.0 and horiz_speed < 2.2:
		desired_state = "RunToStop"
	elif crouching:
		desired_state = "CrouchWalk" if horiz_speed > 0.2 else "CrouchIdle"
	elif talking and horiz_speed <= 0.25:
		desired_state = "Talk"
	elif horiz_speed > 5.8:
		desired_state = "Run"
	elif horiz_speed > 0.25:
		desired_state = "Walk"
	else:
		desired_state = "Idle"

	current_state = desired_state

	if anim_tree != null:
		if not anim_tree.active and is_inside_tree():
			_activate_tree()
		if state_playback != null:
			if shared_library_loaded:
				var blend_speed := clampf(horiz_speed / 9.4, 0.0, 1.0)
				anim_tree.set("parameters/Locomotion/blend_position", blend_speed)
				if desired_state in ["Idle", "Walk", "Run"]:
					state_playback.travel(&"Locomotion")
				else:
					state_playback.travel(StringName(desired_state))
			else:
				state_playback.travel(&"Idle")


static func _find_anim_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for ch in node.get_children():
		var found := _find_anim_player(ch)
		if found != null:
			return found
	return null


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for ch in node.get_children():
		var found := _find_skeleton(ch)
		if found != null:
			return found
	return null
