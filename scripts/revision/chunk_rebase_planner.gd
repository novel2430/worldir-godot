class_name ChunkRebasePlanner
extends RefCounted

const RevisionPlanScript = preload("res://scripts/revision/revision_plan.gd")

const AUTHORITY_PROVISIONAL := "PROVISIONAL"
const AUTHORITY_COMMITTED := "COMMITTED"

const ACTION_MUST_REBASE := "MUST_REBASE"
const ACTION_TARGET_LATEST := "TARGET_LATEST"
const ACTION_PRESERVE := "PRESERVE"

static func can_rebase(record: Variant, transaction_chunk_coord: Vector2i) -> bool:
	var authority := _authority(record)
	return (
		_coord(record) == transaction_chunk_coord
		or authority == AUTHORITY_PROVISIONAL
	)

static func classify(record: Variant, transaction_chunk_coord: Vector2i) -> String:
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
		assert(record_exists(record_value))
		var coord := _coord(record_value)
		if coord == transaction_chunk_coord:
			continue
		match classify(record_value, transaction_chunk_coord):
			ACTION_TARGET_LATEST:
				plan.target_latest.append(coord)
			_:
				plan.preserve.append(coord)
	return plan

static func is_stale(record: Variant) -> bool:
	return source_revision(record) != target_revision(record)

static func record_exists(record: Variant) -> bool:
	return record != null and not (typeof(record) == TYPE_DICTIONARY and record.is_empty())

static func coord(record: Variant) -> Vector2i:
	return _coord(record)

static func authority(record: Variant) -> String:
	return _authority(record)

static func source_revision(record: Variant) -> int:
	return int(_record_value(record, "source_ir_revision", -1))

static func target_revision(record: Variant) -> int:
	return int(_record_value(record, "target_ir_revision", -1))

static func resolved_chunk(record: Variant) -> Variant:
	return _record_value(record, "resolved_chunk", null)

static func _coord(record: Variant) -> Vector2i:
	var value: Variant = _record_value(record, "coord", null)
	assert(value is Vector2i)
	return value as Vector2i

static func _authority(record: Variant) -> String:
	var value: Variant = _record_value(record, "authority", "")
	var authority_name := ""
	if record is Object and record.has_method("authority_name"):
		authority_name = String(record.call("authority_name"))
	else:
		authority_name = String(value)
	assert(authority_name == AUTHORITY_PROVISIONAL or authority_name == AUTHORITY_COMMITTED)
	return authority_name

static func _record_value(record: Variant, field: StringName, fallback: Variant) -> Variant:
	if typeof(record) == TYPE_DICTIONARY:
		return (record as Dictionary).get(field, fallback)
	if record is Object:
		return record.get(field)
	return fallback
