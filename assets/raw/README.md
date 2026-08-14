# Raw imported art

Put downloaded `.glb` / `.gltf` / textures here. Do **not** make the backend load raw GLB directly.
Wrap each imported model in a TSCN under `assets/prototypes/`, attach `world_prototype.gd` to the root `StaticBody3D`, and set `prototype_id`, `semantic_type`, `placement_radius`, and `clearance`.
