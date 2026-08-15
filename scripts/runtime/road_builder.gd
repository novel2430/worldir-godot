class_name RoadBuilder
extends RefCounted

const MITER_LIMIT := 2.0
const POINT_EPSILON_SQUARED := 0.000001

func build(network: ResolvedNetwork) -> Node3D:
    var root := Node3D.new()
    root.name = _safe_name(network.id)
    var points := _clean_centerline(network.curve_points)
    if points.size() < 2:
        return root
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "RoadMesh"
    mesh_instance.mesh = _build_ribbon(points, network.width)
    var material := StandardMaterial3D.new()
    # Warm, low-contrast dirt reads more naturally beside the muted ground than
    # the previous near-black concrete strip. Surface kind remains road semantics.
    material.albedo_color = Color(0.29, 0.245, 0.18)
    material.roughness = 1.0
    mesh_instance.material_override = material
    root.add_child(mesh_instance)
    _add_collision_segments(root, points, network.width)
    return root

func _build_ribbon(points: PackedVector3Array, width: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var half := width * 0.5
    var offsets: Array[Vector2] = []
    for i in range(points.size()):
        offsets.append(_join_offset(points, i, half))

    for i in range(points.size() - 1):
        var a := points[i]
        var b := points[i + 1]
        var a_offset: Vector2 = offsets[i]
        var b_offset: Vector2 = offsets[i + 1]
        var a_l := Vector3(a.x + a_offset.x, a.y, a.z + a_offset.y)
        var a_r := Vector3(a.x - a_offset.x, a.y, a.z - a_offset.y)
        var b_l := Vector3(b.x + b_offset.x, b.y, b.z + b_offset.y)
        var b_r := Vector3(b.x - b_offset.x, b.y, b.z - b_offset.y)
        # Godot treats clockwise winding as front-facing. On the XZ plane these
        # orders face upward while preserving UP as the lighting normal.
        _vertex(st, a_l, Vector2(0, 0)); _vertex(st, b_r, Vector2(1, 1)); _vertex(st, b_l, Vector2(0, 1))
        _vertex(st, a_l, Vector2(0, 0)); _vertex(st, a_r, Vector2(1, 0)); _vertex(st, b_r, Vector2(1, 1))
    return st.commit()

func _join_offset(points: PackedVector3Array, index: int, half_width: float) -> Vector2:
    if index == 0:
        return _segment_normal(points[0], points[1]) * half_width
    if index == points.size() - 1:
        return _segment_normal(points[index - 1], points[index]) * half_width

    var previous_normal := _segment_normal(points[index - 1], points[index])
    var next_normal := _segment_normal(points[index], points[index + 1])
    var miter := previous_normal + next_normal
    if miter.length_squared() <= POINT_EPSILON_SQUARED:
        return next_normal * half_width
    miter = miter.normalized()

    var denominator := miter.dot(next_normal)
    if denominator <= 0.0001:
        return next_normal * half_width
    var miter_length := minf(half_width / denominator, half_width * MITER_LIMIT)
    return miter * miter_length

func _segment_normal(a: Vector3, b: Vector3) -> Vector2:
    var direction := Vector2(b.x - a.x, b.z - a.z).normalized()
    return Vector2(-direction.y, direction.x)

func _clean_centerline(points: PackedVector3Array) -> PackedVector3Array:
    var cleaned := PackedVector3Array()
    for point in points:
        if cleaned.is_empty():
            cleaned.append(point)
            continue
        var previous := cleaned[cleaned.size() - 1]
        var planar_delta := Vector2(point.x - previous.x, point.z - previous.z)
        if planar_delta.length_squared() > POINT_EPSILON_SQUARED:
            cleaned.append(point)
    return cleaned

func _vertex(st: SurfaceTool, p: Vector3, uv: Vector2) -> void:
    st.set_normal(Vector3.UP)
    st.set_uv(uv)
    st.add_vertex(p)

func _add_collision_segments(root: Node3D, points: PackedVector3Array, width: float) -> void:
    for i in range(points.size() - 1):
        var a := points[i]
        var b := points[i + 1]
        var body := StaticBody3D.new()
        var shape_node := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        var length := a.distance_to(b)
        shape.size = Vector3(width, 0.15, length)
        shape_node.shape = shape
        body.position = (a + b) * 0.5 + Vector3(0, -0.08, 0)
        body.rotation.y = atan2(b.x - a.x, b.z - a.z)
        body.add_child(shape_node)
        root.add_child(body)

func _safe_name(value: String) -> String:
    return value.replace(":", "_").replace("/", "_")
