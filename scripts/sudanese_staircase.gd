extends Node3D
class_name SudaneseStaircase

## Reusable, high-FPS Sudanese Architectural Staircase Builder for Godot 4.7.2.
##
## Features:
## - Single multi-surface ArrayMesh (MeshInstance3D) per staircase with static mesh caching
## - Realistic proportions (riser ~0.175m, tread ~0.28m, width ~1.15m)
## - Solid angled concrete waist slab (بلاطة خرسانية مائلة) underneath every flight
## - Grounded landings & reinforced concrete support columns (البسطات والأعمدة)
## - Painted Sudanese iron handrails (درابزين حديدي) with balusters (~0.85m spacing) & top/mid bars
## - Smooth sloped ConvexPolygonShape3D ramp collisions along every flight + BoxShape3D landings
##   and side guard colliders so CharacterBody3D players & NPCs climb smoothly without clipping.

enum StairStyle {
	EXTERIOR_SINGLE_FLIGHT = 0,
	MULTI_STORY_SWITCHBACK = 1,
	LOW_STEPS = 2,
}

@export var stair_style: StairStyle = StairStyle.EXTERIOR_SINGLE_FLIGHT
@export var stair_width: float = 1.15
@export var riser_target: float = 0.175
@export var tread_depth: float = 0.28
@export var total_rise: float = 3.80
@export var climb_dir_z: float = -1.0
@export var landing_depth: float = 1.25
@export var brick_masonry_style: bool = false
@export var vis_range_end: float = 140.0

## Multi-story switchback floor elevations (e.g. Ground -> Floor 1 -> Floor 2 -> Roof)
@export var story_heights: PackedFloat32Array = PackedFloat32Array([0.0, 3.50, 6.90, 10.44])
@export var floor_landing_depth: float = 1.60
@export var mid_landing_depth: float = 1.20
@export var center_gap: float = 0.12

## Low-step settings (Corniche steps / Bus station boarding steps)
@export var low_step_count: int = 4
@export var low_step_run: float = 1.60
@export var low_step_add_handrails: bool = false

## Shared material & merged mesh caches (keeps GPU memory & draw calls minimal)
static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}

var _built: bool = false


# ==============================================================================
# MULTI-SURFACE ARRAYMESH BATCHER (MERGES ALL STAIR PARTS INTO 1 MESHINSTANCE)
# ==============================================================================
class _StairBatcher:
	var _tools: Dictionary = {} # Material -> SurfaceTool

	func _tool_for(mat: Material) -> SurfaceTool:
		if _tools.has(mat):
			return _tools[mat] as SurfaceTool
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(mat)
		_tools[mat] = st
		return st

	func add_box(center: Vector3, size: Vector3, mat: Material) -> void:
		if size.x <= 0.001 or size.y <= 0.001 or size.z <= 0.001:
			return
		var st := _tool_for(mat)
		var bm := BoxMesh.new()
		bm.size = size
		st.append_from(bm, 0, Transform3D(Basis.IDENTITY, center))

	func add_bar(p0: Vector3, p1: Vector3, thickness: float, height: float, mat: Material) -> void:
		var diff := p1 - p0
		var length := diff.length()
		if length <= 0.002:
			return
		var fwd := diff / length
		var up_ref := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		var right := up_ref.cross(fwd).normalized()
		var up := fwd.cross(right).normalized()
		var basis := Basis(right, up, fwd)
		var st := _tool_for(mat)
		var bm := BoxMesh.new()
		bm.size = Vector3(thickness, height, length)
		st.append_from(bm, 0, Transform3D(basis, (p0 + p1) * 0.5))

	## Adds a solid 8-vertex sloped hexahedron (for waist slabs & sloped stringers)
	## Quad A at z=za: bottom (xa0..xa1, ya_bot), top (xa0..xa1, ya_top)
	## Quad B at z=zb: bottom (xb0..xb1, yb_bot), top (xb0..xb1, yb_top)
	func add_sloped_prism_z(
		x0: float, x1: float,
		za: float, ya_bot: float, ya_top: float,
		zb: float, yb_bot: float, yb_top: float,
		mat: Material
	) -> void:
		var st := _tool_for(mat)
		# Normalize ordering so z_lo < z_hi for consistent outward CCW winding
		var z_lo := za
		var y_lo_b := ya_bot
		var y_lo_t := ya_top
		var z_hi := zb
		var y_hi_b := yb_bot
		var y_hi_t := yb_top
		if z_lo > z_hi:
			z_lo = zb
			y_lo_b = yb_bot
			y_lo_t = yb_top
			z_hi = za
			y_hi_b = ya_bot
			y_hi_t = ya_top

		var v000 := Vector3(x0, y_lo_b, z_lo)
		var v100 := Vector3(x1, y_lo_b, z_lo)
		var v110 := Vector3(x1, y_lo_t, z_lo)
		var v010 := Vector3(x0, y_lo_t, z_lo)
		var v001 := Vector3(x0, y_hi_b, z_hi)
		var v101 := Vector3(x1, y_hi_b, z_hi)
		var v111 := Vector3(x1, y_hi_t, z_hi)
		var v011 := Vector3(x0, y_hi_t, z_hi)

		# Godot front-face is CLOCKWISE when looking at the outside of the face
		# Top face (+Y)
		_add_quad(st, v010, v110, v111, v011)
		# Bottom face (-Y)
		_add_quad(st, v001, v101, v100, v000)
		# Right face (+X)
		_add_quad(st, v101, v111, v110, v100)
		# Left face (-X)
		_add_quad(st, v000, v010, v011, v001)
		# Front face (+Z)
		_add_quad(st, v001, v011, v111, v101)
		# Back face (-Z)
		_add_quad(st, v100, v110, v010, v000)

	func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		var n_out := (c - a).cross(b - a).normalized()
		if n_out.length_squared() < 0.0001:
			return
		st.set_normal(n_out)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(a)
		st.set_normal(n_out)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(b)
		st.set_normal(n_out)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(c)

		st.set_normal(n_out)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(a)
		st.set_normal(n_out)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(c)
		st.set_normal(n_out)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(d)

	func commit() -> ArrayMesh:
		var am := ArrayMesh.new()
		for mat in _tools.keys():
			var st := _tools[mat] as SurfaceTool
			st.commit(am)
		return am


