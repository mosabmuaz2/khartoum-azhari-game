extends Node
class_name CharacterAnimationAutoBinder

## Plug-and-Play Master Humanoid Animation Auto-Binder (`res://scripts/characters/character_animation_auto_binder.gd`).
## Attach to `Player`, `NPC`, or any future humanoid character scene.
## On `_ready()` (deferred so dynamically instantiated `.fbx` models exist), automatically:
## 1. Loads and caches `res://animations/master_humanoid_library.tres` (63 Mixamo humanoid clips)
## 2. Remaps every animation track path to the character's exact `Skeleton3D` node path & bone names
##    (supporting both `mixamorig_*` and `SkeletonProfileHumanoid` names)
## 3. Calibrates `Hips` vertical translation using origin- & scale-invariant floor height math so
##    standing, crouching, kneeling, sitting, swimming, jumping, and lying-dead clips align accurately
## 4. Registers the adapted library as `"master"` on the character's `AnimationPlayer`
## 5. Clears any stale procedural bone pose overrides and provides clean `play_state`, `play_one_shot`,
##    and `resume_animation_tree` APIs for Player, NPC roles, and VehicleSeatManager.

signal library_bound(clip_count: int)
signal one_shot_finished(clip_name: String)

const MASTER_LIBRARY_PATH: String = "res://animations/master_humanoid_library.tres"

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

const MIXAMO_TO_HUMANOID: Dictionary = {
	"mixamorig_Hips": "Hips",
	"mixamorig_Spine": "Spine",
	"mixamorig_Spine1": "Chest",
	"mixamorig_Spine2": "UpperChest",
	"mixamorig_Neck": "Neck",
	"mixamorig_Head": "Head",
	"mixamorig_LeftShoulder": "LeftShoulder",
	"mixamorig_LeftArm": "LeftUpperArm",
	"mixamorig_LeftForeArm": "LeftLowerArm",
	"mixamorig_LeftHand": "LeftHand",
	"mixamorig_RightShoulder": "RightShoulder",
	"mixamorig_RightArm": "RightUpperArm",
	"mixamorig_RightForeArm": "RightLowerArm",
	"mixamorig_RightHand": "RightHand",
	"mixamorig_LeftUpLeg": "LeftUpperLeg",
	"mixamorig_LeftLeg": "LeftLowerLeg",
	"mixamorig_LeftFoot": "LeftFoot",
	"mixamorig_LeftToeBase": "LeftToes",
	"mixamorig_RightUpLeg": "RightUpperLeg",
	"mixamorig_RightLeg": "RightLowerLeg",
	"mixamorig_RightFoot": "RightFoot",
	"mixamorig_RightToeBase": "RightToes",
}

@export var library_path: String = MASTER_LIBRARY_PATH
@export var library_name: StringName = &"master"
@export var auto_bind_on_ready: bool = true

static var _cached_master_library: AnimationLibrary = null
static var _cached_idle_hips_y: float = -1.0
static var _adapted_cache: Dictionary = {}

var skeleton: Skeleton3D = null
var anim_player: AnimationPlayer = null
var anim_tree: AnimationTree = null
var is_bound: bool = false

var _override_active: bool = false
var _one_shot_active: bool = false
var _one_shot_clip: String = ""
var _one_shot_resume_tree: bool = true
var _current_clip: String = ""


static func get_shared_master_library(path: String = MASTER_LIBRARY_PATH) -> AnimationLibrary:
	if OS.has_feature("web"):
		# On Web, skip the 18.5 MB 63-clip master library; MixamoAnimationController provides the core clips
		return null
	if path == MASTER_LIBRARY_PATH and _cached_master_library != null:
		return _cached_master_library
	if not ResourceLoader.exists(path):
		return null
	var loaded := ResourceLoader.load(path) as AnimationLibrary
	if loaded != null and path == MASTER_LIBRARY_PATH:
		_cached_master_library = loaded
		_cached_idle_hips_y = _measure_idle_hips_y(loaded)
	return loaded


static func _measure_idle_hips_y(lib: AnimationLibrary) -> float:
	if lib == null:
		return 0.98
	var probe_names: Array[StringName] = [&"Idle", &"Walk", &"Run", &"Talking"]
	for pname in probe_names:
		if lib.has_animation(pname):
			var a := lib.get_animation(pname)
			var y := _find_first_hips_pos_y(a)
			if y > 0.001:
				return y
	for aname in lib.get_animation_list():
		var a := lib.get_animation(aname)
		var y := _find_first_hips_pos_y(a)
		if y > 0.001:
			return y
	return 0.98


static func _find_first_hips_pos_y(anim: Animation) -> float:
	if anim == null:
		return -1.0
	for ti in range(anim.get_track_count()):
		if anim.track_get_type(ti) == Animation.TYPE_POSITION_3D:
			var p := String(anim.track_get_path(ti))
			if p.ends_with(":mixamorig_Hips") or p.ends_with(":Hips"):
				if anim.track_get_key_count(ti) > 0:
					return absf(anim.track_get_key_value(ti, 0).y)
	return -1.0


