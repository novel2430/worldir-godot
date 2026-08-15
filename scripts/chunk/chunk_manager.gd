class_name ChunkManager
extends Node

signal current_chunk_changed(old_coord: Vector2i, new_coord: Vector2i)
signal chunk_record_changed(record: ChunkRecord)
signal chunk_generation_failed(coord: Vector2i, errors: PackedStringArray)
signal preview_rebuild_completed(coord: Vector2i, revision: int)
signal debug_state_changed(snapshot: Dictionary)

@export var auto_track_player := true
@export var keep_dormant_mounted := true
@export var eviction_radius := 2
@export var debug_logging := false

var current_chunk_coord := Vector2i.ZERO
var world_seed := 1337
var chunks: Dictionary = {}

var player: Node3D = null
var world_root: Node3D = null
var prototype_catalog: PrototypeCatalog = null
var scene_runtime: SceneRuntime = null
var generator := ChunkGenerator.new()
var initialized := false
var _revision_ir: Dictionary = {}
var _pin_counts: Dictionary = {}
var _preview_queue: Dictionary = {}
var _latest_committed_ir: Dictionary = {}
var _latest_committed_revision := -1
var _preview_transition_in_flight := false
var _preview_transition_coord := Vector2i.ZERO

func configure(
	catalog: PrototypeCatalog,
	runtime: SceneRuntime = null,
	mount_root: Node3D = null,
	tracked_player: Node3D = null
) -> void:
	prototype_catalog = catalog
	scene_runtime = runtime
	world_root = mount_root
	player = tracked_player
	generator.configure(catalog)
	if scene_runtime != null:
		scene_runtime.prototype_catalog = catalog
		var finished_callable := Callable(self, "_on_chunk_transition_finished")
		if not scene_runtime.chunk_transition_finished.is_connected(finished_callable):
			scene_runtime.chunk_transition_finished.connect(finished_callable)

func _physics_process(_delta: float) -> void:
	if auto_track_player and initialized and player != null:
		update_player_world_position(player.global_position)

func _process(_delta: float) -> void:
	if (
		initialized
		and not _preview_queue.is_empty()
		and not _preview_transition_in_flight
	):
		process_preview_rebuilds(1)

func initialize_world(
	world_ir: Dictionary,
	ir_revision: int,
	seed_value: int,
	initial_world_position: Vector3 = Vector3.INF
) -> bool:
	if prototype_catalog == null:
		chunk_generation_failed.emit(
			Vector2i.ZERO,
			PackedStringArray(["ChunkManager requires a PrototypeCatalog"])
		)
		return false
	_latest_committed_ir = world_ir.duplicate(true)
	_latest_committed_revision = ir_revision
	world_seed = seed_value
	_revision_ir[ir_revision] = _latest_committed_ir.duplicate(true)
	var position := initial_world_position
	if position == Vector3.INF:
		position = player.global_position if player != null else Vector3.ZERO
	current_chunk_coord = ChunkMath.world_to_chunk(position)

	# Materialize and commit the center first. Preview generation may then consume
	# its committed boundary without depending on preview generation order.
	var center := _record_or_create(current_chunk_coord, ir_revision)
	if ensure_chunk(current_chunk_coord) == null:
		_reset_failed_initialization()
		return false
	center.authority = ChunkRecord.AuthorityState.COMMITTED
	center.streaming_state = ChunkRecord.StreamingState.ACTIVE
	initialized = true
	if not _refresh_active_window():
		_reset_failed_initialization()
		return false
	_emit_debug_state()
	return true

func set_generation_context(world_ir: Dictionary, ir_revision: int) -> void:
	# Called by B/WorldState only after its revision commit. ChunkManager keeps a
	# read-copy for future on-demand materialization; it is not revision authority.
	_latest_committed_ir = world_ir.duplicate(true)
	_latest_committed_revision = ir_revision
	_revision_ir[ir_revision] = _latest_committed_ir.duplicate(true)
	_emit_debug_state()

func register_revision_ir(ir_revision: int, world_ir: Dictionary) -> void:
	_revision_ir[ir_revision] = world_ir.duplicate(true)

func get_current_chunk_coord() -> Vector2i:
	return current_chunk_coord

func get_record(coord: Vector2i) -> ChunkRecord:
	return chunks.get(coord) as ChunkRecord

