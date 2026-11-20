extends Node3D
class_name BusSystem

## Manages Large Sudanese City Buses (`بصات الوالي - الأزهري / السوق العربي`) and the 3 Bus Stations (`مواقف بصات`).
## - AI-driven buses automatically loop along the main avenues, stopping for 12.0 seconds at each bus station
##   with passenger doors open while waiting NPCs board and exit.
## - Player can either:
##   * Press `[E]` (`ركوب البص كراكب - Einsteigen`) to ride inside the bus as a passenger while AI drives the route.
##   * Press `[G]` (`قيادة البص - Bus fahren`) to take the steering wheel and drive the bus directly.

const BUS_SCENE_PATH: String = "res://scenes/vehicles/sudanese_bus.tscn"
const BUS_SCENE: PackedScene = preload("res://scenes/vehicles/sudanese_bus.tscn")
const STATION_DWELL_SEC: float = 12.0

var buses: Array[Dictionary] = []

# Route waypoints keeping buses strictly on main asphalt lanes (|x| <= 5.5 or |z| <= 5.5 + roundabout ring)
const BUS_ROUTE: Array[Dictionary] = [
	{"pos": Vector3(-5.2, 0.0, -26.0),  "is_station": true,  "name": "موقف بصات المسجد والسنتر"},
	{"pos": Vector3(-5.2, 0.0, -12.0),  "is_station": false, "name": ""},
	{"pos": Vector3(-8.8, 0.0, 4.5),    "is_station": false, "name": ""},
	{"pos": Vector3(16.0, 0.0, 5.2),    "is_station": false, "name": ""},
	{"pos": Vector3(64.0, 0.0, 5.2),    "is_station": true,  "name": "موقف بصات السوق الشرقي والعماري"},
	{"pos": Vector3(115.0, 0.0, 5.2),   "is_station": false, "name": ""},
	{"pos": Vector3(115.0, 0.0, -5.2),  "is_station": false, "name": ""},
	{"pos": Vector3(50.0, 0.0, -5.2),   "is_station": false, "name": ""},
	{"pos": Vector3(8.5, 0.0, -8.8),    "is_station": false, "name": ""},
	{"pos": Vector3(-16.0, 0.0, -5.2),  "is_station": false, "name": ""},
	{"pos": Vector3(-118.0, 0.0, -5.2), "is_station": true,  "name": "موقف بصات كورنيش النيل"},
	{"pos": Vector3(-121.0, 0.0, 5.2),  "is_station": false, "name": ""},
	{"pos": Vector3(-25.0, 0.0, 5.2),   "is_station": false, "name": ""},
	{"pos": Vector3(-6.5, 0.0, 8.8),    "is_station": false, "name": ""},
	{"pos": Vector3(8.8, 0.0, 4.5),     "is_station": false, "name": ""},
	{"pos": Vector3(5.2, 0.0, -16.0),   "is_station": false, "name": ""},
	{"pos": Vector3(5.2, 0.0, -95.0),   "is_station": false, "name": ""},
	{"pos": Vector3(-5.2, 0.0, -95.0),  "is_station": false, "name": ""},
]


func _ready() -> void:
	add_to_group("bus_system")
	if OS.has_feature("web"):
		call_deferred("_spawn_buses_web")
		return
	_spawn_buses()


func _spawn_buses_web() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var packed := BUS_SCENE
	if packed == null:
		return
	var bus := packed.instantiate() as VehicleController
	if bus == null:
		return
	bus.name = "SudaneseBus_0"
	bus.add_to_group("sudanese_buses")
	bus.bus_ai_active = true
	bus.set_physics_process(false)
	var p0: Vector3 = BUS_ROUTE[0]["pos"]
	var p1: Vector3 = BUS_ROUTE[1]["pos"]
	var dir := (p1 - p0).normalized()
	bus.position = p0
	bus.rotation.y = atan2(-dir.x, -dir.z)
	add_child(bus)
	buses.append({
		"bus": bus,
		"wp_index": 1,
		"dwell_timer": STATION_DWELL_SEC,
		"current_speed": 0.0,
		"current_steer": 0.0,
		"doors_open": true,
		"station_name": String(BUS_ROUTE[0]["name"]),
	})


func get_bus_count() -> int:
	return buses.size()


