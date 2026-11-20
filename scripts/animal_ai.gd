extends Node3D
class_name AnimalAI

## Detailed Multi-Part Articulated Khartoum Animals (Street Dogs, Cats, Goats, Rideable Sudanese Donkeys)
## with Multi-Animation State Machine:
## WALK, TROT_RUN, GRAZE_EAT, SIT_LIE_DOWN, IDLE_LOOK, VOCALIZE_WAG
##
## Donkey Overhaul:
## - True 1:1 anatomical proportions with smoothly blended torso, sloped neck, mane, sculpted muzzle/nostrils/eyes
## - Firmly anchored rear-hip TailPivot with connected upper/lower tail & dark tassel (gentle pendulum swish)
## - Articulated Leg_FL, Leg_FR, Leg_RL, Leg_RR hip/shoulder pivots & lower knee/hock joints
## - Contoured quilted Sudanese padded saddle (بردعة) with belly girth strap (حزام البطن) & brass buckle
## - Brown leather headstall/bridle (لجام) with twin dynamic rope/leather reins (حبل اللجام)
## - Interactive mounting & riding (Seat_Mount, Exit_Left, Exit_Right, WASD steering, Shift trotting)
## - Compatible with optional Karo donkey cart (عربة الكارو) hitching via KaroHitchPoint / hitched_cart.

enum AnimState {
	WALK = 0,
	TROT_RUN = 1,
	GRAZE_EAT = 2,
	SIT_LIE_DOWN = 3,
	IDLE_LOOK = 4,
	VOCALIZE_WAG = 5
}

const STATE_NAMES: Array[String] = [
	"WALK",
	"TROT_RUN",
	"GRAZE_EAT",
	"SIT_LIE_DOWN",
	"IDLE_LOOK",
	"VOCALIZE_WAG"
]

@export var kind: String = "dog" # "dog", "cat", "goat", "donkey", "flock"
@export var coat_color: Color = Color(0.62, 0.44, 0.26, 1.0)
@export var wander_radius: float = 3.6
@export var move_speed: float = 1.15
@export var donkey_name: String = "الحمار السوداني"
@export var hitched_cart: Node3D = null

var current_state: AnimState = AnimState.WALK
var _state_timer: float = 3.5
var _origin: Vector3 = Vector3.ZERO
var _angle: float = 0.0
var _anim_t: float = 0.0
var _gait_phase: float = 0.0
var _sfx: AudioStreamPlayer3D = null

# Articulated hierarchy pivots
var _body_root: Node3D = null
var _neck_pivot: Node3D = null
var _head_pivot: Node3D = null
var _jaw_pivot: Node3D = null
var _ear_l: Node3D = null
var _ear_r: Node3D = null
var _tail_pivot: Node3D = null
var _tail_tip_pivot: Node3D = null
var _upper_legs: Array[Node3D] = [] # [FL, FR, RL, RR]
var _lower_legs: Array[Node3D] = [] # [Knee_FL, Knee_FR, Hock_RL, Hock_RR]
var _base_body_y: float = 0.42

# Donkey riding & saddle/bridle/reins anchors
var seat_mount: Marker3D = null
var exit_left: Marker3D = null
var exit_right: Marker3D = null
var karo_hitch_point: Marker3D = null
var _bit_ring_l: Marker3D = null
var _bit_ring_r: Marker3D = null
var _rein_anchor_idle_l: Marker3D = null
var _rein_anchor_idle_r: Marker3D = null
var _rein_anchor_rider_l: Marker3D = null
var _rein_anchor_rider_r: Marker3D = null
var _rein_mesh_l: MeshInstance3D = null
var _rein_mesh_r: MeshInstance3D = null

# Active rider control state (used when player mounts a donkey)
var rider_node: Node3D = null
var _rider_throttle: float = 0.0
var _rider_steer: float = 0.0
var _rider_trot: bool = false
var _current_speed_mps: float = 0.0
var _is_donkey_anatomy: bool = false

# Flock fallback if kind == "flock"
var _flock_delegate: BirdFlockAI = null


func _ready() -> void:
	add_to_group("animals")
	_origin = global_position
	_angle = randf() * TAU
	_anim_t = randf() * TAU
	_gait_phase = randf() * TAU

	if kind == "flock":
		add_to_group("bird_flocks")
		_flock_delegate = BirdFlockAI.new()
		_flock_delegate.bird_count = 5
		add_child(_flock_delegate)
		return

	if kind == "donkey":
		add_to_group("rideable_donkeys")
		_is_donkey_anatomy = true
		_build_detailed_donkey()
	else:
		_build_detailed_quadruped()
	_pick_next_state()


func _exit_tree() -> void:
	if _sfx != null:
		_sfx.stop()
		_sfx.stream = null


func get_state_name() -> String:
	return STATE_NAMES[int(current_state)]


func set_anim_state(new_state: AnimState, duration: float = 3.5) -> void:
	current_state = new_state
	_state_timer = duration
	if current_state == AnimState.VOCALIZE_WAG:
		_play_vocalization()


func scatter_from(origin: Vector3, radius: float) -> void:
	if is_mounted():
		return
	if _flock_delegate != null:
		_flock_delegate.scatter_from(origin, radius)
	elif global_position.distance_to(origin) <= radius:
		set_anim_state(AnimState.TROT_RUN, 3.2)


# ==============================================================================
# DONKEY RIDING API (MOUNT / DISMOUNT / INPUTS / KARO HITCH)
# ==============================================================================
func is_rideable() -> bool:
	return _is_donkey_anatomy and seat_mount != null


func is_mounted() -> bool:
	return rider_node != null and is_instance_valid(rider_node)


func mount_rider(rider: Node3D) -> bool:
	if not is_rideable() or is_mounted() or rider == null:
		return false
	rider_node = rider
	_rider_throttle = 0.0
	_rider_steer = 0.0
	_rider_trot = false
	_current_speed_mps = 0.0
	current_state = AnimState.IDLE_LOOK
	_play_vocalization()
	return true


func dismount_rider() -> Vector3:
	var exit_pos := get_safe_dismount_position()
	rider_node = null
	_rider_throttle = 0.0
	_rider_steer = 0.0
	_rider_trot = false
	_current_speed_mps = 0.0
	_origin = global_position
	set_anim_state(AnimState.IDLE_LOOK, 4.5)
	return exit_pos


func set_rider_inputs(throttle: float, steer: float, trotting: bool) -> void:
	_rider_throttle = clampf(throttle, -1.0, 1.0)
	_rider_steer = clampf(steer, -1.0, 1.0)
	_rider_trot = trotting


func get_seat_mount_global_position() -> Vector3:
	if seat_mount != null and is_instance_valid(seat_mount):
		return seat_mount.global_position
	return global_position + Vector3(0.0, 1.18, 0.0)


