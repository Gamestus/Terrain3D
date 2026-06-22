// Copyright © 2023-2026 Cory Petkovsek, Roope Palmroos, and Contributors.
// Rain ripple effect adapted from Zavie / shadecore_dev (CC0):
// https://godotshaders.com/shader/rain-puddles-with-ripples-and-reflection/

R"(

//INSERT: PUDDLES_FUNCTIONS
const float PUDDLE_RIPPLE_HASHSCALE1 = 0.1031;
const vec3 PUDDLE_RIPPLE_HASHSCALE3 = vec3(0.1031, 0.1030, 0.0973);

float puddle_ripple_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * PUDDLE_RIPPLE_HASHSCALE1);
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 puddle_ripple_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * PUDDLE_RIPPLE_HASHSCALE3);
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec2 puddle_get_ripple_offset(vec2 world_xz) {
	float __rain = clamp(puddle_rain_intensity, 0.0, 1.0);
	if (__rain < 0.001) {
		return vec2(0.0);
	}

	float __ripple_radius = puddle_ripple_max_radius * __rain;
	const float resolution = 1.25;
	vec2 uv = world_xz / puddle_ripple_scale * resolution;
	vec2 p0 = floor(uv);
	vec2 circles = vec2(0.0);
	float weight_sum = 0.0;
	int rad = clamp(int(floor(__ripple_radius + 0.5)), 0, int(puddle_ripple_max_radius));
	for (int j = -rad; j <= rad; ++j) {
		for (int i = -rad; i <= rad; ++i) {
			vec2 ij = vec2(float(i), float(j));
			if (length(ij) > __ripple_radius + 0.5) {
				continue;
			}
			vec2 pi = p0 + ij;
			vec2 hsh = puddle_ripple_hash22(pi);
			// Fewer active drops when rain is light (stochastic cull).
			if (puddle_ripple_hash12(hsh + 0.37) > __rain) {
				continue;
			}
			vec2 p = pi + puddle_ripple_hash22(hsh);
			float t = fract(puddle_ripple_speed * TIME + puddle_ripple_hash12(hsh));
			vec2 v = p - uv;
			float dist = length(v);
			float d = dist - (__ripple_radius + 1.0) * t;
			float h = 1e-3;
			float d1 = d - h;
			float d2 = d + h;
			float p1 = sin(31.0 * d1) * smoothstep(-0.6, -0.3, d1) * smoothstep(0.0, -0.3, d1);
			float p2 = sin(31.0 * d2) * smoothstep(-0.6, -0.3, d2) * smoothstep(0.0, -0.3, d2);
			vec2 dir = v / max(dist, 1e-4);
			vec2 contrib = 0.5 * dir * ((p2 - p1) / (2.0 * h) * (1.0 - t) * (1.0 - t));
			// Fade around the drop center so rings are not clipped by the cell origin.
			float max_ripple_dist = __ripple_radius + 1.0;
			float drop_fade = 1.0 - smoothstep(max_ripple_dist + 0.1, max_ripple_dist + 0.35, length(uv - p));
			// Hide square voronoi seams at cell edges without offsetting ripple centers.
			vec2 cell_q = fract(uv - pi);
			float edge_dist = min(min(cell_q.x, 1.0 - cell_q.x), min(cell_q.y, 1.0 - cell_q.y));
			float seam_fade = smoothstep(0.0, 0.08, edge_dist);
			float w = drop_fade * seam_fade;
			circles += contrib * w;
			weight_sum += w;
		}
	}
	circles /= max(weight_sum, 1e-4);
	float intensity = mix(0.01, 0.15, smoothstep(0.1, 0.6, abs(fract(0.05 * TIME + 0.5) * 2.0 - 1.0)));
	vec3 n = vec3(circles, sqrt(max(1.0 - dot(circles, circles), 0.0)));
	vec3 light_dir = normalize(vec3(1.0, 0.7, 0.5));
	float spec = pow(clamp(dot(n, light_dir), 0.0, 1.0), 4.0);
	vec2 __offset = intensity * n.xy + light_dir.xy * spec * 0.35;
	return __offset * __rain;
}

