class_name SceneRuntime
extends Node

var road_builder := RoadBuilder.new()

func build_candidate(resolved: ResolvedWorld, catalog: PrototypeCatalog) -> Node3D:
    var root := Node3D.new()
    root.name = "CandidateWorld"
    var regions := Node3D.new(); regions.name = "Regions"; root.add_child(regions)
    var networks := Node3D.new(); networks.name = "Networks"; root.add_child(networks)
    var entities := Node3D.new(); entities.name = "Entities"; root.add_child(entities)
    var distributions := Node3D.new(); distributions.name = "Distributions"; root.add_child(distributions)
    var decorations := Node3D.new(); decorations.name = "Decorations"; root.add_child(decorations)

    for region in resolved.regions:
        regions.add_child(_build_region(region))
    for network in resolved.networks:
        networks.add_child(road_builder.build(network))
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

func _build_region(region: ResolvedRegion) -> Node3D:
    var root: Node3D = Node3D.new(); root.name = _safe_name(region.id)
    if region.polygon.size() < 3: return root
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
