extends Node3D
class_name InteractiveDoor

## Performance-Optimized Authentic Sudanese Interactive Door, Courtyard Gate & Shop Shutter Controller.
## - Preserves full multi-part 3D Sudanese architectural detail (steel frames, crossbars, corrugated sheets,
##   spear-tip ironwork, recessed wooden frames, raised panels, lever handles, hinge barrels, sliding bolts,
##   and slatted shop shutters) while merging static geometry into 1–2 multi-surface ArrayMeshes per element
##   (cutting draw calls & MeshInstance3D nodes by >90%).
## - Disables shadow casting on small hardware (hinge barrels, handles, bolts, spear-tips, pickets, clasps).
## - Sleeps idle door physics (`sync_to_physics = false` & `set_physics_process(false)` when stationary),
##   activating `sync_to_physics = true` ONLY during active open/close/lock/rattle motion.
## - Distance culling (`vis_range_end = 95.0` main, `60.0` hardware).

enum DoorStyle {
	COURTYARD_DOUBLE_GATE = 0,
	COURTYARD_SINGLE_GATE = 1,
	WOOD_SINGLE_DOOR = 2,
	WOOD_DOUBLE_DOOR = 3,
	SHOP_ROLLUP_SHUTTER = 4,
}

enum GatePaintPreset {
	AUTO = 0,
	FOREST_GREEN = 1,
	DARK_NAVY = 2,
	OXIDE_RUST = 3,
	DESERT_GREY = 4,
}

const GATE_PALETTE: Array[Color] = [
	Color(0.11, 0.29, 0.19, 1.0), # Deep Sudanese Forest Green
	Color(0.12, 0.20, 0.34, 1.0), # Dark Navy Blue
	Color(0.42, 0.19, 0.12, 1.0), # Oxide Rust-Brown
	Color(0.56, 0.54, 0.48, 1.0), # Desert Grey / Warm Cream
]

const TEX_CORR_ALB: String = "res://assets/textures/corrugated/albedo.jpg"
const TEX_CORR_NOR: String = "res://assets/textures/corrugated/normal.jpg"
const TEX_CORR_RGH: String = "res://assets/textures/corrugated/roughness.jpg"
const TEX_WOOD_ALB: String = "res://assets/textures/painted_wood/albedo.jpg"
const TEX_WOOD_NOR: String = "res://assets/textures/painted_wood/normal.jpg"
const TEX_WOOD_RGH: String = "res://assets/textures/painted_wood/roughness.jpg"
const TEX_PLAS_ALB: String = "res://assets/textures/plaster/albedo.jpg"

@export var door_label: String = "باب"
@export var door_style: DoorStyle = DoorStyle.WOOD_SINGLE_DOOR
@export var gate_paint: GatePaintPreset = GatePaintPreset.AUTO
@export var opening_width: float = 1.32
@export var opening_height: float = 2.27
@export var wall_thickness: float = 0.35
@export var is_shutter: bool = false
@export_range(85.0, 88.0, 0.5) var open_angle_deg: float = 86.0
@export var slide_height: float = 2.25
@export var is_open: bool = false
@export var is_locked: bool = false
@export var has_lintel_beam: bool = false
@export var has_pillars: bool = false
@export var build_recessed_frame: bool = true
@export var vis_range_end: float = 95.0

var hinge_left: Node3D = null
var hinge_right: Node3D = null
var leaf_body_left: AnimatableBody3D = null
var leaf_body_right: AnimatableBody3D = null
var shutter_body: AnimatableBody3D = null
var _bolt_visuals: Array[Node3D] = []
var _bolt_base_positions: Array[Vector3] = []
var _bolt_lock_deltas: Array[Vector3] = []
var _clasp_visuals: Array[Node3D] = []

var _current_angle_rad: float = 0.0
var _current_shutter_y: float = 0.0
var _bolt_progress: float = 0.0
var _rattle_timer: float = 0.0
var _rattle_elapsed: float = 0.0
var _built: bool = false

static var _shared_mats: Dictionary = {}
static var _merged_mesh_cache: Dictionary = {}


func _ready() -> void:
	add_to_group("interactive_doors")
	if is_shutter:
		door_style = DoorStyle.SHOP_ROLLUP_SHUTTER
	open_angle_deg = clampf(absf(open_angle_deg), 85.0, 88.0)
	if is_locked:
		is_open = false

	_build_sudanese_door_geometry()

	_current_angle_rad = deg_to_rad(open_angle_deg) if (is_open and not is_locked) else 0.0
	_current_shutter_y = _get_shutter_open_y() if (is_open and not is_locked) else _get_shutter_closed_y()
	_bolt_progress = 1.0 if is_locked else 0.0
	_apply_kinematic_poses(0.0)
	# Sleep idle door physics immediately (zero CPU/physics cost until player interacts!)
	_set_physics_active(false)


func _set_physics_active(active: bool) -> void:
	set_physics_process(active)
	if leaf_body_left != null:
		leaf_body_left.sync_to_physics = active
	if leaf_body_right != null:
		leaf_body_right.sync_to_physics = active
	if shutter_body != null:
		shutter_body.sync_to_physics = active


