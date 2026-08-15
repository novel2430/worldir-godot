class_name PrototypeCatalog
extends Node

const PROTOTYPES := {
    "tree_01": "res://assets/prototypes/nature/tree_01.tscn",
    "tree_02": "res://assets/prototypes/nature/tree_02.tscn",
    "tree_03": "res://assets/prototypes/nature/tree_03.tscn",
    "tree_04": "res://assets/prototypes/nature/tree_04.tscn",
    "tree_05": "res://assets/prototypes/nature/tree_05.tscn",
    "tree_06": "res://assets/prototypes/nature/tree_06.tscn",
    "rock_01": "res://assets/prototypes/nature/rock_01.tscn",
    "rock_02": "res://assets/prototypes/nature/rock_02.tscn",
    "rock_03": "res://assets/prototypes/nature/rock_03.tscn",
    "grass_01": "res://assets/prototypes/nature/grass_01.tscn",
    "grass_02": "res://assets/prototypes/nature/grass_02.tscn",
    "grass_03": "res://assets/prototypes/nature/grass_03.tscn",
	"oweng_crate_01": "res://assets/prototypes/oweng/entities/crate_01.tscn",
}

# Thin wrappers around the migrated OwenG source scenes. Bounds are measured
# from the source resources and kept here with the prototype policy, so lowerers
# never hardcode GLTF paths or guess placement footprints. GLTF is parsed and
# cached directly at runtime; checked-in .import sidecars are not required.
const OWENG_PROTOTYPES := {
    "oweng_tree_birch": {
        "asset_id": "tree.birch.coastal",
        "source_path": "res://assets/oweng/vegetation/trees/birch_oga/birch_oga.glb",
        "semantic_type": "tree", "license": "CC0",
        "bounds_position": Vector3(-2.954426, -0.290958, -2.949424),
        "bounds_size": Vector3(5.879683, 13.20512, 5.921411),
        "model_scale": 0.78, "scale_correction": 1.0,
        "collision_shape": "cylinder", "collision_radius": 0.34,
        "collision_height": 7.4, "placement_radius": 2.35, "clearance": 0.35,
        "population_spacing": 5.0, "population_occupancy_scale": 0.80,
        "population_scale_min": 0.86, "population_scale_max": 1.12,
        "population_landmark_chance": 0.06, "population_landmark_scale": 1.18,
    },
    "oweng_tree_pine": {
        "asset_id": "tree.conifer.pine",
        "source_path": "res://assets/oweng/vegetation/trees/pine_sapling_small/pine_sapling_small_1k.gltf",
        "semantic_type": "tree", "license": "CC0",
        "bounds_position": Vector3(-0.360306, -0.015484, -0.371376),
        "bounds_size": Vector3(2.64206, 1.298957, 0.77035),
        "model_scale": 3.8, "scale_correction": 1.0,
        "collision_shape": "cylinder", "collision_radius": 0.30,
        "collision_height": 4.2, "placement_radius": 5.1, "clearance": 0.30,
        "population_spacing": 5.0, "population_occupancy_scale": 0.82,
        "population_scale_min": 0.82, "population_scale_max": 1.10,
    },
    "oweng_tree_fir": {
        "asset_id": "tree.conifer.fir_mature",
        "source_path": "res://assets/oweng/vegetation/trees/fir_sapling_medium/fir_sapling_medium_1k.gltf",
        "semantic_type": "tree", "license": "CC0",
        "bounds_position": Vector3(-2.552252, -0.152274, -2.555667),
        "bounds_size": Vector3(14.79292, 8.890353, 5.275873),
        "model_scale": 0.82, "scale_correction": 1.0,
        "collision_shape": "cylinder", "collision_radius": 0.42,
        "collision_height": 6.8, "placement_radius": 6.3, "clearance": 0.40,
        "population_spacing": 5.0, "population_occupancy_scale": 0.85,
        "population_scale_min": 0.82, "population_scale_max": 1.08,
    },
    "oweng_grass_01": {
        "asset_id": "plant.grass.medium",
        "source_path": "res://assets/oweng/vegetation/grass/grass_medium_02/grass_medium_02_1k.gltf",
        "semantic_type": "grass", "license": "CC0",
        "bounds_position": Vector3(-0.05557, -0.00551, -0.175402),
        "bounds_size": Vector3(1.310635, 0.405314, 0.433247),
        "model_scale": 1.55, "scale_correction": 1.0,
        "placement_radius": 1.08, "clearance": 0.05,
        "population_spacing": 4.0, "population_occupancy_scale": 0.45,
        "population_scale_min": 0.72, "population_scale_max": 1.22,
    },
    "oweng_shrub_01": {
        "asset_id": "plant.shrub.01",
        "source_path": "res://assets/oweng/vegetation/bushes/shrub_01/shrub_01_1k.gltf",
        "semantic_type": "shrub", "license": "CC0",
        "bounds_position": Vector3(-1.854585, -0.008753, -0.113814),
        "bounds_size": Vector3(2.586661, 0.395974, 0.218561),
        "model_scale": 1.55, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 2.05, "clearance": 0.16,
        "population_spacing": 4.0, "population_occupancy_scale": 0.65,
        "population_scale_min": 0.74, "population_scale_max": 1.18,
    },
    "oweng_shrub_02": {
        "asset_id": "plant.shrub.02",
        "source_path": "res://assets/oweng/vegetation/bushes/shrub_02/shrub_02_1k.gltf",
        "semantic_type": "shrub", "license": "CC0",
        "bounds_position": Vector3(-2.30854, -0.606363, -1.19121),
        "bounds_size": Vector3(6.572743, 2.548073, 2.535989),
        "model_scale": 0.72, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 2.55, "clearance": 0.18,
        "population_spacing": 4.0, "population_occupancy_scale": 0.68,
        "population_scale_min": 0.72, "population_scale_max": 1.12,
    },
    "oweng_rock_07": {
        "asset_id": "rock.cold.07",
        "source_path": "res://assets/oweng/rocks/rock_07/rock_07_1k.gltf",
        "semantic_type": "rock", "license": "CC0",
        "bounds_position": Vector3(-0.08758, -0.001907, -0.177975),
        "bounds_size": Vector3(0.168882, 0.14372, 0.320277),
        "model_scale": 5.5, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 1.0, "clearance": 0.20,
        "population_spacing": 6.0, "population_occupancy_scale": 0.90,
        "population_scale_min": 0.72, "population_scale_max": 1.28,
    },
    "oweng_rock_09": {
        "asset_id": "rock.neutral.09",
        "source_path": "res://assets/oweng/rocks/rock_09/rock_09_1k.gltf",
        "semantic_type": "rock", "license": "CC0",
        "bounds_position": Vector3(-0.036733, -0.000574, -0.061063),
        "bounds_size": Vector3(0.07401, 0.032869, 0.144625),
        "model_scale": 12.0, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 0.98, "clearance": 0.18,
        "population_spacing": 6.0, "population_occupancy_scale": 0.90,
        "population_scale_min": 0.76, "population_scale_max": 1.30,
    },
    "oweng_rock_boulder": {
        "asset_id": "rock.boulder.namaqualand_04",
        "source_path": "res://assets/oweng/rocks/namaqualand_boulder_04/namaqualand_boulder_04_1k.gltf",
        "semantic_type": "rock", "license": "CC0",
        "bounds_position": Vector3(-1.340293, -0.029386, -1.031048),
        "bounds_size": Vector3(2.522153, 1.900462, 2.496422),
        "model_scale": 0.72, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 1.35, "clearance": 0.22,
        "population_spacing": 6.0, "population_occupancy_scale": 0.92,
        "population_scale_min": 0.70, "population_scale_max": 1.18,
        "population_landmark_chance": 0.08, "population_landmark_scale": 1.28,
    },
    "oweng_rowboat_weathered": {
        "asset_id": "prop.boat.rowboat",
        "source_path": "res://assets/oweng/generated/source/forest_seaside/weathered_wooden_rowboat_2712647_2.glb",
        "semantic_type": "rowboat", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-0.594274, -0.000003, -0.213742),
        "bounds_size": Vector3(1.157444, 0.342764, 0.429467),
        "model_scale": 3.9, "scale_correction": 3.9,
        "collision_shape": "box", "placement_radius": 2.45, "clearance": 0.40,
    },
    "oweng_tent_canvas": {
        "asset_id": "structure.coastal.tent",
        "source_path": "res://assets/oweng/generated/source/forest_seaside/canvas_ridge_tent.glb",
        "semantic_type": "tent", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-1.548079, -1.1, -1.705953),
        "bounds_size": Vector3(3.096159, 2.2, 3.411906),
        "model_scale": 1.0, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 2.35, "clearance": 0.55,
    },
    "oweng_cabin_coastal": {
        "asset_id": "structure.coastal.cabin",
        "source_path": "res://assets/oweng/generated/source/forest_seaside/rustic_wooden_cabin.glb",
        "semantic_type": "cabin", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-2.715938, -3.25, -3.88756),
        "bounds_size": Vector3(5.431876, 6.5, 7.77512),
        "model_scale": 1.0, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 4.75, "clearance": 0.90,
    },
    "oweng_research_station": {
        "asset_id": "structure.research.station",
        "source_path": "res://assets/oweng/generated/source/industrial/abandoned_soviet_research_station_2711371_2.glb",
        "semantic_type": "research_station", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-9.954303, -0.000311, -6.334494),
        "bounds_size": Vector3(20.07464, 20.0, 16.10388),
        "model_scale": 1.0, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 12.9, "clearance": 1.8,
    },
    "oweng_radar_tower": {
        "asset_id": "structure.research.radar",
        "source_path": "res://assets/oweng/generated/source/industrial/abandoned_radar_tower_2711741_2.glb",
        "semantic_type": "radar_tower", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-5.127048, -0.000393, -4.568861),
        "bounds_size": Vector3(10.43338, 18.0, 8.979081),
        "model_scale": 0.72, "scale_correction": 0.72,
        "collision_shape": "box", "placement_radius": 5.0, "clearance": 1.1,
    },
    "oweng_warning_sign": {
        "asset_id": "prop.research.warning_sign",
        "source_path": "res://assets/oweng/generated/source/industrial/rusted_radiation_warning_sign_2712064_2.glb",
        "semantic_type": "warning_sign", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-0.370535, -0.000001, -0.060243),
        "bounds_size": Vector3(0.739598, 1.026603, 0.101138),
        "model_scale": 2.15, "scale_correction": 2.15,
        "collision_shape": "box", "placement_radius": 0.82, "clearance": 0.28,
    },
    "oweng_cargo_truck": {
        "asset_id": "vehicle.research.cargo_truck",
        "source_path": "res://assets/oweng/generated/source/industrial/rusted_soviet_6x6_cargo_truck.glb",
        "semantic_type": "cargo_truck", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-1.457087, -1.425, -3.988246),
        "bounds_size": Vector3(2.914174, 2.85, 7.976492),
        "model_scale": 1.0, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 4.25, "clearance": 0.70,
    },
    "oweng_crate_real": {
        "asset_id": "prop.industrial.crate",
        "source_path": "res://assets/oweng/props/interactive/wooden_crate_01/wooden_crate_01_1k.gltf",
        "semantic_type": "crate", "license": "CC0",
        "bounds_position": Vector3(-0.412636, -0.007933, -0.19614),
        "bounds_size": Vector3(0.825273, 0.349618, 0.408954),
        "model_scale": 1.0, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 0.47, "clearance": 0.18,
    },
    "oweng_cabin_snow": {
        "asset_id": "structure.snow.cabin",
        "source_path": "res://assets/oweng/generated/source/snow_forest/snow_log_cabin_with_porch.glb",
        "semantic_type": "cabin", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-2.699303, -3.25, -4.009691),
        "bounds_size": Vector3(5.398605, 6.5, 8.019382),
        "model_scale": 1.0, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 4.85, "clearance": 0.90,
    },
    "oweng_maritime_memorial": {
        "asset_id": "structure.snow.maritime_memorial",
        "source_path": "res://assets/oweng/generated/source/snow_forest/snow_maritime_memorial_monument.glb",
        "semantic_type": "maritime_memorial", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-1.205898, -3.5, -1.209914),
        "bounds_size": Vector3(2.411796, 7.0, 2.419828),
        "model_scale": 1.0, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 1.75, "clearance": 0.55,
    },
    "oweng_ruined_archway": {
        "asset_id": "structure.snow.ruined_archway",
        "source_path": "res://assets/oweng/generated/source/snow_forest/snow_ruined_archway_2709821_2.glb",
        "semantic_type": "ruined_archway", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-2.968924, 0.000059, -1.332284),
        "bounds_size": Vector3(6.21031, 6.0, 2.586099),
        "model_scale": 1.0, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 3.4, "clearance": 0.70,
    },
    "oweng_bunker": {
        "asset_id": "structure.snow.bunker",
        "source_path": "res://assets/oweng/generated/source/snow_forest/snow_ruined_concrete_bunker_2709399_2.glb",
        "semantic_type": "bunker", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-2.080588, 0.000045, -2.453814),
        "bounds_size": Vector3(4.066247, 4.5, 4.552525),
        "model_scale": 1.0, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 3.05, "clearance": 0.70,
    },
    "oweng_concrete_wall": {
        "asset_id": "structure.snow.concrete_wall",
        "source_path": "res://assets/oweng/generated/source/snow_forest/snow_ruined_concrete_wall_2708823_2.glb",
        "semantic_type": "concrete_wall", "license": "user_provided_generated_asset",
        "bounds_position": Vector3(-3.311391, -0.000002, -0.714025),
        "bounds_size": Vector3(7.028622, 5.5, 1.383531),
        "model_scale": 1.0, "scale_correction": 1.0,
        "collision_shape": "box", "placement_radius": 3.60, "clearance": 0.65,
    },
}

