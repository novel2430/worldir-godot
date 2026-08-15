extends SceneTree

const REGION_TYPES := ["coastal_forest", "research_base", "snow_forest"]
const DISTRIBUTION_TYPES := ["tree", "grass", "shrub", "rock"]
const ENTITY_POLICY := {
    "rowboat": ["coastal_forest"],
    "tent": ["coastal_forest"],
    "cabin": ["coastal_forest", "snow_forest"],
    "research_station": ["research_base"],
    "radar_tower": ["research_base"],
    "warning_sign": ["research_base"],
    "cargo_truck": ["research_base"],
    "crate": ["research_base"],
    "maritime_memorial": ["snow_forest"],
    "ruined_archway": ["snow_forest"],
    "bunker": ["snow_forest"],
    "concrete_wall": ["snow_forest"],
}
const EDIT_CONFIG := {
    "population_caps": {"tree": 36, "grass": 48, "shrub": 36, "rock": 42},
    "density_spacing_multipliers": {"low": 3.0, "medium": 2.0, "high": 0.45},
}

var catalog: PrototypeCatalog

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    catalog = PrototypeCatalog.new()
    root.add_child(catalog)
    _test_complete_owner_aware_policy()
    await _test_stable_population_edits()
    await _test_region_type_edit()
    _test_single_path_edit()
    await _test_candidate_failure_preserves_committed_world()
    print("OwenG Step 03 closure tests passed")
    quit(0)

func _test_complete_owner_aware_policy() -> void:
    for region_type in REGION_TYPES:
        for semantic_type in DISTRIBUTION_TYPES:
            var options := catalog.get_prototype_ids(semantic_type, region_type)
            assert(not options.is_empty(), "Missing policy for (%s, %s)" % [semantic_type, region_type])
            for prototype_id in options:
                var metadata := catalog.get_metadata(prototype_id)
                assert(String(metadata.semantic_type) == semantic_type)
                assert(String(metadata.source_path).begins_with("res://assets/oweng/"))
                assert(FileAccess.file_exists(String(metadata.source_path)))
                assert(not String(metadata.license).is_empty())
                assert((metadata.visual_footprint as Vector2).x > 0.0)
                assert((metadata.visual_footprint as Vector2).y > 0.0)
    for semantic_type in ENTITY_POLICY.keys():
        for region_type in ENTITY_POLICY[semantic_type]:
            assert(catalog.has_semantic_type(semantic_type, region_type))
    assert(not catalog.has_semantic_type("rowboat", "research_base"))
    assert(catalog.get_prototype_ids("cabin", "coastal_forest") != catalog.get_prototype_ids("cabin", "snow_forest"))

    var fixture := _load_fixture("res://data/fixtures/oweng_final_world.json")
    var resolved := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    assert(resolved.errors.is_empty(), " | ".join(resolved.errors))
    assert(resolved.entities.size() == fixture.world_ir.entities.size())
    assert(resolved.distributions.size() == fixture.world_ir.distributions.size())
    assert(resolved.decorations.is_empty())
    for item: Dictionary in fixture.world_ir.distributions:
        var distribution := resolved.find_distribution(String(item.id))
        assert(distribution != null)
        if String(item.population.amount.mode) == "count":
            assert(distribution.instances.size() == int(item.population.amount.value))

