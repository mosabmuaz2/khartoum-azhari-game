shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Brightly lit PBR character parameters (prevents dark vertex colors or metallic blackouts)
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool vertex_color_use_as_albedo = false;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform vec4 backlight : source_color = vec4(0.35, 0.33, 0.30, 1.0);

// Mesh local AABB bounds normalized to 1.75m character proportions
uniform vec3 aabb_min = vec3(-0.35, 0.0, -0.25);
uniform vec3 aabb_size = vec3(0.70, 1.75, 0.50);

// Animation state parameters driven by CharacterAnimator
uniform float walk_phase = 0.0;
uniform float walk_amount : hint_range(0.0, 1.0) = 0.0;
uniform float run_amount : hint_range(0.0, 1.0) = 0.0;
uniform float idle_time = 0.0;
uniform float is_seated : hint_range(0.0, 1.0) = 0.0;
uniform float is_driving : hint_range(0.0, 1.0) = 0.0;
uniform float is_airborne : hint_range(0.0, 1.0) = 0.0;
uniform float crouch_amount : hint_range(0.0, 1.0) = 0.0;
uniform float slide_amount : hint_range(0.0, 1.0) = 0.0;
uniform float carry_amount : hint_range(0.0, 1.0) = 0.0;
uniform float pickup_bend : hint_range(0.0, 1.0) = 0.0;

vec3 rotate_x(vec3 p, vec3 pivot, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	vec3 d = p - pivot;
	return pivot + vec3(d.x, d.y * c - d.z * s, d.y * s + d.z * c);
}

vec3 rotate_y(vec3 p, vec3 pivot, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	vec3 d = p - pivot;
	return pivot + vec3(d.x * c + d.z * s, d.y, -d.x * s + d.z * c);
}

vec3 rotate_z(vec3 p, vec3 pivot, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	vec3 d = p - pivot;
	return pivot + vec3(d.x * c - d.y * s, d.x * s + d.y * c, d.z);
}

