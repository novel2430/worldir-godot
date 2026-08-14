class_name WorldBackend
extends RefCounted

const IMPLICIT_FOREST_TREES_PREFIX := "__backend_default__:forest_trees:"
const IMPLICIT_FOREST_TREE_DENSITY := "medium"

var region_lowerer := RegionLowerer.new()
var network_lowerer := NetworkLowerer.new()
var entity_lowerer := EntityLowerer.new()
var distribution_lowerer := DistributionLowerer.new()
var solver := PlacementSolver.new()

func lower(
	world_ir: Dictionary,
	catalog: PrototypeCatalog,
	seed_value: int,
	runtime_bindings: Array = [],
	spatial_payloads: Dictionary = {}
) -> ResolvedWorld:
	var out := ResolvedWorld.new()
	out.seed = seed_value
	solver.configure(out.world_bounds, seed_value)

	var ir_objects: Dictionary = {}
	var ir_kinds: Dictionary = {}
	_index_ir(world_ir, ir_objects, ir_kinds)

	var context := {
		"regions": {},
		"networks": {},
		"entities": {},
		"distributions": {},
		"ir_objects": ir_objects,
		"ir_kinds": ir_kinds,
		"spatial_payloads": spatial_payloads,
		"seed": seed_value,
	}

	_validate_binding_capability(runtime_bindings, spatial_payloads, out)
	if not out.errors.is_empty():
		return out

	for item in world_ir.get("regions", []):
		var binding := _binding_for(String(item.get("id", "")), runtime_bindings, out)
		var resolved := region_lowerer.lower(item, solver, binding, spatial_payloads, context)
		if resolved == null:
			out.errors.append(region_lowerer.last_error if not region_lowerer.last_error.is_empty() else "Region lowering failed")
			return out
		out.regions.append(resolved)
		context.regions[resolved.id] = resolved

	for item in world_ir.get("networks", []):
		var binding := _binding_for(String(item.get("id", "")), runtime_bindings, out)
		var resolved := network_lowerer.lower(item, solver, seed_value, context, binding)
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

	_lower_implicit_region_defaults(world_ir, catalog, context, out)

	return out

func _lower_implicit_region_defaults(
	world_ir: Dictionary,
	catalog: PrototypeCatalog,
	context: Dictionary,
	out: ResolvedWorld
) -> void:
	var explicit_tree_forests := _forests_with_explicit_tree_distributions(world_ir)
	for region in out.regions:
		if region.semantic_type != "forest" or explicit_tree_forests.has(region.id):
			continue

		var synthetic_id := _unique_implicit_id(region.id, context)
		var synthetic_distribution := {
			"id": synthetic_id,
			"type": "tree",
			"placement": {
				"relations": [{"type": "inside", "target": region.id}],
			},
			"population": {
				"amount": {"mode": "density", "value": IMPLICIT_FOREST_TREE_DENSITY},
				"arrangement": {"type": "random"},
			},
		}

		# Defaults are decorative and lower last. A failed attempt must not leave
		# partial occupancy or RNG changes that influence another forest default.
		var occupancy_checkpoint: int = solver.occupied.size()
		var rng_checkpoint: int = solver.rng.state
		var resolved := distribution_lowerer.lower(
			synthetic_distribution,
			catalog,
			solver,
			context
		)
		if resolved == null:
			solver.occupied.resize(occupancy_checkpoint)
			solver.rng.state = rng_checkpoint
			out.warnings.append(
				"Skipped implicit trees for forest '%s': %s"
				% [region.id, distribution_lowerer.last_error]
			)
			continue

		out.distributions.append(resolved)
		context.distributions[resolved.id] = resolved

func _forests_with_explicit_tree_distributions(world_ir: Dictionary) -> Dictionary:
	var explicit_forests: Dictionary = {}
	for raw_distribution in world_ir.get("distributions", []):
		if typeof(raw_distribution) != TYPE_DICTIONARY:
			continue
		var distribution: Dictionary = raw_distribution
		if String(distribution.get("type", "")) != "tree":
			continue
		var placement_value: Variant = distribution.get("placement", {})
		if typeof(placement_value) != TYPE_DICTIONARY:
			continue
		var placement: Dictionary = placement_value
		for raw_relation in placement.get("relations", []):
			if typeof(raw_relation) != TYPE_DICTIONARY:
				continue
			var relation: Dictionary = raw_relation
			if String(relation.get("type", "")) == "inside":
				explicit_forests[String(relation.get("target", ""))] = true
	return explicit_forests

func _unique_implicit_id(forest_id: String, context: Dictionary) -> String:
	var base_id := IMPLICIT_FOREST_TREES_PREFIX + forest_id
	var candidate := base_id
	var suffix := 1
	var ir_objects: Dictionary = context.get("ir_objects", {})
	var resolved_distributions: Dictionary = context.get("distributions", {})
	while ir_objects.has(candidate) or resolved_distributions.has(candidate):
		candidate = "%s:%d" % [base_id, suffix]
		suffix += 1
	return candidate

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
