shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_map_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_map_b : hint_normal, repeat_enable, filter_linear_mipmap;

uniform vec4 shallow_water_color : source_color = vec4(0.54, 0.50, 0.34, 0.82);
uniform vec4 mid_water_color : source_color = vec4(0.10, 0.42, 0.48, 0.90);
uniform vec4 deep_water_color : source_color = vec4(0.03, 0.19, 0.30, 0.96);
uniform vec4 sky_reflect_color : source_color = vec4(0.86, 0.78, 0.68, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.97, 0.99, 1.0);

uniform float flow_speed : hint_range(0.0, 2.0) = 0.28;
uniform float uv_scale_a : hint_range(0.005, 0.2) = 0.042;
uniform float uv_scale_b : hint_range(0.005, 0.2) = 0.068;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.72;
uniform float wave_height : hint_range(0.0, 0.25) = 0.048;
uniform float depth_fade_distance : hint_range(0.5, 12.0) = 3.6;
uniform float foam_depth : hint_range(0.05, 2.0) = 0.72;

varying vec3 v_world_pos;

void vertex() {
	vec3 world_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * (flow_speed * 3.2);
	float w1 = sin(world_v.z * 0.28 - t * 1.45 + world_v.x * 0.14) * wave_height;
	float w2 = cos(world_v.x * 0.42 + world_v.z * 0.19 - t * 1.15) * (wave_height * 0.62);
	VERTEX.y += w1 + w2;
	v_world_pos = vec3(world_v.x, world_v.y + w1 + w2, world_v.z);
}

void fragment() {
	float t = TIME * flow_speed;

	// Dual-scrolling world-space normal maps for seamless river current across all segments
	vec2 uv_a = v_world_pos.xz * uv_scale_a + vec2(0.02 * t, -0.22 * t);
	vec2 uv_b = v_world_pos.xz * uv_scale_b + vec2(-0.07 * t, -0.15 * t);
	vec3 n_a = texture(normal_map_a, uv_a).rgb;
	vec3 n_b = texture(normal_map_b, uv_b).rgb;
	vec3 blended_normal = normalize(mix(n_a, n_b, 0.5));
	NORMAL_MAP = blended_normal;
	NORMAL_MAP_DEPTH = normal_strength;

	// Reconstruct linear water depth from hint_depth_texture (GL Compatibility safe)
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw * 2.0 - 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= max(abs(view_pos.w), 0.0001) * sign(view_pos.w);
	float water_depth = clamp(VERTEX.z - view_pos.z, 0.0, 14.0);

	// Depth-based color transition: sandy shallow banks -> Nile turquoise -> deep teal-blue
	float shallow_t = clamp(water_depth / (depth_fade_distance * 0.42), 0.0, 1.0);
	float deep_t = clamp(1.0 - exp(-water_depth / depth_fade_distance), 0.0, 1.0);
	vec3 base_col = mix(shallow_water_color.rgb, mid_water_color.rgb, shallow_t);
	base_col = mix(base_col, deep_water_color.rgb, deep_t);

	// Fresnel sky reflection & sparkling ripple crests
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 4.0);
	vec3 water_col = mix(base_col, sky_reflect_color.rgb, fresnel * 0.58);

	// Animated white shoreline foam around banks, sloped islands, and river rocks
	float foam_noise = clamp((n_a.r + n_b.g) * 0.72, 0.0, 1.0);
	float depth_foam = 1.0 - smoothstep(0.04, foam_depth, water_depth);
	float ripple_band = sin(water_depth * 14.0 - TIME * 2.6 + foam_noise * 5.0) * 0.5 + 0.5;
	float shore_foam = clamp(depth_foam * (0.55 + 0.45 * ripple_band) * smoothstep(0.30, 0.75, foam_noise + depth_foam * 0.55), 0.0, 1.0);
	float crest_foam = smoothstep(0.78, 0.94, foam_noise) * 0.14;
	float total_foam = clamp(shore_foam + crest_foam, 0.0, 0.92);

	ALBEDO = mix(water_col, foam_color.rgb, total_foam);
	ALPHA = clamp(mix(shallow_water_color.a, deep_water_color.a, deep_t) + total_foam * 0.25 + fresnel * 0.12, 0.62, 0.98);
	ROUGHNESS = mix(0.06, 0.34, total_foam);
	METALLIC = 0.04;
	SPECULAR = 0.88;
}
