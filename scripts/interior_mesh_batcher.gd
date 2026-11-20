extends RefCounted
class_name InteriorMeshBatcher

## Shared high-FPS multi-surface ArrayMesh batcher & Sudanese architectural PBR material library.
## Used by MosqueInteriorBuilder, MarketInteriorBuilder, SudaneseHouseInterior, and ApartmentInteriorBuilder
## to merge hundreds of decorative sub-meshes into 1 single draw-call-friendly ArrayMesh per room/building.

static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}

var _tools: Dictionary = {} # Material -> SurfaceTool


func _tool_for(mat: Material) -> SurfaceTool:
	if _tools.has(mat):
		return _tools[mat] as SurfaceTool
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	_tools[mat] = st
	return st


func add_box(center: Vector3, size: Vector3, mat: Material, rot_y: float = 0.0, rot_x: float = 0.0, rot_z: float = 0.0) -> void:
	if size.x <= 0.001 or size.y <= 0.001 or size.z <= 0.001:
		return
	var st := _tool_for(mat)
	var bm := BoxMesh.new()
	bm.size = size
	var basis := Basis.from_euler(Vector3(rot_x, rot_y, rot_z))
	st.append_from(bm, 0, Transform3D(basis, center))


func add_cylinder(center: Vector3, top_r: float, bot_r: float, height: float, mat: Material, segs: int = 10, rot_x: float = 0.0, rot_z: float = 0.0) -> void:
	if height <= 0.001:
		return
	var st := _tool_for(mat)
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = height
	cm.radial_segments = segs
	cm.rings = 1
	var basis := Basis.from_euler(Vector3(rot_x, 0.0, rot_z))
	st.append_from(cm, 0, Transform3D(basis, center))


func add_sphere(center: Vector3, radius: float, mat: Material, scale_v: Vector3 = Vector3.ONE, segs: int = 10, rings: int = 6) -> void:
	if radius <= 0.001:
		return
	var st := _tool_for(mat)
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = segs
	sm.rings = rings
	var basis := Basis.from_scale(scale_v)
	st.append_from(sm, 0, Transform3D(basis, center))


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


func is_empty() -> bool:
	return _tools.is_empty()


func commit() -> ArrayMesh:
	var am := ArrayMesh.new()
	for mat in _tools.keys():
		var st := _tools[mat] as SurfaceTool
		st.commit(am)
	return am


static func add_box_collider(body: StaticBody3D, cname: String, center: Vector3, size: Vector3) -> void:
	if body == null or size.x <= 0.005 or size.y <= 0.005 or size.z <= 0.005:
		return
	var cs := CollisionShape3D.new()
	cs.name = cname
	cs.position = center
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)


# ==============================================================================
# SHARED COLOR & PBR MATERIALS
# ==============================================================================
static func get_color_mat(key: String, col: Color, rough: float = 0.82, metal: float = 0.0, emission: Color = Color(0, 0, 0), emit_energy: float = 0.0) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emit_energy > 0.01:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emit_energy
	_mat_cache[key] = m
	return m


static func get_pbr_mat(key: String, tex_dir: String, tint: Color, rough: float = 0.85, uv_scale: Vector3 = Vector3(1, 1, 1), triplanar: bool = true) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = 0.0
	var alb := tex_dir + "/albedo.jpg"
	var nor := tex_dir + "/normal.jpg"
	var rgh := tex_dir + "/roughness.jpg"
	if ResourceLoader.exists(alb):
		m.albedo_texture = ResourceLoader.load(alb) as Texture2D
	if ResourceLoader.exists(nor):
		m.normal_enabled = true
		m.normal_scale = 0.65
		m.normal_texture = ResourceLoader.load(nor) as Texture2D
	if ResourceLoader.exists(rgh):
		m.roughness_texture = ResourceLoader.load(rgh) as Texture2D
	m.uv1_triplanar = triplanar
	m.uv1_scale = uv_scale
	_mat_cache[key] = m
	return m


