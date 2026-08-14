class_name ContractValidator
extends RefCounted

const ROOT_KEYS := ["regions", "networks", "entities", "distributions"]
const ANCHORS := ["north", "south", "east", "west", "center", "northwest", "northeast", "southwest", "southeast", "whole"]
const DIRECTIONS := ["north", "south", "east", "west", "northwest", "northeast", "southwest", "southeast"]
const RELATIONS := ["inside", "near", "far_from", "along", "direction_of"]
const NETWORK_TYPES := ["road", "path"]
const DENSITIES := ["low", "medium", "high"]
const ARRANGEMENTS := ["uniform", "random", "clustered"]
const SELECTOR_TYPES := ["anchor", "near", "far_from", "direction_of"]
const FACT_KINDS := ["added_object", "removed_object", "object_state", "marked_area"]
const MARKS := ["cleared", "burned"]
const BINDING_PLACEMENTS := ["at", "inside", "near"]
const ROUTES := ["bypass", "deliberate"]

func validate_compile_request(request: Dictionary) -> PackedStringArray:
    var errors := PackedStringArray()
    _exact_keys(request, ["prompt", "current_ir", "runtime_context"], "CompileRequest", errors)
    if typeof(request.get("prompt")) != TYPE_STRING or String(request.get("prompt", "")).strip_edges().is_empty():
        errors.append("CompileRequest.prompt must be a non-empty string")

    var current_ir: Variant = request.get("current_ir")
    if current_ir != null and typeof(current_ir) != TYPE_DICTIONARY:
        errors.append("CompileRequest.current_ir must be object or null")
    elif typeof(current_ir) == TYPE_DICTIONARY:
        _append(errors, validate_world_ir(current_ir))

    var runtime_context_value: Variant = request.get("runtime_context")
    if typeof(runtime_context_value) != TYPE_DICTIONARY:
        errors.append("CompileRequest.runtime_context must be an object")
    else:
        var runtime_context: Dictionary = runtime_context_value
        _append(errors, validate_runtime_context(runtime_context))
        if current_ir == null:
            var facts: Variant = runtime_context.get("facts", [])
            if typeof(facts) == TYPE_ARRAY and not facts.is_empty():
                errors.append("Initial compile requires runtime_context.facts to be empty")
    return errors

func validate_compile_result(result: Dictionary, request_runtime_context: Dictionary = {}) -> PackedStringArray:
    var errors := PackedStringArray()
    var status_value: Variant = result.get("status")
    if typeof(status_value) != TYPE_STRING:
        errors.append("CompileResult.status must be a string")
        return errors
    var status := String(status_value)
    if status == "ok":
        _exact_keys(result, ["status", "world_ir", "runtime_bindings", "runtime_fact_ops", "meta"], "CompileResult(ok)", errors)
        var ir_value: Variant = result.get("world_ir")
        if typeof(ir_value) != TYPE_DICTIONARY:
            errors.append("CompileResult.world_ir must be an object")
            return errors
        var world_ir: Dictionary = ir_value
        _append(errors, validate_world_ir(world_ir))
        _validate_meta(result.get("meta"), errors)
        _validate_bindings(result.get("runtime_bindings"), world_ir, request_runtime_context, errors)
        _validate_fact_ops(result.get("runtime_fact_ops"), request_runtime_context, errors)
    elif status == "ir_gap":
        _exact_keys(result, ["status", "gap", "meta"], "CompileResult(ir_gap)", errors)
        var gap_value: Variant = result.get("gap")
        if typeof(gap_value) != TYPE_DICTIONARY:
            errors.append("CompileResult.gap must be an object")
        else:
            var gap: Dictionary = gap_value
            _exact_keys(gap, ["reason", "unsupported"], "CompileResult.gap", errors)
            if typeof(gap.get("reason")) != TYPE_STRING or String(gap.get("reason", "")).strip_edges().is_empty():
                errors.append("CompileResult.gap.reason must be a non-empty string")
            var unsupported: Variant = gap.get("unsupported")
            if typeof(unsupported) != TYPE_ARRAY:
                errors.append("CompileResult.gap.unsupported must be an array")
            else:
                for item in unsupported:
                    if typeof(item) != TYPE_STRING:
                        errors.append("CompileResult.gap.unsupported[] must contain strings")
        _validate_meta(result.get("meta"), errors)
    else:
        errors.append("CompileResult.status must be 'ok' or 'ir_gap'")
    return errors

