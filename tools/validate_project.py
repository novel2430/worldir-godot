#!/usr/bin/env python3
from pathlib import Path
import json, re, sys

root = Path(__file__).resolve().parents[1]
required = [
    "project.godot", "scenes/main.tscn", "scripts/app/world_coordinator.gd",
    "scripts/backend/world_backend.gd", "scripts/runtime/scene_runtime.gd",
    "scripts/runtime/scene_transition.gd",
    "scripts/backend/backend_config.gd", "data/configs/backend.json",
    "scripts/backend/realization_policy.gd",
    "data/configs/artlab_realization_policy.json",
    "data/configs/artlab_realization_policy.schema.json",
    "scripts/backend/region_claim_resolver.gd",
    "scripts/backend/terrain_resolver.gd", "scripts/resolved/resolved_terrain.gd",
    "scripts/backend/coast_resolver.gd", "scripts/resolved/resolved_water.gd",
    "scripts/backend/forest_dresser.gd", "scripts/resolved/resolved_decoration.gd",
    "docs/artlab_realization_policy.md",
    "docs/artlab_realization_policy_schema.md",
    "docs/artlab_policy_changelog.md",
    "docs/artlab_visual_acceptance.md",
    "assets/prototypes/nature/tree_01.tscn", "assets/prototypes/nature/rock_01.tscn",
    "assets/prototypes/nature/bush_01.tscn", "assets/prototypes/nature/grass_01.tscn",
    "assets/prototypes/nature/dead_tree_01.tscn", "data/fixtures/coastal_town_initial.json",
    "tests/test_terrain_surface.gd",
    "tests/test_main_scene.gd",
    "tests/test_coast_water.gd",
    "tests/test_distribution_arrangement.gd",
    "tests/test_backend_config.gd",
    "tests/test_realization_policy.gd",
    "tests/test_chunk_dependency_closure.gd",
    "tests/test_artlab_policy_determinism.gd",
    "tests/test_artlab_scenario_matrix.gd",
    "tests/test_artlab_streaming_scale.gd",
    "tests/test_artlab_visual_calibration.gd",
    "tests/test_scene_diff.gd",
    "tests/test_coastal_town_houses.gd",
    "tests/test_region_claims.gd",
    "tests/test_scene_transition.gd",
    "tools/run_godot_tests.ps1",
    "tools/dump_artlab_policy.gd",
    "tools/benchmark_artlab_policy.gd",
    "tools/capture_artlab_matrix.gd",
]
missing = [p for p in required if not (root / p).exists()]
if missing:
    print("Missing:", *missing, sep="\n - ")
    sys.exit(1)

for p in (root / "data/configs").glob("*.json"):
    data = json.loads(p.read_text())
    assert isinstance(data, dict), p

policy_path = root / "data/configs/artlab_realization_policy.json"
policy = json.loads(policy_path.read_text())
policy_schema_path = root / "data/configs/artlab_realization_policy.schema.json"
policy_schema = json.loads(policy_schema_path.read_text())
assert policy.get("format") == "worldir-godot-artlab-realization-policy-v1"
assert policy.get("source", {}).get("scope") == "backend_owned_realization_only"
assert policy.get("source", {}).get("world_ir_contract_unchanged") is True
assert "res://" not in policy_path.read_text(), "Realization policy must not contain engine asset paths"
legal_region_types = {"town", "village", "forest", "coast", "graveyard", "district", "field", "swamp"}
for role_types in policy["terrain"]["region_roles"].values():
    assert set(role_types) <= legal_region_types, (policy_path, role_types)
assert set(policy["dressing"]["region_types"]) <= legal_region_types
assert set(policy["dressing"]["layers"]) == {"dead_tree", "rock", "bush", "grass"}
for layer_name, rule in policy["dressing"]["layers"].items():
    assert rule["target_area_per_candidate_m2"] > 0.0, (policy_path, layer_name)
    assert 0.0 <= rule["acceptance_probability"] <= 1.0, (policy_path, layer_name)
    assert rule["cap"] > 0, (policy_path, layer_name)

def _schema_target(reference):
    assert reference.startswith("#/$defs/"), (policy_schema_path, reference)
    return policy_schema["$defs"][reference.removeprefix("#/$defs/")]