const DISTRIBUTION_TYPES := ["tree", "grass", "shrub", "rock"]
const OWENG_VISUAL_SCALE := 1.22
const BOX_COLLISION_XZ_SCALE := 0.68
const BOX_COLLISION_Y_SCALE := 0.86
const CYLINDER_COLLISION_RADIUS_SCALE := 0.78
const TREE_POPULATION_FOOTPRINT_SCALE := 0.60

var _region_profiles := RegionProfileCatalog.new()

var _scene_cache: Dictionary = {}
var _metadata_cache: Dictionary = {}

# Parse any GLTF resources the candidate IR can select before backend lowering
# moves to a worker thread. One uncached source is prepared per frame so a new
# asset family cannot monopolize a single render frame.
func prepare_for_world_ir(world_ir: Dictionary) -> bool:
    var region_types := {}
    for region: Dictionary in world_ir.get("regions", []):
        region_types[String(region.get("id", ""))] = String(region.get("type", ""))
    var required := {}
    for collection_name in ["entities", "distributions"]:
        for item: Dictionary in world_ir.get(collection_name, []):
            var owner_id := ""
            for relation: Dictionary in item.get("placement", {}).get("relations", []):
                if String(relation.get("type", "")) == "inside":
                    owner_id = String(relation.get("target", ""))
                    break
            var owner_type := String(region_types.get(owner_id, ""))
            for prototype_id in get_prototype_ids(String(item.get("type", "")), owner_type):
                required[prototype_id] = true
    var required_ids: Array = required.keys()
    required_ids.sort()
    for prototype_id: String in required_ids:
        if _metadata_cache.has(prototype_id):
            continue
        if is_inside_tree():
            await get_tree().process_frame
        if get_metadata(prototype_id).is_empty():
            return false
    return true

