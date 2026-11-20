extends RefCounted
class_name VehiclePackSetup

## Adapts `res://assets/models/vehicles/pack/*.fbx` vehicle models & wheels onto
## VehicleController scenes cleanly with:
## - Intact, uncluttered 3D chassis (zero procedural bullbars, sticks, cages, or floating door boxes)
## - Clean exterior paint (`metallic = 0.0`, `roughness = 0.65`) & semi-transparent windows (`alpha = 0.30`)
## - Separated spinning & steering wheels (`Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR` / 3 for Raksha)
## - Tires resting squarely at road level (`y = 0.0`)
## - Compact flush lower-bumper license plates & seated cabin alignment below roof

const BICYCLE_PACK_PATH: String = "res://assets/models/vehicles/pack/Bicycle.fbx"
const BICYCLE_PACK_SCENE: PackedScene = preload("res://assets/models/vehicles/pack/Bicycle.fbx")

# Explicit preload() map so Godot's Web exporter bundles all vehicle FBX bodies & wheels in index.pck.
const PACK_VEHICLE_SCENES: Dictionary = {
	"res://assets/models/vehicles/pack/Ambulance.fbx": preload("res://assets/models/vehicles/pack/Ambulance.fbx"),
	"res://assets/models/vehicles/pack/Bus.fbx": preload("res://assets/models/vehicles/pack/Bus.fbx"),
	"res://assets/models/vehicles/pack/NormalCar1.fbx": preload("res://assets/models/vehicles/pack/NormalCar1.fbx"),
	"res://assets/models/vehicles/pack/NormalCar2.fbx": preload("res://assets/models/vehicles/pack/NormalCar2.fbx"),
	"res://assets/models/vehicles/pack/SUV.fbx": preload("res://assets/models/vehicles/pack/SUV.fbx"),
	"res://assets/models/vehicles/pack/SchoolBus.fbx": preload("res://assets/models/vehicles/pack/SchoolBus.fbx"),
	"res://assets/models/vehicles/pack/SportsCar2.fbx": preload("res://assets/models/vehicles/pack/SportsCar2.fbx"),
	"res://assets/models/vehicles/pack/Taxi.fbx": preload("res://assets/models/vehicles/pack/Taxi.fbx"),
}


static func _get_packed_vehicle_scene(veh: VehicleController) -> PackedScene:
	if veh.pack_model_scene != null:
		return veh.pack_model_scene
	var pack_path := veh.pack_model_path
	if PACK_VEHICLE_SCENES.has(pack_path):
		return PACK_VEHICLE_SCENES[pack_path] as PackedScene
	if not pack_path.is_empty() and ResourceLoader.exists(pack_path):
		return ResourceLoader.load(pack_path) as PackedScene
	return null


