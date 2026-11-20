extends Node3D
class_name WorldAmbianceController

## Manages spatial souq/tea/water audio, swimming Nile fish, Poly Haven 3D prop clusters,
## desert dust motes, and spawns AnimalAI dogs, cats, goats, and perched/street bird flocks.

const FISH_MODEL_PATH: String = "res://assets/models/props/fish.glb"

var _tea_ember_light: OmniLight3D = null
var _ember_time: float = 0.0
var _fish_entries: Array[Dictionary] = []
var _ripple_rings: Array[MeshInstance3D] = []


func _ready() -> void:
	if OS.has_feature("web"):
		call_deferred("_setup_web_progressive")
		return
	_setup_dust_motes()
	_setup_market_audio_emitters()
	_setup_tea_stall_effects()
	_setup_fish_basin()
	_setup_props()
	_setup_animals_and_birds()


func _setup_web_progressive() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_setup_tea_stall_effects()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_setup_props()
	get_tree().call_group("network_hud", "_apply_safari_web_graphics_profile")


func _exit_tree() -> void:
	for ch in get_children():
		if ch is AudioStreamPlayer3D:
			var ap := ch as AudioStreamPlayer3D
			ap.stop()
			ap.stream = null


func _process(delta: float) -> void:
	_update_ember_flicker(delta)
	_update_fish_and_ripples(delta)


func _setup_dust_motes() -> void:
	var vfx_mgr := get_node_or_null("/root/VFXManager")
	if vfx_mgr:
		vfx_mgr.create_desert_dust_motes(self)


func _setup_market_audio_emitters() -> void:
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr == null or audio_mgr.market_ambience_stream == null:
		return
	var positions: Array[Vector3] = [
		Vector3(22.0, 2.0, -12.0),  # دكان الأزهري & مخبز الخرطوم
		Vector3(44.0, 2.0, -12.0),  # مطعم فول وطعمية & بنشر
		Vector3(86.0, 2.0, -24.0),  # سوق السمك
	]
	for idx in range(positions.size()):
		var p := AudioStreamPlayer3D.new()
		p.name = "MarketBustle%d" % idx
		p.position = positions[idx]
		p.stream = audio_mgr.market_ambience_stream
		p.max_distance = 90.0
		p.unit_size = 10.0
		p.volume_db = -9.0
		add_child(p)
		p.play()


func _setup_tea_stall_effects() -> void:
	var tea_pos := Vector3(17.9, 0.98, 17.8)
	var vfx_mgr := get_node_or_null("/root/VFXManager")
	if vfx_mgr:
		vfx_mgr.create_steam_particles(self, tea_pos + Vector3(0.0, 0.35, 0.0))

	_tea_ember_light = OmniLight3D.new()
	_tea_ember_light.name = "TeaEmberLight"
	_tea_ember_light.position = tea_pos + Vector3(-0.7, 0.14, 0.0)
	_tea_ember_light.light_color = Color(1.0, 0.38, 0.08, 1.0)
	_tea_ember_light.light_energy = 1.6
	_tea_ember_light.omni_range = 4.5
	add_child(_tea_ember_light)

	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr and audio_mgr.tea_stall_stream:
		var tea_sfx := AudioStreamPlayer3D.new()
		tea_sfx.name = "TeaStallAudio"
		tea_sfx.position = tea_pos
		tea_sfx.stream = audio_mgr.tea_stall_stream
		tea_sfx.max_distance = 26.0
		tea_sfx.unit_size = 3.5
		tea_sfx.volume_db = -6.0
		add_child(tea_sfx)
		tea_sfx.play()


func _setup_fish_basin() -> void:
	var basin_center := Vector3(88.0, 0.48, -28.0)

	var vfx_mgr := get_node_or_null("/root/VFXManager")
	if vfx_mgr:
		vfx_mgr.create_water_splash_particles(self, basin_center + Vector3(0.0, 0.15, 0.0))

	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr and audio_mgr.water_basin_stream:
		var water_sfx := AudioStreamPlayer3D.new()
		water_sfx.name = "WaterBasinAudio"
		water_sfx.position = basin_center
		water_sfx.stream = audio_mgr.water_basin_stream
		water_sfx.max_distance = 34.0
		water_sfx.unit_size = 4.5
		water_sfx.volume_db = -5.5
		add_child(water_sfx)
		water_sfx.play()

	for i in range(3):
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.85
		torus.outer_radius = 0.94
		torus.rings = 20
		torus.ring_segments = 6
		ring.mesh = torus
		ring.position = basin_center + Vector3(0.0, 0.03, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.96, 1.0, 0.45)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = mat
		add_child(ring)
		_ripple_rings.append(ring)

	var fish_scene: PackedScene = null
	if ResourceLoader.exists(FISH_MODEL_PATH):
		fish_scene = ResourceLoader.load(FISH_MODEL_PATH) as PackedScene

	for i in range(5):
		var fish_node: Node3D = null
		if fish_scene:
			fish_node = fish_scene.instantiate() as Node3D
		if fish_node:
			var wrapper := Node3D.new()
			wrapper.add_child(fish_node)
			var bounds := CharacterModelLoader._compute_mesh_aabb(fish_node)
			if bounds.size.length() > 0.01:
				var max_dim := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
				fish_node.scale = Vector3.ONE * (0.85 / max_dim)
			else:
				fish_node.scale = Vector3.ONE * 0.65
			wrapper.position = basin_center
			add_child(wrapper)
			_fish_entries.append({
				"node": wrapper,
				"center": basin_center,
				"radius_x": 1.6 + float(i % 3) * 0.45,
				"radius_z": 1.0 + float(i % 2) * 0.45,
				"angle": float(i) * (TAU / 5.0),
				"speed": 0.65 + float(i) * 0.14,
			})