# ==============================================================================
# LIFECYCLE
# ==============================================================================
func _ready() -> void:
	add_to_group("sudanese_staircases")
	build_staircase()


func build_staircase() -> void:
	if _built:
		return
	_built = true

	var col_body := StaticBody3D.new()
	col_body.name = "StairCollisionBody"
	col_body.add_to_group("walkable_stair_ramps")
	add_child(col_body)

	var cache_key := _make_cache_key()
	var cached_mesh: ArrayMesh = _mesh_cache.get(cache_key) as ArrayMesh
	var batcher: _StairBatcher = null if cached_mesh != null else _StairBatcher.new()

	match stair_style:
		StairStyle.EXTERIOR_SINGLE_FLIGHT:
			_build_exterior_single_flight(batcher, col_body)
		StairStyle.MULTI_STORY_SWITCHBACK:
			_build_multi_story_switchback(batcher, col_body)
		StairStyle.LOW_STEPS:
			_build_low_steps(batcher, col_body)

	var final_mesh: ArrayMesh
	if cached_mesh != null:
		final_mesh = cached_mesh
	else:
		final_mesh = batcher.commit()
		_mesh_cache[cache_key] = final_mesh

	var mi := MeshInstance3D.new()
	mi.name = "MergedStairMesh"
	mi.mesh = final_mesh
	mi.visibility_range_end = vis_range_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


func _make_cache_key() -> String:
	var sh_str := ""
	for h in story_heights:
		sh_str += "%.2f_" % h
	return "st_%d_w%.2f_r%.3f_t%.2f_h%.2f_dz%.1f_ld%.2f_br%s_sh%s_ls%d_%.2f" % [
		int(stair_style), stair_width, riser_target, tread_depth, total_rise,
		climb_dir_z, landing_depth, str(brick_masonry_style), sh_str,
		low_step_count, low_step_run
	]


