@tool
extends Resource
class_name TerrainMeshSurfaceMaterial

enum Kind {
	## Sample terrain ground textures at the mesh fragment world position.
	TERRAIN,
	## Mesh UV textures with terrain snow and puddles only.
	WEATHER_ONLY,
}

@export_range(0, 15) var surface: int = 0:
	set(value):
		surface = value
		emit_changed()

@export var kind: Kind = Kind.TERRAIN:
	set(value):
		kind = value
		emit_changed()

## Optional override. When empty, a preset is created from [member kind] on apply.
@export var material: ShaderMaterial:
	set(value):
		material = value
		emit_changed()
