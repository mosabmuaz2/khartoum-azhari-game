extends RefCounted
class_name SmartWorldOrganizer

## Strict spatial validator & organized placement registry for Al-Azhari (Khartoum).
## Enforces:
## - Zero-obstruction inside building shells or on asphalt / dirt roads.
## - Minimum 3.5m clearance around every building entrance, courtyard gate, and shop doorway.
## - Curated conversational furniture groupings, Banshar workshop zone, Dukkan side props,
##   sidewalk/courtyard trees, and dirt-shoulder/lot-edge rocks.

const ENTRANCE_CLEARANCE_RADIUS: float = 3.5

# Non-enterable solid building wall footprints in world XZ (Rect2(min_x, min_z, size_x, size_z))
const BUILDING_SHELLS: Array[Rect2] = [
	Rect2(-38.0, -39.0, 20.0, 22.0),  # MosqueAzhari (-28, -28)
	Rect2(14.0, -24.0, 44.0, 11.2),   # CommercialStrip (36, -16.5)
	Rect2(-28.0, 13.0, 15.0, 22.0),   # ApartmentWest (-20, 24)
	Rect2(12.5, 31.0, 15.0, 22.0),    # ApartmentEast (20, 42)
	Rect2(-50.0, 16.0, 12.0, 8.0),    # HouseSW Diwan indoor slab
	Rect2(32.0, 16.0, 12.0, 8.0),     # HouseSE Diwan indoor slab
	Rect2(30.0, -38.0, 12.0, 8.0),    # HouseNorth Diwan indoor slab
]

# Every building doorway, courtyard gate, and shop front requiring >= 3.5m clearance
const ENTRANCES: Array[Vector3] = [
	Vector3(-28.0, 0.0, -16.5),  # Mosque porch
	Vector3(19.5, 0.0, -12.6),   # Dukkan entrance
	Vector3(26.5, 0.0, -12.6),   # Bakery entrance
	Vector3(33.5, 0.0, -12.6),   # Foul restaurant entrance
	Vector3(40.5, 0.0, -12.6),   # Pharmacy entrance
	Vector3(47.5, 0.0, -12.6),   # Barber entrance
	Vector3(54.5, 0.0, -12.6),   # Banshar entrance
	Vector3(-44.0, 0.0, 37.0),   # HouseSW courtyard gate
	Vector3(-44.0, 0.0, 24.5),   # HouseSW veranda doorway
	Vector3(38.0, 0.0, 37.0),    # HouseSE courtyard gate
	Vector3(38.0, 0.0, 24.5),    # HouseSE veranda doorway
	Vector3(36.0, 0.0, -51.0),   # HouseNorth courtyard gate
	Vector3(36.0, 0.0, -38.5),   # HouseNorth veranda doorway
	Vector3(-12.2, 0.0, 24.0),   # ApartmentWest entrance
	Vector3(12.2, 0.0, 42.0),    # ApartmentEast entrance
	Vector3(14.5, 0.0, -14.0),   # Kiosk_0 clearance
	Vector3(-15.5, 0.0, -16.5),  # Kiosk_1 clearance
	Vector3(76.5, 0.0, 14.2),    # Kiosk_2 clearance
	Vector3(86.0, 0.0, 15.5),    # Kiosk_3 clearance
	Vector3(-133.5, 0.0, -24.0), # Kiosk_4 clearance
	Vector3(-133.5, 0.0, 18.0),  # Kiosk_5 clearance
	Vector3(-74.0, 0.0, -14.2),  # Kiosk_6 clearance
	Vector3(-34.0, 0.0, 14.2),   # Kiosk_7 clearance
]

# Nile Bridges & Highway Overpasses XZ footprints (Rect2(min_x, min_z, size_x, size_z))
const BRIDGE_FOOTPRINTS: Array[Rect2] = [
	Rect2(-288.0, -7.0, 196.0, 14.0),   # GrandNileBridge (z = 0, x in [-288..-92])
	Rect2(-288.0, -367.0, 196.0, 14.0), # NorthernNileBridge (z = -360)
	Rect2(-288.0, 353.0, 196.0, 14.0),  # SouthernNileBridge (z = +360)
	Rect2(213.0, -267.0, 14.0, 134.0),  # Overpass_Engineering
	Rect2(393.0, -67.0, 14.0, 134.0),   # Overpass_CentralEast
	Rect2(153.0, -367.0, 134.0, 14.0),  # Overpass_NorthernSpine
	Rect2(-427.0, -267.0, 14.0, 134.0), # Overpass_WestVillas
]


static func is_in_bridge_exclusion(pos: Vector3, margin: float = 3.5) -> bool:
	var p2 := Vector2(pos.x, pos.z)
	for rect in BRIDGE_FOOTPRINTS:
		if rect.grow(margin).has_point(p2):
			return true
	return false


static func is_on_asphalt_road(pos: Vector3, margin: float = 0.8) -> bool:
	return absf(pos.x) < (9.2 + margin) or absf(pos.z) < (9.2 + margin)


static func is_on_dirt_road_center(pos: Vector3, margin: float = 2.0) -> bool:
	var on_ns := absf(absf(pos.x) - 64.0) < margin
	var on_ew := absf(absf(pos.z) - 64.0) < margin
	return on_ns or on_ew


static func is_near_entrance(pos: Vector3, extra_radius: float = 0.0) -> bool:
	var req := ENTRANCE_CLEARANCE_RADIUS + extra_radius
	var r2 := req * req
	for ent in ENTRANCES:
		var dx := pos.x - ent.x
		var dz := pos.z - ent.z
		if (dx * dx + dz * dz) < r2:
			return true
	return false


