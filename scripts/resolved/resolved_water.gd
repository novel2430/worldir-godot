class_name ResolvedWater
extends Resource

var id: String = ""
var source_region_id: String = ""
var sea_level: float = -0.6
var seaward_direction: Vector2 = Vector2.ZERO
var shoreline: PackedVector2Array = PackedVector2Array()
var polygon: PackedVector2Array = PackedVector2Array()

func signed_distance_to_shore(point: Vector2) -> float:
    if shoreline.size() < 2 or seaward_direction.is_zero_approx():
        return -INF
    var nearest := shoreline[0]
    var nearest_distance := INF
    for index in range(shoreline.size() - 1):
        var candidate := Geometry2D.get_closest_point_to_segment(point, shoreline[index], shoreline[index + 1])
        var distance := point.distance_squared_to(candidate)
        if distance < nearest_distance:
            nearest = candidate
            nearest_distance = distance
    return (point - nearest).dot(seaward_direction)

func cross_span_influence(point: Vector2, fade_width: float = 4.0) -> float:
    if shoreline.is_empty():
        return 0.0
    var cross_axis := Vector2(-seaward_direction.y, seaward_direction.x)
    var minimum := INF
    var maximum := -INF
    for shore_point in shoreline:
        var projected := shore_point.dot(cross_axis)
        minimum = minf(minimum, projected)
        maximum = maxf(maximum, projected)
    var value := point.dot(cross_axis)
    var outside := maxf(maxf(minimum - value, value - maximum), 0.0)
    return 1.0 - smoothstep(0.0, fade_width, outside)
