class_name SceneRuntime
extends Node

var road_builder := RoadBuilder.new()
var _terrain_material_cache: ShaderMaterial = null
var _water_material_cache: ShaderMaterial = null
var _foam_material_cache: ShaderMaterial = null

func build_candidate(resolved: ResolvedWorld, catalog: PrototypeCatalog) -> Node3D:
    var root := Node3D.new()
    root.name = "CandidateWorld"
    var terrain_layer := Node3D.new(); terrain_layer.name = "Terrain"; root.add_child(terrain_layer)
    var water_layer := Node3D.new(); water_layer.name = "Water"; root.add_child(water_layer)
    var regions := Node3D.new(); regions.name = "Regions"; root.add_child(regions)
    var networks := Node3D.new(); networks.name = "Networks"; root.add_child(networks)
    var entities := Node3D.new(); entities.name = "Entities"; root.add_child(entities)
    var distributions := Node3D.new(); distributions.name = "Distributions"; root.add_child(distributions)
    var decorations := Node3D.new(); decorations.name = "Decorations"; root.add_child(decorations)

    if resolved.terrain != null:
        terrain_layer.add_child(_build_terrain(resolved.terrain))
    for water in resolved.waters:
        water_layer.add_child(_build_water(water))
    for region in resolved.regions:
        regions.add_child(_build_region(region, resolved.terrain == null))
    for network in resolved.networks:
        networks.add_child(road_builder.build(network, resolved.terrain))
    for entity in resolved.entities:
        var node := _instantiate(entity.prototype_id, catalog)
        if node == null:
            root.free(); return null
        node.name = _safe_name(entity.id)
        node.transform = entity.transform
        entities.add_child(node)
    for distribution in resolved.distributions:
        var group := Node3D.new(); group.name = _safe_name(distribution.id); distributions.add_child(group)
        for instance_data in distribution.instances:
            var node := _instantiate(String(instance_data.prototype_id), catalog)
            if node == null:
                root.free(); return null
            node.name = _safe_name(String(instance_data.id))
            node.transform = instance_data.transform
            group.add_child(node)
    for decoration in resolved.decorations:
        var group := Node3D.new(); group.name = _safe_name(decoration.id); decorations.add_child(group)
        for instance_data in decoration.instances:
            var node := _instantiate(String(instance_data.prototype_id), catalog)
            if node == null:
                root.free(); return null
            node.name = _safe_name(String(instance_data.id))
            node.transform = instance_data.transform
            group.add_child(node)
    return root

func commit_candidate(world_root: Node3D, candidate: Node3D) -> void:
    for child in world_root.get_children():
        world_root.remove_child(child)
        child.queue_free()
    world_root.add_child(candidate)
    candidate.name = "GeneratedWorld"

func _instantiate(prototype_id: String, catalog: PrototypeCatalog) -> Node3D:
    var scene := catalog.get_scene(prototype_id)
    if scene == null: return null
    return scene.instantiate() as Node3D

func _build_terrain(terrain: Resource) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = "WorldSurface"
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "TerrainMesh"
    mesh_instance.mesh = _terrain_mesh(terrain)
    mesh_instance.material_override = _terrain_material()
    body.add_child(mesh_instance)
    var collision := CollisionShape3D.new()
    collision.name = "TerrainCollision"
    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(mesh_instance.mesh.get_faces())
    collision.shape = shape
    body.add_child(collision)
    return body

