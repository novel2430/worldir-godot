#!/usr/bin/env python3
from pathlib import Path
import json, re, sys

root = Path(__file__).resolve().parents[1]
required = [
    "project.godot", "scenes/main.tscn", "scripts/app/world_coordinator.gd",
    "scripts/backend/world_backend.gd", "scripts/runtime/scene_runtime.gd",
    "scripts/backend/terrain_resolver.gd", "scripts/resolved/resolved_terrain.gd",
    "scripts/backend/coast_resolver.gd", "scripts/resolved/resolved_water.gd",
    "scripts/backend/forest_dresser.gd", "scripts/resolved/resolved_decoration.gd",
    "assets/prototypes/nature/tree_01.tscn", "assets/prototypes/nature/rock_01.tscn",
    "assets/prototypes/nature/bush_01.tscn", "assets/prototypes/nature/grass_01.tscn",
    "assets/prototypes/nature/dead_tree_01.tscn", "data/fixtures/coastal_town_initial.json",
    "tests/test_terrain_surface.gd",
    "tests/test_main_scene.gd",
    "tests/test_coast_water.gd",
]
missing = [p for p in required if not (root / p).exists()]
if missing:
    print("Missing:", *missing, sep="\n - ")
    sys.exit(1)

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
for src, ref in refs:
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
