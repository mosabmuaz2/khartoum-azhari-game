extends Node3D
class_name TrafficAI

## Autonomous Khartoum Traffic Manager & AI Driver Controller (`scripts/traffic_ai.gd`).
## Spawns 12 AI-driven vehicles (4 Amjad minibuses, 3 Boks pickups, 3 Raksha 3-wheelers, 2 Sedans)
## actively driving along the main asphalt avenues (شارع الزلط), side streets, and central roundabout (صينية التقاطع).
## Every AI vehicle has:
## - A visible, brightly lit 3D driver character in the driver's seat with hands on the steering wheel.
## - Smooth waypoint road-lane navigation, intersection turns, rotating/steering wheels, working headlights & brake lights.
## - Forward obstacle detection (`RayCast3D` + `Area3D`) that smoothly brakes and honks when the player,
##   pedestrians, or other cars cross in front of them.

const SCENE_AMJAD: String = "res://scenes/vehicles/ai_amjad.tscn"
const SCENE_BOKS: String = "res://scenes/vehicles/ai_boks.tscn"
const SCENE_RAKSHA: String = "res://scenes/vehicles/ai_raksha.tscn"
const SCENE_SEDAN: String = "res://scenes/vehicles/ai_sedan.tscn"

const VEHICLE_SCENES: Dictionary = {
	SCENE_AMJAD: preload("res://scenes/vehicles/ai_amjad.tscn"),
	SCENE_BOKS: preload("res://scenes/vehicles/ai_boks.tscn"),
	SCENE_RAKSHA: preload("res://scenes/vehicles/ai_raksha.tscn"),
	SCENE_SEDAN: preload("res://scenes/vehicles/ai_sedan.tscn"),
}

const DRIVER_KEYWORDS: Array[String] = [
	"dreiver",
	"Man",
	"ritchman",
	"Oldman",
	"homeless",
]

var ai_vehicles: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("traffic_ai")
	if OS.has_feature("web"):
		call_deferred("_spawn_traffic_fleet_web")
		return
	_spawn_traffic_fleet()


func _spawn_traffic_fleet_web() -> void:
	var routes := _build_lane_routes()
	# Lightweight Web traffic: 4 nearby core vehicles, frame-sliced without extra Mixamo driver rigs
	var fleet_specs := [
		{"scene": SCENE_AMJAD, "route": 0, "wp": 2, "spd": 9.8, "drv": "dreiver"},
		{"scene": SCENE_BOKS,  "route": 0, "wp": 4, "spd": 10.5, "drv": "Man"},
		{"scene": SCENE_RAKSHA,"route": 1, "wp": 2, "spd": 8.2, "drv": "homeless"},
		{"scene": SCENE_SEDAN, "route": 1, "wp": 4, "spd": 11.0, "drv": "Man"},
	]
	for idx in range(fleet_specs.size()):
		await get_tree().process_frame
		if not is_inside_tree():
			return
		var spec: Dictionary = fleet_specs[idx]
		var scene_path: String = spec["scene"]
		var packed := VEHICLE_SCENES.get(scene_path) as PackedScene
		if packed == null:
			continue
		var veh := packed.instantiate() as VehicleController
		if veh == null:
			continue
		veh.name = "AIVehicle_%d" % idx
		veh.add_to_group("ai_traffic_vehicles")
		veh.driver_peer_id = 0
		veh.ai_autopilot_active = true
		veh.set_physics_process(false)
		var r_idx: int = spec["route"]
		var wp_list: Array = routes[r_idx]
		var wp_i: int = int(spec["wp"]) % wp_list.size()
		var next_i: int = (wp_i + 1) % wp_list.size()
		var start_pos: Vector3 = wp_list[wp_i]
		var next_pos: Vector3 = wp_list[next_i]
		var dir := (next_pos - start_pos).normalized()
		veh.position = start_pos
		veh.rotation.y = atan2(-dir.x, -dir.z)
		add_child(veh)
		var sensors := _setup_obstacle_sensors(veh)
		_optimize_ai_vehicle_lights(veh)
		ai_vehicles.append({
			"vehicle": veh,
			"waypoints": wp_list,
			"wp_index": next_i,
			"cruise_speed": float(spec["spd"]),
			"current_speed": float(spec["spd"]) * 0.75,
			"current_steer": 0.0,
			"ray": sensors["ray"],
			"area": sensors["area"],
			"horn_timer": randf_range(0.5, 2.5),
			"stuck_timer": 0.0,
			"braking": false,
		})


