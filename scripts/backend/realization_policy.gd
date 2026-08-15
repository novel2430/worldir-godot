class_name RealizationPolicy
extends RefCounted

const DEFAULT_PATH := "res://data/configs/artlab_realization_policy.json"
const FORMAT := "worldir-godot-artlab-realization-policy-v1"
const FORMAT_VERSION := 1
const SUPPORTED_FORMATS: Array[String] = [FORMAT]

# Built-in values are compatibility fallbacks. The JSON file is the live policy
# source, just as backend.json is the live source for spatial lowering policy.
const DEFAULT_VALUES := {
    "format": FORMAT,
    "source": {
        "project": "WorldIR Godot ArtLab V2",
        "scope": "backend_owned_realization_only",
        "world_ir_contract_unchanged": true,
    },
    "terrain": {
        "region_roles": {
            "forest_surface": ["forest", "swamp"],
            "settlement_surface": ["town", "village", "district"],
            "coast_surface": ["coast"],
        },
        "geometry": {
            "base_height_limit_m": 2.8,
            "forest_height_limit_m": 3.55,
            "forest_relief_strength": 0.78,
            "settlement_flatten_strength": 0.82,
            "broad_x_frequency": 0.027,
            "broad_x_amplitude_m": 1.05,
            "broad_z_frequency": 0.023,
            "broad_z_amplitude_m": 0.85,
            "broad_diagonal_frequency": 0.014,
            "broad_diagonal_amplitude_m": 0.65,
            "detail_x_frequency": 0.071,
            "detail_z_frequency": 0.043,
            "detail_first_amplitude_m": 0.32,
            "detail_second_x_frequency": 0.049,
            "detail_second_z_frequency": 0.061,
            "detail_second_amplitude_m": 0.24,
            "forest_first_x_frequency": 0.041,
            "forest_first_z_frequency": 0.026,
            "forest_first_amplitude_m": 0.56,
            "forest_second_x_frequency": 0.019,
            "forest_second_z_frequency": 0.044,
            "forest_second_amplitude_m": 0.42,
            "forest_detail_multiplier": 0.48,
        },
        "influences": {
            "region_outer_blend_m": 3.5,
            "region_inner_blend_m": 5.5,
            "road_shoulder_m": 2.6,
            "road_terrain_blend_m": 3.4,
            "building_dirt_fade_m": 2.3,
            "building_flatten_blend_m": 2.8,
            "building_path_max_length_m": 26.0,
            "building_path_surface_inner_m": 0.55,
            "building_path_surface_outer_m": 1.45,
            "coast_beach_blend_start_m": -18.0,
            "coast_beach_blend_end_m": -5.0,
            "coast_land_blend_m": 12.0,
            "coast_wet_sand_m": 4.5,
            "coast_underwater_slope": 0.035,
            "coast_land_height_above_sea_m": 0.62,
            "coast_shore_height_offset_m": -0.06,
            "coast_underwater_height_offset_m": -0.14,
            "coast_max_underwater_drop_m": 1.8,
        },
    },
    "surface": {
        "palette": {
            "meadow_low": [0.19, 0.245, 0.125],
            "meadow_high": [0.255, 0.305, 0.155],
            "forest_green_low": [0.105, 0.17, 0.07],
            "forest_green_high": [0.17, 0.235, 0.105],
            "forest_soil": [0.255, 0.18, 0.095],
            "packed_dirt_low": [0.31, 0.235, 0.135],
            "packed_dirt_high": [0.38, 0.285, 0.16],
            "sand_low": [0.43, 0.405, 0.265],
            "sand_high": [0.52, 0.485, 0.315],
            "wet_sand_low": [0.245, 0.255, 0.19],
            "wet_sand_high": [0.31, 0.295, 0.205],
            "road_dirt_low": [0.285, 0.205, 0.115],
            "road_dirt_high": [0.355, 0.265, 0.145],
        },
        "forest_soil_patch_start": 0.61,
        "forest_soil_patch_end": 0.79,
        "forest_soil_patch_strength": 0.58,
        "settlement_blend_strength": 0.82,
        "wet_sand_blend_strength": 0.88,
        "road_blend_strength": 0.86,
        "variation_min": 0.94,
        "variation_max": 1.06,
        "roughness": 1.0,
        "specular": 0.08,
    },
    "dressing": {
        "density_semantics": "candidate_placement_times_acceptance_probability_times_spatial_influences",
        "region_types": ["forest"],
        "candidate_attempts": 140,
        "cluster_sample_probability": 0.82,
        "cluster_center_attempts": 96,
        "cluster_center_minimum_separation_m": 8.0,
        "cluster_separation_score_distance_m": 14.0,
        "cluster_profile_score_weight": 0.70,
        "edge_profiles": {
            "edge": {
                "minimum_multiplier": 0.08,
                "outer_ramp_start_m": 0.2,
                "outer_ramp_end_m": 2.5,
                "interior_falloff_start_m": 8.0,
                "interior_falloff_end_m": 22.0,
            },
            "interior": {
                "minimum_multiplier": 0.05,
                "ramp_start_m": 5.0,
                "ramp_end_m": 16.0,
            },
            "mixed": {
                "minimum_multiplier": 0.55,
                "falloff_start_m": 10.0,
                "falloff_end_m": 26.0,
            },
        },
        "layers": {
            "dead_tree": {
                "target_area_per_candidate_m2": 456.0,
                "acceptance_probability": 0.12,
                "legacy_area_per_instance_m2": 3800.0,
                "cap": 4,
                "cluster_count": 0,
                "cluster_radius_m": 0.0,
                "edge_mode": "interior",
                "road_clearance_m": 2.0,
            },
            "rock": {
                "target_area_per_candidate_m2": 171.6,
                "acceptance_probability": 0.22,
                "legacy_area_per_instance_m2": 780.0,
                "cap": 18,
                "cluster_count": 3,
                "cluster_radius_m": 3.8,
                "edge_mode": "mixed",
                "road_clearance_m": 1.5,
            },
            "bush": {
                "target_area_per_candidate_m2": 130.0,
                "acceptance_probability": 0.52,
                "legacy_area_per_instance_m2": 250.0,
                "cap": 55,
                "cluster_count": 5,
                "cluster_radius_m": 6.0,
                "edge_mode": "edge",
                "road_clearance_m": 1.0,
            },
            "grass": {
                "target_area_per_candidate_m2": 77.0,
                "acceptance_probability": 0.77,
                "legacy_area_per_instance_m2": 100.0,
                "cap": 120,
                "cluster_count": 7,
                "cluster_radius_m": 7.0,
                "edge_mode": "edge",
                "road_clearance_m": 0.55,
            },
        },
        "building_clearing": {
            "minimum_inner_radius_m": 4.0,
            "minimum_outer_radius_m": 12.0,
            "footprint_inner_scale": 1.6,
            "footprint_outer_scale": 3.0,
            "minimum_multiplier": {
                "dead_tree": 0.20,
                "rock": 0.65,
                "bush": 0.16,
                "grass": 0.12,
            },
        },
        "network_corridors": {
            "road": {
                "outer_extra_width_m": 5.2,
                "minimum_multiplier": {
                    "dead_tree": 0.35,
                    "rock": 0.55,
                    "bush": 0.10,
                    "grass": 0.08,
                },
            },
            "path": {
                "outer_extra_width_m": 2.55,
                "minimum_multiplier": {
                    "dead_tree": 0.45,
                    "rock": 0.65,
                    "bush": 0.12,
                    "grass": 0.10,
                },
            },
        },
    },
}

