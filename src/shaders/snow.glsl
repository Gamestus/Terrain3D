// Copyright © 2023-2026 Cory Petkovsek, Roope Palmroos, and Contributors.

R"(

//INSERT: SNOW_UNIFORMS
group_uniforms shader_uniforms.snow;
uniform int snow_texture : hint_range(0, 31) = 0;
uniform float snow_amount : hint_range(0, 1) = 0.0;
uniform float snow_blend_sharpness : hint_range(0, 1) = 0.5;
group_uniforms;

//INSERT: SNOW_BLEND
	{
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
		__snow_nrm.a = clamp(__snow_nrm.a + _texture_roughness_mod_array[__snow_id], 0., 1.);

		__snow_nrm.xyz = fma(__snow_nrm.xzy, vec3(2.0), vec3(-1.0));
		float __snow_ao = length(__snow_nrm.xyz) * 2.0 - 1.0;
		__snow_ao = mix(__snow_ao * __snow_ao * _texture_ao_strength_array[__snow_id] + 1.0 - _texture_ao_strength_array[__snow_id], 1.0, __snow_alb.a * __snow_alb.a);
		__snow_nrm.xyz = normalize(__snow_nrm.xyz);
		__snow_nrm.xz = rotate_vec2(__snow_nrm.xz, __snow_cs_angle);
		__snow_alb.a = clamp(fma(__snow_alb.a - 0.5, _texture_height_blend_array[__snow_id], 0.5), 0., 1.);

		float __effective_snow = clamp(snow_amount + snow_amount * (1.0 - snow_amount) * (mat.snow_amount_modifier - 1.0), 0., 1.);
		float __snow_sharpness = fma(60., snow_blend_sharpness, 4.);
		float __terrain_weight = exp2(__snow_sharpness * log2(max(mat.albedo_height.a + 1.0 - __effective_snow, 1e-5)));
		float __snow_weight = exp2(__snow_sharpness * log2(max(__snow_alb.a + __effective_snow, 1e-5)));
		float __snow_blend = clamp(__effective_snow * __snow_weight / max(__terrain_weight + __snow_weight, 1e-5), 0., 1.);

		mat.albedo_height = mix(mat.albedo_height, __snow_alb, __snow_blend);
		mat.normal_rough = mix(mat.normal_rough, __snow_nrm, __snow_blend);
		mat.normal_map_depth = mix(mat.normal_map_depth, _texture_normal_depth_array[__snow_id], __snow_blend);
		mat.ao = mix(mat.ao, __snow_ao, __snow_blend);
		mat.ao_affect = mix(mat.ao_affect, _texture_ao_affect_array[__snow_id], __snow_blend);
	}

)" 