func choose_prototype(
    semantic_type: String,
    owner_region_type: String,
    rng: RandomNumberGenerator = null
) -> String:
    var options := get_prototype_ids(semantic_type, owner_region_type)
    if options.is_empty():
        return ""
    if rng != null and options.size() > 1:
        return String(options[rng.randi_range(0, options.size() - 1)])
    return String(options[0])

func get_prototype_ids(
    semantic_type: String,
    owner_region_type: String
) -> Array[String]:
    var result: Array[String] = []
    var profile := _region_profiles.get_profile(owner_region_type)
    var policy_key := (
        "distribution_visual_policy"
        if semantic_type in DISTRIBUTION_TYPES
        else "entity_prototype_policy"
    )
    var policy: Dictionary = profile.get(policy_key, {})
    for raw_prototype_id in policy.get(semantic_type, []):
        var prototype_id := String(raw_prototype_id)
        if not PROTOTYPES.has(prototype_id) and not OWENG_PROTOTYPES.has(prototype_id):
            continue
        var metadata := get_metadata(prototype_id)
        if String(metadata.get("semantic_type", "")) != semantic_type:
            continue
        result.append(prototype_id)
    return result

func choose_population_variant(prototype_ids: Array[String], rng: RandomNumberGenerator) -> Dictionary:
    if prototype_ids.is_empty():
        return {}
    var prototype_id := prototype_ids[rng.randi_range(0, prototype_ids.size() - 1)]
    var meta := get_metadata(prototype_id)
    var minimum_scale := float(meta.get("population_scale_min", 1.0))
    var maximum_scale := maxf(minimum_scale, float(meta.get("population_scale_max", 1.0)))
    var scale := rng.randf_range(minimum_scale, maximum_scale)
    if rng.randf() < float(meta.get("population_landmark_chance", 0.0)):
        scale *= float(meta.get("population_landmark_scale", 1.0))
    return {"prototype_id": prototype_id, "scale": scale}

