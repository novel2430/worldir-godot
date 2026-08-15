class_name ChunkRecord
extends Resource

enum StreamingState {
	UNLOADED,
	GEOMETRY_READY,
	ENVIRONMENT_READY,
	ACTIVE,
	DORMANT,
}

enum AuthorityState {
	PROVISIONAL,
	COMMITTED,
}

var coord := Vector2i.ZERO
var streaming_state := StreamingState.UNLOADED
var authority := AuthorityState.PROVISIONAL
var source_ir_revision := -1
var target_ir_revision := -1
var is_stale := false
var resolved_chunk: ResolvedChunk = null
var generation_constraints: ChunkBoundaryConstraints = null
var committed_resolved_snapshot: ResolvedChunk = null

func configure(
	chunk_coord: Vector2i,
	source_revision: int = -1,
	target_revision: int = -1
) -> ChunkRecord:
	coord = chunk_coord
	source_ir_revision = source_revision
	target_ir_revision = target_revision
	_refresh_stale()
	return self

func set_source_revision(value: int) -> void:
	source_ir_revision = value
	_refresh_stale()

func set_target_revision(value: int) -> void:
	target_ir_revision = value
	_refresh_stale()

func mark_stale(value: int) -> void:
	set_target_revision(value)

func accept_resolved(value: ResolvedChunk) -> void:
	resolved_chunk = value
	if value != null:
		source_ir_revision = value.revision
		target_ir_revision = value.revision
		generation_constraints = (
			value.generation_constraints.duplicate_constraints()
			if value.generation_constraints != null
			else null
		)
		committed_resolved_snapshot = value
	_refresh_stale()

func is_current_ready() -> bool:
	return (
		resolved_chunk != null
		and not is_stale
		and source_ir_revision == target_ir_revision
		and streaming_state != StreamingState.UNLOADED
	)

func streaming_state_name() -> String:
	return StreamingState.keys()[streaming_state]

func authority_name() -> String:
	return AuthorityState.keys()[authority]

func _refresh_stale() -> void:
	is_stale = source_ir_revision != target_ir_revision
