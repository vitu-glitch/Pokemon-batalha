#!/usr/bin/env python3
"""Small source-asset regression test for the Gen 1 Bedrock converter."""
from __future__ import annotations

import json
from pathlib import Path

import import_gen1 as converter

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "pokemon" / "gen1_manifest.json").read_text(encoding="utf-8"))
source_ref = manifest.get("source_branch", "main")
base = f"https://gitlab.com/cable-mc/cobblemon/-/raw/{source_ref}/"
items = {item["id"]: item for item in manifest["pokemon"]}

SAMPLES = ["bulbasaur", "pikachu", "pidgey", "gengar", "charizard"]


def has_motion(clip: dict) -> bool:
    for channels in clip.get("bones", {}).values():
        for values in channels.values():
            if len(values) < 6:
                continue
            first = values[:3]
            for offset in range(3, len(values), 3):
                if any(abs(values[offset + axis] - first[axis]) > 0.0001 for axis in range(3)):
                    return True
    return False


for species_id in SAMPLES:
    item = items[species_id]
    geometry = converter.fetch_json(base, item["model"])
    animations = converter.fetch_json(base, item["animations"])
    model = converter.convert_geometry(geometry, animations)

    assert model["converter_version"] == converter.CONVERTER_VERSION, species_id
    assert model["bones"], species_id
    assert model["tex_w"] > 0 and model["tex_h"] > 0, species_id

    vertices = 0
    for bone in model["bones"]:
        verts = bone["verts"]
        normals = bone["normals"]
        uvs = bone["uvs"]
        assert len(verts) == len(normals), (species_id, bone["name"])
        assert len(verts) * 2 == len(uvs) * 3, (species_id, bone["name"])
        assert len(verts) % 9 == 0, (species_id, bone["name"])
        vertices += len(verts) // 3

    clips = model["anims"]
    assert "ground_idle" in clips and "ground_walk" in clips, species_id
    assert has_motion(clips["ground_idle"]), (species_id, "ground_idle has no movement")
    assert has_motion(clips["ground_walk"]), (species_id, "ground_walk has no movement")
    print(
        f"OK {species_id}: {len(model['bones'])} bones, "
        f"{vertices} vertices, {len(clips)} clips"
    )

print("Gen 1 converter regression checks passed.")
