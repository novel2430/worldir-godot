extends SceneTree

const OUTPUT_DIR := "res://screenshots/artlab_matrix"
const SCENARIOS := [
	{"id": "coastal_town", "fixture": "res://data/fixtures/coastal_town_initial.json"},
	{"id": "clearing_graveyard", "fixture": "res://data/fixtures/clearing_to_graveyard.json"},
	{"id": "restored_forest", "fixture": "res://data/fixtures/restore_forest.json"},
	{"id": "inland_village", "fixture": "res://data/fixtures/inland_forest_village.json"},
	{"id": "southern_coast", "fixture": "res://data/fixtures/southern_coast_hamlet.json"},
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var absolute_output := ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(absolute_output) != OK:
		push_error("Could not create matrix capture directory: %s" % absolute_output)
		quit(1)
		return
	var reports: Array = []
	for scenario: Dictionary in SCENARIOS:
		var result := await _capture_scenario(scenario)
		if result.is_empty():
			quit(1)
			return
		reports.append(result)
	var report := {
		"format": "worldir-godot-artlab-visual-matrix-v1",
		"policy_fingerprint": RealizationPolicy.new().fingerprint(),
		"seed": 1337,
		"camera": {
			"position": [365.0, 330.0, 365.0],
			"target": [80.0, 0.0, 80.0],
			"fov": 52.0,
		},
		"scenarios": reports,
	}
	var report_path := "%s/matrix_metrics.json" % OUTPUT_DIR
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write visual matrix metrics")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("Captured %d ArtLab scenario views to %s" % [reports.size(), absolute_output])
	quit(0)

func _capture_scenario(scenario: Dictionary) -> Dictionary:
	var fixture_path := String(scenario.fixture)
	var fixture := _load_json(fixture_path)
	var world_ir: Dictionary = fixture.get("world_ir", {})
	var errors := ContractValidator.new().validate_world_ir(world_ir)
	if not errors.is_empty():
		push_error("Scenario '%s' is invalid: %s" % [scenario.id, " | ".join(errors)])
		return {}

	var scenario_root := Node3D.new()
	scenario_root.name = String(scenario.id)
	root.add_child(scenario_root)
	_add_environment(scenario_root)

	var world_root := Node3D.new()
	world_root.name = "WorldRoot"
	scenario_root.add_child(world_root)
	var catalog := PrototypeCatalog.new()
	scenario_root.add_child(catalog)
	var runtime := SceneRuntime.new()
	scenario_root.add_child(runtime)
	var manager := ChunkManager.new()
	manager.auto_track_player = false
	scenario_root.add_child(manager)
	manager.configure(catalog, runtime, world_root)
	if not manager.initialize_world(world_ir, 0, 1337, Vector3(80.0, 4.0, 80.0)):
		push_error("Scenario '%s' could not initialize" % scenario.id)
		scenario_root.queue_free()
		return {}
	if manager.get_active_records().size() != 9:
		push_error("Scenario '%s' did not produce a 3x3 active window" % scenario.id)
		scenario_root.queue_free()
		return {}

	var camera := Camera3D.new()
	camera.current = true
	camera.position = Vector3(365.0, 330.0, 365.0)
	camera.fov = 52.0
	camera.far = 1800.0
	camera.look_at(Vector3(80.0, 0.0, 80.0), Vector3.UP)
	scenario_root.add_child(camera)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Scenario '%s' produced an empty viewport" % scenario.id)
		scenario_root.queue_free()
		return {}
	var image_path := "%s/%s.png" % [OUTPUT_DIR, scenario.id]
	if image.save_png(ProjectSettings.globalize_path(image_path)) != OK:
		push_error("Could not save %s" % image_path)
		scenario_root.queue_free()
		return {}
	var metrics := _metrics(manager)
	print("CAPTURED %s %s" % [image_path, JSON.stringify(metrics)])
	scenario_root.queue_free()
	await process_frame
	return {
		"id": String(scenario.id),
		"fixture": fixture_path,
		"image": image_path,
		"metrics": metrics,
	}

func _add_environment(parent: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.47, 0.51, 0.58)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.80, 0.84)
	environment.ambient_light_energy = 0.86
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	parent.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -35.0, 0.0)
	sun.light_energy = 0.84
	sun.shadow_enabled = true
	parent.add_child(sun)

func _metrics(manager: ChunkManager) -> Dictionary:
	var result := {
		"active_chunks": manager.get_active_records().size(),
		"entities": 0,
		"distribution_instances": 0,
		"decorations": 0,
		"warnings": 0,
	}
	for record: ChunkRecord in manager.get_active_records():
		var chunk := record.resolved_chunk
		result.entities += chunk.entities.size()
		result.warnings += chunk.warnings.size()
		for distribution: ResolvedDistribution in chunk.distributions:
			result.distribution_instances += distribution.instances.size()
		for decoration: ResolvedDecoration in chunk.decorations:
			result.decorations += decoration.instances.size()
	return result

func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