func get_safe_dismount_position() -> Vector3:
	var candidates: Array[Vector3] = []
	if exit_left != null and is_instance_valid(exit_left):
		candidates.append(exit_left.global_position)
	if exit_right != null and is_instance_valid(exit_right):
		candidates.append(exit_right.global_position)
	candidates.append(to_global(Vector3(-1.05, 0.05, 0.0)))
	candidates.append(to_global(Vector3(1.05, 0.05, 0.0)))
	candidates.append(to_global(Vector3(0.0, 0.05, 1.35)))

	var world := get_world_3d()
	if world != null:
		var space := world.direct_space_state
		var center_from := global_position + Vector3(0.0, 0.85, 0.0)
		for cand in candidates:
			var q := PhysicsRayQueryParameters3D.create(center_from, cand + Vector3(0.0, 0.85, 0.0), 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				return Vector3(cand.x, global_position.y + 0.05, cand.z)
	return Vector3(candidates[0].x, global_position.y + 0.05, candidates[0].z)


func get_current_speed_mps() -> float:
	return _current_speed_mps


func _process(delta: float) -> void:
	if _flock_delegate != null:
		return
	_anim_t += delta
	if is_mounted():
		_update_ridden_donkey(delta)
	else:
		_state_timer -= delta
		if _state_timer <= 0.0:
			_pick_next_state()
		_update_state_machine(delta)

	if _is_donkey_anatomy:
		_update_donkey_reins()
		_update_hitched_cart(delta)


func _pick_next_state() -> void:
	var roll := randf()
	if _is_donkey_anatomy:
		# Donkeys prefer calm walking, grazing, standing alert, and occasional trotting/braying (no odd cat-curl)
		if roll < 0.34:
			set_anim_state(AnimState.WALK, randf_range(4.0, 6.5))
		elif roll < 0.46:
			set_anim_state(AnimState.TROT_RUN, randf_range(2.2, 3.6))
		elif roll < 0.68:
			set_anim_state(AnimState.GRAZE_EAT, randf_range(3.5, 5.5))
		elif roll < 0.88:
			set_anim_state(AnimState.IDLE_LOOK, randf_range(3.0, 5.0))
		else:
			set_anim_state(AnimState.VOCALIZE_WAG, randf_range(2.0, 3.0))
		return

	if roll < 0.28:
		set_anim_state(AnimState.WALK, randf_range(3.5, 6.0))
	elif roll < 0.44:
		set_anim_state(AnimState.TROT_RUN, randf_range(2.2, 4.0))
	elif roll < 0.62:
		set_anim_state(AnimState.GRAZE_EAT, randf_range(3.0, 5.2))
	elif roll < 0.78:
		set_anim_state(AnimState.SIT_LIE_DOWN, randf_range(3.5, 6.5))
	elif roll < 0.90:
		set_anim_state(AnimState.IDLE_LOOK, randf_range(2.4, 4.2))
	else:
		set_anim_state(AnimState.VOCALIZE_WAG, randf_range(2.0, 3.2))


func _play_vocalization() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if _sfx == null or _sfx.stream == null or _sfx.playing:
		return
	_sfx.pitch_scale = randf_range(0.72, 0.85) if kind == "donkey" else randf_range(0.92, 1.08)
	_sfx.play()


# ==============================================================================
# OVERHAULED 1:1 SCULPTED SUDANESE DONKEY + BARDAA SADDLE + LEATHER BRIDLE
# ==============================================================================
func _build_detailed_donkey() -> void:
	scale = Vector3.ONE
	# True Sudanese donkey proportions: withers ~1.14m, barrel radius 0.27m, length 1.22m
	# Ground contact: _base_body_y (0.88) - hip_y (0.08) - upper (0.38) - lower (0.38) - half_hoof (0.04) = 0.00m
	_base_body_y = 0.88

	# Natural fur & tack PBR materials (metallic = 0.0, roughness = 0.9 on fur)
	var coat_mat := StandardMaterial3D.new()
	coat_mat.albedo_color = coat_color
	coat_mat.metallic = 0.0
	coat_mat.roughness = 0.90
	if ResourceLoader.exists("res://assets/textures/fabric/normal.jpg"):
		coat_mat.normal_enabled = true
		coat_mat.normal_scale = 0.35
		coat_mat.normal_texture = ResourceLoader.load("res://assets/textures/fabric/normal.jpg") as Texture2D
		coat_mat.uv1_scale = Vector3(3.0, 3.0, 1.0)

	var belly_mat := StandardMaterial3D.new()
	belly_mat.albedo_color = coat_color.lightened(0.32) # Pale cream muzzle, belly & eye-rings
	belly_mat.metallic = 0.0
	belly_mat.roughness = 0.90

	var dark_fur_mat := StandardMaterial3D.new()
	dark_fur_mat.albedo_color = Color(0.18, 0.16, 0.14, 1.0) # Mane, dorsal stripe, ear tips, tail tuft
	dark_fur_mat.metallic = 0.0
	dark_fur_mat.roughness = 0.90

	var hoof_mat := StandardMaterial3D.new()
	hoof_mat.albedo_color = Color(0.13, 0.11, 0.10, 1.0)
	hoof_mat.metallic = 0.0
	hoof_mat.roughness = 0.58

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.04, 0.04, 1.0)
	eye_mat.metallic = 0.05
	eye_mat.roughness = 0.18

	var leather_mat := StandardMaterial3D.new()
	leather_mat.albedo_color = Color(0.28, 0.15, 0.08, 1.0) # Brown bridle & belly girth leather
	leather_mat.metallic = 0.0
	leather_mat.roughness = 0.62

	var leather_seat_mat := StandardMaterial3D.new()
	leather_seat_mat.albedo_color = Color(0.42, 0.22, 0.11, 1.0) # Warm padded Bardaa cushion seat
	leather_seat_mat.metallic = 0.0
	leather_seat_mat.roughness = 0.78

	var blanket_mat := StandardMaterial3D.new()
	blanket_mat.albedo_color = Color(0.66, 0.16, 0.14, 1.0) # Sudanese crimson quilted saddle blanket
	blanket_mat.metallic = 0.0
	blanket_mat.roughness = 0.92

	var trim_gold_mat := StandardMaterial3D.new()
	trim_gold_mat.albedo_color = Color(0.86, 0.68, 0.24, 1.0) # Woven gold blanket border & tassels
	trim_gold_mat.metallic = 0.0
	trim_gold_mat.roughness = 0.86

	var brass_mat := StandardMaterial3D.new()
	brass_mat.albedo_color = Color(0.84, 0.68, 0.26, 1.0)
	brass_mat.metallic = 0.78
	brass_mat.roughness = 0.30

	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.56, 0.42, 0.24, 1.0) # Braided leather/rope reins
	rope_mat.metallic = 0.0
	rope_mat.roughness = 0.84

	# ------------------------------------------------------------------
	# 1. SCULPTED BODY ROOT (Torso + Chest + Haunches + Belly + Dorsal Cross)
	# ------------------------------------------------------------------
	_body_root = Node3D.new()
	_body_root.name = "BodyRoot"
	_body_root.position = Vector3(0.0, _base_body_y, 0.0)
	add_child(_body_root)

	var body_batch := InteriorMeshBatcher.new()
	# Main smooth barrel torso along Z
	body_batch.add_cylinder(Vector3(0.0, 0.0, 0.0), 0.265, 0.265, 0.86, coat_mat, 14, PI * 0.5, 0.0)
	# Blended muscular chest breast (-Z front)
	body_batch.add_sphere(Vector3(0.0, -0.01, -0.43), 0.265, coat_mat, Vector3(0.96, 1.02, 1.05), 14, 8)
	# Blended rounded hindquarters / croup (+Z rear)
	body_batch.add_sphere(Vector3(0.0, 0.02, 0.43), 0.275, coat_mat, Vector3(0.98, 1.02, 1.08), 14, 8)
	# Withers slight ridge where neck meets spine
	body_batch.add_sphere(Vector3(0.0, 0.14, -0.36), 0.18, coat_mat, Vector3(0.85, 0.85, 1.25), 10, 6)
	# Lighter cream underbelly smoothly blended along underside
	body_batch.add_sphere(Vector3(0.0, -0.10, 0.02), 0.235, belly_mat, Vector3(0.92, 0.78, 1.95), 12, 6)
	# Authentic Sudanese donkey dark dorsal stripe & shoulder cross (صليب الظهر)
	body_batch.add_box(Vector3(0.0, 0.265, 0.02), Vector3(0.045, 0.025, 0.92), dark_fur_mat)
	body_batch.add_box(Vector3(0.0, 0.16, -0.34), Vector3(0.46, 0.04, 0.055), dark_fur_mat)

	var body_mi := MeshInstance3D.new()
	body_mi.name = "DonkeyTorsoMesh"
	body_mi.mesh = body_batch.commit()
	_body_root.add_child(body_mi)

	# ------------------------------------------------------------------
	# 2. CONTOURED SUDANESE PADDED SADDLE (البردعة) + GIRTH STRAP (حزام البطن)
	# ------------------------------------------------------------------
	var sad_batch := InteriorMeshBatcher.new()
	# Contoured quilted cloth blanket curving cleanly over spine & draping down BOTH flanks
	var blanket_len := 0.62
	var blanket_z := 0.02
	# Top curved spine arch
	sad_batch.add_box(Vector3(0.0, 0.282, blanket_z), Vector3(0.28, 0.045, blanket_len), blanket_mat)
	# Left & Right upper sloped blanket shoulders (hugging the curved ribs)
	for side: float in [-1.0, 1.0]:
		sad_batch.add_box(Vector3(side * 0.215, 0.205, blanket_z), Vector3(0.18, 0.042, blanket_len), blanket_mat, 0.0, 0.0, -side * deg_to_rad(46.0))
		# Lower side blanket flaps draping down cleanly along flanks
		sad_batch.add_box(Vector3(side * 0.285, 0.03, blanket_z), Vector3(0.042, 0.26, blanket_len), blanket_mat, 0.0, 0.0, -side * deg_to_rad(8.0))
		# Woven gold trim border along bottom & front/rear edges of blanket flaps
		sad_batch.add_box(Vector3(side * 0.298, -0.088, blanket_z), Vector3(0.028, 0.045, blanket_len + 0.02), trim_gold_mat)
		for tz: float in [-blanket_len * 0.48, blanket_len * 0.48]:
			sad_batch.add_sphere(Vector3(side * 0.30, -0.125, blanket_z + tz), 0.026, trim_gold_mat, Vector3(0.8, 1.4, 0.8), 6, 4)

	# Raised sculpted padded leather/woven cushion seat (مقعد البردعة)
	sad_batch.add_box(Vector3(0.0, 0.325, blanket_z), Vector3(0.36, 0.075, 0.50), leather_seat_mat)
	# Front pommel bolster (قربوس أمامي) & rear cantle bolster (قربوس خلفي)
	sad_batch.add_cylinder(Vector3(0.0, 0.365, blanket_z - 0.22), 0.068, 0.068, 0.38, leather_seat_mat, 8, 0.0, PI * 0.5)
	sad_batch.add_cylinder(Vector3(0.0, 0.375, blanket_z + 0.23), 0.074, 0.074, 0.40, leather_seat_mat, 8, 0.0, PI * 0.5)
	# Decorative quilted stitching ribs across seat cushion
	for qz in [-0.12, 0.0, 0.12]:
		sad_batch.add_box(Vector3(0.0, 0.364, blanket_z + qz), Vector3(0.35, 0.015, 0.022), trim_gold_mat)

	# Dark leather belly girth strap (حزام البطن) wrapping tightly underneath torso + brass buckle
	var girth_z := -0.06
	for side: float in [-1.0, 1.0]:
		sad_batch.add_box(Vector3(side * 0.285, -0.02, girth_z), Vector3(0.032, 0.46, 0.075), leather_mat)
		sad_batch.add_box(Vector3(side * 0.19, -0.235, girth_z), Vector3(0.18, 0.032, 0.075), leather_mat, 0.0, 0.0, side * deg_to_rad(32.0))
	sad_batch.add_box(Vector3(0.0, -0.285, girth_z), Vector3(0.26, 0.032, 0.078), leather_mat)
	# Brass cinch buckle on left flank + Karo shaft hitch rings on both sides
	sad_batch.add_box(Vector3(-0.305, -0.04, girth_z), Vector3(0.022, 0.085, 0.095), brass_mat)
	for side: float in [-1.0, 1.0]:
		sad_batch.add_cylinder(Vector3(side * 0.305, 0.12, 0.18), 0.038, 0.038, 0.022, brass_mat, 8, 0.0, PI * 0.5)

	var sad_mi := MeshInstance3D.new()
	sad_mi.name = "SaddleAssembly"
	sad_mi.mesh = sad_batch.commit()
	_body_root.add_child(sad_mi)

	# Mount / Seat / Exit / Karo Hitch Markers
	seat_mount = Marker3D.new()
	seat_mount.name = "Seat_Mount"
	# Lowered by 0.18m and shifted 0.05m forward into the center of the brown padded Bardaa cushion
	# so the rider's hips sit flush on the cushion with zero floating gap
	seat_mount.position = Vector3(0.0, 0.08, -0.01)
	_body_root.add_child(seat_mount)

	_rein_anchor_idle_l = Marker3D.new()
	_rein_anchor_idle_l.position = Vector3(-0.11, 0.37, -0.20)
	_body_root.add_child(_rein_anchor_idle_l)

	_rein_anchor_idle_r = Marker3D.new()
	_rein_anchor_idle_r.position = Vector3(0.11, 0.37, -0.20)
	_body_root.add_child(_rein_anchor_idle_r)

	_rein_anchor_rider_l = Marker3D.new()
	_rein_anchor_rider_l.position = Vector3(-0.18, 0.72, -0.24)
	_body_root.add_child(_rein_anchor_rider_l)

	_rein_anchor_rider_r = Marker3D.new()
	_rein_anchor_rider_r.position = Vector3(0.18, 0.72, -0.24)
	_body_root.add_child(_rein_anchor_rider_r)

	karo_hitch_point = Marker3D.new()
	karo_hitch_point.name = "KaroHitchPoint"
	karo_hitch_point.position = Vector3(0.0, 0.06, 0.66)
	_body_root.add_child(karo_hitch_point)

	exit_left = Marker3D.new()
	exit_left.name = "Exit_Left"
	exit_left.position = Vector3(-1.05, 0.05, 0.0)
	add_child(exit_left)

	exit_right = Marker3D.new()
	exit_right.name = "Exit_Right"
	exit_right.position = Vector3(1.05, 0.05, 0.0)
	add_child(exit_right)

	# ------------------------------------------------------------------
	# 3. SLOPED ARTICULATED NECK + UPRIGHT BRISTLY MANE
	# ------------------------------------------------------------------
	_neck_pivot = Node3D.new()
	_neck_pivot.name = "NeckPivot"
	_neck_pivot.position = Vector3(0.0, 0.12, -0.46)
	_body_root.add_child(_neck_pivot)

	var neck_batch := InteriorMeshBatcher.new()
	# Muscular tapered sloped neck rising forward & up
	neck_batch.add_cylinder(Vector3(0.0, 0.20, -0.14), 0.125, 0.185, 0.52, coat_mat, 12, deg_to_rad(36.0), 0.0)
	# Smooth throat blend sphere at base of neck
	neck_batch.add_sphere(Vector3(0.0, 0.02, -0.02), 0.18, coat_mat, Vector3(0.95, 1.0, 1.0), 10, 6)
	# Upright short dark bristly donkey mane along dorsal crest of neck
	for mi_idx in range(6):
		var t := float(mi_idx) / 5.0
		var mp := Vector3(0.0, lerpf(0.08, 0.40, t), lerpf(0.05, -0.20, t))
		neck_batch.add_box(mp, Vector3(0.042, 0.095, 0.08), dark_fur_mat, 0.0, deg_to_rad(34.0), 0.0)

	var neck_mi := MeshInstance3D.new()
	neck_mi.name = "DonkeyNeckMesh"
	neck_mi.mesh = neck_batch.commit()
	_neck_pivot.add_child(neck_mi)

	# ------------------------------------------------------------------
	# 4. SCULPTED HEAD, PALE MUZZLE, NOSTRILS, EYES, EARS & LEATHER BRIDLE (اللجام)
	# ------------------------------------------------------------------
	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadPivot"
	_head_pivot.position = Vector3(0.0, 0.39, -0.28)
	_neck_pivot.add_child(_head_pivot)

	var head_batch := InteriorMeshBatcher.new()
	# Sculpted cranium & cheeks
	head_batch.add_sphere(Vector3(0.0, 0.02, 0.0), 0.145, coat_mat, Vector3(0.84, 0.92, 1.15), 12, 8)
	# Tapered bridge of nose angling forward & slightly downward (-28 deg)
	head_batch.add_cylinder(Vector3(0.0, -0.06, -0.17), 0.078, 0.115, 0.28, coat_mat, 10, deg_to_rad(118.0), 0.0)
	# Characteristic pale-cream soft donkey muzzle
	head_batch.add_sphere(Vector3(0.0, -0.14, -0.31), 0.088, belly_mat, Vector3(0.94, 0.92, 1.18), 10, 6)
	# Twin sculpted dark nostrils (Nostril_L / Nostril_R)
	for sx: float in [-1.0, 1.0]:
		head_batch.add_sphere(Vector3(sx * 0.044, -0.125, -0.39), 0.022, dark_fur_mat, Vector3(0.8, 1.1, 0.7), 6, 4)
	# Expressive dark eyes with pale eye-rings on both sides of head
	for sx: float in [-1.0, 1.0]:
		head_batch.add_sphere(Vector3(sx * 0.105, 0.055, -0.085), 0.036, belly_mat, Vector3(0.55, 1.0, 1.05), 8, 5)
		head_batch.add_sphere(Vector3(sx * 0.115, 0.055, -0.090), 0.025, eye_mat, Vector3(0.65, 1.0, 1.0), 8, 5)

	# --- Brown Leather Headstall / Bridle (اللجام) ---
	# Crownpiece behind ears & browband across forehead
	head_batch.add_box(Vector3(0.0, 0.135, 0.03), Vector3(0.22, 0.022, 0.028), leather_mat)
	head_batch.add_box(Vector3(0.0, 0.095, -0.105), Vector3(0.22, 0.022, 0.026), leather_mat)
	# Noseband wrapping cleanly around muzzle
	head_batch.add_box(Vector3(0.0, -0.065, -0.275), Vector3(0.185, 0.024, 0.028), leather_mat, 0.0, deg_to_rad(28.0), 0.0)
	head_batch.add_box(Vector3(0.0, -0.195, -0.225), Vector3(0.175, 0.022, 0.026), leather_mat, 0.0, deg_to_rad(28.0), 0.0)
	# Left & Right cheekpieces, noseband sides & brass bit rings
	for sx: float in [-1.0, 1.0]:
		head_batch.add_bar(Vector3(sx * 0.105, 0.13, 0.03), Vector3(sx * 0.092, -0.14, -0.26), 0.022, 0.022, leather_mat)
		head_batch.add_bar(Vector3(sx * 0.092, -0.065, -0.275), Vector3(sx * 0.088, -0.195, -0.225), 0.022, 0.022, leather_mat)
		# Brass bit ring at corner of mouth
		head_batch.add_cylinder(Vector3(sx * 0.098, -0.155, -0.27), 0.030, 0.030, 0.014, brass_mat, 8, 0.0, PI * 0.5)

	var head_mi := MeshInstance3D.new()
	head_mi.name = "DonkeyHeadAndBridleMesh"
	head_mi.mesh = head_batch.commit()
	_head_pivot.add_child(head_mi)

	# Bit ring markers for dynamic twin reins
	_bit_ring_l = Marker3D.new()
	_bit_ring_l.name = "BitRing_L"
	_bit_ring_l.position = Vector3(-0.10, -0.155, -0.27)
	_head_pivot.add_child(_bit_ring_l)

	_bit_ring_r = Marker3D.new()
	_bit_ring_r.name = "BitRing_R"
	_bit_ring_r.position = Vector3(0.10, -0.155, -0.27)
	_head_pivot.add_child(_bit_ring_r)

	# Articulated Lower Jaw
	_jaw_pivot = Node3D.new()
	_jaw_pivot.name = "JawPivot"
	_jaw_pivot.position = Vector3(0.0, -0.08, -0.08)
	_head_pivot.add_child(_jaw_pivot)
	var jaw_mi := MeshInstance3D.new()
	var jaw_b := InteriorMeshBatcher.new()
	jaw_b.add_box(Vector3(0.0, -0.04, -0.12), Vector3(0.105, 0.048, 0.22), belly_mat, 0.0, deg_to_rad(20.0), 0.0)
	jaw_mi.mesh = jaw_b.commit()
	_jaw_pivot.add_child(jaw_mi)

	# Iconic Long Articulated Donkey Ears (Ear_L, Ear_R) with pale inner hollow & dark tips
	for side_idx in range(2):
		var sx: float = -1.0 if side_idx == 0 else 1.0
		var ep := Node3D.new()
		ep.name = "Ear_L" if side_idx == 0 else "Ear_R"
		ep.position = Vector3(sx * 0.085, 0.12, 0.015)
		_head_pivot.add_child(ep)

		var eb := InteriorMeshBatcher.new()
		# Outer ear blade
		eb.add_cylinder(Vector3(sx * 0.03, 0.16, 0.0), 0.016, 0.048, 0.32, coat_mat, 8, 0.0, -sx * deg_to_rad(18.0))
		# Pale inner ear facing forward
		eb.add_cylinder(Vector3(sx * 0.03, 0.15, -0.022), 0.010, 0.032, 0.24, belly_mat, 6, 0.0, -sx * deg_to_rad(18.0))
		# Dark donkey ear tip
		eb.add_cylinder(Vector3(sx * 0.075, 0.30, 0.0), 0.008, 0.020, 0.07, dark_fur_mat, 6, 0.0, -sx * deg_to_rad(18.0))

		var ear_mi := MeshInstance3D.new()
		ear_mi.mesh = eb.commit()
		ep.add_child(ear_mi)
		if side_idx == 0:
			_ear_l = ep
		else:
			_ear_r = ep

	# ------------------------------------------------------------------
	# 5. FIRMLY ATTACHED PENDULUM TAIL (TailPivot anchored inside rear hip socket!)
	# Croup rear sphere reaches z = +0.69 -> TailPivot at (0, 0.09, 0.56) is deeply rooted!
	# ------------------------------------------------------------------
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0.0, 0.09, 0.56)
	_body_root.add_child(_tail_pivot)

	var tail_up_b := InteriorMeshBatcher.new()
	# Root socket bulb + upper hanging dock (0.0 down to -0.24m, slightly back +0.06m)
	tail_up_b.add_sphere(Vector3(0.0, 0.0, 0.0), 0.052, coat_mat, Vector3.ONE, 8, 5)
	tail_up_b.add_bar(Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.24, 0.075), 0.044, 0.044, coat_mat)
	var tail_up_mi := MeshInstance3D.new()
	tail_up_mi.name = "TailUpper"
	tail_up_mi.mesh = tail_up_b.commit()
	_tail_pivot.add_child(tail_up_mi)

	# Connected lower tail shaft + bushy dark tassel directly at the end of TailUpper!
	_tail_tip_pivot = Node3D.new()
	_tail_tip_pivot.name = "TailTipPivot"
	_tail_tip_pivot.position = Vector3(0.0, -0.24, 0.075)
	_tail_pivot.add_child(_tail_tip_pivot)

	var tail_low_b := InteriorMeshBatcher.new()
	tail_low_b.add_bar(Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.22, 0.025), 0.032, 0.032, coat_mat)
	# Bushy dark donkey hair tassel at tip
	tail_low_b.add_sphere(Vector3(0.0, -0.25, 0.025), 0.048, dark_fur_mat, Vector3(0.85, 1.85, 0.85), 8, 5)
	var tail_low_mi := MeshInstance3D.new()
	tail_low_mi.name = "TailLower"
	tail_low_mi.mesh = tail_low_b.commit()
	_tail_tip_pivot.add_child(tail_low_mi)

	# ------------------------------------------------------------------
	# 6. ARTICULATED 4-LEG PIVOTS (Leg_FL, Leg_FR, Leg_RL, Leg_RR) + KNEE/HOCK JOINTS
	# ------------------------------------------------------------------
	var leg_specs: Array[Dictionary] = [
		{"name": "Leg_FL", "joint": "Knee_FL", "pos": Vector3(-0.175, -0.08, -0.39), "front": true},
		{"name": "Leg_FR", "joint": "Knee_FR", "pos": Vector3(0.175, -0.08, -0.39), "front": true},
		{"name": "Leg_RL", "joint": "Hock_RL", "pos": Vector3(-0.175, -0.08, 0.40), "front": false},
		{"name": "Leg_RR", "joint": "Hock_RR", "pos": Vector3(0.175, -0.08, 0.40), "front": false},
	]
	var upper_len := 0.38
	var lower_len := 0.38

	for spec in leg_specs:
		var up_pivot := Node3D.new()
		up_pivot.name = String(spec["name"])
		up_pivot.position = spec["pos"] as Vector3
		_body_root.add_child(up_pivot)

		var up_b := InteriorMeshBatcher.new()
		# Rounded shoulder/hip socket sphere embedded cleanly into torso
		up_b.add_sphere(Vector3(0.0, 0.02, 0.0), 0.095 if spec["front"] else 0.115, coat_mat, Vector3(0.85, 1.15, 1.05), 8, 5)
		# Tapered muscular upper leg
		up_b.add_cylinder(Vector3(0.0, -upper_len * 0.5, 0.0), 0.082 if spec["front"] else 0.094, 0.056, upper_len + 0.04, coat_mat, 8)
		var up_mi := MeshInstance3D.new()
		up_mi.name = "UpperLegMesh"
		up_mi.mesh = up_b.commit()
		up_pivot.add_child(up_mi)

		var low_pivot := Node3D.new()
		low_pivot.name = String(spec["joint"])
		low_pivot.position = Vector3(0.0, -upper_len, 0.0)
		up_pivot.add_child(low_pivot)

		var low_b := InteriorMeshBatcher.new()
		# Articulated knee / hock joint sphere
		low_b.add_sphere(Vector3(0.0, 0.0, 0.0), 0.056, coat_mat, Vector3.ONE, 8, 5)
		# Slender cannon bone + pastern
		low_b.add_cylinder(Vector3(0.0, -lower_len * 0.48, 0.0), 0.046, 0.038, lower_len, belly_mat, 8)
		# Dark donkey hoof resting flush at y = 0.00m
		low_b.add_cylinder(Vector3(0.0, -lower_len, -0.012), 0.044, 0.054, 0.075, hoof_mat, 8)
		var low_mi := MeshInstance3D.new()
		low_mi.name = "LowerLegAndHoofMesh"
		low_mi.mesh = low_b.commit()
		low_pivot.add_child(low_mi)

		_upper_legs.append(up_pivot)
		_lower_legs.append(low_pivot)

	# ------------------------------------------------------------------
	# 7. DYNAMIC TWIN ROPE/LEATHER REINS (حبل اللجام)
	# ------------------------------------------------------------------
	for side_idx in range(2):
		var rmi := MeshInstance3D.new()
		rmi.name = "Rein_L" if side_idx == 0 else "Rein_R"
		var rcm := CylinderMesh.new()
		rcm.top_radius = 0.010
		rcm.bottom_radius = 0.010
		rcm.height = 1.0
		rcm.radial_segments = 6
		rmi.mesh = rcm
		rmi.material_override = rope_mat
		add_child(rmi)
		if side_idx == 0:
			_rein_mesh_l = rmi
		else:
			_rein_mesh_r = rmi

	_optimize_animal_meshes(self)
	_setup_vocalization_audio()


