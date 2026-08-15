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

`population.arrangement` is authoritative when present. The backend's seeded Forest naturalization profile is an allowed realization default only when arrangement is absent; explicit `random`, `clustered`, and `uniform` select their corresponding placement paths without that profile.

`data/configs/backend.json` is the live backend realization policy source for world size/default seed, relation distance thresholds, bounded Region claim budgets, unspecified population budget, and area-density spacing/packing/cap parameters. Built-in constants are validation fallbacks, not a second active configuration path.

When the world contains exactly one Region and that Region has neither an anchor nor placement relations, V0 resolves its polygon to the playable world bounds. This is a backend-only spatial fallback: it does not mutate World IR, and it is not applied to unconstrained Regions in multi-Region worlds.

Region relation dependencies are calculated before their dependents when the dependency graph is acyclic, while `ResolvedWorld.regions` retains World IR order. Provisional geometry establishes a deterministic seed for each Region; `RegionClaimResolver` then expands a bounded organic claim using the configured semantic area budget. Same-layer overlap is resolved by an order-independent power score (`budget - distance²`), so Regions compete only where their finite claims meet and unclaimed base terrain may remain between them.

An unanchored Region whose sole relation is `near` another Region derives its seed after the target seed is available. For a boundary Coast, this places the source on the resolved landward side. `inside` is not same-layer competition: the child claim is clipped to the final parent polygon, while the parent retains its complete semantic domain. Runtime-bound polygons and the single-unconstrained-Region whole-world fallback remain exact rather than being reshaped by claim policy.

## Runtime boundary

`SceneRuntime` consumes only Resolved World and Prototype Catalog. It does not parse `near`, `inside`, `along`, or other World IR semantics.

The coordinator treats every compile result as a candidate until backend lowering and candidate scene construction succeed. Initial generation is committed atomically. Subsequent candidates are compared with the active `ResolvedWorld`, applied as an incremental Scene patch, and only then committed to Current IR and Runtime Facts.

## Resolved diff boundary

`SceneDiff` compares old and new `ResolvedWorld` values, never their source IR. Region, Network, Entity, Water, Distribution instance, and Decoration instance identity is matched by resolved ID. Float, polygon, curve, terrain, and transform comparisons use a small epsilon.

Distribution instance IDs remain `<distribution_id>:<index>`. Prototype/scale/yaw/candidate randomness is derived from world seed + semantic object ID + instance index, while along-road and uniform placement use prefix-stable slots. Shared occupancy remains authoritative, so a real spatial conflict may still move a later object.

`SceneTransition` consumes this diff. `unchanged` records retain their exact live Node; `added`, `removed`, `moved`, and `replaced` records receive local animation with bounded spatial staggering. Region/Network/Water changes crossfade concrete geometry, while Terrain swaps its whole mesh near the peak of a local rewrite ripple. Player, camera, and unrelated world Nodes live outside the patched generated layers and are never recreated.
