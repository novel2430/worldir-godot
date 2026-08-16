class_name BackendConfig
extends RefCounted

const PlacementSolverScript = preload("res://scripts/backend/placement_solver.gd")
const DistributionLowererScript = preload("res://scripts/backend/distribution_lowerer.gd")
const RegionClaimResolverScript = preload("res://scripts/backend/region_claim_resolver.gd")

const DEFAULT_PATH := "res://data/configs/backend.json"
const DEFAULT_WORLD_SIZE_M := 160.0
const DEFAULT_SEED := 1337
const DEFAULT_NEAR_THRESHOLD_M := PlacementSolverScript.NEAR_THRESHOLD_M
const DEFAULT_FAR_THRESHOLD_M := PlacementSolverScript.FAR_THRESHOLD_M
const DEFAULT_ALONG_THRESHOLD_M := PlacementSolverScript.ALONG_THRESHOLD_M
const DEFAULT_POPULATION_BUDGET := DistributionLowererScript.DEFAULT_POPULATION_BUDGET
const DEFAULT_RANDOM_PACKING_LOSS := DistributionLowererScript.RANDOM_PACKING_LOSS
const DEFAULT_DENSITY_SPACING_MULTIPLIERS := DistributionLowererScript.DENSITY_SPACING_MULTIPLIERS
const DEFAULT_POPULATION_CAPS := DistributionLowererScript.POPULATION_CAPS
const DEFAULT_REGION_CLAIM_BUDGET_M2 := RegionClaimResolverScript.DEFAULT_REGION_CLAIM_BUDGET_M2
const DEFAULT_REGION_CLAIM_BUDGETS_M2 := RegionClaimResolverScript.DEFAULT_REGION_CLAIM_BUDGETS_M2

var world_size_m := DEFAULT_WORLD_SIZE_M
var seed := DEFAULT_SEED
var near_threshold_m := DEFAULT_NEAR_THRESHOLD_M
var far_threshold_m := DEFAULT_FAR_THRESHOLD_M
var along_threshold_m := DEFAULT_ALONG_THRESHOLD_M
var default_population_budget := DEFAULT_POPULATION_BUDGET
var random_packing_loss := DEFAULT_RANDOM_PACKING_LOSS
var density_spacing_multipliers: Dictionary = DEFAULT_DENSITY_SPACING_MULTIPLIERS.duplicate()
var population_caps: Dictionary = DEFAULT_POPULATION_CAPS.duplicate()
var default_region_claim_budget_m2 := DEFAULT_REGION_CLAIM_BUDGET_M2
var region_claim_budgets_m2: Dictionary = DEFAULT_REGION_CLAIM_BUDGETS_M2.duplicate()
var warnings := PackedStringArray()

func _init(overrides: Dictionary = {}) -> void:
	_apply(_read_file(DEFAULT_PATH), DEFAULT_PATH)
	if not overrides.is_empty():
		_apply(overrides, "WorldBackend override")

func world_bounds() -> Rect2:
	var extent := Vector2.ONE * world_size_m
	return Rect2(-extent * 0.5, extent)

func lowering_values() -> Dictionary:
	return {
		"default_population_budget": default_population_budget,
		"random_packing_loss": random_packing_loss,
		"density_spacing_multipliers": density_spacing_multipliers.duplicate(),
		"population_caps": population_caps.duplicate(),
	}

func region_claim_values() -> Dictionary:
	return {
		"default_region_claim_budget_m2": default_region_claim_budget_m2,
		"region_claim_budgets_m2": region_claim_budgets_m2.duplicate(),
	}

func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		warnings.append("Backend config '%s' is missing; built-in defaults are active" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		warnings.append("Backend config '%s' is not a JSON object; built-in defaults are active" % path)
		return {}
	return parsed as Dictionary

func _apply(values: Dictionary, source: String) -> void:
	world_size_m = _positive_float(values, "world_size_m", world_size_m, source)
	seed = _integer(values, "seed", seed, source)
	near_threshold_m = _positive_float(values, "near_threshold_m", near_threshold_m, source)
	far_threshold_m = _positive_float(values, "far_threshold_m", far_threshold_m, source)
	along_threshold_m = _positive_float(values, "along_threshold_m", along_threshold_m, source)
	default_population_budget = _positive_int(
		values,
		"default_population_budget",
		default_population_budget,
		source
	)
	random_packing_loss = _positive_float(
		values,
		"random_packing_loss",
		random_packing_loss,
		source
	)
	_merge_positive_float_map(
		values,
		"density_spacing_multipliers",
		density_spacing_multipliers,
		source
	)
	_merge_positive_int_map(values, "population_caps", population_caps, source)
	default_region_claim_budget_m2 = _positive_float(
		values,
		"default_region_claim_budget_m2",
		default_region_claim_budget_m2,
		source
	)
	_merge_positive_float_map(
		values,
		"region_claim_budgets_m2",
		region_claim_budgets_m2,
		source
	)

func _positive_float(values: Dictionary, key: String, fallback: float, source: String) -> float:
	if not values.has(key):
		return fallback
	var value: Variant = values[key]
	if not _is_number(value) or float(value) <= 0.0:
		warnings.append("%s.%s must be a positive number; using %s" % [source, key, fallback])
		return fallback
	return float(value)

func _integer(values: Dictionary, key: String, fallback: int, source: String) -> int:
	if not values.has(key):
		return fallback
	var value: Variant = values[key]
	if not _is_number(value) or not is_equal_approx(float(value), round(float(value))):
		warnings.append("%s.%s must be an integer; using %d" % [source, key, fallback])
		return fallback
	return int(value)

func _positive_int(values: Dictionary, key: String, fallback: int, source: String) -> int:
	var value := _integer(values, key, fallback, source)
	if value <= 0:
		warnings.append("%s.%s must be positive; using %d" % [source, key, fallback])
		return fallback
	return value

func _merge_positive_float_map(
	values: Dictionary,
	key: String,
	target: Dictionary,
	source: String
) -> void:
	if not values.has(key):
		return
	if typeof(values[key]) != TYPE_DICTIONARY:
		warnings.append("%s.%s must be an object; using defaults" % [source, key])
		return
	for item_key in (values[key] as Dictionary).keys():
		var value: Variant = values[key][item_key]
		if not _is_number(value) or float(value) <= 0.0:
			warnings.append("%s.%s.%s must be positive; ignoring it" % [source, key, item_key])
			continue
		target[String(item_key)] = float(value)

func _merge_positive_int_map(
	values: Dictionary,
	key: String,
	target: Dictionary,
	source: String
) -> void:
	if not values.has(key):
		return
	if typeof(values[key]) != TYPE_DICTIONARY:
		warnings.append("%s.%s must be an object; using defaults" % [source, key])
		return
	for item_key in (values[key] as Dictionary).keys():
		var value: Variant = values[key][item_key]
		if not _is_number(value) or float(value) <= 0.0 or not is_equal_approx(float(value), round(float(value))):
			warnings.append("%s.%s.%s must be a positive integer; ignoring it" % [source, key, item_key])
			continue
		target[String(item_key)] = int(value)

func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