static func find_on_character(character: Node) -> CharacterAnimationAutoBinder:
	if character == null:
		return null
	var direct := character.get_node_or_null("CharacterAnimationAutoBinder") as CharacterAnimationAutoBinder
	if direct != null:
		return direct
	for ch in character.get_children():
		if ch is CharacterAnimationAutoBinder:
			return ch as CharacterAnimationAutoBinder
	return null


func _ready() -> void:
	if auto_bind_on_ready:
		call_deferred("bind_character")


func _exit_tree() -> void:
	if anim_player != null and is_instance_valid(anim_player):
		if anim_player.animation_finished.is_connected(_on_anim_player_finished):
			anim_player.animation_finished.disconnect(_on_anim_player_finished)
	skeleton = null
	anim_player = null
	anim_tree = null


func bind_character(target_root: Node = null) -> bool:
	var host := target_root if target_root != null else get_parent()
	if host == null:
		return false

	skeleton = _find_skeleton(host)
	if skeleton == null:
		return false

	anim_tree = _find_anim_tree(host)
	anim_player = _find_anim_player(host)
	if anim_player == null:
		anim_player = AnimationPlayer.new()
		anim_player.name = "MasterAnimPlayer"
		var skel_parent := skeleton.get_parent()
		if skel_parent != null:
			skel_parent.add_child(anim_player)
		else:
			host.add_child(anim_player)

	var master_lib := get_shared_master_library(library_path)
	if master_lib == null or master_lib.get_animation_list().is_empty():
		return false

	var ap_root: Node = anim_player.get_node_or_null(anim_player.root_node)
	if ap_root == null:
		ap_root = anim_player.get_parent()

	var skel_path := String(ap_root.get_path_to(skeleton)) if ap_root != null else String(skeleton.name)
	if skel_path.is_empty() or skel_path == ".":
		skel_path = String(skeleton.name)

	var adapted := _get_or_build_adapted_library(master_lib, skel_path, skeleton)
	if anim_player.has_animation_library(library_name):
		anim_player.remove_animation_library(library_name)
	anim_player.add_animation_library(library_name, adapted)

	if not anim_player.animation_finished.is_connected(_on_anim_player_finished):
		anim_player.animation_finished.connect(_on_anim_player_finished)

	# Clear any broken/stale procedural bone overrides so skeletal animations drive clean poses
	skeleton.clear_bones_global_pose_override()
	is_bound = true
	library_bound.emit(adapted.get_animation_list().size())
	return true


func has_clip(clip_name: String) -> bool:
	if not is_bound or anim_player == null or not is_instance_valid(anim_player):
		return false
	return anim_player.has_animation(get_full_clip_name(clip_name))


func get_full_clip_name(clip_name: String) -> StringName:
	if clip_name.contains("/"):
		return StringName(clip_name)
	return StringName("%s/%s" % [String(library_name), clip_name])


func get_clip_names() -> PackedStringArray:
	if not is_bound or anim_player == null or not is_instance_valid(anim_player):
		return PackedStringArray()
	if not anim_player.has_animation_library(library_name):
		return PackedStringArray()
	var lib := anim_player.get_animation_library(library_name)
	return lib.get_animation_list() if lib != null else PackedStringArray()


func play_state(clip_name: String, blend: float = 0.15, speed: float = 1.0, force_restart: bool = false) -> bool:
	if not is_bound and not bind_character():
		return false
	var full := get_full_clip_name(clip_name)
	if anim_player == null or not anim_player.has_animation(full):
		return false

	_override_active = true
	_one_shot_active = false
	_one_shot_clip = ""
	if anim_tree != null and is_instance_valid(anim_tree) and anim_tree.active:
		anim_tree.active = false
	if skeleton != null and is_instance_valid(skeleton):
		skeleton.clear_bones_global_pose_override()

	if (not force_restart) and anim_player.is_playing() and StringName(anim_player.current_animation) == full:
		anim_player.speed_scale = speed
		return true

	anim_player.speed_scale = speed
	anim_player.play(full, blend)
	_current_clip = clip_name
	return true


func play_one_shot(clip_name: String, blend: float = 0.10, speed: float = 1.0, resume_tree_on_finish: bool = true) -> bool:
	if not is_bound and not bind_character():
		return false
	var full := get_full_clip_name(clip_name)
	if anim_player == null or not anim_player.has_animation(full):
		return false

	_override_active = true
	_one_shot_active = true
	_one_shot_clip = clip_name
	_one_shot_resume_tree = resume_tree_on_finish

	if anim_tree != null and is_instance_valid(anim_tree) and anim_tree.active:
		anim_tree.active = false
	if skeleton != null and is_instance_valid(skeleton):
		skeleton.clear_bones_global_pose_override()

	anim_player.speed_scale = speed
	anim_player.play(full, blend)
	_current_clip = clip_name
	return true


