extends SceneTree

var failures := 0

func _init() -> void:
    _run.call_deferred()

func _run() -> void:
    var scene := load("res://scenes/main.tscn") as PackedScene
    _expect(scene != null, "Main scene must load")
    if scene == null:
        quit(1)
        return
    var main := scene.instantiate() as Node3D
    var coordinator := main.get_node("WorldCoordinator") as WorldCoordinator
    coordinator.use_http_compiler = false
    coordinator.auto_generate_demo = true
    # PromptPanel intentionally resolves through SceneTree.current_scene, which
    # is not populated when a test manually attaches an instance under root.
    main.get_node("UI").free()
    root.add_child(main)
    await process_frame
    await process_frame
    _expect(coordinator.current_resolved != null, "Fake compiler must commit the demo world")
    if coordinator.current_resolved != null:
        _expect(coordinator.current_resolved.terrain != null, "Committed demo must include resolved terrain")
        _expect(main.get_node_or_null("WorldRoot/GeneratedWorld/Terrain/WorldSurface") != null, "Committed scene must contain the world surface")
        _expect(main.get_node_or_null("BaseGround") == null, "Legacy flat base ground must stay removed")
    main.free()
    if failures == 0:
        print("Main scene smoke test passed")
    quit(1 if failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    failures += 1
    push_error(message)