static func apply_to_vehicle(veh: VehicleController) -> Dictionary:
	var out := {
		"wheel_spin_nodes": [] as Array[Node3D],
		"front_steer_pivots": [] as Array[Node3D],
		"headlight_mats": [] as Array[StandardMaterial3D],
		"taillight_mats": [] as Array[StandardMaterial3D],
		"reverselight_mats": [] as Array[StandardMaterial3D],
		"steering_wheel": null,
	}
	if veh == null or veh.body_visuals == null:
		return out

	var kw := veh.vehicle_name.to_lower()
	if veh.is_three_wheeler:
		_setup_raksha_pack_parts(veh, out)
		_calibrate_seats_and_build_interior(veh, out, Vector3(1.50, 1.82, 2.52))
		_fix_plates_and_signs(veh, -1.24, 1.24, 1.34, 1.72)
		return out

	var pack_path := veh.pack_model_path
	var packed := _get_packed_vehicle_scene(veh)
	if packed == null:
		_calibrate_seats_and_build_interior(veh, out, Vector3(1.82, 1.75, 4.16))
		_fix_plates_and_signs(veh, -2.08, 2.08, 1.82, 1.75)
		return out
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return out

	# Strip ALL legacy procedural body/bumper/cage/rack/stick boxes — keep ONLY compact plates & route signs
	var keep_prefixes := ["LicensePlate", "RouteSign"]
	for ch in veh.body_visuals.get_children():
		var keep := false
		for pref in keep_prefixes:
			if ch.name.begins_with(pref):
				keep = true
				break
		if not keep:
			ch.queue_free()

	# Align pack coordinate system so headlights point -Z and lowest wheel bottom sits at Y = 0
	var yaw_offset := _detect_yaw_to_neg_z(inst, pack_path)
	var raw_aabb := _compute_local_aabb(inst, yaw_offset)
	var cur_len := maxf(raw_aabb.size.z, 0.001)
	var tgt_len := veh.pack_target_length if veh.pack_target_length > 0.5 else cur_len
	var scale_f := tgt_len / cur_len
	var scale_vec := Vector3.ONE * scale_f
	if veh.is_bus:
		scale_vec = Vector3(scale_f * 0.64, scale_f * 0.80, scale_f)
	elif "sedan" in kw or "taxi" in kw or "private" in kw:
		scale_vec = Vector3(scale_f * 0.88, scale_f * 1.18, scale_f)

	var pack_root := Node3D.new()
	pack_root.name = "PackVehicleRoot"
	veh.body_visuals.add_child(pack_root)

	var aligned_holder := Node3D.new()
	aligned_holder.name = "AlignedPackMesh"
	aligned_holder.scale = scale_vec
	var cx := (raw_aabb.position.x + raw_aabb.size.x * 0.5) * scale_vec.x
	var cz := (raw_aabb.position.z + raw_aabb.size.z * 0.5) * scale_vec.z
	var min_y := raw_aabb.position.y * scale_vec.y
	aligned_holder.position = Vector3(-cx, -min_y, -cz)

	var rot_holder := Node3D.new()
	rot_holder.name = "YawAligned"
	rot_holder.rotation.y = yaw_offset
	rot_holder.add_child(inst)
	aligned_holder.add_child(rot_holder)
	pack_root.add_child(aligned_holder)

	# Process body surfaces & extract clean wheel meshes before hiding fused axle meshes
	var wheel_meshes: Array[Dictionary] = []
	var meshes := _collect_meshes(inst)
	for mi in meshes:
		mi.visible = true
		var lname := mi.name.to_lower()
		if "wheel" in lname:
			wheel_meshes.append({"mi": mi, "lname": lname})
			mi.visible = false
		else:
			_apply_pack_body_materials(mi, veh, out)

	# Reconstruct 4 independent spinning/steering wheels (`Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR`)
	_build_four_wheels_from_pack(veh, pack_root, wheel_meshes, raw_aabb, scale_vec, yaw_offset, out)

	# Calibrate driver & passenger seat heights, build solid cabin floor, cushioned seats & steering wheel
	var roof_y := raw_aabb.size.y * scale_vec.y
	var body_len := raw_aabb.size.z * scale_vec.z
	var body_wid := raw_aabb.size.x * scale_vec.x
	_calibrate_seats_and_build_interior(veh, out, Vector3(body_wid, roof_y, body_len))
	_fix_plates_and_signs(veh, -body_len * 0.5, body_len * 0.5, body_wid, roof_y)
	return out


static func _setup_raksha_pack_parts(veh: VehicleController, out: Dictionary) -> void:
	var packed := BICYCLE_PACK_SCENE
	if packed == null:
		return
	var bike := packed.instantiate()
	var wheel_mesh: Mesh = null
	var handle_mesh: Mesh = null
	for mi in _collect_meshes(bike):
		var ln := mi.name.to_lower()
		if wheel_mesh == null and ("frontwheel" in ln or "backwheel" in ln):
			wheel_mesh = mi.mesh
		elif handle_mesh == null and "handle" in ln:
			handle_mesh = mi.mesh

	if wheel_mesh != null:
		var wheel_targets := [
			{"parent_name": "FrontSteer", "hub_name": "Wheel_Front", "is_front": true},
			{"parent_name": "FrontSteerF", "hub_name": "Wheel_Front", "is_front": true},
			{"parent_name": "RearWheelL", "hub_name": "Wheel_RL", "is_front": false},
			{"parent_name": "RearWheelR", "hub_name": "Wheel_RR", "is_front": false},
		]
		var w_center := wheel_mesh.get_aabb().get_center()
		var w_scale := 0.56 / maxf(wheel_mesh.get_aabb().size.y, 0.01)
		for wt in wheel_targets:
			var parent_n := veh.get_node_or_null(String(wt["parent_name"])) as Node3D
			if parent_n == null:
				continue
			for c in parent_n.get_children():
				if c is MeshInstance3D:
					c.visible = false
				else:
					for gc in c.get_children():
						if gc is MeshInstance3D:
							gc.visible = false
			var hub := Node3D.new()
			hub.name = String(wt["hub_name"])
			var wmi := MeshInstance3D.new()
			wmi.mesh = wheel_mesh
			wmi.scale = Vector3(w_scale, w_scale, w_scale * 2.4)
			wmi.rotation.y = PI * 0.5
			wmi.position = -Vector3(0.0, w_center.y * w_scale, w_center.x * w_scale)
			_brighten_mesh_materials(wmi, Color(0.14, 0.14, 0.15, 1.0))
			hub.add_child(wmi)
			parent_n.add_child(hub)
			out["wheel_spin_nodes"].append(hub)
			if wt["is_front"]:
				out["front_steer_pivots"].append(parent_n)

	if handle_mesh != null:
		var sw := Node3D.new()
		sw.name = "SteeringWheel"
		sw.position = Vector3(0.0, veh.driver_seat_offset.y + 0.28, -0.56)
		var hmi := MeshInstance3D.new()
		hmi.mesh = handle_mesh
		hmi.scale = Vector3.ONE * (0.46 / maxf(handle_mesh.get_aabb().size.x, 0.01))
		_brighten_mesh_materials(hmi, Color(0.16, 0.17, 0.19, 1.0))
		sw.add_child(hmi)
		veh.body_visuals.add_child(sw)
		out["steering_wheel"] = sw

	# Clean bright exterior paint (`metallic = 0.0`, `roughness = 0.65`) and tinted glass (`alpha = 0.30`)
	for ch in veh.body_visuals.get_children():
		if ch is MeshInstance3D:
			var mi := ch as MeshInstance3D
			var mat := mi.get_active_material(0)
			if mat is BaseMaterial3D:
				var nm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				nm.metallic = 0.0
				nm.vertex_color_use_as_albedo = false
				if "windshield" in mi.name.to_lower() or "win" in mi.name.to_lower():
					nm.albedo_color = Color(0.55, 0.72, 0.84, 0.30)
					nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					nm.cull_mode = BaseMaterial3D.CULL_DISABLED
					nm.roughness = 0.14
				else:
					nm.roughness = 0.65
					nm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					nm.cull_mode = BaseMaterial3D.CULL_BACK
				mi.material_override = nm

	bike.free()


