extends SceneTree

var failures := 0

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    var fixture := _load_json("res://data/fixtures/coastal_town_initial.json")
    var catalog := PrototypeCatalog.new()
    root.add_child(catalog)
    _test_catalog(catalog)

    var ir_before := JSON.stringify(fixture.world_ir)
    var first := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    var second := WorldBackend.new().lower(fixture.world_ir, catalog, 1337)
    _expect(first.errors.is_empty(), "Demo forest dressing must lower without errors")
    _expect(second.errors.is_empty(), "Repeated demo forest dressing must lower without errors")
    _expect(JSON.stringify(fixture.world_ir) == ir_before, "Forest dressing must not mutate World IR")
    _test_demo_composition(first, catalog)
    _test_determinism(first, second)
    _test_area_scaling(catalog)
    _test_semantic_occupancy_and_road_clearance(catalog)
    _test_no_forest(catalog)
    _test_runtime(first, catalog)

    catalog.free()
    if failures == 0:
        print("Forest dressing tests passed")
    quit(1 if failures > 0 else 0)

func _test_catalog(catalog: PrototypeCatalog) -> void:
    var expected := {
        "rock": ["rock_01", "rock_02", "rock_03"],
        "bush": ["bush_01", "bush_02", "bush_03"],
        "grass": ["grass_01", "grass_02", "grass_03"],
        "dead_tree": ["dead_tree_01", "dead_tree_02"],
    }
    for kind in expected:
        var prototype_ids := catalog.get_dressing_prototype_ids(kind)
        _expect(prototype_ids == expected[kind], "Dressing catalog must expose the expected %s variants" % kind)
        for prototype_id in prototype_ids:
            var scene := catalog.get_scene(prototype_id)
            _expect(scene != null, "Dressing prototype '%s' must load" % prototype_id)
            if scene == null:
                continue
            var instance := scene.instantiate() as WorldPrototype
            _expect(instance != null and instance.semantic_type == kind, "Dressing prototype metadata must match '%s'" % kind)
            var meta := catalog.get_metadata(prototype_id)
            var footprint: Vector2 = meta.get("visual_footprint", Vector2.ZERO)
            _expect(footprint.x > 0.0 and footprint.y > 0.0, "Dressing prototype '%s' needs a measured footprint" % prototype_id)
            _expect(float(meta.get("population_scale_min", 0.0)) > 0.0, "Dressing scale metadata must be positive")
            if kind == "rock" or kind == "dead_tree":
                _expect(not instance.find_children("*", "CollisionShape3D", true, false).is_empty(), "%s must provide physical collision" % prototype_id)
            instance.free()

func _test_demo_composition(world: ResolvedWorld, catalog: PrototypeCatalog) -> void:
    _expect(world.distributions.size() == 2, "Dressing must not become an IR-owned Distribution")
    _expect(world.decorations.size() == 4, "Demo forest should produce four dressing layers")
    var forest := world.find_region("forest")
    var road := world.find_network("main_road")
    _expect(forest != null and road != null, "Demo forest and road must resolve")
    if forest == null or road == null:
        return

    var area := _polygon_area(forest.polygon)
    var counts := {}
    var edge_means := {}
    for decoration: ResolvedDecoration in world.decorations:
        var rule: Dictionary = ForestDresser.RULES[decoration.decoration_type]
        var expected_count := mini(int(rule["cap"]), int(floor(area / float(rule["area_per_instance"]))))
        _expect(decoration.instances.size() == expected_count, "Uncongested demo dressing should meet its area budget")
        counts[decoration.decoration_type] = decoration.instances.size()
        var edge_total := 0.0
        var used_prototypes := {}
        for item in decoration.instances:
            var transform: Transform3D = item["transform"]
            var point := Vector2(transform.origin.x, transform.origin.z)
            var radius := float(item["occupancy_radius"])
            _expect(Geometry2D.is_point_in_polygon(point, forest.polygon), "Dressing center must stay in the resolved forest polygon")
            _expect(
                point.distance_to(PlacementSolver.new().nearest_point_on_network(point, road))
                >= road.width * 0.5 + radius + float(rule["road_clearance"]) - 0.001,
                "Dressing must respect procedural road width and clearance"
            )
            used_prototypes[String(item["prototype_id"])] = true
            edge_total += _distance_to_polygon_edge(point, forest.polygon)
            var meta := catalog.get_metadata(String(item["prototype_id"]))
            var scale := transform.basis.get_scale().x
            _expect(scale >= float(meta["population_scale_min"]) - 0.001, "Dressing scale must respect prototype metadata")
            _expect(scale <= float(meta["population_scale_max"]) + 0.001, "Dressing scale must respect prototype metadata")
        edge_means[decoration.decoration_type] = edge_total / float(decoration.instances.size())
        if decoration.instances.size() >= 8 and decoration.decoration_type != "dead_tree":
            _expect(used_prototypes.size() > 1, "Seeded dressing should use multiple %s variants" % decoration.decoration_type)

    _expect(int(counts["grass"]) > int(counts["bush"]), "Grass budget must exceed bush budget")
    _expect(int(counts["bush"]) > int(counts["rock"]), "Bush budget must exceed rock budget")
    _expect(int(counts["rock"]) > int(counts["dead_tree"]), "Rock budget must exceed dead-tree accents")
    _expect(float(edge_means["grass"]) < float(edge_means["dead_tree"]), "Grass should bias toward forest edges")
    _expect(float(edge_means["bush"]) < float(edge_means["dead_tree"]), "Bushes should bias toward forest edges")

