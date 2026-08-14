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
    var indices: PackedInt32Array = Geometry2D.triangulate_polygon(region.polygon)
    if indices.is_empty(): return root
    var mesh_instance: MeshInstance3D = MeshInstance3D.new()
    var st: SurfaceTool = SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var height: float = _region_height(region.semantic_type)
    for raw_index in indices:
        var index: int = int(raw_index)
        _region_vertex(st, region.polygon[index], height)
    mesh_instance.mesh = st.commit()
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = _region_color(region.semantic_type)
    material.roughness = 1.0
    mesh_instance.material_override = material
    root.add_child(mesh_instance)
    return root

func _region_vertex(st: SurfaceTool, p: Vector2, height: float) -> void:
    st.set_normal(Vector3.UP); st.add_vertex(Vector3(p.x, height, p.y))

func _region_height(kind: String) -> float:
    match kind:
        "coast": return 0.012
        "forest": return 0.016
        "town", "village": return 0.022
        "graveyard": return 0.026
        _: return 0.018

func _region_color(kind: String) -> Color:
    match kind:
        "forest": return Color(0.12, 0.27, 0.13)
        "coast": return Color(0.25, 0.28, 0.22)
        "graveyard": return Color(0.19, 0.21, 0.18)
        "village", "town": return Color(0.31, 0.29, 0.22)
        _: return Color(0.24, 0.25, 0.20)

func _safe_name(value: String) -> String:
    return value.replace(":", "_").replace("/", "_")