# ==============================================================================
# OTHER ANIMALS (DOGS, CATS, GOATS) — WITH FIXED ATTACHED TAILS
# ==============================================================================
func _build_detailed_quadruped() -> void:
	var scale_f := 1.0
	var body_len := 0.66
	var body_rad := 0.16
	var leg_upper_len := 0.20
	var leg_lower_len := 0.20
	var neck_len := 0.22
	var snout_len := 0.16
	var ear_len := 0.12

	if kind == "cat":
		scale_f = 0.62
		body_len = 0.56
		body_rad = 0.13
		leg_upper_len = 0.15
		leg_lower_len = 0.15
		neck_len = 0.14
		snout_len = 0.09
		ear_len = 0.08
	elif kind == "goat":
		scale_f = 1.06
		body_len = 0.68
		body_rad = 0.17
		leg_upper_len = 0.21
		leg_lower_len = 0.21
		neck_len = 0.25
		snout_len = 0.15
		ear_len = 0.14

	_base_body_y = leg_upper_len + leg_lower_len + body_rad * 0.45

	var coat_mat := StandardMaterial3D.new()
	coat_mat.albedo_color = coat_color
	coat_mat.roughness = 0.90
	coat_mat.metallic = 0.0
	if ResourceLoader.exists("res://assets/textures/fabric/albedo.jpg"):
		coat_mat.albedo_texture = ResourceLoader.load("res://assets/textures/fabric/albedo.jpg") as Texture2D
		coat_mat.uv1_scale = Vector3(3.0, 3.0, 1.0)
	if ResourceLoader.exists("res://assets/textures/fabric/normal.jpg"):
		coat_mat.normal_enabled = true
		coat_mat.normal_scale = 0.45
		coat_mat.normal_texture = ResourceLoader.load("res://assets/textures/fabric/normal.jpg") as Texture2D

	var belly_mat := StandardMaterial3D.new()
	belly_mat.albedo_color = coat_color.lightened(0.22)
	belly_mat.roughness = 0.90
	belly_mat.metallic = 0.0

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.14, 0.12, 0.11, 1.0)
	dark_mat.roughness = 0.55

	_body_root = Node3D.new()
	_body_root.name = "BodyRoot"
	_body_root.position = Vector3(0.0, _base_body_y, 0.0)
	add_child(_body_root)

	var chest := MeshInstance3D.new()
	chest.name = "ChestTorso"
	var cm_chest := CapsuleMesh.new()
	cm_chest.radius = body_rad
	cm_chest.height = body_len
	cm_chest.radial_segments = 12
	cm_chest.rings = 4
	chest.mesh = cm_chest
	chest.material_override = coat_mat
	chest.rotation.x = PI * 0.5
	_body_root.add_child(chest)

	var belly := MeshInstance3D.new()
	belly.name = "BellyUnder"
	var sm_belly := SphereMesh.new()
	sm_belly.radius = body_rad * 0.92
	sm_belly.height = body_len * 0.72
	sm_belly.radial_segments = 10
	sm_belly.rings = 6
	belly.mesh = sm_belly
	belly.material_override = belly_mat
	belly.rotation.x = PI * 0.5
	belly.position = Vector3(0.0, -body_rad * 0.22, 0.02)
	_body_root.add_child(belly)

	_neck_pivot = Node3D.new()
	_neck_pivot.name = "NeckPivot"
	_neck_pivot.position = Vector3(0.0, body_rad * 0.35, -body_len * 0.38)
	_body_root.add_child(_neck_pivot)

	var neck := MeshInstance3D.new()
	neck.name = "NeckMesh"
	var cm_neck := CapsuleMesh.new()
	cm_neck.radius = body_rad * 0.54
	cm_neck.height = neck_len + body_rad * 0.6
	cm_neck.radial_segments = 10
	cm_neck.rings = 4
	neck.mesh = cm_neck
	neck.material_override = coat_mat
	neck.rotation.x = deg_to_rad(32.0)
	neck.position = Vector3(0.0, neck_len * 0.42, -neck_len * 0.25)
	_neck_pivot.add_child(neck)

	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadPivot"
	_head_pivot.position = Vector3(0.0, neck_len * 0.82, -neck_len * 0.48)
	_neck_pivot.add_child(_head_pivot)

	var cranium := MeshInstance3D.new()
	var sm_head := SphereMesh.new()
	sm_head.radius = body_rad * 0.62
	sm_head.height = body_rad * 1.25
	cranium.mesh = sm_head
	cranium.material_override = coat_mat
	_head_pivot.add_child(cranium)

	var snout := MeshInstance3D.new()
	var cm_snout := CapsuleMesh.new()
	cm_snout.radius = body_rad * 0.36
	cm_snout.height = snout_len + body_rad * 0.4
	snout.mesh = cm_snout
	snout.material_override = coat_mat
	snout.rotation.x = PI * 0.5
	snout.position = Vector3(0.0, -body_rad * 0.10, -snout_len * 0.65)
	_head_pivot.add_child(snout)

	var nose := MeshInstance3D.new()
	var sm_nose := SphereMesh.new()
	sm_nose.radius = body_rad * 0.16
	sm_nose.height = body_rad * 0.28
	nose.mesh = sm_nose
	nose.material_override = dark_mat
	nose.position = Vector3(0.0, -body_rad * 0.04, -snout_len * 1.12)
	_head_pivot.add_child(nose)

	_jaw_pivot = Node3D.new()
	_jaw_pivot.position = Vector3(0.0, -body_rad * 0.24, -body_rad * 0.20)
	_head_pivot.add_child(_jaw_pivot)
	var jaw := MeshInstance3D.new()
	var bm_jaw := BoxMesh.new()
	bm_jaw.size = Vector3(body_rad * 0.45, body_rad * 0.16, snout_len * 0.85)
	jaw.mesh = bm_jaw
	jaw.material_override = belly_mat
	jaw.position = Vector3(0.0, 0.0, -snout_len * 0.42)
	_jaw_pivot.add_child(jaw)

	for ex: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var sm_eye := SphereMesh.new()
		sm_eye.radius = body_rad * 0.11
		sm_eye.height = body_rad * 0.22
		eye.mesh = sm_eye
		eye.material_override = dark_mat
		eye.position = Vector3(ex * body_rad * 0.46, body_rad * 0.14, -body_rad * 0.42)
		_head_pivot.add_child(eye)

	for side_idx in range(2):
		var sx: float = -1.0 if side_idx == 0 else 1.0
		var ep := Node3D.new()
		ep.name = "Ear_L" if side_idx == 0 else "Ear_R"
		ep.position = Vector3(sx * body_rad * 0.46, body_rad * 0.44, 0.02)
		_head_pivot.add_child(ep)
		var ear_mi := MeshInstance3D.new()
		var cm_ear := CylinderMesh.new()
		cm_ear.top_radius = 0.012
		cm_ear.bottom_radius = body_rad * 0.20
		cm_ear.height = ear_len
		ear_mi.mesh = cm_ear
		ear_mi.material_override = coat_mat
		if kind == "goat":
			ear_mi.position = Vector3(sx * 0.04, -ear_len * 0.45, 0.0)
			ear_mi.rotation.z = sx * deg_to_rad(135.0)
		else:
			ear_mi.position = Vector3(sx * 0.02, ear_len * 0.45, 0.0)
			ear_mi.rotation.z = -sx * deg_to_rad(18.0)
		ep.add_child(ear_mi)
		if side_idx == 0:
			_ear_l = ep
		else:
			_ear_r = ep

	if kind == "goat":
		for hx: float in [-0.055, 0.055]:
			var horn := MeshInstance3D.new()
			var hcm := CylinderMesh.new()
			hcm.top_radius = 0.008
			hcm.bottom_radius = 0.024
			hcm.height = 0.16
			horn.mesh = hcm
			horn.material_override = dark_mat
			horn.rotation.x = deg_to_rad(-28.0)
			horn.position = Vector3(hx, body_rad * 0.72, 0.04)
			_head_pivot.add_child(horn)

	# Firmly rooted TailPivot embedded inside rear hip socket (zero floating gap!)
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0.0, body_rad * 0.22, body_len * 0.38)
	_body_root.add_child(_tail_pivot)

	var tail_base := MeshInstance3D.new()
	var cm_tb := CapsuleMesh.new()
	cm_tb.radius = 0.024
	cm_tb.height = 0.16
	tail_base.mesh = cm_tb
	tail_base.material_override = coat_mat
	tail_base.rotation.x = deg_to_rad(52.0)
	tail_base.position = Vector3(0.0, 0.03, 0.06)
	_tail_pivot.add_child(tail_base)

	_tail_tip_pivot = Node3D.new()
	_tail_tip_pivot.name = "TailTipPivot"
	_tail_tip_pivot.position = Vector3(0.0, 0.06, 0.12)
	_tail_pivot.add_child(_tail_tip_pivot)

	var tail_tip := MeshInstance3D.new()
	var cm_tt := CapsuleMesh.new()
	cm_tt.radius = 0.020
	cm_tt.height = 0.14
	tail_tip.mesh = cm_tt
	tail_tip.material_override = coat_mat
	tail_tip.rotation.x = deg_to_rad(32.0)
	tail_tip.position = Vector3(0.0, 0.04, 0.04)
	_tail_tip_pivot.add_child(tail_tip)

	var leg_coords: Array[Vector3] = [
		Vector3(-body_rad * 0.68, -body_rad * 0.35, -body_len * 0.30),
		Vector3(body_rad * 0.68, -body_rad * 0.35, -body_len * 0.30),
		Vector3(-body_rad * 0.68, -body_rad * 0.35, body_len * 0.30),
		Vector3(body_rad * 0.68, -body_rad * 0.35, body_len * 0.30),
	]
	var leg_names := ["Leg_FL", "Leg_FR", "Leg_RL", "Leg_RR"]
	for li in range(4):
		var up_pivot := Node3D.new()
		up_pivot.name = leg_names[li]
		up_pivot.position = leg_coords[li]
		_body_root.add_child(up_pivot)

		var up_mesh := MeshInstance3D.new()
		var cm_up := CapsuleMesh.new()
		cm_up.radius = body_rad * 0.28
		cm_up.height = leg_upper_len + body_rad * 0.25
		up_mesh.mesh = cm_up
		up_mesh.material_override = coat_mat
		up_mesh.position = Vector3(0.0, -leg_upper_len * 0.5, 0.0)
		up_pivot.add_child(up_mesh)

		var low_pivot := Node3D.new()
		low_pivot.position = Vector3(0.0, -leg_upper_len, 0.0)
		up_pivot.add_child(low_pivot)

		var low_mesh := MeshInstance3D.new()
		var cm_low := CapsuleMesh.new()
		cm_low.radius = body_rad * 0.21
		cm_low.height = leg_lower_len + body_rad * 0.18
		low_mesh.mesh = cm_low
		low_mesh.material_override = belly_mat
		low_mesh.position = Vector3(0.0, -leg_lower_len * 0.5, 0.0)
		low_pivot.add_child(low_mesh)

		var paw := MeshInstance3D.new()
		var cm_paw := CylinderMesh.new()
		cm_paw.top_radius = body_rad * 0.20
		cm_paw.bottom_radius = body_rad * 0.24
		cm_paw.height = 0.055
		paw.mesh = cm_paw
		paw.material_override = dark_mat if kind == "goat" else belly_mat
		paw.position = Vector3(0.0, -leg_lower_len, -0.015)
		low_pivot.add_child(paw)

		_upper_legs.append(up_pivot)
		_lower_legs.append(low_pivot)

	scale = Vector3.ONE * scale_f
	_optimize_animal_meshes(_body_root)
	_setup_vocalization_audio()


