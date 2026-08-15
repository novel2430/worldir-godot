class_name RevisionPlan
extends RefCounted

const FUTURE_USE_LATEST_ON_FIRST_GENERATION := "USE_LATEST_ON_FIRST_GENERATION"

var from_revision: int
var candidate_revision: int
var transaction_chunk_coord: Vector2i
var must_rebase: Array[Vector2i] = []
var target_latest: Array[Vector2i] = []
var preserve: Array[Vector2i] = []
var future_policy: String = FUTURE_USE_LATEST_ON_FIRST_GENERATION

func _init(
	base_revision: int = -1,
	target_revision: int = 0,
	transaction_coord: Vector2i = Vector2i.ZERO
) -> void:
	from_revision = base_revision
	candidate_revision = target_revision
	transaction_chunk_coord = transaction_coord

func to_dict() -> Dictionary:
	return {
		"from_revision": from_revision,
		"candidate_revision": candidate_revision,
		"transaction_chunk_coord": transaction_chunk_coord,
		"must_rebase": must_rebase.duplicate(),
		"target_latest": target_latest.duplicate(),
		"preserve": preserve.duplicate(),
		"future_policy": future_policy,
	}

func to_debug_string() -> String:
	return (
		"RevisionPlan(from=%d, candidate=%d, transaction_chunk=%s, "
		+ "must_rebase=%s, target_latest=%s, preserve=%s, future=%s)"
	) % [
		from_revision,
		candidate_revision,
		transaction_chunk_coord,
		must_rebase,
		target_latest,
		preserve,
		future_policy,
	]