func _setup_props() -> void:
	_place_prop("res://assets/models/props/crate/crate.gltf", Vector3(15.5, 0.0, -11.5), 0.85, 0.2)
	_place_prop("res://assets/models/props/crate/crate.gltf", Vector3(23.5, 0.0, -11.5), 0.85, -0.4)
	_place_prop("res://assets/models/props/barrel/barrel.gltf", Vector3(19.2, 0.0, -11.5), 1.0, 0.0)
	_place_prop("res://assets/models/props/barrel/barrel.gltf", Vector3(56.8, 0.0, -11.6), 1.0, 0.5)
	_place_prop("res://assets/models/props/tire/tire.gltf", Vector3(52.2, 0.0, -11.4), 0.9, 0.3)
	_place_prop("res://assets/models/props/tire/tire.gltf", Vector3(53.4, 0.0, -11.4), 0.9, 1.1)
	_place_prop("res://assets/models/props/tire/tire.gltf", Vector3(52.8, 0.42, -11.4), 0.9, 0.7)
	_place_prop("res://assets/models/props/stool/stool.gltf", Vector3(31.2, 0.0, -11.4), 0.75, 0.0)
	_place_prop("res://assets/models/props/stool/stool.gltf", Vector3(33.4, 0.0, -11.4), 0.75, 0.5)
	_place_prop("res://assets/models/props/stool/stool.gltf", Vector3(14.5, 0.0, 14.5), 0.65, 0.2)
	_place_prop("res://assets/models/props/stool/stool.gltf", Vector3(16.0, 0.0, 14.2), 0.65, -0.3)
	_place_prop("res://assets/models/props/bench/bench.gltf", Vector3(40.5, 0.0, -11.4), 0.85, 0.0)
	_place_prop("res://assets/models/props/table/table.gltf", Vector3(32.3, 0.0, -11.4), 0.75, 0.0)
	_place_prop("res://assets/models/props/bucket/bucket.gltf", Vector3(17.8, 0.0, 18.6), 0.45, 0.2)
	_place_prop("res://assets/models/props/pot/pot.gltf", Vector3(15.2, 0.0, 17.8), 0.55, 0.0)
	_place_prop("res://assets/models/props/lantern/lantern.gltf", Vector3(16.2, 0.88, 16.8), 0.48, 0.0)
	_place_prop("res://assets/models/props/lantern/lantern.gltf", Vector3(-24.2, 0.0, -16.8), 0.6, 0.0)
	_place_prop("res://assets/models/props/plant/plant.gltf", Vector3(-19.5, 0.0, -17.5), 1.2, 0.0)
	_place_prop("res://assets/models/props/plant/plant.gltf", Vector3(-13.5, 0.0, 13.0), 1.2, 0.8)
	_place_prop("res://assets/models/props/cart/CoffeeCart_01.gltf", Vector3(19.6, 0.0, 17.5), 1.55, 0.4)
	_place_prop("res://assets/models/props/cart/CoffeeCart_01.gltf", Vector3(68.0, 0.0, -14.0), 1.55, -0.3)


func _place_prop(res_path: String, pos: Vector3, target_height: float, yaw: float) -> void:
	if not ResourceLoader.exists(res_path):
		return
	var packed := ResourceLoader.load(res_path) as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	holder.add_child(inst)
	var bounds := CharacterModelLoader._compute_mesh_aabb(inst)
	if bounds.size.y > 0.01:
		var s := target_height / bounds.size.y
		inst.scale = Vector3.ONE * s
		inst.position.y = -bounds.position.y * s
	var vis_dist := 55.0 if ("cart" in res_path.to_lower() or "bench" in res_path.to_lower() or "barrel" in res_path.to_lower()) else 35.0
	_optimize_prop_rendering(inst, vis_dist, false)
	add_child(holder)


func _optimize_prop_rendering(node: Node, vis_dist: float, cast_shadows: bool) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.visibility_range_end = vis_dist
	for child in node.get_children():
		_optimize_prop_rendering(child, vis_dist, cast_shadows)


