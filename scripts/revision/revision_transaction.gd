class_name RevisionTransaction
extends RefCounted

const ChunkRebasePlannerScript = preload("res://scripts/revision/chunk_rebase_planner.gd")

const STATE_CAPTURED := "CAPTURED"
const STATE_PREPARED := "PREPARED"
const STATE_COMMITTED := "COMMITTED"
const STATE_ABORTED := "ABORTED"

var base_revision: int = -1
var candidate_revision: int = 0
var transaction_chunk_coord: Vector2i = Vector2i.ZERO
var state: String = ""
var candidate_ir: Variant = null
var revision_plan: Variant = null

func capture(revision: int, current_chunk_coord: Vector2i) -> void:
	assert(state.is_empty())
	base_revision = revision
	candidate_revision = revision + 1
	# The coordinate is copied at Prompt submission. No later Current Chunk read
	# participates in this transaction's target selection.
	transaction_chunk_coord = current_chunk_coord
	state = STATE_CAPTURED

func prepare(candidate: Dictionary, records: Array):
	assert(state == STATE_CAPTURED)
	candidate_ir = candidate.duplicate(true)
	revision_plan = ChunkRebasePlannerScript.build_plan(
		base_revision,
		candidate_revision,
		transaction_chunk_coord,
		records
	)
	state = STATE_PREPARED
	return revision_plan

func commit_to(world_state: WorldState, candidate_facts: Array = []) -> bool:
	if state != STATE_PREPARED:
		return false
	if world_state.current_ir_revision != base_revision:
		return false
	if not world_state.commit_revision(candidate_ir, candidate_facts, candidate_revision):
		return false
	state = STATE_COMMITTED
	return true

func abort() -> void:
	if state == STATE_COMMITTED:
		return
	candidate_ir = null
	revision_plan = null
	state = STATE_ABORTED
