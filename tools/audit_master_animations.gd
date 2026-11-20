extends SceneTree

const LIB_PATH: String = "res://animations/master_humanoid_library.tres"
const BMAP_PATH: String = "res://animations/humanoid_bone_map.tres"

const EXPECTED_LOOP_CLIPS: Array[String] = [
	"Idle", "Idle_LookAround", "Walk", "Run", "Sprint", "Crouch_Idle", "Crouch_Walk",
	"Sit_Idle", "Sit_Talking", "Sit_Clap", "Sit_Pointing",
	"Yelling", "Cheering", "Talking", "Arguing", "Carrying", "Carrying_Walk",
	"Crying", "Sad_Idle", "Kneeling_Pray", "Injured_Idle", "Injured_Walk",
	"Dizzy_Idle", "Agony", "Laying_Dead_Idle",
	"Swimming", "Treading_Water", "Diving",
	"Driving", "Ride_Donkey", "Steer_Ship",
	"Cooking_Stir", "Chopping", "Dance_1", "Dance_2",
	"Falling_Idle",
]

const EXPECTED_ONESHOT_CLIPS: Array[String] = [
	"Stand_To_Sit", "Sit_To_Stand", "Pick_Up", "Put_Down",
	"Dying", "Fall_Back_Death", "Hit_Body", "Hit_Head", "Knocked_Out", "Get_Up",
	"Punch_Jab", "Punch_Hook", "Kick", "Dodge",
	"Enter_Vehicle", "Exit_Vehicle", "Wave_Hello",
	"Jump_Standard", "Jump_Running", "Jump_Flip", "Jump_High", "Landing",
	"Turn_Left", "Turn_Right", "Pointing", "Run_To_Stop", "Running_Slide",
]


