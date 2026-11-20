extends Node

## Visual Effects (VFX) Manager & Factory for Al-Azhari (GL Compatibility safe).
## Builds GPU particle systems, dynamic vehicle lights, interaction rings, and speaking waves.


func create_smoke_particles(parent: Node3D, local_pos: Vector3, is_diesel: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "ExhaustSmoke"
	p.position = local_pos
	p.amount = 18
	p.lifetime = 1.1
	p.explosiveness = 0.0
	p.local_coords = false

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 0.4, 1.0).normalized()
	proc.spread = 22.0
	proc.initial_velocity_min = 0.8
	proc.initial_velocity_max = 1.6
	proc.gravity = Vector3(0.0, 1.2, 0.0)
	proc.scale_min = 0.35
	proc.scale_max = 0.85
	proc.color = Color(0.32, 0.30, 0.28, 0.42) if is_diesel else Color(0.75, 0.75, 0.78, 0.35)
	p.process_material = proc

	p.draw_pass_1 = _make_soft_quad(Vector2(0.38, 0.38))
	p.emitting = false
	parent.add_child(p)
	return p


func create_dust_particles(parent: Node3D, local_pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "TireDust"
	p.position = local_pos
	p.amount = 22
	p.lifetime = 0.85
	p.local_coords = false

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 0.55, 1.0).normalized()
	proc.spread = 38.0
	proc.initial_velocity_min = 1.1
	proc.initial_velocity_max = 2.4
	proc.gravity = Vector3(0.0, -0.4, 0.0)
	proc.scale_min = 0.45
	proc.scale_max = 1.1
	proc.color = Color(0.76, 0.49, 0.34, 0.48)
	p.process_material = proc

	p.draw_pass_1 = _make_soft_quad(Vector2(0.55, 0.55))
	p.emitting = false
	parent.add_child(p)
	return p


func create_steam_particles(parent: Node3D, local_pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "KettleSteam"
	p.position = local_pos
	p.amount = 14
	p.lifetime = 1.4
	p.local_coords = false

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 16.0
	proc.initial_velocity_min = 0.45
	proc.initial_velocity_max = 0.85
	proc.gravity = Vector3(0.15, 0.35, 0.0)
	proc.scale_min = 0.25
	proc.scale_max = 0.65
	proc.color = Color(0.96, 0.96, 0.98, 0.32)
	p.process_material = proc

	p.draw_pass_1 = _make_soft_quad(Vector2(0.32, 0.32))
	p.emitting = true
	parent.add_child(p)
	return p


func create_water_splash_particles(parent: Node3D, local_pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "WaterSplash"
	p.position = local_pos
	p.amount = 24
	p.lifetime = 0.95
	p.local_coords = false

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 45.0
	proc.initial_velocity_min = 1.4
	proc.initial_velocity_max = 2.6
	proc.gravity = Vector3(0.0, -5.8, 0.0)
	proc.scale_min = 0.14
	proc.scale_max = 0.28
	proc.color = Color(0.68, 0.88, 0.98, 0.65)
	p.process_material = proc

	p.draw_pass_1 = _make_soft_quad(Vector2(0.18, 0.18))
	p.emitting = true
	parent.add_child(p)
	return p


func spawn_feather_burst(parent: Node3D, world_pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 65.0
	proc.initial_velocity_min = 2.0
	proc.initial_velocity_max = 4.5
	proc.gravity = Vector3(0.0, -2.5, 0.0)
	proc.scale_min = 0.18
	proc.scale_max = 0.32
	proc.color = Color(0.92, 0.88, 0.80, 0.85)
	p.process_material = proc

	p.draw_pass_1 = _make_soft_quad(Vector2(0.22, 0.12))
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func create_desert_dust_motes(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "DesertDustMotes"
	p.position = Vector3(0.0, 3.2, 0.0)
	p.amount = 65
	p.lifetime = 5.5
	p.visibility_aabb = AABB(Vector3(-45, -3, -45), Vector3(90, 10, 90))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(40.0, 2.8, 40.0)
	proc.direction = Vector3(1.0, 0.15, 0.4).normalized()
	proc.spread = 20.0
	proc.initial_velocity_min = 0.35
	proc.initial_velocity_max = 0.9
	proc.gravity = Vector3(0.0, -0.02, 0.0)
	proc.scale_min = 0.12
	proc.scale_max = 0.24
	proc.color = Color(1.0, 0.85, 0.56, 0.30)
	p.process_material = proc

	p.draw_pass_1 = _make_soft_quad(Vector2(0.18, 0.18))
	p.emitting = true
	parent.add_child(p)
	return p


func create_interaction_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "InteractionRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 0.90
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.25, 1.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.28, 0.82)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.78, 0.22, 1.0)
	mat.emission_energy_multiplier = 1.8
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.visible = false
	return ring


func create_speaking_wave() -> Node3D:
	var root := Node3D.new()
	root.name = "SpeakingWave"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.95, 0.55, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.95, 0.50, 1.0)
	mat.emission_energy_multiplier = 1.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for i in range(3):
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 0.18, 0.06)
		bar.mesh = box
		bar.material_override = mat
		bar.position = Vector3((i - 1) * 0.11, 0.0, 0.0)
		root.add_child(bar)
	root.visible = false
	return root


func _make_soft_quad(quad_size: Vector2) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = quad_size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	q.material = mat
	return q
