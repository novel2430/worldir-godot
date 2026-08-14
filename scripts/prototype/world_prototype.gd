class_name WorldPrototype
extends StaticBody3D

@export var prototype_id: String = ""
@export var semantic_type: String = ""
@export_range(0.1, 100.0, 0.1) var placement_radius: float = 1.0
@export_range(0.0, 50.0, 0.1) var clearance: float = 0.25

func placement_clearance_radius() -> float:
    return placement_radius + clearance