func get_active_vehicle_count() -> int:
	return ai_vehicles.size()


func _build_lane_routes() -> Array[Array]:
	# 4 multi-lane closed-loop road circuits across Al-Azhari's 360m x 360m road network:
	# Route 0: North-South Main Asphalt Avenue + Roundabout Ring (Right-hand traffic lanes x = ±3.4)
	var route_ns: Array[Vector3] = [
		Vector3(-3.4, 0.0, -135.0),
		Vector3(-3.4, 0.0, -68.0),
		Vector3(-3.4, 0.0, -16.0),
		Vector3(-8.8, 0.0, -6.5),   # Roundabout west arc
		Vector3(-8.8, 0.0, 6.5),
		Vector3(-3.4, 0.0, 16.0),
		Vector3(-3.4, 0.0, 68.0),
		Vector3(-3.4, 0.0, 135.0),
		Vector3(3.4, 0.0, 135.0),   # South U-turn
		Vector3(3.4, 0.0, 68.0),
		Vector3(3.4, 0.0, 16.0),
		Vector3(8.8, 0.0, 6.5),     # Roundabout east arc
		Vector3(8.8, 0.0, -6.5),
		Vector3(3.4, 0.0, -16.0),
		Vector3(3.4, 0.0, -68.0),
		Vector3(3.4, 0.0, -135.0),
	]

	# Route 1: East-West Main Asphalt Avenue + Roundabout Ring (Right-hand traffic lanes z = ±3.4)
	var route_ew: Array[Vector3] = [
		Vector3(-135.0, 0.0, 3.4),
		Vector3(-68.0, 0.0, 3.4),
		Vector3(-16.0, 0.0, 3.4),
		Vector3(-6.5, 0.0, 8.8),    # Roundabout south arc
		Vector3(6.5, 0.0, 8.8),
		Vector3(16.0, 0.0, 3.4),
		Vector3(68.0, 0.0, 3.4),
		Vector3(135.0, 0.0, 3.4),
		Vector3(135.0, 0.0, -3.4),  # East U-turn
		Vector3(68.0, 0.0, -3.4),
		Vector3(16.0, 0.0, -3.4),
		Vector3(6.5, 0.0, -8.8),    # Roundabout north arc
		Vector3(-6.5, 0.0, -8.8),
		Vector3(-16.0, 0.0, -3.4),
		Vector3(-68.0, 0.0, -3.4),
		Vector3(-135.0, 0.0, -3.4),
	]

	# Route 2: Outer Dirt Side-Street Ring (x = ±64, z = ±64) with intersection turns
	var route_outer: Array[Vector3] = [
		Vector3(-64.0, 0.0, -64.0),
		Vector3(0.0, 0.0, -64.0),
		Vector3(64.0, 0.0, -64.0),
		Vector3(64.0, 0.0, 0.0),
		Vector3(64.0, 0.0, 64.0),
		Vector3(0.0, 0.0, 64.0),
		Vector3(-64.0, 0.0, 64.0),
		Vector3(-64.0, 0.0, 0.0),
	]

	# Route 3: Mixed Central Roundabout + Side Street Figure-8 Circuit
	var route_mixed: Array[Vector3] = [
		Vector3(3.4, 0.0, 62.0),
		Vector3(3.4, 0.0, 15.0),
		Vector3(9.2, 0.0, 4.5),     # Turn East at Roundabout
		Vector3(16.0, 0.0, 3.4),
		Vector3(62.0, 0.0, 3.4),
		Vector3(64.0, 0.0, -62.0),  # Turn North on East side street
		Vector3(3.4, 0.0, -64.0),   # Turn West on North side street
		Vector3(-3.4, 0.0, -16.0),  # Turn South onto main avenue
		Vector3(-9.2, 0.0, -4.5),   # Roundabout West arc
		Vector3(-16.0, 0.0, -3.4),  # Turn West onto main avenue
		Vector3(-62.0, 0.0, -3.4),
		Vector3(-64.0, 0.0, 62.0),  # Turn South on West side street
	]

	return [route_ns, route_ew, route_outer, route_mixed]