var values: Dictionary = DEFAULT_VALUES.duplicate(true)
var warnings := PackedStringArray()
var source_path := ""
var loaded_from_disk := false
var _path_cache: Dictionary = {}

func _init(path: String = DEFAULT_PATH) -> void:
    source_path = path
    if path.is_empty():
        return
    if not FileAccess.file_exists(path):
        warnings.append("Realization policy '%s' is missing; built-in defaults are active" % path)
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        warnings.append("Realization policy '%s' is not a JSON object; built-in defaults are active" % path)
        return
    var incoming := parsed as Dictionary
    var incoming_format := String(incoming.get("format", ""))
    if incoming_format not in SUPPORTED_FORMATS:
        warnings.append(
            "Realization policy '%s' has unsupported format '%s' (supported: %s); built-in defaults are active"
            % [path, incoming_format, ", ".join(SUPPORTED_FORMATS)]
        )
        return
    _merge_known(values, incoming, "policy")
    loaded_from_disk = true

func fingerprint() -> String:
    # DEFAULT_VALUES establishes stable insertion order and _merge_known only
    # replaces existing leaves, so this digest is deterministic across runs.
    return JSON.stringify(values).sha256_text()

func diagnostic_snapshot(include_values: bool = false) -> Dictionary:
    var snapshot := {
        "format": String(values.get("format", FORMAT)),
        "format_version": FORMAT_VERSION,
        "fingerprint": fingerprint(),
        "source_path": source_path,
        "loaded_from_disk": loaded_from_disk,
        "warnings": Array(warnings),
    }
    if include_values:
        snapshot["values"] = values.duplicate(true)
    return snapshot