func _physics_process(delta: float) -> void:
	if not _built:
		_set_physics_active(false)
		return

	var rattle_offset_rad := 0.0
	var rattle_offset_y := 0.0
	if _rattle_timer > 0.0:
		_rattle_timer = maxf(0.0, _rattle_timer - delta)
		_rattle_elapsed += delta
		var decay := exp(-_rattle_elapsed * 6.2)
		var wave := sin(_rattle_elapsed * 54.0) * decay
		rattle_offset_rad = deg_to_rad(2.6) * wave
		rattle_offset_y = 0.022 * wave

	var target_bolt := 1.0 if is_locked else 0.0
	_bolt_progress = move_toward(_bolt_progress, target_bolt, delta * 5.5)
	var bolt_done := is_equal_approx(_bolt_progress, target_bolt)

	var motion_done := false
	if door_style == DoorStyle.SHOP_ROLLUP_SHUTTER:
		var target_y := _get_shutter_open_y() if (is_open and not is_locked) else _get_shutter_closed_y()
		_current_shutter_y = lerpf(_current_shutter_y, target_y, clampf(delta * 6.5, 0.0, 1.0))
		if absf(_current_shutter_y - target_y) < 0.002:
			_current_shutter_y = target_y
			motion_done = true
		_apply_kinematic_poses(rattle_offset_y)
	else:
		var target_rad := deg_to_rad(open_angle_deg) if (is_open and not is_locked) else 0.0
		_current_angle_rad = lerpf(_current_angle_rad, target_rad, clampf(delta * 7.2, 0.0, 1.0))
		if absf(_current_angle_rad - target_rad) < 0.0015:
			_current_angle_rad = target_rad
			motion_done = true
		_apply_kinematic_poses(rattle_offset_rad)

	if motion_done and bolt_done and _rattle_timer <= 0.0:
		_apply_kinematic_poses(0.0)
		_set_physics_active(false)


func _apply_kinematic_poses(rattle_delta: float) -> void:
	if door_style == DoorStyle.SHOP_ROLLUP_SHUTTER:
		if shutter_body != null:
			shutter_body.position.y = _current_shutter_y + rattle_delta
	else:
		var ang := maxf(0.0, _current_angle_rad + rattle_delta)
		if leaf_body_left != null:
			leaf_body_left.rotation.y = ang
		if leaf_body_right != null:
			leaf_body_right.rotation.y = -ang

	for i in range(_bolt_visuals.size()):
		var bv := _bolt_visuals[i]
		if bv != null and is_instance_valid(bv):
			bv.position = _bolt_base_positions[i] + _bolt_lock_deltas[i] * _bolt_progress

	for cl in _clasp_visuals:
		if cl != null and is_instance_valid(cl):
			cl.rotation.x = lerpf(deg_to_rad(-55.0), 0.0, _bolt_progress)


func toggle_open() -> String:
	if is_locked:
		trigger_locked_rattle()
		return "🔒 %s مقفول بالترباس! اضغط [K] لفتح القفل" % door_label
	is_open = not is_open
	_set_physics_active(true)
	return "تم %s %s" % [("فتح" if is_open else "إغلاق"), door_label]


func toggle_lock() -> String:
	if is_open:
		is_open = false
	is_locked = not is_locked
	_set_physics_active(true)
	if is_locked:
		return "🔒 تم قفل %s بالترباس" % door_label
	return "🔓 تم فتح قفل %s" % door_label


func trigger_locked_rattle() -> void:
	_rattle_timer = 0.44
	_rattle_elapsed = 0.0
	_set_physics_active(true)


func get_interaction_prompt() -> String:
	if is_locked:
		return "[E] %s (مقفول 🔒)  |  [K] فتح القفل" % door_label
	var act := "إغلاق" if is_open else "فتح"
	return "[E] %s %s  |  [K] قفل بالترباس" % [act, door_label]


func _get_shutter_closed_y() -> float:
	return opening_height * 0.5


func _get_shutter_open_y() -> float:
	return opening_height * 0.5 + minf(slide_height, opening_height - 0.18)


# ==============================================================================
# MERGED MULTI-SURFACE ARRAYMESH BUILDER (CUTS DRAW CALLS BY >90%)
# ==============================================================================
class _MeshBatcher:
	var _tools: Dictionary = {} # Material -> SurfaceTool

	func _tool_for(mat: Material) -> SurfaceTool:
		if _tools.has(mat):
			return _tools[mat] as SurfaceTool
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(mat)
		_tools[mat] = st
		return st

	func add_box(pos: Vector3, size: Vector3, mat: Material, rot_z: float = 0.0) -> void:
		var st := _tool_for(mat)
		var bm := BoxMesh.new()
		bm.size = size
		var xf := Transform3D(Basis(Vector3.FORWARD, rot_z), pos)
		st.append_from(bm, 0, xf)

	func add_cylinder(pos: Vector3, radius: float, height: float, mat: Material, rot_z: float = 0.0) -> void:
		var st := _tool_for(mat)
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = height
		cm.radial_segments = 8
		cm.rings = 1
		var xf := Transform3D(Basis(Vector3.FORWARD, rot_z), pos)
		st.append_from(cm, 0, xf)

	func is_empty() -> bool:
		return _tools.is_empty()

	func commit() -> ArrayMesh:
		var am := ArrayMesh.new()
		for mat in _tools.keys():
			var st := _tools[mat] as SurfaceTool
			st.commit(am)
		return am


func _build_sudanese_door_geometry() -> void:
	if _built:
		return
	_built = true

	for ch in get_children():
		if ch.name in ["M", "C"]:
			ch.queue_free()

	match door_style:
		DoorStyle.COURTYARD_DOUBLE_GATE:
			_build_courtyard_gate(true)
		DoorStyle.COURTYARD_SINGLE_GATE:
			_build_courtyard_gate(false)
		DoorStyle.WOOD_SINGLE_DOOR:
			_build_wooden_door(false)
		DoorStyle.WOOD_DOUBLE_DOOR:
			_build_wooden_door(true)
		DoorStyle.SHOP_ROLLUP_SHUTTER:
			_build_shop_rollup_shutter()


func _pick_gate_color() -> Color:
	if gate_paint != GatePaintPreset.AUTO:
		return GATE_PALETTE[clampi(int(gate_paint) - 1, 0, GATE_PALETTE.size() - 1)]
	var h := absi(int(round(global_position.x * 0.73 + global_position.z * 1.19)))
	return GATE_PALETTE[h % GATE_PALETTE.size()]


