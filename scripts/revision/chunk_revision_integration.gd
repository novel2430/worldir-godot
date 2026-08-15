class_name ChunkRevisionIntegration
extends RefCounted

const ChunkRebasePlannerScript = preload("res://scripts/revision/chunk_rebase_planner.gd")

## Public A APIs consumed by the B revision layer. The last three methods are
## the Step 3 scene/install seams recorded in the Step 4 alignment notes.
const REQUIRED_PUBLIC_APIS: Array[String] = [
	"get_current_chunk_coord",
	"get_record",
	"get_active_records",
	"pin_chunk",
	"unpin_chunk",
	"generate_candidate",
	"set_generation_context",
	"set_target_revision",
	"request_rebuild",
	"ensure_latest",
	"get_chunk_root",
	"get_boundary_constraints",
	"install_resolved_candidate",
]

signal preview_rebuild_requested(coord: Vector2i, revision: int)
signal preview_rebuild_request_failed(coord: Vector2i, revision: int, reason: String)
signal entry_barrier_finished(coord: Vector2i, ready: bool, reason: String)

var chunk_manager: Variant = null
var last_commit_report: Dictionary = {}
var last_entry_error := ""

func configure(manager: Variant) -> void:
	chunk_manager = manager

func contract_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if chunk_manager == null:
		errors.append("ChunkManager is not configured")
		return errors
	for method_name in REQUIRED_PUBLIC_APIS:
		if not chunk_manager.has_method(method_name):
			errors.append("Missing ChunkManager public API: %s" % method_name)
	return errors

## Publish only after the Current transaction has committed. Authority is read
## again at this point because player/streaming lifecycle may have changed while
## the Compiler or transition was running. Streaming/visibility never affects
## the routing decision.
func publish_committed_revision(
	committed_revision: int,
	transaction_chunk_coord: Vector2i
) -> Dictionary:
	var report := {
		"revision": committed_revision,
		"target_latest": [],
		"preserve": [],
		"request_failures": [],
	}
	for record_value in chunk_manager.get_active_records():
		if not ChunkRebasePlannerScript.record_exists(record_value):
			continue
		var coord: Vector2i = ChunkRebasePlannerScript.coord(record_value)
		if coord == transaction_chunk_coord:
			continue
		if ChunkRebasePlannerScript.authority(record_value) != ChunkRebasePlannerScript.AUTHORITY_PROVISIONAL:
			report.preserve.append(coord)
			continue

		var target_result: Variant = chunk_manager.set_target_revision(coord, committed_revision)
		if not _call_succeeded(target_result):
			_record_request_failure(report, coord, committed_revision, "set_target_revision rejected")
			continue
		var updated: Variant = chunk_manager.get_record(coord)
		if ChunkRebasePlannerScript.target_revision(updated) != committed_revision:
			_record_request_failure(report, coord, committed_revision, "target revision was not installed")
			continue

		report.target_latest.append(coord)
		var rebuild_result: Variant = chunk_manager.request_rebuild(coord, committed_revision)
		if not _call_succeeded(rebuild_result):
			_record_request_failure(report, coord, committed_revision, "request_rebuild rejected")
			continue
		preview_rebuild_requested.emit(coord, committed_revision)

	last_commit_report = report
	return report

## This is a barrier hook, not a movement implementation. A's promotion
## lifecycle must await it (or provide equivalent behavior) before changing the
## Chunk's authority/current status.
func ensure_latest_before_entry(coord: Vector2i) -> bool:
	last_entry_error = ""
	var record_before: Variant = chunk_manager.get_record(coord)
	if not ChunkRebasePlannerScript.record_exists(record_before):
		return _finish_entry_barrier(coord, false, "ChunkRecord is unavailable")
	if not ChunkRebasePlannerScript.is_stale(record_before):
		return _finish_entry_barrier(coord, true, "")

	var ensure_result: Variant = await chunk_manager.ensure_latest(coord)
	if not _call_succeeded(ensure_result):
		return _finish_entry_barrier(coord, false, "ensure_latest failed")
	var record_after: Variant = chunk_manager.get_record(coord)
	if (
		not ChunkRebasePlannerScript.record_exists(record_after)
		or ChunkRebasePlannerScript.is_stale(record_after)
	):
		return _finish_entry_barrier(coord, false, "Chunk remains stale after ensure_latest")
	return _finish_entry_barrier(coord, true, "")

func _record_request_failure(
	report: Dictionary,
	coord: Vector2i,
	revision: int,
	reason: String
) -> void:
	report.request_failures.append({
		"coord": coord,
		"revision": revision,
		"reason": reason,
	})
	preview_rebuild_request_failed.emit(coord, revision, reason)

func _finish_entry_barrier(coord: Vector2i, ready: bool, reason: String) -> bool:
	last_entry_error = reason
	entry_barrier_finished.emit(coord, ready, reason)
	return ready

func _call_succeeded(result: Variant) -> bool:
	return typeof(result) != TYPE_BOOL or bool(result)
