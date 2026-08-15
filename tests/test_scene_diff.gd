extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    var fixture: Dictionary = JSON.parse_string(
        FileAccess.get_file_as_string("res://data/fixtures/oweng_semantic_baseline.json")
    )
    var old_world := WorldBackend.new().lower(fixture.world_ir, catalog, 404)
    var same_world := WorldBackend.new().lower(fixture.world_ir, catalog, 404)
    assert(old_world.errors.is_empty() and same_world.errors.is_empty())
    var identical := SceneDiff.new().compare(old_world, same_world)
    assert(not identical.terrain_changed)
    assert(identical.regions.changed.is_empty())
    assert(identical.networks.changed.is_empty())
    assert(identical.entities.moved.is_empty())
    assert(identical.entities.replaced.is_empty())
    assert(identical.distribution_instances.moved.is_empty())
    assert(identical.distribution_instances.replaced.is_empty())

    var changed := ResolvedWorld.new()
    var old_entity := ResolvedEntity.new()
    old_entity.id = "crate"
    old_entity.semantic_type = "crate"
    old_entity.prototype_id = "oweng_crate_01"
    old_entity.transform = Transform3D.IDENTITY
    changed.entities.append(old_entity)
    var moved := ResolvedWorld.new()
    var moved_entity := ResolvedEntity.new()
    moved_entity.id = "crate"
    moved_entity.semantic_type = "crate"
    moved_entity.prototype_id = "oweng_crate_01"
    moved_entity.transform = Transform3D(Basis.IDENTITY, Vector3(2.0, 0.0, 0.0))
    moved.entities.append(moved_entity)
    var movement := SceneDiff.new().compare(changed, moved)
    assert(movement.entities.moved.size() == 1)
    assert(movement.entities.replaced.is_empty())

    var old_distribution := ResolvedDistribution.new()
    old_distribution.id = "trees"
    old_distribution.semantic_type = "tree"
    old_distribution.instances = [{
        "id": "trees:000", "prototype_id": "tree_01", "transform": Transform3D.IDENTITY,
    }]
    var new_distribution := ResolvedDistribution.new()
    new_distribution.id = "trees"
    new_distribution.semantic_type = "tree"
    new_distribution.instances = [{
        "id": "trees:000", "prototype_id": "tree_04", "transform": Transform3D.IDENTITY,
    }]
    var old_set := ResolvedWorld.new()
    var new_set := ResolvedWorld.new()
    old_set.distributions.append(old_distribution)
    new_set.distributions.append(new_distribution)
    assert(SceneDiff.new().compare(old_set, new_set).distribution_instances.replaced.size() == 1)
    print("Stable Resolved SceneDiff tests passed")
    quit(0)