func _spawn_traffic_fleet() -> void:
	var routes := _build_lane_routes()
	# 12 AI Vehicles: 4 Amjad, 3 Boks, 3 Raksha, 2 Sedan
	var fleet_specs := [
		{"scene": SCENE_AMJAD, "route": 0, "wp": 0, "spd": 9.8, "drv": "dreiver"},
		{"scene": SCENE_BOKS,  "route": 0, "wp": 4, "spd": 10.5, "drv": "Man"},
		{"scene": SCENE_RAKSHA,"route": 0, "wp": 8, "spd": 8.2, "drv": "homeless"},
		{"scene": SCENE_AMJAD, "route": 0, "wp": 12,"spd": 9.5, "drv": "Oldman"},

		{"scene": SCENE_BOKS,  "route": 1, "wp": 0, "spd": 10.2, "drv": "ritchman"},
		{"scene": SCENE_SEDAN, "route": 1, "wp": 4, "spd": 11.0, "drv": "Man"},
		{"scene": SCENE_AMJAD, "route": 1, "wp": 8, "spd": 9.6, "drv": "dreiver"},
		{"scene": SCENE_RAKSHA,"route": 1, "wp": 12,"spd": 8.0, "drv": "Oldman"},

		{"scene": SCENE_BOKS,  "route": 2, "wp": 0, "spd": 8.8, "drv": "dreiver"},
		{"scene": SCENE_RAKSHA,"route": 2, "wp": 4, "spd": 7.8, "drv": "Man"},

		{"scene": SCENE_AMJAD, "route": 3, "wp": 0, "spd": 9.2, "drv": "ritchman"},
		{"scene": SCENE_SEDAN, "route": 3, "wp": 6, "spd": 10.4, "drv": "dreiver"},
	]

	for idx in range(fleet_specs.size()):
		var spec: Dictionary = fleet_specs[idx]
		var scene_path: String = spec["scene"]
		var packed := VEHICLE_SCENES.get(scene_path) as PackedScene
		if packed == null:
			continue
		var veh := packed.instantiate() as VehicleController
		if veh == null:
			continue

		veh.name = "AIVehicle_%d" % idx
		veh.add_to_group("ai_traffic_vehicles")
		veh.driver_peer_id = 0
		veh.ai_autopilot_active = true
		veh.set_physics_process(false)
		if spec["scene"] == SCENE_SEDAN:
			var sedan_models := [
				"res://assets/models/vehicles/pack/NormalCar1.fbx",
				"res://assets/models/vehicles/pack/NormalCar2.fbx",
				"res://assets/models/vehicles/pack/Taxi.fbx",
				"res://assets/models/vehicles/pack/SportsCar2.fbx",
			]
			var sedan_colors := [
				Color(0.56, 0.66, 0.76, 1.0),
				Color(0.95, 0.78, 0.14, 1.0),
				Color(0.92, 0.92, 0.90, 1.0),
				Color(0.64, 0.18, 0.18, 1.0),
			]
			var m_idx := idx % sedan_models.size()
			veh.pack_model_path = sedan_models[m_idx]
			veh.pack_paint_color = sedan_colors[m_idx]

		var r_idx: int = spec["route"]
		var wp_list: Array = routes[r_idx]
		var wp_i: int = int(spec["wp"]) % wp_list.size()
		var next_i: int = (wp_i + 1) % wp_list.size()
		var start_pos: Vector3 = wp_list[wp_i]
		var next_pos: Vector3 = wp_list[next_i]
		var dir := (next_pos - start_pos).normalized()

		veh.position = start_pos
		veh.rotation.y = atan2(-dir.x, -dir.z)
		add_child(veh)

		_setup_driver_and_steering_wheel(veh, String(spec["drv"]))
		var sensors := _setup_obstacle_sensors(veh)
		_optimize_ai_vehicle_lights(veh)

		ai_vehicles.append({
			"vehicle": veh,
			"waypoints": wp_list,
			"wp_index": next_i,
			"cruise_speed": float(spec["spd"]),
			"current_speed": float(spec["spd"]) * 0.75,
			"current_steer": 0.0,
			"ray": sensors["ray"],
			"area": sensors["area"],
			"horn_timer": randf_range(0.5, 2.5),
			"stuck_timer": 0.0,
			"braking": false,
		})


