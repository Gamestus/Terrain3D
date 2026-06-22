# Copyright © 2023-2026 Cory Petkovsek, Roope Palmroos, and Contributors.
# Syncs Terrain3D shader uniforms into a ShaderMaterial on a MeshInstance3D.
@tool
extends Node

const DEFAULT_MATERIAL: ShaderMaterial = preload("res://addons/terrain_3d/extras/shaders/M_terrain_mesh.tres")

@export var terrain: Terrain3D:
	set(value):
		_disconnect_terrain()
		terrain = value
		_connect_terrain()
		call_deferred("_sync_uniforms")

@export var mesh_instance: MeshInstance3D:
	set(value):
		mesh_instance = value
		_apply_material()
		call_deferred("_sync_uniforms")

@export var material: ShaderMaterial:
	set(value):
		material = value
		_ensure_material()
		_apply_material()
		call_deferred("_sync_uniforms")

@export var puddle_ripples_enabled: bool = true:
	set(value):
		puddle_ripples_enabled = value
		if material:
			material.set_shader_parameter("puddle_ripples_enabled", value)


func _ready() -> void:
	_ensure_material()
	if not terrain:
		var node: Node = self
		while node:
			if node is Terrain3D:
				terrain = node
				break
			node = node.get_parent()
	_apply_material()
	_connect_terrain()
	call_deferred("_sync_uniforms")


func _enter_tree() -> void:
	call_deferred("_connect_terrain")
	call_deferred("_sync_uniforms")


func _ensure_material() -> void:
	if not material:
		material = DEFAULT_MATERIAL.duplicate() as ShaderMaterial


func _exit_tree() -> void:
	_disconnect_terrain()


func _apply_material() -> void:
	if not mesh_instance or not material:
		return
	if mesh_instance.material_override != material:
		mesh_instance.material_override = material


func _connect_terrain() -> void:
	if not terrain or not is_inside_tree():
		return
	if not terrain.data.maps_changed.is_connected(_sync_uniforms):
		terrain.data.maps_changed.connect(_sync_uniforms)
	if not terrain.assets.textures_changed.is_connected(_sync_uniforms):
		terrain.assets.textures_changed.connect(_sync_uniforms)
	if not terrain.material_changed.is_connected(_sync_uniforms):
		terrain.material_changed.connect(_sync_uniforms)


func _disconnect_terrain() -> void:
	if not terrain:
		return
	if terrain.data and terrain.data.maps_changed.is_connected(_sync_uniforms):
		terrain.data.maps_changed.disconnect(_sync_uniforms)
	if terrain.assets and terrain.assets.textures_changed.is_connected(_sync_uniforms):
		terrain.assets.textures_changed.disconnect(_sync_uniforms)
	if terrain.material_changed.is_connected(_sync_uniforms):
		terrain.material_changed.disconnect(_sync_uniforms)


