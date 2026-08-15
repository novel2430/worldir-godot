extends SceneTree

var catalog: PrototypeCatalog
var runtime: SceneRuntime
var world_root: Node3D

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    catalog = PrototypeCatalog.new()
    root.add_child(catalog)
    runtime = SceneRuntime.new()
    root.add_child(runtime)
    runtime.scene_transition.duration_scale = 0.025
    world_root = Node3D.new()
    world_root.name = "WorldRoot"
    root.add_child(world_root)

    await _test_object_patch_and_animation()
    await _test_terrain_swap_preserves_unchanged_nodes()

    print("Incremental Scene Transition tests passed")
    quit(0)

func _test_object_patch_and_animation() -> void:
    var old_world := _object_world(false)
    var new_world := _object_world(true)
    var initial := runtime.build_candidate(old_world, catalog)
    assert(initial != null)
    runtime.commit_candidate(world_root, initial)
    var active := world_root.get_node("GeneratedWorld")

    var stable := active.get_node("Entities/stable_church") as Node3D
    var mover := active.get_node("Entities/moving_church") as Node3D
    var stable_tree := active.get_node("Distributions/trees/trees_000") as Node3D
    var removed_tree := active.get_node("Distributions/trees/trees_001") as Node3D
    var replaced_tree := active.get_node("Distributions/trees/trees_002") as Node3D
    var old_road := active.get_node("Networks/main_road") as Node3D
    var active_id := active.get_instance_id()
    var stable_id := stable.get_instance_id()
    var mover_id := mover.get_instance_id()
    var stable_tree_id := stable_tree.get_instance_id()
    var replaced_tree_id := replaced_tree.get_instance_id()
    var old_road_id := old_road.get_instance_id()

    var candidate := runtime.build_candidate(new_world, catalog)
    assert(candidate != null)
    var patch: Dictionary = await runtime.transition_candidate(
        world_root, candidate, old_world, new_world
    )
    await process_frame
    await process_frame

    active = world_root.get_node("GeneratedWorld")
    assert(active.get_instance_id() == active_id)
    assert((active.get_node("Entities/stable_church") as Node3D).get_instance_id() == stable_id)
    assert((active.get_node("Entities/moving_church") as Node3D).get_instance_id() == mover_id)
    assert((active.get_node("Distributions/trees/trees_000") as Node3D).get_instance_id() == stable_tree_id)
    assert((active.get_node("Entities/moving_church") as Node3D).transform.is_equal_approx(
        (new_world.find_entity("moving_church") as ResolvedEntity).transform
    ))
    assert(not is_instance_valid(removed_tree))

    var new_tree := active.get_node("Distributions/trees/trees_003") as Node3D
    assert(new_tree != null and String(new_tree.get("prototype_id")) == "tree_04")
    assert(_all_geometry_opaque(new_tree))
    assert(_all_collisions_enabled(new_tree))

    var new_replacement := active.get_node("Distributions/trees/trees_002") as Node3D
    assert(new_replacement.get_instance_id() != replaced_tree_id)
    assert(String(new_replacement.get("prototype_id")) == "tree_05")
    assert(not is_instance_valid(replaced_tree))
    var new_road := active.get_node("Networks/main_road") as Node3D
    assert(new_road.get_instance_id() != old_road_id)
    assert(_all_geometry_opaque(new_road))
    assert(_all_collisions_enabled(new_road))
    assert(patch.networks.changed.size() == 1)
    assert(patch.distribution_instances.added.size() == 1)
    assert(patch.distribution_instances.removed.size() == 1)
    assert(patch.distribution_instances.replaced.size() == 1)
    assert(patch.distribution_instances.unchanged.size() == 1)
    assert(float(runtime.scene_transition.last_patch_summary.max_stagger_delay) <= 0.34 + 0.001)
    assert(runtime.scene_transition.last_patch_summary.ripple_spawned)
    assert(active.get_node("Effects").get_child_count() == 0)

    var stable_tree_after := active.get_node("Distributions/trees/trees_000") as Node3D
    var unchanged_patch: Dictionary = await runtime.transition_candidate(
        world_root,
        runtime.build_candidate(new_world, catalog),
        new_world,
        new_world
    )
    assert(unchanged_patch.distribution_instances.unchanged.size() == 3)
    assert((active.get_node("Distributions/trees/trees_000") as Node3D).get_instance_id() == stable_tree_after.get_instance_id())
    assert(not runtime.scene_transition.last_patch_summary.ripple_spawned)