func validate_runtime_context(runtime_context: Dictionary) -> PackedStringArray:
    var errors := PackedStringArray()
    _exact_keys(runtime_context, ["version", "facts"], "RuntimeContext", errors)
    if String(runtime_context.get("version", "")) != "1":
        errors.append("RuntimeContext.version must equal '1'")
    var facts_value: Variant = runtime_context.get("facts")
    if typeof(facts_value) != TYPE_ARRAY:
        errors.append("RuntimeContext.facts must be an array")
        return errors
    for index in range(facts_value.size()):
        var fact_value: Variant = facts_value[index]
        if typeof(fact_value) != TYPE_DICTIONARY:
            errors.append("RuntimeContext.facts[%d] must be an object" % index)
            continue
        _validate_runtime_fact(fact_value, "RuntimeContext.facts[%d]" % index, errors)
    return errors

func validate_world_ir(world_ir: Dictionary) -> PackedStringArray:
    var errors := PackedStringArray()
    _exact_keys(world_ir, ROOT_KEYS, "WorldIR", errors)
    for root_key in ROOT_KEYS:
        if typeof(world_ir.get(root_key)) != TYPE_ARRAY:
            errors.append("WorldIR.%s must be an array" % root_key)

    if not errors.is_empty():
        return errors

    var id_kinds: Dictionary = {}
    var id_objects: Dictionary = {}
    _index_collection(world_ir["regions"], "region", "regions", id_kinds, id_objects, errors)
    _index_collection(world_ir["networks"], "network", "networks", id_kinds, id_objects, errors)
    _index_collection(world_ir["entities"], "entity", "entities", id_kinds, id_objects, errors)
    _index_collection(world_ir["distributions"], "distribution", "distributions", id_kinds, id_objects, errors)

    for index in range(world_ir["regions"].size()):
        _validate_region(world_ir["regions"][index], "regions[%d]" % index, id_kinds, errors)
    for index in range(world_ir["networks"].size()):
        _validate_network(world_ir["networks"][index], "networks[%d]" % index, id_kinds, errors)
    for index in range(world_ir["entities"].size()):
        _validate_entity(world_ir["entities"][index], "entities[%d]" % index, id_kinds, errors)
    for index in range(world_ir["distributions"].size()):
        _validate_distribution(world_ir["distributions"][index], "distributions[%d]" % index, id_kinds, errors)
    return errors

func _index_collection(items: Array, kind: String, root_name: String, id_kinds: Dictionary, id_objects: Dictionary, errors: PackedStringArray) -> void:
    for index in range(items.size()):
        var value: Variant = items[index]
        if typeof(value) != TYPE_DICTIONARY:
            errors.append("%s[%d] must be an object" % [root_name, index])
            continue
        var item: Dictionary = value
        if typeof(item.get("id")) != TYPE_STRING:
            errors.append("%s[%d].id must be a string" % [root_name, index])
            continue
        var object_id := String(item.get("id", ""))
        if id_kinds.has(object_id):
            errors.append("World IR id '%s' is duplicated across the global namespace" % object_id)
        else:
            id_kinds[object_id] = kind
            id_objects[object_id] = item

