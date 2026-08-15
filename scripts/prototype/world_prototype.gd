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
@export_range(0.5, 2.0, 0.01) var population_scale_min: float = 1.0
@export_range(0.5, 2.0, 0.01) var population_scale_max: float = 1.0
@export_range(0.0, 1.0, 0.01) var population_landmark_chance: float = 0.0
@export_range(1.0, 2.0, 0.01) var population_landmark_scale: float = 1.0

# Optional roadside realization hints. They affect only explicit Distributions
# with an `along` relation and never become World IR semantics.
@export_range(0.0, 20.0, 0.1) var roadside_setback: float = 1.0
@export_range(0.0, 45.0, 0.5) var roadside_yaw_jitter_degrees: float = 0.0

func placement_clearance_radius() -> float:
    return placement_radius + clearance
