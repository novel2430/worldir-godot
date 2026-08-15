class_name FakeChunkManager
extends RefCounted

var generator: RefCounted
var current_chunk_coord: Vector2i = Vector2i.ZERO
var records: Dictionary = {}
var chunk_roots: Dictionary = {}
var boundary_constraints: Dictionary = {}
var _pin_counts: Dictionary = {}
var target_revision_calls: Array[Dictionary] = []
var rebuild_requests: Array[Dictionary] = []
var rebuild_queue: Dictionary = {}
var ensure_latest_calls: Array[Vector2i] = []
var rebuild_failure_coords: Dictionary = {}
var ensure_latest_failure_coords: Dictionary = {}
var revision_worlds: Dictionary = {}
var world_seed := 1

func _init(fake_generator: RefCounted = null) -> void:
	generator = fake_generator

func register_chunk(
	coord: Vector2i,
	authority: String,
	resolved_chunk: ResolvedWorld,
	chunk_root: Node3D
) -> void:
	records[coord] = {
		"coord": coord,
		"streaming_state": "ACTIVE" if coord == current_chunk_coord else "ENVIRONMENT_READY",
		"authority": authority,
		"source_ir_revision": int(resolved_chunk.get("revision")),
		"target_ir_revision": int(resolved_chunk.get("revision")),
		"resolved_chunk": resolved_chunk,
	}
	chunk_roots[coord] = chunk_root

func get_current_chunk_coord() -> Vector2i:
	return current_chunk_coord

func set_current_chunk_coord(coord: Vector2i) -> void:
	current_chunk_coord = coord

func get_record(coord: Vector2i) -> Dictionary:
	return records.get(coord, {})

func get_active_records() -> Array:
	return records.values()

func get_chunk_root(coord: Vector2i) -> Node3D:
	return chunk_roots.get(coord) as Node3D

func get_boundary_constraints(coord: Vector2i) -> Dictionary:
	return (boundary_constraints.get(coord, {}) as Dictionary).duplicate(true)

func pin_chunk(coord: Vector2i) -> void:
	_pin_counts[coord] = int(_pin_counts.get(coord, 0)) + 1

func unpin_chunk(coord: Vector2i) -> void:
	var count := int(_pin_counts.get(coord, 0))
	if count <= 1:
		_pin_counts.erase(coord)
	else:
		_pin_counts[coord] = count - 1

func is_pinned(coord: Vector2i) -> bool:
	return int(_pin_counts.get(coord, 0)) > 0

func set_target_revision(coord: Vector2i, revision: int) -> bool:
	target_revision_calls.append({"coord": coord, "revision": revision})
	if not records.has(coord):
		return false
	var record: Dictionary = records[coord]
	record["target_ir_revision"] = revision
	return true

func request_rebuild(coord: Vector2i, revision: int) -> bool:
	rebuild_requests.append({"coord": coord, "revision": revision})
	if not records.has(coord) or rebuild_failure_coords.has(coord):
		return false
	# A scheduler owns timing. This fake models only its required latest-wins
	# queue behavior, so a newer request supersedes the queued older revision.
	rebuild_queue[coord] = revision
	return true

func register_revision_world(revision: int, world_ir: Dictionary) -> void:
	revision_worlds[revision] = world_ir.duplicate(true)

func ensure_latest(coord: Vector2i) -> bool:
	ensure_latest_calls.append(coord)
	if not records.has(coord) or ensure_latest_failure_coords.has(coord):
		return false
	var record: Dictionary = records[coord]
	var source_revision := int(record.get("source_ir_revision", -1))
	var target_revision := int(record.get("target_ir_revision", -1))
	if source_revision == target_revision:
		return true
	if not revision_worlds.has(target_revision):
		return false
	var resolved: Variant = generate_chunk(
		coord,
		revision_worlds[target_revision],
		target_revision,
		world_seed,
		get_boundary_constraints(coord),
		{}
	)
	if resolved == null:
		return false
	install_revision(coord, resolved, target_revision)
	rebuild_queue.erase(coord)
	return true

func generate_chunk(
	coord: Vector2i,
	world_ir: Dictionary,
	ir_revision: int,
	world_seed: int,
	constraints: Dictionary,
	generation_overrides: Dictionary = {}
):
	if generator == null:
		return null
	return generator.generate_chunk(
		coord,
		world_ir,
		ir_revision,
		world_seed,
		constraints,
		generation_overrides
	)

func install_revision(coord: Vector2i, resolved_chunk: ResolvedWorld, revision: int) -> void:
	var record: Dictionary = records[coord]
	record["resolved_chunk"] = resolved_chunk
	record["source_ir_revision"] = revision
	record["target_ir_revision"] = revision