static func _detect_yaw_to_neg_z(_inst: Node3D, pack_path: String) -> float:
	var low := pack_path.to_lower()
	# Bus.fbx / SchoolBus.fbx front grille & windshield face -X natively -> -90 deg maps -X to -Z
	if "bus.fbx" in low:
		return -PI * 0.5
	# SUV, Cars, Taxi, Ambulance face +Z natively -> 180 deg maps +Z to -Z
	return PI


static func _compute_local_aabb(inst: Node3D, yaw_rot: float) -> AABB:
	var rot_xform := Transform3D(Basis(Vector3.UP, yaw_rot), Vector3.ZERO)
	var combined := AABB()
	var first := true
	for mi in _collect_meshes(inst):
		var local_xf := rot_xform * _get_rel_transform(inst, mi)
		var a := local_xf * mi.get_aabb()
		if first:
			combined = a
			first = false
		else:
			combined = combined.merge(a)
	return combined


static func _get_rel_transform(root_n: Node3D, target: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = target
	while cur != null and cur != root_n:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	if cur == root_n:
		xf = root_n.transform * xf
	return xf


static func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var list: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		list.append(node as MeshInstance3D)
	for c in node.get_children():
		list.append_array(_collect_meshes(c))
	return list


static func _apply_pack_body_materials(mi: MeshInstance3D, veh: VehicleController, out: Dictionary) -> void:
	if mi.mesh == null:
		return
	var kw := veh.vehicle_name.to_lower()
	for si in range(mi.mesh.get_surface_count()):
		var orig := mi.mesh.surface_get_material(si)
		var mname := orig.resource_name.to_lower() if orig != null else ""
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = false
		mat.metallic = 0.0
		mat.roughness = 0.65
		if orig is BaseMaterial3D:
			var obm := orig as BaseMaterial3D
			mat.albedo_color = obm.albedo_color
			mat.albedo_texture = obm.albedo_texture

		if "window" in mname or "glass" in mname:
			mat.albedo_color = Color(0.55, 0.72, 0.84, 0.30)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.roughness = 0.14
		elif "headlight" in mname or mname == "lights" or "whitelights" in mname:
			mat.albedo_color = Color(1.0, 0.97, 0.86, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.93, 0.72, 1.0)
			mat.emission_energy_multiplier = 0.25
			out["headlight_mats"].append(mat)
		elif "taillight" in mname:
			mat.albedo_color = Color(0.88, 0.14, 0.12, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.95, 0.12, 0.08, 1.0)
			mat.emission_energy_multiplier = 0.18
			out["taillight_mats"].append(mat)
		else:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
			# Clean Sudanese liveries per vehicle type
			if "amjad" in kw:
				if "red" in mname:
					mat.albedo_color = veh.pack_stripe_color
				elif "bumper" in mname or "grey" in mname:
					mat.albedo_color = Color(0.28, 0.29, 0.31, 1.0)
				else:
					mat.albedo_color = Color(0.98, 0.98, 0.97, 1.0)
			elif "bus" in kw:
				if mname in ["bottom", "details"]:
					mat.albedo_color = veh.pack_stripe_color
				elif "bumper" in mname:
					mat.albedo_color = Color(0.24, 0.25, 0.27, 1.0)
				else:
					mat.albedo_color = Color(0.98, 0.97, 0.94, 1.0)
			elif "daffar" in kw:
				if "yellow" in mname or mname == "material":
					mat.albedo_color = veh.pack_paint_color
				elif "details" in mname:
					mat.albedo_color = veh.pack_stripe_color
				elif "bumper" in mname:
					mat.albedo_color = Color(0.24, 0.25, 0.27, 1.0)
			elif "boks" in kw:
				if "black" in mname or "grey" in mname:
					mat.albedo_color = Color(0.24, 0.25, 0.27, 1.0)
				else:
					mat.albedo_color = Color(0.98, 0.98, 0.97, 1.0)
			elif "sedan" in kw or "taxi" in kw or "private" in kw:
				if mname in ["blue", "lightblue", "yellow", "white", "orange", "darkorange"]:
					mat.albedo_color = veh.pack_paint_color
				elif "black" in mname or "grey" in mname:
					mat.albedo_color = Color(0.24, 0.25, 0.27, 1.0)

		mi.set_surface_override_material(si, mat)


static func _brighten_mesh_materials(mi: MeshInstance3D, fallback_col: Color) -> void:
	if mi.mesh == null:
		return
	for si in range(mi.mesh.get_surface_count()):
		var orig := mi.mesh.surface_get_material(si)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = false
		mat.metallic = 0.0
		mat.roughness = 0.65
		if orig is BaseMaterial3D and (orig as BaseMaterial3D).albedo_color.v > 0.05:
			mat.albedo_color = (orig as BaseMaterial3D).albedo_color
		else:
			mat.albedo_color = fallback_col
		mi.set_surface_override_material(si, mat)


static func _build_four_wheels_from_pack(
	veh: VehicleController,
	pack_root: Node3D,
	wheel_meshes: Array[Dictionary],
	raw_aabb: AABB,
	scale_vec: Vector3,
	yaw_offset: float,
	out: Dictionary
) -> void:
	for ch in veh.get_children():
		if ch.name.begins_with("FrontSteer") or ch.name.begins_with("RearWheel") or ch.name.begins_with("Wheel"):
			ch.visible = false

	var cx := (raw_aabb.position.x + raw_aabb.size.x * 0.5) * scale_vec.x
	var cz := (raw_aabb.position.z + raw_aabb.size.z * 0.5) * scale_vec.z
	var min_y := raw_aabb.position.y * scale_vec.y
	var offset_v := Vector3(-cx, -min_y, -cz)
	var wheel_scale_f := minf(scale_vec.y, scale_vec.z)
	var body_basis := Basis.from_scale(scale_vec) * Basis(Vector3.UP, yaw_offset)
	var wheel_rot_basis := Basis.from_scale(Vector3.ONE * wheel_scale_f) * Basis(Vector3.UP, yaw_offset)

	var sample_fl: Mesh = null
	var fl_basis := wheel_rot_basis
	var front_z := -raw_aabb.size.z * scale_vec.z * 0.30
	var rear_z := raw_aabb.size.z * scale_vec.z * 0.30
	var half_x := raw_aabb.size.x * scale_vec.x * 0.41

	for wm in wheel_meshes:
		var mi: MeshInstance3D = wm["mi"]
		var ln: String = wm["lname"]
		var pr_xf := Transform3D(body_basis, offset_v) * mi.transform
		var ga := pr_xf * mi.get_aabb()
		var center := ga.get_center()
		if "frontleft" in ln:
			sample_fl = mi.mesh
			fl_basis = wheel_rot_basis * mi.transform.basis
			front_z = center.z
			half_x = maxf(absf(center.x), half_x)
		elif "frontwheels" in ln or ("front" in ln and sample_fl == null):
			front_z = center.z
			half_x = maxf(ga.size.x * 0.42, 0.55)
			sample_fl = _extract_half_wheel_mesh(mi.mesh, mi.transform, yaw_offset, true)
			fl_basis = Basis.from_scale(Vector3.ONE * wheel_scale_f)
		elif "backwheels" in ln or "rear" in ln:
			rear_z = center.z
			if sample_fl == null:
				sample_fl = _extract_half_wheel_mesh(mi.mesh, mi.transform, yaw_offset, true)
				fl_basis = Basis.from_scale(Vector3.ONE * wheel_scale_f)

	var veh_half_w := raw_aabb.size.x * scale_vec.x * 0.43
	half_x = clampf(half_x, 0.55, veh_half_w)

	if sample_fl == null:
		return

	var centered_mesh := _center_mesh_to_basis(sample_fl, fl_basis)
	var wheel_r := centered_mesh.get_aabb().size.y * 0.5
	var wheel_y := maxf(wheel_r, 0.24)

	var specs := [
		{"name": "Wheel_FL", "steer": true, "pos": Vector3(-half_x, wheel_y, front_z), "flip_x": false},
		{"name": "Wheel_FR", "steer": true, "pos": Vector3(half_x, wheel_y, front_z), "flip_x": true},
		{"name": "Wheel_RL", "steer": false, "pos": Vector3(-half_x, wheel_y, rear_z), "flip_x": false},
		{"name": "Wheel_RR", "steer": false, "pos": Vector3(half_x, wheel_y, rear_z), "flip_x": true},
	]
	for sp in specs:
		var pivot := Node3D.new()
		pivot.name = ("Steer_" if sp["steer"] else "") + String(sp["name"])
		pivot.position = sp["pos"]
		pack_root.add_child(pivot)

		var hub := Node3D.new()
		hub.name = String(sp["name"])
		pivot.add_child(hub)

		var wmi := MeshInstance3D.new()
		wmi.mesh = centered_mesh
		if sp["flip_x"]:
			wmi.rotation.y = PI
		_brighten_mesh_materials(wmi, Color(0.14, 0.14, 0.15, 1.0))
		hub.add_child(wmi)

		out["wheel_spin_nodes"].append(hub)
		if sp["steer"]:
			out["front_steer_pivots"].append(pivot)


static func _extract_half_wheel_mesh(mesh: Mesh, local_xf: Transform3D, yaw_offset: float, take_neg_x: bool) -> Mesh:
	var rot := Transform3D(Basis(Vector3.UP, yaw_offset), Vector3.ZERO) * local_xf
	var arr := ArrayMesh.new()
	for si in range(mesh.get_surface_count()):
		var sa := mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = sa[Mesh.ARRAY_NORMAL] if sa[Mesh.ARRAY_NORMAL] else PackedVector3Array()
		var idx: PackedInt32Array = sa[Mesh.ARRAY_INDEX] if sa[Mesh.ARRAY_INDEX] else PackedInt32Array()
		if idx.is_empty():
			for vi in range(vs.size()):
				idx.append(vi)
		var out_v := PackedVector3Array()
		var out_n := PackedVector3Array()
		var min_x := 1e9
		var max_x := -1e9
		for v in vs:
			var p := rot * v
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
		var mid_x := 0.5 * (min_x + max_x)
		for ti in range(0, idx.size(), 3):
			var p0 := rot * vs[idx[ti]]
			var p1 := rot * vs[idx[ti + 1]]
			var p2 := rot * vs[idx[ti + 2]]
			var cx := (p0.x + p1.x + p2.x) / 3.0
			if (take_neg_x and cx <= mid_x) or (not take_neg_x and cx >= mid_x):
				out_v.append_array([p0, p1, p2])
				if not ns.is_empty():
					var b := rot.basis
					out_n.append_array([
						(b * ns[idx[ti]]).normalized(),
						(b * ns[idx[ti + 1]]).normalized(),
						(b * ns[idx[ti + 2]]).normalized(),
					])
		if out_v.size() >= 3:
			var nsa := []
			nsa.resize(Mesh.ARRAY_MAX)
			nsa[Mesh.ARRAY_VERTEX] = out_v
			if out_n.size() == out_v.size():
				nsa[Mesh.ARRAY_NORMAL] = out_n
			arr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, nsa)
			var orig := mesh.surface_get_material(si)
			if orig:
				arr.surface_set_material(arr.get_surface_count() - 1, orig)
	return arr if arr.get_surface_count() > 0 else mesh


