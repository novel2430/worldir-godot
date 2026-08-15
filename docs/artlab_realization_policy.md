# ArtLab Realization Policy

This document records how validated ArtLab generation findings enter the V1-A
Backend without becoming World IR or changing the Compiler/Runtime contracts.

Implementation baseline: `1372c875397ff1f829daa50277182caf6f9b05cf`.

## Boundary

The live policy source is:

```text
data/configs/artlab_realization_policy.json
```

It is Backend-owned realization data. It is not accepted by
`ContractValidator`, sent to the Compiler Server, stored in Runtime Facts, or
written back to World IR. Existing public method signatures on `WorldBackend`,
`ChunkGenerator`, `ChunkManager`, and `SceneRuntime` remain unchanged.

Precedence is fixed:

```text
explicit World IR semantics
    > resolved placement and prototype occupancy constraints
    > Backend-owned ArtLab realization policy
```

In particular, the policy never changes an explicit Distribution count,
arrangement, placement relation, or stable instance identity. Population rules
in this file apply to Backend-owned forest dressing only.

## Adopted findings

### Geometry and surface

Terrain macro/detail frequencies, forest relief, settlement flattening,
semantic Region blend widths, coast shaping, road/building influence widths,
and the current surface palette are now policy-driven. Built-in constants
remain compatibility fallbacks and match the checked-in policy defaults.

Region roles are selected only from existing legal World IR Region types. A
Chunk is not assigned one ArtLab profile: V1-A may contain several semantic
Regions in one 160m Chunk, so policy is resolved spatially from Region masks.

### Population and dressing

Backend forest dressing uses the ArtLab density interpretation:

```text
candidate area
× acceptance probability
× edge profile
× building clearing influence
× road/path corridor influence
× shared occupancy
→ realized decoration instances
```

The checked-in candidate areas are calibrated for the existing V1-A KayKit
prototype scale and 160m world frame. ArtLab's 48/64/80m experiment values are
evidence, not constants copied blindly into V1-A.

Building clearing radii scale from measured TSCN visual footprints. Roads and
paths retain their hard collision/clearance core, then use a smooth outer
corridor to avoid a visible straight population cutoff. Explicit semantic
Entities and Distributions continue to claim occupancy before dressing.

### Determinism

The policy introduces no mutable generation state. Geometry continues to use
the world seed; Chunk-local placement and dressing continue to use the existing
realization seed. Same inputs remain deterministic and generation-order
independent.

## Deliberately not adopted

The following require a separate approved contract/design change and are not
implemented here:

- `snow_forest`, `research_base`, or other profile IDs in World IR;
- biome, weather, lighting, atmosphere, or precipitation Compiler fields;
- arbitrary new ResolvedTerrain surface channels;
- cross-Chunk persistent-structure influence payloads;
- a new Resolved environment output consumed by a world lighting coordinator;
- ArtLab's fixed five-Chunk layout, lifecycle, mutation key, HUD, or evidence code.

Exact snow/biome selection cannot be expressed by the current four-root World
IR contract. Until that contract is intentionally extended, the policy only
improves realization of existing legal Region/Network/Entity/Distribution
semantics.

## Verification

```bash
python3 tools/validate_project.py
godot --headless --path . --script tests/test_realization_policy.gd
godot --headless --path . --script tests/test_forest_dressing.gd
godot --headless --path . --script tests/test_terrain_surface.gd
godot --headless --path . --script tests/test_chunk_generation.gd
godot --headless --path . --script tests/test_chunk_manager.gd
```

`test_realization_policy.gd` also guards the negative boundary: adding an
`environment` root to World IR must remain invalid.