func _terrain_mesh(terrain: Resource) -> ArrayMesh:
    var vertex_count: int = terrain.grid_size * terrain.grid_size
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    var uvs := PackedVector2Array()
    var uv2s := PackedVector2Array()
    vertices.resize(vertex_count)
    normals.resize(vertex_count)
    colors.resize(vertex_count)
    uvs.resize(vertex_count)
    uv2s.resize(vertex_count)
    var step_x: float = terrain.world_bounds.size.x / float(terrain.grid_size - 1)
    var step_z: float = terrain.world_bounds.size.y / float(terrain.grid_size - 1)
    for z_index in range(terrain.grid_size):
        for x_index in range(terrain.grid_size):
            var index: int = z_index * terrain.grid_size + x_index
            var x: float = terrain.world_bounds.position.x + float(x_index) * step_x
            var z: float = terrain.world_bounds.position.y + float(z_index) * step_z
            vertices[index] = Vector3(x, terrain.heights[index], z)
            colors[index] = terrain.surface_masks[index]
            uvs[index] = Vector2(
                float(x_index) / float(terrain.grid_size - 1),
                float(z_index) / float(terrain.grid_size - 1)
            )
            uv2s[index] = Vector2(terrain.shore_wetness[index], 0.0)
    for z_index in range(terrain.grid_size):
        for x_index in range(terrain.grid_size):
            var index: int = z_index * terrain.grid_size + x_index
            var left: float = terrain.heights[z_index * terrain.grid_size + maxi(0, x_index - 1)]
            var right: float = terrain.heights[z_index * terrain.grid_size + mini(terrain.grid_size - 1, x_index + 1)]
            var back: float = terrain.heights[maxi(0, z_index - 1) * terrain.grid_size + x_index]
            var front: float = terrain.heights[mini(terrain.grid_size - 1, z_index + 1) * terrain.grid_size + x_index]
            var x_span := step_x * (1.0 if x_index == 0 or x_index == terrain.grid_size - 1 else 2.0)
            var z_span := step_z * (1.0 if z_index == 0 or z_index == terrain.grid_size - 1 else 2.0)
            normals[index] = Vector3((left - right) / x_span, 1.0, (back - front) / z_span).normalized()

    var indices := PackedInt32Array()
    for z_index in range(terrain.grid_size - 1):
        for x_index in range(terrain.grid_size - 1):
            var a: int = z_index * terrain.grid_size + x_index
            var b: int = a + 1
            var c: int = a + terrain.grid_size
            var d: int = c + 1
            # Clockwise in XZ is Godot's upward-facing front side.
            indices.append_array(PackedInt32Array([a, b, d, a, d, c]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_TEX_UV2] = uv2s
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _terrain_material() -> ShaderMaterial:
    if _terrain_material_cache != null:
        return _terrain_material_cache
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

varying vec3 world_position;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec4 influence = COLOR;
    float broad_noise = value_noise(world_position.xz * 0.035);
    float detail_noise = value_noise(world_position.xz * 0.11 + vec2(17.0, 41.0));
    vec3 meadow = mix(vec3(0.19, 0.245, 0.125), vec3(0.255, 0.305, 0.155), broad_noise);
    vec3 forest_green = mix(vec3(0.105, 0.17, 0.07), vec3(0.17, 0.235, 0.105), broad_noise);
    vec3 forest_soil = vec3(0.255, 0.18, 0.095);
    float soil_patch = smoothstep(0.61, 0.79, detail_noise) * influence.r * 0.58;
    vec3 forest_floor = mix(forest_green, forest_soil, soil_patch);
    vec3 packed_dirt = mix(vec3(0.31, 0.235, 0.135), vec3(0.38, 0.285, 0.16), broad_noise);
    vec3 sand = mix(vec3(0.43, 0.405, 0.265), vec3(0.52, 0.485, 0.315), broad_noise);
    vec3 wet_sand = mix(vec3(0.245, 0.255, 0.19), vec3(0.31, 0.295, 0.205), broad_noise);
    vec3 road_dirt = mix(vec3(0.285, 0.205, 0.115), vec3(0.355, 0.265, 0.145), detail_noise);

    vec3 surface = meadow;
    surface = mix(surface, forest_floor, influence.r);
    surface = mix(surface, packed_dirt, influence.g * 0.82);
    surface = mix(surface, sand, influence.b);
    surface = mix(surface, wet_sand, UV2.x * influence.b * 0.88);
    surface = mix(surface, road_dirt, influence.a * 0.86);
    surface *= mix(0.94, 1.06, detail_noise);
    ALBEDO = surface;
    ROUGHNESS = 1.0;
    SPECULAR = 0.08;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    _terrain_material_cache = material
    return _terrain_material_cache

func _build_water(water: Resource) -> Node3D:
    var root := Node3D.new()
    root.name = _safe_name(water.id)
    var water_mesh := MeshInstance3D.new()
    water_mesh.name = "WaterMesh"
    water_mesh.mesh = _water_mesh(water)
    water_mesh.material_override = _water_material()
    water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(water_mesh)
    var foam := MeshInstance3D.new()
    foam.name = "ShoreFoam"
    foam.mesh = _foam_mesh(water)
    foam.material_override = _foam_material()
    foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(foam)
    return root

func _water_mesh(water: Resource) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var depth_segments := 12
    for shore_index in range(water.shoreline.size() - 1):
        var a_shore: Vector2 = water.shoreline[shore_index]
        var b_shore: Vector2 = water.shoreline[shore_index + 1]
        var a_boundary := _water_boundary_point(water, a_shore)
        var b_boundary := _water_boundary_point(water, b_shore)
        for depth_index in range(depth_segments):
            var near_t := float(depth_index) / float(depth_segments)
            var far_t := float(depth_index + 1) / float(depth_segments)
            var a_near := a_shore.lerp(a_boundary, near_t)
            var b_near := b_shore.lerp(b_boundary, near_t)
            var a_far := a_shore.lerp(a_boundary, far_t)
            var b_far := b_shore.lerp(b_boundary, far_t)
            _water_triangle(st, a_near, b_far, b_near, water, near_t, far_t, near_t)
            _water_triangle(st, a_near, a_far, b_far, water, near_t, far_t, far_t)
    return st.commit()

func _water_triangle(
    st: SurfaceTool,
    a: Vector2,
    b: Vector2,
    c: Vector2,
    water: Resource,
    depth_a: float,
    depth_b: float,
    depth_c: float
) -> void:
    var a3 := Vector3(a.x, water.sea_level, a.y)
    var b3 := Vector3(b.x, water.sea_level, b.y)
    var c3 := Vector3(c.x, water.sea_level, c.y)
    if (b3 - a3).cross(c3 - a3).dot(Vector3.DOWN) < 0.0:
        _water_vertex(st, a, water, depth_a)
        _water_vertex(st, c, water, depth_c)
        _water_vertex(st, b, water, depth_b)
    else:
        _water_vertex(st, a, water, depth_a)
        _water_vertex(st, b, water, depth_b)
        _water_vertex(st, c, water, depth_c)

func _water_vertex(st: SurfaceTool, point: Vector2, water: Resource, depth: float) -> void:
    st.set_normal(Vector3.UP)
    st.set_color(Color(1.0 - smoothstep(0.0, 0.58, depth), 0.0, 0.0, 1.0))
    st.add_vertex(Vector3(point.x, water.sea_level, point.y))

func _water_boundary_point(water: Resource, shore_point: Vector2) -> Vector2:
    var result := shore_point
    if absf(water.seaward_direction.x) > 0.5:
        result.x = water.polygon[water.polygon.size() - 1].x
    else:
        result.y = water.polygon[water.polygon.size() - 1].y
    return result

func _foam_mesh(water: Resource) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var foam_width := 0.58
    var height: float = water.sea_level + 0.045
    for index in range(water.shoreline.size() - 1):
        var a: Vector2 = water.shoreline[index]
        var b: Vector2 = water.shoreline[index + 1]
        var a_sea: Vector2 = a + water.seaward_direction * foam_width
        var b_sea: Vector2 = b + water.seaward_direction * foam_width
        _flat_triangle(st, Vector3(a.x, height, a.y), Vector3(b_sea.x, height, b_sea.y), Vector3(b.x, height, b.y))
        _flat_triangle(st, Vector3(a.x, height, a.y), Vector3(a_sea.x, height, a_sea.y), Vector3(b_sea.x, height, b_sea.y))
    return st.commit()

func _flat_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    if (b - a).cross(c - a).dot(Vector3.DOWN) < 0.0:
        var swap := b
        b = c
        c = swap
    for point in [a, b, c]:
        st.set_normal(Vector3.UP)
        st.add_vertex(point)

func _water_material() -> ShaderMaterial:
    if _water_material_cache != null:
        return _water_material_cache
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

varying vec3 world_position;

void vertex() {
    vec3 source_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float wave = sin(source_world.x * 0.13 + TIME * 0.55) * 0.032;
    wave += sin(source_world.z * 0.17 - TIME * 0.43) * 0.024;
    VERTEX.y += wave;
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float variation = sin(world_position.x * 0.08 + world_position.z * 0.055) * 0.5 + 0.5;
    vec3 deep_water = mix(vec3(0.045, 0.235, 0.34), vec3(0.06, 0.315, 0.39), variation);
    vec3 shallow_water = vec3(0.16, 0.47, 0.46);
    ALBEDO = mix(deep_water, shallow_water, COLOR.r * 0.72);
    ROUGHNESS = 0.72;
    SPECULAR = 0.28;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    _water_material_cache = material
    return _water_material_cache

func _foam_material() -> ShaderMaterial:
    if _foam_material_cache != null:
        return _foam_material_cache
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

varying vec3 world_position;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float variation = sin(world_position.x * 0.35 + world_position.z * 0.23) * 0.5 + 0.5;
    ALBEDO = mix(vec3(0.60, 0.69, 0.62), vec3(0.68, 0.76, 0.67), variation);
    ROUGHNESS = 0.95;
    SPECULAR = 0.08;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    _foam_material_cache = material
    return _foam_material_cache

func _build_region(region: ResolvedRegion, render_surface: bool = true) -> Node3D:
    var root: Node3D = Node3D.new(); root.name = _safe_name(region.id)
    if not render_surface or region.polygon.size() < 3: return root
    var mesh_instance: MeshInstance3D = MeshInstance3D.new()
    var height: float = _region_height(region.semantic_type)
    var feather_width := _region_feather_width(region.semantic_type)
    mesh_instance.mesh = _build_region_mesh(region.polygon, height, feather_width)
    if mesh_instance.mesh == null:
        return root
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = _region_color(region.semantic_type)
    material.roughness = 1.0
    if feather_width > 0.0:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.vertex_color_use_as_albedo = true
        material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
    mesh_instance.material_override = material
    root.add_child(mesh_instance)
    return root

func _build_region_mesh(polygon: PackedVector2Array, height: float, feather_width: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    if feather_width <= 0.0:
        var indices := Geometry2D.triangulate_polygon(polygon)
        if indices.is_empty():
            return null
        for raw_index in indices:
            _region_vertex(st, polygon[int(raw_index)], height, Color.WHITE)
        return st.commit()

    var center := Vector2.ZERO
    for point in polygon:
        center += point
    center /= float(polygon.size())
    var inner := PackedVector2Array()
    for point in polygon:
        inner.append(point.move_toward(center, minf(feather_width, point.distance_to(center) * 0.25)))
    var inner_indices := Geometry2D.triangulate_polygon(inner)
    if inner_indices.is_empty():
        return null
    for raw_index in inner_indices:
        _region_vertex(st, inner[int(raw_index)], height, Color.WHITE)

    # The outer strip fades into the shared ground. Keep a tiny residual alpha
    # so the transition remains legible without revealing a razor-straight seam.
    var edge_color := Color(1.0, 1.0, 1.0, 0.04)
    for index in range(polygon.size()):
        var next := (index + 1) % polygon.size()
        _region_triangle(st, polygon[index], polygon[next], inner[next], height, edge_color, edge_color, Color.WHITE)
        _region_triangle(st, polygon[index], inner[next], inner[index], height, edge_color, Color.WHITE, Color.WHITE)
    return st.commit()

func _region_triangle(
    st: SurfaceTool,
    a: Vector2,
    b: Vector2,
    c: Vector2,
    height: float,
    color_a: Color,
    color_b: Color,
    color_c: Color
) -> void:
    var a3 := Vector3(a.x, height, a.y)
    var b3 := Vector3(b.x, height, b.y)
    var c3 := Vector3(c.x, height, c.y)
    # Godot considers clockwise triangles front-facing. Normalize every strip
    # triangle so its visible side stays upward regardless of polygon winding.
    if (b3 - a3).cross(c3 - a3).dot(Vector3.DOWN) < 0.0:
        _region_vertex(st, a, height, color_a)
        _region_vertex(st, c, height, color_c)
        _region_vertex(st, b, height, color_b)
    else:
        _region_vertex(st, a, height, color_a)
        _region_vertex(st, b, height, color_b)
        _region_vertex(st, c, height, color_c)

func _region_vertex(st: SurfaceTool, p: Vector2, height: float, color: Color) -> void:
    st.set_normal(Vector3.UP)
    st.set_color(color)
    st.add_vertex(Vector3(p.x, height, p.y))

func _region_feather_width(kind: String) -> float:
    match kind:
        "forest", "coast", "swamp", "field": return 3.2
        _: return 0.0

func _region_height(kind: String) -> float:
    match kind:
        "coast": return 0.012
        "forest": return 0.016
        "town", "village": return 0.022
        "graveyard": return 0.026
        _: return 0.018

func _region_color(kind: String) -> Color:
    match kind:
        # Region surfaces should tint the shared ground, not look like brightly
        # colored sheets laid on top of it. Tree density carries most forest cue.
        "forest": return Color(0.17, 0.245, 0.145)
        "coast": return Color(0.24, 0.265, 0.20)
        "graveyard": return Color(0.185, 0.205, 0.17)
        "village", "town": return Color(0.285, 0.27, 0.205)
        _: return Color(0.22, 0.235, 0.18)

func _safe_name(value: String) -> String:
    return value.replace(":", "_").replace("/", "_")