func _sync_uniforms() -> void:
	if not terrain or not material:
		return
	if not terrain.data or not terrain.assets:
		return
	if terrain.data.get_region_count() == 0 or terrain.assets.get_texture_count() == 0:
		return

	material.set_shader_parameter("_vertex_spacing", terrain.vertex_spacing)
	material.set_shader_parameter("_vertex_density", 1.0 / terrain.vertex_spacing)
	material.set_shader_parameter("_region_size", terrain.region_size)
	material.set_shader_parameter("_region_texel_size", 1.0 / terrain.region_size)
	material.set_shader_parameter("_region_map_size", 32)
	material.set_shader_parameter("_region_map", terrain.data.get_region_map())
	material.set_shader_parameter("_region_locations", terrain.data.get_region_locations())
	material.set_shader_parameter("_height_maps", terrain.data.get_height_maps_rid())
	material.set_shader_parameter("_control_maps", terrain.data.get_control_maps_rid())

	var assets: Terrain3DAssets = terrain.assets
	material.set_shader_parameter("_texture_array_albedo", assets.get_albedo_array_rid())
	material.set_shader_parameter("_texture_array_normal", assets.get_normal_array_rid())
	material.set_shader_parameter("_texture_color_array", assets.get_texture_colors())
	material.set_shader_parameter("_texture_normal_depth_array", assets.get_texture_normal_depths())
	material.set_shader_parameter("_texture_ao_strength_array", assets.get_texture_ao_strengths())
	material.set_shader_parameter("_texture_ao_affect_array", assets.get_texture_ao_light_affects())
	material.set_shader_parameter("_texture_roughness_mod_array", assets.get_texture_roughness_mods())
	material.set_shader_parameter("_texture_uv_scale_array", assets.get_texture_uv_scales())
	material.set_shader_parameter("_texture_detile_array", assets.get_texture_detiles())
	material.set_shader_parameter("_texture_height_blend_array", assets.get_texture_height_blends())
	material.set_shader_parameter("_texture_snow_amount_array", assets.get_texture_snow_amount_mods())

	var terrain_mat: Terrain3DMaterial = terrain.material
	material.set_shader_parameter("auto_shader_enabled", terrain_mat.auto_shader_enabled)
	material.set_shader_parameter("snow_enabled", terrain_mat.snow_enabled)
	_set_shader_param("blend_sharpness", terrain_mat.get_shader_param("blend_sharpness"))
	_set_shader_param("auto_slope", terrain_mat.get_shader_param("auto_slope"))
	_set_shader_param("auto_height_reduction", terrain_mat.get_shader_param("auto_height_reduction"))
	_set_shader_param("auto_base_texture", terrain_mat.get_shader_param("auto_base_texture"))
	_set_shader_param("auto_overlay_texture", terrain_mat.get_shader_param("auto_overlay_texture"))
	_set_shader_param("snow_texture", terrain_mat.get_shader_param("snow_texture"))
	_set_shader_param("snow_blend_sharpness", terrain_mat.get_shader_param("snow_blend_sharpness"))
	var snow_amount: Variant = terrain_mat.get_shader_param("snow_amount")
	if terrain_mat.snow_enabled and snow_amount != null:
		_set_shader_param("snow_amount", snow_amount)
	else:
		material.set_shader_parameter("snow_amount", 0.0)

	_sync_puddle_params(terrain_mat)


func _sync_puddle_params(terrain_mat: Terrain3DMaterial) -> void:
	material.set_shader_parameter("puddles_enabled", terrain_mat.puddles_enabled)
	if not terrain_mat.puddles_enabled:
		material.set_shader_parameter("material_wetness", 0.0)
		return

	const PUDDLE_PARAMS: Array[StringName] = [
		&"puddle_noise",
		&"puddle_noise_scale",
		&"puddle_noise_threshold",
		&"puddle_max_material_height",
		&"puddle_edge_fade",
		&"puddle_slope_limit",
		&"puddle_slope_falloff",
		&"puddle_color",
		&"puddle_roughness",
		&"puddle_specular",
		&"puddle_metallic",
		&"puddle_height_cutoff",
		&"puddle_ripples_enabled",
		&"puddle_ripple_max_radius",
		&"puddle_rain_intensity",
		&"puddle_ripple_scale",
		&"puddle_ripple_speed",
		&"puddle_ripple_strength",
		&"puddle_normal_depth",
		&"material_wetness",
	]
	for param_name: StringName in PUDDLE_PARAMS:
		_set_shader_param(param_name, terrain_mat.get_shader_param(param_name))
	if terrain_mat.get_shader_param("puddle_ripples_enabled") == null:
		material.set_shader_parameter("puddle_ripples_enabled", puddle_ripples_enabled)
	var wetness: Variant = terrain_mat.get_shader_param("material_wetness")
	material.set_shader_parameter("material_wetness", wetness if wetness != null else 0.0)


func _set_shader_param(param_name: StringName, value: Variant) -> void:
	if value != null:
		material.set_shader_parameter(param_name, value)