func _setup_vocalization_audio() -> void:
	var audio_mgr := get_node_or_null("/root/AudioManager")
	_sfx = AudioStreamPlayer3D.new()
	_sfx.name = "AnimalVoice3D"
	_sfx.max_distance = 34.0
	_sfx.unit_size = 3.5
	_sfx.volume_db = -5.0
	if audio_mgr:
		if kind == "dog":
			_sfx.stream = audio_mgr.dog_bark_stream
		elif kind == "cat":
			_sfx.stream = audio_mgr.cat_meow_stream
		else:
			_sfx.stream = audio_mgr.goat_bleat_stream
	add_child(_sfx)


func _optimize_animal_meshes(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.visibility_range_end = 100.0 if _is_donkey_anatomy else 90.0
	for ch in node.get_children():
		_optimize_animal_meshes(ch)


# ==============================================================================
# RIDDEN DONKEY MOVEMENT, GROUND SNAPPING & SPEED-SCALED 4-LEG GAIT
# ==============================================================================
func _update_ridden_donkey(delta: float) -> void:
	var max_fwd := 7.6 if _rider_trot else 4.2
	var target_spd := _rider_throttle * (max_fwd if _rider_throttle >= 0.0 else 1.8)
	_current_speed_mps = lerpf(_current_speed_mps, target_spd, clampf(delta * 6.5, 0.0, 1.0))

	# Smooth steering (allows pivoting smoothly even at low speed)
	if absf(_rider_steer) > 0.02:
		var turn_sign := -1.0 if _current_speed_mps < -0.25 else 1.0
		var turn_rate := 2.15 if absf(_current_speed_mps) > 0.4 else 1.55
		rotation.y += _rider_steer * turn_rate * turn_sign * delta

	# Forward vector is local -Z
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		fwd = fwd.normalized()

	var step_vec := fwd * (_current_speed_mps * delta)
	var can_move := true
	var world := get_world_3d()
	if world != null and step_vec.length() > 0.001:
		var space := world.direct_space_state
		var move_dir := step_vec.normalized()
		var obs_from := global_position + Vector3(0.0, 0.72, 0.0)
		var obs_to := obs_from + move_dir * (0.88 + step_vec.length())
		var q_obs := PhysicsRayQueryParameters3D.create(obs_from, obs_to, 1)
		var hit_obs := space.intersect_ray(q_obs)
		if not hit_obs.is_empty():
			var n: Vector3 = hit_obs.get("normal", Vector3.ZERO)
			if n.y < 0.55:
				# Slide smoothly along wall instead of clipping through buildings
				var slide := step_vec - n * step_vec.dot(n)
				slide.y = 0.0
				step_vec = slide * 0.65
				_current_speed_mps *= 0.5

	if can_move:
		global_position += step_vec

	# Ground snapping (climbs Nile bridges, ramps, curbs & terrain smoothly)
	if world != null:
		var space := world.direct_space_state
		var g_from := global_position + Vector3(0.0, 1.35, 0.0)
		var g_to := global_position + Vector3(0.0, -2.5, 0.0)
		var q_g := PhysicsRayQueryParameters3D.create(g_from, g_to, 1)
		var hit_g := space.intersect_ray(q_g)
		if not hit_g.is_empty():
			var gy: float = (hit_g["position"] as Vector3).y
			global_position.y = lerpf(global_position.y, gy, clampf(delta * 16.0, 0.0, 1.0))

	# Animate natural 4-leg diagonal gait scaled by actual movement speed!
	var abs_spd := absf(_current_speed_mps)
	if abs_spd > 0.15:
		var is_trotting := abs_spd > 4.6
		var freq := clampf(abs_spd * 2.1, 4.5, 13.5)
		_gait_phase += delta * freq * (1.0 if _current_speed_mps >= 0.0 else -1.0)
		var amp := clampf(abs_spd * 0.095, 0.18, 0.58)
		_apply_diagonal_leg_gait(amp, is_trotting, delta)
		_body_root.position.y = _base_body_y + absf(sin(_gait_phase)) * (0.042 if is_trotting else 0.020)
		_body_root.rotation.x = sin(_gait_phase) * (0.04 if is_trotting else 0.02)
		_neck_pivot.rotation.x = lerpf(_neck_pivot.rotation.x, -0.05 + sin(_gait_phase) * 0.075, clampf(delta * 10.0, 0.0, 1.0))
		_neck_pivot.rotation.y = lerpf(_neck_pivot.rotation.y, _rider_steer * 0.24, clampf(delta * 8.0, 0.0, 1.0))
		_head_pivot.rotation = Vector3(sin(_gait_phase) * 0.05, _rider_steer * 0.18, 0.0)
		_animate_donkey_tail_and_ears(delta, 1.5 if is_trotting else 1.1)
	else:
		# Calm standing idle under rider
		_body_root.position.y = lerpf(_body_root.position.y, _base_body_y + sin(_anim_t * 2.2) * 0.008, clampf(delta * 8.0, 0.0, 1.0))
		_body_root.rotation.x = lerpf(_body_root.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		for i in range(4):
			_upper_legs[i].rotation.x = lerpf(_upper_legs[i].rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
			_lower_legs[i].rotation.x = lerpf(_lower_legs[i].rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		_neck_pivot.rotation.x = lerpf(_neck_pivot.rotation.x, -0.04, clampf(delta * 7.0, 0.0, 1.0))
		_neck_pivot.rotation.y = lerpf(_neck_pivot.rotation.y, sin(_anim_t * 1.1) * 0.10, clampf(delta * 5.0, 0.0, 1.0))
		_head_pivot.rotation = Vector3(sin(_anim_t * 1.4) * 0.04, sin(_anim_t * 1.1) * 0.12, 0.0)
		_animate_donkey_tail_and_ears(delta, 0.85)


func _apply_diagonal_leg_gait(amp: float, is_trot: bool, _delta: float) -> void:
	# Diagonal quadruped gait: FL(0) + RR(3) paired vs FR(1) + RL(2) opposite phase
	var phases := [0.0, PI, PI + 0.28, 0.28]
	for i in range(4):
		var ph: float = _gait_phase + phases[i]
		var swing := sin(ph) * amp
		var lift := maxf(0.0, -cos(ph)) * (0.64 if is_trot else 0.44)
		_upper_legs[i].rotation.x = swing
		_lower_legs[i].rotation.x = lift if i < 2 else -lift * 0.72


func _animate_donkey_tail_and_ears(delta: float, energy: float) -> void:
	if _ear_l and _ear_r:
		var twitch := sin(_anim_t * 7.5) * 0.14 if fmod(_anim_t, 2.3) < 0.45 else 0.0
		_ear_l.rotation.x = lerpf(_ear_l.rotation.x, twitch, clampf(delta * 12.0, 0.0, 1.0))
		_ear_r.rotation.x = lerpf(_ear_r.rotation.x, -twitch * 0.8, clampf(delta * 12.0, 0.0, 1.0))
	if _tail_pivot and _tail_tip_pivot:
		# Natural hanging pendulum sway side-to-side (rotation.z) + subtle forward/back bounce (rotation.x)
		_tail_pivot.rotation.z = sin(_anim_t * 3.1 * energy) * 0.24 * energy
		_tail_pivot.rotation.x = 0.06 + sin(_anim_t * 6.2 * energy) * 0.05
		_tail_tip_pivot.rotation.z = sin(_anim_t * 3.1 * energy - 0.65) * 0.22 * energy


func _update_donkey_reins() -> void:
	if _rein_mesh_l == null or _rein_mesh_r == null or _bit_ring_l == null or _bit_ring_r == null:
		return
	var target_l: Vector3
	var target_r: Vector3
	if is_mounted():
		var hands: Dictionary = {}
		if rider_node.has_method("get_hand_global_positions"):
			hands = rider_node.call("get_hand_global_positions") as Dictionary
		if hands.has("left") and hands.has("right"):
			target_l = hands["left"] as Vector3
			target_r = hands["right"] as Vector3
		else:
			target_l = _rein_anchor_rider_l.global_position
			target_r = _rein_anchor_rider_r.global_position
	elif hitched_cart != null and is_instance_valid(hitched_cart):
		target_l = hitched_cart.to_global(Vector3(-0.32, 0.88, -0.85))
		target_r = hitched_cart.to_global(Vector3(0.32, 0.88, -0.85))
	else:
		target_l = _rein_anchor_idle_l.global_position
		target_r = _rein_anchor_idle_r.global_position

	_orient_rein_bar(_rein_mesh_l, _bit_ring_l.global_position, target_l)
	_orient_rein_bar(_rein_mesh_r, _bit_ring_r.global_position, target_r)


func _orient_rein_bar(bar: MeshInstance3D, p0: Vector3, p1: Vector3) -> void:
	var diff := p1 - p0
	var length := diff.length()
	if length < 0.02:
		bar.visible = false
		return
	bar.visible = true
	var up := diff / length
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.95 else Vector3.FORWARD
	var right := ref.cross(up).normalized()
	var fwd := right.cross(up).normalized()
	bar.global_transform = Transform3D(Basis(right, up, fwd), (p0 + p1) * 0.5)
	bar.scale = Vector3(1.0, length, 1.0)


func _update_hitched_cart(delta: float) -> void:
	if hitched_cart == null or not is_instance_valid(hitched_cart) or karo_hitch_point == null:
		return
	var hitch_world := karo_hitch_point.global_position
	var rear_dir := global_transform.basis.z
	rear_dir.y = 0.0
	rear_dir = rear_dir.normalized() if rear_dir.length_squared() > 0.001 else Vector3.BACK
	var desired_pos := Vector3(hitch_world.x, global_position.y, hitch_world.z) + rear_dir * 1.15
	hitched_cart.global_position = hitched_cart.global_position.lerp(desired_pos, clampf(delta * 10.0, 0.0, 1.0))
	hitched_cart.rotation.y = lerp_angle(hitched_cart.rotation.y, rotation.y, clampf(delta * 5.5, 0.0, 1.0))


# ==============================================================================
# AUTONOMOUS AMBIENT AI STATE MACHINE (UNMOUNTED)
# ==============================================================================
func _update_state_machine(delta: float) -> void:
	if _is_donkey_anatomy:
		_animate_donkey_tail_and_ears(delta, 1.0)
	elif _ear_l and _ear_r:
		var twitch := sin(_anim_t * 7.5) * 0.14 if fmod(_anim_t, 2.3) < 0.45 else 0.0
		_ear_l.rotation.x = twitch
		_ear_r.rotation.x = -twitch * 0.8

	match current_state:
		AnimState.WALK, AnimState.TROT_RUN:
			var is_trot := current_state == AnimState.TROT_RUN
			var spd_mult := 1.85 if is_trot else 1.0
			_angle += move_speed * spd_mult * 0.34 * delta
			var nx := _origin.x + cos(_angle) * wander_radius
			var nz := _origin.z + sin(_angle) * (wander_radius * 0.82)
			var dx := -sin(_angle) * wander_radius
			var dz := cos(_angle) * (wander_radius * 0.82)
			global_position = Vector3(nx, _origin.y, nz)
			rotation.y = lerp_angle(rotation.y, atan2(-dx, -dz), clampf(delta * 8.0, 0.0, 1.0))
			_current_speed_mps = move_speed * spd_mult

			_gait_phase += delta * (10.5 if is_trot else 6.4)
			var amp := 0.56 if is_trot else 0.38
			_apply_diagonal_leg_gait(amp, is_trot, delta)

			_body_root.position.y = _base_body_y + absf(sin(_gait_phase)) * (0.038 if is_trot else 0.018)
			_body_root.rotation.x = sin(_gait_phase) * (0.042 if is_trot else 0.02)
			_neck_pivot.rotation.x = lerpf(_neck_pivot.rotation.x, sin(_gait_phase) * 0.08, clampf(delta * 8.0, 0.0, 1.0))
			_neck_pivot.rotation.y = lerpf(_neck_pivot.rotation.y, 0.0, clampf(delta * 8.0, 0.0, 1.0))
			_head_pivot.rotation = Vector3(sin(_gait_phase) * 0.06, 0.0, 0.0)
			_jaw_pivot.rotation.x = 0.0
			if not _is_donkey_anatomy:
				_tail_pivot.rotation.y = sin(_gait_phase * 1.4) * 0.38
				_tail_tip_pivot.rotation.y = cos(_gait_phase * 1.4) * 0.32

		AnimState.GRAZE_EAT:
			_current_speed_mps = 0.0
			for i in range(4):
				var target_leg := 0.14 if i < 2 else -0.08
				_upper_legs[i].rotation.x = lerpf(_upper_legs[i].rotation.x, target_leg, clampf(delta * 8.0, 0.0, 1.0))
				_lower_legs[i].rotation.x = lerpf(_lower_legs[i].rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
			_body_root.position.y = lerpf(_body_root.position.y, _base_body_y - 0.04, clampf(delta * 6.0, 0.0, 1.0))
			_body_root.rotation.x = lerpf(_body_root.rotation.x, 0.12, clampf(delta * 6.0, 0.0, 1.0))
			_neck_pivot.rotation.x = lerpf(_neck_pivot.rotation.x, 0.78, clampf(delta * 7.0, 0.0, 1.0))
			_neck_pivot.rotation.y = sin(_anim_t * 1.8) * 0.12
			_head_pivot.rotation.x = lerpf(_head_pivot.rotation.x, 0.25 + sin(_anim_t * 6.5) * 0.08, clampf(delta * 8.0, 0.0, 1.0))
			_jaw_pivot.rotation.x = absf(sin(_anim_t * 8.0)) * 0.24
			if not _is_donkey_anatomy:
				_tail_pivot.rotation.y = sin(_anim_t * 3.5) * 0.24

		AnimState.SIT_LIE_DOWN:
			_current_speed_mps = 0.0
			_body_root.position.y = lerpf(_body_root.position.y, _base_body_y * 0.46, clampf(delta * 6.0, 0.0, 1.0))
			_body_root.rotation.x = lerpf(_body_root.rotation.x, -0.14, clampf(delta * 6.0, 0.0, 1.0))
			for i in range(4):
				var up_target := -1.15 if i < 2 else -1.35
				var low_target := 1.25 if i < 2 else 1.45
				_upper_legs[i].rotation.x = lerpf(_upper_legs[i].rotation.x, up_target, clampf(delta * 7.0, 0.0, 1.0))
				_lower_legs[i].rotation.x = lerpf(_lower_legs[i].rotation.x, low_target, clampf(delta * 7.0, 0.0, 1.0))
			_neck_pivot.rotation.x = lerpf(_neck_pivot.rotation.x, -0.10, clampf(delta * 6.0, 0.0, 1.0))
			_head_pivot.rotation.y = sin(_anim_t * 1.1) * 0.22
			_jaw_pivot.rotation.x = 0.0
			if not _is_donkey_anatomy:
				_tail_pivot.rotation.y = sin(_anim_t * 2.2) * 0.35
				_tail_tip_pivot.rotation.y = 0.55 if kind == "cat" else sin(_anim_t * 2.2) * 0.25

		AnimState.IDLE_LOOK:
			_current_speed_mps = 0.0
			_body_root.position.y = lerpf(_body_root.position.y, _base_body_y + sin(_anim_t * 2.4) * 0.008, clampf(delta * 8.0, 0.0, 1.0))
			_body_root.rotation.x = lerpf(_body_root.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
			for i in range(4):
				_upper_legs[i].rotation.x = lerpf(_upper_legs[i].rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
				_lower_legs[i].rotation.x = lerpf(_lower_legs[i].rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
			_neck_pivot.rotation.x = lerpf(_neck_pivot.rotation.x, -0.08, clampf(delta * 7.0, 0.0, 1.0))
			_neck_pivot.rotation.y = sin(_anim_t * 1.6) * 0.26
			_head_pivot.rotation.y = sin(_anim_t * 1.6) * 0.30
			_head_pivot.rotation.z = cos(_anim_t * 2.1) * 0.08
			_jaw_pivot.rotation.x = 0.0
			if not _is_donkey_anatomy:
				_tail_pivot.rotation.y = sin(_anim_t * 4.5) * 0.32

		AnimState.VOCALIZE_WAG:
			_current_speed_mps = 0.0
			_body_root.position.y = lerpf(_body_root.position.y, _base_body_y, clampf(delta * 8.0, 0.0, 1.0))
			_body_root.rotation.x = lerpf(_body_root.rotation.x, -0.06, clampf(delta * 8.0, 0.0, 1.0))
			for i in range(4):
				_upper_legs[i].rotation.x = lerpf(_upper_legs[i].rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
				_lower_legs[i].rotation.x = lerpf(_lower_legs[i].rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
			_neck_pivot.rotation.x = lerpf(_neck_pivot.rotation.x, -0.22, clampf(delta * 8.0, 0.0, 1.0))
			_head_pivot.rotation.x = -0.18 + sin(_anim_t * 10.0) * 0.08
			_jaw_pivot.rotation.x = 0.16 + absf(sin(_anim_t * 12.0)) * 0.24
			if not _is_donkey_anatomy:
				_tail_pivot.rotation.y = sin(_anim_t * 15.0) * 0.65
				_tail_tip_pivot.rotation.y = cos(_anim_t * 15.0) * 0.55
