extends SceneTree

var failures := 0
var catalog: PrototypeCatalog

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    catalog = PrototypeCatalog.new()
    root.add_child(catalog)

    _test_forest_only()
    _test_explicit_override()
    _test_per_forest_override()
    _test_determinism()
    _test_no_forest()
    _test_implicit_failure_rolls_back()
    _test_synthetic_id_collision()

    catalog.free()
    if failures == 0:
        print("Implicit forest default tests passed")
    quit(1 if failures > 0 else 0)

func _test_forest_only() -> void:
    var ir := _world([
        {"id": "forest", "type": "forest", "placement": {"anchor": "west"}},
    ])
    var original: Dictionary = ir.duplicate(true)
    var resolved := WorldBackend.new().lower(ir, catalog, 1337)
    var forest: ResolvedRegion = resolved.find_region("forest")
    var implicit := _implicit_for(resolved, "forest")

    _expect(resolved.errors.is_empty(), "Forest-only IR must resolve")
    _expect(forest != null, "Forest-only IR must retain its forest Region")
    _expect(implicit != null, "Forest-only IR must gain an implicit tree Distribution")
    if implicit != null and forest != null:
        _expect(implicit.instances.size() == DistributionLowerer.DENSITY_COUNTS["medium"], "Implicit forest trees must use medium density")
        _expect(_all_instances_inside(implicit, forest), "Every implicit tree must be inside its forest")
    _expect(ir == original, "Implicit lowering must not mutate World IR")

func _test_explicit_override() -> void:
    var ir := _world(
        [{"id": "forest", "type": "forest", "placement": {"anchor": "west"}}],
        [_tree_distribution("forest_trees", "forest", "low")]
    )
    var resolved := WorldBackend.new().lower(ir, catalog, 1337)
    var explicit: ResolvedDistribution = resolved.find_distribution("forest_trees")

    _expect(resolved.errors.is_empty(), "Explicit forest trees must resolve")
    _expect(explicit != null, "Explicit tree Distribution must be preserved")
    if explicit != null:
        _expect(explicit.instances.size() == DistributionLowerer.DENSITY_COUNTS["low"], "Explicit low density must keep existing count semantics")
    _expect(_implicit_for(resolved, "forest") == null, "Explicit trees inside a forest must suppress that forest default")
    _expect(resolved.distributions.size() == 1, "Explicit override must not be combined with implicit trees")

func _test_per_forest_override() -> void:
    var ir := _world(
        [
            {"id": "forest_a", "type": "forest", "placement": {"anchor": "west"}},
            {"id": "forest_b", "type": "forest", "placement": {"anchor": "east"}},
        ],
        [_tree_distribution("trees_a", "forest_a", "low")]
    )
    var resolved := WorldBackend.new().lower(ir, catalog, 1337)
    var explicit: ResolvedDistribution = resolved.find_distribution("trees_a")
    var implicit_b := _implicit_for(resolved, "forest_b")

    _expect(resolved.errors.is_empty(), "Per-forest override IR must resolve")
    _expect(explicit != null and explicit.instances.size() == DistributionLowerer.DENSITY_COUNTS["low"], "forest_a must use only its explicit low population")
    _expect(_implicit_for(resolved, "forest_a") == null, "forest_a must not receive an implicit population")
    _expect(implicit_b != null, "forest_b must retain its independent implicit population")
    if implicit_b != null:
        _expect(implicit_b.instances.size() == DistributionLowerer.DENSITY_COUNTS["medium"], "forest_b implicit population must use medium density")

