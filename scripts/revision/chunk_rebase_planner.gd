class_name ChunkRebasePlanner
extends RefCounted

const RevisionPlanScript = preload("res://scripts/revision/revision_plan.gd")

const AUTHORITY_PROVISIONAL := "PROVISIONAL"
const AUTHORITY_COMMITTED := "COMMITTED"

const ACTION_MUST_REBASE := "MUST_REBASE"
const ACTION_TARGET_LATEST := "TARGET_LATEST"
const ACTION_PRESERVE := "PRESERVE"

static func can_rebase(record: Dictionary, transaction_chunk_coord: Vector2i) -> bool:
	var authority := _authority(record)
	return (
		_coord(record) == transaction_chunk_coord
		or authority == AUTHORITY_PROVISIONAL
	)

static func classify(record: Dictionary, transaction_chunk_coord: Vector2i) -> String:
	if _coord(record) == transaction_chunk_coord:
		return ACTION_MUST_REBASE
	if _authority(record) == AUTHORITY_PROVISIONAL:
		return ACTION_TARGET_LATEST
	return ACTION_PRESERVE

static func build_plan(
	from_revision: int,
	candidate_revision: int,
	transaction_chunk_coord: Vector2i,
	records: Array
):
	var plan := RevisionPlanScript.new(
		from_revision,
		candidate_revision,
		transaction_chunk_coord
	)
	# The captured transaction target is always the synchronous rebase target,
	# even if A has not materialized a record view for it yet.
	plan.must_rebase.append(transaction_chunk_coord)
	for record_value in records:
		assert(typeof(record_value) == TYPE_DICTIONARY)
		var record: Dictionary = record_value
		var coord := _coord(record)
		if coord == transaction_chunk_coord:
			continue
		match classify(record, transaction_chunk_coord):
			ACTION_TARGET_LATEST:
				plan.target_latest.append(coord)
			_:
				plan.preserve.append(coord)
	return plan

static func is_stale(record: Dictionary) -> bool:
	return int(record.get("source_ir_revision", -1)) != int(
		record.get("target_ir_revision", -1)
	)

static func _coord(record: Dictionary) -> Vector2i:
	assert(record.has("coord"))
	var value: Variant = record["coord"]
	assert(value is Vector2i)
	return value as Vector2i

static func _authority(record: Dictionary) -> String:
	var authority := String(record.get("authority", ""))
	assert(authority == AUTHORITY_PROVISIONAL or authority == AUTHORITY_COMMITTED)
	return authority