static func _center_mesh_to_basis(mesh: Mesh, basis_xf: Basis) -> Mesh:
	var mdt_arr := ArrayMesh.new()
	var xf := Transform3D(basis_xf, Vector3.ZERO)
	var b := xf * mesh.get_aabb()
	var c := b.get_center()
	for si in range(mesh.get_surface_count()):
		var sa := mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = sa[Mesh.ARRAY_NORMAL] if sa[Mesh.ARRAY_NORMAL] else PackedVector3Array()
		var out_v := PackedVector3Array()
		var out_n := PackedVector3Array()
		for i in range(vs.size()):
			out_v.append((xf * vs[i]) - c)
			if i < ns.size():
				out_n.append((basis_xf * ns[i]).normalized())
		var nsa := []
		nsa.resize(Mesh.ARRAY_MAX)
		nsa[Mesh.ARRAY_VERTEX] = out_v
		if out_n.size() == out_v.size():
			nsa[Mesh.ARRAY_NORMAL] = out_n
		if sa[Mesh.ARRAY_TEX_UV]:
			nsa[Mesh.ARRAY_TEX_UV] = sa[Mesh.ARRAY_TEX_UV]
		if sa[Mesh.ARRAY_INDEX]:
			nsa[Mesh.ARRAY_INDEX] = sa[Mesh.ARRAY_INDEX]
		mdt_arr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, nsa)
		var mat := mesh.surface_get_material(si)
		if mat:
			mdt_arr.surface_set_material(mdt_arr.get_surface_count() - 1, mat)
	return mdt_arr