func _test_terrain_swap_preserves_unchanged_nodes() -> void:
    for child in world_root.get_children():
        child.free()
    var old_world := _terrain_world(0.0)
    var new_world := _terrain_world(0.35)
    runtime.commit_candidate(world_root, runtime.build_candidate(old_world, catalog))
    var active := world_root.get_node("GeneratedWorld")
    var entity := active.get_node("Entities/stable_church") as Node3D
    var terrain := active.get_node("Terrain/WorldSurface") as Node3D
    var active_id := active.get_instance_id()
    var entity_id := entity.get_instance_id()
    var terrain_id := terrain.get_instance_id()

    var patch: Dictionary = await runtime.transition_candidate(
        world_root,
        runtime.build_candidate(new_world, catalog),
        old_world,
        new_world
    )
    await process_frame
    active = world_root.get_node("GeneratedWorld")
    assert(active.get_instance_id() == active_id)
    assert((active.get_node("Entities/stable_church") as Node3D).get_instance_id() == entity_id)
    assert((active.get_node("Terrain/WorldSurface") as Node3D).get_instance_id() != terrain_id)
    assert(patch.terrain_changed)
    assert(patch.entities.unchanged.size() == 1)
    var rewrite_center: Vector3 = runtime.scene_transition.last_patch_summary.change_center
    assert(Vector2(rewrite_center.x, rewrite_center.z).distance_to(Vector2.ONE) < 0.01)

func _object_world(updated: bool) -> ResolvedWorld:
    var world := ResolvedWorld.new()
    world.world_bounds = Rect2(-40.0, -40.0, 80.0, 80.0)
    world.entities.append(_entity("stable_church", Vector3(-12.0, 0.0, 0.0)))
    world.entities.append(_entity(
        "moving_church",
        Vector3(12.0, 0.0, 5.0) if updated else Vector3(0.0, 0.0, 5.0)
    ))
    var road := ResolvedNetwork.new()
    road.id = "main_road"
    road.semantic_type = "road"
    road.surface_kind = "road_dirt"
    road.width = 5.5
    road.curve_points = PackedVector3Array([
        Vector3(0.0, 0.08, -18.0),
        Vector3(4.0 if updated else 0.0, 0.08, 18.0),
    ])
    world.networks.append(road)
    var trees := ResolvedDistribution.new()
    trees.id = "trees"
    trees.semantic_type = "tree"
    trees.instances.append(_instance("trees:000", "tree_01", Vector3(-6.0, 0.0, -5.0)))
    if not updated:
        trees.instances.append(_instance("trees:001", "tree_02", Vector3(-2.0, 0.0, -5.0)))
        trees.instances.append(_instance("trees:002", "tree_03", Vector3(2.0, 0.0, -5.0)))
    else:
        trees.instances.append(_instance("trees:002", "tree_05", Vector3(2.0, 0.0, -5.0)))
        trees.instances.append(_instance("trees:003", "tree_04", Vector3(8.0, 0.0, -5.0)))
    world.distributions.append(trees)
    return world

func _terrain_world(height: float) -> ResolvedWorld:
    var world := ResolvedWorld.new()
    world.world_bounds = Rect2(-1.0, -1.0, 2.0, 2.0)
    world.entities.append(_entity("stable_church", Vector3.ZERO))
    var terrain := ResolvedTerrain.new()
    terrain.world_bounds = world.world_bounds
    terrain.grid_size = 2
    terrain.heights = PackedFloat32Array([0.0, 0.0, 0.0, height])
    terrain.surface_masks = PackedColorArray([Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK])
    terrain.shore_wetness = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
    world.terrain = terrain
    return world

func _entity(object_id: String, position: Vector3) -> ResolvedEntity:
    var entity := ResolvedEntity.new()
    entity.id = object_id
    entity.semantic_type = "church"
    entity.prototype_id = "church_01"
    entity.transform = Transform3D(Basis.IDENTITY, position)
    return entity

func _instance(object_id: String, prototype_id: String, position: Vector3) -> Dictionary:
    return {
        "id": object_id,
        "prototype_id": prototype_id,
        "transform": Transform3D(Basis.IDENTITY, position),
    }

func _all_geometry_opaque(node: Node) -> bool:
    var found := false
    if node is GeometryInstance3D:
        found = true
        if not is_zero_approx((node as GeometryInstance3D).transparency):
            return false
    for child in node.get_children():
        var child_has_geometry := _has_geometry(child)
        if child_has_geometry:
            found = true
            if not _all_geometry_opaque(child):
                return false
    return found

func _has_geometry(node: Node) -> bool:
    if node is GeometryInstance3D:
        return true
    for child in node.get_children():
        if _has_geometry(child):
            return true
    return false

func _all_collisions_enabled(node: Node) -> bool:
    if node is CollisionShape3D and (node as CollisionShape3D).disabled:
        return false
    for child in node.get_children():
        if not _all_collisions_enabled(child):
            return false
    return true