func _setup_driver_and_steering_wheel(veh: VehicleController, driver_kw: String) -> void:
	if veh.body_visuals == null:
		return

	# Semi-transparent cabin glass so the brightly lit 3D driver is clearly visible from outside
	for ch in veh.body_visuals.get_children():
		if ch is MeshInstance3D and ("Win" in ch.name or "Windshield" in ch.name):
			var mi := ch as MeshInstance3D
			var gmat := StandardMaterial3D.new()
			gmat.albedo_color = Color(0.36, 0.52, 0.62, 0.28)
			gmat.roughness = 0.15
			gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = gmat

	# Steering Wheel in front of driver seat (only if not already created by VehiclePackSetup)
	var seat_pos := veh.driver_seat_offset
	var seat_in_bv := Vector3(seat_pos.x, seat_pos.y - veh.body_visuals.position.y, seat_pos.z)
	if veh.body_visuals.find_child("SteeringWheel", true, false) == null:
		var wheel_node := MeshInstance3D.new()
		wheel_node.name = "SteeringWheel"
		var tm := TorusMesh.new()
		tm.inner_radius = 0.13
		tm.outer_radius = 0.165
		tm.rings = 12
		tm.ring_segments = 8
		wheel_node.mesh = tm
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.14, 0.14, 0.16, 1.0)
		wmat.roughness = 0.6
		wheel_node.material_override = wmat
		wheel_node.position = seat_in_bv + Vector3(0.0, 0.30, -0.36)
		wheel_node.rotation.x = deg_to_rad(62.0)
		veh.body_visuals.add_child(wheel_node)

	# Visible, brightly lit 3D Driver Character seated cleanly inside the cabin below the roof
	var drv_path := CharacterModelLoader.find_model_path(driver_kw)
	var seated_h := 1.48 if ("sedan" in veh.vehicle_name.to_lower() or "taxi" in veh.vehicle_name.to_lower() or "private" in veh.vehicle_name.to_lower()) else 1.56
	var drv_pivot := CharacterModelLoader.instantiate_normalized(drv_path, seated_h, true)
	if drv_pivot != null:
		drv_pivot.name = "DriverCharacter"
		drv_pivot.position = seat_in_bv + Vector3(0.0, -0.80, 0.0)
		veh.body_visuals.add_child(drv_pivot)
		if drv_pivot.has_meta("character_animator"):
			var anim := drv_pivot.get_meta("character_animator") as CharacterAnimator
			if anim != null:
				anim.update_animation(0.1, 0.0, true, true, false)
				drv_pivot.position = seat_in_bv + Vector3(0.0, -0.80, 0.0)


func _setup_obstacle_sensors(veh: VehicleController) -> Dictionary:
	var ray := RayCast3D.new()
	ray.name = "ForwardObstacleRay"
	ray.position = Vector3(0.0, 0.75, -1.8)
	ray.target_position = Vector3(0.0, 0.0, -12.0)
	ray.collision_mask = 7
	ray.enabled = true
	ray.exclude_parent = true
	veh.add_child(ray)

	var area := Area3D.new()
	area.name = "ForwardObstacleArea"
	area.collision_layer = 0
	area.collision_mask = 7
	area.monitoring = true
	area.monitorable = false
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 1.5, 7.2)
	col.shape = bs
	col.position = Vector3(0.0, 0.8, -5.2)
	area.add_child(col)
	veh.add_child(area)

	return {"ray": ray, "area": area}


func _optimize_ai_vehicle_lights(veh: VehicleController) -> void:
	for spot in veh._headlights:
		if spot != null:
			spot.shadow_enabled = false
			spot.distance_fade_enabled = true
			spot.distance_fade_begin = 28.0
			spot.distance_fade_length = 8.0


