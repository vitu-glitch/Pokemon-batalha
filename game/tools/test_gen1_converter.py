#!/usr/bin/env python3
"""Small source-asset regression test for the Gen 1 Bedrock converter."""
from __future__ import annotations

import gzip
import json
import tempfile
from pathlib import Path
from unittest.mock import patch

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




# Missing animation_length defaults to the last explicit keyframe time.
assert converter.infer_animation_length({
    "bones": {"tail": {"rotation": {
        "0.0": [0, 0, 0], "0.4": [10, 0, 0], "1.35": [0, 0, 0]
    }}}
}, True) == 1.35
assert converter.infer_animation_length({
    "bones": {"tail": {"rotation": [0, 0, 0]}}
}, True) == converter.ANIM_DEFAULT_LOOP_LENGTH

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
assert converter.sample_channel(step_channel, 1.0, {}, [0.0, 0.0, 0.0]) == [10.0, 10.0, 10.0]
assert converter.sample_channel(step_channel, 1.5, {}, [0.0, 0.0, 0.0]) == [10.0, 10.0, 10.0]


# Bedrock cube rotation without an explicit cube pivot is around the cube center,
# not the parent bone pivot.
mini_geometry = {
    "minecraft:geometry": [{
        "description": {"texture_width": 64, "texture_height": 64},
        "bones": [{
            "name": "root",
            "pivot": [0, 0, 0],
            "cubes": [{
                "origin": [10, 0, 0],
                "size": [2, 2, 2],
                "rotation": [0, 0, 90],
                "uv": [0, 0],
            }],
        }],
    }]
}
mini_model = converter.convert_geometry(mini_geometry, {"animations": {}})
mini_vertices = mini_model["bones"][0]["verts"]
mean = [
    sum(mini_vertices[i] for i in range(axis, len(mini_vertices), 3)) / (len(mini_vertices) // 3)
    for axis in range(3)
]
assert all(abs(mean[i] - [11.0, 1.0, 1.0][i]) < 0.001 for i in range(3)), mean

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


# The in-game neutral pose must prefer ground_idle over battle_idle guard poses.
fighter_source = (ROOT / "scripts" / "fighter.gd").read_text(encoding="utf-8")
assert 'var a := "ground_idle" if model.has_anim("ground_idle") else "battle_idle"' in fighter_source


# End-to-end smoke test for process_one(): catches errors that a pure geometry
# conversion test cannot see (directory writes, source marker, textures, gzip).
def test_process_one_smoke():
    png_signature = bytes((137, 80, 78, 71, 13, 10, 26, 10))
    png_bytes = png_signature + bytes(16)
    geometry = {
        "minecraft:geometry": [{
            "description": {"texture_width": 64, "texture_height": 64},
            "bones": [{
                "name": "root",
                "pivot": [0, 0, 0],
                "cubes": [{"origin": [0, 0, 0], "size": [4, 4, 4], "uv": [0, 0]}],
            }],
        }]
    }
    animations = {
        "animations": {
            "animation.converter_smoke_test.ground_idle": {
                "loop": True,
                "bones": {"root": {"rotation": [0, 0, 0]}},
            },
            "animation.converter_smoke_test.ground_walk": {
                "loop": True,
                "bones": {"root": {"rotation": {
                    "0.0": [0, 0, 0], "0.5": [10, 0, 0], "1.0": [0, 0, 0]
                }}},
            },
        }
    }
    metadata = {
        "nationalPokedexNumber": 152,
        "name": "Converter Smoke Test",
        "primaryType": "normal",
        "baseStats": {
            "hp": 50, "attack": 50, "defence": 50,
            "special_attack": 50, "special_defence": 50, "speed": 50,
        },
        "height": 10,
        "weight": 100,
        "abilities": [],
        "moves": [],
    }
    source_payloads = {
        "model": json.dumps(geometry).encode("utf-8"),
        "animations": json.dumps(animations).encode("utf-8"),
        "texture": png_bytes,
        "shiny_texture": png_bytes,
    }

    def fake_resolve(item, raw_base, asset_key, source_ref):
        return f"smoke/{asset_key}", source_payloads[asset_key]

    item = {
        "dex": 152,
        "id": "converter_smoke_test",
        "folder": "converter_smoke_test",
        "model": "smoke.geo.json",
        "animations": "smoke.animation.json",
        "texture": "smoke.png",
        "shiny_texture": "smoke_shiny.png",
    }
    with tempfile.TemporaryDirectory() as temp:
        temp_dir = Path(temp)
        with (
            patch.object(converter, "POKEMON_DIR", temp_dir),
            patch.object(converter, "SOURCE_COMMIT", "test-source", create=True),
            patch.object(converter, "fetch_json", return_value=metadata),
            patch.object(converter, "resolve_source_asset", side_effect=fake_resolve),
        ):
            species_id, species_data, stats = converter.process_one(item, "")
            pokemon_dir = temp_dir / species_id
            model_path = pokemon_dir / "model.json.gz"
            with gzip.open(model_path, "rt", encoding="utf-8") as stream:
                converted = json.load(stream)
            assert converted["converter_version"] == converter.CONVERTER_VERSION
            assert stats["bones"] == 1 and stats["vertices"] > 0
            assert stats["walk_motion"] is True
            assert (pokemon_dir / "import_source.txt").read_text(encoding="utf-8").strip() == "test-source"
            assert (pokemon_dir / "texture.png").read_bytes()[:8] == png_signature
            assert (pokemon_dir / "texture_shiny.png").read_bytes()[:8] == png_signature


test_process_one_smoke()

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
    animated_idle_names = [name for name in idle_names if has_motion(clips[name])]
    motion_note = ",".join(movement_names) if movement_names else "static-pose locomotion"
    print(
        f"OK {species_id}: {model_path} | {len(model['bones'])} bones, "
        f"{vertices} vertices, {len(clips)} clips; "
        f"idle={','.join(animated_idle_names) or 'static'}, move={motion_note}"
    )

print("Gen 1 converter regression checks passed.")