func _validate_region(value: Variant, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        return
    var item: Dictionary = value
    _exact_keys_subset(item, ["id", "type", "placement"], ["id", "type"], path, errors)
    _validate_string_field(item, "id", path, errors)
    _validate_string_field(item, "type", path, errors)
    if item.has("placement"):
        _validate_placement(item["placement"], "region", path + ".placement", id_kinds, errors)

func _validate_entity(value: Variant, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        return
    var item: Dictionary = value
    _exact_keys_subset(item, ["id", "type", "placement"], ["id", "type"], path, errors)
    _validate_string_field(item, "id", path, errors)
    _validate_string_field(item, "type", path, errors)
    if item.has("placement"):
        _validate_placement(item["placement"], "entity", path + ".placement", id_kinds, errors)

func _validate_network(value: Variant, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        return
    var item: Dictionary = value
    _exact_keys_subset(item, ["id", "type", "topology", "placement"], ["id", "type", "topology"], path, errors)
    _validate_string_field(item, "id", path, errors)
    if typeof(item.get("type")) != TYPE_STRING or not (String(item.get("type", "")) in NETWORK_TYPES):
        errors.append("%s.type must be 'road' or 'path'" % path)
    _validate_topology(item.get("topology"), path + ".topology", id_kinds, errors)
    if item.has("placement"):
        _validate_placement(item["placement"], "network", path + ".placement", id_kinds, errors)

func _validate_distribution(value: Variant, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        return
    var item: Dictionary = value
    _exact_keys_subset(item, ["id", "type", "placement", "population"], ["id", "type"], path, errors)
    _validate_string_field(item, "id", path, errors)
    _validate_string_field(item, "type", path, errors)
    if item.has("placement"):
        _validate_placement(item["placement"], "distribution", path + ".placement", id_kinds, errors)
    if item.has("population"):
        _validate_population(item["population"], path + ".population", id_kinds, errors)

func _validate_topology(value: Variant, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        errors.append("%s must be an object" % path)
        return
    var topology: Dictionary = value
    _exact_keys_subset(topology, ["from", "to", "via"], ["from", "to"], path, errors)
    _validate_topology_token(topology.get("from"), path + ".from", id_kinds, errors)
    _validate_topology_token(topology.get("to"), path + ".to", id_kinds, errors)
    if topology.has("via"):
        var via_value: Variant = topology["via"]
        if typeof(via_value) != TYPE_ARRAY:
            errors.append("%s.via must be an array" % path)
        else:
            for index in range(via_value.size()):
                var token: Variant = via_value[index]
                if typeof(token) != TYPE_STRING or not id_kinds.has(String(token)):
                    errors.append("%s.via[%d] must reference an existing World IR id" % [path, index])

func _validate_topology_token(value: Variant, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_STRING:
        errors.append("%s must be an anchor or existing World IR id" % path)
        return
    var token := String(value)
    if not (token in ANCHORS) and not id_kinds.has(token):
        errors.append("%s references unknown token '%s'" % [path, token])

func _validate_placement(value: Variant, source_kind: String, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        errors.append("%s must be an object" % path)
        return
    var placement: Dictionary = value
    _exact_keys_subset(placement, ["anchor", "relations"], [], path, errors)
    if placement.has("anchor"):
        if typeof(placement["anchor"]) != TYPE_STRING or not (String(placement["anchor"]) in ANCHORS):
            errors.append("%s.anchor is not a valid World IR anchor" % path)
    if placement.has("relations"):
        var relations_value: Variant = placement["relations"]
        if typeof(relations_value) != TYPE_ARRAY:
            errors.append("%s.relations must be an array" % path)
        else:
            for index in range(relations_value.size()):
                _validate_relation(relations_value[index], source_kind, "%s.relations[%d]" % [path, index], id_kinds, errors)

func _validate_relation(value: Variant, source_kind: String, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        errors.append("%s must be an object" % path)
        return
    var rel: Dictionary = value
    var kind_value: Variant = rel.get("type")
    if typeof(kind_value) != TYPE_STRING or not (String(kind_value) in RELATIONS):
        errors.append("%s.type is not a supported relation" % path)
        return
    var kind := String(kind_value)
    var allowed_keys: Array = ["type", "target", "direction"] if kind == "direction_of" else ["type", "target"]
    _exact_keys(rel, allowed_keys, path, errors)
    if typeof(rel.get("target")) != TYPE_STRING:
        errors.append("%s.target must be a string" % path)
        return
    var target := String(rel.get("target", ""))
    if not id_kinds.has(target):
        errors.append("%s.target references unknown World IR id '%s'" % [path, target])
        return
    if kind == "inside" and String(id_kinds[target]) != "region":
        errors.append("%s inside.target must be a Region" % path)
    if kind == "along":
        if not (source_kind in ["entity", "distribution"]):
            errors.append("%s along source must be Entity or Distribution" % path)
        if String(id_kinds[target]) != "network":
            errors.append("%s along.target must be a Network" % path)
    if kind == "direction_of":
        if typeof(rel.get("direction")) != TYPE_STRING or not (String(rel.get("direction", "")) in DIRECTIONS):
            errors.append("%s.direction is not a valid relation direction" % path)

func _validate_population(value: Variant, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        errors.append("%s must be an object" % path)
        return
    var population: Dictionary = value
    _exact_keys_subset(population, ["amount", "arrangement", "density_profile"], [], path, errors)
    var amount_mode := ""
    if population.has("amount"):
        amount_mode = _validate_amount(population["amount"], path + ".amount", errors)
    if population.has("arrangement"):
        _validate_arrangement(population["arrangement"], path + ".arrangement", errors)
    if population.has("density_profile"):
        _validate_density_profile(population["density_profile"], path + ".density_profile", id_kinds, errors)
        if amount_mode == "density":
            errors.append("%s cannot combine amount.mode=density with density_profile" % path)

func _validate_amount(value: Variant, path: String, errors: PackedStringArray) -> String:
    if typeof(value) != TYPE_DICTIONARY:
        errors.append("%s must be an object" % path)
        return ""
    var amount: Dictionary = value
    _exact_keys(amount, ["mode", "value"], path, errors)
    if typeof(amount.get("mode")) != TYPE_STRING:
        errors.append("%s.mode must be 'count' or 'density'" % path)
        return ""
    var mode := String(amount.get("mode", ""))
    if mode == "count":
        var count_value: Variant = amount.get("value")
        if not _is_nonnegative_json_integer(count_value):
            errors.append("%s.value must be a non-negative integer for count mode" % path)
    elif mode == "density":
        if typeof(amount.get("value")) != TYPE_STRING or not (String(amount.get("value", "")) in DENSITIES):
            errors.append("%s.value must be low|medium|high for density mode" % path)
    else:
        errors.append("%s.mode must be 'count' or 'density'" % path)
    return mode

func _validate_arrangement(value: Variant, path: String, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        errors.append("%s must be an object" % path)
        return
    var arrangement: Dictionary = value
    _exact_keys(arrangement, ["type"], path, errors)
    if typeof(arrangement.get("type")) != TYPE_STRING or not (String(arrangement.get("type", "")) in ARRANGEMENTS):
        errors.append("%s.type must be uniform|random|clustered" % path)

func _validate_density_profile(value: Variant, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        errors.append("%s must be an object" % path)
        return
    var profile: Dictionary = value
    _exact_keys(profile, ["type", "from", "to"], path, errors)
    if String(profile.get("type", "")) != "gradient":
        errors.append("%s.type must be 'gradient'" % path)
    _validate_gradient_endpoint(profile.get("from"), path + ".from", id_kinds, errors)
    _validate_gradient_endpoint(profile.get("to"), path + ".to", id_kinds, errors)

func _validate_gradient_endpoint(value: Variant, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        errors.append("%s must be an object" % path)
        return
    var endpoint: Dictionary = value
    _exact_keys(endpoint, ["selector", "density"], path, errors)
    if typeof(endpoint.get("density")) != TYPE_STRING or not (String(endpoint.get("density", "")) in DENSITIES):
        errors.append("%s.density must be low|medium|high" % path)
    _validate_selector(endpoint.get("selector"), path + ".selector", id_kinds, errors)

func _validate_selector(value: Variant, path: String, id_kinds: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        errors.append("%s must be an object" % path)
        return
    var selector: Dictionary = value
    if typeof(selector.get("type")) != TYPE_STRING or not (String(selector.get("type", "")) in SELECTOR_TYPES):
        errors.append("%s.type is not a supported SpatialSelector" % path)
        return
    var kind := String(selector.get("type", ""))
    if kind == "anchor":
        _exact_keys(selector, ["type", "value"], path, errors)
        if typeof(selector.get("value")) != TYPE_STRING or not (String(selector.get("value", "")) in ANCHORS):
            errors.append("%s.value is not a valid anchor" % path)
        return
    var allowed_keys: Array = ["type", "target", "direction"] if kind == "direction_of" else ["type", "target"]
    _exact_keys(selector, allowed_keys, path, errors)
    if typeof(selector.get("target")) != TYPE_STRING or not id_kinds.has(String(selector.get("target", ""))):
        errors.append("%s.target must reference an existing World IR id" % path)
    if kind == "direction_of":
        if typeof(selector.get("direction")) != TYPE_STRING or not (String(selector.get("direction", "")) in DIRECTIONS):
            errors.append("%s.direction is not a valid direction" % path)

func _validate_runtime_fact(value: Variant, path: String, errors: PackedStringArray) -> void:
    var fact: Dictionary = value
    var kind_value: Variant = fact.get("kind")
    if typeof(kind_value) != TYPE_STRING or not (String(kind_value) in FACT_KINDS):
        errors.append("%s.kind is not a valid Runtime Fact kind" % path)
        return
    var kind := String(kind_value)
    if kind in ["added_object", "removed_object"]:
        _exact_keys_subset(fact, ["id", "kind", "object_type", "location"], ["id", "kind", "object_type"], path, errors)
        _validate_nonempty_string(fact.get("id"), path + ".id", errors)
        _validate_nonempty_string(fact.get("object_type"), path + ".object_type", errors)
        if fact.has("location"):
            _validate_semantic_location(fact["location"], path + ".location", errors)
    elif kind == "object_state":
        _exact_keys(fact, ["id", "kind", "target", "state"], path, errors)
        _validate_nonempty_string(fact.get("id"), path + ".id", errors)
        _validate_nonempty_string(fact.get("target"), path + ".target", errors)
        _validate_nonempty_string(fact.get("state"), path + ".state", errors)
    elif kind == "marked_area":
        _exact_keys_subset(fact, ["id", "kind", "mark", "location", "affected_type", "count"], ["id", "kind", "mark", "location"], path, errors)
        _validate_nonempty_string(fact.get("id"), path + ".id", errors)
        if typeof(fact.get("mark")) != TYPE_STRING or not (String(fact.get("mark", "")) in MARKS):
            errors.append("%s.mark must be cleared|burned" % path)
        _validate_semantic_location(fact.get("location"), path + ".location", errors)
        if fact.has("affected_type"):
            _validate_nonempty_string(fact["affected_type"], path + ".affected_type", errors)
        if fact.has("count"):
            var count_value: Variant = fact["count"]
            if not _is_nonnegative_json_integer(count_value):
                errors.append("%s.count must be a non-negative integer" % path)

func _validate_semantic_location(value: Variant, path: String, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        errors.append("%s must be an object" % path)
        return
    var location: Dictionary = value
    _exact_keys_subset(location, ["anchor", "inside", "near"], [], path, errors)
    if location.is_empty():
        errors.append("%s must contain at least one semantic location field" % path)
    if location.has("anchor") and (typeof(location["anchor"]) != TYPE_STRING or not (String(location["anchor"]) in ANCHORS)):
        errors.append("%s.anchor is not a valid anchor" % path)
    if location.has("inside"):
        _validate_nonempty_string(location["inside"], path + ".inside", errors)
    if location.has("near"):
        _validate_nonempty_string(location["near"], path + ".near", errors)

func _validate_meta(value: Variant, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_DICTIONARY:
        errors.append("CompileResult.meta must be an object")
        return
    var meta: Dictionary = value
    _exact_keys_subset(meta, ["request_id", "mode", "route"], ["request_id", "mode"], "CompileResult.meta", errors)
    _validate_nonempty_string(meta.get("request_id"), "CompileResult.meta.request_id", errors)
    if typeof(meta.get("mode")) != TYPE_STRING or not (String(meta.get("mode", "")) in ["initial", "edit"]):
        errors.append("CompileResult.meta.mode must be initial|edit")
    if meta.has("route") and (typeof(meta["route"]) != TYPE_STRING or not (String(meta["route"]) in ROUTES)):
        errors.append("CompileResult.meta.route must be bypass|deliberate when present")

func _validate_bindings(value: Variant, world_ir: Dictionary, runtime_context: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_ARRAY:
        errors.append("CompileResult.runtime_bindings must be an array")
        return
    var ir_ids := _world_ir_ids(world_ir)
    var fact_ids := _runtime_fact_ids(runtime_context)
    for index in range(value.size()):
        var binding_value: Variant = value[index]
        var path := "CompileResult.runtime_bindings[%d]" % index
        if typeof(binding_value) != TYPE_DICTIONARY:
            errors.append("%s must be an object" % path)
            continue
        var binding: Dictionary = binding_value
        _exact_keys(binding, ["ir_object_id", "runtime_fact_id", "placement"], path, errors)
        var object_id := String(binding.get("ir_object_id", ""))
        var fact_id := String(binding.get("runtime_fact_id", ""))
        if typeof(binding.get("ir_object_id")) != TYPE_STRING or not ir_ids.has(object_id):
            errors.append("%s.ir_object_id must reference Candidate World IR" % path)
        if typeof(binding.get("runtime_fact_id")) != TYPE_STRING or not fact_ids.has(fact_id):
            errors.append("%s.runtime_fact_id must reference a fact from the request Runtime Context" % path)
        if typeof(binding.get("placement")) != TYPE_STRING or not (String(binding.get("placement", "")) in BINDING_PLACEMENTS):
            errors.append("%s.placement must be at|inside|near" % path)

func _validate_fact_ops(value: Variant, runtime_context: Dictionary, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_ARRAY:
        errors.append("CompileResult.runtime_fact_ops must be an array")
        return
    var fact_ids := _runtime_fact_ids(runtime_context)
    for index in range(value.size()):
        var op_value: Variant = value[index]
        var path := "CompileResult.runtime_fact_ops[%d]" % index
        if typeof(op_value) != TYPE_DICTIONARY:
            errors.append("%s must be an object" % path)
            continue
        var op: Dictionary = op_value
        _exact_keys(op, ["op", "runtime_fact_id"], path, errors)
        if String(op.get("op", "")) != "clear":
            errors.append("%s.op must equal 'clear'" % path)
        var fact_id := String(op.get("runtime_fact_id", ""))
        if typeof(op.get("runtime_fact_id")) != TYPE_STRING or not fact_ids.has(fact_id):
            errors.append("%s.runtime_fact_id must reference a fact from the request Runtime Context" % path)

func _world_ir_ids(world_ir: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for root_key in ROOT_KEYS:
        var items: Variant = world_ir.get(root_key, [])
        if typeof(items) != TYPE_ARRAY:
            continue
        for item in items:
            if typeof(item) == TYPE_DICTIONARY and typeof(item.get("id")) == TYPE_STRING:
                out[String(item.get("id", ""))] = true
    return out

func _runtime_fact_ids(runtime_context: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    var facts: Variant = runtime_context.get("facts", [])
    if typeof(facts) != TYPE_ARRAY:
        return out
    for fact in facts:
        if typeof(fact) == TYPE_DICTIONARY and typeof(fact.get("id")) == TYPE_STRING:
            out[String(fact.get("id", ""))] = true
    return out


func _is_nonnegative_json_integer(value: Variant) -> bool:
    # Godot parses JSON numbers as float. The wire-level Contract says integer,
    # so accept either an actual int or an integral finite float such as 12.0.
    if typeof(value) == TYPE_INT:
        return int(value) >= 0
    if typeof(value) == TYPE_FLOAT:
        var number: float = float(value)
        return is_finite(number) and number >= 0.0 and number == floor(number)
    return false

func _validate_string_field(item: Dictionary, field_name: String, path: String, errors: PackedStringArray) -> void:
    if typeof(item.get(field_name)) != TYPE_STRING:
        errors.append("%s.%s must be a string" % [path, field_name])

func _validate_nonempty_string(value: Variant, path: String, errors: PackedStringArray) -> void:
    if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
        errors.append("%s must be a non-empty string" % path)

func _exact_keys(value: Dictionary, allowed: Array, path: String, errors: PackedStringArray) -> void:
    for required_key in allowed:
        if not value.has(required_key):
            errors.append("%s is missing required field '%s'" % [path, required_key])
    for key in value.keys():
        if not (String(key) in allowed):
            errors.append("%s has unknown field '%s'" % [path, String(key)])

func _exact_keys_subset(value: Dictionary, allowed: Array, required: Array, path: String, errors: PackedStringArray) -> void:
    for required_key in required:
        if not value.has(required_key):
            errors.append("%s is missing required field '%s'" % [path, required_key])
    for key in value.keys():
        if not (String(key) in allowed):
            errors.append("%s has unknown field '%s'" % [path, String(key)])

func _append(target: PackedStringArray, source: PackedStringArray) -> void:
    for message in source:
        target.append(message)
