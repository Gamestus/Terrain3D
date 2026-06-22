# Syncs Terrain3D shader uniforms into ShaderMaterials on a MeshInstance3D.
@tool
extends Node

const DEFAULT_TERRAIN_MATERIAL: ShaderMaterial = preload("res://addons/terrain_3d/extras/shaders/M_terrain_mesh.tres")
const DEFAULT_WEATHER_MATERIAL: ShaderMaterial = preload("res://addons/terrain_3d/extras/shaders/M_mesh_weather.tres")
const TERRAIN_MESH_SHADER: Shader = preload("res://addons/terrain_3d/extras/shaders/terrain_mesh.gdshader")
const MESH_WEATHER_SHADER: Shader = preload("res://addons/terrain_3d/extras/shaders/mesh_weather.gdshader")

enum ApplyMode {
	## Assign each surface entry material via surface override slots.
	SURFACE_MASK,
	## Do not modify mesh materials; assign materials to surfaces yourself.
	MANUAL,
}

@export var terrain: Terrain3D:
	set(value):
		_disconnect_terrain()
		terrain = value
		_connect_terrain()
		call_deferred("_sync_uniforms")

@export var mesh_instance: MeshInstance3D:
	set(value):
		_clear_applied_surfaces()
		mesh_instance = value
		_apply_materials()
		call_deferred("_sync_uniforms")

@export var apply_mode: ApplyMode = ApplyMode.SURFACE_MASK:
	set(value):
		apply_mode = value
		_apply_materials()

@export var surfaces: Array[TerrainMeshSurfaceMaterial] = []:
	set(value):
		_disconnect_surface_configs()
		surfaces = value
		_connect_surface_configs()
		_apply_materials()
		call_deferred("_sync_uniforms")

## Fallback when [Terrain3DMaterial] has no [code]puddle_ripples_enabled[/code] shader param.
@export var puddle_ripples_enabled: bool = true:
	set(value):
		puddle_ripples_enabled = value
		for mat: ShaderMaterial in _get_all_materials():
			mat.set_shader_parameter("puddle_ripples_enabled", value)

var _applied_surfaces: Dictionary = {}


func _ready() -> void:
	_ensure_default_surfaces()
	if not terrain:
		var node: Node = self
		while node:
			if node is Terrain3D:
				terrain = node
				break
			node = node.get_parent()
	_connect_surface_configs()
	_apply_materials()
	_connect_terrain()
	call_deferred("_sync_uniforms")
	call_deferred("_sync_uniforms_when_ready")


func _sync_uniforms_when_ready() -> void:
	if not terrain or not is_inside_tree():
		return
	if terrain.data and terrain.data.get_region_count() > 0:
		return
	await get_tree().process_frame
	_sync_uniforms()


func _enter_tree() -> void:
	_connect_surface_configs()
	call_deferred("_connect_terrain")
	call_deferred("_sync_uniforms")


func _exit_tree() -> void:
	_clear_applied_surfaces()
	_disconnect_surface_configs()
	_disconnect_terrain()


func _ensure_default_surfaces() -> void:
	if not surfaces.is_empty():
		return
	var config := TerrainMeshSurfaceMaterial.new()
	config.surface = 0
	config.kind = TerrainMeshSurfaceMaterial.Kind.TERRAIN
	surfaces = [config]


func _connect_surface_configs() -> void:
	for config: TerrainMeshSurfaceMaterial in surfaces:
		if config and not config.changed.is_connected(_on_surface_config_changed):
			config.changed.connect(_on_surface_config_changed)


func _disconnect_surface_configs() -> void:
	for config: TerrainMeshSurfaceMaterial in surfaces:
		if config and config.changed.is_connected(_on_surface_config_changed):
			config.changed.disconnect(_on_surface_config_changed)


func _on_surface_config_changed() -> void:
	_apply_materials()
	call_deferred("_sync_uniforms")


func _create_default_material(kind: TerrainMeshSurfaceMaterial.Kind) -> ShaderMaterial:
	var preset: ShaderMaterial = (
		DEFAULT_WEATHER_MATERIAL if kind == TerrainMeshSurfaceMaterial.Kind.WEATHER_ONLY else DEFAULT_TERRAIN_MATERIAL
	)
	return preset.duplicate() as ShaderMaterial


func _shader_matches(shader: Shader, reference: Shader) -> bool:
	if not shader or not reference:
		return false
	return shader == reference or shader.resource_path == reference.resource_path