# ==============================================================================
# STYLE 0: EXTERIOR SINGLE-FLIGHT ROOF STAIRCASE (SUDANESE COURTYARD HOUSE)
# ==============================================================================
func _build_exterior_single_flight(b: _StairBatcher, col_body: StaticBody3D) -> void:
	var dir_z: float = -1.0 if climb_dir_z < 0.0 else 1.0
	var w := stair_width
	var mat_conc := _get_concrete_mat()
	var mat_tread := _get_tread_stone_mat()
	var mat_trim := _get_brick_masonry_mat() if brick_masonry_style else _get_concrete_trim_mat()
	var mat_iron := _get_iron_handrail_mat()

	var n_risers := maxi(4, int(round(total_rise / maxf(0.14, riser_target))))
	var riser := total_rise / float(n_risers)
	var n_treads := n_risers - 1
	var run := float(n_treads) * tread_depth
	var z_start := 0.0
	var z_end := dir_z * run
	var slab_thick := 0.22

	# 1. Flight steps + solid angled waist slab + smooth ConvexPolygonShape3D ramp
	_add_flight_z(
		b, col_body, "RoofFlight",
		0.0, w,
		z_start, 0.0,
		z_end, total_rise,
		n_risers, tread_depth, slab_thick,
		mat_conc, mat_tread, mat_trim
	)

	# 2. Ground entry concrete threshold pad (prevents gap at bottom step)
	if b != null:
		b.add_box(Vector3(w * 0.5, 0.025, z_start - dir_z * 0.18), Vector3(w + 0.04, 0.05, 0.36), mat_tread)

	# 3. Top Landing Slab (flush with roof top y = total_rise, tucked -0.04m into wall edge)
	var z_land_far := z_end + dir_z * landing_depth
	var z_land_min := minf(z_end, z_land_far)
	var z_land_max := maxf(z_end, z_land_far)
	var z_land_ctr := (z_land_min + z_land_max) * 0.5
	var x_land_min := -0.04
	var x_land_max := w + 0.04
	var x_land_w := x_land_max - x_land_min
	var x_land_ctr := (x_land_min + x_land_max) * 0.5

	if b != null:
		# Structural concrete slab
		b.add_box(
			Vector3(x_land_ctr, total_rise - slab_thick * 0.5 - 0.015, z_land_ctr),
			Vector3(x_land_w, slab_thick - 0.03, landing_depth),
			mat_conc
		)
		# Top dark stone finish cap flush with total_rise
		b.add_box(
			Vector3(x_land_ctr, total_rise - 0.018, z_land_ctr),
			Vector3(x_land_w + 0.02, 0.036, landing_depth + 0.02),
			mat_tread
		)
	# Recessed 0.08m behind z_end so the ramp's flat top crest overlaps cleanly with zero vertical lip
	var col_ld := maxf(0.4, landing_depth - 0.08)
	var col_z_ctr := z_land_ctr + dir_z * 0.04
	_add_box_collider(
		col_body, "TopLandingCol",
		Vector3(x_land_ctr, total_rise - slab_thick * 0.5, col_z_ctr),
		Vector3(x_land_w, slab_thick, col_ld)
	)

	# 4. Grounded Reinforced Concrete Support Columns (under top landing + mid-span pier)
	var col_sz := 0.24
	var col_h := total_rise - slab_thick
	var z_col_far := z_land_far - dir_z * (col_sz * 0.55)
	var z_col_near := z_end + dir_z * (col_sz * 0.55)
	var col_positions: Array[Vector2] = [
		Vector2(w - col_sz * 0.5, z_col_far),
		Vector2(col_sz * 0.5 + 0.02, z_col_far),
		Vector2(w - col_sz * 0.5, z_col_near),
	]
	for ci in range(col_positions.size()):
		var cp := col_positions[ci]
		if b != null:
			b.add_box(Vector3(cp.x, col_h * 0.5, cp.y), Vector3(col_sz, col_h, col_sz), mat_conc)
			# Ground concrete plinth footing
			b.add_box(Vector3(cp.x, 0.09, cp.y), Vector3(col_sz + 0.10, 0.18, col_sz + 0.10), mat_trim)
		_add_box_collider(col_body, "SupportCol_%d" % ci, Vector3(cp.x, col_h * 0.5, cp.y), Vector3(col_sz, col_h, col_sz))

	# Mid-span brick/concrete support pier directly under the waist slab (zero floating look)
	var z_mid := (z_start + z_end) * 0.5
	var y_mid_soffit := total_rise * 0.5 - slab_thick - 0.04
	if y_mid_soffit > 0.35:
		if b != null:
			b.add_box(Vector3(w * 0.5, y_mid_soffit * 0.5, z_mid), Vector3(w - 0.08, y_mid_soffit, 0.28), mat_trim)
			b.add_box(Vector3(w * 0.5, 0.08, z_mid), Vector3(w, 0.16, 0.36), mat_conc)
		_add_box_collider(col_body, "MidPierCol", Vector3(w * 0.5, y_mid_soffit * 0.5, z_mid), Vector3(w - 0.08, y_mid_soffit, 0.28))

	# 5. Painted Sudanese Iron Handrail along open outer edge (+X) and far top landing edge
	var x_rail := w - 0.045
	# Sloped handrail on open outer side of flight
	_add_sloped_handrail_z(
		b, col_body, "FlightRail",
		x_rail,
		z_start, riser * 0.5,
		z_end, total_rise,
		mat_iron
	)
	# Outer edge of top landing (+X)
	_add_flat_handrail(
		b, col_body, "TopLandingRailOuter",
		Vector3(x_rail, total_rise, z_end),
		Vector3(x_rail, total_rise, z_land_far - dir_z * 0.045),
		mat_iron
	)
	# Far back edge of top landing (closing end perpendicular to wall, leaving -X wall/roof side open!)
	_add_flat_handrail(
		b, col_body, "TopLandingRailEnd",
		Vector3(x_rail, total_rise, z_land_far - dir_z * 0.045),
		Vector3(0.04, total_rise, z_land_far - dir_z * 0.045),
		mat_iron
	)


