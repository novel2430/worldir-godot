extends SceneTree

const ResolvedChunkScript = preload("res://scripts/resolved/resolved_chunk.gd")

var catalog: PrototypeCatalog
var runtime: SceneRuntime
var failures := 0

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    catalog = PrototypeCatalog.new()
    root.add_child(catalog)
    runtime = SceneRuntime.new()
    runtime.prototype_catalog = catalog
    runtime.scene_transition.duration_scale = 0.02
    root.add_child(runtime)

    await _test_chunk_scoped_mount_diff_and_transition()

    if failures == 0:
        print("Chunk-scoped Scene Runtime tests passed")
    quit(1 if failures > 0 else 0)

func _test_chunk_scoped_mount_diff_and_transition() -> void:
    var c5_root := Node3D.new()
    c5_root.name = "Chunk_5_5"
    root.add_child(c5_root)
    var c6_root := Node3D.new()
    c6_root.name = "Chunk_6_5"
    root.add_child(c6_root)

    var old_c5: Variant = _chunk(Vector2i(5, 5), 0, false)
    var new_c5: Variant = _chunk(Vector2i(5, 5), 1, true)
    var c6: Variant = _chunk(Vector2i(6, 5), 0, false)
    _expect(old_c5.bounds == old_c5.world_bounds, "ResolvedChunk bounds must alias world_bounds")
    _expect(old_c5.revision == 0 and new_c5.revision == 1, "ResolvedChunk must retain revision provenance")

    _expect(runtime.mount_chunk(c5_root, old_c5) != null, "C5 must mount")
    _expect(runtime.mount_chunk(c6_root, c6) != null, "C6 must mount independently")
    var c5_active := c5_root.get_node(SceneRuntime.CHUNK_CONTENT_NAME) as Node3D
    var c6_active := c6_root.get_node(SceneRuntime.CHUNK_CONTENT_NAME) as Node3D
    var c5_active_id := c5_active.get_instance_id()
    var c6_active_id := c6_active.get_instance_id()
    var c6_stable := c6_active.get_node("Entities/stable_church") as Node3D
    var c6_stable_id := c6_stable.get_instance_id()
    var c6_stable_transform := c6_stable.transform

    var patch: Variant = await runtime.transition_chunk(
        c5_root,
        old_c5,
        new_c5,
        SceneRuntime.TRANSITION_MODE_FULL_REWRITE
    )
    await process_frame
    await process_frame

    _expect(patch != null, "C5 transition must produce a patch")
    if patch != null:
        _expect(_ids(patch.entities.unchanged) == ["stable_church"], "Stable ID/type/transform must be unchanged")
        _expect(_ids(patch.entities.moved) == ["moving_church"], "Same ID with new transform must be moved")
        _expect(_ids(patch.distribution_instances.added) == ["trees:added"], "New ID must be added")
        _expect(_ids(patch.distribution_instances.removed) == ["trees:removed"], "Missing old ID must be removed")
        _expect(_ids(patch.distribution_instances.replaced) == ["trees:replaced"], "Same ID with new prototype must be replaced")
        _expect(_ids(patch.distribution_instances.unchanged) == ["trees:stable"], "Stable population ID must remain unchanged across revisions")

    var c5_after := c5_root.get_node(SceneRuntime.CHUNK_CONTENT_NAME) as Node3D
    _expect(c5_after.get_instance_id() == c5_active_id, "Animated transition must patch C5 in place")
    _expect(
        (c5_after.get_node("Entities/moving_church") as Node3D).transform.is_equal_approx(
            (new_c5.find_entity("moving_church") as ResolvedEntity).transform
        ),
        "C5 moved entity must reach the new transform"
    )
    _expect(not c5_after.has_node("Distributions/trees/trees_removed"), "C5 removed ID must leave the Scene")
    _expect(c5_after.has_node("Distributions/trees/trees_added"), "C5 added ID must enter the Scene")

    var c6_after := c6_root.get_node(SceneRuntime.CHUNK_CONTENT_NAME) as Node3D
    _expect(c6_after.get_instance_id() == c6_active_id, "Transitioning C5 must not replace C6 content")
    _expect(
        (c6_after.get_node("Entities/stable_church") as Node3D).get_instance_id() == c6_stable_id,
        "Transitioning C5 must not touch C6 object identity"
    )
    _expect(
        (c6_after.get_node("Entities/stable_church") as Node3D).transform.is_equal_approx(c6_stable_transform),
        "Transitioning C5 must not touch C6 transforms"
    )

    runtime.remove_chunk(c5_root)
    await process_frame
    _expect(not c5_root.has_node(SceneRuntime.CHUNK_CONTENT_NAME), "remove_chunk must remove only C5 content")
    _expect(c6_root.has_node(SceneRuntime.CHUNK_CONTENT_NAME), "remove_chunk(C5) must leave C6 mounted")

func _chunk(coord: Vector2i, revision: int, updated: bool):
    var chunk := ResolvedChunkScript.new()
    chunk.coord = coord
    chunk.revision = revision
    chunk.bounds = Rect2(Vector2(coord) * 160.0, Vector2.ONE * 160.0)
    chunk.entities.append(_entity("stable_church", Vector3(8.0, 0.0, 8.0)))
    chunk.entities.append(_entity(
        "moving_church",
        Vector3(24.0, 0.0, 12.0) if updated else Vector3(16.0, 0.0, 12.0)
    ))

    var trees := ResolvedDistribution.new()
    trees.id = "trees"
    trees.semantic_type = "tree"
    trees.instances.append(_instance("trees:stable", "tree_01", Vector3(5.0, 0.0, 5.0)))
    if updated:
        trees.instances.append(_instance("trees:replaced", "tree_05", Vector3(10.0, 0.0, 5.0)))
        trees.instances.append(_instance("trees:added", "tree_04", Vector3(15.0, 0.0, 5.0)))
    else:
        trees.instances.append(_instance("trees:removed", "tree_02", Vector3(7.5, 0.0, 5.0)))
        trees.instances.append(_instance("trees:replaced", "tree_03", Vector3(10.0, 0.0, 5.0)))
    chunk.distributions.append(trees)
    return chunk

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

func _ids(records: Array) -> Array[String]:
    var result: Array[String] = []
    for record: Dictionary in records:
        result.append(String(record["id"]))
    return result

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    failures += 1
    push_error(message)
