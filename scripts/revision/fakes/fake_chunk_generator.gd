class_name FakeChunkGenerator
extends RefCounted

const ResolvedChunkScript = preload("res://scripts/resolved/resolved_chunk.gd")

var fail_generation := false
var fail_scene_build := false
var calls: Array[Dictionary] = []

func generate_chunk(
	coord: Vector2i,
	world_ir: Dictionary,
	ir_revision: int,
	world_seed: int,
	boundary_constraints: Dictionary,
	generation_overrides: Dictionary = {}
):
	calls.append({
		"coord": coord,
		"world_ir": world_ir.duplicate(true),
		"ir_revision": ir_revision,
		"world_seed": world_seed,
		"boundary_constraints": boundary_constraints.duplicate(true),
		"generation_overrides": generation_overrides.duplicate(true),
	})
	if fail_generation:
		return null

	var chunk := ResolvedChunkScript.new()
	chunk.coord = coord
	chunk.revision = ir_revision
	chunk.seed = world_seed
	chunk.bounds = Rect2(Vector2(coord) * 160.0, Vector2.ONE * 160.0)
	_add_distribution(chunk, world_ir, "trees", "tree", "tree_01", 0.0)
	_add_distribution(chunk, world_ir, "houses", "house", "house_01", 40.0)
	if fail_scene_build and not chunk.distributions.is_empty():
		var first_distribution: ResolvedDistribution = chunk.distributions[0]
		if not first_distribution.instances.is_empty():
			first_distribution.instances[0]["prototype_id"] = "missing_prototype"
	return chunk

func _add_distribution(
	chunk: ResolvedWorld,
	world_ir: Dictionary,
	distribution_id: String,
	semantic_type: String,
	prototype_id: String,
	z_offset: float
) -> void:
	var count := _distribution_count(world_ir, distribution_id)
	var distribution := ResolvedDistribution.new()
	distribution.id = distribution_id
	distribution.semantic_type = semantic_type
	for index in range(count):
		distribution.instances.append({
			"id": "%s:%03d" % [distribution_id, index],
			"prototype_id": prototype_id,
			"transform": Transform3D(
				Basis.IDENTITY,
				Vector3(5.0 + float(index % 5) * 6.0, 0.0, z_offset + float(index / 5) * 6.0)
			),
		})
	chunk.distributions.append(distribution)

func _distribution_count(world_ir: Dictionary, distribution_id: String) -> int:
	for value in world_ir.get("distributions", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var distribution: Dictionary = value
		if String(distribution.get("id", "")) != distribution_id:
			continue
		var population: Dictionary = distribution.get("population", {})
		var amount: Dictionary = population.get("amount", {})
		if String(amount.get("mode", "")) == "count":
			return maxi(0, int(amount.get("value", 0)))
	return 0
