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
SAMPLES = ["bulbasaur", "pikachu", "pidgey", "gengar", "charizard", "raichu", "arbok"]

from urllib.parse import urlencode
from urllib.request import Request, urlopen

GITLAB_API = "https://gitlab.com/api/v4/projects/cable-mc%2Fcobblemon/repository/tree"


def list_gitlab_directory(path: str) -> list[dict]:
    query = urlencode({"path": path, "ref": source_ref, "per_page": 100})
    request = Request(GITLAB_API + "?" + query, headers={"User-Agent": "PokeBrawl-Gen1-Importer/1.0"})
    with urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))



# Official Bedrock vector rules: scalars and one-component arrays apply to all axes.
for channel_value in [2.0, "2.0", [2.0], ["2.0"]]:
    converted = converter.vector_value(channel_value, 0.0, {}, [0.0, 0.0, 0.0])
    assert converted == [2.0, 2.0, 2.0], (channel_value, converted)

# Unspecified axes in a two-component scale track retain their scale default.
assert converter.vector_value([2.0, 3.0], 0.0, {}, [1.0, 1.0, 1.0]) == [2.0, 3.0, 1.0]

# Pre/post keyframes must interpolate towards the incoming pre value, not the post jump.
step_channel = {
    "0.0": [0.0, 0.0, 0.0],
    "1.0": {"pre": [0.0, 0.0, 0.0], "post": [10.0, 10.0, 10.0]},
    "2.0": [10.0, 10.0, 10.0],
}
assert converter.sample_channel(step_channel, 0.5, {}, [0.0, 0.0, 0.0]) == [0.0, 0.0, 0.0]
assert converter.sample_channel(step_channel, 1.5, {}, [0.0, 0.0, 0.0]) == [10.0, 10.0, 10.0]

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
    model_path, geometry_bytes = converter.resolve_source_asset(item, base, "model", source_ref)
    animation_path, animation_bytes = converter.resolve_source_asset(item, base, "animations", source_ref)
    texture_path, texture_bytes = converter.resolve_source_asset(item, base, "texture", source_ref)
    shiny_path, shiny_bytes = converter.resolve_source_asset(item, base, "shiny_texture", source_ref)
    geometry = json.loads(geometry_bytes.decode("utf-8"))
    animations = json.loads(animation_bytes.decode("utf-8"))
    assert texture_bytes[:8] == bytes((137, 80, 78, 71, 13, 10, 26, 10)), texture_path
    assert shiny_bytes[:8] == bytes((137, 80, 78, 71, 13, 10, 26, 10)), shiny_path
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

    source_clip_names = {
        name.split(".")[-1]
        for name in animations.get("animations", {})
    }
    idle_names = [
        name for name in ("battle_idle", "ground_idle", "air_idle", "hover_idle", "water_idle")
        if name in source_clip_names and name in clips
    ]
    movement_names = [
        name for name in clips
        if name in source_clip_names
        and any(token in name for token in ("walk", "run", "fly", "swim"))
        and has_motion(clips[name])
    ]
    assert idle_names, (species_id, "no idle clip in source")
    assert movement_names, (species_id, "no animated locomotion clip in source")
    animated_idle_names = [name for name in idle_names if has_motion(clips[name])]
    print(
        f"OK {species_id}: {model_path} | {len(model['bones'])} bones, "
        f"{vertices} vertices, {len(clips)} clips; "
        f"idle={','.join(animated_idle_names) or 'static'}, "
        f"move={','.join(movement_names)}"
    )

print("Gen 1 converter regression checks passed.")
