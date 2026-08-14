class_name PrototypeCatalog
extends Node

const PROTOTYPES := {
    "tree_01": "res://assets/prototypes/tree_01.tscn",
    "house_01": "res://assets/prototypes/house_01.tscn",
    "church_01": "res://assets/prototypes/church_01.tscn",
    "tombstone_01": "res://assets/prototypes/tombstone_01.tscn",
}

const SEMANTIC_TYPES := {
    "tree": ["tree_01"],
    "house": ["house_01"],
    "church": ["church_01"],
    "tombstone": ["tombstone_01"],
}

var _scene_cache: Dictionary = {}
var _metadata_cache: Dictionary = {}

func choose_prototype(semantic_type: String, _rng: RandomNumberGenerator = null) -> String:
    var options: Array = SEMANTIC_TYPES.get(semantic_type, [])
    if options.is_empty():
        return ""
    return String(options[0])

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
    var instance := scene.instantiate()
    var meta := {
        "prototype_id": prototype_id,
        "semantic_type": String(instance.get("semantic_type")),
        "placement_radius": float(instance.get("placement_radius")),
        "clearance": float(instance.get("clearance")),
    }
    instance.free()
    _metadata_cache[prototype_id] = meta
    return meta

func has_semantic_type(semantic_type: String) -> bool:
    return SEMANTIC_TYPES.has(semantic_type)