func _build_courtyard_gate(is_double: bool) -> void:
	var frame_root := Node3D.new()
	frame_root.name = "StaticFrame"
	add_child(frame_root)

	var gate_col := _pick_gate_color()
	var mat_steel := _get_satin_steel_mat(gate_col, false)
	var mat_corr := _get_satin_steel_mat(gate_col.darkened(0.06), true)
	var mat_iron := _get_dark_iron_mat()
	var mat_bolt := _get_galvanized_bolt_mat()
	var mat_concrete := _get_concrete_pillar_mat()

	var w := opening_width
	var h := opening_height
	var hinge_inset_z := maxf(0.11, wall_thickness * 0.36)

	# 1. Merge ALL static frame elements (pillars, lintel beam, ground track) into ONE single ArrayMesh!
	var frame_key := "gate_frame_%.2f_%.2f_%s_%s" % [w, h, str(has_pillars), str(has_lintel_beam)]
	var frame_mesh: ArrayMesh
	if _merged_mesh_cache.has(frame_key):
		frame_mesh = _merged_mesh_cache[frame_key] as ArrayMesh
	else:
		var fb := _MeshBatcher.new()
		if has_pillars:
			var p_w := 0.42
			var p_h := h + 0.42
			for side: float in [-1.0, 1.0]:
				var px := side * (w * 0.5 + p_w * 0.5)
				fb.add_box(Vector3(px, p_h * 0.5, 0.0), Vector3(p_w, p_h, p_w), mat_concrete)
				fb.add_box(Vector3(px, p_h + 0.06, 0.0), Vector3(p_w + 0.08, 0.12, p_w + 0.08), mat_concrete)
		if has_lintel_beam:
			var beam_y := h + 0.24
			fb.add_box(Vector3(0.0, beam_y, 0.0), Vector3(w + 0.96, 0.24, 0.48), mat_concrete)
			fb.add_box(Vector3(0.0, beam_y - 0.13, 0.0), Vector3(w + 0.08, 0.04, 0.14), mat_iron)
		fb.add_box(Vector3(0.0, 0.015, -hinge_inset_z), Vector3(w + 0.04, 0.03, 0.16), mat_iron)
		frame_mesh = fb.commit()
		_merged_mesh_cache[frame_key] = frame_mesh

	var frame_mi := MeshInstance3D.new()
	frame_mi.name = "MergedFrameMesh"
	frame_mi.mesh = frame_mesh
	frame_mi.visibility_range_end = vis_range_end
	frame_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (has_pillars or has_lintel_beam) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frame_root.add_child(frame_mi)

	# Pillar colliders (lightweight static boxes only when has_pillars is true)
	if has_pillars:
		var p_w := 0.42
		var p_h := h + 0.42
		var psb := StaticBody3D.new()
		psb.name = "GatePillarsCol"
		for side: float in [-1.0, 1.0]:
			var pcs := CollisionShape3D.new()
			var pbs := BoxShape3D.new()
			pbs.size = Vector3(p_w, p_h, p_w)
			pcs.shape = pbs
			pcs.position = Vector3(side * (w * 0.5 + p_w * 0.5), p_h * 0.5, 0.0)
			psb.add_child(pcs)
		frame_root.add_child(psb)

	# 2. Side-hinged leaf / leaves: each leaf merges into 1 shadow-casting body mesh + 1 shadow-free hardware mesh!
	var leaf_gap := 0.025
	var hinge_clearance := 0.025
	var leaf_w := ((w - hinge_clearance * 2.0 - leaf_gap) * 0.5) if is_double else (w - hinge_clearance * 2.0)

	hinge_left = Node3D.new()
	hinge_left.name = "Hinge_Left"
	hinge_left.position = Vector3(-w * 0.5 + hinge_clearance, 0.0, -hinge_inset_z)
	add_child(hinge_left)

	var pair_l := _create_hinged_leaf_body("LeafBody_Left", Vector3(leaf_w * 0.5, h * 0.5, 0.0), Vector3(leaf_w, h, 0.075))
	leaf_body_left = pair_l["body"] as AnimatableBody3D
	hinge_left.add_child(leaf_body_left)
	_attach_merged_steel_gate_leaf(pair_l["visuals"] as Node3D, leaf_w, h, -1, gate_col, mat_steel, mat_corr, mat_iron, mat_bolt, true)

	if is_double:
		hinge_right = Node3D.new()
		hinge_right.name = "Hinge_Right"
		hinge_right.position = Vector3(w * 0.5 - hinge_clearance, 0.0, -hinge_inset_z)
		add_child(hinge_right)

		var pair_r := _create_hinged_leaf_body("LeafBody_Right", Vector3(-leaf_w * 0.5, h * 0.5, 0.0), Vector3(leaf_w, h, 0.075))
		leaf_body_right = pair_r["body"] as AnimatableBody3D
		hinge_right.add_child(leaf_body_right)
		_attach_merged_steel_gate_leaf(pair_r["visuals"] as Node3D, leaf_w, h, 1, gate_col, mat_steel, mat_corr, mat_iron, mat_bolt, false)