func _test_stable_population_edits() -> void:
    var backend := WorldBackend.new(EDIT_CONFIG)
    var initial_ir := _population_ir("medium", "high")
    var rocks_reduced_ir: Dictionary = initial_ir.duplicate(true)
    _set_density(rocks_reduced_ir, "snow_rocks", "medium")
    var trees_increased_ir: Dictionary = rocks_reduced_ir.duplicate(true)
    _set_density(trees_increased_ir, "coastal_trees", "high")

    var initial := backend.lower(initial_ir, catalog, 48031)
    var rocks_reduced := backend.lower(rocks_reduced_ir, catalog, 48031)
    var trees_increased := backend.lower(trees_increased_ir, catalog, 48031)
    assert(initial.errors.is_empty(), " | ".join(initial.errors))
    assert(rocks_reduced.errors.is_empty(), " | ".join(rocks_reduced.errors))
    assert(trees_increased.errors.is_empty(), " | ".join(trees_increased.errors))

    var old_rocks := initial.find_distribution("snow_rocks")
    var fewer_rocks := rocks_reduced.find_distribution("snow_rocks")
    assert(fewer_rocks.instances.size() < old_rocks.instances.size())
    _assert_stable_prefix(old_rocks, fewer_rocks)
    var rock_patch := SceneDiff.new().compare(initial, rocks_reduced)
    assert(_records_for(rock_patch.distribution_instances.removed, "snow_rocks").size() == old_rocks.instances.size() - fewer_rocks.instances.size())
    assert(_records_for(rock_patch.distribution_instances.unchanged, "snow_rocks").size() == fewer_rocks.instances.size())
    assert(_records_for(rock_patch.distribution_instances.added, "snow_rocks").is_empty())
    assert(_records_for(rock_patch.distribution_instances.moved, "snow_rocks").is_empty())
    assert(_records_for(rock_patch.distribution_instances.replaced, "snow_rocks").is_empty())

    var old_trees := rocks_reduced.find_distribution("coastal_trees")
    var more_trees := trees_increased.find_distribution("coastal_trees")
    assert(more_trees.instances.size() > old_trees.instances.size())
    _assert_stable_prefix(more_trees, old_trees)
    var tree_patch := SceneDiff.new().compare(rocks_reduced, trees_increased)
    assert(_records_for(tree_patch.distribution_instances.added, "coastal_trees").size() == more_trees.instances.size() - old_trees.instances.size())
    assert(_records_for(tree_patch.distribution_instances.unchanged, "coastal_trees").size() == old_trees.instances.size())
    assert(_records_for(tree_patch.distribution_instances.removed, "coastal_trees").is_empty())
    assert(_records_for(tree_patch.distribution_instances.moved, "coastal_trees").is_empty())
    assert(_records_for(tree_patch.distribution_instances.replaced, "coastal_trees").is_empty())

    var runtime := SceneRuntime.new()
    root.add_child(runtime)
    runtime.scene_transition.duration_scale = 0.01
    var world_root := Node3D.new()
    world_root.name = "PopulationWorldRoot"
    root.add_child(world_root)
    runtime.commit_candidate(world_root, runtime.build_candidate(initial, catalog))
    var stable_rock_nodes := _node_ids(
        world_root.get_node("GeneratedWorld/Distributions/snow_rocks"),
        fewer_rocks.instances.size()
    )
    await runtime.transition_candidate(
        world_root,
        runtime.build_candidate(rocks_reduced, catalog),
        initial,
        rocks_reduced
    )
    await process_frame
    await process_frame
    _assert_node_ids(
        world_root.get_node("GeneratedWorld/Distributions/snow_rocks"),
        stable_rock_nodes
    )
    assert(world_root.get_node("GeneratedWorld/Distributions/snow_rocks").get_child_count() == fewer_rocks.instances.size())

    var stable_tree_nodes := _node_ids(
        world_root.get_node("GeneratedWorld/Distributions/coastal_trees"),
        old_trees.instances.size()
    )
    await runtime.transition_candidate(
        world_root,
        runtime.build_candidate(trees_increased, catalog),
        rocks_reduced,
        trees_increased
    )
    await process_frame
    await process_frame
    _assert_node_ids(
        world_root.get_node("GeneratedWorld/Distributions/coastal_trees"),
        stable_tree_nodes
    )
    assert(world_root.get_node("GeneratedWorld/Distributions/coastal_trees").get_child_count() == more_trees.instances.size())
    print(
        "Population edits: snow rocks %d -> %d, coastal trees %d -> %d"
        % [old_rocks.instances.size(), fewer_rocks.instances.size(), old_trees.instances.size(), more_trees.instances.size()]
    )
    runtime.free()
    world_root.free()

