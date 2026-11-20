extends Node3D
class_name GasStationController

## Interactive Gas Station Refueling Controller (`scripts/gas_station.gd`).
## Creates Area3D refueling zones (`radius = 5.0m`) around each fuel pump island.
## When the player drives or stands near a pump, shows `[E] تعبئة وقود السيارة`,
## and pressing `[E]` refills the active or nearest vehicle's fuel tank to 100%
## with pump sound effects and an on-screen confirmation toast.

const REFUEL_RADIUS: float = 5.0

var pump_areas: Array[Area3D] = []
var _pump_sfx: AudioStreamPlayer3D = null


func _ready() -> void:
	add_to_group("gas_stations")
	_setup_pump_areas()
	_setup_pump_audio()


func _exit_tree() -> void:
	if _pump_sfx != null:
		_pump_sfx.stop()
		_pump_sfx.stream = null


func _setup_pump_areas() -> void:
	var island_positions := [
		Vector3(-3.4, 1.0, 1.5),
		Vector3(3.4, 1.0, 1.5),
	]
	for idx in range(island_positions.size()):
		var area := Area3D.new()
		area.name = "RefuelZone_%d" % idx
		area.position = island_positions[idx]
		area.collision_layer = 0
		area.collision_mask = 7
		area.monitoring = true
		area.monitorable = true
		area.add_to_group("gas_pump_areas")

		var col := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = REFUEL_RADIUS
		col.shape = sph
		area.add_child(col)
		add_child(area)
		pump_areas.append(area)


func _setup_pump_audio() -> void:
	_pump_sfx = AudioStreamPlayer3D.new()
	_pump_sfx.name = "PumpSFXPlayer"
	_pump_sfx.position = Vector3(0.0, 1.4, 1.5)
	_pump_sfx.max_distance = 28.0
	_pump_sfx.unit_size = 3.5
	_pump_sfx.volume_db = -3.0
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr and audio_mgr.water_basin_stream:
		_pump_sfx.stream = audio_mgr.water_basin_stream
	add_child(_pump_sfx)


func is_position_in_pump_zone(world_pos: Vector3) -> bool:
	for area in pump_areas:
		if area != null and is_instance_valid(area):
			var d := Vector2(world_pos.x - area.global_position.x, world_pos.z - area.global_position.z).length()
			if d <= REFUEL_RADIUS:
				return true
	return false


static func find_station_for_position(tree: SceneTree, world_pos: Vector3) -> GasStationController:
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("gas_stations"):
		var gs := node as GasStationController
		if gs != null and gs.is_position_in_pump_zone(world_pos):
			return gs
	return null


func refuel_active_or_nearest_vehicle(player: Node3D) -> String:
	var target_veh: VehicleController = null
	if player is PlayerController:
		target_veh = (player as PlayerController).get_current_vehicle()

	if target_veh == null:
		var best_d := 14.0
		var search_origin := player.global_position if player != null else global_position
		for node in get_tree().get_nodes_in_group("vehicles"):
			var v := node as VehicleController
			if v != null:
				var d := search_origin.distance_to(v.global_position)
				if d <= best_d:
					best_d = d
					target_veh = v

	if _pump_sfx and _pump_sfx.stream and DisplayServer.get_name() != "headless":
		_pump_sfx.pitch_scale = 1.15
		_pump_sfx.play()
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if is_instance_valid(_pump_sfx):
				_pump_sfx.stop()
		)

	if target_veh != null:
		target_veh.fuel_liters = target_veh.max_fuel_liters
		var msg := "⛽ تم تعبئة وقود السيارة (%s) ١٠٠٪ (%.0f / %.0f لتر)" % [target_veh.vehicle_name, target_veh.fuel_liters, target_veh.max_fuel_liters]
		get_tree().call_group("network_hud", "show_toast", msg)
		return msg

	var generic_msg := "⛽ تم تعبئة وقود السيارة ١٠٠٪ بنجاح!"
	get_tree().call_group("network_hud", "show_toast", generic_msg)
	return generic_msg