func _resolve_surface_material(config: TerrainMeshSurfaceMaterial) -> ShaderMaterial:
	if config.material:
		return config.material
	if _applied_surfaces.has(config.surface):
		return _applied_surfaces[config.surface]
	if apply_mode == ApplyMode.MANUAL and mesh_instance:
		return mesh_instance.get_surface_override_material(config.surface) as ShaderMaterial
	return null


func _apply_materials() -> void:
	if not mesh_instance:
		return

	mesh_instance.material_override = null

	if apply_mode == ApplyMode.MANUAL:
		_clear_applied_surfaces()
		return

	var mesh: Mesh = mesh_instance.mesh
	if not mesh:
		_clear_applied_surfaces()
		return

	var next_applied: Dictionary = {}
	var assigned_surfaces: Dictionary = {}
	for config: TerrainMeshSurfaceMaterial in surfaces:
		if not config:
			continue
		var surface: int = config.surface
		if surface < 0 or surface >= mesh.get_surface_count():
			continue
		if assigned_surfaces.has(surface):
			continue
		assigned_surfaces[surface] = true

		var mat: ShaderMaterial = _resolve_surface_material(config)
		if not mat:
			mat = _create_default_material(config.kind)
			config.material = mat

		mesh_instance.set_surface_override_material(surface, mat)
		next_applied[surface] = mat

	for surface: int in _applied_surfaces:
		if not next_applied.has(surface):
			if mesh_instance.get_surface_override_material(surface) == _applied_surfaces[surface]:
				mesh_instance.set_surface_override_material(surface, null)

	_applied_surfaces = next_applied


func _clear_applied_surfaces() -> void:
	if not mesh_instance:
		_applied_surfaces.clear()
		return
	for surface: int in _applied_surfaces:
		if mesh_instance.get_surface_override_material(surface) == _applied_surfaces[surface]:
			mesh_instance.set_surface_override_material(surface, null)
	_applied_surfaces.clear()
	if mesh_instance:
		mesh_instance.material_override = null


func _get_all_materials() -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	var seen: Dictionary = {}

	if mesh_instance:
		for config: TerrainMeshSurfaceMaterial in surfaces:
			if not config:
				continue
			var mat: ShaderMaterial = mesh_instance.get_surface_override_material(config.surface) as ShaderMaterial
			if mat and not seen.has(mat):
				seen[mat] = true
				materials.append(mat)

	if materials.is_empty():
		for config: TerrainMeshSurfaceMaterial in surfaces:
			if not config:
				continue
			var mat: ShaderMaterial = _resolve_surface_material(config)
			if mat and not seen.has(mat):
				seen[mat] = true
				materials.append(mat)

	return materials


func _is_weather_only(mat: ShaderMaterial) -> bool:
	return _shader_matches(mat.shader if mat else null, MESH_WEATHER_SHADER)


func _is_terrain_mesh(mat: ShaderMaterial) -> bool:
	return _shader_matches(mat.shader if mat else null, TERRAIN_MESH_SHADER)


## Re-reads terrain data and shader parameters into all managed materials.
func update_from_terrain() -> void:
	_sync_uniforms()


## Syncs only snow and puddle shader parameters into all managed materials.
func update_weather_uniforms() -> void:
	if not terrain:
		return
	var terrain_mat: Terrain3DMaterial = terrain.material
	if not terrain_mat:
		return
	if not terrain.assets or terrain.assets.get_texture_count() == 0:
		return
	for mat: ShaderMaterial in _get_all_materials():
		_sync_snow_texture_arrays(mat)
		_sync_snow_params(mat, terrain_mat)
		_sync_puddle_params(mat, terrain_mat)


func _connect_terrain() -> void:
	if not terrain or not is_inside_tree():
		return
	if terrain.data and not terrain.data.maps_changed.is_connected(_sync_uniforms):
		terrain.data.maps_changed.connect(_sync_uniforms)
	if terrain.assets and not terrain.assets.textures_changed.is_connected(_sync_uniforms):
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
	if not terrain:
		return
	if not terrain.assets or terrain.assets.get_texture_count() == 0:
		return

	var terrain_mat: Terrain3DMaterial = terrain.material
	if not terrain_mat:
		return

	var has_terrain_data: bool = terrain.data != null and terrain.data.get_region_count() > 0

	for mat: ShaderMaterial in _get_all_materials():
		if _is_weather_only(mat):
			_sync_snow_texture_arrays(mat)
			_sync_snow_params(mat, terrain_mat)
			_sync_puddle_params(mat, terrain_mat)
		elif _is_terrain_mesh(mat) and has_terrain_data:
			_sync_terrain_uniforms(mat, terrain_mat)


