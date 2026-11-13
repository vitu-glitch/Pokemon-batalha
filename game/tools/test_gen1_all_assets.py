#!/usr/bin/env python3
"""Full upstream-asset and conversion check for all 151 Kanto species."""
from __future__ import annotations

import concurrent.futures
import json
import math
import struct
from pathlib import Path

import import_gen1 as converter

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "pokemon" / "gen1_manifest.json").read_text(encoding="utf-8"))
source_ref = manifest.get("source_branch", "main")
base = f"https://gitlab.com/cable-mc/cobblemon/-/raw/{source_ref}/"
metadata_base = converter.METADATA_RAW_BASE
items = sorted(manifest["pokemon"], key=lambda item: int(item["dex"]))
EXPECTED = 151
PNG_SIGNATURE = bytes((137, 80, 78, 71, 13, 10, 26, 10))
CORE_ANIMATIONS = {
    "ground_idle", "battle_idle", "ground_walk", "ground_run", "air_idle", "air_fly"
}


def png_dimensions(data: bytes, species_id: str, label: str) -> tuple[int, int]:
    if len(data) < 24 or data[:8] != PNG_SIGNATURE:
        raise RuntimeError(f"{species_id}: {label} is not a valid PNG")
    return struct.unpack(">II", data[16:24])


def validate_one(item: dict) -> dict:
    species_id = item["id"]
    dex = int(item["dex"])

    metadata_path = (
        "common/src/main/resources/data/cobblemon/species/"
        f"generation1/{species_id}.json"
    )
    metadata = converter.fetch_json(metadata_base, metadata_path)
    if int(metadata.get("nationalPokedexNumber", -1)) != dex:
        raise RuntimeError(f"{species_id}: species metadata has wrong Pokédex number")

    model_path, geometry_bytes = converter.resolve_source_asset(
        item, base, "model", source_ref
    )
    animation_path, animation_bytes = converter.resolve_source_asset(
        item, base, "animations", source_ref
    )
    texture_path, texture_bytes = converter.resolve_source_asset(
        item, base, "texture", source_ref
    )
    shiny_path, shiny_bytes = converter.resolve_source_asset(
        item, base, "shiny_texture", source_ref
    )

    geometry = json.loads(geometry_bytes.decode("utf-8"))
    animations = json.loads(animation_bytes.decode("utf-8"))
    model = converter.convert_geometry(geometry, animations)

    if model.get("converter_version") != converter.CONVERTER_VERSION:
        raise RuntimeError(f"{species_id}: wrong converter version")
    bones = model.get("bones", [])
    if not bones:
        raise RuntimeError(f"{species_id}: model has no bones")
    bone_names = [bone["name"] for bone in bones]
    bone_set = set(bone_names)
    if len(bone_set) != len(bone_names):
        raise RuntimeError(f"{species_id}: duplicate bone names")

    vertices = 0
    for bone in bones:
        verts = bone.get("verts", [])
        normals = bone.get("normals", [])
        uvs = bone.get("uvs", [])
        if len(verts) != len(normals) or len(verts) * 2 != len(uvs) * 3:
            raise RuntimeError(f"{species_id}/{bone['name']}: invalid vertex/normal/UV lengths")
        if len(verts) % 9:
            raise RuntimeError(f"{species_id}/{bone['name']}: incomplete triangle data")
        if any(not math.isfinite(float(v)) for v in verts + normals + uvs):
            raise RuntimeError(f"{species_id}/{bone['name']}: non-finite geometry value")
        vertices += len(verts) // 3
    if vertices < 1:
        raise RuntimeError(f"{species_id}: model has no renderable vertices")

    texture_size = png_dimensions(texture_bytes, species_id, "normal texture")
    shiny_size = png_dimensions(shiny_bytes, species_id, "shiny texture")
    expected_size = (int(model["tex_w"]), int(model["tex_h"]))
    if texture_size != expected_size:
        raise RuntimeError(
            f"{species_id}: model UV canvas {expected_size} does not match "
            f"texture {texture_size} ({texture_path})"
        )
    if shiny_size != expected_size:
        raise RuntimeError(
            f"{species_id}: model UV canvas {expected_size} does not match "
            f"shiny texture {shiny_size} ({shiny_path})"
        )

    source_bones = {
        bone["name"] for bone in geometry["minecraft:geometry"][0].get("bones", [])
    }
    missing_core_refs = {}
    source_clips = animations.get("animations", {})
    for full_name, clip in source_clips.items():
        short_name = full_name.split(".")[-1]
        if short_name not in CORE_ANIMATIONS:
            continue
        missing = sorted(set((clip.get("bones") or {}).keys()) - source_bones)
        if missing:
            missing_core_refs[short_name] = missing
    if missing_core_refs:
        raise RuntimeError(f"{species_id}: core animations reference absent bones {missing_core_refs}")

    clips = model.get("anims", {})
    if "ground_idle" not in clips or "ground_walk" not in clips:
        raise RuntimeError(f"{species_id}: missing controller fallback clips")
    for clip_name, clip in clips.items():
        for bone_name, channels in clip.get("bones", {}).items():
            if bone_name not in bone_set:
                continue
            for channel_name, values in channels.items():
                if len(values) % 3:
                    raise RuntimeError(
                        f"{species_id}/{clip_name}/{bone_name}/{channel_name}: invalid track length"
                    )
                if any(not math.isfinite(float(value)) for value in values):
                    raise RuntimeError(
                        f"{species_id}/{clip_name}/{bone_name}/{channel_name}: non-finite track"
                    )

    return {
        "dex": dex,
        "id": species_id,
        "model": model_path.split("/")[-1],
        "bones": len(bones),
        "vertices": vertices,
        "clips": len(clips),
        "texture": texture_size,
    }


if len(items) != EXPECTED:
    raise SystemExit(f"Expected {EXPECTED} Kanto species, got {len(items)}")

failures = []
reports = []
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    futures = {pool.submit(validate_one, item): item for item in items}
    for future in concurrent.futures.as_completed(futures):
        item = futures[future]
        try:
            reports.append(future.result())
        except Exception as exc:
            failures.append((item["id"], str(exc)))
            print(f"[FAIL] {item['dex']:03d} {item['id']}: {exc}", flush=True)

reports.sort(key=lambda row: row["dex"])
for row in reports:
    print(
        f"[OK] {row['dex']:03d} {row['id']}: {row['bones']} bones, "
        f"{row['vertices']} vertices, {row['clips']} clips, "
        f"texture {row['texture'][0]}x{row['texture'][1]}",
        flush=True,
    )

print(f"\nValidated {len(reports)}/{EXPECTED} Kanto species.")
if failures:
    raise SystemExit(f"{len(failures)} species failed validation.")
print("Full Gen 1 asset and converter validation passed.")