func get_active_records() -> Array[ChunkRecord]:
	var result: Array[ChunkRecord] = []
	for coord: Vector2i in ChunkMath.active_window_coords(current_chunk_coord):
		var record := get_record(coord)
		if record != null:
			result.append(record)
	return result

func get_chunk_root(coord: Vector2i) -> Node3D:
	if scene_runtime == null or world_root == null:
		return null
	return scene_runtime.get_mounted_chunk(world_root, coord)

func get_boundary_constraints(coord: Vector2i) -> Dictionary:
	var record := get_record(coord)
	if record == null or record.generation_constraints == null:
		return {}
	return record.generation_constraints.to_value().duplicate(true)

func pin_chunk(coord: Vector2i) -> bool:
	var record := get_record(coord)
	if record == null:
		return false
	_pin_counts[coord] = int(_pin_counts.get(coord, 0)) + 1
	_emit_debug_state()
	return true

func unpin_chunk(coord: Vector2i) -> bool:
	var count := int(_pin_counts.get(coord, 0))
	if count <= 0:
		return false
	if count == 1:
		_pin_counts.erase(coord)
	else:
		_pin_counts[coord] = count - 1
	_emit_debug_state()
	return true

func is_chunk_pinned(coord: Vector2i) -> bool:
	return int(_pin_counts.get(coord, 0)) > 0

func ensure_chunk(coord: Vector2i) -> ChunkRecord:
	var record := get_record(coord)
	if record != null and record.resolved_chunk != null:
		return record
	if record == null:
		record = _record_or_create(coord, _latest_committed_revision)

	var revision := record.target_ir_revision
	if revision < 0:
		revision = _latest_committed_revision
		record.set_target_revision(revision)
	var constraints := _boundary_constraints_for(coord)
	if record.source_ir_revision == revision and record.generation_constraints != null:
		constraints = record.generation_constraints.duplicate_constraints()
	var candidate: ResolvedChunk = null
	if (
		record.source_ir_revision == revision
		and record.committed_resolved_snapshot != null
	):
		candidate = record.committed_resolved_snapshot
	else:
		var generation_ir := _ir_for_revision(revision)
		if generation_ir.is_empty():
			_fail(coord, PackedStringArray(["No World IR registered for revision %d" % revision]))
			return null
		candidate = generator.generate_chunk(
			coord,
			generation_ir,
			revision,
			world_seed,
			constraints
		)
	if not candidate.errors.is_empty():
		_fail(coord, candidate.errors)
		return null
	# Build/mount is part of materialization PREPARE. Publish the candidate to
	# the formal record only after the scene path succeeds.
	if not _mount_candidate(candidate):
		return null
	record.accept_resolved(candidate)
	record.streaming_state = ChunkRecord.StreamingState.GEOMETRY_READY
	record.streaming_state = ChunkRecord.StreamingState.ENVIRONMENT_READY
	chunk_record_changed.emit(record)
	refresh_revision_boundary_visuals()
	return record

func set_target_revision(coord: Vector2i, target_revision: int) -> bool:
	var record := get_record(coord)
	if record == null:
		# Future/unmaterialized space must not create an unbounded revision table.
		return false
	record.set_target_revision(target_revision)
	chunk_record_changed.emit(record)
	_emit_debug_state()
	return true

func mark_stale(coord: Vector2i, target_revision: int) -> void:
	set_target_revision(coord, target_revision)

func generate_candidate(
	coord: Vector2i,
	world_ir: Dictionary,
	ir_revision: int,
	generation_overrides: Dictionary = {}
) -> ResolvedChunk:
	# PREPARE is deliberately record-free: a failed candidate cannot change any
	# official ChunkRecord or preview target.
	var candidate := generator.generate_chunk(
		coord,
		world_ir,
		ir_revision,
		world_seed,
		_boundary_constraints_for(coord),
		generation_overrides
	)
	if not candidate.errors.is_empty():
		_fail(coord, candidate.errors)
		return null
	return candidate

func request_rebuild(coord: Vector2i, ir_revision: int) -> bool:
	var record := get_record(coord)
	if record == null or record.target_ir_revision != ir_revision:
		return false
	if not _revision_ir.has(ir_revision):
		_fail(coord, PackedStringArray([
			"No World IR registered for revision %d" % ir_revision
		]))
		return false
	if not record.is_stale:
		_preview_queue.erase(coord)
		return true
	# Dictionary assignment coalesces queued work: the newest committed target
	# supersedes an older revision that has not started.
	_preview_queue[coord] = ir_revision
	_emit_debug_state()
	return true

