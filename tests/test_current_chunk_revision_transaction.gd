extends SceneTree

const CoordinatorScript = preload("res://scripts/revision/current_chunk_revision_coordinator.gd")
const FakeChunkGeneratorScript = preload("res://scripts/revision/fakes/fake_chunk_generator.gd")
const FakeChunkManagerScript = preload("res://scripts/revision/fakes/fake_chunk_manager.gd")
const FakeRevisionCompilerScript = preload("res://scripts/revision/fakes/fake_revision_compiler.gd")
const WorldStateScript = preload("res://scripts/app/world_state.gd")

var failures := 0
var _case_index := 0

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    await _test_successful_transaction_keeps_captured_target()
    await _test_prepare_failure("compile", FakeRevisionCompilerScript.MODE_ERROR, true, false, false)
    await _test_prepare_failure("ir_gap", FakeRevisionCompilerScript.MODE_IR_GAP, true, false, false)
    await _test_prepare_failure("generate", FakeRevisionCompilerScript.MODE_SUCCESS, false, true, false)
    await _test_prepare_failure("candidate_scene", FakeRevisionCompilerScript.MODE_SUCCESS, false, false, true)

    if failures == 0:
        print("Current Chunk Revision Transaction tests passed")
    quit(1 if failures > 0 else 0)

func _test_successful_transaction_keeps_captured_target() -> void:
    var harness := _create_harness()
    var coordinator: Node = harness.coordinator
    var compiler: Node = harness.compiler
    var manager: Variant = harness.manager
    var generator: Variant = harness.generator
    var state_store: WorldState = harness.state_store
    var c5_root: Node3D = harness.c5_root
    var c6_root: Node3D = harness.c6_root
    var record_before: Dictionary = manager.get_record(Vector2i(5, 5))
    var old_chunk: Resource = record_before.resolved_chunk
    var old_c5_active := c5_root.get_node("GeneratedChunk") as Node3D
    var old_c5_active_id := old_c5_active.get_instance_id()
    var stable_tree := old_c5_active.get_node("Distributions/trees/trees_000") as Node3D
    var stable_tree_id := stable_tree.get_instance_id()
    var removed_tree := old_c5_active.get_node("Distributions/trees/trees_009") as Node3D
    var c6_active := c6_root.get_node("GeneratedChunk") as Node3D
    var c6_active_id := c6_active.get_instance_id()

    var outcomes: Array[Dictionary] = []
    coordinator.transaction_finished.connect(func(success: bool, message: String) -> void:
        outcomes.append({"success": success, "message": message})
    )
    _expect(coordinator.submit_prompt("树少一点，房屋多一点"), "Prompt must start a transaction")
    _expect(manager.is_pinned(Vector2i(5, 5)), "Captured C5 must be pinned during compile")
    _expect(state_store.current_ir_revision == 0, "CAPTURE/COMPILE must not advance revision")
    _expect(record_before.resolved_chunk == old_chunk, "CAPTURE/COMPILE must not mutate ChunkRecord")

    manager.set_current_chunk_coord(Vector2i(6, 5))
    compiler.deliver()
    _expect(coordinator.state == "APPLY", "Valid Candidate must reach APPLY before commit")
    _expect(state_store.current_ir_revision == 0, "APPLY must begin before official revision advances")
    _expect(record_before.resolved_chunk == old_chunk, "APPLY must begin before official record install")
    var outcome := await _wait_for_outcome(outcomes)

    _expect(outcome.get("success", false), "IR0 -> IR1 transaction must succeed")
    _expect(coordinator.state_history == [
        "STABLE", "CAPTURE", "COMPILE", "PREPARE", "APPLY", "COMMIT", "STABLE",
    ], "Successful transaction must follow the required state flow")
    _expect(coordinator.last_transaction.transaction_chunk_coord == Vector2i(5, 5), "Transaction target must remain C5 after player moves to C6")
    _expect(manager.get_current_chunk_coord() == Vector2i(6, 5), "Test player Current must remain C6")
    _expect(not manager.is_pinned(Vector2i(5, 5)), "Successful transaction must unpin C5")
    _expect(state_store.current_ir_revision == 1, "Successful transition must commit revision 1")
    _expect(state_store.current_ir == _world_ir(5, 6), "Successful transition must commit Candidate IR1")
    _expect(state_store.runtime_facts.is_empty(), "Candidate runtime_fact_ops must commit after transition")
    _expect(not state_store.spatial_payloads.has("clearing_01"), "Committed cleared fact must prune its payload")

    var committed_record: Dictionary = manager.get_record(Vector2i(5, 5))
    _expect(committed_record.source_ir_revision == 1, "Installed target source revision must be 1")
    _expect(committed_record.target_ir_revision == 1, "Installed target target revision must be 1")
    _expect(committed_record.resolved_chunk.revision == 1, "Installed ResolvedChunk provenance must be 1")
    _expect(manager.get_record(Vector2i(6, 5)).source_ir_revision == 0, "C6 must not synchronously rebase")
    _expect(manager.get_record(Vector2i(6, 5)).target_ir_revision == 1, "C6 PROVISIONAL must target the committed revision")
    _expect(manager.rebuild_queue.get(Vector2i(6, 5)) == 1, "C6 rebuild must be deferred to A at revision 1")
    _expect(generator.calls.size() == 1, "Only the captured transaction target may generate synchronously")
    if generator.calls.size() == 1:
        var generation_call: Dictionary = generator.calls[0]
        _expect(generation_call.coord == Vector2i(5, 5), "GenerateChunk must receive captured C5")
        _expect(generation_call.ir_revision == 1, "GenerateChunk must receive Candidate revision 1")
        _expect(generation_call.world_seed == 7301, "GenerateChunk must receive the configured world seed")
        var overrides: Dictionary = generation_call.generation_overrides
        _expect(overrides.runtime_bindings.size() == 1, "Runtime binding must enter generation_overrides")
        _expect(overrides.spatial_payloads.has("clearing_01"), "Referenced spatial payload must enter generation_overrides")
        _expect(not state_store.current_ir.has("runtime_bindings"), "Overrides must not be written into World IR")

    var c5_after := c5_root.get_node("GeneratedChunk") as Node3D
    _expect(c5_after.get_instance_id() == old_c5_active_id, "Current Chunk rewrite must patch in place, not full refresh")
    _expect((c5_after.get_node("Distributions/trees/trees_000") as Node3D).get_instance_id() == stable_tree_id, "Stable tree identity must survive revision")
    _expect(not is_instance_valid(removed_tree), "Reduced tree count must animate removal")
    _expect(c5_after.has_node("Distributions/houses/houses_005"), "Increased house count must animate additions")
    _expect((c6_root.get_node("GeneratedChunk") as Node3D).get_instance_id() == c6_active_id, "C6 Scene must remain untouched")
    _expect(coordinator.last_patch.distribution_instances.removed.size() == 5, "Diff must remove only five excess trees")
    _expect(coordinator.last_patch.distribution_instances.added.size() == 4, "Diff must add only four new houses")