func get_scene(prototype_id: String) -> PackedScene:
    if _scene_cache.has(prototype_id):
        return _scene_cache[prototype_id]
    var descriptor: Dictionary = OWENG_PROTOTYPES.get(prototype_id, {})
    var path: String = (
        String(descriptor.get("source_path", ""))
        if not descriptor.is_empty()
        else String(PROTOTYPES.get(prototype_id, ""))
    )
    if path.is_empty():
        return null
    var scene: PackedScene = (
        _load_gltf_scene(path, prototype_id)
        if not descriptor.is_empty()
        else load(path) as PackedScene
    )
    if scene != null:
        _scene_cache[prototype_id] = scene
    return scene

func _load_gltf_scene(path: String, prototype_id: String) -> PackedScene:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    var parse_error := document.append_from_file(path, state)
    if parse_error != OK:
        push_error(
            "OwenG prototype '%s' could not parse '%s' (error %d)"
            % [prototype_id, path, parse_error]
        )
        return null
    var source := document.generate_scene(state)
    if source == null:
        push_error("OwenG prototype '%s' generated no scene from '%s'" % [prototype_id, path])
        return null
    var scene := PackedScene.new()
    var pack_error := scene.pack(source)
    source.free()
    if pack_error != OK:
        push_error(
            "OwenG prototype '%s' could not cache '%s' (error %d)"
            % [prototype_id, path, pack_error]
        )
        return null
    return scene

