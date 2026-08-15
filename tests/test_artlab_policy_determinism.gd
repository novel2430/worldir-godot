extends SceneTree

const COORDS: Array[Vector2i] = [
	Vector2i(-2, 1),
	Vector2i.ZERO,
	Vector2i(3, -1),
	Vector2i(-1, -2),
	Vector2i(2, 2),
]

func _init() -> void:
	var fixture := _load_json("res://data/fixtures/coastal_town_initial.json")
	var ir: Dictionary = fixture.get("world_ir", {})
	var before := JSON.stringify(ir)
	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)

	var forward := _generate_signatures(COORDS, ir, catalog)
	var reverse_coords := COORDS.duplicate()
	reverse_coords.reverse()
	var reverse := _generate_signatures(reverse_coords, ir, catalog)
	assert(forward == reverse)
	assert(JSON.stringify(ir) == before)

	var policy_a := RealizationPolicy.new()
	var policy_b := RealizationPolicy.new()
	assert(policy_a.fingerprint() == policy_b.fingerprint())
	assert(policy_a.diagnostic_snapshot() == policy_b.diagnostic_snapshot())

	catalog.free()
	print("ArtLab policy determinism tests passed")
	quit(0)

func _generate_signatures(
	coords: Array[Vector2i],
	ir: Dictionary,
	catalog: PrototypeCatalog
) -> Dictionary:
	var generator := ChunkGenerator.new(catalog)
	var signatures := {}
	for coord in coords:
		var chunk := generator.generate_chunk(coord, ir, 7, 7301)
		assert(chunk.errors.is_empty())
		signatures[coord] = chunk.deterministic_signature()
	return signatures

func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
