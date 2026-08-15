extends SceneTree

func _init() -> void:
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)

    var explicit_random_forest := _lower(catalog, "forest", "random", 8128)
    var explicit_random_field := _lower(catalog, "field", "random", 8128)
    var unspecified_forest := _lower(catalog, "forest", "", 8128)
    var unspecified_forest_repeat := _lower(catalog, "forest", "", 8128)
    var unspecified_field := _lower(catalog, "field", "", 8128)
    var clustered_forest := _lower(catalog, "forest", "clustered", 8128)
    var uniform_forest := _lower(catalog, "forest", "uniform", 8128)

    for result in [
        explicit_random_forest,
        explicit_random_field,
        unspecified_forest,
        unspecified_forest_repeat,
        unspecified_field,
        clustered_forest,
        uniform_forest,
    ]:
        assert(result != null)
        assert(result.instances.size() == 36)

    # With identical geometry and RNG, explicit random is independent of Region
    # presentation policy. A Forest must not secretly add clustering to it.
    assert(_same_xz(explicit_random_forest, explicit_random_field))

    # Only the missing-arrangement Forest receives the backend naturalization
    # profile. The same unspecified population in a Field stays ordinary random.
    assert(not _same_xz(unspecified_forest, unspecified_field))
    assert(_same_instances(unspecified_forest, unspecified_forest_repeat))

    # Explicit arrangements remain distinct semantic branches.
    assert(not _same_xz(explicit_random_forest, clustered_forest))
    assert(not _same_xz(explicit_random_forest, uniform_forest))
    assert(not _same_xz(clustered_forest, uniform_forest))

    print("Distribution arrangement semantics tests passed")
    quit(0)

func _lower(
    catalog: PrototypeCatalog,
    region_type: String,
    arrangement: String,
    seed_value: int
) -> ResolvedDistribution:
    var region := ResolvedRegion.new()
    region.id = "domain"
    region.semantic_type = region_type
    region.polygon = PackedVector2Array([
        Vector2(-30.0, -30.0),
        Vector2(30.0, -30.0),
        Vector2(30.0, 30.0),
        Vector2(-30.0, 30.0),
    ])
    var population := {
        "amount": {"mode": "count", "value": 36},
    }
    if not arrangement.is_empty():
        population["arrangement"] = {"type": arrangement}
    var item := {
        "id": "trees",
        "type": "tree",
        "placement": {"relations": [{"type": "inside", "target": "domain"}]},
        "population": population,
    }
    var solver := PlacementSolver.new()
    solver.configure(Rect2(-40.0, -40.0, 80.0, 80.0), seed_value)
    var context := {
        "regions": {"domain": region},
        "networks": {},
        "entities": {},
        "distributions": {},
        "spatial_payloads": {},
        "seed": seed_value,
    }
    return DistributionLowerer.new().lower(item, catalog, solver, context)

func _same_xz(a: ResolvedDistribution, b: ResolvedDistribution) -> bool:
    if a.instances.size() != b.instances.size():
        return false
    for index in range(a.instances.size()):
        var a_origin: Vector3 = (a.instances[index]["transform"] as Transform3D).origin
        var b_origin: Vector3 = (b.instances[index]["transform"] as Transform3D).origin
        if not Vector2(a_origin.x, a_origin.z).is_equal_approx(Vector2(b_origin.x, b_origin.z)):
            return false
    return true

func _same_instances(a: ResolvedDistribution, b: ResolvedDistribution) -> bool:
    if a.instances.size() != b.instances.size():
        return false
    for index in range(a.instances.size()):
        if a.instances[index]["prototype_id"] != b.instances[index]["prototype_id"]:
            return false
        var a_transform: Transform3D = a.instances[index]["transform"]
        var b_transform: Transform3D = b.instances[index]["transform"]
        if not a_transform.is_equal_approx(b_transform):
            return false
    return true
