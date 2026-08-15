extends SceneTree

var failures := 0

func _init() -> void:
	var blend := RevisionBoundaryBlend.new()
	var historical_chunk := _chunk(Vector2i.ZERO, 0, 8, true)
	var latest_chunk := _chunk(Vector2i.RIGHT, 1, 1, false)
	var historical := ChunkRecord.new().configure(Vector2i.ZERO, 0, 0)
	historical.accept_resolved(historical_chunk)
	historical.authority = ChunkRecord.AuthorityState.COMMITTED
	var latest := ChunkRecord.new().configure(Vector2i.RIGHT, 1, 1)
	latest.accept_resolved(latest_chunk)
	latest.authority = ChunkRecord.AuthorityState.COMMITTED
	var historical_source := historical.source_ir_revision
	var historical_target := historical.target_ir_revision
	var historical_authority := historical.authority

	var plan := blend.build_plan([historical, latest])
	_expect(float(plan.transition_band_m) == 16.0, "Revision transition band must be 16m")
	_expect((plan.pairs as Array).size() == 1, "Different adjacent revisions must produce one boundary pair")
	_expect(not (plan.operations as Array).is_empty(), "Higher-density side must receive deterministic visual thinning")

	var historical_root := _scene_root(historical_chunk)
	var latest_root := _scene_root(latest_chunk)
	root.add_child(historical_root)
	root.add_child(latest_root)
	blend.apply_plan(plan, {
		Vector2i.ZERO: historical_root,
		Vector2i.RIGHT: latest_root,
	})
	var faded_count := 0
	for node in historical_root.get_node("GeneratedWorld/Distributions/trees").get_children():
		var mesh := node.get_node("Visual") as MeshInstance3D
		if mesh.transparency > 0.001:
			faded_count += 1
	_expect(faded_count > 0, "Boundary plan must affect rendered regenerable population")

	_expect(historical.authority == historical_authority, "Blend must not change Historical authority")
	_expect(historical.source_ir_revision == historical_source, "Blend must not change Historical source revision")
	_expect(historical.target_ir_revision == historical_target, "Blend must not change Historical target revision")
	_expect(latest.source_ir_revision == 1 and latest.target_ir_revision == 1, "Blend must not change latest provenance")

	var same_revision := _chunk(Vector2i.RIGHT, 0, 1, false)
	latest.accept_resolved(same_revision)
	var no_boundary_plan := blend.build_plan([historical, latest])
	_expect((no_boundary_plan.pairs as Array).is_empty(), "Equal revisions must not create a revision boundary")

	if failures == 0:
		print("Revision boundary visual blend tests passed")
	quit(1 if failures > 0 else 0)

func _chunk(coord: Vector2i, revision: int, count: int, west_side: bool) -> ResolvedChunk:
	var chunk := ResolvedChunk.new()
	chunk.coord = coord
	chunk.revision = revision
	chunk.bounds = ChunkMath.chunk_bounds(coord)
	var distribution := ResolvedDistribution.new()
	distribution.id = "trees"
	distribution.semantic_type = "tree"
	for index in range(count):
		var x := (
			chunk.bounds.end.x - 1.0 - float(index % 4) * 2.0
			if west_side
			else chunk.bounds.position.x + 1.0 + float(index % 4) * 2.0
		)
		distribution.instances.append({
			"id": "tree:%03d" % index,
			"prototype_id": "tree",
			"transform": Transform3D(Basis.IDENTITY, Vector3(x, 0.0, chunk.bounds.position.y + 20.0 + index)),
		})
	chunk.distributions.append(distribution)
	return chunk

func _scene_root(chunk: ResolvedChunk) -> Node3D:
	var chunk_root := Node3D.new()
	chunk_root.name = "Chunk_%d_%d" % [chunk.coord.x, chunk.coord.y]
	var content := Node3D.new()
	content.name = SceneRuntime.CHUNK_CONTENT_NAME
	chunk_root.add_child(content)
	for layer_name in ["Entities", "Distributions", "Decorations"]:
		var layer := Node3D.new()
		layer.name = layer_name
		content.add_child(layer)
	var group := Node3D.new()
	group.name = "trees"
	content.get_node("Distributions").add_child(group)
	for instance: Dictionary in (chunk.distributions[0] as ResolvedDistribution).instances:
		var node := Node3D.new()
		node.name = String(instance.id).replace(":", "_")
		var mesh := MeshInstance3D.new()
		mesh.name = "Visual"
		node.add_child(mesh)
		group.add_child(node)
	return chunk_root

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