func _attach_merged_steel_gate_leaf(
	vis: Node3D,
	lw: float,
	lh: float,
	hinge_side: int,
	gate_col: Color,
	mat_steel: Material,
	mat_corr: Material,
	mat_iron: Material,
	mat_bolt: Material,
	add_lock_bolt: bool
) -> void:
	var key := "gate_leaf_%.2f_%.2f_%d_%s" % [lw, lh, hinge_side, gate_col.to_html(false)]
	var main_mesh: ArrayMesh
	var hw_mesh: ArrayMesh

	var grille_split_y := lh * 0.20
	var mid_bar_y := -lh * 0.14
	var hinge_x := float(hinge_side) * (lw * 0.5)
	var latch_x := -hinge_x

	if _merged_mesh_cache.has(key + "_m"):
		main_mesh = _merged_mesh_cache[key + "_m"] as ArrayMesh
		hw_mesh = _merged_mesh_cache[key + "_h"] as ArrayMesh
	else:
		var mb := _MeshBatcher.new() # Solid structural frame & corrugated sheet (shadow caster)
		var hb := _MeshBatcher.new() # Tiny hardware, pickets, spear-tips, hinge barrels, handles (NO shadow!)

		var frame_t := 0.068
		var rail_w := 0.065

		# Structural outer frame & crossbars
		mb.add_box(Vector3(hinge_x - float(hinge_side) * rail_w * 0.5, 0.0, 0.0), Vector3(rail_w, lh, frame_t), mat_steel)
		mb.add_box(Vector3(latch_x + float(hinge_side) * rail_w * 0.5, 0.0, 0.0), Vector3(rail_w, lh, frame_t), mat_steel)
		mb.add_box(Vector3(0.0, -lh * 0.5 + rail_w * 0.5, 0.0), Vector3(lw, rail_w, frame_t), mat_steel)
		mb.add_box(Vector3(0.0, lh * 0.5 - rail_w * 0.5, 0.0), Vector3(lw, rail_w, frame_t), mat_steel)
		mb.add_box(Vector3(0.0, grille_split_y, 0.0), Vector3(lw - rail_w, 0.055, frame_t * 0.96), mat_steel)
		mb.add_box(Vector3(0.0, mid_bar_y, 0.0), Vector3(lw - rail_w, 0.050, frame_t * 0.94), mat_steel)
		mb.add_box(Vector3(0.0, (grille_split_y - lh * 0.5) * 0.5, 0.0), Vector3(0.048, (grille_split_y + lh * 0.5), frame_t * 0.92), mat_steel)

		# Recessed corrugated steel panel
		var sheet_h := (grille_split_y + lh * 0.5) - rail_w
		var sheet_cy := -lh * 0.5 + rail_w + sheet_h * 0.5
		mb.add_box(Vector3(0.0, sheet_cy, 0.0), Vector3(lw - rail_w * 1.8, sheet_h, 0.028), mat_corr)

		# Corrugated standing ribs (non-shadow detail)
		var rib_count := maxi(4, int(round(lw * 4.5)))
		for ri in range(rib_count):
			var t := (float(ri) + 0.5) / float(rib_count)
			var rx := lerpf(-lw * 0.5 + rail_w + 0.04, lw * 0.5 - rail_w - 0.04, t)
			hb.add_box(Vector3(rx, sheet_cy, 0.0), Vector3(0.022, sheet_h - 0.04, 0.042), mat_corr)

		# Upper wrought-iron pickets, geometric diamonds & spear-tip finials (merged, shadow OFF)
		var grille_h := (lh * 0.5 - rail_w) - grille_split_y
		var grille_cy := grille_split_y + grille_h * 0.5
		var picket_count := maxi(4, int(round(lw * 5.5)))
		for pi in range(picket_count):
			var t := (float(pi) + 0.5) / float(picket_count)
			var px := lerpf(-lw * 0.5 + rail_w + 0.05, lw * 0.5 - rail_w - 0.05, t)
			hb.add_box(Vector3(px, grille_cy + 0.06, 0.0), Vector3(0.018, grille_h + 0.14, 0.018), mat_iron)
			hb.add_box(Vector3(px, lh * 0.5 + 0.065, 0.0), Vector3(0.042, 0.095, 0.024), mat_iron, deg_to_rad(45.0))

		hb.add_box(Vector3(0.0, grille_cy, 0.0), Vector3(lw - rail_w * 1.8, 0.022, 0.024), mat_iron)
		var dia_count := maxi(2, int(round(lw * 2.2)))
		for di in range(dia_count):
			var dt := (float(di) + 0.5) / float(dia_count)
			var dx := lerpf(-lw * 0.5 + rail_w + 0.14, lw * 0.5 - rail_w - 0.14, dt)
			hb.add_box(Vector3(dx, grille_cy, 0.0), Vector3(0.11, 0.11, 0.026), mat_iron, deg_to_rad(45.0))

		# 3 cylindrical hinge barrels (`مفصلات`, shadow OFF)
		for hi in range(3):
			var hy := lerpf(-lh * 0.38, lh * 0.38, float(hi) / 2.0)
			hb.add_cylinder(Vector3(hinge_x, hy, 0.0), 0.024, 0.13, mat_iron)

		# Latch handles & bolt guide sleeves (shadow OFF)
		var handle_x := latch_x + float(hinge_side) * 0.11
		var handle_y := -lh * 0.05
		for side_z: float in [-1.0, 1.0]:
			hb.add_box(Vector3(handle_x, handle_y, side_z * 0.042), Vector3(0.045, 0.22, 0.012), mat_iron)
			hb.add_box(Vector3(handle_x, handle_y, side_z * 0.072), Vector3(0.022, 0.15, 0.022), mat_bolt)
			hb.add_box(Vector3(handle_x, handle_y + 0.065, side_z * 0.055), Vector3(0.020, 0.020, 0.036), mat_iron)
			hb.add_box(Vector3(handle_x, handle_y - 0.065, side_z * 0.055), Vector3(0.020, 0.020, 0.036), mat_iron)

		if add_lock_bolt:
			var bolt_x := latch_x + float(hinge_side) * 0.055
			hb.add_box(Vector3(bolt_x, -lh * 0.26, -0.048), Vector3(0.048, 0.042, 0.038), mat_iron)
			hb.add_box(Vector3(bolt_x, -lh * 0.42, -0.048), Vector3(0.048, 0.042, 0.038), mat_iron)
			hb.add_box(Vector3(bolt_x + float(hinge_side) * 0.04, mid_bar_y, -0.048), Vector3(0.14, 0.055, 0.022), mat_iron)

		main_mesh = mb.commit()
		hw_mesh = hb.commit()
		_merged_mesh_cache[key + "_m"] = main_mesh
		_merged_mesh_cache[key + "_h"] = hw_mesh

	var mi_main := MeshInstance3D.new()
	mi_main.name = "LeafMainMesh"
	mi_main.mesh = main_mesh
	mi_main.visibility_range_end = vis_range_end
	mi_main.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	vis.add_child(mi_main)

	var mi_hw := MeshInstance3D.new()
	mi_hw.name = "LeafHardwareMesh"
	mi_hw.mesh = hw_mesh
	mi_hw.visibility_range_end = minf(vis_range_end, 70.0)
	mi_hw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vis.add_child(mi_hw)

	# Visible animated sliding metal `ترباس` bolt (1 merged non-shadow mesh, cached!)
	if add_lock_bolt:
		var bolt_x := latch_x + float(hinge_side) * 0.055
		var drop_mesh := _get_cached_drop_bolt_mesh(hinge_side, mat_bolt)
		var drop_mi := MeshInstance3D.new()
		drop_mi.name = "VerticalDropBolt"
		var drop_base := Vector3(bolt_x, -lh * 0.34, -0.052)
		drop_mi.position = drop_base
		drop_mi.mesh = drop_mesh
		drop_mi.visibility_range_end = 45.0
		drop_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vis.add_child(drop_mi)
		_bolt_visuals.append(drop_mi)
		_bolt_base_positions.append(drop_base)
		_bolt_lock_deltas.append(Vector3(0.0, -0.14, 0.0))