func _test_region_type_edit() -> void:
    var before_ir := _region_type_ir("coastal_forest")
    var after_ir := _region_type_ir("snow_forest")
    var backend := WorldBackend.new()
    var before := backend.lower(before_ir, catalog, 90210)
    var after := backend.lower(after_ir, catalog, 90210)
    assert(before.errors.is_empty(), " | ".join(before.errors))
    assert(after.errors.is_empty(), " | ".join(after.errors))
    assert(after.find_region("edited_region").profile_id == "snow_forest")
    assert(before.find_entity("region_cabin").prototype_id == "oweng_cabin_coastal")
    assert(after.find_entity("region_cabin").prototype_id == "oweng_cabin_snow")
    assert(_semantic_object_ids(before) == _semantic_object_ids(after))
    assert(after.entities.size() == 1 and after.distributions.size() == 2)
    assert(after.decorations.is_empty())
    assert(after.find_distribution("region_trees").owner_region_type == "snow_forest")
    assert(after.find_distribution("region_rocks").owner_region_type == "snow_forest")

    var patch := SceneDiff.new().compare(before, after)
    assert(patch.regions.changed.size() == 1)
    assert(patch.entities.replaced.size() == 1)
    assert(patch.entities.added.is_empty() and patch.entities.removed.is_empty())
    assert(patch.distribution_instances.added.is_empty())
    assert(patch.distribution_instances.removed.is_empty())
    assert(patch.terrain_changed)

    var runtime := SceneRuntime.new()
    root.add_child(runtime)
    runtime.scene_transition.duration_scale = 0.01
    var world_root := Node3D.new()
    world_root.name = "RegionEditWorldRoot"
    root.add_child(world_root)
    runtime.commit_candidate(world_root, runtime.build_candidate(before, catalog))
    var old_cabin := world_root.get_node("GeneratedWorld/Entities/region_cabin") as WorldPrototype
    var old_cabin_id := old_cabin.get_instance_id()
    await runtime.transition_candidate(
        world_root,
        runtime.build_candidate(after, catalog),
        before,
        after
    )
    await process_frame
    await process_frame
    var new_cabin := world_root.get_node("GeneratedWorld/Entities/region_cabin") as WorldPrototype
    assert(new_cabin.get_instance_id() != old_cabin_id)
    assert(new_cabin.prototype_id == "oweng_cabin_snow")
    assert(world_root.get_node("GeneratedWorld/Distributions/region_trees").get_child_count() == 5)
    assert(world_root.get_node("GeneratedWorld/Distributions/region_rocks").get_child_count() == 4)
    runtime.free()
    world_root.free()

func _test_single_path_edit() -> void:
    var before_ir := _population_ir("medium", "medium")
    var after_ir: Dictionary = before_ir.duplicate(true)
    after_ir.networks[0].topology.to = "southeast"
    var backend := WorldBackend.new(EDIT_CONFIG)
    var before := backend.lower(before_ir, catalog, 1122)
    var after := backend.lower(after_ir, catalog, 1122)
    assert(before.errors.is_empty() and after.errors.is_empty())
    assert(before.networks.size() == 1 and after.networks.size() == 1)
    assert(before.networks[0].id == "main_path" and after.networks[0].id == "main_path")
    var patch := SceneDiff.new().compare(before, after)
    assert(patch.networks.changed.size() == 1)
    assert(patch.networks.added.is_empty() and patch.networks.removed.is_empty())

func _test_candidate_failure_preserves_committed_world() -> void:
    var packed := load("res://scenes/main.tscn") as PackedScene
    var main := packed.instantiate() as Node3D
    var coordinator := main.get_node("WorldCoordinator") as WorldCoordinator
    coordinator.auto_generate_demo = false
    coordinator.use_http_compiler = false
    main.get_node("UI").free()
    root.add_child(main)
    await process_frame

    var committed_ir := _transaction_ir("crate")
    coordinator._on_compile_completed(_compile_result(committed_ir))
    await process_frame
    assert(coordinator.current_resolved != null)
    var world_state := main.get_node("WorldState") as WorldState
    var committed_json := JSON.stringify(world_state.current_ir)
    var committed_resolved := coordinator.current_resolved
    var generated := main.get_node("WorldRoot/GeneratedWorld") as Node3D
    var generated_id := generated.get_instance_id()

    var rejected_ir := _transaction_ir("rowboat")
    coordinator._on_compile_completed(_compile_result(rejected_ir))
    await process_frame
    assert(JSON.stringify(world_state.current_ir) == committed_json)
    assert(coordinator.current_resolved == committed_resolved)
    assert((main.get_node("WorldRoot/GeneratedWorld") as Node3D).get_instance_id() == generated_id)
    assert(not coordinator.busy)
    main.free()

