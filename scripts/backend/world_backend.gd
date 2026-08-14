class_name WorldBackend
extends RefCounted

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
	}

	_validate_binding_capability(runtime_bindings, spatial_payloads, out)
	if not out.errors.is_empty():
		return out

	for item in world_ir.get("regions", []):
		var binding := _binding_for(String(item.get("id", "")), runtime_bindings, out)
		var resolved := region_lowerer.lower(item, solver, binding, spatial_payloads, context)
		out.regions.append(resolved)
		context.regions[resolved.id] = resolved

	for item in world_ir.get("networks", []):
		var binding := _binding_for(String(item.get("id", "")), runtime_bindings, out)
		var resolved := network_lowerer.lower(item, solver, seed_value, context, binding)
		out.networks.append(resolved)
		context.networks[resolved.id] = resolved

	for item in world_ir.get("entities", []):
		var binding := _binding_for(String(item.get("id", "")), runtime_bindings, out)
		var resolved := entity_lowerer.lower(item, catalog, solver, context, binding)
		if resolved == null:
			out.errors.append(
                "Backend capability missing: no TSCN prototype for Entity '%s' (type='%s')"
				% [String(item.get("id", "")), String(item.get("type", ""))]
			)
			continue
		out.entities.append(resolved)
		context.entities[resolved.id] = resolved

	for item in world_ir.get("distributions", []):
		var binding := _binding_for(String(item.get("id", "")), runtime_bindings, out)
		var resolved := distribution_lowerer.lower(item, catalog, solver, context, binding)
		if resolved == null:
			out.errors.append(
                "Backend capability missing: no TSCN prototype for Distribution '%s' (type='%s')"
				% [String(item.get("id", "")), String(item.get("type", ""))]
			)
			continue
		out.distributions.append(resolved)
		context.distributions[resolved.id] = resolved

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
