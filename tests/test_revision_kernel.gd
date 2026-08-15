extends SceneTree

const ChunkRebasePlannerScript = preload("res://scripts/revision/chunk_rebase_planner.gd")
const RevisionTransactionScript = preload("res://scripts/revision/revision_transaction.gd")
const WorldStateScript = preload("res://scripts/app/world_state.gd")

var failures := 0

func _init() -> void:
    _test_authority_policy_ignores_streaming_state()
    _test_transaction_target_is_captured_at_submission()
    _test_revision_plan_classification()
    _test_candidate_abort_is_isolated()
    _test_successful_commit_advances_exactly_once()
    _test_stale_is_derived_from_revisions()

    if failures == 0:
        print("Revision kernel tests passed")
    quit(1 if failures > 0 else 0)

func _test_authority_policy_ignores_streaming_state() -> void:
    var target := _record(Vector2i(5, 5), "COMMITTED", 0, 0)
    target["streaming_state"] = "DORMANT"
    target["visible"] = false
    _expect(
        ChunkRebasePlannerScript.can_rebase(target, Vector2i(5, 5)),
        "Transaction Target COMMITTED must be rebaseable"
    )

    var provisional := _record(Vector2i(6, 5), "PROVISIONAL", 0, 0)
    provisional["streaming_state"] = "ENVIRONMENT_READY"
    provisional["visible"] = true
    _expect(
        ChunkRebasePlannerScript.can_rebase(provisional, Vector2i(5, 5)),
        "PROVISIONAL must be rebaseable even when loaded and visible"
    )

    var historical := _record(Vector2i(4, 5), "COMMITTED", 0, 0)
    historical["streaming_state"] = "ACTIVE"
    historical["visible"] = true
    _expect(
        not ChunkRebasePlannerScript.can_rebase(historical, Vector2i(5, 5)),
        "Historical COMMITTED must be preserved regardless of streaming state"
    )

func _test_transaction_target_is_captured_at_submission() -> void:
    var player_current := Vector2i(5, 5)
    var transaction := RevisionTransactionScript.new()
    transaction.capture(0, player_current)
    player_current = Vector2i(6, 5)

    var plan: Variant = transaction.prepare(
        {"name": "IR1"},
        [
            _record(Vector2i(5, 5), "COMMITTED", 0, 0),
            _record(Vector2i(6, 5), "COMMITTED", 0, 0),
        ]
    )
    _expect(player_current == Vector2i(6, 5), "Test setup must move Current to C6")
    _expect(
        transaction.transaction_chunk_coord == Vector2i(5, 5),
        "Transaction target must remain the Prompt submission Chunk C5"
    )
    _expect(
        plan.must_rebase == [Vector2i(5, 5)],
        "Captured C5, not later Current C6, must be MUST_REBASE"
    )
    _expect(
        plan.preserve == [Vector2i(6, 5)],
        "Later Current C6 is historical to this transaction policy snapshot"
    )

func _test_revision_plan_classification() -> void:
    var records := [
        _record(Vector2i(5, 5), "COMMITTED", 2, 2),
        _record(Vector2i(6, 5), "PROVISIONAL", 2, 2),
        _record(Vector2i(5, 6), "PROVISIONAL", 1, 2),
        _record(Vector2i(4, 5), "COMMITTED", 0, 0),
    ]
    var records_before: Array = records.duplicate(true)
    var plan: Variant = ChunkRebasePlannerScript.build_plan(2, 3, Vector2i(5, 5), records)

    _expect(plan.from_revision == 2, "Plan must retain from_revision")
    _expect(plan.candidate_revision == 3, "Plan must retain candidate_revision")
    _expect(plan.must_rebase == [Vector2i(5, 5)], "Current target must be MUST_REBASE")
    _expect(
        plan.target_latest == [Vector2i(6, 5), Vector2i(5, 6)],
        "All non-target PROVISIONAL records must be TARGET_LATEST"
    )
    _expect(plan.preserve == [Vector2i(4, 5)], "Historical COMMITTED must be PRESERVE")
    _expect(
        plan.future_policy == "USE_LATEST_ON_FIRST_GENERATION",
        "Unmaterialized Future must require no immediate record or action"
    )
    _expect(records == records_before, "Building a RevisionPlan must not mutate official records")
    _expect(not plan.to_debug_string().is_empty(), "RevisionPlan must be printable")

