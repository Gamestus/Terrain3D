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
	float resolution = 10.0 * exp2(-3.0);
	vec2 uv = world_xz / puddle_ripple_scale * resolution;
	vec2 p0 = floor(uv);
	vec2 circles = vec2(0.0);
	for (float j = -puddle_ripple_max_radius; j <= puddle_ripple_max_radius; ++j) {
		for (float i = -puddle_ripple_max_radius; i <= puddle_ripple_max_radius; ++i) {
			if (max(abs(i), abs(j)) > __ripple_radius + 0.5) {
				continue;
			}
			vec2 pi = p0 + vec2(i, j);
			vec2 hsh = puddle_ripple_hash22(pi);
			// Fewer active drops when rain is light (stochastic cull).
			if (puddle_ripple_hash12(hsh + 0.37) > __rain) {
				continue;
			}
			vec2 p = pi + puddle_ripple_hash22(hsh);
			float t = fract(puddle_ripple_speed * TIME + puddle_ripple_hash12(hsh));
			vec2 v = p - uv;
			float d = length(v) - (__ripple_radius + 1.0) * t;
			float h = 1e-3;
			float d1 = d - h;
			float d2 = d + h;
			float p1 = sin(31.0 * d1) * smoothstep(-0.6, -0.3, d1) * smoothstep(0.0, -0.3, d1);
			float p2 = sin(31.0 * d2) * smoothstep(-0.6, -0.3, d2) * smoothstep(0.0, -0.3, d2);
			circles += 0.5 * normalize(v) * ((p2 - p1) / (2.0 * h) * (1.0 - t) * (1.0 - t));
		}
	}
	float __grid = __ripple_radius * 2.0 + 1.0;
	circles /= max(__grid * __grid, 1.0);
	float intensity = mix(0.01, 0.15, smoothstep(0.1, 0.6, abs(fract(0.05 * TIME + 0.5) * 2.0 - 1.0)));
	vec3 n = vec3(circles, sqrt(1.0 - dot(circles, circles)));
	vec2 __offset = (intensity * n.xy) + 5.0 * pow(clamp(dot(n, normalize(vec3(1.0, 0.7, 0.5))), 0.0, 1.0), 6.0);
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
uniform float puddle_ripple_max_radius : hint_range(0.0, 5.0, 1.0) = 2.0;
uniform float puddle_rain_intensity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float puddle_ripple_scale : hint_range(0.1, 10.0, 0.1) = 1.0;
uniform float puddle_ripple_speed : hint_range(0.1, 2.0, 0.01) = 0.5;
uniform float puddle_ripple_strength : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float puddle_normal_depth : hint_range(0.0, 2.0, 0.01) = 1.0;
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
	float __puddle_mask = clamp(__noise_mask * __height_mask * __slope_mask, 0.0, 1.0);

	// Full ripple strength under the puddle; mask only blends material, not wave amplitude.
	vec2 __ripple_offset = puddle_get_ripple_offset(v_vertex.xz) * puddle_ripple_strength;
	vec3 __puddle_nrm = normalize(vec3(-__ripple_offset.x, 1.0, -__ripple_offset.y));
	mat.albedo_height.rgb = mix(mat.albedo_height.rgb, puddle_color.rgb, __puddle_mask * puddle_color.a);
	mat.normal_rough = mix(mat.normal_rough, vec4(__puddle_nrm, puddle_roughness), __puddle_mask);
	mat.normal_map_depth = mix(mat.normal_map_depth, puddle_normal_depth, __puddle_mask);

//INSERT: PUDDLES_APPLY
	roughness = mix(roughness, puddle_roughness, __puddle_mask);

)"