func process_preview_rebuilds(max_count: int = 1) -> int:
	if _preview_transition_in_flight:
		return 0
	var processed := 0
	var coords: Array = _preview_queue.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i):
		var distance_a := ChunkMath.chebyshev_distance(a, current_chunk_coord)
		var distance_b := ChunkMath.chebyshev_distance(b, current_chunk_coord)
		return distance_a < distance_b or (
			distance_a == distance_b
			and (a.y < b.y or (a.y == b.y and a.x < b.x))
		)
	)
	for coord: Vector2i in coords:
		if processed >= maxi(0, max_count):
			break
		_preview_queue.erase(coord)
		var record := get_record(coord)
		if record == null or not record.is_stale:
			continue
		var revision := record.target_ir_revision
		var generation_ir := _ir_for_revision(revision)
		if generation_ir.is_empty():
			_fail(coord, PackedStringArray([
				"No World IR registered for target revision %d" % revision
			]))
			processed += 1
			continue
		var candidate := generate_candidate(coord, generation_ir, revision)
		processed += 1
		if candidate == null:
			continue
		# A newer commit may supersede work that was already running. Never accept
		# a now-obsolete preview candidate.
		if record.target_ir_revision != revision:
			request_rebuild(coord, record.target_ir_revision)
			continue
		var transition_mode := SceneRuntime.TRANSITION_MODE_SILENT
		if scene_runtime != null:
			transition_mode = scene_runtime.preview_transition_mode(
				current_chunk_coord,
				coord,
				get_chunk_root(coord)
			)
		if transition_mode == SceneRuntime.TRANSITION_MODE_LIGHT_REBASE:
			_preview_transition_in_flight = true
			_preview_transition_coord = coord
		if accept_rebuild(coord, candidate, true, transition_mode):
			preview_rebuild_completed.emit(coord, revision)
		elif transition_mode == SceneRuntime.TRANSITION_MODE_LIGHT_REBASE:
			_preview_transition_in_flight = false
		if _preview_transition_in_flight:
			break
	return processed

func accept_rebuild(
	coord: Vector2i,
	candidate: ResolvedChunk,
	mount_immediately := true,
	transition_mode: String = SceneRuntime.TRANSITION_MODE_SILENT
) -> bool:
	if candidate == null or candidate.coord != coord or not candidate.errors.is_empty():
		return false
	var record := get_record(coord)
	if record == null:
		record = _record_or_create(coord, candidate.revision)
	if record.target_ir_revision != candidate.revision:
		return false
	var previous := record.resolved_chunk
	if mount_immediately:
		var installed_scene := false
		if previous != null and get_chunk_root(coord) != null:
			installed_scene = _transition_rebuild_candidate(
				coord,
				previous,
				candidate,
				transition_mode
			)
		else:
			installed_scene = _mount_candidate(candidate)
		if not installed_scene:
			record.resolved_chunk = previous
			return false
	record.accept_resolved(candidate)
	if record.streaming_state == ChunkRecord.StreamingState.UNLOADED:
		record.streaming_state = ChunkRecord.StreamingState.ENVIRONMENT_READY
	chunk_record_changed.emit(record)
	_emit_debug_state()
	return true

func install_resolved_candidate(
	coord: Vector2i,
	resolved_chunk: ResolvedChunk,
	source_ir_revision: int,
	target_ir_revision: int
) -> bool:
	var record := get_record(coord)
	if (
		record == null
		or resolved_chunk == null
		or resolved_chunk.coord != coord
		or not resolved_chunk.errors.is_empty()
		or record.source_ir_revision != source_ir_revision
		or record.target_ir_revision != target_ir_revision
		or resolved_chunk.revision != target_ir_revision
	):
		return false
	record.accept_resolved(resolved_chunk)
	if record.streaming_state == ChunkRecord.StreamingState.UNLOADED:
		record.streaming_state = ChunkRecord.StreamingState.ENVIRONMENT_READY
	chunk_record_changed.emit(record)
	refresh_revision_boundary_visuals()
	_emit_debug_state()
	return true

