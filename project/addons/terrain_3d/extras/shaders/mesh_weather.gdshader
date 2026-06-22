// Mesh PBR with Terrain3D snow and puddles synced via terrain_mesh_material.gd.
// Does not sample terrain ground textures or control maps.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	#define fma(a, b, c) ((a) * (b) + (c))
	#define dFdxCoarse(a) dFdx(a)
	#define dFdyCoarse(a) dFdy(a)
#endif

group_uniforms base;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float normal_depth : hint_range(0.0, 2.0) = 1.0;
uniform float uv_scale : hint_range(0.01, 100.0) = 1.0;
uniform bool use_textures = true;
group_uniforms;

group_uniforms terrain_snow;
uniform float _texture_normal_depth_array[32];
uniform float _texture_ao_strength_array[32];
uniform float _texture_ao_affect_array[32];
uniform float _texture_roughness_mod_array[32];
uniform float _texture_height_blend_array[32];
uniform float _texture_uv_scale_array[32];
uniform vec2 _texture_detile_array[32];
uniform vec4 _texture_color_array[32];
uniform highp sampler2DArray _texture_array_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform highp sampler2DArray _texture_array_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
group_uniforms;

group_uniforms shader_uniforms.snow;
uniform bool snow_enabled = false;
uniform int snow_texture : hint_range(0, 31) = 0;
uniform float snow_amount : hint_range(0, 1) = 0.0;
uniform float snow_blend_sharpness : hint_range(0, 1) = 0.5;
group_uniforms;

group_uniforms shader_uniforms.puddles;
uniform bool puddles_enabled = false;
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

varying vec3 v_vertex;
varying vec3 v_normal;
varying mat3 TBN;

