extends Node
class_name TimeOfDayController

## Cycles Khartoum Time-of-Day atmosphere (L key or HUD button):
## 0 = Golden Sunset (Maghrib), 1 = Morning Sun, 2 = Warm Streetlamp Night.

enum Period { SUNSET = 0, MORNING = 1, NIGHT = 2 }

const LABELS: Array[String] = ["Sunset", "Morning", "Night"]

@onready var world_env: WorldEnvironment = $"../WorldEnvironment"
@onready var sun_light: DirectionalLight3D = $"../DirectionalLight3D"
@onready var street_props: Node3D = $"../Neighborhood/StreetProps"

var _period: int = Period.SUNSET
var _lamp_lights: Array[OmniLight3D] = []


func _ready() -> void:
	add_to_group("time_controller")
	if OS.has_feature("web") and sun_light != null:
		sun_light.shadow_enabled = false
	_setup_streetlamp_lights()
	_apply_period(Period.SUNSET, false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_time_of_day"):
		for p in get_tree().get_nodes_in_group("local_player"):
			if p.has_method("get_current_vehicle") and p.get_current_vehicle() != null:
				return
		cycle_time_of_day()


func cycle_time_of_day() -> void:
	_period = (_period + 1) % 3
	_apply_period(_period, true)


func get_period_label() -> String:
	return LABELS[_period]


func _setup_streetlamp_lights() -> void:
	if street_props == null:
		return
	for lname in ["LampNW", "LampNE", "LampSW", "LampSE"]:
		var lamp := street_props.get_node_or_null(lname)
		if lamp:
			var light := OmniLight3D.new()
			light.name = "StreetGlow"
			light.position = Vector3(0.0, 2.1, 0.0)
			light.light_color = Color(1.0, 0.78, 0.42, 1.0)
			light.light_energy = 0.0
			light.omni_range = 24.0
			light.visible = false
			lamp.add_child(light)
			_lamp_lights.append(light)


func _apply_period(p: int, show_toast: bool) -> void:
	if world_env == null or world_env.environment == null or sun_light == null:
		return
	if OS.has_feature("web"):
		sun_light.shadow_enabled = false
	var env := world_env.environment
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial

	match p:
		Period.SUNSET:
			sun_light.rotation_degrees = Vector3(-20.0, -40.0, 0.0)
			sun_light.light_color = Color(1.0, 0.79, 0.54, 1.0)
			sun_light.light_energy = 1.35
			env.fog_light_color = Color(0.91, 0.68, 0.47, 1.0)
			env.fog_density = 0.0022
			env.ambient_light_sky_contribution = 0.78
			if sky_mat:
				sky_mat.sky_top_color = Color(0.24, 0.38, 0.62, 1.0)
				sky_mat.sky_horizon_color = Color(0.96, 0.66, 0.42, 1.0)
				sky_mat.ground_horizon_color = Color(0.88, 0.63, 0.43, 1.0)
			_set_lamps(true, 1.1)
		Period.MORNING:
			sun_light.rotation_degrees = Vector3(-52.0, -25.0, 0.0)
			sun_light.light_color = Color(1.0, 0.96, 0.88, 1.0)
			sun_light.light_energy = 1.65
			env.fog_light_color = Color(0.88, 0.85, 0.78, 1.0)
			env.fog_density = 0.0012
			env.ambient_light_sky_contribution = 0.85
			if sky_mat:
				sky_mat.sky_top_color = Color(0.22, 0.52, 0.85, 1.0)
				sky_mat.sky_horizon_color = Color(0.82, 0.88, 0.94, 1.0)
				sky_mat.ground_horizon_color = Color(0.85, 0.76, 0.64, 1.0)
			_set_lamps(false, 0.0)
		Period.NIGHT:
			sun_light.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
			sun_light.light_color = Color(0.55, 0.66, 0.90, 1.0)
			sun_light.light_energy = 0.28
			env.fog_light_color = Color(0.08, 0.10, 0.18, 1.0)
			env.fog_density = 0.0032
			env.ambient_light_sky_contribution = 0.45
			if sky_mat:
				sky_mat.sky_top_color = Color(0.03, 0.05, 0.12, 1.0)
				sky_mat.sky_horizon_color = Color(0.10, 0.13, 0.24, 1.0)
				sky_mat.ground_horizon_color = Color(0.09, 0.09, 0.13, 1.0)
			_set_lamps(true, 3.2)

	get_tree().call_group("network_hud", "sync_time_button", LABELS[p])
	if show_toast:
		get_tree().call_group("network_hud", "show_toast", "Time of Day: %s" % LABELS[p])


func _set_lamps(active: bool, energy: float) -> void:
	for light in _lamp_lights:
		light.visible = active
		light.light_energy = energy