static func _calibrate_seats_and_build_interior(veh: VehicleController, out: Dictionary, body_size: Vector3) -> void:
	if veh.body_visuals == null:
		return

	var kw := veh.vehicle_name.to_lower()
	var body_w := maxf(body_size.x, 1.35)
	var roof_y := maxf(body_size.y, 1.35)
	var body_l := maxf(body_size.z, 2.40)

	# Compute exact cabin floor bounds (strictly inset >= 0.12m from outer body walls),
	# true front-cab DriverSeat, and clean passenger seat rows per vehicle archetype.
	var drv_pos := Vector3(-0.38, 0.72, -0.25)
	var pass_pos := Vector3(0.38, 0.72, -0.25)
	var floor_y := 0.34
	var floor_size := Vector3(body_w - 0.26, 0.06, body_l * 0.62)
	var floor_z := 0.15
	var extra_seats: Array[Vector3] = []

	if veh.is_bus:
		# Sudanese City Bus: driver cab directly behind front windshield (-Z), 4 rows of passenger seats behind
		drv_pos = Vector3(-0.68, 1.50, -3.45)
		pass_pos = Vector3(0.72, 1.50, -0.80)
		floor_y = 1.08
		floor_size = Vector3(body_w - 0.28, 0.08, body_l - 0.90)
		floor_z = 0.0
		extra_seats = [
			Vector3(-0.72, 1.50, -2.10),
			Vector3(0.72, 1.50, -2.10),
			Vector3(-0.72, 1.50, -0.80),
			Vector3(-0.72, 1.50, 0.50),
			Vector3(0.72, 1.50, 0.50),
			Vector3(-0.72, 1.50, 1.85),
			Vector3(0.72, 1.50, 1.85),
		]
	elif "amjad" in kw or "ambulance" in kw or "van" in kw:
		# Amjad / Ambulance Van: tucked inward (x=-0.32), back from windshield (z=-0.42), and lowered (y=0.84)
		# so boots, legs, arms, and head stay 100% inside the cabin
		drv_pos = Vector3(-0.32, 0.84, -0.42)
		pass_pos = Vector3(0.32, 0.84, 0.50)
		floor_y = 0.44
		floor_size = Vector3(body_w - 0.30, 0.06, body_l - 1.15)
		floor_z = 0.38
		extra_seats = [
			Vector3(0.32, 0.84, -0.42),
			Vector3(-0.32, 0.84, 0.50),
			Vector3(-0.32, 0.84, 1.35),
			Vector3(0.32, 0.84, 1.35),
		]
	elif "daffar" in kw:
		# Daffar Utility Truck (SchoolBus.fbx aligned -Z forward): front cab behind engine hood + rear benches
		drv_pos = Vector3(-0.46, 1.16, -1.18)
		pass_pos = Vector3(0.46, 1.16, -1.18)
		floor_y = 0.74
		floor_size = Vector3(body_w - 0.28, 0.07, body_l - 1.30)
		floor_z = 0.35
		extra_seats = [
			Vector3(-0.46, 1.16, 0.10),
			Vector3(0.46, 1.16, 0.10),
			Vector3(-0.46, 1.16, 1.35),
			Vector3(0.46, 1.16, 1.35),
		]
	elif "boks" in kw:
		# Boks Pickup / SUV: lowered by 0.20m (0.86 -> 0.66) so driver head clears 1.69m roof comfortably
		drv_pos = Vector3(-0.42, 0.66, -0.28)
		pass_pos = Vector3(0.42, 0.66, -0.28)
		floor_y = 0.30
		floor_size = Vector3(body_w - 0.30, 0.06, body_l - 1.75)
		floor_z = 0.35
		extra_seats = [
			Vector3(-0.42, 0.66, 0.68),
			Vector3(0.42, 0.66, 0.68),
		]
	elif veh.is_three_wheeler:
		# Raksha 3-wheeler: center front driver + rear bench
		drv_pos = Vector3(0.0, 0.66, -0.16)
		pass_pos = Vector3(0.0, 0.68, 0.56)
		floor_y = 0.28
		floor_size = Vector3(body_w - 0.26, 0.05, 1.85)
		floor_z = 0.05
	else:
		# Private Sedan / Police / Taxi: lowered by 0.20m (0.62 -> 0.42) so head sits cleanly below 1.40m roof
		drv_pos = Vector3(-0.32, 0.42, -0.14)
		pass_pos = Vector3(0.32, 0.42, -0.14)
		floor_y = 0.16
		floor_size = Vector3(body_w - 0.24, 0.05, 1.98)
		floor_z = 0.20
		extra_seats = [
			Vector3(-0.32, 0.42, 0.62),
			Vector3(0.32, 0.42, 0.62),
		]

	# Guarantee head clearance safely below roof (`seat_y + 0.87 <= roof_y - 0.05`)
	var max_safe_y := maxf(0.32, roof_y - 0.92)
	drv_pos.y = minf(drv_pos.y, max_safe_y)
	pass_pos.y = minf(pass_pos.y, max_safe_y)
	floor_y = clampf(drv_pos.y - 0.36, 0.14, drv_pos.y - 0.20)

	veh.driver_seat_offset = drv_pos
	veh.passenger_seat_offset = pass_pos

	for m_info in [
		{"name": "DriverSeat", "pos": veh.driver_seat_offset},
		{"name": "PassengerSeat", "pos": veh.passenger_seat_offset},
	]:
		var mk := veh.get_node_or_null(String(m_info["name"])) as Marker3D
		if mk == null:
			mk = Marker3D.new()
			mk.name = String(m_info["name"])
			veh.add_child(mk)
		mk.position = m_info["pos"]

	var raksha_sw := veh.body_visuals.get_node_or_null("SteeringWheel") as Node3D
	if raksha_sw != null:
		raksha_sw.position = Vector3(drv_pos.x, drv_pos.y + 0.30, drv_pos.z - 0.42)

	# Build solid dark charcoal CabinFloor + cushioned 3D seats + steering wheel strictly inside cabin
	var old_int := veh.body_visuals.get_node_or_null("CabinInterior")
	if old_int != null:
		old_int.queue_free()

	var cabin := Node3D.new()
	cabin.name = "CabinInterior"
	veh.body_visuals.add_child(cabin)

	var mat_floor := StandardMaterial3D.new()
	mat_floor.albedo_color = Color(0.16, 0.16, 0.18, 1.0)
	mat_floor.roughness = 0.90
	mat_floor.metallic = 0.0

	var mat_seat := StandardMaterial3D.new()
	mat_seat.albedo_color = Color(0.24, 0.21, 0.19, 1.0)
	mat_seat.roughness = 0.88
	mat_seat.metallic = 0.0

	var mat_wheel := StandardMaterial3D.new()
	mat_wheel.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
	mat_wheel.roughness = 0.55
	mat_wheel.metallic = 0.0

	# 1. Solid CabinFloor pan (inset from outer shell so zero geometry pokes outside; NO dashboard bar across windshield)
	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "CabinFloor"
	var fbm := BoxMesh.new()
	fbm.size = floor_size
	fbm.material = mat_floor
	floor_mi.mesh = fbm
	floor_mi.position = Vector3(0.0, floor_y - floor_size.y * 0.5, floor_z)
	cabin.add_child(floor_mi)

	# 2. Cushioned 3D seats under DriverSeat, PassengerSeat, and every rear row seat
	var seat_w := 0.44 if (veh.is_three_wheeler or body_w < 1.75) else 0.50
	var max_back_h := clampf(roof_y - drv_pos.y - 0.22, 0.36, 0.54)
	_add_seat_mesh(cabin, "SeatMesh_Driver", drv_pos, floor_y, seat_w, max_back_h, mat_seat, mat_floor)
	if veh.is_three_wheeler:
		_add_seat_mesh(cabin, "SeatMesh_PassengerBench", pass_pos, floor_y, 0.96, max_back_h, mat_seat, mat_floor)
	else:
		_add_seat_mesh(cabin, "SeatMesh_Passenger", pass_pos, floor_y, seat_w, max_back_h, mat_seat, mat_floor)
		for idx in range(extra_seats.size()):
			var sp: Vector3 = extra_seats[idx]
			sp.y = minf(sp.y, max_safe_y)
			_add_seat_mesh(cabin, "SeatMesh_Row_%d" % idx, sp, floor_y, seat_w, max_back_h, mat_seat, mat_floor)

	# 3. Compact Steering Wheel directly in front of DriverSeat (rotates with A/D)
	if not veh.is_three_wheeler:
		var sw_pivot := _add_steering_wheel(cabin, drv_pos, mat_wheel)
		out["steering_wheel"] = sw_pivot