void vertex() {
	vec3 sz = max(aabb_size, vec3(0.001));
	vec3 center = aabb_min + sz * 0.5;

	// Normalized coordinates relative to character height H (1.75m) and width W
	float yn = clamp((VERTEX.y - aabb_min.y) / sz.y, 0.0, 1.0);
	float xn = (VERTEX.x - center.x) / sz.x;
	float side_blend = smoothstep(-0.025, 0.025, xn);
	float side_sign = mix(-1.0, 1.0, side_blend);

	vec3 pos = VERTEX;
	vec3 nrm = NORMAL;

	float idle_factor = clamp(1.0 - walk_amount * 1.2, 0.0, 1.0) * (1.0 - is_seated) * (1.0 - slide_amount);

	// -------------------------------------------------------------------------
	// 1. LEFT & RIGHT LEG ARTICULATION (yn < 0.49 * H, split cleanly at x = 0.0)
	//    Hip pivots at (±0.10m, 0.85m, 0.0m) in 1.75m space -> yn = 0.486
	// -------------------------------------------------------------------------
	float leg_mask = (1.0 - smoothstep(0.45, 0.50, yn));
	if (leg_mask > 0.001) {
		float leg_phase = walk_phase + ((xn >= 0.0) ? 0.0 : 3.14159265);
		float stride_amp = (0.62 * walk_amount + 0.34 * run_amount) * (1.0 - 0.35 * crouch_amount);
		float thigh_angle = sin(leg_phase) * stride_amp - 0.62 * crouch_amount;

		if (slide_amount > 0.05) {
			thigh_angle = mix(thigh_angle, (xn >= 0.0) ? -1.15 : -0.45, slide_amount);
		}
		if (is_airborne > 0.5) {
			thigh_angle = ((xn >= 0.0) ? -0.52 : 0.38);
		}
		if (is_seated > 0.5) {
			thigh_angle = -1.32;
		}

		vec3 hip_pivot = vec3(
			center.x + side_sign * (0.10 / 0.70) * sz.x,
			aabb_min.y + (0.85 / 1.75) * sz.y,
			center.z
		);

		// Knee bend & foot lift below knee (yn < 0.27 * H)
		float knee_mask = 1.0 - smoothstep(0.22, 0.29, yn);
		float lift_wave = max(0.0, -cos(leg_phase));
		float knee_angle = lift_wave * (0.68 * walk_amount + 0.48 * run_amount) + 0.88 * crouch_amount;
		if (slide_amount > 0.05) {
			knee_angle = mix(knee_angle, (xn >= 0.0) ? 0.25 : 1.15, slide_amount);
		}
		if (is_airborne > 0.5) {
			knee_angle = 0.65;
		}
		if (is_seated > 0.5) {
			knee_angle = 1.32;
		}

		vec3 knee_pivot = vec3(
			hip_pivot.x,
			aabb_min.y + (0.46 / 1.75) * sz.y,
			center.z
		);

		vec3 p_leg = pos;
		if (knee_mask > 0.001) {
			p_leg = mix(p_leg, rotate_x(p_leg, knee_pivot, knee_angle), knee_mask);
		}
		p_leg = rotate_x(p_leg, hip_pivot, thigh_angle);
		p_leg.y += lift_wave * (0.045 * walk_amount + 0.035 * run_amount) * sz.y * knee_mask * (1.0 - is_seated);

		pos = mix(pos, p_leg, leg_mask);
		nrm = normalize(mix(nrm, rotate_x(nrm, vec3(0.0), thigh_angle * 0.6), leg_mask));
	}

	// -------------------------------------------------------------------------
	// 2. LEFT & RIGHT ARM ARTICULATION + T-POSE LOWERING TO NATURAL SIDES
	//    Anatomical shoulder pivots at (±0.145 * width, 0.79 * H, 0.0m)
	// -------------------------------------------------------------------------
	float arm_x_mask = smoothstep(0.11, 0.16, abs(xn));
	float arm_y_mask = smoothstep(0.38, 0.44, yn) * (1.0 - smoothstep(0.80, 0.85, yn));
	float arm_mask = arm_x_mask * arm_y_mask;
	if (arm_mask > 0.001) {
		float arm_phase = walk_phase + ((xn >= 0.0) ? 3.14159265 : 0.0);
		float arm_amp = (0.62 * walk_amount + 0.38 * run_amount) * (1.0 - carry_amount);
		float shoulder_angle = sin(arm_phase) * arm_amp;

		shoulder_angle += sin(idle_time * 1.5 + side_sign * 0.8) * 0.055 * idle_factor * (1.0 - carry_amount);

		if (carry_amount > 0.01) {
			shoulder_angle = mix(shoulder_angle, -0.92, carry_amount);
		}
		if (pickup_bend > 0.01) {
			shoulder_angle = mix(shoulder_angle, -1.18, pickup_bend);
		}
		if (is_airborne > 0.5 && carry_amount < 0.2) {
			shoulder_angle = -0.58;
		}
		if (is_seated > 0.5) {
			shoulder_angle = (is_driving > 0.5) ? -0.88 : -0.35;
		}

		vec3 shoulder_pivot = vec3(
			center.x + side_sign * 0.145 * sz.x,
			aabb_min.y + 0.79 * sz.y,
			center.z
		);

		// First lower arms from baked T/A-pose down to natural sides along Z-axis
		float tpose_drop_z = -side_sign * (0.44 - 0.03 * idle_factor * sin(idle_time * 1.4)) * (1.0 - carry_amount * 0.5);
		vec3 p_arm = rotate_z(pos, shoulder_pivot, tpose_drop_z);

		float elbow_mask = 1.0 - smoothstep(0.56, 0.64, yn);
		float elbow_angle = -0.14 * idle_factor - max(0.0, -sin(arm_phase)) * (0.46 * walk_amount + 0.54 * run_amount) * (1.0 - carry_amount);
		if (carry_amount > 0.01) {
			elbow_angle = mix(elbow_angle, -0.48, carry_amount);
		}
		if (is_driving > 0.5) {
			elbow_angle = -0.35;
		}
		vec3 elbow_pivot = vec3(
			center.x + side_sign * 0.165 * sz.x,
			aabb_min.y + 0.61 * sz.y,
			center.z
		);

		if (elbow_mask > 0.001) {
			p_arm = mix(p_arm, rotate_x(p_arm, elbow_pivot, elbow_angle), elbow_mask);
		}
		p_arm = rotate_x(p_arm, shoulder_pivot, shoulder_angle);

		pos = mix(pos, p_arm, arm_mask);
		nrm = normalize(mix(nrm, rotate_x(rotate_z(nrm, vec3(0.0), tpose_drop_z * 0.7), vec3(0.0), shoulder_angle * 0.6), arm_mask));
	}

	// -------------------------------------------------------------------------
	// 3. TORSO SPINE TWIST, CROUCH / PICKUP BEND, IDLE BREATHING & HEAD LOOK
	// -------------------------------------------------------------------------
	float torso_mask = smoothstep(0.46, 0.56, yn);
	if (torso_mask > 0.001) {
		float spine_twist = sin(walk_phase) * (0.085 * walk_amount + 0.06 * run_amount) * (1.0 - is_seated) * (1.0 - carry_amount * 0.7);
		pos = rotate_y(pos, vec3(center.x, pos.y, center.z), spine_twist * torso_mask);

		// Forward torso bend when crouching or picking up an object (beugen)
		float bend_angle = -(0.32 * crouch_amount + 0.68 * pickup_bend) + 0.48 * slide_amount;
		if (abs(bend_angle) > 0.005) {
			vec3 waist_pivot = vec3(center.x, aabb_min.y + 0.48 * sz.y, center.z);
			pos = mix(pos, rotate_x(pos, waist_pivot, bend_angle), torso_mask);
		}
	}

	// Lower overall body during crouch or slide while keeping feet planted
	float crouch_drop = (0.20 * crouch_amount + 0.28 * slide_amount) * sz.y * smoothstep(0.12, 0.48, yn);
	pos.y -= crouch_drop;

	// Idle chest breathing rise & ribcage expansion (yn between 0.55 and 0.82)
	float chest_mask = smoothstep(0.52, 0.62, yn) * (1.0 - smoothstep(0.78, 0.84, yn));
	if (chest_mask > 0.001) {
		float breath = sin(idle_time * 2.1);
		pos.y += breath * 0.009 * sz.y * chest_mask * idle_factor;
		pos.z += breath * 0.012 * sz.z * sign(pos.z - center.z) * chest_mask * idle_factor;
	}

	// Head look-around motion when standing still (yn > 0.82)
	float head_mask = smoothstep(0.81, 0.86, yn);
	if (head_mask > 0.001) {
		float look_yaw = sin(idle_time * 0.85) * 0.16 * idle_factor;
		float look_pitch = cos(idle_time * 1.15) * 0.045 * idle_factor;
		vec3 neck_pivot = vec3(center.x, aabb_min.y + 0.82 * sz.y, center.z);
		vec3 p_head = rotate_y(pos, neck_pivot, look_yaw);
		p_head = rotate_x(p_head, neck_pivot, look_pitch);
		pos = mix(pos, p_head, head_mask);
	}

	VERTEX = pos;
	NORMAL = nrm;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 base_col = tex.rgb * albedo_color.rgb;
	if (vertex_color_use_as_albedo) {
		base_col *= COLOR.rgb;
	}
	ALBEDO = base_col;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
	BACKLIGHT = backlight.rgb;
}
