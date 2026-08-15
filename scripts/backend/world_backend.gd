class_name WorldBackend
extends RefCounted

const TerrainResolverScript = preload("res://scripts/backend/terrain_resolver.gd")
const CoastResolverScript = preload("res://scripts/backend/coast_resolver.gd")
const BackendConfigScript = preload("res://scripts/backend/backend_config.gd")
const RegionClaimResolverScript = preload("res://scripts/backend/region_claim_resolver.gd")

var region_lowerer := RegionLowerer.new()
var network_lowerer := NetworkLowerer.new()
var entity_lowerer := EntityLowerer.new()
var distribution_lowerer := DistributionLowerer.new()
var terrain_resolver: RefCounted = TerrainResolverScript.new()
var coast_resolver: RefCounted = CoastResolverScript.new()
var forest_dresser := ForestDresser.new()
var solver := PlacementSolver.new()
var region_claim_resolver: RefCounted = RegionClaimResolverScript.new()
var config: RefCounted

func _init(config_overrides: Dictionary = {}) -> void:
	config = BackendConfigScript.new(config_overrides)
	distribution_lowerer.configure(config.lowering_values())
	region_claim_resolver.configure(config.region_claim_values())

func lower(
	world_ir: Dictionary,
	catalog: PrototypeCatalog,
	seed_value: int = -1,
	runtime_bindings: Array = [],
	spatial_payloads: Dictionary = {},
	world_bounds_override: Rect2 = Rect2(),
	realization_seed_override: int = -1
) -> ResolvedWorld:
	var out := ResolvedWorld.new()
	var effective_seed: int = config.seed if seed_value < 0 else seed_value
	var realization_seed: int = (
		effective_seed if realization_seed_override < 0 else realization_seed_override
	)
	out.seed = effective_seed
	out.realization_seed = realization_seed
	var environment_value: Variant = world_ir.get("environment", {})
	if environment_value is Dictionary:
		out.environment = environment_value.duplicate(true)
	out.world_bounds = (
		world_bounds_override if world_bounds_override.has_area() else config.world_bounds()
	)
	for warning in config.warnings:
		out.warnings.append(warning)
	solver.configure(
		out.world_bounds,
		realization_seed,
		config.near_threshold_m,
		config.far_threshold_m,
		config.along_threshold_m
	)

	var ir_objects: Dictionary = {}
	var ir_kinds: Dictionary = {}
	_index_ir(world_ir, ir_objects, ir_kinds)

	var context := {
		"regions": {},
		"region_count": (world_ir.get("regions", []) as Array).size(),
		"networks": {},
		"entities": {},
		"distributions": {},
		"ir_objects": ir_objects,
		"ir_kinds": ir_kinds,
		"spatial_payloads": spatial_payloads,
		"seed": realization_seed,
	}

	_validate_binding_capability(runtime_bindings, spatial_payloads, out)
	if not out.errors.is_empty():
		return out

	var region_items: Array = world_ir.get("regions", [])
	var resolved_regions_by_id: Dictionary = {}
	var fixed_region_ids: Dictionary = {}
	var region_lowering_order := _region_lowering_order(region_items, ir_kinds)
	for item in region_lowering_order:
		var binding := _binding_for(String(item.get("id", "")), runtime_bindings, out)
		var resolved := region_lowerer.lower(item, solver, binding, spatial_payloads, context)
		if resolved == null:
			out.errors.append(region_lowerer.last_error if not region_lowerer.last_error.is_empty() else "Region lowering failed")
			return out
		resolved_regions_by_id[resolved.id] = resolved
		context.regions[resolved.id] = resolved
		if not binding.is_empty() or _is_single_unconstrained_region(item, region_items.size()):
			fixed_region_ids[resolved.id] = true
	if not region_claim_resolver.apply(
		region_lowering_order,
		resolved_regions_by_id,
		solver,
		fixed_region_ids
	):
		out.errors.append(region_claim_resolver.last_error)
		return out
	# Dependencies affect calculation order only. Preserve IR order in ResolvedWorld
	# so callers never observe a gratuitous collection reorder.
	for item in region_items:
		out.regions.append(resolved_regions_by_id[String(item.get("id", ""))])

	for item in world_ir.get("networks", []):
		var binding := _binding_for(String(item.get("id", "")), runtime_bindings, out)
		var resolved := network_lowerer.lower(item, solver, realization_seed, context, binding)
		if resolved == null:
			out.errors.append(network_lowerer.last_error if not network_lowerer.last_error.is_empty() else "Network lowering failed")
			return out
		out.networks.append(resolved)
		context.networks[resolved.id] = resolved

	for item in world_ir.get("entities", []):
		var binding := _binding_for(String(item.get("id", "")), runtime_bindings, out)
		var resolved := entity_lowerer.lower(item, catalog, solver, context, binding)
		if resolved == null:
			out.errors.append(entity_lowerer.last_error if not entity_lowerer.last_error.is_empty() else "Entity lowering failed")
			continue
		out.entities.append(resolved)
		context.entities[resolved.id] = resolved

	for item in world_ir.get("distributions", []):
		var binding := _binding_for(String(item.get("id", "")), runtime_bindings, out)
		var resolved := distribution_lowerer.lower(item, catalog, solver, context, binding)
		if resolved == null:
			out.errors.append(distribution_lowerer.last_error if not distribution_lowerer.last_error.is_empty() else "Distribution lowering failed")
			continue
		out.distributions.append(resolved)
		context.distributions[resolved.id] = resolved

	# Dressing is derived only after every explicit semantic object has claimed
	# occupancy. It is backend-owned, best effort, and cannot fail World lowering.
	if out.errors.is_empty():
		out.waters = coast_resolver.resolve(out)
		out.terrain = terrain_resolver.resolve(out, catalog)
		terrain_resolver.conform_world(out)
		forest_dresser.dress(out, catalog, solver)

	return out