static func _add_seat_mesh(parent: Node3D, n_name: String, seat_pos: Vector3, floor_y: float, width: float, back_h: float, mat_fabric: Material, mat_base: Material) -> void:
	var seat := Node3D.new()
	seat.name = n_name
	seat.position = Vector3(seat_pos.x, 0.0, seat_pos.z)
	# Rotated 180 deg around Y (`PI`) so backrest & headrest sit behind character's back (+Z) reclining cleanly backward while facing forward (-Z)
	seat.rotation.y = PI
	parent.add_child(seat)

	var cushion_top := seat_pos.y - 0.02
	var cushion_h := 0.09
	var ped_h := maxf(0.05, (cushion_top - cushion_h) - floor_y)

	# Support pedestal grounded directly onto CabinFloor
	var ped := MeshInstance3D.new()
	ped.name = "Pedestal"
	var pbm := BoxMesh.new()
	pbm.size = Vector3(width * 0.72, ped_h, 0.34)
	pbm.material = mat_base
	ped.mesh = pbm
	ped.position = Vector3(0.0, floor_y + ped_h * 0.5, -0.02)
	seat.add_child(ped)

	# Seat cushion (top face sits at seat_pos.y - 0.02 so character hips sit squarely on it)
	var cush := MeshInstance3D.new()
	cush.name = "Cushion"
	var cbm := BoxMesh.new()
	cbm.size = Vector3(width, cushion_h, 0.44)
	cbm.material = mat_fabric
	cush.mesh = cbm
	cush.position = Vector3(0.0, cushion_top - cushion_h * 0.5, 0.0)
	seat.add_child(cush)

	# Contoured backrest behind character's back (local -Z -> world +Z after rotation.y = PI) reclining gracefully backward (+Z)
	var back := MeshInstance3D.new()
	back.name = "Backrest"
	var bbm := BoxMesh.new()
	bbm.size = Vector3(width * 0.96, back_h, 0.09)
	bbm.material = mat_fabric
	back.mesh = bbm
	back.position = Vector3(0.0, cushion_top + back_h * 0.46, -0.23)
	back.rotation.x = deg_to_rad(-12.0)
	seat.add_child(back)

	# Compact headrest behind head (local -Z -> world +Z after rotation.y = PI)
	var head := MeshInstance3D.new()
	head.name = "Headrest"
	var hbm := BoxMesh.new()
	hbm.size = Vector3(minf(width * 0.52, 0.24), 0.13, 0.08)
	hbm.material = mat_fabric
	head.mesh = hbm
	head.position = Vector3(0.0, cushion_top + back_h + 0.05, -0.29)
	seat.add_child(head)


