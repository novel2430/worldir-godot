class_name RoadBuilder
extends RefCounted

func build(network: ResolvedNetwork) -> Node3D:
    var root := Node3D.new()
    root.name = _safe_name(network.id)
    if network.curve_points.size() < 2:
        return root
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "RoadMesh"
    mesh_instance.mesh = _build_ribbon(network.curve_points, network.width)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.16, 0.17, 0.18)
    material.roughness = 0.95
    mesh_instance.material_override = material
    root.add_child(mesh_instance)
    _add_collision_segments(root, network.curve_points, network.width)
    return root

func _build_ribbon(points: PackedVector3Array, width: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var half := width * 0.5
    for i in range(points.size() - 1):
        var a := points[i]
        var b := points[i + 1]
        var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
        var n := Vector2(-dir.y, dir.x) * half
        var a_l := Vector3(a.x + n.x, a.y, a.z + n.y)
        var a_r := Vector3(a.x - n.x, a.y, a.z - n.y)
        var b_l := Vector3(b.x + n.x, b.y, b.z + n.y)
        var b_r := Vector3(b.x - n.x, b.y, b.z - n.y)
        # Godot treats clockwise winding as front-facing. On the XZ plane these
        # orders face upward while preserving UP as the lighting normal.
        _vertex(st, a_l, Vector2(0, 0)); _vertex(st, b_r, Vector2(1, 1)); _vertex(st, b_l, Vector2(0, 1))
        _vertex(st, a_l, Vector2(0, 0)); _vertex(st, a_r, Vector2(1, 0)); _vertex(st, b_r, Vector2(1, 1))
    return st.commit()

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