func _population_ir(coastal_density: String, snow_density: String) -> Dictionary:
    return {
        "regions": [
            {"id": "coastal_region", "type": "coastal_forest", "placement": {"anchor": "west"}},
            {"id": "research_region", "type": "research_base", "placement": {"anchor": "center"}},
            {"id": "snow_region", "type": "snow_forest", "placement": {"anchor": "east"}},
        ],
        "networks": [{
            "id": "main_path", "type": "path",
            "topology": {"from": "west", "to": "east", "via": ["research_region"]},
        }],
        "entities": [],
        "distributions": [
            {
                "id": "coastal_trees", "type": "tree",
                "placement": {"relations": [{"type": "inside", "target": "coastal_region"}]},
                "population": {
                    "amount": {"mode": "density", "value": coastal_density},
                    "arrangement": {"type": "clustered"},
                },
            },
            {
                "id": "snow_rocks", "type": "rock",
                "placement": {"relations": [{"type": "inside", "target": "snow_region"}]},
                "population": {
                    "amount": {"mode": "density", "value": snow_density},
                    "arrangement": {"type": "uniform"},
                },
            },
        ],
    }

func _region_type_ir(region_type: String) -> Dictionary:
    return {
        "regions": [{
            "id": "edited_region", "type": region_type, "placement": {"anchor": "west"},
        }],
        "networks": [],
        "entities": [{
            "id": "region_cabin", "type": "cabin",
            "placement": {"relations": [{"type": "inside", "target": "edited_region"}]},
        }],
        "distributions": [
            {
                "id": "region_trees", "type": "tree",
                "placement": {"relations": [{"type": "inside", "target": "edited_region"}]},
                "population": {"amount": {"mode": "count", "value": 5}},
            },
            {
                "id": "region_rocks", "type": "rock",
                "placement": {"relations": [{"type": "inside", "target": "edited_region"}]},
                "population": {"amount": {"mode": "count", "value": 4}},
            },
        ],
    }

func _transaction_ir(entity_type: String) -> Dictionary:
    return {
        "regions": [{"id": "base", "type": "research_base", "placement": {}}],
        "networks": [],
        "entities": [{
            "id": "transaction_object", "type": entity_type,
            "placement": {"relations": [{"type": "inside", "target": "base"}]},
        }],
        "distributions": [],
    }

func _compile_result(world_ir: Dictionary) -> Dictionary:
    return {
        "status": "ok", "world_ir": world_ir,
        "runtime_bindings": [], "runtime_fact_ops": [], "meta": {},
    }

func _set_density(world_ir: Dictionary, distribution_id: String, density: String) -> void:
    for item: Dictionary in world_ir.distributions:
        if String(item.id) == distribution_id:
            item.population.amount.value = density
            return
    assert(false, "Missing distribution: %s" % distribution_id)

func _assert_stable_prefix(larger: ResolvedDistribution, smaller: ResolvedDistribution) -> void:
    assert(larger.instances.size() >= smaller.instances.size())
    for index in range(smaller.instances.size()):
        var large_instance: Dictionary = larger.instances[index]
        var small_instance: Dictionary = smaller.instances[index]
        assert(String(large_instance.id) == "%s:%03d" % [larger.id, index])
        assert(large_instance.id == small_instance.id)
        assert(large_instance.prototype_id == small_instance.prototype_id)
        assert((large_instance.transform as Transform3D).is_equal_approx(
            small_instance.transform as Transform3D
        ))

func _records_for(records: Array, owner_id: String) -> Array:
    return records.filter(func(record: Dictionary) -> bool:
        return String(record.owner_id) == owner_id
    )

func _node_ids(group: Node, count: int) -> Array[int]:
    var result: Array[int] = []
    for index in range(count):
        result.append(group.get_node("%s_%03d" % [group.name, index]).get_instance_id())
    return result

func _assert_node_ids(group: Node, expected_ids: Array[int]) -> void:
    for index in range(expected_ids.size()):
        assert(group.get_node("%s_%03d" % [group.name, index]).get_instance_id() == expected_ids[index])

func _semantic_object_ids(world: ResolvedWorld) -> Array[String]:
    var result: Array[String] = []
    for entity: ResolvedEntity in world.entities:
        result.append("entity:%s:%s" % [entity.id, entity.semantic_type])
    for distribution: ResolvedDistribution in world.distributions:
        result.append("distribution:%s:%s" % [distribution.id, distribution.semantic_type])
    result.sort()
    return result

func _load_fixture(path: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    assert(typeof(parsed) == TYPE_DICTIONARY)
    return parsed as Dictionary
