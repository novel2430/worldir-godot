extends SceneTree

const DEFAULT_FIXTURE := "res://data/fixtures/coastal_town_initial.json"
const DEFAULT_OUTPUT := "res://test-results/artlab-policy-diagnostics.json"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var options := _options()
	var fixture_path := String(options.get("fixture", DEFAULT_FIXTURE))
	var output_path := String(options.get("output", DEFAULT_OUTPUT))
	var seed_value := int(options.get("seed", 1337))
	var fixture := _load_json(fixture_path)
	var world_ir: Dictionary = fixture.get("world_ir", {})
	var validation_errors := ContractValidator.new().validate_world_ir(world_ir)
	if not validation_errors.is_empty():
		push_error("Diagnostic fixture is invalid: %s" % " | ".join(validation_errors))
		quit(1)
		return

	var catalog := PrototypeCatalog.new()
	root.add_child(catalog)
	var manager := ChunkManager.new()
	manager.auto_track_player = false
	root.add_child(manager)
	manager.configure(catalog)
	if not manager.initialize_world(world_ir, 0, seed_value, Vector3(80.0, 4.0, 80.0)):
		push_error("Could not initialize diagnostic 3x3 world")
		quit(1)
		return

	var policy := RealizationPolicy.new()
	var chunks: Array = []
	var totals := {"entities": 0, "distribution_instances": 0, "decorations": 0}
	for record: ChunkRecord in manager.get_active_records():
		var chunk := record.resolved_chunk
		var chunk_report := _chunk_report(chunk, policy)
		chunks.append(chunk_report)
		totals.entities += int(chunk_report.counts.entities)
		totals.distribution_instances += int(chunk_report.counts.distribution_instances)
		totals.decorations += int(chunk_report.counts.decorations)
	chunks.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.coord[1]) < int(b.coord[1]) or (
			int(a.coord[1]) == int(b.coord[1]) and int(a.coord[0]) < int(b.coord[0])
		)
	)

	var report := {
		"format": "worldir-godot-artlab-diagnostics-v1",
		"fixture": fixture_path,
		"seed": seed_value,
		"policy": policy.diagnostic_snapshot(),
		"active_chunks": chunks.size(),
		"totals": totals,
		"chunks": chunks,
	}
	if not _write_json(output_path, report):
		quit(1)
		return
	print("ARTLAB_DIAGNOSTICS %s" % JSON.stringify({
		"output": output_path,
		"active_chunks": chunks.size(),
		"totals": totals,
		"policy_fingerprint": policy.fingerprint(),
	}))
	manager.free()
	catalog.free()
	quit(0)

func _chunk_report(chunk: ResolvedChunk, policy: RealizationPolicy) -> Dictionary:
	var region_roles := {
		"forest_surface": policy.string_array("terrain.region_roles.forest_surface", []),
		"settlement_surface": policy.string_array("terrain.region_roles.settlement_surface", []),
		"coast_surface": policy.string_array("terrain.region_roles.coast_surface", []),
	}
	var regions: Array = []
	for region: ResolvedRegion in chunk.regions:
		var roles: Array[String] = []
		for role_name in region_roles:
			if region.semantic_type in region_roles[role_name]:
				roles.append(String(role_name))
		regions.append({"id": region.id, "type": region.semantic_type, "roles": roles})

	var distributions: Array = []
	var distribution_instance_count := 0
	for distribution: ResolvedDistribution in chunk.distributions:
		distribution_instance_count += distribution.instances.size()
		distributions.append({
			"id": distribution.id,
			"type": distribution.semantic_type,
			"instances": distribution.instances.size(),
		})
	var decorations: Array = []
	var decoration_count := 0
	for decoration: ResolvedDecoration in chunk.decorations:
		decoration_count += decoration.instances.size()
		decorations.append({
			"id": decoration.id,
			"type": decoration.decoration_type,
			"region_id": decoration.region_id,
			"instances": decoration.instances.size(),
		})

	var samples: Array = []
	for uv in [Vector2(0.25, 0.25), Vector2(0.5, 0.5), Vector2(0.75, 0.75)]:
		var point := chunk.bounds.position + chunk.bounds.size * uv
		var mask: Color = chunk.terrain.sample_surface_mask(point)
		samples.append({
			"world_xz": [point.x, point.y],
			"height_m": chunk.terrain.sample_height(point),
			"surface": {
				"forest": mask.r,
				"settlement": mask.g,
				"coast": mask.b,
				"road_or_building": mask.a,
			},
			"shore_wetness": chunk.terrain.sample_shore_wetness(point),
		})
	return {
		"coord": [chunk.coord.x, chunk.coord.y],
		"revision": chunk.revision,
		"realization_seed": chunk.realization_seed,
		"regions": regions,
		"networks": chunk.networks.map(func(network: ResolvedNetwork): return {
			"id": network.id,
			"type": network.semantic_type,
			"width_m": network.width,
		}),
		"distributions": distributions,
		"decoration_layers": decorations,
		"terrain_samples": samples,
		"counts": {
			"entities": chunk.entities.size(),
			"distribution_instances": distribution_instance_count,
			"decorations": decoration_count,
		},
		"warnings": Array(chunk.warnings),
	}

func _options() -> Dictionary:
	var result := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or "=" not in argument:
			continue
		var parts := argument.trim_prefix("--").split("=", true, 1)
		result[String(parts[0])] = String(parts[1])
	return result

func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _write_json(path: String, value: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		push_error("Could not create diagnostic output directory: %s" % absolute.get_base_dir())
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write diagnostic output: %s" % path)
		return false
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	return true
