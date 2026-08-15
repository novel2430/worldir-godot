class_name SceneTransition
extends RefCounted

const ADD_VEGETATION_DURATION := 0.62
const ADD_BUILDING_DURATION := 0.78
const ADD_SMALL_DURATION := 0.44
const REMOVE_DURATION := 0.58
const MOVE_DURATION := 0.76
const REPLACE_DURATION := 0.64
const STATIC_REPLACE_DURATION := 0.58
const RIPPLE_DURATION := 0.82
const STAGGER_WINDOW := 0.34
const TERRAIN_SWAP_DELAY := 0.34
const COMPLETE_PADDING := 0.08

const VEGETATION_TYPES := ["tree", "bush", "grass", "dead_tree", "stump", "plant", "flower"]
const BUILDING_TYPES := ["house", "church", "tower", "lighthouse", "bridge", "radio_tower", "gas_station"]

var duration_scale := 1.0
var last_patch_summary: Dictionary = {}

func apply(
    active_root: Node3D,
    candidate: Node3D,
    patch: Dictionary,
    new_world: ResolvedWorld
) -> void:
    var changes := _collect_changes(patch)
    var spatial := _spatial_profile(changes, new_world, patch)
    var center: Vector3 = spatial.center
    var max_distance: float = spatial.max_distance
    var maximum_delay := 0.0

    last_patch_summary = {
        "change_count": changes.size(),
        "change_center": center,
        "max_stagger_delay": 0.0,
        "terrain_changed": bool(patch.get("terrain_changed", false)),
        "ripple_spawned": false,
    }

    if not changes.is_empty() or bool(patch.get("terrain_changed", false)):
        _spawn_rewrite_ripple(active_root, center, changes.size())
        last_patch_summary.ripple_spawned = true
    else:
        candidate.free()
        return

    maximum_delay = maxf(maximum_delay, _patch_changed_resources(
        active_root, candidate, "Regions", patch.regions, center, max_distance
    ))
    maximum_delay = maxf(maximum_delay, _patch_changed_resources(
        active_root, candidate, "Networks", patch.networks, center, max_distance
    ))
    maximum_delay = maxf(maximum_delay, _patch_changed_resources(
        active_root, candidate, "Water", patch.waters, center, max_distance
    ))
    maximum_delay = maxf(maximum_delay, _patch_transformables(
        active_root, candidate, "Entities", patch.entities, center, max_distance
    ))
    maximum_delay = maxf(maximum_delay, _patch_transformables(
        active_root,
        candidate,
        "Distributions",
        patch.distribution_instances,
        center,
        max_distance
    ))
    maximum_delay = maxf(maximum_delay, _patch_transformables(
        active_root,
        candidate,
        "Decorations",
        patch.decoration_instances,
        center,
        max_distance
    ))

    if bool(patch.get("terrain_changed", false)):
        _schedule_terrain_swap(active_root, candidate)

    last_patch_summary.max_stagger_delay = maximum_delay
    _schedule_empty_group_cleanup(active_root)
    candidate.free()

    var total := maxf(
        RIPPLE_DURATION,
        maximum_delay + maxf(ADD_BUILDING_DURATION, maxf(MOVE_DURATION, REMOVE_DURATION))
    ) * duration_scale + COMPLETE_PADDING
    if active_root.is_inside_tree() and duration_scale > 0.0:
        await active_root.get_tree().create_timer(total).timeout

func _patch_changed_resources(
    active_root: Node3D,
    candidate: Node3D,
    layer_name: String,
    bucket: Dictionary,
    center: Vector3,
    max_distance: float
) -> float:
    var maximum_delay := 0.0
    for record: Dictionary in bucket.get("removed", []):
        var node := _find_object_node(active_root, layer_name, record)
        if node == null:
            continue
        var delay := _delay_for(record, center, max_distance)
        maximum_delay = maxf(maximum_delay, delay)
        _animate_static_remove(node, delay)
    for record: Dictionary in bucket.get("added", []):
        var new_node := _take_candidate_node(candidate, layer_name, record)
        if new_node == null:
            continue
        var parent := _target_parent(active_root, layer_name, record)
        parent.add_child(new_node)
        var delay := _delay_for(record, center, max_distance)
        maximum_delay = maxf(maximum_delay, delay)
        _animate_static_add(new_node, delay)
    for record: Dictionary in bucket.get("changed", []):
        var old_node := _find_object_node(active_root, layer_name, record)
        var new_node := _take_candidate_node(candidate, layer_name, record)
        if new_node == null:
            continue
        var parent := _target_parent(active_root, layer_name, record)
        var delay := _delay_for(record, center, max_distance)
        maximum_delay = maxf(maximum_delay, delay)
        _crossfade_static_replace(old_node, new_node, parent, delay)
    return maximum_delay

