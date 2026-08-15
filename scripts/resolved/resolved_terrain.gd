class_name ResolvedTerrain
extends Resource

# Vertex color channels are backend surface influences:
# R = forest floor, G = settlement/packed dirt, B = coast/sand,
# A = road/building-local dirt.
var world_bounds: Rect2 = Rect2()
var grid_size: int = 0
var road_surface_offset: float = 0.025
var heights: PackedFloat32Array = PackedFloat32Array()
var surface_masks: PackedColorArray = PackedColorArray()
var shore_wetness: PackedFloat32Array = PackedFloat32Array()

func sample_height(point: Vector2) -> float:
    if grid_size < 2 or heights.size() != grid_size * grid_size or not world_bounds.has_area():
        return 0.0
    var uv := Vector2(
        inverse_lerp(world_bounds.position.x, world_bounds.end.x, point.x),
        inverse_lerp(world_bounds.position.y, world_bounds.end.y, point.y)
    ).clamp(Vector2.ZERO, Vector2.ONE)
    var grid_point := uv * float(grid_size - 1)
    var x0 := clampi(int(floor(grid_point.x)), 0, grid_size - 1)
    var z0 := clampi(int(floor(grid_point.y)), 0, grid_size - 1)
    var x1 := mini(x0 + 1, grid_size - 1)
    var z1 := mini(z0 + 1, grid_size - 1)
    var tx := grid_point.x - float(x0)
    var tz := grid_point.y - float(z0)
    var top := lerpf(heights[_index(x0, z0)], heights[_index(x1, z0)], tx)
    var bottom := lerpf(heights[_index(x0, z1)], heights[_index(x1, z1)], tx)
    return lerpf(top, bottom, tz)

func sample_surface_mask(point: Vector2) -> Color:
    if grid_size < 2 or surface_masks.size() != grid_size * grid_size or not world_bounds.has_area():
        return Color(0.0, 0.0, 0.0, 0.0)
    var uv := Vector2(
        inverse_lerp(world_bounds.position.x, world_bounds.end.x, point.x),
        inverse_lerp(world_bounds.position.y, world_bounds.end.y, point.y)
    ).clamp(Vector2.ZERO, Vector2.ONE)
    var grid_point := uv * float(grid_size - 1)
    var x0 := clampi(int(floor(grid_point.x)), 0, grid_size - 1)
    var z0 := clampi(int(floor(grid_point.y)), 0, grid_size - 1)
    var x1 := mini(x0 + 1, grid_size - 1)
    var z1 := mini(z0 + 1, grid_size - 1)
    var tx := grid_point.x - float(x0)
    var tz := grid_point.y - float(z0)
    var top := surface_masks[_index(x0, z0)].lerp(surface_masks[_index(x1, z0)], tx)
    var bottom := surface_masks[_index(x0, z1)].lerp(surface_masks[_index(x1, z1)], tx)
    return top.lerp(bottom, tz)

func sample_shore_wetness(point: Vector2) -> float:
    if grid_size < 2 or shore_wetness.size() != grid_size * grid_size or not world_bounds.has_area():
        return 0.0
    var uv := Vector2(
        inverse_lerp(world_bounds.position.x, world_bounds.end.x, point.x),
        inverse_lerp(world_bounds.position.y, world_bounds.end.y, point.y)
    ).clamp(Vector2.ZERO, Vector2.ONE)
    var grid_point := uv * float(grid_size - 1)
    var x0 := clampi(int(floor(grid_point.x)), 0, grid_size - 1)
    var z0 := clampi(int(floor(grid_point.y)), 0, grid_size - 1)
    var x1 := mini(x0 + 1, grid_size - 1)
    var z1 := mini(z0 + 1, grid_size - 1)
    var tx := grid_point.x - float(x0)
    var tz := grid_point.y - float(z0)
    var top := lerpf(shore_wetness[_index(x0, z0)], shore_wetness[_index(x1, z0)], tx)
    var bottom := lerpf(shore_wetness[_index(x0, z1)], shore_wetness[_index(x1, z1)], tx)
    return lerpf(top, bottom, tz)

func _index(x: int, z: int) -> int:
    return z * grid_size + x