//INSERT: PUDDLES_UNIFORMS
group_uniforms shader_uniforms.puddles;
uniform sampler2D puddle_noise : repeat_enable, hint_default_white;
uniform vec2 puddle_noise_scale = vec2(0.01);
uniform float puddle_noise_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float puddle_max_material_height : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float puddle_edge_fade : hint_range(0.0, 0.5, 0.001) = 0.08;
uniform float puddle_slope_limit : hint_range(0.0, 1.0, 0.01) = 0.88;
uniform float puddle_slope_falloff : hint_range(0.0, 0.5, 0.001) = 0.12;
uniform vec4 puddle_color : source_color = vec4(0.08, 0.12, 0.16, 0.85);
uniform float puddle_roughness : hint_range(0.0, 1.0, 0.01) = 0.04;
uniform float puddle_specular : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform float puddle_metallic : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform bool puddle_ripples_enabled = true;
uniform float puddle_height_cutoff : hint_range(-1000.0, 1000.0, 0.1) = -1000.0;
uniform float puddle_ripple_max_radius : hint_range(0.0, 5.0, 1.0) = 2.0;
uniform float puddle_rain_intensity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float puddle_ripple_scale : hint_range(0.1, 10.0, 0.1) = 1.0;
uniform float puddle_ripple_speed : hint_range(0.1, 2.0, 0.01) = 0.5;
uniform float puddle_ripple_strength : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float puddle_normal_depth : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float material_wetness : hint_range(0.0, 1.0, 0.01) = 0.0;
group_uniforms;

//INSERT: PUDDLES
	float __noise = texture(puddle_noise, v_vertex.xz * puddle_noise_scale).r;
	float __noise_mask = smoothstep(
		puddle_noise_threshold - puddle_edge_fade,
		puddle_noise_threshold + puddle_edge_fade,
		__noise);
	float __height_mask = 1.0 - smoothstep(
		puddle_max_material_height - puddle_edge_fade,
		puddle_max_material_height + puddle_edge_fade,
		mat.albedo_height.a);
	float __slope_mask = smoothstep(
		puddle_slope_limit - puddle_slope_falloff,
		puddle_slope_limit,
		w_normal.y);
	float __world_height_mask = smoothstep(
		puddle_height_cutoff - puddle_edge_fade,
		puddle_height_cutoff + puddle_edge_fade,
		v_vertex.y);
	float __puddle_mask = clamp(
		__noise_mask * __height_mask * __slope_mask * __world_height_mask,
		0.0, 1.0);

	// Full ripple strength under the puddle; skip expensive ripple where there is no puddle.
	vec2 __ripple_offset = vec2(0.0);
	if (__puddle_mask > 0.001 && puddle_ripples_enabled && puddle_rain_intensity > 0.001) {
		__ripple_offset = puddle_get_ripple_offset(v_vertex.xz) * puddle_ripple_strength;
	}
	vec3 __puddle_nrm = normalize(vec3(-__ripple_offset.x, 1.0, -__ripple_offset.y));
	mat.albedo_height.rgb = mix(mat.albedo_height.rgb, puddle_color.rgb, __puddle_mask * puddle_color.a);
	mat.normal_rough = mix(mat.normal_rough, vec4(__puddle_nrm, puddle_roughness), __puddle_mask);
	mat.normal_map_depth = mix(mat.normal_map_depth, puddle_normal_depth, __puddle_mask);

//INSERT: PUDDLES_APPLY
	// Global wetness on base material (specular in PUDDLES_OUTPUT_ROUGHNESS); puddles unchanged.
	roughness *= mix(1.0, 0.0, material_wetness);
	roughness = mix(roughness, puddle_roughness, __puddle_mask);

)"