func _patch_transformables(
    active_root: Node3D,
    candidate: Node3D,
    layer_name: String,
    bucket: Dictionary,
    center: Vector3,
    max_distance: float
) -> float:
    var maximum_delay := 0.0
    for record: Dictionary in bucket.get("removed", []):
        var node := _find_object_node(active_root, layer_name, record)
        if node == null:
            continue
        var delay := _delay_for(record, center, max_distance)
        maximum_delay = maxf(maximum_delay, delay)
        _animate_remove(node, String(record.get("semantic_type", "")), delay)
    for record: Dictionary in bucket.get("added", []):
        var new_node := _take_candidate_node(candidate, layer_name, record)
        if new_node == null:
            continue
        _target_parent(active_root, layer_name, record).add_child(new_node)
        var delay := _delay_for(record, center, max_distance)
        maximum_delay = maxf(maximum_delay, delay)
        _animate_add(new_node, String(record.get("semantic_type", "")), delay)
    for record: Dictionary in bucket.get("moved", []):
        var node := _find_object_node(active_root, layer_name, record)
        if node == null:
            continue
        var delay := _delay_for(record, center, max_distance)
        maximum_delay = maxf(maximum_delay, delay)
        _animate_move(
            node,
            _value_transform(record.get("new")),
            String(record.get("semantic_type", "")),
            delay
        )
    for record: Dictionary in bucket.get("replaced", []):
        var old_node := _find_object_node(active_root, layer_name, record)
        var new_node := _take_candidate_node(candidate, layer_name, record)
        if new_node == null:
            continue
        var delay := _delay_for(record, center, max_distance)
        maximum_delay = maxf(maximum_delay, delay)
        _crossfade_replace(
            old_node,
            new_node,
            _target_parent(active_root, layer_name, record),
            String(record.get("semantic_type", "")),
            delay
        )
    return maximum_delay