func number(path: String, fallback: float) -> float:
    var value: Variant = get_value(path, fallback)
    return float(value) if _is_number(value) else fallback

func positive_number(path: String, fallback: float) -> float:
    var value := number(path, fallback)
    return value if value > 0.0 else fallback

func probability(path: String, fallback: float) -> float:
    return clampf(number(path, fallback), 0.0, 1.0)

func integer(path: String, fallback: int) -> int:
    var value: Variant = get_value(path, fallback)
    if not _is_number(value) or not is_equal_approx(float(value), round(float(value))):
        return fallback
    return int(value)

func text(path: String, fallback: String) -> String:
    var value: Variant = get_value(path, fallback)
    return String(value) if typeof(value) == TYPE_STRING else fallback

func color(path: String, fallback: Color) -> Color:
    var value: Variant = get_value(path, null)
    if value is Array and value.size() >= 3:
        return Color(
            float(value[0]),
            float(value[1]),
            float(value[2]),
            float(value[3]) if value.size() >= 4 else 1.0
        )
    if typeof(value) == TYPE_STRING:
        return Color.from_string(String(value), fallback)
    return fallback

func dictionary(path: String) -> Dictionary:
    var value: Variant = get_value(path, {})
    return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func string_array(path: String, fallback: Array = []) -> Array[String]:
    var value: Variant = get_value(path, fallback)
    if not (value is Array):
        var fallback_result: Array[String] = []
        for item in fallback:
            if typeof(item) == TYPE_STRING:
                fallback_result.append(String(item))
        return fallback_result
    var result: Array[String] = []
    for item in value:
        if typeof(item) == TYPE_STRING:
            result.append(String(item))
    return result

func dressing_rule(decoration_type: String, fallback: Dictionary = {}) -> Dictionary:
    var rule := dictionary("dressing.layers.%s" % decoration_type)
    return fallback.duplicate(true) if rule.is_empty() else rule

func get_value(path: String, fallback: Variant = null) -> Variant:
    if _path_cache.has(path):
        return _path_cache[path]
    var current: Variant = values
    for segment in path.split(".", false):
        if typeof(current) != TYPE_DICTIONARY or not (current as Dictionary).has(segment):
            return fallback
        current = (current as Dictionary)[segment]
    _path_cache[path] = current
    return current

func _merge_known(target: Dictionary, incoming: Dictionary, path: String) -> void:
    for raw_key in incoming.keys():
        var key := String(raw_key)
        if not target.has(key):
            warnings.append("%s.%s is unknown and was ignored" % [path, key])
            continue
        var expected: Variant = target[key]
        var candidate: Variant = incoming[key]
        if expected is Dictionary:
            if candidate is Dictionary:
                _merge_known(expected as Dictionary, candidate as Dictionary, "%s.%s" % [path, key])
            else:
                warnings.append("%s.%s must be an object; using the built-in value" % [path, key])
        elif _is_number(expected):
            if _is_number(candidate):
                target[key] = candidate
            else:
                warnings.append("%s.%s must be numeric; using the built-in value" % [path, key])
        elif typeof(candidate) == typeof(expected):
            target[key] = candidate
        else:
            warnings.append("%s.%s has the wrong type; using the built-in value" % [path, key])

func _is_number(value: Variant) -> bool:
    return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
