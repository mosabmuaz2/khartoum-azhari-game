@tool
extends SceneTree

## Headless builder for `res://animations/master_humanoid_library.tres` and
## `res://animations/humanoid_bone_map.tres` (Godot 4.7.2).
##
## Run via:
##   Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tools/build_master_humanoid_library.gd

const RAW_DIR: String = "res://assets/animations/mixamo_raw"
const OUT_DIR: String = "res://animations"
const OUT_LIB_PATH: String = "res://animations/master_humanoid_library.tres"
const OUT_BONEMAP_PATH: String = "res://animations/humanoid_bone_map.tres"

const LOOP_CLIPS: Dictionary = {
	"Idle": true,
	"Idle_LookAround": true,
	"Walk": true,
	"Run": true,
	"Sprint": true,
	"Crouch_Idle": true,
	"Crouch_Walk": true,
	"Sit_Idle": true,
	"Sit_Talking": true,
	"Sit_Clap": true,
	"Sit_Pointing": true,
	"Yelling": true,
	"Cheering": true,
	"Talking": true,
	"Arguing": true,
	"Carrying": true,
	"Carrying_Walk": true,
	"Crying": true,
	"Sad_Idle": true,
	"Kneeling_Pray": true,
	"Injured_Idle": true,
	"Injured_Walk": true,
	"Dizzy_Idle": true,
	"Agony": true,
	"Laying_Dead_Idle": true,
	"Swimming": true,
	"Treading_Water": true,
	"Diving": true,
	"Driving": true,
	"Ride_Donkey": true,
	"Steer_Ship": true,
	"Cooking_Stir": true,
	"Chopping": true,
	"Dance_1": true,
	"Dance_2": true,
	"Falling_Idle": true,
}

const HUMANOID_MAP_PAIRS: Dictionary = {
	"Root": "mixamorig_Hips",
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


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save_humanoid_bonemap()
	_build_master_library()
	quit(0)


func _save_humanoid_bonemap() -> void:
	var profile := SkeletonProfileHumanoid.new()
	var bmap := BoneMap.new()
	bmap.profile = profile
	for profile_bone in HUMANOID_MAP_PAIRS.keys():
		var src_bone: String = HUMANOID_MAP_PAIRS[profile_bone]
		bmap.set_skeleton_bone_name(StringName(profile_bone), StringName(src_bone))
	var err := ResourceSaver.save(bmap, OUT_BONEMAP_PATH)
	print("Saved BoneMap (%s): err=%d" % [OUT_BONEMAP_PATH, err])


func _build_master_library() -> void:
	var dir := DirAccess.open(RAW_DIR)
	if dir == null:
		push_error("Cannot open raw animations dir: %s" % RAW_DIR)
		quit(1)
		return

	var files: Array[String] = []
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.to_lower().ends_with(".fbx"):
			files.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	files.sort()

	var master_lib := AnimationLibrary.new()
	var built_count: int = 0
	var loop_count: int = 0
	var oneshot_count: int = 0
	var failed: Array[String] = []

	for fname in files:
		var clip_name := fname.get_basename()
		var fpath := "%s/%s" % [RAW_DIR, fname]
		if not ResourceLoader.exists(fpath):
			failed.append(clip_name + " (not imported)")
			continue
		var packed := ResourceLoader.load(fpath) as PackedScene
		if packed == null:
			failed.append(clip_name + " (not PackedScene)")
			continue
		var inst := packed.instantiate()
		var src_ap := _find_anim_player(inst)
		var picked_anim: Animation = null
		if src_ap != null:
			for a_key in src_ap.get_animation_list():
				if a_key == "RESET":
					continue
				var cand := src_ap.get_animation(a_key)
				if cand != null and cand.get_track_count() > 0:
					picked_anim = cand
					break
		if picked_anim == null:
			inst.free()
			failed.append(clip_name + " (no animation tracks)")
			continue

		var dup := picked_anim.duplicate(true) as Animation
		var should_loop: bool = bool(LOOP_CLIPS.get(clip_name, false))
		dup.loop_mode = Animation.LOOP_LINEAR if should_loop else Animation.LOOP_NONE

		# Normalize all bone track node prefixes to canonical `Skeleton3D:<BoneName>`
		# and drop scale tracks so character height scaling is never distorted.
		for ti in range(dup.get_track_count() - 1, -1, -1):
			if dup.track_get_type(ti) == Animation.TYPE_SCALE_3D:
				dup.remove_track(ti)
				continue
			var raw_path := String(dup.track_get_path(ti))
			var colon := raw_path.find(":")
			if colon < 0:
				dup.remove_track(ti)
				continue
			var bone_sub := raw_path.substr(colon + 1)
			if bone_sub.is_empty():
				dup.remove_track(ti)
				continue
			dup.track_set_path(ti, NodePath("Skeleton3D:%s" % bone_sub))

		if dup.get_track_count() == 0:
			inst.free()
			failed.append(clip_name + " (0 tracks after normalize)")
			continue

		master_lib.add_animation(StringName(clip_name), dup)
		built_count += 1
		if should_loop:
			loop_count += 1
		else:
			oneshot_count += 1
		inst.free()

	var save_err := ResourceSaver.save(master_lib, OUT_LIB_PATH)
	print("MASTER LIBRARY BUILT: %d clips (%d LOOP_LINEAR, %d LOOP_NONE) -> %s (save_err=%d)" % [
		built_count, loop_count, oneshot_count, OUT_LIB_PATH, save_err
	])
	if not failed.is_empty():
		print("FAILED CLIPS (%d): %s" % [failed.size(), ", ".join(failed)])


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for ch in node.get_children():
		var f := _find_anim_player(ch)
		if f != null:
			return f
	return null