func _build_wooden_door(is_double: bool) -> void:
	var frame_root := Node3D.new()
	frame_root.name = "StaticFrame"
	add_child(frame_root)

	var mat_frame := _get_wood_mat(Color(0.46, 0.30, 0.18, 1.0))
	var mat_leaf := _get_wood_mat(Color(0.56, 0.37, 0.22, 1.0))
	var mat_panel := _get_wood_mat(Color(0.49, 0.32, 0.19, 1.0))
	var mat_brass := _get_brass_mat()
	var mat_iron := _get_dark_iron_mat()
	var mat_threshold := _get_concrete_pillar_mat()

	var w := opening_width
	var h := opening_height
	var jamb_t := 0.065
	var frame_d := wall_thickness + 0.06
	var hinge_inset_z := maxf(0.12, wall_thickness * 0.44)

	# 1. Merge entire recessed 3D door frame + architraves + threshold into ONE ArrayMesh!
	var fkey := "wood_frame_%.2f_%.2f_%.2f_%s" % [w, h, wall_thickness, str(build_recessed_frame)]
	var fmesh: ArrayMesh
	if _merged_mesh_cache.has(fkey):
		fmesh = _merged_mesh_cache[fkey] as ArrayMesh
	else:
		var fb := _MeshBatcher.new()
		if build_recessed_frame:
			fb.add_box(Vector3(-w * 0.5 - jamb_t * 0.5, h * 0.5, 0.0), Vector3(jamb_t, h + jamb_t, frame_d), mat_frame)
			fb.add_box(Vector3(w * 0.5 + jamb_t * 0.5, h * 0.5, 0.0), Vector3(jamb_t, h + jamb_t, frame_d), mat_frame)
			fb.add_box(Vector3(0.0, h + jamb_t * 0.5, 0.0), Vector3(w + jamb_t * 2.0, jamb_t, frame_d), mat_frame)
			for sz: float in [-1.0, 1.0]:
				var tz: float = sz * (frame_d * 0.5 + 0.012)
				fb.add_box(Vector3(-w * 0.5 - jamb_t * 0.6, h * 0.5, tz), Vector3(0.085, h + 0.10, 0.022), mat_frame)
				fb.add_box(Vector3(w * 0.5 + jamb_t * 0.6, h * 0.5, tz), Vector3(0.085, h + 0.10, 0.022), mat_frame)
				fb.add_box(Vector3(0.0, h + jamb_t * 0.65, tz), Vector3(w + 0.22, 0.085, 0.022), mat_frame)
		fb.add_box(Vector3(0.0, 0.018, 0.0), Vector3(w + jamb_t * 1.4, 0.036, frame_d + 0.04), mat_threshold)
		fmesh = fb.commit()
		_merged_mesh_cache[fkey] = fmesh

	var fmi := MeshInstance3D.new()
	fmi.name = "MergedFrameMesh"
	fmi.mesh = fmesh
	fmi.visibility_range_end = vis_range_end
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frame_root.add_child(fmi)

	# 2. Side-hinged wooden leaf / leaves
	var clearance := 0.012
	var center_gap := 0.014 if is_double else 0.0
	var leaf_w := ((w - clearance * 2.0 - center_gap) * 0.5) if is_double else (w - clearance * 2.0)
	var leaf_h := h - 0.035

	hinge_left = Node3D.new()
	hinge_left.name = "Hinge_Left"
	hinge_left.position = Vector3(-w * 0.5 + clearance, 0.032, -hinge_inset_z)
	add_child(hinge_left)

	var pair_l := _create_hinged_leaf_body("LeafBody_Left", Vector3(leaf_w * 0.5, leaf_h * 0.5, 0.0), Vector3(leaf_w, leaf_h, 0.062))
	leaf_body_left = pair_l["body"] as AnimatableBody3D
	hinge_left.add_child(leaf_body_left)
	_attach_merged_wood_leaf(pair_l["visuals"] as Node3D, leaf_w, leaf_h, -1, mat_leaf, mat_panel, mat_brass, mat_iron, true)

	if is_double:
		hinge_right = Node3D.new()
		hinge_right.name = "Hinge_Right"
		hinge_right.position = Vector3(w * 0.5 - clearance, 0.032, -hinge_inset_z)
		add_child(hinge_right)

		var pair_r := _create_hinged_leaf_body("LeafBody_Right", Vector3(-leaf_w * 0.5, leaf_h * 0.5, 0.0), Vector3(leaf_w, leaf_h, 0.062))
		leaf_body_right = pair_r["body"] as AnimatableBody3D
		hinge_right.add_child(leaf_body_right)
		_attach_merged_wood_leaf(pair_r["visuals"] as Node3D, leaf_w, leaf_h, 1, mat_leaf, mat_panel, mat_brass, mat_iron, false)