def _validate_schema(value, schema, path="policy"):
    if "$ref" in schema:
        _validate_schema(value, _schema_target(schema["$ref"]), path)
        return
    if "const" in schema:
        assert value == schema["const"], (policy_path, path, "const", value)
    if "enum" in schema:
        assert value in schema["enum"], (policy_path, path, "enum", value)
    expected = schema.get("type")
    if expected == "object":
        assert isinstance(value, dict), (policy_path, path, "object")
        required = set(schema.get("required", []))
        assert required <= set(value), (policy_path, path, "missing", required - set(value))
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            assert set(value) <= set(properties), (policy_path, path, "unknown", set(value) - set(properties))
        for key, item in value.items():
            if key in properties:
                _validate_schema(item, properties[key], f"{path}.{key}")
    elif expected == "array":
        assert isinstance(value, list), (policy_path, path, "array")
        assert len(value) >= schema.get("minItems", 0), (policy_path, path, "minItems")
        if "maxItems" in schema:
            assert len(value) <= schema["maxItems"], (policy_path, path, "maxItems")
        if schema.get("uniqueItems"):
            assert len({json.dumps(item, sort_keys=True) for item in value}) == len(value), (policy_path, path, "uniqueItems")
        for index, item in enumerate(value):
            _validate_schema(item, schema.get("items", {}), f"{path}[{index}]")
    elif expected == "string":
        assert isinstance(value, str), (policy_path, path, "string")
        assert len(value) >= schema.get("minLength", 0), (policy_path, path, "minLength")
    elif expected == "boolean":
        assert isinstance(value, bool), (policy_path, path, "boolean")
    elif expected == "integer":
        assert isinstance(value, int) and not isinstance(value, bool), (policy_path, path, "integer")
    elif expected == "number":
        assert isinstance(value, (int, float)) and not isinstance(value, bool), (policy_path, path, "number")
    if expected in {"number", "integer"}:
        if "minimum" in schema:
            assert value >= schema["minimum"], (policy_path, path, "minimum", value)
        if "maximum" in schema:
            assert value <= schema["maximum"], (policy_path, path, "maximum", value)
        if "exclusiveMinimum" in schema:
            assert value > schema["exclusiveMinimum"], (policy_path, path, "exclusiveMinimum", value)

_validate_schema(policy, policy_schema)

geometry = policy["terrain"]["geometry"]
influences = policy["terrain"]["influences"]
surface = policy["surface"]
dressing = policy["dressing"]
assert geometry["forest_height_limit_m"] >= geometry["base_height_limit_m"]
assert influences["building_path_surface_inner_m"] < influences["building_path_surface_outer_m"]
assert influences["coast_beach_blend_start_m"] < influences["coast_beach_blend_end_m"]
assert surface["forest_soil_patch_start"] < surface["forest_soil_patch_end"]
assert surface["variation_min"] <= surface["variation_max"]
edge = dressing["edge_profiles"]["edge"]
interior = dressing["edge_profiles"]["interior"]
mixed = dressing["edge_profiles"]["mixed"]
assert edge["outer_ramp_start_m"] < edge["outer_ramp_end_m"]
assert edge["interior_falloff_start_m"] < edge["interior_falloff_end_m"]
assert interior["ramp_start_m"] < interior["ramp_end_m"]
assert mixed["falloff_start_m"] < mixed["falloff_end_m"]
clearing = dressing["building_clearing"]
assert clearing["minimum_inner_radius_m"] < clearing["minimum_outer_radius_m"]
assert clearing["footprint_inner_scale"] < clearing["footprint_outer_scale"]

# JSON and minimal CompileResult/WorldIR shape checks.
for p in (root / "data/fixtures").glob("*.json"):
    data = json.loads(p.read_text())
    assert data.get("status") in {"ok", "ir_gap"}, p
    if data.get("status") == "ok":
        ir = data.get("world_ir")
        assert isinstance(ir, dict), p
        for key in ("regions", "networks", "entities", "distributions"):
            assert isinstance(ir.get(key), list), (p, key)
        ids = {}
        for key in ("regions", "networks", "entities", "distributions"):
            for item in ir[key]:
                assert isinstance(item.get("id"), str) and item["id"], (p, item)
                assert item["id"] not in ids, (p, "duplicate id", item["id"])
                ids[item["id"]] = key
        for item in ir["networks"]:
            assert item.get("type") in {"road", "path"}, (p, item)
            assert isinstance(item.get("topology"), dict), (p, item)
        for key in ("regions", "networks", "entities", "distributions"):
            for item in ir[key]:
                for rel in item.get("placement", {}).get("relations", []):
                    target = rel.get("target")
                    if target:
                        assert target in ids, (p, "missing relation target", target)

# res:// references in scripts/scenes must exist.
refs = []
for p in list(root.rglob("*.tscn")) + list(root.rglob("*.gd")):
    text = p.read_text(errors="ignore")
    refs += [(p, m) for m in re.findall(r'res://[^\"\'\s)]+', text)]
bad = []
generated_output_prefixes = (
    "res://test-results/",
    "res://screenshots/artlab_matrix",
)
for src, ref in refs:
    if ref.startswith(generated_output_prefixes):
        continue
    q = root / ref.removeprefix("res://")
    if not q.exists():
        bad.append((src.relative_to(root), ref))
if bad:
    print("Broken res:// references:")
    for x in bad:
        print(" -", *x)
    sys.exit(2)

# TSCN internal resource IDs must resolve within their own file.
for p in root.rglob("*.tscn"):
    text = p.read_text()
    ext_defined = set(re.findall(r'\[ext_resource[^\]]* id="([^"]+)"\]', text))
    sub_defined = set(re.findall(r'\[sub_resource[^\]]* id="([^"]+)"\]', text))
    ext_used = set(re.findall(r'ExtResource\("([^"]+)"\)', text))
    sub_used = set(re.findall(r'SubResource\("([^"]+)"\)', text))
    assert ext_used <= ext_defined, (p, "undefined ExtResource", ext_used - ext_defined)
    assert sub_used <= sub_defined, (p, "undefined SubResource", sub_used - sub_defined)

print(
    "OK: project structure, JSON fixtures, WorldIR references, res:// paths, "
    "and TSCN resource references pass static validation."
)
