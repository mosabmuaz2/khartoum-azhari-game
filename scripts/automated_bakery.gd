extends Node3D
class_name AutomatedBakery

## Automated Khartoum Bakery Controller (مخبز آلي).
## Features glowing oven warmth, counter interaction (`[E]`), and grants a 45-second
## sprint speed boost (`+42%` horizontal travel speed while sprinting on foot)
## without modifying `scripts/player.gd`.

const INTERACT_RADIUS: float = 4.2
const BOOST_DURATION_SEC: float = 45.0
const SPRINT_THRESHOLD_SPEED: float = 6.2
const BOOST_EXTRA_FACTOR: float = 0.42

@export var bakery_title: String = "مخبز الأزهري الآلي"
@export var district_name: String = "حي الأزهري"

var _boost_active_players: Dictionary = {}
var _prev_interact_down: bool = false
var _oven_light: OmniLight3D = null
var _pulse_time: float = 0.0
var _counter_pos_local: Vector3 = Vector3(0.0, 0.0, 2.2)


func _ready() -> void:
	add_to_group("automated_bakeries")
	var sign_lbl := get_node_or_null("SignText") as Label3D
	if sign_lbl != null:
		sign_lbl.text = bakery_title
	var counter := get_node_or_null("BakeryCounter") as StaticBody3D
	if counter != null:
		counter.set_meta("interact_message", "%s (%s) — [E] شراء عيش بلدي سخن (+سرعة جري 45 ثانية)" % [bakery_title, district_name])
		_counter_pos_local = counter.position
	_oven_light = get_node_or_null("OvenGlowLight") as OmniLight3D


func _process(delta: float) -> void:
	_pulse_time += delta * 5.0
	if _oven_light != null:
		_oven_light.light_energy = 1.6 + 0.35 * sin(_pulse_time)

	# Handle `[E]` bakery interaction cleanly when local player stands near the counter
	var local_players := get_tree().get_nodes_in_group("local_player")
	if local_players.is_empty():
		return
	var p := local_players[0] as PlayerController
	if p == null or p.get_current_vehicle() != null:
		return

	var interact_now := Input.is_action_pressed("interact")
	if interact_now and not _prev_interact_down:
		var counter_world := to_global(_counter_pos_local)
		if p.global_position.distance_to(counter_world) <= INTERACT_RADIUS:
			trigger_bread_purchase(p)
	_prev_interact_down = interact_now


func _physics_process(delta: float) -> void:
	# Enforce 45-second sprint boost once across all bakeries using SceneTree metadata
	var tree := get_tree()
	if tree == null or not tree.has_meta("bread_sprint_boost_owner"):
		return
	if int(tree.get_meta("bread_sprint_boost_owner")) != get_instance_id():
		return
	var until_ms: int = int(tree.get_meta("bread_sprint_boost_until_ms", 0))
	if Time.get_ticks_msec() >= until_ms:
		tree.remove_meta("bread_sprint_boost_owner")
		tree.remove_meta("bread_sprint_boost_until_ms")
		get_tree().call_group("network_hud", "show_toast", "انتهى مفعول طاقة العيش السخن.")
		return

	var local_players := tree.get_nodes_in_group("local_player")
	if local_players.is_empty():
		return
	var p := local_players[0] as PlayerController
	if p == null or not is_instance_valid(p) or p.get_current_vehicle() != null:
		return
	var horiz := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if horiz.length() > SPRINT_THRESHOLD_SPEED and p.is_on_floor():
		p.move_and_collide(horiz * BOOST_EXTRA_FACTOR * delta)


func trigger_bread_purchase(p: PlayerController) -> void:
	var tree := get_tree()
	if tree == null or p == null:
		return
	tree.set_meta("bread_sprint_boost_owner", get_instance_id())
	tree.set_meta("bread_sprint_boost_until_ms", Time.get_ticks_msec() + int(BOOST_DURATION_SEC * 1000.0))
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr and audio_mgr.has_method("play_ui_chime"):
		audio_mgr.play_ui_chime()
	tree.call_group("network_hud", "show_toast", "🥖 اشتريت عيش سخن من %s! زيادة سرعة الجري 45 ثانية!" % bakery_title)