func _test_determinism(first: ResolvedWorld, second: ResolvedWorld) -> void:
    _expect(first.decorations.size() == second.decorations.size(), "Dressing layer count must be deterministic")
    for layer_index in range(first.decorations.size()):
        var a: ResolvedDecoration = first.decorations[layer_index]
        var b: ResolvedDecoration = second.decorations[layer_index]
        _expect(a.id == b.id and a.decoration_type == b.decoration_type, "Dressing layer identity must be deterministic")
        _expect(a.instances.size() == b.instances.size(), "Dressing instance count must be deterministic")
        for instance_index in range(a.instances.size()):
            var item_a: Dictionary = a.instances[instance_index]
            var item_b: Dictionary = b.instances[instance_index]
            _expect(item_a["prototype_id"] == item_b["prototype_id"], "Dressing prototype choice must be deterministic")
            _expect((item_a["transform"] as Transform3D).is_equal_approx(item_b["transform"] as Transform3D), "Dressing transform must be deterministic")

func _test_area_scaling(catalog: PrototypeCatalog) -> void:
    var small := _lower_bound_forest(catalog, 36.0, 2024)
    var large := _lower_bound_forest(catalog, 72.0, 2024)
    _expect(small.errors.is_empty() and large.errors.is_empty(), "Bound forests must dress without semantic errors")
    var small_counts := _decoration_counts(small)
    var large_counts := _decoration_counts(large)
    _expect(int(small_counts.get("grass", 0)) < int(large_counts.get("grass", 0)), "Grass dressing must scale with resolved forest area")
    _expect(int(small_counts.get("bush", 0)) < int(large_counts.get("bush", 0)), "Bush dressing must scale with resolved forest area")
    _expect(int(small_counts.get("rock", 0)) < int(large_counts.get("rock", 0)), "Rock dressing must scale with resolved forest area")
    _expect(int(small_counts.get("dead_tree", 0)) == 0, "Small forests should not force a dead-tree accent")
    _expect(int(large_counts.get("dead_tree", 0)) > 0, "Large forests may receive rare dead-tree accents")

func _test_semantic_occupancy_and_road_clearance(catalog: PrototypeCatalog) -> void:
    var ir := {
        "regions": [{"id": "forest", "type": "forest"}],
        "networks": [{
            "id": "main_road",
            "type": "road",
            "topology": {"from": "south", "to": "north"},
            "placement": {"relations": [{"type": "inside", "target": "forest"}]},
        }],
        "entities": [{
            "id": "church",
            "type": "church",
            "placement": {"relations": [
                {"type": "inside", "target": "forest"},
                {"type": "near", "target": "main_road"},
            ]},
        }],
        "distributions": [
            {
                "id": "trees",
                "type": "tree",
                "placement": {"relations": [{"type": "inside", "target": "forest"}]},
                "population": {"amount": {"mode": "count", "value": 24}},
            },
            {
                "id": "houses",
                "type": "house",
                "placement": {"relations": [
                    {"type": "inside", "target": "forest"},
                    {"type": "along", "target": "main_road"},
                ]},
                "population": {"amount": {"mode": "count", "value": 4}},
            },
        ],
    }
    var bindings := [{"ir_object_id": "forest", "runtime_fact_id": "forest_area", "placement": "inside"}]
    var payloads := {"forest_area": {"aabb2": {"x": -36.0, "z": -36.0, "w": 72.0, "d": 72.0}}}
    var world := WorldBackend.new().lower(ir, catalog, 9001, bindings, payloads)
    _expect(world.errors.is_empty(), "Crowded forest semantics must resolve before dressing")
    if not world.errors.is_empty():
        return
    var semantic_occupancy := _semantic_occupancy(world, catalog)
    var decoration_occupancy: Array = []
    for decoration: ResolvedDecoration in world.decorations:
        var rule: Dictionary = ForestDresser.RULES[decoration.decoration_type]
        for item in decoration.instances:
            var transform: Transform3D = item["transform"]
            var point := Vector2(transform.origin.x, transform.origin.z)
            var radius := float(item["occupancy_radius"])
            for occupied in semantic_occupancy:
                _expect(point.distance_to(occupied["position"]) + 0.001 >= radius + float(occupied["radius"]), "Dressing must not overlap explicit semantic occupancy")
            for occupied in decoration_occupancy:
                _expect(point.distance_to(occupied["position"]) + 0.001 >= radius + float(occupied["radius"]), "Dressing layers must share one occupancy system")
            for network: ResolvedNetwork in world.networks:
                var nearest := PlacementSolver.new().nearest_point_on_network(point, network)
                _expect(point.distance_to(nearest) + 0.001 >= network.width * 0.5 + radius + float(rule["road_clearance"]), "Dressing must not intrude into a road")
            decoration_occupancy.append({"position": point, "radius": radius})