func instantiate_prototype(prototype_id: String) -> WorldPrototype:
    var descriptor: Dictionary = OWENG_PROTOTYPES.get(prototype_id, {})
    if descriptor.is_empty():
        var scene := get_scene(prototype_id)
        return null if scene == null else scene.instantiate() as WorldPrototype
    var source_scene := get_scene(prototype_id)
    if source_scene == null:
        return null

    var root := WorldPrototype.new()
    root.name = prototype_id
    root.prototype_id = prototype_id
    root.semantic_type = String(descriptor.semantic_type)
    root.placement_radius = float(descriptor.get("placement_radius", 1.0))
    root.clearance = float(descriptor.get("clearance", 0.25))
    root.population_spacing = float(descriptor.get("population_spacing", 2.0))
    root.population_occupancy_scale = float(descriptor.get("population_occupancy_scale", 0.75))
    root.population_scale_min = float(descriptor.get("population_scale_min", 1.0))
    root.population_scale_max = float(descriptor.get("population_scale_max", 1.0))
    root.population_landmark_chance = float(descriptor.get("population_landmark_chance", 0.0))
    root.population_landmark_scale = float(descriptor.get("population_landmark_scale", 1.0))
    root.set_meta("oweng_asset_id", String(descriptor.get("asset_id", "")))
    root.set_meta("source_path", String(descriptor.source_path))
    root.set_meta("license", String(descriptor.get("license", "")))
    root.set_meta("scale_correction", float(descriptor.get("scale_correction", 1.0)))

    var source := source_scene.instantiate() as Node3D
    if source == null:
        root.free()
        return null
    source.name = "Model"
    var bounds_position: Vector3 = descriptor.bounds_position
    var bounds_size: Vector3 = descriptor.bounds_size
    var model_scale := float(descriptor.get("model_scale", 1.0)) * OWENG_VISUAL_SCALE
    source.scale = Vector3.ONE * model_scale
    source.position = Vector3(
        -(bounds_position.x + bounds_size.x * 0.5) * model_scale,
        -bounds_position.y * model_scale,
        -(bounds_position.z + bounds_size.z * 0.5) * model_scale
    )
    root.add_child(source)

    var collision_kind := String(descriptor.get("collision_shape", ""))
    if not collision_kind.is_empty():
        var collision := CollisionShape3D.new()
        collision.name = "Collision"
        if collision_kind == "cylinder":
            var cylinder := CylinderShape3D.new()
            cylinder.radius = (
                float(descriptor.collision_radius) * CYLINDER_COLLISION_RADIUS_SCALE
            )
            cylinder.height = float(descriptor.collision_height)
            collision.shape = cylinder
            collision.position.y = cylinder.height * 0.5
        else:
            var box := BoxShape3D.new()
            box.size = bounds_size * model_scale * Vector3(
                BOX_COLLISION_XZ_SCALE,
                BOX_COLLISION_Y_SCALE,
                BOX_COLLISION_XZ_SCALE
            )
            collision.shape = box
            collision.position.y = box.size.y * 0.5
        root.add_child(collision)
    return root

