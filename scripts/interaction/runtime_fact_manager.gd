class_name RuntimeFactManager
extends Node

signal fact_created(fact: Dictionary, payload: Dictionary)

func create_demo_clearing() -> void:
    var fact := {
        "id": "clearing_01",
        "kind": "marked_area",
        "mark": "cleared",
        "location": {"inside": "forest", "anchor": "east"},
        "affected_type": "tree",
        "count": 23,
    }
    # Payload is Godot-local and intentionally never sent to the compiler.
    var payload := {
        "aabb2": {"x": -44.0, "z": -15.0, "w": 18.0, "d": 28.0},
        "center": {"x": -35.0, "z": -1.0},
        "affected_instance_ids": [],
    }
    fact_created.emit(fact, payload)