func _sync_terrain_uniforms(mat: ShaderMaterial, terrain_mat: Terrain3DMaterial) -> void:
	mat.set_shader_parameter("_vertex_spacing", terrain.vertex_spacing)
	mat.set_shader_parameter("_vertex_density", 1.0 / terrain.vertex_spacing)
	mat.set_shader_parameter("_region_size", terrain.region_size)
	mat.set_shader_parameter("_region_texel_size", 1.0 / terrain.region_size)
	mat.set_shader_parameter("_region_map_size", 32)
	mat.set_shader_parameter("_region_map", terrain.data.get_region_map())
	mat.set_shader_parameter("_region_locations", terrain.data.get_region_locations())
	mat.set_shader_parameter("_height_maps", terrain.data.get_height_maps_rid())
	mat.set_shader_parameter("_control_maps", terrain.data.get_control_maps_rid())

	_sync_snow_texture_arrays(mat)
	mat.set_shader_parameter("_texture_snow_amount_array", terrain.assets.get_texture_snow_amount_mods())

	mat.set_shader_parameter("auto_shader_enabled", terrain_mat.auto_shader_enabled)
	_set_shader_param(mat, "blend_sharpness", terrain_mat.get_shader_param("blend_sharpness"))
	_set_shader_param(mat, "auto_slope", terrain_mat.get_shader_param("auto_slope"))
	_set_shader_param(mat, "auto_height_reduction", terrain_mat.get_shader_param("auto_height_reduction"))
	_set_shader_param(mat, "auto_base_texture", terrain_mat.get_shader_param("auto_base_texture"))
	_set_shader_param(mat, "auto_overlay_texture", terrain_mat.get_shader_param("auto_overlay_texture"))
	_sync_snow_params(mat, terrain_mat)
	_sync_puddle_params(mat, terrain_mat)


func _sync_snow_texture_arrays(mat: ShaderMaterial) -> void:
	var assets: Terrain3DAssets = terrain.assets
	mat.set_shader_parameter("_texture_array_albedo", assets.get_albedo_array_rid())
	mat.set_shader_parameter("_texture_array_normal", assets.get_normal_array_rid())
	mat.set_shader_parameter("_texture_color_array", assets.get_texture_colors())
	mat.set_shader_parameter("_texture_normal_depth_array", assets.get_texture_normal_depths())
	mat.set_shader_parameter("_texture_ao_strength_array", assets.get_texture_ao_strengths())
	mat.set_shader_parameter("_texture_ao_affect_array", assets.get_texture_ao_light_affects())
	mat.set_shader_parameter("_texture_roughness_mod_array", assets.get_texture_roughness_mods())
	mat.set_shader_parameter("_texture_uv_scale_array", assets.get_texture_uv_scales())
	mat.set_shader_parameter("_texture_detile_array", assets.get_texture_detiles())
	mat.set_shader_parameter("_texture_height_blend_array", assets.get_texture_height_blends())


func _sync_snow_params(mat: ShaderMaterial, terrain_mat: Terrain3DMaterial) -> void:
	mat.set_shader_parameter("snow_enabled", terrain_mat.snow_enabled)
	_set_shader_param(mat, "snow_texture", terrain_mat.get_shader_param("snow_texture"))
	_set_shader_param(mat, "snow_blend_sharpness", terrain_mat.get_shader_param("snow_blend_sharpness"))
	var snow_amount: Variant = terrain_mat.get_shader_param("snow_amount")
	if terrain_mat.snow_enabled and snow_amount != null:
		_set_shader_param(mat, "snow_amount", snow_amount)
	else:
		mat.set_shader_parameter("snow_amount", 0.0)


func _sync_puddle_params(mat: ShaderMaterial, terrain_mat: Terrain3DMaterial) -> void:
	mat.set_shader_parameter("puddles_enabled", terrain_mat.puddles_enabled)
	if not terrain_mat.puddles_enabled:
		mat.set_shader_parameter("material_wetness", 0.0)
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
		_set_shader_param(mat, param_name, terrain_mat.get_shader_param(param_name))
	if terrain_mat.get_shader_param("puddle_ripples_enabled") == null:
		mat.set_shader_parameter("puddle_ripples_enabled", puddle_ripples_enabled)
	var wetness: Variant = terrain_mat.get_shader_param("material_wetness")
	mat.set_shader_parameter("material_wetness", wetness if wetness != null else 0.0)


func _set_shader_param(mat: ShaderMaterial, param_name: StringName, value: Variant) -> void:
	if value != null:
		mat.set_shader_parameter(param_name, value)