float random(in vec2 xy) {
	return fract(sin(dot(xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 rotate_vec2(const vec2 v, const vec2 cs) {
	return vec2(fma(cs.x, v.x, cs.y * v.y), fma(cs.x, v.y, -cs.y * v.x));
}

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
			float max_ripple_dist = __ripple_radius + 1.0;
			float drop_fade = 1.0 - smoothstep(max_ripple_dist + 0.1, max_ripple_dist + 0.35, length(uv - p));
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

void vertex() {
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 w_tangent = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
	vec3 w_binormal = normalize((MODEL_MATRIX * vec4(BINORMAL, 0.0)).xyz);
	TBN = mat3(w_tangent, w_binormal, v_normal);
}

void fragment() {
	vec2 mesh_uv = UV * uv_scale;
	vec3 base_ddx = dFdxCoarse(v_vertex);
	vec3 base_ddy = dFdyCoarse(v_vertex);

	vec4 albedo_height;
	vec4 normal_rough;
	float normal_map_depth = normal_depth;
	float ao = 1.0;
	float ao_affect = 0.0;

	if (use_textures) {
		albedo_height = texture(albedo_texture, mesh_uv);
		albedo_height.rgb *= albedo.rgb;
		normal_rough = texture(normal_texture, mesh_uv);
		normal_rough.a = clamp(normal_rough.a + roughness, 0.0, 1.0);
	} else {
		albedo_height = vec4(albedo.rgb, 0.5);
		normal_rough = vec4(0.0, 1.0, 0.0, roughness);
	}

	if (snow_enabled && snow_amount > 0.001) {
		int __snow_id = clamp(snow_texture, 0, 31);
		float __snow_scale = _texture_uv_scale_array[__snow_id];
		vec4 __snow_dd = vec4(base_ddx.xz, base_ddy.xz) * __snow_scale;

		vec2 __snow_uv = v_vertex.xz;
		vec2 __snow_pos = v_vertex.xz;
		vec2 __snow_center = floor(fma(__snow_pos, vec2(__snow_scale), vec2(0.5)));
		vec2 __snow_detile = fma(random(__snow_center), 2.0, -1.0) * _texture_detile_array[__snow_id] * TAU;
		vec2 __snow_cs_angle = vec2(cos(__snow_detile.x), sin(__snow_detile.x));

		__snow_uv = rotate_vec2(fma(__snow_uv, vec2(__snow_scale), -__snow_center), __snow_cs_angle) + __snow_center + __snow_detile.y - 0.5;
		__snow_dd.xy = rotate_vec2(__snow_dd.xy, __snow_cs_angle);
		__snow_dd.zw = rotate_vec2(__snow_dd.zw, __snow_cs_angle);

		vec4 __snow_alb = textureGrad(_texture_array_albedo, vec3(__snow_uv, float(__snow_id)), __snow_dd.xy, __snow_dd.zw);
		vec4 __snow_nrm = textureGrad(_texture_array_normal, vec3(__snow_uv, float(__snow_id)), __snow_dd.xy, __snow_dd.zw);
		__snow_alb.rgb *= _texture_color_array[__snow_id].rgb;
		__snow_nrm.a = clamp(__snow_nrm.a + _texture_roughness_mod_array[__snow_id], 0.0, 1.0);

		__snow_nrm.xyz = fma(__snow_nrm.xzy, vec3(2.0), vec3(-1.0));
		float __snow_ao = length(__snow_nrm.xyz) * 2.0 - 1.0;
		__snow_ao = mix(
			__snow_ao * __snow_ao * _texture_ao_strength_array[__snow_id] + 1.0 - _texture_ao_strength_array[__snow_id],
			1.0,
			__snow_alb.a * __snow_alb.a);
		__snow_nrm.xyz = normalize(__snow_nrm.xyz);
		__snow_nrm.xz = rotate_vec2(__snow_nrm.xz, __snow_cs_angle);
		__snow_alb.a = clamp(fma(__snow_alb.a - 0.5, _texture_height_blend_array[__snow_id], 0.5), 0.0, 1.0);

		float __effective_snow = snow_amount;
		float __snow_sharpness = fma(60.0, snow_blend_sharpness, 4.0);
		float __terrain_weight = exp2(__snow_sharpness * log2(max(albedo_height.a + 1.0 - __effective_snow, 1e-5)));
		float __snow_weight = exp2(__snow_sharpness * log2(max(__snow_alb.a + __effective_snow, 1e-5)));
		float __snow_blend = clamp(__effective_snow * __snow_weight / max(__terrain_weight + __snow_weight, 1e-5), 0.0, 1.0);

		albedo_height = mix(albedo_height, __snow_alb, __snow_blend);
		normal_rough = mix(normal_rough, __snow_nrm, __snow_blend);
		normal_map_depth = mix(normal_map_depth, _texture_normal_depth_array[__snow_id], __snow_blend);
		ao = mix(ao, __snow_ao, __snow_blend);
		ao_affect = mix(ao_affect, _texture_ao_affect_array[__snow_id], __snow_blend);
	}

	float __puddle_mask = 0.0;
	if (puddles_enabled) {
		float __noise = texture(puddle_noise, v_vertex.xz * puddle_noise_scale).r;
		float __noise_mask = smoothstep(
			puddle_noise_threshold - puddle_edge_fade,
			puddle_noise_threshold + puddle_edge_fade,
			__noise);
		float __height_mask = 1.0 - smoothstep(
			puddle_max_material_height - puddle_edge_fade,
			puddle_max_material_height + puddle_edge_fade,
			albedo_height.a);
		float __slope_mask = smoothstep(
			puddle_slope_limit - puddle_slope_falloff,
			puddle_slope_limit,
			v_normal.y);
		float __world_height_mask = smoothstep(
			puddle_height_cutoff - puddle_edge_fade,
			puddle_height_cutoff + puddle_edge_fade,
			v_vertex.y);
		__puddle_mask = clamp(
			__noise_mask * __height_mask * __slope_mask * __world_height_mask,
			0.0, 1.0);

		vec2 __ripple_offset = vec2(0.0);
		if (puddle_ripples_enabled && __puddle_mask > 0.001 && puddle_rain_intensity > 0.001) {
			__ripple_offset = puddle_get_ripple_offset(v_vertex.xz) * puddle_ripple_strength;
		}
		vec3 w_puddle_nrm = normalize(vec3(-__ripple_offset.x, 1.0, -__ripple_offset.y));
		vec3 t_puddle_nrm = vec3(
			dot(TBN[0], w_puddle_nrm),
			dot(TBN[2], w_puddle_nrm),
			dot(TBN[1], w_puddle_nrm));
		albedo_height.rgb = mix(albedo_height.rgb, puddle_color.rgb, __puddle_mask * puddle_color.a);
		normal_rough = mix(normal_rough, vec4(t_puddle_nrm, puddle_roughness), __puddle_mask);
		normal_map_depth = mix(normal_map_depth, puddle_normal_depth, __puddle_mask);
	}

	float roughness_out = clamp(normal_rough.a, 0.0, 1.0);
	if (puddles_enabled) {
		roughness_out *= mix(1.0, 0.0, material_wetness);
		roughness_out = mix(roughness_out, puddle_roughness, __puddle_mask);
	}

	ALBEDO = albedo_height.rgb;
	ROUGHNESS = roughness_out;
	float __base_spec = 1.0 - normal_rough.a;
	float __wet_spec = mix(__base_spec, 1.0, material_wetness);
	SPECULAR = puddles_enabled ? mix(__wet_spec, puddle_specular, __puddle_mask) : __base_spec;
	METALLIC = puddles_enabled ? puddle_metallic * __puddle_mask : metallic;
	NORMAL_MAP = fma(normalize(normal_rough.xzy), vec3(0.5), vec3(0.5));
	NORMAL_MAP_DEPTH = normal_map_depth;
	AO = clamp(ao, 0.0, 1.0);
	AO_LIGHT_AFFECT = ao_affect;
}