func get_metadata(prototype_id: String) -> Dictionary:
    if _metadata_cache.has(prototype_id):
        return _metadata_cache[prototype_id]
    var instance := instantiate_prototype(prototype_id)
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
    if instance.semantic_type == "tree" and OWENG_PROTOTYPES.has(prototype_id):
        # Forest canopies should overlap visually. Placement collision remains
        # trunk-based, while density estimation uses a smaller crown footprint.
        population_footprint *= TREE_POPULATION_FOOTPRINT_SCALE
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
    if OWENG_PROTOTYPES.has(prototype_id):
        var descriptor: Dictionary = OWENG_PROTOTYPES[prototype_id]
        meta["oweng_asset_id"] = descriptor.get("asset_id", "")
        meta["source_path"] = descriptor.get("source_path", "")
        meta["license"] = descriptor.get("license", "")
        meta["scale_correction"] = descriptor.get("scale_correction", 1.0)
        meta["presentation_scale"] = OWENG_VISUAL_SCALE
        meta["collision_xz_scale"] = BOX_COLLISION_XZ_SCALE
        meta["collision_shape"] = descriptor.get("collision_shape", "")
    instance.free()
    _metadata_cache[prototype_id] = meta
    return meta

func has_semantic_type(
    semantic_type: String,
    owner_region_type: String
) -> bool:
    return not get_prototype_ids(semantic_type, owner_region_type).is_empty()

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