static func _add_steering_wheel(parent: Node3D, drv_pos: Vector3, mat_wheel: Material) -> Node3D:
	var col := MeshInstance3D.new()
	col.name = "SteeringColumn"
	var ccm := CylinderMesh.new()
	ccm.top_radius = 0.032
	ccm.bottom_radius = 0.038
	ccm.height = 0.34
	ccm.radial_segments = 10
	ccm.material = mat_wheel
	col.mesh = ccm
	col.position = Vector3(drv_pos.x, drv_pos.y + 0.22, drv_pos.z - 0.50)
	col.rotation.x = deg_to_rad(-62.0)
	parent.add_child(col)

	var pivot := Node3D.new()
	pivot.name = "SteeringWheel"
	pivot.position = Vector3(drv_pos.x, drv_pos.y + 0.28, drv_pos.z - 0.40)
	pivot.rotation.x = deg_to_rad(-28.0)
	parent.add_child(pivot)

	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.135
	tm.outer_radius = 0.175
	tm.rings = 16
	tm.ring_segments = 10
	tm.material = mat_wheel
	rim.mesh = tm
	rim.rotation.x = PI * 0.5
	pivot.add_child(rim)

	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var hbm := BoxMesh.new()
	hbm.size = Vector3(0.28, 0.045, 0.04)
	hbm.material = mat_wheel
	hub.mesh = hbm
	pivot.add_child(hub)
	return pivot