func _attach_merged_wood_leaf(
	vis: Node3D,
	lw: float,
	lh: float,
	hinge_side: int,
	mat_leaf: Material,
	mat_panel: Material,
	mat_brass: Material,
	mat_iron: Material,
	add_lock_bolt: bool
) -> void:
	var key := "wood_leaf_%.2f_%.2f_%d" % [lw, lh, hinge_side]
	var main_mesh: ArrayMesh
	var hw_mesh: ArrayMesh

	var core_d := 0.048
	var hinge_x := float(hinge_side) * (lw * 0.5)
	var latch_x := -hinge_x
	var hy := -lh * 0.06

	if _merged_mesh_cache.has(key + "_m"):
		main_mesh = _merged_mesh_cache[key + "_m"] as ArrayMesh
		hw_mesh = _merged_mesh_cache[key + "_h"] as ArrayMesh
	else:
		var mb := _MeshBatcher.new()
		var hb := _MeshBatcher.new()

		mb.add_box(Vector3.ZERO, Vector3(lw, lh, core_d), mat_leaf)
		var stile_w := clampf(lw * 0.13, 0.09, 0.14)
		mb.add_box(Vector3(hinge_x - float(hinge_side) * stile_w * 0.5, 0.0, 0.0), Vector3(stile_w, lh, core_d + 0.014), mat_leaf)
		mb.add_box(Vector3(latch_x + float(hinge_side) * stile_w * 0.5, 0.0, 0.0), Vector3(stile_w, lh, core_d + 0.014), mat_leaf)
		mb.add_box(Vector3(0.0, lh * 0.5 - 0.08, 0.0), Vector3(lw, 0.16, core_d + 0.014), mat_leaf)
		mb.add_box(Vector3(0.0, -lh * 0.04, 0.0), Vector3(lw, 0.14, core_d + 0.014), mat_leaf)
		mb.add_box(Vector3(0.0, -lh * 0.5 + 0.10, 0.0), Vector3(lw, 0.20, core_d + 0.014), mat_leaf)

		var pan_w := maxf(0.24, lw - stile_w * 2.4)
		var panel_specs: Array[Array] = [[lh * 0.26, lh * 0.30], [-lh * 0.25, lh * 0.28]]
		for spec in panel_specs:
			var py: float = spec[0]
			var ph: float = spec[1]
			for sz: float in [-1.0, 1.0]:
				mb.add_box(Vector3(0.0, py, sz * (core_d * 0.5 + 0.008)), Vector3(pan_w, ph, 0.016), mat_panel)
				mb.add_box(Vector3(0.0, py, sz * (core_d * 0.5 + 0.014)), Vector3(pan_w * 0.84, ph * 0.82, 0.012), mat_leaf)

		# Small hardware (merged into non-shadow mesh): 3 hinge barrels + lever handles + keyhole plates
		for hi in range(3):
			var bhy := lerpf(-lh * 0.38, lh * 0.38, float(hi) / 2.0)
			hb.add_cylinder(Vector3(hinge_x, bhy, -0.018), 0.016, 0.10, mat_brass)

		var hx := latch_x + float(hinge_side) * 0.085
		for sz: float in [-1.0, 1.0]:
			var fz: float = sz * (core_d * 0.5 + 0.012)
			hb.add_box(Vector3(hx, hy - 0.02, fz), Vector3(0.044, 0.18, 0.010), mat_brass)
			hb.add_box(Vector3(hx, hy - 0.075, fz + sz * 0.006), Vector3(0.010, 0.024, 0.006), mat_iron)
			hb.add_box(Vector3(hx, hy + 0.02, fz + sz * 0.024), Vector3(0.020, 0.020, 0.042), mat_brass)
			hb.add_box(Vector3(hx + float(hinge_side) * 0.055, hy + 0.02, fz + sz * 0.045), Vector3(0.125, 0.020, 0.018), mat_brass)

		if add_lock_bolt:
			var bx := latch_x + float(hinge_side) * 0.09
			hb.add_box(Vector3(bx, hy + 0.16, -(core_d * 0.5 + 0.014)), Vector3(0.12, 0.045, 0.018), mat_iron)

		main_mesh = mb.commit()
		hw_mesh = hb.commit()
		_merged_mesh_cache[key + "_m"] = main_mesh
		_merged_mesh_cache[key + "_h"] = hw_mesh

	var mi_main := MeshInstance3D.new()
	mi_main.name = "LeafMainMesh"
	mi_main.mesh = main_mesh
	mi_main.visibility_range_end = vis_range_end
	mi_main.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	vis.add_child(mi_main)

	var mi_hw := MeshInstance3D.new()
	mi_hw.name = "LeafHardwareMesh"
	mi_hw.mesh = hw_mesh
	mi_hw.visibility_range_end = minf(vis_range_end, 55.0)
	mi_hw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vis.add_child(mi_hw)

	if add_lock_bolt:
		var bx := latch_x + float(hinge_side) * 0.09
		var bolt_mi := MeshInstance3D.new()
		bolt_mi.name = "SlidingDeadbolt"
		var b_base := Vector3(bx + float(hinge_side) * 0.02, hy + 0.16, -(core_d * 0.5 + 0.026))
		bolt_mi.position = b_base
		bolt_mi.mesh = _get_cached_deadbolt_mesh(hinge_side, mat_brass)
		bolt_mi.visibility_range_end = 40.0
		bolt_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vis.add_child(bolt_mi)
		_bolt_visuals.append(bolt_mi)
		_bolt_base_positions.append(b_base)
		_bolt_lock_deltas.append(Vector3(-float(hinge_side) * 0.072, 0.0, 0.0))