func _test_no_forest(catalog: PrototypeCatalog) -> void:
    var ir := {
        "regions": [{"id": "town", "type": "town", "placement": {"anchor": "center"}}],
        "networks": [], "entities": [], "distributions": [],
    }
    var world := WorldBackend.new().lower(ir, catalog, 1337)
    _expect(world.errors.is_empty(), "World without forest must still lower")
    _expect(world.decorations.is_empty(), "World without forest must not receive forest dressing")

func _test_runtime(world: ResolvedWorld, catalog: PrototypeCatalog) -> void:
    var runtime := SceneRuntime.new()
    var candidate := runtime.build_candidate(world, catalog)
    _expect(candidate != null, "SceneRuntime must instantiate forest dressing")
    if candidate != null:
        var root_node := candidate.get_node_or_null("Decorations") as Node3D
        _expect(root_node != null and root_node.get_child_count() == world.decorations.size(), "Runtime must preserve dressing layer groups")
        var expected_instances := 0
        for decoration in world.decorations:
            expected_instances += decoration.instances.size()
        _expect(root_node.find_children("*", "WorldPrototype", true, false).size() == expected_instances, "Runtime must instantiate every resolved dressing instance")
        candidate.free()
    runtime.free()

func _semantic_occupancy(world: ResolvedWorld, catalog: PrototypeCatalog) -> Array:
    var result: Array = []
    for entity: ResolvedEntity in world.entities:
        var meta := catalog.get_metadata(entity.prototype_id)
        result.append({
            "position": Vector2(entity.transform.origin.x, entity.transform.origin.z),
            "radius": float(meta["placement_radius"]) + float(meta["clearance"]),
        })
    for distribution: ResolvedDistribution in world.distributions:
        var radius := 0.0
        for prototype_id in catalog.get_prototype_ids(distribution.semantic_type):
            radius = maxf(radius, float(catalog.get_metadata(prototype_id)["population_occupancy_radius"]))
        for item in distribution.instances:
            var transform: Transform3D = item["transform"]
            result.append({"position": Vector2(transform.origin.x, transform.origin.z), "radius": radius})
    return result

func _lower_bound_forest(catalog: PrototypeCatalog, size: float, seed_value: int) -> ResolvedWorld:
    var ir := {
        "regions": [{"id": "forest", "type": "forest"}],
        "networks": [], "entities": [], "distributions": [],
    }
    var bindings := [{"ir_object_id": "forest", "runtime_fact_id": "forest_area", "placement": "inside"}]
    var payloads := {"forest_area": {"aabb2": {"x": -size * 0.5, "z": -size * 0.5, "w": size, "d": size}}}
    return WorldBackend.new().lower(ir, catalog, seed_value, bindings, payloads)

func _decoration_counts(world: ResolvedWorld) -> Dictionary:
    var result := {}
    for decoration: ResolvedDecoration in world.decorations:
        result[decoration.decoration_type] = decoration.instances.size()
    return result

func _polygon_area(polygon: PackedVector2Array) -> float:
    var twice_area := 0.0
    for index in range(polygon.size()):
        var a := polygon[index]
        var b := polygon[(index + 1) % polygon.size()]
        twice_area += a.x * b.y - b.x * a.y
    return absf(twice_area) * 0.5

func _distance_to_polygon_edge(point: Vector2, polygon: PackedVector2Array) -> float:
    var result := INF
    for index in range(polygon.size()):
        var closest := Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])
        result = minf(result, point.distance_to(closest))
    return result

func _load_json(path: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    _expect(typeof(parsed) == TYPE_DICTIONARY, "Fixture must contain a JSON object")
    return parsed as Dictionary

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    failures += 1
    push_error(message)
