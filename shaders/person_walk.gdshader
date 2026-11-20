shader_type spatial;
render_mode cull_disabled;

uniform float char_height = 1.72;
uniform float walk_phase = 0.0;
uniform float walk_amount : hint_range(0.0, 1.0) = 0.0;
uniform float idle_time = 0.0;
uniform float is_seated : hint_range(0.0, 1.0) = 0.0;

uniform vec4 skin_color : source_color = vec4(0.45, 0.29, 0.19, 1.0);
uniform vec4 top_color : source_color = vec4(0.92, 0.90, 0.86, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.20, 0.24, 0.30, 1.0);
uniform vec4 head_color : source_color = vec4(0.95, 0.94, 0.90, 1.0);
uniform vec4 shoe_color : source_color = vec4(0.14, 0.11, 0.09, 1.0);
uniform float is_robed : hint_range(0.0, 1.0) = 0.0;

varying float v_h_norm;
varying float v_x_abs;
varying float v_z_dir;

void vertex() {
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Character local coordinates relative to root forward (-Z) and right (+X)
	vec3 axis_x = normalize(MODEL_MATRIX[0].xyz);
	vec3 axis_y = normalize(MODEL_MATRIX[1].xyz);
	vec3 axis_z = normalize(MODEL_MATRIX[2].xyz);
	vec3 rel = world_pos - world_origin;
	float x_m = dot(rel, axis_x);
	float y_m = dot(rel, axis_y);
	float z_m = dot(rel, axis_z);

	float h = clamp(y_m / max(0.5, char_height), 0.0, 1.0);
	v_h_norm = h;
	v_x_abs = abs(x_m) / max(0.5, char_height);
	v_z_dir = z_m;

	// Hip & Shoulder joint pivots in meters
	float hip_y = 0.47 * char_height;
	float shoulder_y = 0.78 * char_height;

	// Leg articulation below hips (exclude outer lowered arms)
	float is_arm = smoothstep(0.16, 0.23, abs(x_m) / max(0.5, char_height)) * smoothstep(0.40, 0.48, h) * (1.0 - smoothstep(0.81, 0.86, h));
	float is_leg = (1.0 - smoothstep(0.43, 0.50, h)) * (1.0 - is_arm);

	float leg_side = (x_m < 0.0) ? 1.0 : -1.0;
	float leg_angle = sin(walk_phase) * 0.46 * walk_amount * leg_side;
	leg_angle = mix(leg_angle, -1.25, is_seated);

	if (is_leg > 0.01) {
		float dy = y_m - hip_y;
		float dz = z_m;
		float c = cos(leg_angle);
		float s = sin(leg_angle);
		float ny = dy * c - dz * s + hip_y;
		float nz = dy * s + dz * c;
		rel += axis_y * ((ny - y_m) * is_leg) + axis_z * ((nz - z_m) * is_leg);
	}

	// Arm articulation around shoulder height
	if (is_arm > 0.01) {
		float arm_side = (x_m < 0.0) ? -1.0 : 1.0;
		float arm_angle = sin(walk_phase) * 0.42 * walk_amount * arm_side;
		arm_angle = mix(arm_angle, -0.45, is_seated);
		float dy = y_m - shoulder_y;
		float dz = z_m;
		float c = cos(arm_angle);
		float s = sin(arm_angle);
		float ny = dy * c - dz * s + shoulder_y;
		float nz = dy * s + dz * c;
		rel += axis_y * ((ny - y_m) * is_arm) + axis_z * ((nz - z_m) * is_arm);
	}

	// Subtle torso breathing & walk stride bounce
	float bob = abs(cos(walk_phase)) * 0.028 * walk_amount * (1.0 - is_seated);
	float breathe = sin(idle_time * 2.2) * 0.008 * smoothstep(0.55, 0.85, h);
	rel += axis_y * (bob + breathe);

	vec3 new_world = world_origin + rel;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(new_world, 1.0)).xyz;
}

void fragment() {
	vec3 col = bottom_color.rgb;
	float rough = 0.86;

	// Torso & robe top
	float top_mask = smoothstep(0.46, 0.51, v_h_norm);
	col = mix(bottom_color.rgb, top_color.rgb, top_mask);
	if (is_robed > 0.5) {
		col = mix(top_color.rgb * 0.94, top_color.rgb, top_mask);
	}

	// Shoes
	float shoe_mask = 1.0 - smoothstep(0.04, 0.075, v_h_norm);
	col = mix(col, shoe_color.rgb, shoe_mask);

	// Neck / Face / Hands skin tone
	float face_mask = smoothstep(0.84, 0.87, v_h_norm) * (1.0 - smoothstep(0.94, 0.97, v_h_norm));
	float hand_mask = smoothstep(0.22, 0.27, v_x_abs) * (1.0 - smoothstep(0.54, 0.59, v_h_norm)) * smoothstep(0.42, 0.46, v_h_norm);
	float skin_m = clamp(face_mask + hand_mask * (1.0 - is_robed * 0.5), 0.0, 1.0);
	col = mix(col, skin_color.rgb, skin_m);
	rough = mix(rough, 0.68, skin_m);

	// Hair / Imma / Hijab crown
	float head_top = smoothstep(0.935, 0.96, v_h_norm);
	col = mix(col, head_color.rgb, head_top);

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.02;
}