func _spawn_buses() -> void:
	var packed := BUS_SCENE
	if packed == null:
		return

	var start_waypoints := [0, 4]
	for idx in range(start_waypoints.size()):
		var bus := packed.instantiate() as VehicleController
		if bus == null:
			continue
		bus.name = "SudaneseBus_%d" % idx
		bus.add_to_group("sudanese_buses")
		bus.bus_ai_active = true
		bus.set_physics_process(false)

		var wp_i: int = start_waypoints[idx]
		var next_i: int = (wp_i + 1) % BUS_ROUTE.size()
		var p0: Vector3 = BUS_ROUTE[wp_i]["pos"]
		var p1: Vector3 = BUS_ROUTE[next_i]["pos"]
		var dir := (p1 - p0).normalized()

		bus.position = p0
		bus.rotation.y = atan2(-dir.x, -dir.z)
		add_child(bus)

		_populate_bus_interior(bus, idx)

		buses.append({
			"bus": bus,
			"wp_index": next_i,
			"dwell_timer": STATION_DWELL_SEC if idx == 0 else 0.0,
			"current_speed": 0.0 if idx == 0 else 7.5,
			"current_steer": 0.0,
			"doors_open": idx == 0,
			"station_name": String(BUS_ROUTE[wp_i]["name"]),
		})


func _populate_bus_interior(bus: VehicleController, idx: int) -> void:
	if bus.body_visuals == null:
		return
	var drv_path := CharacterModelLoader.find_model_path("dreiver")
	var drv := CharacterModelLoader.instantiate_normalized(drv_path, 1.64, true)
	var seat_in_bv := Vector3(bus.driver_seat_offset.x, bus.driver_seat_offset.y - bus.body_visuals.position.y - 0.80, bus.driver_seat_offset.z)
	if drv != null:
		drv.name = "BusDriverNPC"
		drv.position = seat_in_bv
		bus.body_visuals.add_child(drv)
		if drv.has_meta("character_animator"):
			var anim := drv.get_meta("character_animator") as CharacterAnimator
			if anim:
				anim.update_animation(0.1, 0.0, true, true, false)
				drv.position = seat_in_bv

	var pass_keywords := ["Oldman", "mama", "ritchman"]
	var pass_y := bus.passenger_seat_offset.y - bus.body_visuals.position.y - 0.80
	var seat_offsets := [
		Vector3(-0.72, pass_y, -2.10),
		Vector3(0.72, pass_y, -0.80),
		Vector3(-0.72, pass_y, 0.50),
	]
	for pi in range(seat_offsets.size()):
		var kw: String = pass_keywords[(pi + idx) % pass_keywords.size()]
		var ppath := CharacterModelLoader.find_model_path(kw)
		var pnode := CharacterModelLoader.instantiate_normalized(ppath, 1.62, true)
		if pnode != null:
			pnode.name = "BusPassengerNPC_%d" % pi
			pnode.position = seat_offsets[pi]
			bus.body_visuals.add_child(pnode)
			if pnode.has_meta("character_animator"):
				var panim := pnode.get_meta("character_animator") as CharacterAnimator
				if panim:
					panim.update_animation(0.1, 0.0, true, false, false)
					pnode.position = seat_offsets[pi]


func find_nearby_bus(world_pos: Vector3, max_dist: float = 5.6) -> VehicleController:
	var best: VehicleController = null
	var best_d := max_dist
	for entry in buses:
		var bus := entry["bus"] as VehicleController
		if bus == null or not is_instance_valid(bus):
			continue
		var d := world_pos.distance_to(bus.global_position)
		if d <= best_d:
			best_d = d
			best = bus
	return best


func is_bus_stopped_at_station(bus: VehicleController) -> bool:
	for entry in buses:
		if entry["bus"] == bus:
			return float(entry["dwell_timer"]) > 0.0 or float(entry["current_speed"]) < 1.2
	return false


func take_over_bus_driving(bus: VehicleController, peer_id: int) -> void:
	for entry in buses:
		if entry["bus"] == bus:
			bus.bus_ai_active = false
			bus.passenger_peer_id = 0
			bus.set_physics_process(true)
			var drv := bus.body_visuals.get_node_or_null("BusDriverNPC") as Node3D
			if drv:
				drv.visible = false
				drv.process_mode = Node.PROCESS_MODE_DISABLED
			bus.request_enter(peer_id)
			return