# ==============================================================================
# PROCEDURAL TEXTURES: ISLAMIC PRAYER CARPET & SUDANESE WOVEN RUG
# ==============================================================================
static func get_prayer_carpet_mat(repeat_x: float = 7.0, repeat_z: float = 6.0) -> StandardMaterial3D:
	var key := "prayer_carpet_%.1f_%.1f" % [repeat_x, repeat_z]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D

	var tex: ImageTexture = _tex_cache.get("prayer_carpet_tex") as ImageTexture
	if tex == null:
		var w := 256
		var h := 256
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var c_emerald := Color(0.06, 0.31, 0.21)
		var c_emerald_dk := Color(0.04, 0.22, 0.15)
		var c_burgundy := Color(0.45, 0.09, 0.13)
		var c_gold := Color(0.84, 0.69, 0.28)
		var c_ivory := Color(0.95, 0.92, 0.82)

		for y in range(h):
			var fy := float(y) / float(h) # 0 = Qibla top (-Z), 1 = back (+Z)
			for x in range(w):
				var fx := float(x) / float(w) # 1 prayer mat width
				var col := c_emerald
				# Subtle woven fabric grain
				if ((x + y) % 4) == 0:
					col = c_emerald_dk
				# Horizontal Saf prayer row line along the Qibla front edge & back band
				if fy < 0.055 or fy > 0.96:
					col = c_ivory if (fy < 0.025 or fy > 0.98) else c_gold
				elif fy < 0.12 or fy > 0.89:
					col = c_burgundy
					if (x % 16) < 4 and absf(fy - 0.088) < 0.015:
						col = c_gold
				else:
					# Side burgundy ornamental stripes separating each worshipper's space
					var dx_edge := minf(fx, 1.0 - fx)
					if dx_edge < 0.045:
						col = c_gold if dx_edge < 0.016 else c_burgundy
					elif dx_edge < 0.075:
						col = c_gold if ((y % 12) < 5) else c_emerald_dk
					else:
						# Pointed Islamic Mihrab arch motif pointing toward Qibla (fy -> 0)
						var cx := absf(fx - 0.5) * 2.0 # 0 at center, 1 at edge
						var arch_y := 0.22 + cx * cx * 0.28
						if absf(fy - arch_y) < 0.024 and cx < 0.78:
							col = c_gold
						elif fy > arch_y and fy < arch_y + 0.035 and cx < 0.72:
							col = c_burgundy
						# Central diamond medallion inside each prayer mat
						var med := absf(fx - 0.5) * 2.2 + absf(fy - 0.58) * 1.8
						if med < 0.16:
							col = c_gold if med > 0.11 else c_burgundy
				img.set_pixel(x, y, col)
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
		_tex_cache["prayer_carpet_tex"] = tex

	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.94
	m.metallic = 0.0
	m.uv1_scale = Vector3(repeat_x, repeat_z, 1.0)
	_mat_cache[key] = m
	return m


static func get_sudanese_rug_mat(variant: int = 0) -> StandardMaterial3D:
	var key := "sudanese_rug_%d" % variant
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D

	var tex_key := "sudanese_rug_tex_%d" % variant
	var tex: ImageTexture = _tex_cache.get(tex_key) as ImageTexture
	if tex == null:
		var w := 192
		var h := 192
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var c_base := Color(0.56, 0.14, 0.14) if variant == 0 else Color(0.14, 0.30, 0.42)
		var c_acc := Color(0.84, 0.66, 0.26) if variant == 0 else Color(0.82, 0.46, 0.22)
		var c_cream := Color(0.93, 0.88, 0.76)
		var c_dark := Color(0.18, 0.12, 0.10)

		for y in range(h):
			var fy := float(y) / float(h)
			for x in range(w):
				var fx := float(x) / float(w)
				var ex := minf(fx, 1.0 - fx)
				var ey := minf(fy, 1.0 - fy)
				var edge := minf(ex, ey)
				var col := c_base
				if edge < 0.05:
					col = c_cream if ((x + y) % 8) < 4 else c_dark
				elif edge < 0.11:
					col = c_acc if (((x / 8) + (y / 8)) % 2 == 0) else c_dark
				elif edge < 0.14:
					col = c_cream
				else:
					var d_ctr := absf(fx - 0.5) + absf(fy - 0.5)
					if d_ctr < 0.22:
						col = c_acc if d_ctr > 0.15 else c_cream
					elif d_ctr < 0.27:
						col = c_dark
					elif ((x / 12 + y / 12) % 3) == 0:
						col = c_base.darkened(0.14)
				img.set_pixel(x, y, col)
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
		_tex_cache[tex_key] = tex

	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.94
	m.metallic = 0.0
	_mat_cache[key] = m
	return m