func _test_prepare_failure(
    label: String,
    compiler_mode: String,
    expect_no_generation: bool,
    fail_generation: bool,
    fail_scene_build: bool
) -> void:
    var harness := _create_harness()
    var coordinator: Node = harness.coordinator
    var compiler: Node = harness.compiler
    var manager: Variant = harness.manager
    var generator: Variant = harness.generator
    var state_store: WorldState = harness.state_store
    var c5_root: Node3D = harness.c5_root
    compiler.response_mode = compiler_mode
    generator.fail_generation = fail_generation
    generator.fail_scene_build = fail_scene_build

    var ir_before: Dictionary = state_store.current_ir.duplicate(true)
    var facts_before: Array = state_store.runtime_facts.duplicate(true)
    var payloads_before: Dictionary = state_store.spatial_payloads.duplicate(true)
    var record: Dictionary = manager.get_record(Vector2i(5, 5))
    var resolved_before: Resource = record.resolved_chunk
    var source_before: int = record.source_ir_revision
    var target_before: int = record.target_ir_revision
    var active_before := c5_root.get_node("GeneratedChunk") as Node3D
    var active_id := active_before.get_instance_id()
    var tree_count := active_before.get_node("Distributions/trees").get_child_count()
    var outcomes: Array[Dictionary] = []
    coordinator.transaction_finished.connect(func(success: bool, message: String) -> void:
        outcomes.append({"success": success, "message": message})
    )

    _expect(coordinator.submit_prompt("failure case %s" % label), "%s must start" % label)
    _expect(manager.is_pinned(Vector2i(5, 5)), "%s must pin C5" % label)
    compiler.deliver()
    var outcome := await _wait_for_outcome(outcomes)

    _expect(not outcome.get("success", true), "%s must abort" % label)
    _expect(coordinator.state == "STABLE", "%s must return to STABLE" % label)
    _expect(coordinator.last_transaction.state == "ABORTED", "%s transaction must be ABORTED" % label)
    _expect(not manager.is_pinned(Vector2i(5, 5)), "%s must unpin C5" % label)
    _expect(state_store.current_ir == ir_before, "%s must preserve current_ir" % label)
    _expect(state_store.current_ir_revision == 0, "%s must preserve revision" % label)
    _expect(state_store.runtime_facts == facts_before, "%s must preserve runtime facts" % label)
    _expect(state_store.spatial_payloads == payloads_before, "%s must preserve spatial payloads" % label)
    _expect(record.resolved_chunk == resolved_before, "%s must preserve official ResolvedChunk" % label)
    _expect(record.source_ir_revision == source_before, "%s must preserve source revision" % label)
    _expect(record.target_ir_revision == target_before, "%s must preserve target revision" % label)
    _expect((c5_root.get_node("GeneratedChunk") as Node3D).get_instance_id() == active_id, "%s must preserve old Chunk Scene root" % label)
    _expect(c5_root.get_node("GeneratedChunk/Distributions/trees").get_child_count() == tree_count, "%s must preserve old Chunk Scene objects" % label)
    if expect_no_generation:
        _expect(generator.calls.is_empty(), "%s must abort before GenerateChunk" % label)

