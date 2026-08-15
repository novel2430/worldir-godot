class_name ChunkStreamingDemo
extends Node3D

@onready var world_root: Node3D = %WorldRoot
@onready var player: Node3D = %Player
@onready var prototype_catalog: PrototypeCatalog = %PrototypeCatalog
@onready var scene_runtime: SceneRuntime = %SceneRuntime
@onready var chunk_manager: ChunkManager = %ChunkManager
@onready var debug_label: Label = %ChunkDebugLabel

var base_ir: Dictionary = {}
var fake_revision := 0

func _ready() -> void:
	base_ir = _load_fixture_ir()
	if base_ir.is_empty():
		debug_label.text = "Chunk demo fixture failed to load"
		return
	chunk_manager.configure(prototype_catalog, scene_runtime, world_root, player)
	if player.has_method("set_chunk_manager"):
		player.call("set_chunk_manager", chunk_manager)
	chunk_manager.debug_state_changed.connect(_on_debug_state_changed)
	chunk_manager.chunk_generation_failed.connect(_on_chunk_generation_failed)
	if not chunk_manager.initialize_world(base_ir, 0, 1337, player.global_position):
		debug_label.text = "Chunk demo initialization failed"
		return
	_update_debug_text("WASD: move | F: fake preview revision | R: reload east preview")

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F:
		_fake_preview_revision()
	elif event.keycode == KEY_R:
		_reload_east_preview()

func _fake_preview_revision() -> void:
	fake_revision += 1
	var candidate_ir := base_ir.duplicate(true)
	for item: Dictionary in candidate_ir.get("distributions", []):
		if String(item.get("id", "")) != "trees":
			continue
		var population: Dictionary = item.get("population", {}).duplicate(true)
		population["amount"] = {"mode": "count", "value": maxi(2, 10 - fake_revision)}
		item["population"] = population
	var target := chunk_manager.get_current_chunk_coord() + Vector2i.RIGHT
	chunk_manager.register_revision_ir(fake_revision, candidate_ir)
	if chunk_manager.set_target_revision(target, fake_revision):
		chunk_manager.request_rebuild(target, fake_revision)
		_update_debug_text("Queued preview revision %d for %s" % [fake_revision, target])

func _reload_east_preview() -> void:
	var target := chunk_manager.get_current_chunk_coord() + Vector2i.RIGHT
	var record := chunk_manager.get_record(target)
	if record == null or record.resolved_chunk == null:
		return
	var signature := record.resolved_chunk.deterministic_signature()
	if not chunk_manager.unload_chunk(target):
		return
	var reloaded := chunk_manager.ensure_chunk(target)
	var stable := (
		reloaded != null
		and reloaded.resolved_chunk != null
		and reloaded.resolved_chunk.deterministic_signature() == signature
	)
	_update_debug_text("East preview reload deterministic: %s" % str(stable))

func _on_debug_state_changed(_snapshot: Dictionary) -> void:
	_update_debug_text()

func _on_chunk_generation_failed(coord: Vector2i, errors: PackedStringArray) -> void:
	_update_debug_text("Generation failed %s: %s" % [coord, " | ".join(errors)])

func _update_debug_text(message: String = "") -> void:
	var text := chunk_manager.debug_text()
	if not message.is_empty():
		text = "%s\n%s" % [message, text]
	debug_label.text = text

func _load_fixture_ir() -> Dictionary:
	var file := FileAccess.open("res://data/fixtures/coastal_town_initial.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var value: Variant = (parsed as Dictionary).get("world_ir", {})
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}