# ==============================================================================
# STYLE 1: MULTI-STORY 180-DEGREE SWITCHBACK EXTERIOR STAIRCASE (APARTMENTS)
# ==============================================================================
func _build_multi_story_switchback(b: _StairBatcher, col_body: StaticBody3D) -> void:
	if story_heights.size() < 2:
		return

	var w := stair_width
	var gap := center_gap
	var total_w := w * 2.0 + gap
	# Inner lane (against building wall, upper half-flight B): x in [0, w]
	# Outer lane (lower half-flight A): x in [w + gap, total_w]
	var x_in0 := 0.0
	var x_in1 := w
	var x_out0 := w + gap
	var x_out1 := total_w

	var mat_conc := _get_concrete_mat()
	var mat_tread := _get_tread_stone_mat()
	var mat_trim := _get_concrete_trim_mat()
	var mat_iron := _get_iron_handrail_mat()

	var slab_thick := 0.20
	var z_fl_back := -floor_landing_depth * 0.5 # -0.80 (centered on doorway z=0)
	var z_fl_front := floor_landing_depth * 0.5 # +0.80

	# Compute uniform horizontal run from max half-story rise so all flights stack cleanly vertically
	var max_half_rise := 0.0
	for si in range(story_heights.size() - 1):
		max_half_rise = maxf(max_half_rise, (story_heights[si + 1] - story_heights[si]) * 0.5)
	var n_risers := maxi(6, int(round(max_half_rise / maxf(0.15, riser_target))))
	var n_treads := n_risers - 1
	var run := float(n_treads) * tread_depth # ~2.52m for 10 risers

	var z_mid_near := z_fl_front + run # ~+3.32
	var z_mid_far := z_mid_near + mid_landing_depth # ~+4.52

	# Ground entry concrete pad at bottom of Flight 0A
	if b != null:
		b.add_box(Vector3((x_out0 + x_out1) * 0.5, 0.025, z_fl_front - 0.30), Vector3(w + 0.08, 0.05, 0.65), mat_tread)

	# 1. Build each story's switchback pair (Flight A up to Mid-Landing -> 180 deg -> Flight B up to Floor Landing)
	var num_stories := story_heights.size() - 1
	for s in range(num_stories):
		var y0 := story_heights[s]
		var y1 := story_heights[s + 1]
		var y_mid := (y0 + y1) * 0.5

		# Flight A (Outer lane, rises +Z from z_fl_front to z_mid_near)
		_add_flight_z(
			b, col_body, "Story%d_FlightA" % s,
			x_out0, x_out1,
			z_fl_front, y0,
			z_mid_near, y_mid,
			n_risers, tread_depth, slab_thick,
			mat_conc, mat_tread, mat_trim
		)

		# Mid-Landing Slab (connects outer lane to inner lane at y_mid)
		var z_ml_ctr := (z_mid_near + z_mid_far) * 0.5
		if b != null:
			b.add_box(
				Vector3(total_w * 0.5, y_mid - slab_thick * 0.5 - 0.015, z_ml_ctr),
				Vector3(total_w + 0.04, slab_thick - 0.03, mid_landing_depth),
				mat_conc
			)
			b.add_box(
				Vector3(total_w * 0.5, y_mid - 0.018, z_ml_ctr),
				Vector3(total_w + 0.06, 0.036, mid_landing_depth + 0.02),
				mat_tread
			)
			# Cross tie-beam underneath mid-landing
			b.add_box(
				Vector3(total_w * 0.5, y_mid - slab_thick - 0.11, z_mid_far - 0.14),
				Vector3(total_w, 0.22, 0.24),
				mat_conc
			)
		# Recess landing box front face 0.08m behind z_mid_near so Flight A's flat crest & Flight B's start both overlap seamlessly
		var ml_col_d := maxf(0.4, mid_landing_depth - 0.08)
		_add_box_collider(
			col_body, "MidLandingCol_%d" % s,
			Vector3(total_w * 0.5, y_mid - slab_thick * 0.5, z_ml_ctr + 0.04),
			Vector3(total_w + 0.04, slab_thick, ml_col_d)
		)

		# Flight B (Inner lane against building wall, 180-deg turn, rises -Z from z_mid_near to z_fl_front)
		_add_flight_z(
			b, col_body, "Story%d_FlightB" % s,
			x_in0, x_in1,
			z_mid_near, y_mid,
			z_fl_front, y1,
			n_risers, tread_depth, slab_thick,
			mat_conc, mat_tread, mat_trim
		)

		# Upper Floor Landing Slab at y1 (aligned with building doorway z in [-0.80, +0.80])
		var x_fl_min := -0.05
		var x_fl_w := total_w - x_fl_min + 0.02
		var x_fl_ctr := (x_fl_min + total_w + 0.02) * 0.5
		var z_fl_ctr := (z_fl_back + z_fl_front) * 0.5
		if b != null:
			b.add_box(
				Vector3(x_fl_ctr, y1 - slab_thick * 0.5 - 0.015, z_fl_ctr),
				Vector3(x_fl_w, slab_thick - 0.03, floor_landing_depth),
				mat_conc
			)
			b.add_box(
				Vector3(x_fl_ctr, y1 - 0.018, z_fl_ctr),
				Vector3(x_fl_w + 0.02, 0.036, floor_landing_depth + 0.02),
				mat_tread
			)
			# Underside perimeter support beams
			b.add_box(Vector3(x_fl_ctr, y1 - slab_thick - 0.11, z_fl_back + 0.13), Vector3(x_fl_w, 0.22, 0.24), mat_conc)
			b.add_box(Vector3(x_fl_ctr, y1 - slab_thick - 0.11, z_fl_front - 0.13), Vector3(x_fl_w, 0.22, 0.24), mat_conc)
		# Recess front edge of floor landing 0.08m behind z_fl_front so Flight B's flat crest & next Flight A's start both overlap seamlessly
		var fl_col_d := maxf(0.4, floor_landing_depth - 0.08)
		_add_box_collider(
			col_body, "FloorLandingCol_%d" % (s + 1),
			Vector3(x_fl_ctr, y1 - slab_thick * 0.5, z_fl_ctr - 0.04),
			Vector3(x_fl_w, slab_thick, fl_col_d)
		)

		# --- Handrails & Guard Colliders for Story s ---
		var x_outer_rail := total_w - 0.045
		var x_gap_out := x_out0 + 0.04
		var x_gap_in := x_in1 - 0.04
		var riser_s := (y_mid - y0) / float(n_risers)

		# Flight A outer rail (+X) & inner stairwell gap rail
		_add_sloped_handrail_z(b, col_body, "S%d_FA_OuterRail" % s, x_outer_rail, z_fl_front, y0 + riser_s * 0.4, z_mid_near, y_mid, mat_iron)
		_add_sloped_handrail_z(b, col_body, "S%d_FA_GapRail" % s, x_gap_out, z_fl_front, y0 + riser_s * 0.4, z_mid_near, y_mid, mat_iron)

		# Mid-landing outer (+X) and front (+Z) rails
		_add_flat_handrail(b, col_body, "S%d_ML_OuterRail" % s, Vector3(x_outer_rail, y_mid, z_mid_near), Vector3(x_outer_rail, y_mid, z_mid_far - 0.045), mat_iron)
		_add_flat_handrail(b, col_body, "S%d_ML_FrontRail" % s, Vector3(x_outer_rail, y_mid, z_mid_far - 0.045), Vector3(0.05, y_mid, z_mid_far - 0.045), mat_iron)

		# Flight B inner stairwell gap rail (building wall guards x=0 side)
		_add_sloped_handrail_z(b, col_body, "S%d_FB_GapRail" % s, x_gap_in, z_mid_near, y_mid + riser_s * 0.4, z_fl_front, y1, mat_iron)

		# Floor Landing y1 rails: outer (+X) & back (-Z) always guarded (leaving -X doorway open!)
		_add_flat_handrail(b, col_body, "S%d_FL_OuterRail" % s, Vector3(x_outer_rail, y1, z_fl_front), Vector3(x_outer_rail, y1, z_fl_back + 0.045), mat_iron)
		_add_flat_handrail(b, col_body, "S%d_FL_BackRail" % s, Vector3(x_outer_rail, y1, z_fl_back + 0.045), Vector3(0.05, y1, z_fl_back + 0.045), mat_iron)

		# On the topmost landing (Roof), close off the +Z outer lane front edge since no flight continues above!
		if s == num_stories - 1:
			_add_flat_handrail(
				b, col_body, "TopRoofLandingFrontGuard",
				Vector3(x_outer_rail, y1, z_fl_front - 0.045),
				Vector3(x_gap_in, y1, z_fl_front - 0.045),
				mat_iron
			)

	# 2. Four Full-Height Reinforced Concrete Support Columns reaching ground y = 0.0
	# Placed just outside the clear walking lanes so 100% of every flight & landing is unobstructed
	var top_y := story_heights[story_heights.size() - 1]
	var col_sz := 0.26
	var col_h := top_y + 0.04
	var x_col_outer := total_w + col_sz * 0.5
	var z_col_mid := z_mid_far + col_sz * 0.5
	var col_coords: Array[Vector2] = [
		Vector2(x_col_outer, z_fl_back + col_sz * 0.5),   # Outer back floor landing
		Vector2(x_col_outer, z_fl_front - col_sz * 0.5),  # Outer front floor landing
		Vector2(x_col_outer, z_col_mid),                  # Outer mid-landing corner
		Vector2(col_sz * 0.5 + 0.02, z_col_mid),          # Wall-side mid-landing corner
	]
	for ci in range(col_coords.size()):
		var cc := col_coords[ci]
		if b != null:
			b.add_box(Vector3(cc.x, col_h * 0.5, cc.y), Vector3(col_sz, col_h, col_sz), mat_conc)
			b.add_box(Vector3(cc.x, 0.10, cc.y), Vector3(col_sz + 0.12, 0.20, col_sz + 0.12), mat_trim)
			# Corbel brackets tying outer columns into each floor & mid landing slab
			for si in range(1, story_heights.size()):
				var sy := story_heights[si]
				var sm := (story_heights[si - 1] + sy) * 0.5
				if ci < 2:
					b.add_box(Vector3(cc.x - col_sz * 0.4, sy - slab_thick * 0.5, cc.y), Vector3(col_sz * 1.2, slab_thick, col_sz + 0.04), mat_conc)
				else:
					b.add_box(Vector3(cc.x, sm - slab_thick * 0.5, cc.y - col_sz * 0.4), Vector3(col_sz + 0.04, slab_thick, col_sz * 1.2), mat_conc)
		_add_box_collider(col_body, "SwitchbackCol_%d" % ci, Vector3(cc.x, col_h * 0.5, cc.y), Vector3(col_sz, col_h, col_sz))


