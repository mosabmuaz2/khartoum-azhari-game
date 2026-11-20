shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex : hint_roughness_g, filter_linear_mipmap, repeat_enable;

uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);

uniform bool has_albedo_tex = false;
uniform bool has_normal_tex = false;
uniform bool has_roughness_tex = false;
uniform bool use_vertex_color = false;

uniform float roughness_val : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;

uniform float wind_strength : hint_range(0.0, 1.0) = 0.09;
uniform float wind_speed : hint_range(0.1, 6.0) = 1.45;
uniform float min_sway_height = 1.4;
uniform float phase_offset = 0.0;
uniform float max_wind_distance = 65.0;
uniform vec2 wind_dir = vec2(0.86, 0.51);

void vertex() {
	UV = UV * uv_scale + uv_offset;
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float cam_dist = distance(world_origin, cam_pos);
	if (wind_strength > 0.001 && cam_dist < max_wind_distance) {
		float dist_fade = 1.0 - smoothstep(max_wind_distance * 0.75, max_wind_distance, cam_dist);
		vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float h_above = max(0.0, (world_pos.y - world_origin.y) - min_sway_height);
		float bend = clamp(h_above * 0.34, 0.0, 1.5);
		float sway = bend * bend * dist_fade * wind_strength;
		float t = TIME * wind_speed + phase_offset + world_origin.x * 0.23 + world_origin.z * 0.17;
		float gust = sin(t) * 0.7 + sin(t * 2.05 + world_pos.y * 0.7) * 0.3;
		vec3 world_disp = vec3(wind_dir.x * gust * sway, 0.0, wind_dir.y * gust * sway);
		VERTEX += (inverse(mat3(MODEL_MATRIX)) * world_disp);
	}
}

void fragment() {
	vec3 col = albedo_color.rgb;
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	if (has_albedo_tex) {
		col *= texture(texture_albedo, UV).rgb;
	}
	ALBEDO = col;
	METALLIC = metallic_val;
	if (has_roughness_tex) {
		ROUGHNESS = clamp(texture(roughness_tex, UV).g * roughness_val, 0.45, 1.0);
	} else {
		ROUGHNESS = roughness_val;
	}
	if (has_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}
