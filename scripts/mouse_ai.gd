extends Node3D
class_name MouseAI

## Autonomous scurrying Khartoum street mouse/rat AI (`~0.18m-0.24m` long).
## Loads downloaded rodent 3D `.glb`/`.gltf` models (`mouse`, `rat`, `rodent`)
## dynamically, patrols wall edges with sniff pauses, and flees rapidly with a
## faint spatial squeak whenever a player or vehicle comes within 4.5m.

@export var scurry_speed: float = 2.8
@export var flee_speed: float = 4.2
@export var flee_radius: float = 4.5
@export var target_length: float = 0.21
@export var wall_edge_a: Vector3 = Vector3.ZERO
@export var wall_edge_b: Vector3 = Vector3(4.0, 0.0, 0.0)
@export var cover_pos: Vector3 = Vector3.ZERO

static var _cached_rodent_scene: PackedScene = null
static var _rodent_search_done: bool = false

var _model_pivot: Node3D = null
var _squeak_player: AudioStreamPlayer3D = null
var _rng := RandomNumberGenerator.new()

var _phase: float = 0.0
var _pause_timer: float = 0.0
var _squeak_cooldown: float = 0.0
var _flee_timer: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("mice")
	_rng.seed = hash(name) ^ int(absf(position.x) * 31.0 + absf(position.z) * 17.0)
	_phase = _rng.randf_range(0.0, TAU)
	target_length = _rng.randf_range(0.18, 0.24)

	if wall_edge_a == Vector3.ZERO and wall_edge_b == Vector3(4.0, 0.0, 0.0):
		wall_edge_a = position + Vector3(-2.4, 0.0, -0.5)
		wall_edge_b = position + Vector3(2.4, 0.0, 0.5)
	if cover_pos == Vector3.ZERO:
		cover_pos = wall_edge_a

	_target_pos = wall_edge_b
	_build_rodent_visual()
	_setup_audio()


func _process(delta: float) -> void:
	_squeak_cooldown = maxf(0.0, _squeak_cooldown - delta)

	var threat_pos := _nearest_threat_within(flee_radius)
	if threat_pos != Vector3.INF:
		if _flee_timer <= 0.0 and _squeak_cooldown <= 0.0:
			_play_squeak()
		_flee_timer = 1.6
		_pause_timer = 0.0

	if _flee_timer > 0.0:
		_flee_timer -= delta
		_move_toward(cover_pos, flee_speed, delta, 36.0)
		return

	if _pause_timer > 0.0:
		_pause_timer -= delta
		_animate_sniff(delta)
		return

	var reached := _move_toward(_target_pos, scurry_speed, delta, 28.0)
	if reached:
		_pause_timer = _rng.randf_range(0.8, 2.5)
		var next_a := wall_edge_a.lerp(wall_edge_b, _rng.randf())
		_target_pos = next_a + Vector3(_rng.randf_range(-0.35, 0.35), 0.0, _rng.randf_range(-0.35, 0.35))


func _move_toward(dest: Vector3, spd: float, delta: float, wiggle_freq: float) -> bool:
	var to_target := dest - position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist < 0.14:
		return true

	var dir := to_target / dist
	position += dir * minf(spd * delta, dist)
	position.y = 0.0

	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * 14.0))

	_phase += delta * wiggle_freq
	if _model_pivot:
		_model_pivot.rotation.y = sin(_phase) * 0.14
		_model_pivot.rotation.z = cos(_phase * 0.5) * 0.06
		_model_pivot.position.y = absf(sin(_phase * 0.85)) * 0.012
	return false


func _animate_sniff(delta: float) -> void:
	_phase += delta * 9.0
	if _model_pivot:
		_model_pivot.position.y = 0.0
		_model_pivot.rotation.x = sin(_phase) * 0.08
		_model_pivot.rotation.y = sin(_phase * 0.45) * 0.18
		_model_pivot.rotation.z = 0.0