func _setup_animals_and_birds() -> void:
	var animal_specs := [
		{"kind": "dog", "pos": Vector3(-13.0, 0.0, 20.0), "col": Color(0.62, 0.44, 0.26), "r": 3.4, "spd": 1.3},
		{"kind": "dog", "pos": Vector3(32.0, 0.0, 40.0), "col": Color(0.32, 0.24, 0.18), "r": 3.8, "spd": 1.4},
		{"kind": "dog", "pos": Vector3(-62.0, 0.0, -18.0), "col": Color(0.72, 0.56, 0.36), "r": 3.6, "spd": 1.25},
		{"kind": "cat", "pos": Vector3(17.5, 0.0, 14.5), "col": Color(0.85, 0.62, 0.34), "r": 1.8, "spd": 0.75},
		{"kind": "cat", "pos": Vector3(79.0, 0.0, -23.0), "col": Color(0.35, 0.35, 0.38), "r": 2.2, "spd": 0.8},
		{"kind": "cat", "pos": Vector3(-24.0, 0.0, -14.0), "col": Color(0.92, 0.88, 0.82), "r": 1.9, "spd": 0.75},
		{"kind": "goat", "pos": Vector3(-42.0, 0.0, 41.0), "col": Color(0.88, 0.84, 0.76), "r": 3.2, "spd": 1.0},
		{"kind": "goat", "pos": Vector3(44.0, 0.0, 41.0), "col": Color(0.45, 0.36, 0.28), "r": 3.5, "spd": 1.1},
		{"kind": "donkey", "pos": Vector3(68.0, 0.0, -34.0), "col": Color(0.54, 0.48, 0.43), "r": 4.2, "spd": 0.95},
		{"kind": "donkey", "pos": Vector3(-64.0, 0.0, 36.0), "col": Color(0.48, 0.43, 0.38), "r": 4.0, "spd": 0.9},
		{"kind": "donkey", "pos": Vector3(14.0, 0.0, 22.0), "col": Color(0.56, 0.50, 0.44), "r": 3.4, "spd": 0.85},
	]
	for idx in range(animal_specs.size()):
		var s: Dictionary = animal_specs[idx]
		var animal := AnimalAI.new()
		animal.name = "Animal_%d" % idx
		animal.kind = s["kind"]
		animal.coat_color = s["col"]
		animal.wander_radius = s["r"]
		animal.move_speed = s["spd"]
		animal.position = s["pos"]
		add_child(animal)

	# 6 BirdFlockAI flocks totaling 32 detailed 3D birds (22 perched/ground + 10 sky soaring)
	var flock_specs := [
		{"mode": "perch_or_ground", "species": "pigeon", "count": 6, "pos": Vector3(11.5, 0.0, -10.8), "r": 0.0, "spd": 0.0},
		{"mode": "perch_or_ground", "species": "pigeon", "count": 5, "pos": Vector3(28.0, 6.26, -8.0), "r": 0.0, "spd": 0.0},
		{"mode": "perch_or_ground", "species": "pigeon", "count": 6, "pos": Vector3(-28.0, 6.05, -20.0), "r": 0.0, "spd": 0.0},
		{"mode": "perch_or_ground", "species": "kite", "count": 5, "pos": Vector3(78.0, 0.0, 26.0), "r": 0.0, "spd": 0.0},
		{"mode": "sky_soar", "species": "kite", "count": 5, "pos": Vector3(0.0, 24.0, -8.0), "r": 28.0, "spd": 0.36},
		{"mode": "sky_soar", "species": "pigeon", "count": 5, "pos": Vector3(42.0, 20.0, 16.0), "r": 22.0, "spd": 0.44},
	]
	for f_idx in range(flock_specs.size()):
		var fs: Dictionary = flock_specs[f_idx]
		var flock := BirdFlockAI.new()
		flock.name = "BirdFlock_%d" % f_idx
		flock.flock_mode = fs["mode"]
		flock.species = fs["species"]
		flock.bird_count = fs["count"]
		flock.soar_radius = fs["r"]
		flock.soar_speed = fs["spd"]
		flock.position = fs["pos"]
		add_child(flock)


func _update_ember_flicker(delta: float) -> void:
	if _tea_ember_light == null:
		return
	_ember_time += delta * 9.0
	_tea_ember_light.light_energy = 1.45 + 0.35 * sin(_ember_time) + 0.2 * cos(_ember_time * 2.3)


func _update_fish_and_ripples(delta: float) -> void:
	for entry in _fish_entries:
		entry["angle"] = float(entry["angle"]) + float(entry["speed"]) * delta
		var a: float = entry["angle"]
		var cx: Vector3 = entry["center"]
		var rx: float = entry["radius_x"]
		var rz: float = entry["radius_z"]
		var nx := cx.x + cos(a) * rx
		var nz := cx.z + sin(a) * rz
		var dx := -sin(a) * rx
		var dz := cos(a) * rz
		var node: Node3D = entry["node"]
		node.position = Vector3(nx, cx.y - 0.10 + sin(a * 3.0) * 0.03, nz)
		node.rotation.y = atan2(-dx, -dz)

	for i in range(_ripple_rings.size()):
		var ring := _ripple_rings[i]
		var phase := fmod(_ember_time * 0.09 + float(i) * 0.33, 1.0)
		var sc := 0.35 + phase * 1.65
		ring.scale = Vector3(sc, 0.2, sc)
		var mat := ring.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color.a = (1.0 - phase) * 0.45