func _init() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var failures: Array[String] = []

	# 1. Verify Master Library & BoneMap resources
	var bmap := ResourceLoader.load(BMAP_PATH) as BoneMap
	if bmap == null or bmap.profile == null:
		failures.append("BoneMap missing or invalid: " + BMAP_PATH)
	else:
		print("[PASS] BoneMap loaded with SkeletonProfileHumanoid")

	var lib := ResourceLoader.load(LIB_PATH) as AnimationLibrary
	if lib == null:
		failures.append("Master library failed to load: " + LIB_PATH)
		_finish(failures)
		return

	var all_names := lib.get_animation_list()
	print("[INFO] Master library clip count: %d" % all_names.size())

	var loop_ok: int = 0
	for cname in EXPECTED_LOOP_CLIPS:
		if not lib.has_animation(StringName(cname)):
			failures.append("Missing LOOP clip: " + cname)
			continue
		var a := lib.get_animation(StringName(cname))
		if a.loop_mode != Animation.LOOP_LINEAR:
			failures.append("Expected LOOP_LINEAR on %s, got %d" % [cname, a.loop_mode])
		elif a.get_track_count() < 10:
			failures.append("Too few tracks (%d) on %s" % [a.get_track_count(), cname])
		else:
			loop_ok += 1

	var oneshot_ok: int = 0
	for cname in EXPECTED_ONESHOT_CLIPS:
		if not lib.has_animation(StringName(cname)):
			failures.append("Missing ONESHOT clip: " + cname)
			continue
		var a := lib.get_animation(StringName(cname))
		if a.loop_mode != Animation.LOOP_NONE:
			failures.append("Expected LOOP_NONE on %s, got %d" % [cname, a.loop_mode])
		elif a.get_track_count() < 10:
			failures.append("Too few tracks (%d) on %s" % [a.get_track_count(), cname])
		else:
			oneshot_ok += 1

	print("[PASS] Verified %d/%d LOOP_LINEAR clips and %d/%d LOOP_NONE clips" % [
		loop_ok, EXPECTED_LOOP_CLIPS.size(), oneshot_ok, EXPECTED_ONESHOT_CLIPS.size()
	])

	# 2. Verify Player scene auto-binding, Swimming & Multi-Jump
	var player_scene := ResourceLoader.load("res://scenes/player.tscn") as PackedScene
	var player := player_scene.instantiate() as PlayerController
	root.add_child(player)
	await process_frame
	await process_frame

	var p_binder := CharacterAnimationAutoBinder.find_on_character(player)
	if p_binder == null or not p_binder.is_bound:
		failures.append("Player CharacterAnimationAutoBinder not bound!")
	else:
		print("[PASS] Player bound %d master clips on skeleton %s" % [
			p_binder.get_clip_names().size(),
			String(p_binder.skeleton.name) if p_binder.skeleton != null else "null"
		])

	# Test Player Swimming transitions: Treading_Water -> Swimming -> Diving -> Exit
	player._enter_swimming_state()
	var sw_idle := p_binder.get_current_clip_name() if p_binder != null else ""
	player._update_swimming_animation(0.05, 4.0, false, false)
	var sw_move := p_binder.get_current_clip_name() if p_binder != null else ""
	player._update_swimming_animation(0.05, 2.0, false, true)
	var sw_dive := p_binder.get_current_clip_name() if p_binder != null else ""
	player._exit_swimming_state()
	if sw_idle != "Treading_Water" or sw_move != "Swimming" or sw_dive != "Diving":
		failures.append("Swimming clip mismatch: idle=%s move=%s dive=%s" % [sw_idle, sw_move, sw_dive])
	elif p_binder != null and p_binder.is_override_active():
		failures.append("Swimming exit did not clear binder override")
	else:
		print("[PASS] Player SWIMMING state clips verified: Treading_Water -> Swimming -> Diving -> Exit")

	# Test Player Multi-Jump variations
	var seen_jumps: Dictionary = {}
	for i in range(40):
		var j := player.trigger_random_jump_animation(i % 2 == 0)
		if not j.is_empty():
			seen_jumps[j] = true
	if seen_jumps.size() < 4:
		failures.append("Multi-jump only triggered %d/4 variations: %s" % [seen_jumps.size(), str(seen_jumps.keys())])
	else:
		print("[PASS] Player multi-jump triggered all 4 variations: %s" % str(seen_jumps.keys()))

	player.queue_free()
	await process_frame

	# 3. Verify NPC scene auto-binding & ALL 10 NPCBehaviorRole values
	var npc_scene := ResourceLoader.load("res://scenes/npc.tscn") as PackedScene
	var npc := npc_scene.instantiate() as NPCInteractive
	npc.model_keyword = "Doctor"
	root.add_child(npc)
	await process_frame
	await process_frame

	var n_binder := CharacterAnimationAutoBinder.find_on_character(npc)
	if n_binder == null or not n_binder.is_bound:
		failures.append("NPC (Doctor) CharacterAnimationAutoBinder not bound!")
	else:
		print("[PASS] NPC (Doctor) bound %d master clips" % n_binder.get_clip_names().size())

	var role_results: Array[String] = []
	for role_val in range(10):
		npc.npc_behavior_role = role_val
		var played := npc.apply_behavior_role_animation(true, 1.5 if role_val == NPCInteractive.NPCBehaviorRole.CARRYING_GOODS else 0.0)
		if role_val == NPCInteractive.NPCBehaviorRole.PATROL:
			if n_binder != null and n_binder.is_override_active():
				failures.append("NPC PATROL role left override active")
			else:
				role_results.append("PATROL->AnimTree")
		else:
			if played.is_empty():
				failures.append("NPC role %d played empty clip" % role_val)
			else:
				role_results.append("%d->%s" % [role_val, played])
	print("[PASS] Verified all 10 NPCBehaviorRole values: %s" % ", ".join(role_results))

	# 4. Verify VehicleSeatManager uses master/Sit_Idle cleanly
	var veh_scene := ResourceLoader.load("res://scenes/vehicles/amjad.tscn") as PackedScene
	var veh := veh_scene.instantiate() as VehicleController
	root.add_child(veh)
	await process_frame

	npc.npc_behavior_role = NPCInteractive.NPCBehaviorRole.PATROL
	var sm := veh.get_seat_manager()
	if sm == null:
		failures.append("Amjad missing VehicleSeatManager")
	else:
		var boarded := sm.board_passenger(npc, true)
		var playing_name: String = String(n_binder.anim_player.current_animation) if (n_binder != null and n_binder.anim_player != null) else ""
		var exited := sm.exit_passenger(npc)
		if not boarded or not exited or playing_name != "master/Sit_Idle":
			failures.append("VehicleSeatManager seating check failed: boarded=%s exited=%s clip=%s" % [str(boarded), str(exited), playing_name])
		else:
			print("[PASS] VehicleSeatManager seated passenger with %s and exited cleanly" % playing_name)

	veh.queue_free()
	npc.queue_free()
	await process_frame

	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("=== AUDIT SUMMARY: ALL CHECKS PASSED (0 FAILURES) ===")
		quit(0)
	else:
		print("=== AUDIT SUMMARY: %d FAILURES ===" % failures.size())
		for f in failures:
			print("  [FAIL] " + f)
		quit(1)
