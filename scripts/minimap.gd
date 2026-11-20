extends Control
class_name NeighborhoodMinimap

## 2D Top-Down Minimap in the HUD corner showing the Nile River (نهر النيل) on the western edge,
## main asphalt avenues, grid side streets, Mosque, Market, Amary/Sa'ud Shop, Gas Station,
## Bus Stations, Tea Corner, Football Pitch, vehicles, NPCs, and live player direction.

const WORLD_RANGE: float = 320.0

var _refresh_timer: float = 0.0
var _cached_landmarks: Array[Dictionary] = []
var _landmarks_loaded: bool = false


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer += delta
	if _refresh_timer >= 0.05:
		_refresh_timer = 0.0
		queue_redraw()


func _draw() -> void:
	var half := size * 0.5
	var radius := minf(size.x, size.y) * 0.48
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.07, 0.06, 0.82), true)

	var local_players := get_tree().get_nodes_in_group("local_player")
	var player_pos := Vector3.ZERO
	var player_yaw := 0.0
	if not local_players.is_empty():
		var p := local_players[0] as PlayerController
		if p:
			player_pos = p.global_position
			player_yaw = p.visuals.global_rotation.y

	var to_map := func(wx: float, wz: float) -> Vector2:
		var rel_x := (wx - player_pos.x) / WORLD_RANGE
		var rel_z := (wz - player_pos.z) / WORLD_RANGE
		var pt := half + Vector2(rel_x, rel_z) * radius
		return Vector2(clampf(pt.x, 4.0, size.x - 4.0), clampf(pt.y, 4.0, size.y - 4.0))

	# Great Nile River along western bank boundary (x in [-235 .. -143])
	var nile_left: Vector2 = to_map.call(-235.0, 0.0)
	var nile_right: Vector2 = to_map.call(-143.0, 0.0)
	if nile_right.x > 4.5 and nile_left.x < size.x - 4.5:
		var band_x0 := clampf(nile_left.x, 2.0, size.x - 4.0)
		var band_x1 := clampf(nile_right.x, 2.0, size.x - 4.0)
		var w_band := maxf(8.0, band_x1 - band_x0)
		draw_rect(Rect2(Vector2(band_x0, 2.0), Vector2(w_band, size.y - 4.0)), Color(0.12, 0.54, 0.78, 0.88), true)
		draw_line(Vector2(band_x1, 2.0), Vector2(band_x1, size.y - 2.0), Color(0.90, 0.82, 0.65, 0.9), 2.0)
		draw_line(Vector2(band_x0, 2.0), Vector2(band_x0, size.y - 2.0), Color(0.90, 0.82, 0.65, 0.9), 2.0)

	# Expanded City Arterial Avenues across East & West Banks
	for ax in [-560.0, -420.0, -268.0, -112.0, 0.0, 220.0, 400.0, 560.0]:
		var px: float = half.x + ((ax - player_pos.x) / WORLD_RANGE) * radius
		if px > 4.0 and px < size.x - 4.0:
			var w_px := 4.5 if absf(ax) < 1.0 else 3.0
			draw_line(Vector2(px, 4.0), Vector2(px, size.y - 4.0), Color(0.30, 0.30, 0.32, 0.85), w_px)
	for az in [-560.0, -360.0, -200.0, 0.0, 200.0, 360.0, 560.0]:
		var pz: float = half.y + ((az - player_pos.z) / WORLD_RANGE) * radius
		if pz > 4.0 and pz < size.y - 4.0:
			var w_pz := 4.5 if (absf(az) < 1.0 or absf(absf(az) - 360.0) < 1.0) else 3.0
			draw_line(Vector2(4.0, pz), Vector2(size.x - 4.0, pz), Color(0.30, 0.30, 0.32, 0.85), w_pz)

	# Core Intersection Roundabout
	var c0: Vector2 = to_map.call(0.0, 0.0)
	draw_circle(c0, 5.5, Color(0.36, 0.36, 0.38, 0.95))

	# Dynamic Expanded Landmarks (Mosques M, Bakeries B, Health H, Police P, Engineering E, Docks D, Stadium S, Bridges BR)
	if not _landmarks_loaded:
		var builders := get_tree().get_nodes_in_group("city_mega_builder")
		if not builders.is_empty() and builders[0].has_method("get_minimap_landmarks"):
			_cached_landmarks = builders[0].get_minimap_landmarks()
			_landmarks_loaded = true
	for lm in _cached_landmarks:
		var lpos: Vector3 = lm.get("pos", Vector3.ZERO)
		if absf(lpos.x - player_pos.x) < WORLD_RANGE * 1.1 and absf(lpos.z - player_pos.z) < WORLD_RANGE * 1.1:
			_draw_landmark(to_map.call(lpos.x, lpos.z), lm.get("color", Color.WHITE), str(lm.get("tag", "?")))

	# Core Landmarks: Mosque (M), Market (S), Gas Station (G), Amary Shop (A), Fish Market (F), Tea Corner (T), Dafouri Pitch (P)
	_draw_landmark(to_map.call(-28.0, -28.0), Color(0.20, 0.78, 0.42), "M")
	_draw_landmark(to_map.call(36.0, -16.5), Color(0.94, 0.66, 0.24), "S")
	_draw_landmark(to_map.call(52.0, 18.0), Color(0.92, 0.24, 0.22), "G")
	_draw_landmark(to_map.call(28.0, 14.5), Color(0.88, 0.74, 0.22), "A")
	_draw_landmark(to_map.call(88.0, -28.0), Color(0.28, 0.76, 0.92), "F")
	_draw_landmark(to_map.call(16.6, 16.6), Color(0.92, 0.42, 0.24), "T")
	_draw_landmark(to_map.call(92.0, 34.0), Color(0.62, 0.86, 0.34), "P")

	# Vehicles (yellow squares)
	for node in get_tree().get_nodes_in_group("vehicles"):
		var veh := node as Node3D
		if veh:
			var vp: Vector2 = to_map.call(veh.global_position.x, veh.global_position.z)
			draw_rect(Rect2(vp - Vector2(2.5, 2.5), Vector2(5, 5)), Color(1.0, 0.86, 0.24, 0.95), true)

	# NPCs (cyan dots, bright green if following)
	for node in get_tree().get_nodes_in_group("npcs"):
		var npc := node as NPCInteractive
		if npc:
			var np: Vector2 = to_map.call(npc.global_position.x, npc.global_position.z)
			var col := Color(0.35, 1.0, 0.55, 0.95) if npc.following_peer_id > 0 else Color(0.55, 0.82, 0.96, 0.72)
			draw_circle(np, 2.0, col)

	# Active Mission Waypoint Beacon (pulsing target ring + guide line)
	var mm := get_node_or_null("/root/MissionManager")
	if mm and mm.has_method("get_active_waypoint"):
		var wp: Dictionary = mm.get_active_waypoint()
		if not wp.is_empty():
			var wpos: Vector3 = wp.get("position", Vector3.ZERO)
			var wcol: Color = wp.get("color", Color(1.0, 0.85, 0.22))
			var mp: Vector2 = to_map.call(wpos.x, wpos.z)
			var pulse := 1.0 + 0.28 * sin(float(Time.get_ticks_msec()) * 0.008)
			draw_line(half, mp, Color(wcol.r, wcol.g, wcol.b, 0.55), 1.8)
			draw_arc(mp, 9.0 * pulse, 0.0, TAU, 24, wcol, 2.2)
			draw_circle(mp, 5.2, wcol)
			var font_m := ThemeDB.fallback_font
			if font_m:
				draw_string(font_m, mp + Vector2(-3.5, 3.8), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.05, 0.05, 0.05, 1.0))

	# Outer border frame
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.92, 0.65, 0.36, 0.72), false, 2.0)

	# Local Player Arrow at center
	var dir_2d := Vector2(-sin(player_yaw), -cos(player_yaw)).normalized()
	var perp := Vector2(-dir_2d.y, dir_2d.x)
	var tip := half + dir_2d * 7.5
	var left_pt := half - dir_2d * 5.0 + perp * 4.5
	var right_pt := half - dir_2d * 5.0 - perp * 4.5
	draw_colored_polygon(PackedVector2Array([tip, left_pt, right_pt]), Color(1.0, 0.94, 0.65, 1.0))


func _draw_landmark(pt: Vector2, col: Color, tag: String) -> void:
	draw_circle(pt, 5.2, col)
	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, pt + Vector2(-3.5, 3.5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.05, 0.05, 0.05, 1.0))