func _physics_process(delta: float) -> void:
	for entry in ai_vehicles:
		var veh := entry["vehicle"] as VehicleController
		if veh == null or not is_instance_valid(veh):
			continue

		# If the player entered this vehicle with [E], let PlayerController / VehicleController drive it!
		if veh.driver_peer_id > 0 or not veh.ai_autopilot_active:
			entry["stuck_timer"] = 0.0
			continue

		if float(entry["horn_timer"]) > 0.0:
			entry["horn_timer"] = float(entry["horn_timer"]) - delta

		var wp_list: Array = entry["waypoints"]
		var wp_idx: int = entry["wp_index"]
		var target: Vector3 = wp_list[wp_idx]
		var to_target := Vector3(target.x - veh.global_position.x, 0.0, target.z - veh.global_position.z)
		if to_target.length() < 3.6:
			wp_idx = (wp_idx + 1) % wp_list.size()
			entry["wp_index"] = wp_idx
			target = wp_list[wp_idx]
			to_target = Vector3(target.x - veh.global_position.x, 0.0, target.z - veh.global_position.z)

		var desired_dir := to_target.normalized()
		var desired_yaw := atan2(-desired_dir.x, -desired_dir.z)
		var yaw_diff := wrapf(desired_yaw - veh.rotation.y, -PI, PI)

		# Obstacle detection via 12.0m RayCast3D + Area3D + forward cone check
		var obstacle_detected := _check_forward_obstacles(veh, entry["ray"] as RayCast3D, entry["area"] as Area3D)
		entry["braking"] = obstacle_detected

		var cruise_spd: float = entry["cruise_speed"]
		var turn_slowdown := clampf(1.0 - absf(yaw_diff) * 0.45, 0.55, 1.0)
		var target_spd := 0.0 if obstacle_detected else (cruise_spd * turn_slowdown)
		var cur_spd: float = entry["current_speed"]

		if obstacle_detected:
			cur_spd = move_toward(cur_spd, 0.0, 16.0 * delta)
			if float(entry["horn_timer"]) <= 0.0:
				entry["horn_timer"] = randf_range(3.2, 6.0)
				if multiplayer.has_multiplayer_peer():
					veh.trigger_horn()
		else:
			cur_spd = move_toward(cur_spd, target_spd, 9.5 * delta)

		# Unstuck recovery timer: if speed stays near 0 for 3.5 seconds, nudge/reset onto road lane waypoint
		if cur_spd < 0.85:
			var st := float(entry["stuck_timer"]) + delta
			entry["stuck_timer"] = st
			if st >= 3.5:
				wp_idx = (wp_idx + 1) % wp_list.size()
				var next_idx := (wp_idx + 1) % wp_list.size()
				var reset_pos: Vector3 = wp_list[wp_idx]
				var next_pos: Vector3 = wp_list[next_idx]
				var ndir := (next_pos - reset_pos).normalized()
				veh.global_position = reset_pos
				veh.rotation.y = atan2(-ndir.x, -ndir.z)
				entry["wp_index"] = next_idx
				entry["stuck_timer"] = 0.0
				cur_spd = cruise_spd * 0.65
		else:
			entry["stuck_timer"] = 0.0

		entry["current_speed"] = cur_spd
		var cur_steer := clampf(yaw_diff * 1.4, -1.0, 1.0)
		entry["current_steer"] = lerpf(float(entry["current_steer"]), cur_steer, clampf(delta * 8.0, 0.0, 1.0))

		if cur_spd > 0.15:
			veh.rotation.y = lerp_angle(veh.rotation.y, desired_yaw, clampf(delta * 3.8, 0.0, 1.0))
			var fwd := -veh.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			veh.global_position += fwd * (cur_spd * delta)
			veh.global_position.y = 0.12

		veh._input_throttle = 0.0 if obstacle_detected else clampf(cur_spd / maxf(cruise_spd, 1.0), 0.0, 1.0)
		veh._animate_visuals(delta, cur_spd, float(entry["current_steer"]))
		veh._update_vfx(cur_spd, float(entry["current_steer"]), obstacle_detected)
		if multiplayer.has_multiplayer_peer():
			veh._update_engine_audio(cur_spd, float(entry["current_steer"]), obstacle_detected)


func _check_forward_obstacles(veh: VehicleController, ray: RayCast3D, area: Area3D) -> bool:
	if ray != null and ray.is_colliding():
		var col := ray.get_collider()
		if col != null and col != veh:
			if col is CharacterBody3D or col is RigidBody3D:
				return true

	if area != null and area.monitoring:
		for body in area.get_overlapping_bodies():
			if body != null and body != veh:
				if body is CharacterBody3D or body is RigidBody3D:
					return true

	# Direct forward cone distance check for players, pedestrians, and other vehicles
	var fwd := -veh.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var vpos := veh.global_position

	for grp in ["players", "npcs", "vehicles", "ai_traffic_vehicles"]:
		for node in get_tree().get_nodes_in_group(grp):
			if node == veh or not (node is Node3D):
				continue
			var npos := (node as Node3D).global_position
			var diff := Vector3(npos.x - vpos.x, 0.0, npos.z - vpos.z)
			var dist := diff.length()
			if dist > 0.5 and dist < 8.2:
				var forward_dot := fwd.dot(diff / dist)
				if forward_dot > 0.72:
					return true

	return false