func resume_animation_tree() -> void:
	_override_active = false
	_one_shot_active = false
	_one_shot_clip = ""
	_current_clip = ""
	if anim_player != null and is_instance_valid(anim_player):
		anim_player.speed_scale = 1.0
		if anim_player.is_playing():
			anim_player.stop()
	if skeleton != null and is_instance_valid(skeleton):
		skeleton.clear_bones_global_pose_override()
	if anim_tree != null and is_instance_valid(anim_tree):
		anim_tree.active = true


func is_override_active() -> bool:
	return _override_active


func is_one_shot_playing() -> bool:
	return _one_shot_active and anim_player != null and is_instance_valid(anim_player) and anim_player.is_playing()


func get_current_clip_name() -> String:
	return _current_clip


func _on_anim_player_finished(anim_name: StringName) -> void:
	if not _one_shot_active:
		return
	var expected := get_full_clip_name(_one_shot_clip)
	if anim_name != expected:
		return
	var finished_clip := _one_shot_clip
	_one_shot_active = false
	_one_shot_clip = ""
	if _one_shot_resume_tree:
		resume_animation_tree()
	one_shot_finished.emit(finished_clip)


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
	var rev_mapped: String = MIXAMO_TO_HUMANOID.get(track_bone, "")
	if not rev_mapped.is_empty() and skel.find_bone(rev_mapped) != -1:
		return rev_mapped
	var stripped := track_bone.replace("mixamorig_", "")
	if skel.find_bone(stripped) != -1:
		return stripped
	return ""


static func _get_or_build_adapted_library(master_lib: AnimationLibrary, skel_path: String, skel: Skeleton3D) -> AnimationLibrary:
	var hips_bone := _resolve_bone_name(skel, "mixamorig_Hips")
	if hips_bone.is_empty():
		hips_bone = skel.get_bone_name(0) if skel.get_bone_count() > 0 else "Hips"
	var hips_idx := skel.find_bone(hips_bone)
	var hips_rest_origin: Vector3 = skel.get_bone_rest(hips_idx).origin if hips_idx >= 0 else Vector3(0.0, 0.95, 0.0)
	var hips_rest_y_signed: float = hips_rest_origin.y

	var min_bone_y: float = hips_rest_y_signed
	for bi in range(skel.get_bone_count()):
		var by: float = skel.get_bone_global_rest(bi).origin.y
		if by < min_bone_y:
			min_bone_y = by
	var hips_above_feet: float = hips_rest_y_signed - min_bone_y
	if hips_above_feet < 0.0005:
		hips_above_feet = absf(hips_rest_y_signed) if absf(hips_rest_y_signed) > 0.0005 else 0.95

	var cache_key := "%s|%s|%.4f|%.4f|%d" % [
		skel_path, hips_bone, hips_rest_y_signed, hips_above_feet, skel.get_bone_count()
	]
	if _adapted_cache.has(cache_key):
		return _adapted_cache[cache_key] as AnimationLibrary

	var idle_ref_y: float = _cached_idle_hips_y if _cached_idle_hips_y > 0.001 else _measure_idle_hips_y(master_lib)
	var unit_scale: float = hips_above_feet / maxf(idle_ref_y, 0.001)

	var out := AnimationLibrary.new()
	for anim_key in master_lib.get_animation_list():
		var src_anim := master_lib.get_animation(anim_key)
		if src_anim == null:
			continue
		var anim := src_anim.duplicate(true) as Animation

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
						# Exact origin- & scale-invariant height relative to floor (min_bone_y):
						# Standing Idle -> hips_rest_y; Crouch/Kneel/Sit/Laying_Dead -> accurate lower height;
						# Jump -> accurate leap arc; horizontal X/Z locked to rest origin to prevent collider drift.
						var target_y: float = min_bone_y + v.y * unit_scale
						anim.track_set_key_value(ti, ki, Vector3(hips_rest_origin.x, target_y, hips_rest_origin.z))
				else:
					anim.remove_track(ti)

		out.add_animation(anim_key, anim)

	_adapted_cache[cache_key] = out
	return out


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for ch in node.get_children():
		var f := _find_skeleton(ch)
		if f != null:
			return f
	return null


static func _find_anim_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for ch in node.get_children():
		var f := _find_anim_player(ch)
		if f != null:
			return f
	return null


static func _find_anim_tree(node: Node) -> AnimationTree:
	if node == null:
		return null
	if node is AnimationTree:
		return node as AnimationTree
	for ch in node.get_children():
		var f := _find_anim_tree(ch)
		if f != null:
			return f
	return null