func _nearest_threat_within(radius: float) -> Vector3:
	var r2 := radius * radius
	for grp in ["players", "vehicles"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node3D:
				var d2 := (n as Node3D).global_position.distance_squared_to(global_position)
				if d2 <= r2:
					return (n as Node3D).global_position
	return Vector3.INF


func _play_squeak() -> void:
	_squeak_cooldown = 3.5
	if _squeak_player and _squeak_player.stream:
		_squeak_player.pitch_scale = _rng.randf_range(0.92, 1.15)
		_squeak_player.play()


func _setup_audio() -> void:
	_squeak_player = AudioStreamPlayer3D.new()
	_squeak_player.name = "SqueakAudio"
	_squeak_player.max_distance = 14.0
	_squeak_player.unit_size = 1.8
	_squeak_player.volume_db = -11.0
	add_child(_squeak_player)
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr and audio_mgr.mouse_squeak_stream:
		_squeak_player.stream = audio_mgr.mouse_squeak_stream


func _build_rodent_visual() -> void:
	_model_pivot = Node3D.new()
	_model_pivot.name = "RodentPivot"
	add_child(_model_pivot)

	var scene := _find_rodent_scene()
	if scene != null:
		var inst := scene.instantiate() as Node3D
		if inst != null:
			_model_pivot.add_child(inst)
			var aabb := CharacterModelLoader._compute_mesh_aabb(inst)
			var raw_len := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
			if raw_len > 0.001:
				var s := target_length / raw_len
				inst.scale = Vector3.ONE * s
				# Seat cleanly on y = 0.0 and center X/Z; align longest horizontal axis along -Z
				var cx := (aabb.position.x + aabb.size.x * 0.5) * s
				var cz := (aabb.position.z + aabb.size.z * 0.5) * s
				var bottom := aabb.position.y * s
				inst.position = Vector3(-cx, -bottom, -cz)
				if aabb.size.x > aabb.size.z * 1.15:
					inst.rotation.y = PI * 0.5
			_apply_mouse_render_culling(_model_pivot)
			return

	# Clean lightweight fallback only if no rodent .glb/.gltf exists
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color(0.36, 0.33, 0.30, 1.0)
	fur.roughness = 0.9
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.028
	cap.height = target_length * 0.72
	body.mesh = cap
	body.material_override = fur
	body.rotation.x = PI * 0.5
	body.position = Vector3(0.0, 0.028, 0.0)
	_model_pivot.add_child(body)

	var tail := MeshInstance3D.new()
	var t_mesh := CylinderMesh.new()
	t_mesh.top_radius = 0.003
	t_mesh.bottom_radius = 0.008
	t_mesh.height = target_length * 0.6
	tail.mesh = t_mesh
	tail.material_override = fur
	tail.rotation.x = PI * 0.48
	tail.position = Vector3(0.0, 0.022, target_length * 0.55)
	_model_pivot.add_child(tail)
	_apply_mouse_render_culling(_model_pivot)


func _apply_mouse_render_culling(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.visibility_range_end = 28.0
	for child in node.get_children():
		_apply_mouse_render_culling(child)


static func _find_rodent_scene() -> PackedScene:
	if _rodent_search_done:
		return _cached_rodent_scene
	_rodent_search_done = true
	var path := _scan_for_rodent_model("res://assets/models")
	if path != "" and ResourceLoader.exists(path):
		_cached_rodent_scene = ResourceLoader.load(path) as PackedScene
	return _cached_rodent_scene


static func _scan_for_rodent_model(dir_path: String) -> String:
	var entries := ResourceLoader.list_directory(dir_path)
	entries.sort()
	for entry in entries:
		var lower := entry.to_lower()
		var full := "%s/%s" % [dir_path, entry]
		if entry.ends_with("/"):
			var hit := _scan_for_rodent_model(full.trim_suffix("/"))
			if hit != "":
				return hit
		elif lower.ends_with(".glb") or lower.ends_with(".gltf") or lower.ends_with(".fbx"):
			if "mouse" in lower or "rat" in lower or "rodent" in lower or "rat" in dir_path.to_lower() or "mouse" in dir_path.to_lower():
				return full
	return ""
