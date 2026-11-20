extends Node3D
class_name BirdFlockAI

## Detailed 3D Khartoum Bird Flocks (Pigeons/Doves & Brown Kites/Sparrows) with
## articulated left/right wings, fan tails, heads, and beaks.
## Supports:
## - "perch_or_ground": Perched on domes, parapets, walls, wires, or pecking crumbs on the ground;
##   bursts upward into rapid wing-flapping flight when player approaches within 4.5m or honks (H).
## - "sky_soar": Gliding and circling gracefully above the Khartoum skyline with rhythmic wing beats.

const BIRD_SCENE_PATH: String = "res://scenes/animals/bird.tscn"

@export var species: String = "pigeon" # "pigeon" or "kite"
@export var flock_mode: String = "perch_or_ground" # "perch_or_ground" or "sky_soar"
@export var bird_count: int = 5
@export var soar_radius: float = 24.0
@export var soar_speed: float = 0.38

var _origin: Vector3 = Vector3.ZERO
var _birds: Array[Dictionary] = []
var _scattered: bool = false
var _flight_timer: float = 0.0
var _soar_angle: float = 0.0
var _anim_t: float = 0.0
var _sfx: AudioStreamPlayer3D = null


func _ready() -> void:
	add_to_group("bird_flocks")
	_origin = global_position
	_soar_angle = randf() * TAU
	_anim_t = randf() * TAU
	_build_flock()


func _exit_tree() -> void:
	if _sfx != null:
		_sfx.stop()
		_sfx.stream = null


func get_bird_count() -> int:
	return _birds.size()


func scatter_from(origin: Vector3, radius: float) -> void:
	if flock_mode == "sky_soar" or _scattered:
		return
	if global_position.distance_to(origin) > radius:
		return
	_scattered = true
	_flight_timer = 6.0
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if _sfx and audio_mgr and audio_mgr.bird_scatter_stream:
		_sfx.stream = audio_mgr.bird_scatter_stream
		_sfx.play()
	var vfx_mgr := get_node_or_null("/root/VFXManager")
	if vfx_mgr and get_parent() is Node3D:
		vfx_mgr.spawn_feather_burst(get_parent() as Node3D, global_position + Vector3(0.0, 0.25, 0.0))


func _build_flock() -> void:
	_sfx = AudioStreamPlayer3D.new()
	_sfx.max_distance = 42.0
	_sfx.unit_size = 4.5
	_sfx.volume_db = -3.0
	add_child(_sfx)

	var bird_packed: PackedScene = null
	if ResourceLoader.exists(BIRD_SCENE_PATH):
		bird_packed = ResourceLoader.load(BIRD_SCENE_PATH) as PackedScene

	var is_kite := species == "kite"
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.46, 0.30, 0.18, 1.0) if is_kite else Color(0.68, 0.70, 0.74, 1.0)
	body_mat.roughness = 0.82

	var wing_mat := StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.32, 0.20, 0.12, 1.0) if is_kite else Color(0.48, 0.50, 0.56, 1.0)
	wing_mat.roughness = 0.85

	for i in range(bird_count):
		var bird_node: Node3D = null
		if bird_packed != null:
			bird_node = bird_packed.instantiate() as Node3D
		else:
			bird_node = Node3D.new()

		bird_node.name = "Bird_%d" % i
		var scale_f := 1.45 if is_kite else 1.0
		bird_node.scale = Vector3.ONE * scale_f

		var base_offset := Vector3.ZERO
		if flock_mode == "sky_soar":
			base_offset = Vector3((i - bird_count * 0.5) * 1.8, sin(float(i) * 1.3) * 0.65, absf(float(i) - bird_count * 0.5) * 1.4)
		else:
			base_offset = Vector3((i - bird_count * 0.5) * 0.46, 0.0, sin(float(i) * 1.7) * 0.32)
		bird_node.position = base_offset

		var body_mi := bird_node.get_node_or_null("BreastBody") as MeshInstance3D
		if body_mi:
			body_mi.material_override = body_mat
		var head_pivot := bird_node.get_node_or_null("HeadPivot") as Node3D
		if head_pivot and head_pivot.get_node_or_null("HeadMesh") is MeshInstance3D:
			(head_pivot.get_node("HeadMesh") as MeshInstance3D).material_override = body_mat
		var tail_pivot := bird_node.get_node_or_null("FanTailPivot") as Node3D
		if tail_pivot and tail_pivot.get_node_or_null("TailMesh") is MeshInstance3D:
			(tail_pivot.get_node("TailMesh") as MeshInstance3D).material_override = wing_mat
		var wing_l := bird_node.get_node_or_null("LeftWingPivot") as Node3D
		if wing_l and wing_l.get_node_or_null("WingMesh") is MeshInstance3D:
			(wing_l.get_node("WingMesh") as MeshInstance3D).material_override = wing_mat
		var wing_r := bird_node.get_node_or_null("RightWingPivot") as Node3D
		if wing_r and wing_r.get_node_or_null("WingMesh") is MeshInstance3D:
			(wing_r.get_node("WingMesh") as MeshInstance3D).material_override = wing_mat

		_optimize_bird_meshes(bird_node)
		add_child(bird_node)

		_birds.append({
			"node": bird_node,
			"base_pos": base_offset,
			"head": head_pivot,
			"tail": tail_pivot,
			"wing_l": wing_l,
			"wing_r": wing_r,
			"phase": float(i) * 1.15,
		})