static func _fix_plates_and_signs(veh: VehicleController, front_z: float, rear_z: float, width: float, roof_y: float) -> void:
	if veh.body_visuals == null:
		return
	var half_w := maxf(width * 0.5, 0.65)

	# Compact, cleanly scaled license plates flush against lower front/rear bumpers
	var plate_front := veh.body_visuals.get_node_or_null("LicensePlateFront") as Label3D
	if plate_front != null:
		plate_front.double_sided = false
		plate_front.scale = Vector3(0.72, 0.72, 0.72)
		plate_front.rotation = Vector3(0.0, PI, 0.0)
		plate_front.position = Vector3(0.0, 0.36, front_z - 0.015)
		plate_front.font_size = 18
		plate_front.outline_size = 4

	var plate_rear := veh.body_visuals.get_node_or_null("LicensePlateRear") as Label3D
	if plate_rear != null:
		plate_rear.double_sided = false
		plate_rear.scale = Vector3(0.72, 0.72, 0.72)
		plate_rear.rotation = Vector3.ZERO
		plate_rear.position = Vector3(0.0, 0.40, rear_z + 0.015)
		plate_rear.font_size = 18
		plate_rear.outline_size = 4

	var route_front := veh.body_visuals.get_node_or_null("RouteSignFront") as Label3D
	if route_front != null:
		route_front.double_sided = false
		route_front.scale = Vector3(0.85, 0.85, 0.85)
		route_front.rotation = Vector3(0.0, PI, 0.0)
		route_front.position = Vector3(0.0, roof_y - 0.14, front_z - 0.015)

	var route_side := veh.body_visuals.get_node_or_null("RouteSignSide") as Label3D
	if route_side != null:
		route_side.double_sided = false
		route_side.scale = Vector3(0.85, 0.85, 0.85)
		route_side.rotation = Vector3(0.0, PI * 0.5, 0.0)
		route_side.position = Vector3(half_w + 0.015, roof_y - 0.26, -0.45)