static func is_inside_building_shell(pos: Vector3, radius: float = 0.5) -> bool:
	for rect in BUILDING_SHELLS:
		var expanded := rect.grow(radius)
		if expanded.has_point(Vector2(pos.x, pos.z)):
			return true
	return false


static func is_spot_valid(pos: Vector3, obj_radius: float = 0.6, allow_courtyard_interior: bool = false) -> bool:
	if is_in_bridge_exclusion(pos, maxf(3.5, obj_radius + 3.0)):
		return false
	if is_on_asphalt_road(pos, obj_radius):
		return false
	if is_on_dirt_road_center(pos, 1.8 + obj_radius):
		return false
	if is_near_entrance(pos, obj_radius):
		return false
	if not allow_courtyard_interior and is_inside_building_shell(pos, obj_radius):
		return false
	return true


static func filter_valid_spots(candidates: Array[Vector3], obj_radius: float = 0.6) -> Array[Vector3]:
	var valid: Array[Vector3] = []
	for p in candidates:
		if is_spot_valid(p, obj_radius, false):
			valid.append(p)
	return valid


static func get_tree_spots() -> Array[Vector3]:
	# Sidewalk strips, mosque plaza flanks, squares, and open Hosh corners (all >=3.5m from gates)
	var raw: Array[Vector3] = [
		Vector3(-52.5, 0.0, 33.5),
		Vector3(-35.5, 0.0, 33.5),
		Vector3(30.5, 0.0, 33.5),
		Vector3(46.0, 0.0, 33.5),
		Vector3(28.5, 0.0, -47.5),
		Vector3(44.0, 0.0, -47.5),
		Vector3(-15.5, 0.0, -19.5),
		Vector3(-41.0, 0.0, -21.0),
		Vector3(-15.0, 0.0, -38.0),
		Vector3(11.8, 0.0, -13.0),
		Vector3(-13.5, 0.0, 13.0),
		Vector3(13.5, 0.0, 26.0),
		Vector3(74.0, 0.0, -18.5),
		Vector3(74.5, 0.0, 21.5),
	]
	return filter_valid_spots(raw, 0.7)


static func get_shrub_spots() -> Array[Vector3]:
	var raw: Array[Vector3] = [
		Vector3(-50.5, 0.0, 28.5),
		Vector3(-37.0, 0.0, 28.5),
		Vector3(32.5, 0.0, 28.5),
		Vector3(44.0, 0.0, 28.5),
		Vector3(-21.0, 0.0, -18.5),
		Vector3(-35.0, 0.0, -18.5),
		Vector3(59.0, 0.0, -16.0),
		Vector3(-58.5, 0.0, 16.0),
	]
	return filter_valid_spots(raw, 0.45)


static func get_rock_spots() -> Array[Vector3]:
	# Strictly along outer dirt shoulders & vacant lot / football pitch edges
	var raw: Array[Vector3] = [
		Vector3(-59.2, 0.0, -14.0),
		Vector3(-68.8, 0.0, 14.0),
		Vector3(59.5, 0.0, -12.0),
		Vector3(68.8, 0.0, 15.0),
		Vector3(-18.0, 0.0, -59.5),
		Vector3(24.0, 0.0, -68.8),
		Vector3(-22.0, 0.0, 59.5),
		Vector3(28.0, 0.0, 68.8),
		Vector3(-57.5, 0.0, 24.0),
		Vector3(-30.5, 0.0, 35.0),
		Vector3(25.0, 0.0, 24.5),
		Vector3(51.5, 0.0, 34.5),
		Vector3(22.5, 0.0, -34.0),
		Vector3(70.5, 0.0, 19.0),
		Vector3(86.0, 0.0, 20.5),
		Vector3(92.0, 0.0, 38.0),
		Vector3(69.5, 0.0, 44.0),
		Vector3(80.0, 0.0, 47.0),
	]
	return filter_valid_spots(raw, 0.5)


static func get_banshar_tool_spots() -> Array[Dictionary]:
	# Workshop flank beside بنشر ولحام لساتك & courtyard work corners (all >= 3.5m clear of doorways)
	return [
		{"pos": Vector3(58.6, 0.0, -10.6), "yaw": 0.4, "h": 0.45},
		{"pos": Vector3(59.6, 0.0, -11.6), "yaw": -0.6, "h": 0.36},
		{"pos": Vector3(58.8, 0.0, -11.2), "yaw": 1.1, "h": 0.55},
		{"pos": Vector3(59.2, 0.0, -12.2), "yaw": 0.2, "h": 0.40},
		{"pos": Vector3(-52.5, 0.0, 28.0), "yaw": 0.8, "h": 0.42},
		{"pos": Vector3(46.0, 0.0, 28.0), "yaw": -0.5, "h": 0.42},
	]


static func get_tea_stall_group_spots() -> Dictionary:
	# Organized conversational table + 4 flanking chairs around ست الشاي (centered around x=15.0, z=15.0)
	return {
		"tables": [Vector3(15.0, 0.0, 15.0)],
		"chairs": [
			{"pos": Vector3(14.0, 0.0, 15.0), "yaw": PI * 0.5},
			{"pos": Vector3(16.0, 0.0, 15.0), "yaw": -PI * 0.5},
			{"pos": Vector3(15.0, 0.0, 14.0), "yaw": 0.0},
			{"pos": Vector3(15.0, 0.0, 16.0), "yaw": PI},
		],
	}


static func get_dukkan_side_prop_spots() -> Array[Vector3]:
	# Vegetable crates & sacks aligned along east/west flanks of دكان الأزهري (door at 19.5, -12.6)
	return filter_valid_spots([
		Vector3(14.5, 0.0, -11.4),
		Vector3(15.4, 0.0, -11.4),
		Vector3(23.4, 0.0, -11.4),
	], 0.35)
