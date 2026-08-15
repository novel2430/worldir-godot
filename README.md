# WorldIR Godot Backend V0

A GDScript-first Godot 4.7 project implementing the architecture baseline:

`Compiler Client → World State → Godot Backend → Resolved World → Scene Runtime`, coordinated transactionally by `WorldCoordinator`.

## Run immediately

1. Extract this folder.
2. Open `project.godot` in Godot 4.7.x.
3. Let Godot import resources.
4. Press **F6/F5** (run project).
5. The fake compiler automatically generates a playable coastal-town demo.
6. Move with **WASD or arrow keys**, look with mouse, `Esc` releases mouse.

No external 3D assets and no LLM server are required for the first run. The repository includes a small KayKit low-poly baseline plus local placeholder prototypes.

## Demo edit flow

The top-left panel drives the same compile boundary that the real server will use.

- Click **Create demo Runtime Fact: clearing_01**.
- Enter: `把我刚刚砍出来的地方变成墓地`
- The fake compiler returns `graveyard ↔ clearing_01`; Godot lowers the candidate and commits it.
- Enter: `恢复我刚刚砍掉的森林` to exercise `runtime_fact_ops.clear`.
- Enter a prompt containing `50` to see an `ir_gap` response leave the world unchanged.

## Switching to the real compiler server

Select `Main/WorldCoordinator` in `scenes/main.tscn` and enable `use_http_compiler`, or change the exported property in the scene. `HttpCompilerClient` uses:

- `GET /health`
- `GET /info`
- `POST /v1/compile`

`WorldCoordinator` now exposes `compiler_base_url` and `compiler_timeout_seconds` in the Inspector. The default URL is `http://127.0.0.1:8787`.

## Replacing placeholder art with GLB

The backend intentionally resolves semantic types to **TSCN prototypes**, not raw GLB.

For a real tree:

1. Copy/import `tree_x.glb` under `assets/raw/`.
2. Create `assets/prototypes/tree_x.tscn` with a `StaticBody3D` root.
3. Instance the GLB scene as a child, add/adjust collision.
4. Attach `scripts/prototype/world_prototype.gd` to the root.
5. Set `prototype_id`, `semantic_type="tree"`, `placement_radius`, `clearance`.
6. Tune the optional population metadata: `population_spacing` controls visual density and
   `population_occupancy_scale` keeps only a core collision footprint as a hard exclusion.
7. Add the prototype path and semantic mapping in `scripts/prototype/prototype_catalog.gd`.

No placement/backend/runtime code needs to change.

The current visual baseline uses CC0 KayKit Forest Nature models for six seeded tree
variations plus small rock, bush, grass, and bare-tree dressing sets. KayKit Medieval
Hexagon supplies two houses and one church. Only referenced GLTF/BIN/shared texture
files are stored under `assets/raw/kaykit/`; license texts are kept beside them.

## Current V0 implementation

Implemented:

- Strict World IR V2 / Runtime Context V1 / CompileResult V1 contract validation at the Compiler boundary.
- World IR V2 root primitives: Region / Network / Entity / Distribution.
- Region anchor lowering to concrete polygons.
- Procedural road/path lowering to deterministic polyline/ribbon geometry.
- Deterministic low-frequency macro terrain with forest/settlement/coast/road/building surface influences.
- One stylized world-surface shader blending meadow, forest floor, packed dirt, sand, and road dirt without photographic PBR textures.
- Boundary-touching Coast Regions resolve into deterministic shoreline geometry, submerged terrain, wet sand, foam, and a lightweight stylized ocean surface.
- Prototype-aware Entity placement.
- Distribution `count` / TSCN-footprint and usable-area-scaled qualitative `density` / `density_profile.gradient` weighted lowering.
- Resolved-polygon Forest Dressing with area-scaled, seeded edge vegetation, clustered rocks/bushes, rare bare-tree accents, and shared occupancy avoidance.
- `inside`, `near`, `far_from`, `along`, `direction_of` placement operators.
- `random`, `uniform`, `clustered` arrangement.
- Runtime Binding `at` / `inside` / `near` lowering through Godot-local spatial payloads.
- Backend capability rejection when a valid World Catalog V1 type has no Godot TSCN prototype (candidate world is not committed).
- Candidate scene construction before state commit.
- Fake compiler + HTTP compiler boundary.
- Playable first-person controller and collision.

Deliberately still simple:

- Region geometry uses lightly irregular deterministic polygons as mask domains; V0 terrain is one bounded 129×129 mesh, not a streaming/erosion terrain system.
- Roads bend lightly; terrain is graded beneath the core/shoulder, the ribbon is longitudinally densified, and both edges independently sample terrain. Topology routing remains a simple deterministic heuristic.
- Ocean V0 is opaque, bounded to world-edge Coast realization, and intentionally has no swimming, buoyancy, reflection probe, or transparent depth rendering.
- Density gradient uses qualitative weighted sampling; it is intentionally not a numeric density-field solver.
- Scene transition is an atomic rebuild/swap extension point, not a visual dissolve/growth effect yet.
- Runtime Fact gameplay aggregation is demonstrated by a deterministic demo fact, not tree-cutting gameplay.

## Smoke checks

Without Godot installed:

```bash
python3 tools/validate_project.py
```

With Godot 4.7 available:

```bash
godot --headless --path . --script tests/test_contract.gd
godot --headless --path . --script tests/test_backend.gd
godot --headless --path . --script tests/test_forest_dressing.gd
godot --headless --path . --script tests/test_road_builder.gd
godot --headless --path . --script tests/test_terrain_surface.gd
godot --headless --path . --script tests/test_main_scene.gd
godot --headless --path . --script tests/test_coast_water.gd
```

## Architecture invariants

- Backend never mutates SceneTree.
- Scene Runtime never interprets World IR semantic relations.
- Compiler Client only handles API/JSON contract.
- Prototype is chosen before placement; solver reads prototype layout metadata.
- Runtime spatial payload never goes to the Compiler Server.
- Compile response is a candidate until lowering + scene build succeeds.
- Resolved World contains value data, never live Node references.
- Resolved Terrain is backend value data; Runtime renders its heights and RGBA surface masks without re-reading World IR.
- Resolved Water is backend value data derived from a boundary-touching resolved Coast polygon; it never becomes a World IR object.
- Backend-owned dressing remains separate from IR-owned Distributions and runs only after explicit semantics claim occupancy.

## Contract enforcement

The executable boundary validator lives in `scripts/compiler/contract_validator.gd`. Compiler requests/results are rejected before lowering when they violate the current World IR V2 / Runtime Context V1 / CompileResult V1 contract; structural validity and Godot asset capability are intentionally separate checks.