func _optimize_bird_meshes(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.visibility_range_end = 115.0
	for ch in node.get_children():
		_optimize_bird_meshes(ch)


func _process(delta: float) -> void:
	_anim_t += delta
	if flock_mode == "sky_soar":
		_process_sky_soar(delta)
	else:
		_process_perch_or_ground(delta)


func _process_sky_soar(delta: float) -> void:
	_soar_angle += soar_speed * delta
	var nx := _origin.x + cos(_soar_angle) * soar_radius
	var nz := _origin.z + sin(_soar_angle) * (soar_radius * 0.82)
	var ny := _origin.y + sin(_soar_angle * 2.0) * 1.8
	var dx := -sin(_soar_angle) * soar_radius
	var dz := cos(_soar_angle) * (soar_radius * 0.82)
	global_position = Vector3(nx, ny, nz)
	rotation.y = atan2(-dx, -dz)

	for b in _birds:
		var ph: float = b["phase"]
		var node := b["node"] as Node3D
		var base_p: Vector3 = b["base_pos"]
		# Alternate rhythmic wing beats with graceful thermal gliding
		var cycle := fmod(_anim_t + ph, 4.5)
		var flap := sin((_anim_t + ph) * 11.0) * 0.55 if cycle < 2.2 else sin((_anim_t + ph) * 2.0) * 0.08
		node.position.y = base_p.y + sin((_anim_t + ph) * 3.0) * 0.14
		node.rotation.z = sin(_soar_angle + ph * 0.3) * 0.18
		var wl := b["wing_l"] as Node3D
		var wr := b["wing_r"] as Node3D
		var tl := b["tail"] as Node3D
		if wl:
			wl.rotation.z = flap
			wl.rotation.y = 0.0
		if wr:
			wr.rotation.z = -flap
			wr.rotation.y = 0.0
		if tl:
			tl.scale.x = 1.25


func _process_perch_or_ground(delta: float) -> void:
	var local_players := get_tree().get_nodes_in_group("local_player")
	if not _scattered and not local_players.is_empty():
		var ppos := (local_players[0] as Node3D).global_position
		if global_position.distance_to(ppos) <= 4.5:
			scatter_from(ppos, 6.5)

	if _scattered:
		_flight_timer -= delta
		var t := 6.0 - _flight_timer
		var lift := sin(clampf(t / 6.0, 0.0, 1.0) * PI) * 9.5
		global_position = _origin + Vector3(cos(t * 1.5) * 4.8, lift, sin(t * 1.5) * 4.8)
		rotation.y = t * 1.9
		for b in _birds:
			var ph: float = b["phase"]
			var node := b["node"] as Node3D
			var base_p: Vector3 = b["base_pos"]
			var flap := sin((_anim_t + ph) * 22.0) * 0.72
			node.position.y = base_p.y + sin((_anim_t + ph) * 16.0) * 0.16
			var wl := b["wing_l"] as Node3D
			var wr := b["wing_r"] as Node3D
			var hd := b["head"] as Node3D
			var tl := b["tail"] as Node3D
			if wl:
				wl.rotation.z = flap
				wl.rotation.y = 0.0
			if wr:
				wr.rotation.z = -flap
				wr.rotation.y = 0.0
			if hd:
				hd.rotation.x = 0.0
			if tl:
				tl.scale.x = 1.35
		if _flight_timer <= 0.0:
			_scattered = false
			global_position = _origin
			rotation.y = 0.0
	else:
		var is_ground := _origin.y < 0.5
		for b in _birds:
			var ph: float = b["phase"]
			var node := b["node"] as Node3D
			var base_p: Vector3 = b["base_pos"]
			var wl := b["wing_l"] as Node3D
			var wr := b["wing_r"] as Node3D
			var hd := b["head"] as Node3D
			var tl := b["tail"] as Node3D
			# Fold wings neatly against body when perched or pecking
			if wl:
				wl.rotation.z = 0.65
				wl.rotation.y = -0.35
			if wr:
				wr.rotation.z = -0.65
				wr.rotation.y = 0.35
			if tl:
				tl.scale.x = 0.9
			# Head-bobbing crumb pecking & look-around
			var peck_wave := maxf(0.0, sin((_anim_t + ph) * 4.2))
			if is_ground and peck_wave > 0.55:
				node.rotation.x = -0.38 * peck_wave
				if hd:
					hd.rotation.x = -0.55 * peck_wave
			else:
				node.rotation.x = lerpf(node.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
				if hd:
					hd.rotation.x = 0.0
					hd.rotation.y = sin((_anim_t + ph) * 1.8) * 0.35
			node.position.y = base_p.y + maxf(0.0, sin((_anim_t + ph) * 2.8)) * 0.03