func _test_candidate_abort_is_isolated() -> void:
    var world_state := WorldStateScript.new()
    world_state.commit({"name": "IR0"}, [{"id": "fact_0"}])
    var official_records := [
        _record(Vector2i(5, 5), "COMMITTED", 0, 0),
        _record(Vector2i(6, 5), "PROVISIONAL", 0, 0),
    ]
    var records_before: Array = official_records.duplicate(true)
    var ir_before: Dictionary = world_state.current_ir.duplicate(true)
    var facts_before: Array = world_state.runtime_facts.duplicate(true)

    var transaction := RevisionTransactionScript.new()
    transaction.capture(
        world_state.current_ir_revision,
        Vector2i(5, 5)
    )
    var external_candidate := {"name": "IR1", "nested": {"density": "low"}}
    transaction.prepare(external_candidate, official_records)
    external_candidate["nested"]["density"] = "high"

    _expect(world_state.current_ir == ir_before, "Prepared candidate must not replace current_ir")
    _expect(world_state.current_ir_revision == 0, "Prepared candidate must not advance revision")
    _expect(world_state.runtime_facts == facts_before, "Prepared candidate must not commit facts")
    _expect(official_records == records_before, "Prepared candidate must not mutate ChunkRecords")
    _expect(
        transaction.candidate_ir["nested"]["density"] == "low",
        "Candidate state must be isolated from caller mutation"
    )

    transaction.abort()
    _expect(transaction.state == "ABORTED", "Abort must end candidate transaction")
    _expect(transaction.candidate_ir == null, "Abort must discard candidate IR")
    _expect(world_state.current_ir == ir_before, "Abort must leave current_ir unchanged")
    _expect(world_state.current_ir_revision == 0, "Abort must leave official revision unchanged")
    _expect(official_records == records_before, "Abort must leave official ChunkRecords unchanged")
    world_state.free()

func _test_successful_commit_advances_exactly_once() -> void:
    var world_state := WorldStateScript.new()
    _expect(world_state.current_ir_revision == -1, "Uninitialized WorldState must have no committed revision")
    world_state.commit({"name": "IR0"}, [])
    _expect(world_state.current_ir_revision == 0, "Initial successful commit must become revision 0")

    var transaction := RevisionTransactionScript.new()
    transaction.capture(0, Vector2i(5, 5))
    transaction.prepare({"name": "IR1"}, [])
    _expect(transaction.commit_to(world_state), "Prepared transaction must commit")
    _expect(world_state.current_ir_revision == 1, "Successful edit must advance revision to 1")
    _expect(world_state.current_ir["name"] == "IR1", "Successful edit must commit candidate IR")
    _expect(not transaction.commit_to(world_state), "Transaction must not commit twice")
    _expect(world_state.current_ir_revision == 1, "Rejected second commit must not advance revision")
    world_state.free()

func _test_stale_is_derived_from_revisions() -> void:
    _expect(
        not ChunkRebasePlannerScript.is_stale(_record(Vector2i.ZERO, "PROVISIONAL", 2, 2)),
        "Equal source/target revisions must not be stale"
    )
    _expect(
        ChunkRebasePlannerScript.is_stale(_record(Vector2i.ZERO, "PROVISIONAL", 1, 2)),
        "Different source/target revisions must be stale"
    )

func _record(
    coord: Vector2i,
    authority: String,
    source_revision: int,
    target_revision: int
) -> Dictionary:
    return {
        "coord": coord,
        "authority": authority,
        "source_ir_revision": source_revision,
        "target_ir_revision": target_revision,
    }

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    failures += 1
    push_error(message)