func _create_harness() -> Dictionary:
    _case_index += 1
    var case_root := Node.new()
    case_root.name = "Step3Case%d" % _case_index
    root.add_child(case_root)

    var state_store := WorldStateScript.new()
    case_root.add_child(state_store)
    state_store.commit(_world_ir(10, 2), [])
    state_store.add_runtime_fact(_runtime_fact(), {"polygon": PackedVector2Array([
        Vector2(4.0, 4.0), Vector2(12.0, 4.0), Vector2(12.0, 12.0), Vector2(4.0, 12.0),
    ])})

    var catalog := PrototypeCatalog.new()
    case_root.add_child(catalog)
    var runtime := SceneRuntime.new()
    runtime.prototype_catalog = catalog
    runtime.scene_transition.duration_scale = 0.08
    case_root.add_child(runtime)
    var generator := FakeChunkGeneratorScript.new()
    var manager := FakeChunkManagerScript.new(generator)
    manager.set_current_chunk_coord(Vector2i(5, 5))
    var c5_root := Node3D.new()
    c5_root.name = "Chunk_5_5"
    case_root.add_child(c5_root)
    var c6_root := Node3D.new()
    c6_root.name = "Chunk_6_5"
    case_root.add_child(c6_root)
    var c5: Variant = generator.generate_chunk(Vector2i(5, 5), state_store.current_ir, 0, 7301, {}, {})
    var c6: Variant = generator.generate_chunk(Vector2i(6, 5), state_store.current_ir, 0, 7301, {}, {})
    manager.register_chunk(Vector2i(5, 5), "COMMITTED", c5, c5_root)
    manager.register_chunk(Vector2i(6, 5), "PROVISIONAL", c6, c6_root)
    runtime.mount_chunk(c5_root, c5)
    runtime.mount_chunk(c6_root, c6)
    generator.calls.clear()

    var compiler := FakeRevisionCompilerScript.new()
    compiler.result = _compile_result()
    case_root.add_child(compiler)
    var coordinator := CoordinatorScript.new()
    case_root.add_child(coordinator)
    coordinator.configure(state_store, compiler, manager, runtime, 7301)
    return {
        "state_store": state_store,
        "runtime": runtime,
        "generator": generator,
        "manager": manager,
        "compiler": compiler,
        "coordinator": coordinator,
        "c5_root": c5_root,
        "c6_root": c6_root,
    }

func _wait_for_outcome(outcomes: Array[Dictionary]) -> Dictionary:
    for _frame in range(600):
        if not outcomes.is_empty():
            return outcomes[0]
        await process_frame
    _expect(false, "Timed out waiting for transaction_finished")
    return {}

func _compile_result() -> Dictionary:
    return {
        "status": "ok",
        "world_ir": _world_ir(5, 6),
        "runtime_bindings": [{
            "ir_object_id": "houses",
            "runtime_fact_id": "clearing_01",
            "placement": "near",
        }],
        "runtime_fact_ops": [{"op": "clear", "runtime_fact_id": "clearing_01"}],
        "meta": {"request_id": "fake_step_3", "mode": "edit", "route": "deliberate"},
    }

func _world_ir(tree_count: int, house_count: int) -> Dictionary:
    return {
        "regions": [],
        "networks": [],
        "entities": [],
        "distributions": [
            {
                "id": "trees",
                "type": "tree",
                "population": {"amount": {"mode": "count", "value": tree_count}},
            },
            {
                "id": "houses",
                "type": "house",
                "population": {"amount": {"mode": "count", "value": house_count}},
            },
        ],
    }

func _runtime_fact() -> Dictionary:
    return {
        "id": "clearing_01",
        "kind": "marked_area",
        "mark": "cleared",
        "location": {"anchor": "center"},
        "affected_type": "tree",
        "count": 5,
    }

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    failures += 1
    push_error(message)