func ensure_latest(coord: Vector2i) -> bool:
	var record := get_record(coord)
	if record == null:
		record = ensure_chunk(coord)
		return record != null and not record.is_stale
	if not record.is_stale and record.resolved_chunk != null:
		return true
	var target_ir := _ir_for_revision(record.target_ir_revision)
	if target_ir.is_empty():
		_fail(coord, PackedStringArray([
			"No World IR registered for target revision %d" % record.target_ir_revision
		]))
		return false
	var candidate := generate_candidate(coord, target_ir, record.target_ir_revision)
	if candidate == null:
		return false
	# Entry is a correctness barrier, not a background visual event. Install the
	# latest Candidate silently before promotion so old gameplay collision is
	# never authoritative under the player.
	return accept_rebuild(
		coord,
		candidate,
		true,
		SceneRuntime.TRANSITION_MODE_SILENT
	)

func prepare_player_entry(coord: Vector2i) -> bool:
	var record := get_record(coord)
	if record == null:
		record = ensure_chunk(coord)
	if record == null or not ensure_latest(coord):
		return false
	return _ensure_window_materialized(coord)

func update_player_world_position(world_position: Vector3) -> bool:
	var next_coord := ChunkMath.world_to_chunk(world_position)
	if next_coord == current_chunk_coord:
		return true
	var next_record := get_record(next_coord)
	if next_record == null:
		next_record = ensure_chunk(next_coord)
	if next_record == null:
		return false
	if (
		next_record.authority == ChunkRecord.AuthorityState.PROVISIONAL
		and next_record.target_ir_revision < _latest_committed_revision
	):
		next_record.set_target_revision(_latest_committed_revision)
	if not ensure_latest(next_coord):
		return false
	if not _ensure_window_materialized(next_coord):
		return false

	var old_coord := current_chunk_coord
	var old_record := get_record(old_coord)
	if old_record != null:
		old_record.streaming_state = ChunkRecord.StreamingState.ENVIRONMENT_READY
		old_record.authority = ChunkRecord.AuthorityState.COMMITTED
		chunk_record_changed.emit(old_record)

	current_chunk_coord = next_coord
	next_record.authority = ChunkRecord.AuthorityState.COMMITTED
	next_record.streaming_state = ChunkRecord.StreamingState.ACTIVE
	_apply_window_states()
	refresh_revision_boundary_visuals()
	current_chunk_changed.emit(old_coord, next_coord)
	_emit_debug_state()
	return true

func unload_chunk(coord: Vector2i) -> bool:
	var record := get_record(coord)
	if record == null or coord == current_chunk_coord or is_chunk_pinned(coord):
		return false
	if scene_runtime != null and world_root != null:
		scene_runtime.unmount_chunk(world_root, coord)
	record.resolved_chunk = null
	record.streaming_state = ChunkRecord.StreamingState.UNLOADED
	chunk_record_changed.emit(record)
	refresh_revision_boundary_visuals()
	_emit_debug_state()
	return true

func debug_snapshot() -> Dictionary:
	var records: Array = []
	var coords: Array = chunks.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i):
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	for coord: Vector2i in coords:
		var record := get_record(coord)
		records.append({
			"coord": [coord.x, coord.y],
			"streaming_state": record.streaming_state_name(),
			"authority": record.authority_name(),
			"source_ir_revision": record.source_ir_revision,
			"target_ir_revision": record.target_ir_revision,
			"is_stale": record.is_stale,
			"pin_count": int(_pin_counts.get(coord, 0)),
			"queued_revision": int(_preview_queue.get(coord, -1)),
		})
	return {
		"current_chunk_coord": [current_chunk_coord.x, current_chunk_coord.y],
		"current_ir_revision": _latest_committed_revision,
		"active_coords": _coord_values(ChunkMath.active_window_coords(current_chunk_coord)),
		"records": records,
		"preview_queue_size": _preview_queue.size(),
		"preview_transition_in_flight": _preview_transition_in_flight,
	}

func debug_text() -> String:
	var snapshot := debug_snapshot()
	var lines: PackedStringArray = PackedStringArray([
		"Current Chunk: (%d,%d)" % [current_chunk_coord.x, current_chunk_coord.y],
		"IR Revision: %d" % _latest_committed_revision,
		"Active Chunks: %d" % get_active_records().size(),
	])
	for record: Dictionary in snapshot.records:
		lines.append(
			"Chunk(%d,%d): %s / %s source=%d target=%d stale=%s"
			% [
				int(record.coord[0]),
				int(record.coord[1]),
				String(record.streaming_state),
				String(record.authority),
				int(record.source_ir_revision),
				int(record.target_ir_revision),
				str(record.is_stale),
			]
		)
	return "\n".join(lines)