func _animate_add(node: Node3D, semantic_type: String, delay: float) -> void:
    var target := node.transform
    var profile := _add_profile(semantic_type)
    var start := target
    start.basis = target.basis.scaled(Vector3.ONE * float(profile.scale))
    start.origin.y -= float(profile.sink)
    node.transform = start
    _set_visual_transparency(node, 1.0)
    _set_collision_enabled(node, false)

    var tween := node.create_tween().set_parallel(true)
    tween.tween_property(
        node,
        "transform",
        target,
        float(profile.duration) * duration_scale
    ).set_delay(delay * duration_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    _tween_visual_transparency(
        tween,
        node,
        0.0,
        float(profile.duration) * duration_scale,
        delay * duration_scale
    )
    var lifecycle := node.create_tween()
    lifecycle.tween_interval((delay + float(profile.duration)) * duration_scale)
    lifecycle.tween_callback(_set_collision_enabled.bind(node, true))

func _animate_remove(node: Node3D, _semantic_type: String, delay: float) -> void:
    var target := node.transform
    target.basis = node.transform.basis.scaled(Vector3.ONE * 0.65)
    target.origin.y -= 0.42
    var actual_delay := delay * duration_scale
    var actual_duration := REMOVE_DURATION * duration_scale
    var lifecycle := node.create_tween()
    lifecycle.tween_interval(actual_delay)
    lifecycle.tween_callback(_set_collision_enabled.bind(node, false))

    var tween := node.create_tween().set_parallel(true)
    tween.tween_property(node, "transform", target, actual_duration).set_delay(actual_delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    _tween_visual_transparency(tween, node, 1.0, actual_duration, actual_delay)
    var cleanup := node.create_tween()
    cleanup.tween_interval(actual_delay + actual_duration)
    cleanup.tween_callback(node.queue_free)

func _animate_move(
    node: Node3D,
    target: Transform3D,
    semantic_type: String,
    delay: float
) -> void:
    var source := node.transform
    var lift := 0.42 if semantic_type in BUILDING_TYPES else 0.12
    var tween := node.create_tween()
    tween.tween_interval(delay * duration_scale)
    tween.tween_method(
        _apply_move.bind(node, source, target, lift),
        0.0,
        1.0,
        MOVE_DURATION * duration_scale
    ).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _apply_move(
    weight: float,
    node: Node3D,
    source: Transform3D,
    target: Transform3D,
    lift: float
) -> void:
    if not is_instance_valid(node):
        return
    var value := source.interpolate_with(target, weight)
    value.origin.y += sin(weight * PI) * lift
    node.transform = value

func _animate_static_add(node: Node3D, delay: float) -> void:
    _set_visual_transparency(node, 1.0)
    _set_collision_enabled(node, false)
    var actual_delay := delay * duration_scale
    var actual_duration := STATIC_REPLACE_DURATION * duration_scale
    var tween := node.create_tween().set_parallel(true)
    _tween_visual_transparency(tween, node, 0.0, actual_duration, actual_delay)
    var lifecycle := node.create_tween()
    lifecycle.tween_interval(actual_delay + actual_duration)
    lifecycle.tween_callback(_set_collision_enabled.bind(node, true))

func _animate_static_remove(node: Node3D, delay: float) -> void:
    var actual_delay := delay * duration_scale
    var actual_duration := STATIC_REPLACE_DURATION * duration_scale
    var lifecycle := node.create_tween()
    lifecycle.tween_interval(actual_delay)
    lifecycle.tween_callback(_set_collision_enabled.bind(node, false))
    var tween := node.create_tween().set_parallel(true)
    _tween_visual_transparency(tween, node, 1.0, actual_duration, actual_delay)
    var cleanup := node.create_tween()
    cleanup.tween_interval(actual_delay + actual_duration)
    cleanup.tween_callback(node.queue_free)

func _crossfade_static_replace(
    old_node: Node3D,
    new_node: Node3D,
    parent: Node,
    delay: float
) -> void:
    if old_node != null:
        old_node.name = "__rewrite_old_%s" % old_node.name
        _animate_static_remove(old_node, delay)
    parent.add_child(new_node)
    _animate_static_add(new_node, delay + STATIC_REPLACE_DURATION * 0.16)

func _crossfade_replace(
    old_node: Node3D,
    new_node: Node3D,
    parent: Node,
    semantic_type: String,
    delay: float
) -> void:
    if old_node != null:
        old_node.name = "__rewrite_old_%s" % old_node.name
        _animate_remove(old_node, semantic_type, delay)
    parent.add_child(new_node)
    _animate_add(new_node, semantic_type, delay + REPLACE_DURATION * 0.18)

func _schedule_terrain_swap(active_root: Node3D, candidate: Node3D) -> void:
    var old_terrain := active_root.get_node_or_null("Terrain/WorldSurface") as Node3D
    var new_terrain := candidate.get_node_or_null("Terrain/WorldSurface") as Node3D
    if new_terrain != null:
        new_terrain.get_parent().remove_child(new_terrain)
    var delay := TERRAIN_SWAP_DELAY * duration_scale
    var tween := active_root.create_tween()
    tween.tween_interval(delay)
    tween.tween_callback(_swap_terrain.bind(active_root, old_terrain, new_terrain))

func _swap_terrain(active_root: Node3D, old_terrain: Node3D, new_terrain: Node3D) -> void:
    if is_instance_valid(old_terrain):
        old_terrain.free()
    if is_instance_valid(new_terrain):
        var layer := active_root.get_node_or_null("Terrain")
        if layer != null:
            layer.add_child(new_terrain)

func _spawn_rewrite_ripple(active_root: Node3D, center: Vector3, change_count: int) -> void:
    var effects := active_root.get_node_or_null("Effects") as Node3D
    if effects == null:
        effects = Node3D.new()
        effects.name = "Effects"
        active_root.add_child(effects)
    var ripple := MeshInstance3D.new()
    ripple.name = "RewriteRipple"
    var torus := TorusMesh.new()
    torus.inner_radius = 0.90
    torus.outer_radius = 1.0
    torus.rings = 32
    torus.ring_segments = 6
    ripple.mesh = torus
    ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material := StandardMaterial3D.new()
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(0.46, 0.78, 0.72, 0.20)
    material.emission_enabled = true
    material.emission = Color(0.25, 0.58, 0.54)
    material.emission_energy_multiplier = 0.32
    ripple.material_override = material
    ripple.position = center + Vector3.UP * 0.16
    ripple.scale = Vector3(0.35, 0.16, 0.35)
    ripple.transparency = 0.28
    effects.add_child(ripple)

    var radius := clampf(5.5 + sqrt(float(maxi(change_count, 1))) * 0.85, 6.0, 14.0)
    var tween := ripple.create_tween().set_parallel(true)
    tween.tween_property(
        ripple,
        "scale",
        Vector3(radius, 0.08, radius),
        RIPPLE_DURATION * duration_scale
    ).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(
        ripple,
        "transparency",
        1.0,
        RIPPLE_DURATION * duration_scale
    ).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    var cleanup := ripple.create_tween()
    cleanup.tween_interval(RIPPLE_DURATION * duration_scale)
    cleanup.tween_callback(ripple.queue_free)

func _collect_changes(patch: Dictionary) -> Array:
    var result: Array = []
    for bucket_name in ["regions", "networks", "waters"]:
        var bucket: Dictionary = patch.get(bucket_name, {})
        for category in ["added", "removed", "changed"]:
            result.append_array(bucket.get(category, []))
    for bucket_name in ["entities", "distribution_instances", "decoration_instances"]:
        var bucket: Dictionary = patch.get(bucket_name, {})
        for category in ["added", "removed", "moved", "replaced"]:
            result.append_array(bucket.get(category, []))
    return result

func _spatial_profile(
    changes: Array,
    new_world: ResolvedWorld,
    patch: Dictionary
) -> Dictionary:
    var points: Array[Vector3] = []
    for record: Dictionary in changes:
        points.append(_record_position(record))
    var center := Vector3.ZERO
    if points.is_empty():
        center = _terrain_dirty_center(patch.get("terrain", {}), new_world.world_bounds)
    else:
        for point in points:
            center += point
        center /= float(points.size())
    if new_world.terrain != null:
        center.y = new_world.terrain.sample_height(Vector2(center.x, center.z))
    var max_distance := 0.0
    for point in points:
        max_distance = maxf(max_distance, _planar_distance(point, center))
    return {"center": center, "max_distance": max_distance}

func _terrain_dirty_center(terrain_patch: Dictionary, fallback_bounds: Rect2) -> Vector3:
    var old_terrain: Resource = terrain_patch.get("old")
    var new_terrain: Resource = terrain_patch.get("new")
    if (
        old_terrain == null
        or new_terrain == null
        or old_terrain.grid_size != new_terrain.grid_size
        or old_terrain.grid_size < 2
        or not old_terrain.world_bounds.is_equal_approx(new_terrain.world_bounds)
    ):
        var fallback := fallback_bounds.get_center()
        return Vector3(fallback.x, 0.0, fallback.y)
    var center := Vector2.ZERO
    var count := 0
    var grid_size: int = new_terrain.grid_size
    var bounds: Rect2 = new_terrain.world_bounds
    for index in range(grid_size * grid_size):
        var changed := (
            absf(float(old_terrain.heights[index]) - float(new_terrain.heights[index])) > 0.001
            or not (old_terrain.surface_masks[index] as Color).is_equal_approx(
                new_terrain.surface_masks[index]
            )
            or absf(
                float(old_terrain.shore_wetness[index])
                - float(new_terrain.shore_wetness[index])
            ) > 0.001
        )
        if not changed:
            continue
        var x_index := index % grid_size
        var z_index := floori(float(index) / float(grid_size))
        center += Vector2(
            lerpf(bounds.position.x, bounds.end.x, float(x_index) / float(grid_size - 1)),
            lerpf(bounds.position.y, bounds.end.y, float(z_index) / float(grid_size - 1))
        )
        count += 1
    if count == 0:
        center = bounds.get_center()
    else:
        center /= float(count)
    return Vector3(center.x, 0.0, center.y)

func _delay_for(record: Dictionary, center: Vector3, max_distance: float) -> float:
    if max_distance <= 0.001:
        return 0.0
    return clampf(
        _planar_distance(_record_position(record), center) / max_distance,
        0.0,
        1.0
    ) * STAGGER_WINDOW

func _record_position(record: Dictionary) -> Vector3:
    var value: Variant = record.get("new")
    if value == null:
        value = record.get("old")
    if value is ResolvedEntity:
        return value.transform.origin
    if value is ResolvedRegion:
        return _polygon_center(value.polygon)
    if value is ResolvedNetwork:
        return _curve_center(value.curve_points)
    if value is ResolvedWater:
        return _polygon_center(value.shoreline)
    if typeof(value) == TYPE_DICTIONARY:
        return ((value as Dictionary).get("transform", Transform3D.IDENTITY) as Transform3D).origin
    return Vector3.ZERO

func _polygon_center(polygon: PackedVector2Array) -> Vector3:
    if polygon.is_empty():
        return Vector3.ZERO
    var center := Vector2.ZERO
    for point in polygon:
        center += point
    center /= float(polygon.size())
    return Vector3(center.x, 0.0, center.y)

func _curve_center(points: PackedVector3Array) -> Vector3:
    if points.is_empty():
        return Vector3.ZERO
    var center := Vector3.ZERO
    for point in points:
        center += point
    return center / float(points.size())

func _planar_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _add_profile(semantic_type: String) -> Dictionary:
    if semantic_type in VEGETATION_TYPES:
        return {"scale": 0.10, "sink": 0.34, "duration": ADD_VEGETATION_DURATION}
    if semantic_type in BUILDING_TYPES:
        return {"scale": 0.85, "sink": 0.62, "duration": ADD_BUILDING_DURATION}
    return {"scale": 0.35, "sink": 0.16, "duration": ADD_SMALL_DURATION}

func _find_object_node(root: Node3D, layer_name: String, record: Dictionary) -> Node3D:
    return root.get_node_or_null(_object_path(layer_name, record)) as Node3D

func _take_candidate_node(candidate: Node3D, layer_name: String, record: Dictionary) -> Node3D:
    var node := candidate.get_node_or_null(_object_path(layer_name, record)) as Node3D
    if node != null:
        node.get_parent().remove_child(node)
    return node

func _target_parent(root: Node3D, layer_name: String, record: Dictionary) -> Node:
    var layer := root.get_node(layer_name)
    var owner_id := String(record.get("owner_id", ""))
    if owner_id.is_empty():
        return layer
    var group_name := _safe_name(owner_id)
    var group := layer.get_node_or_null(group_name)
    if group == null:
        group = Node3D.new()
        group.name = group_name
        layer.add_child(group)
    return group

func _object_path(layer_name: String, record: Dictionary) -> NodePath:
    var owner_id := String(record.get("owner_id", ""))
    var object_name := _safe_name(String(record.get("id", "")))
    if owner_id.is_empty():
        return NodePath("%s/%s" % [layer_name, object_name])
    return NodePath("%s/%s/%s" % [layer_name, _safe_name(owner_id), object_name])

func _value_transform(value: Variant) -> Transform3D:
    if value is ResolvedEntity:
        return value.transform
    if typeof(value) == TYPE_DICTIONARY:
        return (value as Dictionary).get("transform", Transform3D.IDENTITY)
    return Transform3D.IDENTITY

func _set_visual_transparency(root: Node, value: float) -> void:
    for geometry in _geometry_instances(root):
        geometry.transparency = value

func _tween_visual_transparency(
    tween: Tween,
    root: Node,
    target: float,
    duration: float,
    delay: float
) -> void:
    for geometry in _geometry_instances(root):
        tween.tween_property(geometry, "transparency", target, duration).set_delay(delay)

func _geometry_instances(root: Node) -> Array[GeometryInstance3D]:
    var result: Array[GeometryInstance3D] = []
    if root is GeometryInstance3D:
        result.append(root)
    for child in root.get_children():
        result.append_array(_geometry_instances(child))
    return result

func _set_collision_enabled(root: Node, enabled: bool) -> void:
    if not is_instance_valid(root):
        return
    if root is CollisionShape3D:
        root.set_deferred("disabled", not enabled)
    for child in root.get_children():
        _set_collision_enabled(child, enabled)

func _schedule_empty_group_cleanup(active_root: Node3D) -> void:
    var tween := active_root.create_tween()
    tween.tween_interval((STAGGER_WINDOW + REMOVE_DURATION) * duration_scale + 0.02)
    tween.tween_callback(_cleanup_empty_groups.bind(active_root))

func _cleanup_empty_groups(active_root: Node3D) -> void:
    for layer_name in ["Distributions", "Decorations"]:
        var layer := active_root.get_node_or_null(layer_name)
        if layer == null:
            continue
        for group in layer.get_children():
            if group.get_child_count() == 0:
                group.queue_free()

func _safe_name(value: String) -> String:
    return value.replace(":", "_").replace("/", "_")
