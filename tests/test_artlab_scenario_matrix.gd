extends SceneTree

const FIXTURES: Array[String] = [
	"res://data/fixtures/coastal_town_initial.json",
	"res://data/fixtures/clearing_to_graveyard.json",
	"res://data/fixtures/restore_forest.json",
	"res://data/fixtures/inland_forest_village.json",
	"res://data/fixtures/southern_coast_hamlet.json",
]

func _init() -> void:
	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	var validator := ContractValidator.new()
	var generator := ChunkGenerator.new(catalog)
	for fixture_path in FIXTURES:
		var fixture := _load_json(fixture_path)
		var ir: Dictionary = fixture.get("world_ir", {})
		assert(validator.validate_world_ir(ir).is_empty())
		var before := JSON.stringify(ir)
		for coord in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var chunk := generator.generate_chunk(coord, ir, 0, 1337)
			assert(chunk.errors.is_empty())
			assert(chunk.terrain != null)
		assert(JSON.stringify(ir) == before)
	catalog.free()
	print("ArtLab scenario matrix tests passed")
	quit(0)

func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