# ==============================================================================
# STYLE 2: LOW ARCHITECTURAL STEPS (CORNICHE PROMENADE / BUS STATION PLATFORM)
# ==============================================================================
func _build_low_steps(b: _StairBatcher, col_body: StaticBody3D) -> void:
	var dir_z: float = -1.0 if climb_dir_z < 0.0 else 1.0
	var w := stair_width
	var mat_conc := _get_concrete_mat()
	var mat_tread := _get_tread_stone_mat()
	var mat_trim := _get_concrete_trim_mat()
	var mat_iron := _get_iron_handrail_mat()

	var n_steps := maxi(2, low_step_count)
	var step_tread := low_step_run / float(n_steps)
	var riser := total_rise / float(n_steps)
	var z_start := 0.0
	var z_end := dir_z * low_step_run

	if b != null:
		# Solid stepped masonry base resting flush on ground y=0 (zero floating!)
		for i in range(n_steps):
			var y_top := (float(i) + 1.0) * riser
			var z_f := z_start + dir_z * (float(i) * step_tread)
			var z_b := z_start + dir_z * (float(i + 1) * step_tread)
			var z_ctr := (z_f + z_b) * 0.5
			var body_h := maxf(0.04, y_top - 0.032)
			b.add_box(Vector3(0.0, body_h * 0.5, z_ctr), Vector3(w, body_h, step_tread + 0.01), mat_conc)
			b.add_box(Vector3(0.0, y_top - 0.016, z_ctr - dir_z * 0.012), Vector3(w + 0.02, 0.032, step_tread + 0.025), mat_tread)
		# Low side stone cheek curbs
		for side: float in [-1.0, 1.0]:
			var sx := side * (w * 0.5 + 0.06)
			b.add_sloped_prism_z(
				sx - 0.06, sx + 0.06,
				z_start, 0.0, riser + 0.04,
				z_end, 0.0, total_rise + 0.04,
				mat_trim
			)

	# Smooth sloped ConvexPolygonShape3D ramp across full width [-w/2, +w/2]
	_add_ramp_convex_collider(
		col_body, "LowStepsRamp",
		-w * 0.5 - 0.04, w * 0.5 + 0.04,
		z_start - dir_z * 0.08, 0.0,
		z_end + dir_z * 0.05, total_rise,
		0.18
	)

	if low_step_add_handrails:
		for side: float in [-1.0, 1.0]:
			_add_sloped_handrail_z(
				b, col_body, "LowStepRail_%s" % ("L" if side < 0.0 else "R"),
				side * (w * 0.5 + 0.04),
				z_start, riser * 0.5,
				z_end, total_rise,
				mat_iron
			)