func _test_determinism() -> void:
    var ir := _world([
        {"id": "forest", "type": "forest", "placement": {"anchor": "west"}},
    ])
    var a := WorldBackend.new().lower(ir, catalog, 4242)
    var b := WorldBackend.new().lower(ir, catalog, 4242)
    var trees_a := _implicit_for(a, "forest")
    var trees_b := _implicit_for(b, "forest")

    _expect(trees_a != null and trees_b != null, "Determinism test requires both implicit populations")
    if trees_a == null or trees_b == null:
        return
    _expect(trees_a.instances.size() == trees_b.instances.size(), "Deterministic implicit populations must have equal sizes")
    for index in range(mini(trees_a.instances.size(), trees_b.instances.size())):
        var transform_a: Transform3D = trees_a.instances[index]["transform"]
        var transform_b: Transform3D = trees_b.instances[index]["transform"]
        _expect(transform_a.is_equal_approx(transform_b), "Implicit tree transforms must be deterministic")

func _test_no_forest() -> void:
    var ir := _world([
        {"id": "coast", "type": "coast", "placement": {"anchor": "east"}},
    ])
    var resolved := WorldBackend.new().lower(ir, catalog, 1337)
    _expect(resolved.errors.is_empty(), "Non-forest world must resolve")
    _expect(resolved.distributions.is_empty(), "A world without forest must not gain implicit trees")

func _test_implicit_failure_rolls_back() -> void:
    var ir := _world([
        {"id": "forest", "type": "forest"},
    ])
    var bindings := [{
        "ir_object_id": "forest",
        "runtime_fact_id": "tiny_forest",
        "placement": "inside",
    }]
    var payloads := {
        "tiny_forest": {"aabb2": {"x": 0.0, "z": 0.0, "w": 2.0, "d": 2.0}},
    }
    var backend := WorldBackend.new()
    var resolved := backend.lower(ir, catalog, 1337, bindings, payloads)

    _expect(resolved.errors.is_empty(), "Implicit decoration failure must not fail the world")
    _expect(_implicit_for(resolved, "forest") == null, "An incomplete implicit population must be skipped")
    _expect(not resolved.warnings.is_empty(), "Skipped implicit decoration should produce a warning")
    _expect(backend.solver.occupied.is_empty(), "Failed implicit placement must roll back partial occupancy")

func _test_synthetic_id_collision() -> void:
    var colliding_id := WorldBackend.IMPLICIT_FOREST_TREES_PREFIX + "forest"
    var reserved_distribution := {
        "id": colliding_id,
        "type": "house",
        "placement": {"relations": [{"type": "inside", "target": "forest"}]},
        "population": {"amount": {"mode": "count", "value": 0}},
    }
    var ir := _world(
        [{"id": "forest", "type": "forest", "placement": {"anchor": "west"}}],
        [reserved_distribution]
    )
    var resolved := WorldBackend.new().lower(ir, catalog, 1337)
    var implicit := _implicit_for(resolved, "forest")

    _expect(resolved.find_distribution(colliding_id) != null, "Explicit IR ID must be preserved on backend-prefix collision")
    _expect(implicit != null and implicit.id != colliding_id, "Implicit ID must deterministically avoid an IR collision")

func _world(regions: Array, distributions: Array = []) -> Dictionary:
    return {
        "regions": regions,
        "networks": [],
        "entities": [],
        "distributions": distributions,
    }

func _tree_distribution(distribution_id: String, forest_id: String, density: String) -> Dictionary:
    return {
        "id": distribution_id,
        "type": "tree",
        "placement": {"relations": [{"type": "inside", "target": forest_id}]},
        "population": {
            "amount": {"mode": "density", "value": density},
            "arrangement": {"type": "random"},
        },
    }

func _implicit_for(resolved: ResolvedWorld, forest_id: String) -> ResolvedDistribution:
    var id_prefix := WorldBackend.IMPLICIT_FOREST_TREES_PREFIX + forest_id
    for distribution in resolved.distributions:
        if distribution.semantic_type == "tree" and String(distribution.id).begins_with(id_prefix):
            return distribution
    return null

func _all_instances_inside(distribution: ResolvedDistribution, forest: ResolvedRegion) -> bool:
    for instance in distribution.instances:
        var transform: Transform3D = instance["transform"]
        var point := Vector2(transform.origin.x, transform.origin.z)
        if not Geometry2D.is_point_in_polygon(point, forest.polygon):
            return false
    return true

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    failures += 1
    push_error(message)
