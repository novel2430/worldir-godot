extends SceneTree

const ChunkRevisionIntegrationScript = preload("res://scripts/revision/chunk_revision_integration.gd")
const FakeChunkGeneratorScript = preload("res://scripts/revision/fakes/fake_chunk_generator.gd")
const FakeChunkManagerScript = preload("res://scripts/revision/fakes/fake_chunk_manager.gd")
const WorldStateScript = preload("res://scripts/app/world_state.gd")

const CURRENT := Vector2i(5, 5)
const PREVIEW := Vector2i(6, 5)
const HISTORICAL := Vector2i(4, 5)

var failures := 0
var _case_index := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_public_contract_shape()
	_test_provisional_stale_and_historical_preserve()
	await _test_revision_coalescing_generates_latest_only()
	_test_preview_failure_isolated_from_committed_revision()
	await _test_player_entry_barrier_blocks_stale_promotion()
	_test_future_first_generation_uses_latest_committed_ir()

	if failures == 0:
		print("Step 4 Provisional Revision tests passed")
	quit(1 if failures > 0 else 0)

func _test_public_contract_shape() -> void:
	var harness := _create_harness()
	var integration: Variant = harness.integration
	_expect(
		integration.contract_errors().is_empty(),
		"ChunkManager test double must expose every public A API consumed by B"
	)

func _test_provisional_stale_and_historical_preserve() -> void:
	var harness := _create_harness()
	var integration: Variant = harness.integration
	var manager: Variant = harness.manager
	var historical_before: Dictionary = manager.get_record(HISTORICAL).duplicate(true)

	var report: Dictionary = integration.publish_committed_revision(1, CURRENT)
	var preview: Dictionary = manager.get_record(PREVIEW)
	var historical: Dictionary = manager.get_record(HISTORICAL)

	_expect(preview.source_ir_revision == 0, "Preview source must remain installed IR0")
	_expect(preview.target_ir_revision == 1, "Preview target must advance to committed IR1")
	_expect(
		preview.source_ir_revision != preview.target_ir_revision,
		"Preview stale state must derive from source != target"
	)
	_expect(manager.rebuild_queue.get(PREVIEW) == 1, "Preview rebuild must be queued, not run synchronously")
	_expect(report.target_latest == [PREVIEW], "Only PROVISIONAL must route to TARGET_LATEST")
	_expect(report.preserve == [HISTORICAL], "Historical COMMITTED must route to PRESERVE")
	_expect(historical == historical_before, "Historical metadata and ResolvedChunk must remain unchanged")
	_expect(
		not _has_coord(manager.target_revision_calls, HISTORICAL),
		"B must never request latest target for Historical COMMITTED"
	)

func _test_revision_coalescing_generates_latest_only() -> void:
	var harness := _create_harness()
	var integration: Variant = harness.integration
	var manager: Variant = harness.manager
	var generator: Variant = harness.generator
	manager.register_revision_world(1, _world_ir(8, 4))
	manager.register_revision_world(2, _world_ir(4, 8))

	integration.publish_committed_revision(1, CURRENT)
	_expect(manager.get_record(PREVIEW).target_ir_revision == 1, "First commit must target IR1")
	integration.publish_committed_revision(2, CURRENT)
	_expect(manager.get_record(PREVIEW).source_ir_revision == 0, "Queued Preview may remain at IR0")
	_expect(manager.get_record(PREVIEW).target_ir_revision == 2, "Second commit must coalesce target directly to IR2")
	_expect(manager.rebuild_queue.get(PREVIEW) == 2, "Latest-wins queue must supersede queued IR1")

	generator.calls.clear()
	var ready: bool = await integration.ensure_latest_before_entry(PREVIEW)
	_expect(ready, "Entry barrier must be able to materialize latest target")
	_expect(generator.calls.size() == 1, "Coalesced Preview must generate only once")
	if generator.calls.size() == 1:
		_expect(generator.calls[0].ir_revision == 2, "Coalesced Preview must generate IR2, never replay IR1")
		_expect(generator.calls[0].generation_overrides.is_empty(), "Preview rebuild must not inherit transaction bindings")
	_expect(manager.get_record(PREVIEW).source_ir_revision == 2, "Successful ensure_latest must install IR2")
	_expect(manager.get_record(PREVIEW).target_ir_revision == 2, "Successful ensure_latest must clear derived stale state")