# ==============================================================================
# SHARED FLIGHT, HANDRAIL & COLLIDER HELPERS
# ==============================================================================
func _add_flight_z(
	b: _StairBatcher,
	col_body: StaticBody3D,
	prefix: String,
	x0: float, x1: float,
	z_start: float, y_start: float,
	z_end: float, y_end: float,
	n_risers: int,
	tread: float,
	slab_thick: float,
	mat_conc: Material,
	mat_tread: Material,
	mat_trim: Material
) -> void:
	var dir_z: float = 1.0 if z_end >= z_start else -1.0
	var width := x1 - x0
	var x_ctr := (x0 + x1) * 0.5
	var riser := (y_end - y_start) / float(n_risers)
	var n_treads := n_risers - 1

	if b != null:
		# 1. Continuous sloped concrete waist slab (بلاطة خرسانية مائلة) underneath all steps
		var y_bot_start := maxf(0.0, y_start - slab_thick)
		var y_bot_end := y_end - slab_thick
		b.add_sloped_prism_z(
			x0, x1,
			z_start, y_bot_start, y_start + 0.02,
			z_end, y_bot_end, y_end - riser + 0.02,
			mat_conc
		)

		# Optional framed outer brick/concrete stringer trim cheek along the open outer side
		b.add_sloped_prism_z(
			x1 - 0.05, x1 + 0.015,
			z_start, y_bot_start, y_start + riser * 0.85,
			z_end, y_bot_end, y_end,
			mat_trim
		)

		# 2. Individual grounded concrete steps + darker stone/cement tread nosings
		var nosing_h := 0.036
		var nosing_overhang := 0.024
		for i in range(n_treads):
			var y_step_top := y_start + float(i + 1) * riser
			var y_step_bot := maxf(y_start, y_start + float(i) * riser - 0.04)
			var step_body_h := maxf(0.03, (y_step_top - nosing_h) - y_step_bot)
			var z_f := z_start + dir_z * (float(i) * tread)
			var z_b := z_start + dir_z * (float(i + 1) * tread)
			var z_ctr := (z_f + z_b) * 0.5

			# Concrete riser/step core
			b.add_box(
				Vector3(x_ctr, y_step_bot + step_body_h * 0.5, z_ctr),
				Vector3(width, step_body_h, tread + 0.02),
				mat_conc
			)
			# Darker stone/cement tread slab with clean front nosing overhang
			b.add_box(
				Vector3(x_ctr, y_step_top - nosing_h * 0.5, z_ctr - dir_z * (nosing_overhang * 0.5)),
				Vector3(width + 0.02, nosing_h, tread + nosing_overhang),
				mat_tread
			)

	# 3. Smooth Sloped Ramp ConvexPolygonShape3D with flat top crest (zero vertical lip at landing!)
	_add_ramp_convex_collider(
		col_body, prefix + "_RampCol",
		x0, x1,
		z_start - dir_z * 0.10, y_start,
		z_end, y_end,
		slab_thick,
		dir_z * 0.30
	)


