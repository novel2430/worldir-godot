# Godot Backend Contract V0

This is the implementation-facing contract extracted from the architecture baseline.

## Input

`WorldBackend.lower(world_ir, prototype_catalog, seed, runtime_bindings, spatial_payloads)`

The backend receives semantic World IR and Godot-local runtime context. It may read prototype placement metadata but must not instantiate or mutate SceneTree nodes.

## Output

A `ResolvedWorld` containing only value data:

- region polygons;
- network curve points and widths;
- entity prototype IDs and `Transform3D`;
- distribution instance IDs, prototype IDs and `Transform3D`.

No live `Node`, `RID`, `MeshInstance3D`, or `CollisionObject3D` reference belongs in Resolved World.

## Lowering order

1. World frame.
2. Regions.
3. Networks.
4. Prototype choice.
5. Entities.
6. Distributions.
7. Validation/warnings.

## Placement operators implemented

- `anchor`
- `inside`
- `near`
- `far_from`
- `along`
- `direction_of`

Prototype radius + clearance participates in occupancy checks. Region and road spatial occupation come from resolved polygon / curve+width rather than guessed object footprints.

## Runtime boundary

`SceneRuntime` consumes only Resolved World and Prototype Catalog. It does not parse `near`, `inside`, `along`, or other World IR semantics.

The coordinator treats every compile result as a candidate until backend lowering and candidate scene construction succeed. Only then are Current IR and Runtime Facts committed.