func _index_ir(world_ir: Dictionary, ir_objects: Dictionary, ir_kinds: Dictionary) -> void:
	var roots := {
		"regions": "region",
		"networks": "network",
		"entities": "entity",
		"distributions": "distribution",
	}
	for root_key in roots.keys():
		for item in world_ir.get(root_key, []):
			var object_id := String(item.get("id", ""))
			ir_objects[object_id] = item
			ir_kinds[object_id] = String(roots[root_key])

func _region_lowering_order(items: Array, ir_kinds: Dictionary) -> Array:
	var pending: Array = items.duplicate()
	var result: Array = []
	var resolved_ids: Dictionary = {}
	while not pending.is_empty():
		var selected_index := -1
		for index in range(pending.size()):
			if _region_dependencies_ready(pending[index], resolved_ids, ir_kinds):
				selected_index = index
				break
		# Cycles retain deterministic IR order and use the existing raw-target
		# fallback for the first member; resolving it unlocks the rest of the cycle.
		if selected_index < 0:
			selected_index = 0
		var item: Dictionary = pending[selected_index]
		pending.remove_at(selected_index)
		result.append(item)
		resolved_ids[String(item.get("id", ""))] = true
	return result

func _region_dependencies_ready(
	item: Dictionary,
	resolved_ids: Dictionary,
	ir_kinds: Dictionary
) -> bool:
	for relation in item.get("placement", {}).get("relations", []):
		var target := String(relation.get("target", ""))
		if String(ir_kinds.get(target, "")) == "region" and not resolved_ids.has(target):
			return false
	return true

func _is_single_unconstrained_region(item: Dictionary, region_count: int) -> bool:
	if region_count != 1:
		return false
	var placement: Dictionary = item.get("placement", {})
	return (
		String(placement.get("anchor", "")).strip_edges().is_empty()
		and (placement.get("relations", []) as Array).is_empty()
	)

func _validate_binding_capability(bindings: Array, spatial_payloads: Dictionary, out: ResolvedWorld) -> void:
	var per_object_count: Dictionary = {}
	for binding in bindings:
		var object_id := String(binding.get("ir_object_id", ""))
		var fact_id := String(binding.get("runtime_fact_id", ""))
		per_object_count[object_id] = int(per_object_count.get(object_id, 0)) + 1
		if not spatial_payloads.has(fact_id):
			out.errors.append(
                "Runtime Binding references fact '%s', but Godot has no Spatial Payload for it"
				% fact_id
			)
	for object_id in per_object_count.keys():
		if int(per_object_count[object_id]) > 1:
			out.errors.append(
                "Godot Backend V0 supports one Runtime Binding per IR object; '%s' received %d"
				% [String(object_id), int(per_object_count[object_id])]
			)

func _binding_for(ir_object_id: String, bindings: Array, _out: ResolvedWorld) -> Dictionary:
	for binding in bindings:
		if String(binding.get("ir_object_id", "")) == ir_object_id:
			return binding
	return {}
