class_name OwnerRegionResolver
extends RefCounted

var last_error := ""

func validate_regions(items: Array, ir_kinds: Dictionary) -> bool:
	last_error = ""
	for item: Dictionary in items:
		for relation: Dictionary in item.get("placement", {}).get("relations", []):
			if String(relation.get("type", "")) != "inside":
				continue
			var target := String(relation.get("target", ""))
			last_error = (
				"Owner Region validation failed: Region '%s' cannot be inside '%s'; "
				+ "Region nesting is not supported"
			) % [String(item.get("id", "")), target]
			return false
	return true

func resolve(item: Dictionary, context: Dictionary, object_kind: String) -> Dictionary:
	last_error = ""
	var object_id := String(item.get("id", ""))
	var inside_relations: Array = []
	for relation: Dictionary in item.get("placement", {}).get("relations", []):
		if String(relation.get("type", "")) == "inside":
			inside_relations.append(relation)

	if inside_relations.size() != 1:
		last_error = (
			"Owner Region validation failed for %s '%s': expected exactly one "
			+ "placement.relations[].type='inside', found %d"
		) % [object_kind, object_id, inside_relations.size()]
		return {}

	var target_id := String((inside_relations[0] as Dictionary).get("target", ""))
	var target_kind := String(context.get("ir_kinds", {}).get(target_id, ""))
	if target_kind != "region":
		last_error = (
			"Owner Region validation failed for %s '%s': inside target '%s' "
			+ "must be a Region"
		) % [object_kind, object_id, target_id]
		return {}

	var region: ResolvedRegion = context.get("regions", {}).get(target_id)
	if region == null:
		last_error = (
			"Owner Region validation failed for %s '%s': Region '%s' is not resolved"
		) % [object_kind, object_id, target_id]
		return {}

	return {
		"id": region.id,
		"type": region.semantic_type,
		"profile_id": region.profile_id,
		"profile": region.profile,
	}