func _build_shop_rollup_shutter() -> void:
	var frame_root := Node3D.new()
	frame_root.name = "StaticFrame"
	add_child(frame_root)

	var w := opening_width
	var h := opening_height
	var shutter_col := _pick_gate_color()
	var mat_slat := _get_satin_steel_mat(shutter_col, true)
	var mat_rail := _get_dark_iron_mat()
	var mat_box := _get_satin_steel_mat(shutter_col.darkened(0.18), false)
	var mat_bolt := _get_galvanized_bolt_mat()

	# 1. Merge roller housing box + side guide rails + floor plate into 1 MeshInstance3D!
	var fkey := "shutter_frame_%.2f_%.2f_%s" % [w, h, shutter_col.to_html(false)]
	var fmesh: ArrayMesh
	if _merged_mesh_cache.has(fkey):
		fmesh = _merged_mesh_cache[fkey] as ArrayMesh
	else:
		var fb := _MeshBatcher.new()
		fb.add_box(Vector3(0.0, h + 0.18, 0.04), Vector3(w + 0.18, 0.34, 0.34), mat_box)
		fb.add_box(Vector3(-w * 0.5 - 0.035, h * 0.5, 0.02), Vector3(0.07, h + 0.04, 0.11), mat_rail)
		fb.add_box(Vector3(w * 0.5 + 0.035, h * 0.5, 0.02), Vector3(0.07, h + 0.04, 0.11), mat_rail)
		fb.add_box(Vector3(0.0, 0.015, 0.02), Vector3(w + 0.04, 0.03, 0.14), mat_rail)
		fmesh = fb.commit()
		_merged_mesh_cache[fkey] = fmesh

	var fmi := MeshInstance3D.new()
	fmi.name = "RollerHousingBox"
	fmi.mesh = fmesh
	fmi.visibility_range_end = vis_range_end
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frame_root.add_child(fmi)

	# 2. Moving slatted shutter curtain merged into 1 single ArrayMesh on AnimatableBody3D!
	shutter_body = _create_leaf_animatable_body("ShutterCurtain", Vector3(0.0, h * 0.5, 0.02), Vector3(w - 0.02, h, 0.065))
	add_child(shutter_body)

	var skey := "shutter_curtain_%.2f_%.2f_%s" % [w, h, shutter_col.to_html(false)]
	var smesh: ArrayMesh
	if _merged_mesh_cache.has(skey):
		smesh = _merged_mesh_cache[skey] as ArrayMesh
	else:
		var sb := _MeshBatcher.new()
		sb.add_box(Vector3.ZERO, Vector3(w - 0.04, h, 0.032), mat_slat)
		var slat_count := maxi(8, int(round(h * 4.5)))
		var slat_step := h / float(slat_count)
		for si in range(slat_count):
			var sy := -h * 0.5 + (float(si) + 0.5) * slat_step
			sb.add_box(Vector3(0.0, sy, 0.0), Vector3(w - 0.03, slat_step * 0.72, 0.052), mat_slat)
		sb.add_box(Vector3(0.0, -h * 0.5 + 0.045, 0.0), Vector3(w, 0.09, 0.085), mat_rail)
		sb.add_box(Vector3(0.0, -h * 0.5 + 0.20, 0.055), Vector3(0.32, 0.032, 0.042), mat_bolt)
		smesh = sb.commit()
		_merged_mesh_cache[skey] = smesh

	var smi := MeshInstance3D.new()
	smi.name = "MergedCurtainMesh"
	smi.mesh = smesh
	smi.visibility_range_end = vis_range_end
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	shutter_body.add_child(smi)

	# Twin animated padlock clasps (merged into 1 tiny non-shadow mesh each)
	var clasp_mesh := _get_cached_clasp_mesh(mat_rail, mat_bolt)
	for side: float in [-1.0, 1.0]:
		var cx: float = side * (w * 0.36)
		var clasp := MeshInstance3D.new()
		clasp.name = "PadlockClasp_%s" % ("L" if side < 0.0 else "R")
		clasp.position = Vector3(cx, -h * 0.5 + 0.08, 0.050)
		clasp.mesh = clasp_mesh
		clasp.visibility_range_end = 45.0
		clasp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shutter_body.add_child(clasp)
		_clasp_visuals.append(clasp)


# ==============================================================================
# CACHED HARDWARE MINI-MESHES & SHARED MATERIALS
# ==============================================================================
func _get_cached_drop_bolt_mesh(hinge_side: int, mat_bolt: Material) -> ArrayMesh:
	var key := "drop_bolt_%d" % hinge_side
	if _merged_mesh_cache.has(key):
		return _merged_mesh_cache[key] as ArrayMesh
	var b := _MeshBatcher.new()
	b.add_cylinder(Vector3.ZERO, 0.013, 0.42, mat_bolt)
	b.add_box(Vector3(float(hinge_side) * 0.045, 0.16, -0.015), Vector3(0.09, 0.022, 0.022), mat_bolt)
	var m := b.commit()
	_merged_mesh_cache[key] = m
	return m


