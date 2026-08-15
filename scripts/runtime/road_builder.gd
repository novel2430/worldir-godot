class_name RoadBuilder
extends RefCounted

const MITER_LIMIT := 2.0
const POINT_EPSILON_SQUARED := 0.000001
const MAX_TERRAIN_SEGMENT_LENGTH_M := 1.25

var region_profiles := RegionProfileCatalog.new()
var _path_material_cache: ShaderMaterial = null

func build(network: ResolvedNetwork, terrain: Resource = null) -> Node3D:
    var root := Node3D.new()
    root.name = _safe_name(network.id)
    var points := _clean_centerline(network.curve_points)
    if terrain != null:
        points = _densify_and_conform(points, terrain)
    if points.size() < 2:
        return root
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "RoadMesh"
    mesh_instance.mesh = _build_ribbon(points, network.width, terrain)
    # The road is a surface treatment a few centimeters above the terrain, not
    # an elevated slab. Disabling its own cast shadow removes the black trench
    # that otherwise appears between two nearly coincident surfaces.
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    mesh_instance.material_override = _path_material()
    root.add_child(mesh_instance)
    _add_collision(root, mesh_instance.mesh)
    return root

func _build_ribbon(points: PackedVector3Array, width: float, terrain: Resource = null) -> ArrayMesh:
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
        var a_l := _edge_point(a, a_offset, terrain)
        var a_r := _edge_point(a, -a_offset, terrain)
        var b_l := _edge_point(b, b_offset, terrain)
        var b_r := _edge_point(b, -b_offset, terrain)
        # Godot treats clockwise winding as front-facing. On the XZ plane these
        # orders face upward while preserving UP as the lighting normal.
        _triangle(st, a_l, b_r, b_l, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1), terrain)
        _triangle(st, a_l, a_r, b_r, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), terrain)
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

func _densify_and_conform(points: PackedVector3Array, terrain: Resource) -> PackedVector3Array:
    var result := PackedVector3Array()
    if points.is_empty():
        return result
    for segment_index in range(points.size() - 1):
        var a := points[segment_index]
        var b := points[segment_index + 1]
        var planar_length := Vector2(b.x - a.x, b.z - a.z).length()
        var steps := maxi(1, int(ceil(planar_length / MAX_TERRAIN_SEGMENT_LENGTH_M)))
        for step_index in range(steps + 1):
            if segment_index > 0 and step_index == 0:
                continue
            var point := a.lerp(b, float(step_index) / float(steps))
            point.y = terrain.sample_height(Vector2(point.x, point.z)) + float(terrain.road_surface_offset)
            result.append(point)
    return result

func _edge_point(center: Vector3, offset: Vector2, terrain: Resource) -> Vector3:
    var result := Vector3(center.x + offset.x, center.y, center.z + offset.y)
    if terrain != null:
        result.y = terrain.sample_height(Vector2(result.x, result.z)) + float(terrain.road_surface_offset)
    return result

func _triangle(
    st: SurfaceTool,
    a: Vector3,
    b: Vector3,
    c: Vector3,
    uv_a: Vector2,
    uv_b: Vector2,
    uv_c: Vector2,
    terrain: Resource
) -> void:
    # Godot's clockwise front face uses the reverse of the conventional cross
    # product. This keeps road lighting correct as the ribbon follows terrain.
    var normal := (c - a).cross(b - a).normalized()
    if normal.y < 0.0:
        normal = -normal
    _vertex(st, a, uv_a, normal, terrain)
    _vertex(st, b, uv_b, normal, terrain)
    _vertex(st, c, uv_c, normal, terrain)

func _vertex(
    st: SurfaceTool,
    p: Vector3,
    uv: Vector2,
    normal: Vector3,
    terrain: Resource
) -> void:
    st.set_normal(normal)
    st.set_uv(uv)
    st.set_color(_path_color_at(p, terrain))
    st.add_vertex(p)

func _path_color_at(point: Vector3, terrain: Resource) -> Color:
    var weights := Color(1.0, 0.0, 0.0, 0.0)
    if terrain != null:
        weights = terrain.sample_region_weights(Vector2(point.x, point.z))
    var total := weights.r + weights.g + weights.b
    if total > 0.0001:
        weights.r /= total
        weights.g /= total
        weights.b /= total
    var coastal: Color = region_profiles.get_profile("coastal_forest").path_style.color
    var research: Color = region_profiles.get_profile("research_base").path_style.color
    var snow: Color = region_profiles.get_profile("snow_forest").path_style.color
    var result := coastal * weights.r + research * weights.g + snow * weights.b
    result.a = 1.0
    return result

func _path_material() -> ShaderMaterial:
    if _path_material_cache != null:
        return _path_material_cache
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

varying vec3 world_position;

float path_noise(vec2 p) {
    return fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float grain = path_noise(world_position.xz * 1.7);
    float edge = smoothstep(0.58, 1.0, abs(UV.x * 2.0 - 1.0));
    vec3 surface = COLOR.rgb * mix(0.91, 1.07, grain);
    surface *= mix(1.0, 0.82, edge);
    ALBEDO = surface;
    ROUGHNESS = 0.96;
    SPECULAR = 0.07;
}
"""
    _path_material_cache = ShaderMaterial.new()
    _path_material_cache.shader = shader
    return _path_material_cache

func _add_collision(root: Node3D, mesh: ArrayMesh) -> void:
    var body := StaticBody3D.new()
    body.name = "RoadCollision"
    var shape_node := CollisionShape3D.new()
    shape_node.name = "CollisionShape3D"
    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(mesh.get_faces())
    shape_node.shape = shape
    body.add_child(shape_node)
    root.add_child(body)

func _safe_name(value: String) -> String:
    return value.replace(":", "_").replace("/", "_")
