class_name WorldPrototype
extends StaticBody3D

@export var prototype_id: String = ""
@export var semantic_type: String = ""
@export_range(0.1, 100.0, 0.1) var placement_radius: float = 1.0
@export_range(0.0, 50.0, 0.1) var clearance: float = 0.25

# Population density uses the scene's measured XZ footprint. These two values
# describe the parts geometry cannot tell us: desired visual spacing and how
# much of the collision footprint must remain a hard placement exclusion.
@export_range(0.0, 100.0, 0.1) var population_spacing: float = 2.0
@export_range(0.1, 1.0, 0.05) var population_occupancy_scale: float = 0.75
@export var population_footprint_override: Vector2 = Vector2.ZERO

func placement_clearance_radius() -> float:
    return placement_radius + clearance