func _refresh_active_window() -> bool:
	if not _ensure_window_materialized(current_chunk_coord):
		return false
	_apply_window_states()
	return true

func _ensure_window_materialized(center_coord: Vector2i) -> bool:
	for coord: Vector2i in ChunkMath.active_window_coords(center_coord):
		if ensure_chunk(coord) == null:
			return false
	return true

func _apply_window_states() -> void:
	var desired := {}
	for coord: Vector2i in ChunkMath.active_window_coords(current_chunk_coord):
		desired[coord] = true
		var record := get_record(coord)
		if coord == current_chunk_coord:
			record.streaming_state = ChunkRecord.StreamingState.ACTIVE
			record.authority = ChunkRecord.AuthorityState.COMMITTED
		elif record.streaming_state != ChunkRecord.StreamingState.UNLOADED:
			record.streaming_state = ChunkRecord.StreamingState.ENVIRONMENT_READY
		chunk_record_changed.emit(record)

	for coord: Vector2i in chunks.keys():
		if desired.has(coord):
			continue
		var record := get_record(coord)
		record.streaming_state = ChunkRecord.StreamingState.DORMANT
		chunk_record_changed.emit(record)
		if (
			not keep_dormant_mounted
			and ChunkMath.chebyshev_distance(coord, current_chunk_coord) > eviction_radius
		):
			unload_chunk(coord)

func _record_or_create(coord: Vector2i, target_revision: int) -> ChunkRecord:
	var record := get_record(coord)
	if record != null:
		return record
	record = ChunkRecord.new().configure(coord, -1, target_revision)
	chunks[coord] = record
	chunk_record_changed.emit(record)
	return record

func _boundary_constraints_for(coord: Vector2i) -> ChunkBoundaryConstraints:
	var constraints := ChunkBoundaryConstraints.new()
	var neighbor_specs := [
		{"edge": "north", "neighbor": coord + Vector2i(0, -1), "neighbor_edge": "south"},
		{"edge": "south", "neighbor": coord + Vector2i(0, 1), "neighbor_edge": "north"},
		{"edge": "west", "neighbor": coord + Vector2i(-1, 0), "neighbor_edge": "east"},
		{"edge": "east", "neighbor": coord + Vector2i(1, 0), "neighbor_edge": "west"},
	]
	for spec: Dictionary in neighbor_specs:
		var neighbor := get_record(spec.neighbor)
		if (
			neighbor == null
			or neighbor.authority != ChunkRecord.AuthorityState.COMMITTED
			or neighbor.resolved_chunk == null
		):
			continue
		var edge := String(spec.edge)
		var neighbor_edge := String(spec.neighbor_edge)
		constraints.set_terrain_heights(
			edge,
			_terrain_edge(neighbor.resolved_chunk, neighbor_edge)
		)
		for road_exit: Dictionary in _road_exits(neighbor.resolved_chunk, neighbor_edge):
			constraints.add_road_exit(edge, road_exit)
	return constraints

func _terrain_edge(chunk: ResolvedChunk, edge: String) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if chunk.terrain == null:
		return result
	var grid_size: int = chunk.terrain.grid_size
	result.resize(grid_size)
	for offset in range(grid_size):
		var x_index := offset
		var z_index := 0
		match edge:
			"south": z_index = grid_size - 1
			"west":
				x_index = 0
				z_index = offset
			"east":
				x_index = grid_size - 1
				z_index = offset
		result[offset] = chunk.terrain.heights[z_index * grid_size + x_index]
	return result

func _road_exits(chunk: ResolvedChunk, edge: String) -> Array:
	var result: Array = []
	var edge_coordinate := _edge_coordinate(chunk.bounds, edge)
	for network: ResolvedNetwork in chunk.networks:
		if network.curve_points.size() < 2:
			continue
		var candidates := [
			{"point": network.curve_points[0], "inside": network.curve_points[1]},
			{"point": network.curve_points[-1], "inside": network.curve_points[-2]},
		]
		for candidate: Dictionary in candidates:
			var point: Vector3 = candidate.point
			var point2 := Vector2(point.x, point.z)
			if absf(_edge_component(point2, edge) - edge_coordinate) > 0.05:
				continue
			var inside: Vector3 = candidate.inside
			var tangent := (point2 - Vector2(inside.x, inside.z)).normalized()
			result.append({
				"id": network.id,
				"semantic_type": network.semantic_type,
				"position": point2,
				"tangent": tangent,
				"width": network.width,
			})
	return result

