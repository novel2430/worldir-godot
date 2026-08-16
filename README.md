# WorldIR Godot Backend V0

A GDScript-first Godot 4.7 project implementing the architecture baseline:

`Compiler Client → World State → Godot Backend → Resolved World → Scene Runtime`, coordinated transactionally by `WorldCoordinator`.

## Run immediately

1. Extract this folder.
2. Open `project.godot` in Godot 4.7.x.
3. Let Godot import resources.
4. Press **F6/F5** (run project).
5. The game opens on a non-semantic, completely flat grass canvas. The first successful prompt replaces it with the resolved OwenG world. Enable `auto_generate_demo` on `WorldCoordinator` to generate the fixed demo automatically instead.
6. Move with **WASD or arrow keys**, look with mouse, `Esc` releases mouse.

No external OwenG checkout or LLM server is required for the first run. Reusable OwenG art is namespaced under `assets/oweng/` and the active owner-aware policies use those local models and PBR ground textures.

## Demo edit flow

The compact translucent prompt card at the bottom left drives the same compile boundary that the real server will use. Before running, select `Main/UI/PromptPanel` in the Godot Editor and toggle the exported `Debug Mode` property. It defaults on; when off, the card collapses to the prompt row and only surfaces failed requests as `IR GAP`.

- The first fake compile returns the complete `coastal_forest`, `research_base`, and `snow_forest` fixture with one explicit path and Region-owned Entity/Distribution objects; failed compilation leaves the initial grass canvas untouched.
- Prompt `雪林里的石头少一点` (or an English equivalent containing “snow”, “rock”, and “less/fewer”) to change `snow_rocks` from high to medium density.
- Prompt `海岸森林的树多一点` (or an English equivalent containing “coastal”, “tree”, and “more”) to raise `coastal_trees` to high density.
- Other subsequent prompts echo the current IR, keeping the no-op Scene Diff / Transition path testable.
- Enter a prompt containing `50` to see an `ir_gap` response leave the world unchanged.

## Switching to the real compiler server

Select `Main/WorldCoordinator` in `scenes/main.tscn` and enable `use_http_compiler`, or change the exported property in the scene. `HttpCompilerClient` uses:

- `GET /health`
- `GET /info`
- `POST /v1/compile`

`WorldCoordinator` now exposes `compiler_base_url` and `compiler_timeout_seconds` in the Inspector. The default URL is `http://127.0.0.1:8787`.

## Adding another prototype

The backend resolves semantic types through PrototypeCatalog descriptors or existing TSCN prototypes; lowerers never own raw asset paths.

For another manually wrapped prototype:

1. Copy/import `tree_x.glb` under `assets/raw/`.
2. Create `assets/prototypes/tree_x.tscn` with a `StaticBody3D` root.
3. Instance the GLB scene as a child, add/adjust collision.
4. Attach `scripts/prototype/world_prototype.gd` to the root.
5. Set `prototype_id`, `semantic_type="tree"`, `placement_radius`, `clearance`.
6. Tune the optional population metadata: `population_spacing` controls visual density and
   `population_occupancy_scale` keeps only a core collision footprint as a hard exclusion.
7. Add the prototype path and semantic mapping in `scripts/prototype/prototype_catalog.gd`.

No placement/backend/runtime code needs to change.

The OwenG-aligned policies use migrated tree, grass, shrub, rock, prop, vehicle, and structure assets. Legacy prototype entries remain available only to existing low-level transition tests and are not active semantic-policy fallbacks.

## Current V0 implementation

Implemented:

- Strict World IR V2 / World Catalog V2 / Runtime Context V1 / CompileResult V1 contract validation at the Compiler boundary.
- World IR V2 root primitives: Region / Network / Entity / Distribution.
- Region anchor lowering to concrete polygons.
- A single Region with no anchor or relations falls back to the full playable-world domain; multi-Region worlds keep normal constrained lowering.
- Procedural `path` lowering to deterministic polyline/ribbon geometry.
- Fixed active vocabulary for OwenG-aligned Region, Network, Entity, and Distribution types.
- Exactly one owner Region is required for every Entity and Distribution; Region nesting is rejected.
- `RegionProfileCatalog` carries the terrain, surface, visual policy, path, lighting, atmosphere, and transition seams for the three Region types.
- Owner-aware prototype selection resolves `(semantic_type, owner_region_type)` to a compatible pool and rejects unsupported combinations.
- OwenG prototype descriptors wrap migrated GLTF/GLB resources with measured source bounds, scale corrections, placement/collision metadata, and license provenance for every active Distribution type and the supported Region-specific Entity set.
- One continuous 129×129 terrain blends gentle coastal relief, a controlled research-base grade, and rolling snow-forest terrain from final Region claim polygons.
- Normalized polygon-distance weights drive one continuous surface shader that blends OwenG CC0 grass, dirt, white-sand, and gray-gravel PBR albedo/normal/roughness textures without hard polygon color fills.
- One continuous Path ribbon samples the same weights per vertex, transitioning from forest dirt through industrial gravel to compacted snow.
- The single Sun and WorldEnvironment blend profile lighting/fog from player position; one shared dynamic sky shader continuously blends sky color, procedural cloud coverage, cloud tone, and wind across Regions, while one player-following snowfall emitter fades with snow-forest influence.
- Prototype-aware Entity placement.
- Distribution `count` / TSCN-footprint and usable-area-scaled qualitative `density` / `density_profile.gradient` weighted lowering.
- Explicit Distribution arrangements remain authoritative.
- `data/configs/backend.json` drives world size, default seed, spatial thresholds, and area-density realization parameters.
- Stable Resolved SceneDiff reports object-level added/removed/changed or moved/replaced/unchanged records for incremental transitions.
- Incremental World Rewrite transitions preserve unchanged Node identity; changed objects grow/fade/move/crossfade with bounded spatial stagger and a restrained local ground ripple.
- Distribution variants, yaw, candidates, clusters, and along-road slots use object-local deterministic streams; count changes preserve existing instance prefixes when spatial constraints remain compatible.
- OwenG presentation scale is calibrated above raw source size, while runtime collision boxes stay inset from measured visual bounds.
- Tree density treats overlapping canopies as normal forest composition: default coastal calibration is roughly `medium=54`, `high=136` before other-object occupancy.
- IR updates build only SceneDiff-added/replaced prototypes; population-only edits reuse the committed Terrain resource, while terrain-changing candidates are built in short frame slices.
- The default offline fixture is the complete three-Region OwenG world; fake-compiler prompts for fewer snow rocks or more coastal trees exercise stable population edits without an LLM server.
- Regions use deterministic bounded claims: anchors and relations establish seeds, configured area budgets limit spread, and same-layer Regions arbitrate contested ground without filling the world.
- Region profiles never create semantic objects; vegetation, rocks, and entities are realized only when explicitly present in IR.
- `inside`, `near`, `far_from`, `along`, `direction_of` placement operators.
- `random`, `uniform`, `clustered` arrangement.
- Runtime Binding `at` / `inside` / `near` lowering through Godot-local spatial payloads.
- Backend capability rejection when an owner-aware semantic pair has no compatible prototype (candidate world is not committed).
- Candidate scene construction before state commit.
- Fake compiler + HTTP compiler boundary.
- Playable first-person controller and collision.

Deliberately still simple:

- Region geometry uses lightly irregular deterministic polygons as mask domains; the current experiment uses a 500×500 m world on one bounded 97×97 terrain mesh, not a streaming/erosion terrain system.
- Roads bend lightly; terrain is graded beneath the core/shoulder, the ribbon is longitudinally densified, and both edges independently sample terrain. Topology routing remains a simple deterministic heuristic.
- Density gradient uses qualitative weighted sampling; it is intentionally not a numeric density-field solver.
- Path geometry changes currently use ripple-assisted crossfade rather than spline morphing; Terrain swaps its whole mesh at the ripple peak rather than chunking or vertex morphing.
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
godot --headless --path . --script tests/test_oweng_semantic_rebase.gd
godot --headless --path . --script tests/test_continuous_region_visuals.gd
godot --headless --path . --script tests/test_oweng_step03_closure.gd
godot --headless --path . --script tests/test_forest_dressing.gd
godot --headless --path . --script tests/test_road_builder.gd
godot --headless --path . --script tests/test_terrain_surface.gd
godot --headless --path . --script tests/test_main_scene.gd
godot --headless --path . --script tests/test_coast_water.gd
godot --headless --path . --script tests/test_distribution_arrangement.gd
godot --headless --path . --script tests/test_backend_config.gd
godot --headless --path . --script tests/test_scene_diff.gd
godot --headless --path . --script tests/test_coastal_town_houses.gd
godot --headless --path . --script tests/test_region_claims.gd
godot --headless --path . --script tests/test_scene_transition.gd
```

For a rendered Step 03 visual pass (requires a working display/OpenGL driver):

```bash
godot --path . --display-driver wayland --rendering-method gl_compatibility --audio-driver Dummy --script tools/capture_step03_visual.gd
```

The six captures are written to `screenshots/step03/` and include the snow-rock and coastal-tree edits before and after transition.

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
- Region profiles never dress a Region implicitly; every Entity and Distribution instance originates from explicit IR.
- Single-unconstrained-Region fallback exists only in Resolved geometry and never writes a synthetic placement back into World IR.

## Contract enforcement

The executable boundary validator lives in `scripts/compiler/contract_validator.gd`. Compiler requests/results are rejected before lowering when they violate the current World IR V2 / Runtime Context V1 / CompileResult V1 contract; structural validity and Godot asset capability are intentionally separate checks.
