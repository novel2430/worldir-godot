class_name RoadBuilder
extends RefCounted

const MITER_LIMIT := 2.0
const POINT_EPSILON_SQUARED := 0.000001
const MAX_TERRAIN_SEGMENT_LENGTH_M := 1.25
const PATH_CROWN_HEIGHT_M := 0.085
const CROSS_SECTION := [-1.0, -0.72, 0.0, 0.72, 1.0]
const COASTAL_WIDTH_SCALE := 0.88
const RESEARCH_WIDTH_SCALE := 1.0
const SNOW_WIDTH_SCALE := 0.94

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
    st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
    var half := width * 0.5
    var offsets: Array[Vector2] = []
    var distances := PackedFloat32Array()
    distances.resize(points.size())
    for i in range(points.size()):
        if i > 0:
            distances[i] = distances[i - 1] + Vector2(
                points[i].x - points[i - 1].x,
                points[i].z - points[i - 1].z
            ).length()
        var realized_half := half * _width_scale(points[i], distances[i], terrain)
        offsets.append(_join_offset(points, i, realized_half))

    for i in range(points.size() - 1):
        var v_a := distances[i] / 5.0
        var v_b := distances[i + 1] / 5.0
        for band in range(CROSS_SECTION.size() - 1):
            var lateral_0: float = CROSS_SECTION[band]
            var lateral_1: float = CROSS_SECTION[band + 1]
            var a_0 := _cross_section_point(points[i], offsets[i], lateral_0, terrain)
            var a_1 := _cross_section_point(points[i], offsets[i], lateral_1, terrain)
            var b_0 := _cross_section_point(points[i + 1], offsets[i + 1], lateral_0, terrain)
            var b_1 := _cross_section_point(points[i + 1], offsets[i + 1], lateral_1, terrain)
            var u_0 := (lateral_0 + 1.0) * 0.5
            var u_1 := (lateral_1 + 1.0) * 0.5
            # Godot treats clockwise winding as front-facing. These triangles
            # face upward while the five-point section supplies a subtle crown
            # and enough lateral resolution for worn center/shoulder shading.
            _triangle(st, a_0, b_1, b_0, Vector2(u_0, v_a), Vector2(u_1, v_b), Vector2(u_0, v_b), terrain)
            _triangle(st, a_0, a_1, b_1, Vector2(u_0, v_a), Vector2(u_1, v_a), Vector2(u_1, v_b), terrain)
    return st.commit()

func _width_scale(point: Vector3, distance: float, terrain: Resource) -> float:
    var profile_scale := COASTAL_WIDTH_SCALE
    if terrain != null:
        var weights: Color = terrain.sample_region_weights(Vector2(point.x, point.z))
        var total := weights.r + weights.g + weights.b
        if total > 0.0001:
            profile_scale = (
                weights.r * COASTAL_WIDTH_SCALE
                + weights.g * RESEARCH_WIDTH_SCALE
                + weights.b * SNOW_WIDTH_SCALE
            ) / total
    # Two low-frequency waves keep the silhouette organic without making the
    # route width flicker between adjacent terrain-conforming samples.
    var edge_variation := (
        sin(distance * 0.071 + point.x * 0.013) * 0.045
        + sin(distance * 0.173 + point.z * 0.019 + 1.7) * 0.025
    )
    return clampf(profile_scale + edge_variation, 0.80, 1.02)

func _cross_section_point(
    center: Vector3,
    full_offset: Vector2,
    lateral: float,
    terrain: Resource
) -> Vector3:
    var result := _edge_point(center, full_offset * -lateral, terrain)
    var crown := PATH_CROWN_HEIGHT_M * (1.0 - pow(absf(lateral), 1.55))
    result.y += crown
    return result

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
    var region_weights := _region_weights_at(p, terrain)
    st.set_color(_path_color_for_weights(region_weights))
    st.set_custom(0, region_weights)
    st.add_vertex(p)

func _region_weights_at(point: Vector3, terrain: Resource) -> Color:
    var weights := Color(1.0, 0.0, 0.0, 0.0)
    if terrain != null:
        weights = terrain.sample_region_weights(Vector2(point.x, point.z))
    var total := weights.r + weights.g + weights.b
    if total > 0.0001:
        weights.r /= total
        weights.g /= total
        weights.b /= total
    return weights

func _path_color_for_weights(weights: Color) -> Color:
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
varying vec3 region_weights;

float path_noise(vec2 p) {
    return fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);
}

float smooth_path_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = path_noise(cell);
    float b = path_noise(cell + vec2(1.0, 0.0));
    float c = path_noise(cell + vec2(0.0, 1.0));
    float d = path_noise(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    region_weights = CUSTOM0.rgb;
}

void fragment() {
    float lateral = abs(UV.x * 2.0 - 1.0);
    float coarse = smooth_path_noise(world_position.xz * 0.33);
    float grain = path_noise(world_position.xz * 3.4);
    float aggregate = path_noise(world_position.xz * 8.5 + vec2(19.7, 6.3));
    float broken_edge = 0.925 + (coarse - 0.5) * 0.12;
    float edge_coverage = 1.0 - smoothstep(0.82, broken_edge, lateral);
    float edge_dither = smooth_path_noise(world_position.xz * 2.7 + vec2(3.1, 27.4));
    if (edge_dither > edge_coverage) {
        discard;
    }
    float shoulder = smoothstep(0.66, 0.98, lateral);
    float center_wear = 1.0 - smoothstep(0.0, 0.58, lateral);
    float wheel_tracks = exp(-pow((lateral - 0.43) / 0.13, 2.0));
    float longitudinal_wear = 0.5 + 0.5 * sin(UV.y * 2.7 + coarse * 4.0);
    float coastal = region_weights.r;
    float research = region_weights.g;
    float snow = region_weights.b;
    vec3 surface = COLOR.rgb;
    surface *= mix(0.88, 1.08, coarse);
    surface *= mix(0.94, 1.04, grain);
    surface *= mix(1.0, 0.76, shoulder);
    surface *= mix(1.0, 0.90, wheel_tracks * (research * 0.85 + snow * 0.62));
    surface *= mix(0.94, 1.035, center_wear * longitudinal_wear * coastal);
    float gravel_fleck = smoothstep(0.88, 1.0, aggregate) * research;
    float snow_scuff = smoothstep(0.64, 0.98, grain) * wheel_tracks * snow;
    surface += vec3(gravel_fleck * 0.075 + snow_scuff * 0.035);
    ALBEDO = surface;
    ROUGHNESS = clamp(mix(0.90, 0.99, shoulder) + gravel_fleck * 0.025, 0.0, 1.0);
    SPECULAR = mix(0.10, 0.035, shoulder);
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
