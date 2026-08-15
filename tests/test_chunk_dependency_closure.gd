extends SceneTree

func _init() -> void:
	var generator := ChunkGenerator.new()
	var ir := _dependency_graph()
	assert(ContractValidator.new().validate_world_ir(ir).is_empty())
	var before := JSON.stringify(ir)

	var center := generator._interpret_world_ir(ir, Vector2i.ZERO, {}, [])
	assert(_ids(center, "regions") == ["coast", "town", "market", "forest"])
	assert(_ids(center, "networks") == ["road", "trail"])
	assert(_ids(center, "entities") == ["lighthouse"])
	assert(_ids(center, "distributions") == ["houses", "lamps", "mixed_growth", "forest_trees"])

	# The east-anchored coast is not part of a northwest Chunk. Its complete
	# dependent subgraph must disappear, including a region cycle, topology via,
	# a network-to-network chain, multiple placement targets, and a gradient
	# selector. The independent forest branch must remain intact.
	var northwest := generator._interpret_world_ir(ir, Vector2i(-1, -1), {}, [])
	assert(_ids(northwest, "regions") == ["forest"])
	assert(_ids(northwest, "networks").is_empty())
	assert(_ids(northwest, "entities").is_empty())
	assert(_ids(northwest, "distributions") == ["forest_trees"])
	assert(JSON.stringify(ir) == before)

	# A pure cycle with no Chunk-local removal seed is legal input to this pass
	# and must not be removed merely because it is cyclic.
	var cycle_only := {
		"regions": [
			{"id": "a", "type": "town", "placement": {"relations": [{"type": "near", "target": "b"}]}},
			{"id": "b", "type": "village", "placement": {"relations": [{"type": "near", "target": "a"}]}},
		],
		"networks": [],
		"entities": [],
		"distributions": [],
	}
	assert(ContractValidator.new().validate_world_ir(cycle_only).is_empty())
	var retained_cycle := generator._interpret_world_ir(cycle_only, Vector2i(-4, 7), {}, [])
	assert(_ids(retained_cycle, "regions") == ["a", "b"])

	print("Chunk dependency closure tests passed")
	quit(0)

func _dependency_graph() -> Dictionary:
	return {
		"regions": [
			{"id": "coast", "type": "coast", "placement": {"anchor": "east"}},
			{"id": "town", "type": "town", "placement": {"relations": [
				{"type": "near", "target": "coast"},
				{"type": "near", "target": "market"},
			]}},
			{"id": "market", "type": "district", "placement": {"relations": [
				{"type": "inside", "target": "town"},
			]}},
			{"id": "forest", "type": "forest", "placement": {"anchor": "west"}},
		],
		"networks": [
			{
				"id": "road",
				"type": "road",
				"topology": {"from": "south", "to": "north", "via": ["town", "market"]},
				"placement": {"relations": [{"type": "inside", "target": "town"}]},
			},
			{
				"id": "trail",
				"type": "path",
				"topology": {"from": "road", "to": "north"},
			},
		],
		"entities": [{
			"id": "lighthouse",
			"type": "lighthouse",
			"placement": {"relations": [{"type": "near", "target": "coast"}]},
		}],
		"distributions": [
			{
				"id": "houses",
				"type": "house",
				"placement": {"relations": [
					{"type": "inside", "target": "town"},
					{"type": "along", "target": "road"},
				]},
				"population": {"amount": {"mode": "count", "value": 6}},
			},
			{
				"id": "lamps",
				"type": "lamp",
				"population": {
					"amount": {"mode": "count", "value": 8},
					"density_profile": {
						"type": "gradient",
						"from": {"selector": {"type": "near", "target": "trail"}, "density": "high"},
						"to": {"selector": {"type": "anchor", "value": "west"}, "density": "low"},
					},
				},
			},
			{
				"id": "mixed_growth",
				"type": "tree",
				"placement": {"relations": [
					{"type": "inside", "target": "forest"},
					{"type": "far_from", "target": "town"},
				]},
			},
			{
				"id": "forest_trees",
				"type": "tree",
				"placement": {"relations": [{"type": "inside", "target": "forest"}]},
				"population": {"amount": {"mode": "density", "value": "medium"}},
			},
		],
	}

func _ids(world_ir: Dictionary, collection_name: String) -> Array[String]:
	var result: Array[String] = []
	for item: Dictionary in world_ir.get(collection_name, []):
		result.append(String(item.get("id", "")))
	return result