func _mount_candidate(candidate: ResolvedChunk) -> bool:
	if scene_runtime == null or world_root == null:
		return true
	var existing := scene_runtime.get_mounted_chunk(world_root, candidate.coord)
	var chunk_root := scene_runtime.get_or_create_chunk_root(world_root, candidate.coord)
	var mounted := scene_runtime.mount_chunk(chunk_root, candidate, prototype_catalog)
	if mounted == null:
		if existing == null:
			scene_runtime.unmount_chunk(world_root, candidate.coord)
		_fail(candidate.coord, PackedStringArray(["SceneRuntime failed to mount Chunk"]))
		return false
	return true

func _transition_rebuild_candidate(
	coord: Vector2i,
	previous: ResolvedChunk,
	candidate: ResolvedChunk,
	transition_mode: String
) -> bool:
	if scene_runtime == null:
		return true
	var chunk_root := get_chunk_root(coord)
	if chunk_root == null:
		return _mount_candidate(candidate)
	var prepared := scene_runtime.prepare_chunk_transition(
		previous,
		candidate,
		prototype_catalog
	)
	if prepared.is_empty():
		return false
	var candidate_scene := prepared.get("candidate_scene") as Node3D
	if candidate_scene == null:
		scene_runtime.discard_prepared_chunk_transition(prepared)
		return false
	scene_runtime.reconcile_revision_boundaries(
		get_active_records(),
		_active_chunk_roots(),
		{coord: candidate},
		{coord: candidate_scene}
	)
	var result: Variant = scene_runtime.apply_prepared_preview_transition(
		chunk_root,
		candidate,
		prepared,
		transition_mode
	)
	if typeof(result) != TYPE_DICTIONARY:
		scene_runtime.discard_prepared_chunk_transition(prepared)
		return false
	chunk_root.set_meta("chunk_coord", coord)
	chunk_root.set_meta("ir_revision", candidate.revision)
	return true

func refresh_revision_boundary_visuals() -> Dictionary:
	if scene_runtime == null:
		return {}
	return scene_runtime.reconcile_revision_boundaries(
		get_active_records(),
		_active_chunk_roots()
	)

func _active_chunk_roots() -> Dictionary:
	var roots := {}
	for record: ChunkRecord in get_active_records():
		var chunk_root := get_chunk_root(record.coord)
		if chunk_root != null:
			roots[record.coord] = chunk_root
	return roots

func _on_chunk_transition_finished(coord: Vector2i, mode: String) -> void:
	if (
		mode == SceneRuntime.TRANSITION_MODE_LIGHT_REBASE
		and _preview_transition_in_flight
		and coord == _preview_transition_coord
	):
		_preview_transition_in_flight = false
		_preview_transition_coord = Vector2i.ZERO
		_emit_debug_state()

func _ir_for_revision(revision: int) -> Dictionary:
	var value: Variant = _revision_ir.get(revision, {})
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}

func _edge_coordinate(bounds: Rect2, edge: String) -> float:
	return bounds.position.y if edge == "north" else (
		bounds.end.y if edge == "south" else (
			bounds.position.x if edge == "west" else bounds.end.x
		)
	)

func _edge_component(point: Vector2, edge: String) -> float:
	return point.y if edge == "north" or edge == "south" else point.x

func _coord_values(coords: Array[Vector2i]) -> Array:
	var result: Array = []
	for coord in coords:
		result.append([coord.x, coord.y])
	return result

func _fail(coord: Vector2i, errors: PackedStringArray) -> void:
	chunk_generation_failed.emit(coord, errors)

func _reset_failed_initialization() -> void:
	if scene_runtime != null and world_root != null:
		for coord: Vector2i in chunks.keys():
			scene_runtime.unmount_chunk(world_root, coord)
	chunks.clear()
	_revision_ir.clear()
	_pin_counts.clear()
	_preview_queue.clear()
	_latest_committed_ir = {}
	_latest_committed_revision = -1
	_preview_transition_in_flight = false
	_preview_transition_coord = Vector2i.ZERO
	current_chunk_coord = Vector2i.ZERO
	initialized = false

func _emit_debug_state() -> void:
	var snapshot := debug_snapshot()
	debug_state_changed.emit(snapshot)
	if debug_logging:
		print(debug_text())