func _add_ramp_convex_collider(
	col_body: StaticBody3D,
	cname: String,
	x0: float, x1: float,
	za: float, ya_top: float,
	zb: float, yb_top: float,
	thickness: float,
	top_crest_ext_z: float = 0.0
) -> void:
	var shape := ConvexPolygonShape3D.new()
	var ya_bot := ya_top - thickness
	var yb_bot := yb_top - thickness
	var pts := PackedVector3Array([
		Vector3(x0, ya_bot, za),
		Vector3(x1, ya_bot, za),
		Vector3(x0, ya_top, za),
		Vector3(x1, ya_top, za),
		Vector3(x0, yb_bot, zb),
		Vector3(x1, yb_bot, zb),
		Vector3(x0, yb_top, zb),
		Vector3(x1, yb_top, zb),
	])
	if absf(top_crest_ext_z) > 0.005:
		var zc := zb + top_crest_ext_z
		pts.append(Vector3(x0, yb_bot, zc))
		pts.append(Vector3(x1, yb_bot, zc))
		pts.append(Vector3(x0, yb_top, zc))
		pts.append(Vector3(x1, yb_top, zc))
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.name = cname
	cs.shape = shape
	col_body.add_child(cs)


func _add_sloped_handrail_z(
	b: _StairBatcher,
	col_body: StaticBody3D,
	cname: String,
	x_pos: float,
	z0: float, y0: float,
	z1: float, y1: float,
	mat_iron: Material
) -> void:
	var rail_h := 0.95
	var mid_h := 0.50
	var p0_top := Vector3(x_pos, y0 + rail_h, z0)
	var p1_top := Vector3(x_pos, y1 + rail_h, z1)
	var p0_mid := Vector3(x_pos, y0 + mid_h, z0)
	var p1_mid := Vector3(x_pos, y1 + mid_h, z1)

	if b != null:
		# Continuous sloped top handrail bar & mid safety rail
		b.add_bar(p0_top, p1_top, 0.048, 0.042, mat_iron)
		b.add_bar(p0_mid, p1_mid, 0.032, 0.028, mat_iron)

		# Vertical steel balusters spaced every ~0.85m
		var horiz_len := absf(z1 - z0)
		var segs := maxi(2, int(round(horiz_len / 0.85)))
		for i in range(segs + 1):
			var t := float(i) / float(segs)
			var zb := lerpf(z0, z1, t)
			var yb := lerpf(y0, y1, t)
			var post_w := 0.042 if (i == 0 or i == segs) else 0.030
			b.add_box(Vector3(x_pos, yb + rail_h * 0.5, zb), Vector3(post_w, rail_h + 0.06, post_w), mat_iron)

	# Sloped side guard collider so players & NPCs cannot fall off the open side
	_add_ramp_convex_collider(
		col_body, cname + "_GuardCol",
		x_pos - 0.045, x_pos + 0.045,
		z0, y0 + rail_h,
		z1, y1 + rail_h,
		rail_h
	)