func _test_preview_failure_isolated_from_committed_revision() -> void:
	var harness := _create_harness()
	var integration: Variant = harness.integration
	var manager: Variant = harness.manager
	var state_store := WorldStateScript.new()
	root.add_child(state_store)
	state_store.commit(_world_ir(10, 2), [])
	state_store.commit(_world_ir(8, 4), [])
	manager.rebuild_failure_coords[PREVIEW] = true

	var report: Dictionary = integration.publish_committed_revision(1, CURRENT)
	_expect(state_store.current_ir_revision == 1, "Preview request failure must not roll back global IR1")
	_expect(manager.get_record(CURRENT).source_ir_revision == 0, "Preview failure must not mutate the Current record")
	_expect(manager.get_record(PREVIEW).source_ir_revision == 0, "Failed Preview must retain installed IR0")
	_expect(manager.get_record(PREVIEW).target_ir_revision == 1, "Failed Preview must remain stale for retry")
	_expect(report.request_failures.size() == 1, "Preview request failure must be observable")

func _test_player_entry_barrier_blocks_stale_promotion() -> void:
	var harness := _create_harness()
	var integration: Variant = harness.integration
	var manager: Variant = harness.manager
	manager.register_revision_world(1, _world_ir(8, 4))
	integration.publish_committed_revision(1, CURRENT)
	manager.ensure_latest_failure_coords[PREVIEW] = true

	var ready: bool = await integration.ensure_latest_before_entry(PREVIEW)
	_expect(not ready, "Entry barrier must reject a Chunk when ensure_latest fails")
	_expect(manager.get_record(PREVIEW).authority == "PROVISIONAL", "B barrier must not promote authority")
	_expect(manager.get_record(PREVIEW).source_ir_revision == 0, "Rejected entry must leave stale source installed")
	_expect(manager.ensure_latest_calls == [PREVIEW], "Stale entry must call A.ensure_latest exactly once")

	manager.ensure_latest_failure_coords.erase(PREVIEW)
	ready = await integration.ensure_latest_before_entry(PREVIEW)
	_expect(ready, "Entry barrier may release only after latest is installed")
	_expect(
		manager.get_record(PREVIEW).source_ir_revision == manager.get_record(PREVIEW).target_ir_revision,
		"Barrier success requires source == target"
	)
	_expect(manager.get_record(PREVIEW).authority == "PROVISIONAL", "Authority promotion remains A-owned")

func _test_future_first_generation_uses_latest_committed_ir() -> void:
	var harness := _create_harness()
	var manager: Variant = harness.manager
	var generator: Variant = harness.generator
	var state_store := WorldStateScript.new()
	root.add_child(state_store)
	state_store.commit(_world_ir(10, 2), [])
	state_store.commit(_world_ir(8, 4), [])
	var future_coord := Vector2i(9, 9)
	_expect(manager.get_record(future_coord).is_empty(), "Future Chunk must not have a pre-created revision record")

	generator.calls.clear()
	var future: Variant = manager.generate_chunk(
		future_coord,
		state_store.current_ir,
		state_store.current_ir_revision,
		7301,
		{},
		{}
	)
	_expect(future != null, "Future Chunk must materialize from latest committed state")
	_expect(future.revision == 1, "Future first generation must use committed IR1 revision")
	_expect(generator.calls[0].world_ir == state_store.current_ir, "Future generation must receive latest committed IR")
	_expect(generator.calls[0].generation_overrides.is_empty(), "Future must not inherit transaction-local overrides")

func _create_harness() -> Dictionary:
	_case_index += 1
	var case_root := Node.new()
	case_root.name = "Step4Case%d" % _case_index
	root.add_child(case_root)
	var generator := FakeChunkGeneratorScript.new()
	var manager := FakeChunkManagerScript.new(generator)
	manager.world_seed = 7301
	manager.set_current_chunk_coord(CURRENT)
	var ir0 := _world_ir(10, 2)
	_register_chunk(case_root, manager, generator, CURRENT, "COMMITTED", ir0, 0)
	_register_chunk(case_root, manager, generator, PREVIEW, "PROVISIONAL", ir0, 0)
	_register_chunk(case_root, manager, generator, HISTORICAL, "COMMITTED", ir0, 0)
	generator.calls.clear()
	var integration := ChunkRevisionIntegrationScript.new()
	integration.configure(manager)
	return {
		"generator": generator,
		"manager": manager,
		"integration": integration,
	}

func _register_chunk(
	case_root: Node,
	manager: Variant,
	generator: Variant,
	coord: Vector2i,
	authority: String,
	world_ir: Dictionary,
	revision: int
) -> void:
	var chunk_root := Node3D.new()
	chunk_root.name = "Chunk_%d_%d" % [coord.x, coord.y]
	case_root.add_child(chunk_root)
	var resolved: Variant = generator.generate_chunk(coord, world_ir, revision, 7301, {}, {})
	manager.register_chunk(coord, authority, resolved, chunk_root)

func _has_coord(calls: Array[Dictionary], coord: Vector2i) -> bool:
	for call in calls:
		if call.get("coord") == coord:
			return true
	return false

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

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