func _get_cached_deadbolt_mesh(hinge_side: int, mat_brass: Material) -> ArrayMesh:
	var key := "deadbolt_%d" % hinge_side
	if _merged_mesh_cache.has(key):
		return _merged_mesh_cache[key] as ArrayMesh
	var b := _MeshBatcher.new()
	b.add_cylinder(Vector3.ZERO, 0.010, 0.16, mat_brass, PI * 0.5)
	b.add_box(Vector3(float(hinge_side) * 0.03, 0.0, -0.020), Vector3(0.020, 0.020, 0.036), mat_brass)
	var m := b.commit()
	_merged_mesh_cache[key] = m
	return m


func _get_cached_clasp_mesh(mat_rail: Material, mat_bolt: Material) -> ArrayMesh:
	var key := "shutter_clasp"
	if _merged_mesh_cache.has(key):
		return _merged_mesh_cache[key] as ArrayMesh
	var b := _MeshBatcher.new()
	b.add_box(Vector3(0.0, -0.04, 0.008), Vector3(0.055, 0.11, 0.016), mat_rail)
	b.add_box(Vector3(0.0, -0.085, 0.022), Vector3(0.052, 0.068, 0.028), mat_bolt)
	var m := b.commit()
	_merged_mesh_cache[key] = m
	return m


func _create_hinged_leaf_body(bname: String, leaf_center_offset: Vector3, col_size: Vector3) -> Dictionary:
	var ab := AnimatableBody3D.new()
	ab.name = bname
	ab.sync_to_physics = false
	ab.position = Vector3.ZERO
	ab.set_meta("interactive_door", self)

	var cs := CollisionShape3D.new()
	cs.name = "LeafCollision"
	cs.position = leaf_center_offset
	var bs := BoxShape3D.new()
	bs.size = col_size
	cs.shape = bs
	ab.add_child(cs)

	var vis := Node3D.new()
	vis.name = "LeafVisuals"
	vis.position = leaf_center_offset
	ab.add_child(vis)

	return {"body": ab, "visuals": vis}


func _create_leaf_animatable_body(bname: String, local_offset: Vector3, col_size: Vector3) -> AnimatableBody3D:
	var ab := AnimatableBody3D.new()
	ab.name = bname
	ab.sync_to_physics = false
	ab.position = local_offset
	ab.set_meta("interactive_door", self)

	var cs := CollisionShape3D.new()
	cs.name = "LeafCollision"
	var bs := BoxShape3D.new()
	bs.size = col_size
	cs.shape = bs
	ab.add_child(cs)
	return ab


static func _get_satin_steel_mat(col: Color, corrugated: bool) -> StandardMaterial3D:
	var key := "steel_%s_%s" % [col.to_html(false), str(corrugated)]
	if _shared_mats.has(key):
		return _shared_mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.25
	m.roughness = 0.55
	if corrugated and ResourceLoader.exists(TEX_CORR_ALB):
		m.albedo_texture = ResourceLoader.load(TEX_CORR_ALB) as Texture2D
		if ResourceLoader.exists(TEX_CORR_NOR):
			m.normal_enabled = true
			m.normal_scale = 0.65
			m.normal_texture = ResourceLoader.load(TEX_CORR_NOR) as Texture2D
		if ResourceLoader.exists(TEX_CORR_RGH):
			m.roughness_texture = ResourceLoader.load(TEX_CORR_RGH) as Texture2D
		m.uv1_scale = Vector3(2.0, 2.0, 1.0)
	_shared_mats[key] = m
	return m


static func _get_wood_mat(col: Color) -> StandardMaterial3D:
	var key := "wood_%s" % col.to_html(false)
	if _shared_mats.has(key):
		return _shared_mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.0
	m.roughness = 0.72
	if ResourceLoader.exists(TEX_WOOD_ALB):
		m.albedo_texture = ResourceLoader.load(TEX_WOOD_ALB) as Texture2D
		if ResourceLoader.exists(TEX_WOOD_NOR):
			m.normal_enabled = true
			m.normal_scale = 0.65
			m.normal_texture = ResourceLoader.load(TEX_WOOD_NOR) as Texture2D
		if ResourceLoader.exists(TEX_WOOD_RGH):
			m.roughness_texture = ResourceLoader.load(TEX_WOOD_RGH) as Texture2D
		m.uv1_scale = Vector3(1.5, 2.0, 1.0)
	_shared_mats[key] = m
	return m


static func _get_dark_iron_mat() -> StandardMaterial3D:
	if _shared_mats.has("dark_iron"):
		return _shared_mats["dark_iron"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.14, 0.15, 0.17, 1.0)
	m.metallic = 0.65
	m.roughness = 0.48
	_shared_mats["dark_iron"] = m
	return m


static func _get_galvanized_bolt_mat() -> StandardMaterial3D:
	if _shared_mats.has("galv_bolt"):
		return _shared_mats["galv_bolt"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.74, 0.76, 0.78, 1.0)
	m.metallic = 0.80
	m.roughness = 0.34
	_shared_mats["galv_bolt"] = m
	return m


static func _get_brass_mat() -> StandardMaterial3D:
	if _shared_mats.has("brass"):
		return _shared_mats["brass"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.62, 0.28, 1.0)
	m.metallic = 0.78
	m.roughness = 0.32
	_shared_mats["brass"] = m
	return m


static func _get_concrete_pillar_mat() -> StandardMaterial3D:
	if _shared_mats.has("concrete_lintel"):
		return _shared_mats["concrete_lintel"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.80, 0.70, 1.0)
	m.metallic = 0.0
	m.roughness = 0.88
	if ResourceLoader.exists(TEX_PLAS_ALB):
		m.albedo_texture = ResourceLoader.load(TEX_PLAS_ALB) as Texture2D
		m.uv1_scale = Vector3(2.0, 2.0, 1.0)
	_shared_mats["concrete_lintel"] = m
	return m