func _add_flat_handrail(
	b: _StairBatcher,
	col_body: StaticBody3D,
	cname: String,
	p0: Vector3,
	p1: Vector3,
	mat_iron: Material
) -> void:
	var rail_h := 0.95
	var mid_h := 0.50
	var span := p0.distance_to(p1)
	if span < 0.08:
		return

	if b != null:
		b.add_bar(p0 + Vector3(0.0, rail_h, 0.0), p1 + Vector3(0.0, rail_h, 0.0), 0.048, 0.042, mat_iron)
		b.add_bar(p0 + Vector3(0.0, mid_h, 0.0), p1 + Vector3(0.0, mid_h, 0.0), 0.032, 0.028, mat_iron)
		var segs := maxi(1, int(round(span / 0.85)))
		for i in range(segs + 1):
			var t := float(i) / float(segs)
			var pt := p0.lerp(p1, t)
			var pw := 0.042 if (i == 0 or i == segs) else 0.030
			b.add_box(pt + Vector3(0.0, rail_h * 0.5, 0.0), Vector3(pw, rail_h + 0.04, pw), mat_iron)

	# Horizontal BoxShape3D guard collider along landing railing
	var ctr := (p0 + p1) * 0.5 + Vector3(0.0, rail_h * 0.5, 0.0)
	var dx := absf(p1.x - p0.x)
	var dz := absf(p1.z - p0.z)
	var box_sz := Vector3(maxf(0.09, dx), rail_h, maxf(0.09, dz))
	_add_box_collider(col_body, cname + "_GuardCol", ctr, box_sz)


func _add_box_collider(col_body: StaticBody3D, cname: String, center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = cname
	cs.position = center
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	col_body.add_child(cs)


# ==============================================================================
# SHARED SUDANESE ARCHITECTURAL MATERIALS (WITH PBR PLASTER / BRICK TEXTURES)
# ==============================================================================
static func _apply_pbr_tex(m: StandardMaterial3D, base_dir: String, uv_scale: Vector3, n_scale: float = 0.65) -> void:
	var alb := base_dir + "/albedo.jpg"
	var nor := base_dir + "/normal.jpg"
	var rgh := base_dir + "/roughness.jpg"
	if ResourceLoader.exists(alb):
		m.albedo_texture = ResourceLoader.load(alb) as Texture2D
	if ResourceLoader.exists(nor):
		m.normal_enabled = true
		m.normal_scale = n_scale
		m.normal_texture = ResourceLoader.load(nor) as Texture2D
	if ResourceLoader.exists(rgh):
		m.roughness_texture = ResourceLoader.load(rgh) as Texture2D
	m.uv1_triplanar = true
	m.uv1_scale = uv_scale


static func _get_concrete_mat() -> StandardMaterial3D:
	if _mat_cache.has("concrete"):
		return _mat_cache["concrete"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.84, 0.79, 0.70) # Warm Khartoum exterior cement plaster
	m.roughness = 0.90
	m.metallic = 0.0
	_apply_pbr_tex(m, "res://assets/textures/plaster", Vector3(0.45, 0.45, 0.45), 0.55)
	_mat_cache["concrete"] = m
	return m


static func _get_tread_stone_mat() -> StandardMaterial3D:
	if _mat_cache.has("tread_stone"):
		return _mat_cache["tread_stone"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.50, 0.48, 0.44) # Darker stone / troweled cement tread nosings
	m.roughness = 0.84
	m.metallic = 0.02
	_apply_pbr_tex(m, "res://assets/textures/plaster", Vector3(0.65, 0.65, 0.65), 0.70)
	_mat_cache["tread_stone"] = m
	return m


static func _get_brick_masonry_mat() -> StandardMaterial3D:
	if _mat_cache.has("brick"):
		return _mat_cache["brick"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.50, 0.36) # Authentic Sudanese red-ochre kiln brick masonry
	m.roughness = 0.92
	m.metallic = 0.0
	_apply_pbr_tex(m, "res://assets/textures/brick", Vector3(0.55, 0.55, 0.55), 0.75)
	_mat_cache["brick"] = m
	return m


static func _get_concrete_trim_mat() -> StandardMaterial3D:
	if _mat_cache.has("trim"):
		return _mat_cache["trim"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.70, 0.66, 0.59) # Structural concrete trim & column plinths
	m.roughness = 0.88
	m.metallic = 0.0
	_apply_pbr_tex(m, "res://assets/textures/plaster", Vector3(0.5, 0.5, 0.5), 0.60)
	_mat_cache["trim"] = m
	return m


static func _get_iron_handrail_mat() -> StandardMaterial3D:
	if _mat_cache.has("iron"):
		return _mat_cache["iron"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.14, 0.19, 0.22) # Painted Sudanese charcoal-slate steel handrail
	m.roughness = 0.40
	m.metallic = 0.68
	_mat_cache["iron"] = m
	return m
