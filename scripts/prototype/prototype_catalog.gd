class_name PrototypeCatalog
extends Node

const PROTOTYPES := {
    "tree_01": "res://assets/prototypes/nature/tree_01.tscn",
    "tree_02": "res://assets/prototypes/nature/tree_02.tscn",
    "tree_03": "res://assets/prototypes/nature/tree_03.tscn",
    "tree_04": "res://assets/prototypes/nature/tree_04.tscn",
    "tree_05": "res://assets/prototypes/nature/tree_05.tscn",
    "tree_06": "res://assets/prototypes/nature/tree_06.tscn",
    "house_01": "res://assets/prototypes/buildings/house_01.tscn",
    "house_02": "res://assets/prototypes/buildings/house_02.tscn",
    "church_01": "res://assets/prototypes/buildings/church_01.tscn",
    "tombstone_01": "res://assets/prototypes/tombstone_01.tscn",
}

const SEMANTIC_TYPES := {
    "tree": [
        "tree_01",
        "tree_02",
        "tree_03",
        "tree_04",
        "tree_05",
        "tree_06",
    ],
    "house": ["house_01", "house_02"],
    "church": ["church_01"],
    "tombstone": ["tombstone_01"],
}

var _scene_cache: Dictionary = {}
var _metadata_cache: Dictionary = {}

func choose_prototype(semantic_type: String, rng: RandomNumberGenerator = null) -> String:
    var options: Array = SEMANTIC_TYPES.get(semantic_type, [])
    if options.is_empty():
        return ""
    if rng != null and options.size() > 1:
        return String(options[rng.randi_range(0, options.size() - 1)])
    return String(options[0])

func get_prototype_ids(semantic_type: String) -> Array[String]:
    var result: Array[String] = []
    for prototype_id in SEMANTIC_TYPES.get(semantic_type, []):
        result.append(String(prototype_id))
    return result

func get_scene(prototype_id: String) -> PackedScene:
    if _scene_cache.has(prototype_id):
        return _scene_cache[prototype_id]
    var path: String = PROTOTYPES.get(prototype_id, "")
    if path.is_empty():
        return null
    var scene := load(path) as PackedScene
    if scene != null:
        _scene_cache[prototype_id] = scene
    return scene

func get_metadata(prototype_id: String) -> Dictionary:
    if _metadata_cache.has(prototype_id):
        return _metadata_cache[prototype_id]
    var scene := get_scene(prototype_id)
    if scene == null:
        return {}
    var instance := scene.instantiate() as WorldPrototype
    if instance == null:
        return {}
    var measured := _measure_footprints(instance)
    var visual_footprint: Vector2 = measured.get("visual", Vector2.ZERO)
    var collision_footprint: Vector2 = measured.get("collision", Vector2.ZERO)
    var fallback_size := Vector2.ONE * instance.placement_radius * 2.0
    if visual_footprint.x <= 0.0 or visual_footprint.y <= 0.0:
        visual_footprint = fallback_size
    if collision_footprint.x <= 0.0 or collision_footprint.y <= 0.0:
        collision_footprint = fallback_size
    var population_footprint := visual_footprint
    if instance.population_footprint_override.x > 0.0 and instance.population_footprint_override.y > 0.0:
        population_footprint = instance.population_footprint_override
    var collision_radius := collision_footprint.length() * 0.5
    var population_occupancy_radius := maxf(
        0.1,
        (collision_radius + instance.clearance) * instance.population_occupancy_scale
    )
    var meta := {
        "prototype_id": prototype_id,
        "semantic_type": instance.semantic_type,
        "placement_radius": instance.placement_radius,
        "clearance": instance.clearance,
        "visual_footprint": visual_footprint,
        "collision_footprint": collision_footprint,
        "population_footprint": population_footprint,
        "population_spacing": instance.population_spacing,
        "population_occupancy_radius": population_occupancy_radius,
        "population_scale_min": instance.population_scale_min,
        "population_scale_max": instance.population_scale_max,
        "population_landmark_chance": instance.population_landmark_chance,
        "population_landmark_scale": instance.population_landmark_scale,
        "roadside_setback": instance.roadside_setback,
        "roadside_yaw_jitter_degrees": instance.roadside_yaw_jitter_degrees,
    }
    instance.free()
    _metadata_cache[prototype_id] = meta
    return meta

func has_semantic_type(semantic_type: String) -> bool:
    return SEMANTIC_TYPES.has(semantic_type)

func _measure_footprints(root: Node3D) -> Dictionary:
    var visual_bounds := {"has_value": false, "minimum": Vector2.ZERO, "maximum": Vector2.ZERO}
    var collision_bounds := {"has_value": false, "minimum": Vector2.ZERO, "maximum": Vector2.ZERO}
    _collect_footprints(root, Transform3D.IDENTITY, visual_bounds, collision_bounds)
    return {
        "visual": _bounds_size(visual_bounds),
        "collision": _bounds_size(collision_bounds),
    }

func _collect_footprints(
    node: Node,
    transform_to_root: Transform3D,
    visual_bounds: Dictionary,
    collision_bounds: Dictionary
) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh != null:
            _include_aabb(visual_bounds, mesh_instance.mesh.get_aabb(), transform_to_root)
    elif node is CollisionShape3D:
        var collision_shape := node as CollisionShape3D
        if not collision_shape.disabled and collision_shape.shape != null:
            var shape_aabb := _shape_aabb(collision_shape.shape)
            if shape_aabb.size.x > 0.0 and shape_aabb.size.z > 0.0:
                _include_aabb(collision_bounds, shape_aabb, transform_to_root)

    for child in node.get_children():
        var child_transform := transform_to_root
        if child is Node3D:
            child_transform = transform_to_root * (child as Node3D).transform
        _collect_footprints(child, child_transform, visual_bounds, collision_bounds)

func _shape_aabb(shape: Shape3D) -> AABB:
    if shape is BoxShape3D:
        var size := (shape as BoxShape3D).size
        return AABB(-size * 0.5, size)
    if shape is SphereShape3D:
        var diameter := (shape as SphereShape3D).radius * 2.0
        var size := Vector3.ONE * diameter
        return AABB(-size * 0.5, size)
    if shape is CapsuleShape3D:
        var capsule := shape as CapsuleShape3D
        var size := Vector3(capsule.radius * 2.0, capsule.height, capsule.radius * 2.0)
        return AABB(-size * 0.5, size)
    if shape is CylinderShape3D:
        var cylinder := shape as CylinderShape3D
        var size := Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
        return AABB(-size * 0.5, size)
    var debug_mesh := shape.get_debug_mesh()
    return AABB() if debug_mesh == null else debug_mesh.get_aabb()

func _include_aabb(bounds: Dictionary, aabb: AABB, transform_to_root: Transform3D) -> void:
    for x in [aabb.position.x, aabb.end.x]:
        for y in [aabb.position.y, aabb.end.y]:
            for z in [aabb.position.z, aabb.end.z]:
                var point := transform_to_root * Vector3(float(x), float(y), float(z))
                var point_xz := Vector2(point.x, point.z)
                if not bool(bounds["has_value"]):
                    bounds["has_value"] = true
                    bounds["minimum"] = point_xz
                    bounds["maximum"] = point_xz
                else:
                    bounds["minimum"] = (bounds["minimum"] as Vector2).min(point_xz)
                    bounds["maximum"] = (bounds["maximum"] as Vector2).max(point_xz)

func _bounds_size(bounds: Dictionary) -> Vector2:
    if not bool(bounds["has_value"]):
        return Vector2.ZERO
    return (bounds["maximum"] as Vector2) - (bounds["minimum"] as Vector2)