func resume_ai_if_unoccupied(bus: VehicleController) -> void:
	for entry in buses:
		if entry["bus"] == bus and bus.driver_peer_id == 0:
			bus.bus_ai_active = true
			bus.set_physics_process(false)
			var drv := bus.body_visuals.get_node_or_null("BusDriverNPC") as Node3D
			if drv:
				drv.process_mode = Node.PROCESS_MODE_INHERIT
				drv.visible = true


func _physics_process(delta: float) -> void:
	for entry in buses:
		var bus := entry["bus"] as VehicleController
		if bus == null or not is_instance_valid(bus):
			continue
		if not bus.bus_ai_active:
			if bus.driver_peer_id == 0:
				resume_ai_if_unoccupied(bus)
			continue

		var dwell: float = entry["dwell_timer"]
		_animate_bus_doors(bus, dwell > 0.0, delta)

		if dwell > 0.0:
			dwell -= delta
			entry["dwell_timer"] = maxf(0.0, dwell)
			entry["current_speed"] = move_toward(float(entry["current_speed"]), 0.0, 14.0 * delta)
			bus._animate_visuals(delta, float(entry["current_speed"]), 0.0)
			bus._update_vfx(0.0, 0.0, true)
			continue

		var wp_idx: int = entry["wp_index"]
		var wp_info: Dictionary = BUS_ROUTE[wp_idx]
		var target: Vector3 = wp_info["pos"]
		var to_target := Vector3(target.x - bus.global_position.x, 0.0, target.z - bus.global_position.z)

		if to_target.length() < 3.8:
			var is_st: bool = wp_info["is_station"]
			wp_idx = (wp_idx + 1) % BUS_ROUTE.size()
			entry["wp_index"] = wp_idx
			if is_st:
				entry["dwell_timer"] = STATION_DWELL_SEC
				entry["station_name"] = String(wp_info["name"])
				if bus.passenger_peer_id > 0:
					get_tree().call_group("network_hud", "show_toast", "🚌 وصل البص: %s ([E] للنزول)" % String(wp_info["name"]))
				continue
			target = BUS_ROUTE[wp_idx]["pos"]
			to_target = Vector3(target.x - bus.global_position.x, 0.0, target.z - bus.global_position.z)

		var desired_dir := to_target.normalized()
		for k in get_tree().get_nodes_in_group("kiosks"):
			var kn := k as Node3D
			if kn == null:
				continue
			var off := Vector3(bus.global_position.x - kn.global_position.x, 0.0, bus.global_position.z - kn.global_position.z)
			if off.length_squared() > 0.001 and off.length_squared() < (5.5 * 5.5):
				desired_dir = (desired_dir + off.normalized() * 1.4).normalized()
		var desired_yaw := atan2(-desired_dir.x, -desired_dir.z)
		var yaw_diff := wrapf(desired_yaw - bus.rotation.y, -PI, PI)

		var cur_spd: float = move_toward(float(entry["current_speed"]), 8.8, 6.5 * delta)
		entry["current_speed"] = cur_spd
		var cur_steer := clampf(yaw_diff * 1.2, -1.0, 1.0)
		entry["current_steer"] = lerpf(float(entry["current_steer"]), cur_steer, clampf(delta * 6.0, 0.0, 1.0))

		bus.rotation.y = lerp_angle(bus.rotation.y, desired_yaw, clampf(delta * 3.0, 0.0, 1.0))
		var fwd := -bus.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		bus.global_position += fwd * (cur_spd * delta)
		bus.global_position.y = 0.12

		bus._animate_visuals(delta, cur_spd, float(entry["current_steer"]))
		bus._update_vfx(cur_spd, float(entry["current_steer"]), false)


func _animate_bus_doors(bus: VehicleController, open_doors: bool, delta: float) -> void:
	if bus.body_visuals == null:
		return
	var df := bus.body_visuals.get_node_or_null("BusDoorFront") as Node3D
	var dr := bus.body_visuals.get_node_or_null("BusDoorRear") as Node3D
	var target_z_front := -2.35 if open_doors else -3.1
	var target_z_rear := 2.55 if open_doors else 1.8
	if df:
		df.position.z = lerpf(df.position.z, target_z_front, clampf(delta * 5.0, 0.0, 1.0))
	if dr:
		dr.position.z = lerpf(dr.position.z, target_z_rear, clampf(delta * 5.0, 0.0, 1.0))
