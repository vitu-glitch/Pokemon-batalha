#!/usr/bin/env python3
"""Import and convert all 151 Kanto Pokemon for PokeBrawl.

Run from the repository root with:
    py game/tools/import_gen1.py

The importer uses Python's standard library only. It downloads current Cobblemon
assets from the maintained Cable/Cobblemon GitLab main branch, converts Bedrock
geometry and animations to PokeBrawl's runtime format, and writes game species data.
"""
from __future__ import annotations

import ast
import concurrent.futures
import gzip
import json
import math
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POKEMON_DIR = ROOT / "pokemon"
MANIFEST_PATH = POKEMON_DIR / "gen1_manifest.json"
SPECIES_OUTPUT = POKEMON_DIR / "gen1_species.json"
FPS = 20
ANIM_DEFAULT_LOOP_LENGTH = 4.0
MAX_ANIMATION_FRAMES = 480
CONVERTER_VERSION = 6
USER_AGENT = "PokeBrawl-Gen1-Importer/1.0"

# Corner order produces outward normals; triangle indices are reversed below
# because Godot's ArrayMesh uses clockwise winding for front faces.
FACE_NORMAL_AXIS = {
    "north": 2, "south": 2, "east": 0,
    "west": 0, "up": 1, "down": 1,
}
GODOT_TRIANGLE_ORDER = (0, 2, 1, 0, 3, 2)

FACES = {
    "north": (lambda x0,y0,z0,x1,y1,z1: [(x0,y0,z0),(x0,y1,z0),(x1,y1,z0),(x1,y0,z0)],
              lambda u,v,w,h: [(u,v+h),(u,v),(u+w,v),(u+w,v+h)], "xy"),
    "south": (lambda x0,y0,z0,x1,y1,z1: [(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)],
              lambda u,v,w,h: [(u+w,v+h),(u,v+h),(u,v),(u+w,v)], "xy"),
    "east":  (lambda x0,y0,z0,x1,y1,z1: [(x1,y0,z1),(x1,y0,z0),(x1,y1,z0),(x1,y1,z1)],
              lambda u,v,w,h: [(u+w,v+h),(u,v+h),(u,v),(u+w,v)], "yz"),
    "west":  (lambda x0,y0,z0,x1,y1,z1: [(x0,y0,z0),(x0,y0,z1),(x0,y1,z1),(x0,y1,z0)],
              lambda u,v,w,h: [(u,v+h),(u+w,v+h),(u+w,v),(u,v)], "yz"),
    "up":    (lambda x0,y0,z0,x1,y1,z1: [(x0,y1,z1),(x1,y1,z1),(x1,y1,z0),(x0,y1,z0)],
              lambda u,v,w,h: [(u,v+h),(u+w,v+h),(u+w,v),(u,v)], "xz"),
    "down":  (lambda x0,y0,z0,x1,y1,z1: [(x0,y0,z0),(x1,y0,z0),(x1,y0,z1),(x0,y0,z1)],
              lambda u,v,w,h: [(u,v),(u+w,v),(u+w,v+h),(u,v+h)], "xz"),
}


def fetch_bytes(url: str, attempts: int = 5) -> bytes:
    last = None
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=45) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                raise RuntimeError(f"HTTP Error 404: {url}") from exc
            last = exc
            time.sleep(min(2 ** attempt, 10))
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last = exc
            time.sleep(min(2 ** attempt, 10))
    raise RuntimeError(f"Download failed: {url}\n{last}")


_GITLAB_DIRECTORY_CACHE: dict[str, list[str]] = {}
GITLAB_TREE_API = "https://gitlab.com/api/v4/projects/cable-mc%2Fcobblemon/repository/tree"

ASSET_ROOTS = {
    "model": "common/src/main/resources/assets/cobblemon/bedrock/pokemon/models",
    "animations": "common/src/main/resources/assets/cobblemon/bedrock/pokemon/animations",
    "texture": "common/src/main/resources/assets/cobblemon/textures/pokemon",
    "shiny_texture": "common/src/main/resources/assets/cobblemon/textures/pokemon",
}


def gitlab_directory_names(directory: str, source_ref: str) -> list[str]:
    cache_key = f"{source_ref}:{directory}"
    if cache_key in _GITLAB_DIRECTORY_CACHE:
        return _GITLAB_DIRECTORY_CACHE[cache_key]
    query = urllib.parse.urlencode({
        "path": directory,
        "ref": source_ref,
        "per_page": 100,
    })
    payload = json.loads(fetch_bytes(GITLAB_TREE_API + "?" + query, attempts=3).decode("utf-8"))
    names = sorted(
        entry["name"] for entry in payload
        if isinstance(entry, dict) and entry.get("type") == "blob" and "name" in entry
    )
    _GITLAB_DIRECTORY_CACHE[cache_key] = names
    return names


def _is_http_404(error: Exception) -> bool:
    return "HTTP Error 404" in str(error)


def _choose_asset_name(names: list[str], species_id: str, asset_key: str) -> str:
    if asset_key == "model":
        candidates = [name for name in names if name.lower().endswith(".geo.json")]
        preferred = [
            f"{species_id}_male.geo.json",
            f"{species_id}.geo.json",
            f"{species_id}_female.geo.json",
        ]
        for name in preferred:
            if name in candidates:
                return name
        if len(candidates) == 1:
            return candidates[0]
        male = [name for name in candidates if "_male." in name.lower()]
        if male:
            return sorted(male)[0]
        exact_species = [name for name in candidates if species_id in name.lower()]
        if len(exact_species) == 1:
            return exact_species[0]
        # Prefer the base/default model over costumes, regional forms and props.
        neutral = [
            name for name in candidates
            if not any(token in name.lower() for token in ("alolan", "galarian", "hisui", "paldean", "cap_", "detective", "captain", "fluff"))
        ]
        if len(neutral) == 1:
            return neutral[0]
        if neutral:
            return sorted(neutral)[0]
    elif asset_key == "animations":
        candidates = [name for name in names if name.lower().endswith(".animation.json")]
        preferred = f"{species_id}.animation.json"
        if preferred in candidates:
            return preferred
        if len(candidates) == 1:
            return candidates[0]
        species_matches = [name for name in candidates if species_id in name.lower()]
        if species_matches:
            return sorted(species_matches)[0]
    elif asset_key == "texture":
        candidates = [
            name for name in names
            if name.lower().endswith(".png")
            and "shiny" not in name.lower()
            and "alpha" not in name.lower()
            and "emissive" not in name.lower()
            and "pattern" not in name.lower()
        ]
        preferred = f"{species_id}.png"
        if preferred in candidates:
            return preferred
        male = f"{species_id}_male.png"
        if male in candidates:
            return male
        species_matches = [name for name in candidates if name.lower().startswith(species_id)]
        if species_matches:
            return sorted(species_matches)[0]
        if len(candidates) == 1:
            return candidates[0]
    elif asset_key == "shiny_texture":
        candidates = [
            name for name in names
            if name.lower().endswith(".png")
            and "shiny" in name.lower()
            and "emissive" not in name.lower()
            and "pattern" not in name.lower()
        ]
        preferred = f"{species_id}_shiny.png"
        if preferred in candidates:
            return preferred
        species_matches = [name for name in candidates if name.lower().startswith(species_id)]
        if species_matches:
            return sorted(species_matches)[0]
        if len(candidates) == 1:
            return candidates[0]
    else:
        raise ValueError(f"Unknown asset key: {asset_key}")
    raise RuntimeError(
        f"No default {asset_key} asset found for {species_id}. "
        f"Files in source folder: {', '.join(names)}"
    )


def resolve_source_asset(item: dict, raw_base: str, asset_key: str, source_ref: str) -> tuple[str, bytes]:
    original_path = str(item[asset_key])
    try:
        return original_path, fetch_bytes(raw_base + original_path, attempts=1)
    except RuntimeError as exc:
        if not _is_http_404(exc):
            raise
    folder = str(item.get("folder", Path(original_path).parent.name))
    directory = ASSET_ROOTS[asset_key] + "/" + folder
    names = gitlab_directory_names(directory, source_ref)
    selected_name = _choose_asset_name(names, str(item["id"]), asset_key)
    resolved_path = directory + "/" + selected_name
    return resolved_path, fetch_bytes(raw_base + resolved_path)


def fetch_json(base: str, path: str) -> dict:
    try:
        value = json.loads(fetch_bytes(base + path).decode("utf-8"))
    except Exception as exc:
        raise RuntimeError(f"Could not read {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"Expected a JSON object in {path}")
    return value


def vec_add(a, b):
    return tuple(a[i] + b[i] for i in range(3))


def vec_sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def dot_cross(a, b):
    return (
        a[1]*b[2] - a[2]*b[1],
        a[2]*b[0] - a[0]*b[2],
        a[0]*b[1] - a[1]*b[0],
    )


def mat_mul(a, b):
    return tuple(tuple(sum(a[r][k] * b[k][c] for k in range(3))
                       for c in range(3)) for r in range(3))


def mat_vec(m, v):
    return tuple(sum(m[r][c] * v[c] for c in range(3)) for r in range(3))


def transpose(m):
    return tuple(tuple(m[c][r] for c in range(3)) for r in range(3))


def euler_basis(degrees):
    x, y, z = [math.radians(float(v)) for v in degrees]
    sx, cx = math.sin(x), math.cos(x)
    sy, cy = math.sin(y), math.cos(y)
    sz, cz = math.sin(z), math.cos(z)
    rx = ((1,0,0),(0,cx,-sx),(0,sx,cx))
    ry = ((cy,0,sy),(0,1,0),(-sy,0,cy))
    rz = ((cz,-sz,0),(sz,cz,0),(0,0,1))
    return mat_mul(mat_mul(rz, ry), rx)


def rotate_about(point, pivot, rotation):
    return vec_add(pivot, mat_vec(euler_basis(rotation), vec_sub(point, pivot)))


def uv_rects(uv, width, height, depth):
    u, v = float(uv[0]), float(uv[1])
    return {
        "north": (u + depth, v + depth, width, height),
        "east": (u + depth + width, v + depth, depth, height),
        "south": (u + depth + width + depth, v + depth, width, height),
        "west": (u, v + depth, depth, height),
        "up": (u + depth, v, width, depth),
        "down": (u + depth + width, v, width, depth),
    }


def face_uvs(cube, face, dims, tex_w, tex_h):
    uv_data = cube.get("uv", [0, 0])
    if isinstance(uv_data, dict):
        info = uv_data.get(face)
        if not isinstance(info, dict) or "uv" not in info:
            return None
        u, v = float(info["uv"][0]), float(info["uv"][1])
        uv_size = info.get("uv_size")
        if uv_size is None:
            axis = FACES[face][2]
            w, h = (dims[0], dims[2]) if axis == "xz" else (
                (dims[2], dims[1]) if axis == "yz" else (dims[0], dims[1]))
        else:
            w, h = float(uv_size[0]), float(uv_size[1])
        rotation = int(info.get("uv_rotation", info.get("rotation", 0))) % 360
    else:
        rect = uv_rects(uv_data, *dims)[face]
        u, v, w, h = rect
        rotation = 0

    points = FACES[face][1](u, v, w, h)
    if rotation:
        cu, cv = u + w * 0.5, v + h * 0.5
        turns = (rotation // 90) % 4
        rotated = []
        for px, py in points:
            dx, dy = px - cu, py - cv
            for _ in range(turns):
                dx, dy = -dy, dx
            rotated.append((cu + dx, cv + dy))
        points = rotated
    if cube.get("mirror", False):
        points = [(2.0 * u + w - px, py) for px, py in points]
    return [(px / tex_w, py / tex_h) for px, py in points]


def convert_geometry(geometry_json: dict, animation_json: dict) -> dict:
    geometries = geometry_json.get("minecraft:geometry", [])
    if not geometries:
        raise RuntimeError("No minecraft:geometry entry")
    geometry = geometries[0]
    desc = geometry.get("description", {})
    tex_w = int(desc.get("texture_width", 64))
    tex_h = int(desc.get("texture_height", 64))
    source_bones = geometry.get("bones", [])
    by_name = {bone["name"]: bone for bone in source_bones}

    ordered, visited = [], set()
    def visit(bone):
        name = bone["name"]
        if name in visited:
            return
        parent = bone.get("parent", "")
        if parent and parent in by_name:
            visit(by_name[parent])
        visited.add(name)
        ordered.append(bone)

    for bone in source_bones:
        visit(bone)

    global_basis, global_pivot = {}, {}
    output_bones = []
    for bone in ordered:
        name = bone["name"]
        pivot = tuple(float(v) for v in bone.get("pivot", [0,0,0]))
        rotation = tuple(float(v) for v in bone.get("rotation", [0,0,0]))
        parent = bone.get("parent", "")
        local_basis = euler_basis(rotation)
        if parent and parent in global_basis:
            parent_basis = global_basis[parent]
            local_pos = mat_vec(transpose(parent_basis),
                                vec_sub(pivot, global_pivot[parent]))
            world_basis = mat_mul(parent_basis, local_basis)
        else:
            parent = ""
            local_pos = pivot
            world_basis = local_basis
        global_basis[name] = world_basis
        global_pivot[name] = pivot

        verts, normals, uvs = [], [], []
        for cube in bone.get("cubes", []) or []:
            origin = [float(v) for v in cube.get("origin", [0,0,0])]
            source_size = [max(0.0, float(v)) for v in cube.get("size", [0,0,0])]
            inflate = float(cube.get("inflate", 0.0))
            lo = [origin[i] - inflate for i in range(3)]
            hi = [origin[i] + source_size[i] + inflate for i in range(3)]

            # Bedrock uses zero-size axes for flat leaves, ears, fins and facial details.
            # Give those planes a little physical thickness, but render only their two
            # broad faces. The four artificial edge faces have no valid texture area.
            flat_axes = [axis for axis, extent in enumerate(source_size) if extent <= 1e-5]
            if len(flat_axes) >= 2:
                # A line has no textured surface area. Expanding two zero axes
                # fabricates four faces with undefined UVs and creates black spikes.
                continue
            for axis in flat_axes:
                if hi[axis] - lo[axis] < 0.02:
                    center = (hi[axis] + lo[axis]) * 0.5
                    lo[axis], hi[axis] = center - 0.01, center + 0.01

            x0,y0,z0 = lo
            x1,y1,z1 = hi
            dims = (x1-x0, y1-y0, z1-z0)
            # Inflate changes the mesh bounds, never the texture's UV layout.
            uv_dims = tuple(source_size)
            cube_pivot = tuple(float(v) for v in cube.get("pivot", pivot))
            cube_rotation = tuple(float(v) for v in cube.get("rotation", [0,0,0]))
            inv_bone = transpose(world_basis)

            for face, (make_corners, _, _) in FACES.items():
                if flat_axes and FACE_NORMAL_AXIS[face] != flat_axes[0]:
                    continue
                corners = make_corners(x0,y0,z0,x1,y1,z1)
                uv_points = face_uvs(cube, face, uv_dims, tex_w, tex_h)
                if uv_points is None:
                    continue
                world_points = [rotate_about(p, cube_pivot, cube_rotation) for p in corners]
                local_points = [mat_vec(inv_bone, vec_sub(p, pivot)) for p in world_points]
                edge_a = vec_sub(world_points[1], world_points[0])
                edge_b = vec_sub(world_points[2], world_points[0])
                n = dot_cross(edge_a, edge_b)
                n_len = math.sqrt(sum(v*v for v in n))
                if n_len < 1e-7:
                    continue
                n_world = tuple(v / n_len for v in n)
                n_local = mat_vec(inv_bone, n_world)
                # UVs and normals stay attached to their original corners. Only the
                # triangle order changes so Godot sees the outside as the front face.
                for index in GODOT_TRIANGLE_ORDER:
                    p = local_points[index]
                    verts.extend(round(float(v), 5) for v in p)
                    normals.extend(round(float(v), 5) for v in n_local)
                    uvs.extend(round(float(v), 6) for v in uv_points[index])

        locators = {}
        for locator_name, raw_locator in (bone.get("locators", {}) or {}).items():
            point = raw_locator.get("offset", raw_locator.get("position", [0,0,0])) if isinstance(raw_locator, dict) else raw_locator
            if isinstance(point, (list, tuple)) and len(point) >= 3:
                loc = tuple(float(v) for v in point[:3])
                locators[locator_name] = list(mat_vec(transpose(world_basis), vec_sub(loc, pivot)))

        output_bones.append({
            "name": name, "parent": parent,
            "pos": [round(float(v), 5) for v in local_pos],
            "rot": list(rotation),
            "verts": verts, "normals": normals, "uvs": uvs,
            "locators": locators,
        })

    return {
        "converter_version": CONVERTER_VERSION,
        "fps": FPS,
        "tex_w": tex_w,
        "tex_h": tex_h,
        "bones": output_bones,
        "anims": convert_animations(animation_json),
    }


def molang(expression, seconds, query):
    text = str(expression).strip()
    text = text.replace("query.anim_time", "anim_time").replace("q.anim_time", "anim_time")
    for key, value in query.items():
        text = re.sub(r"\b(?:query|q)\." + re.escape(key) + r"\b", str(value), text)
    text = re.sub(r"\b(?:query|q)\.[A-Za-z0-9_]+\b", "0", text)
    text = text.replace("math.", "")
    text = re.sub(r"\btrue\b", "True", text, flags=re.IGNORECASE)
    text = re.sub(r"\bfalse\b", "False", text, flags=re.IGNORECASE)
    env = {
        "anim_time": seconds,
        "sin": lambda x: math.sin(math.radians(float(x))),
        "cos": lambda x: math.cos(math.radians(float(x))),
        "tan": lambda x: math.tan(math.radians(float(x))),
        "clamp": lambda x,a,b: max(float(a), min(float(b), float(x))),
        "abs": abs, "sqrt": math.sqrt, "pow": pow,
        "min": min, "max": max, "floor": math.floor, "ceil": math.ceil,
        "round": round, "pi": math.pi,
        "lerp": lambda a,b,t: float(a) + (float(b)-float(a))*float(t),
        "random": lambda *args: sum(float(x) for x in args)/len(args) if args else 0.5,
        "True": True, "False": False,
    }
    try:
        root = ast.parse(text, mode="eval")
    except (SyntaxError, ValueError):
        return 0.0

    def evaluate(node):
        if isinstance(node, ast.Expression):
            return evaluate(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, (int,float,bool)):
            return node.value
        if isinstance(node, ast.Name):
            return env.get(node.id, 0.0)
        if isinstance(node, ast.BinOp):
            a,b = evaluate(node.left), evaluate(node.right)
            if isinstance(node.op, ast.Add): return a+b
            if isinstance(node.op, ast.Sub): return a-b
            if isinstance(node.op, ast.Mult): return a*b
            if isinstance(node.op, ast.Div): return a/b if b else 0.0
            if isinstance(node.op, ast.Pow): return a**b
            if isinstance(node.op, ast.Mod): return a%b if b else 0.0
        if isinstance(node, ast.UnaryOp):
            value = evaluate(node.operand)
            if isinstance(node.op, ast.USub): return -value
            if isinstance(node.op, ast.UAdd): return value
            if isinstance(node.op, ast.Not): return not value
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            fn = env.get(node.func.id)
            if callable(fn):
                args = [evaluate(arg) for arg in node.args]
                try: return fn(*args)
                except (TypeError, ValueError, ZeroDivisionError, OverflowError): return 0.0
        if isinstance(node, ast.Compare):
            left = evaluate(node.left)
            for op, item in zip(node.ops, node.comparators):
                right = evaluate(item)
                if isinstance(op, ast.Lt): ok = left < right
                elif isinstance(op, ast.LtE): ok = left <= right
                elif isinstance(op, ast.Gt): ok = left > right
                elif isinstance(op, ast.GtE): ok = left >= right
                elif isinstance(op, ast.Eq): ok = left == right
                elif isinstance(op, ast.NotEq): ok = left != right
                else: return False
                if not ok: return False
                left = right
            return True
        if isinstance(node, ast.BoolOp):
            values = [bool(evaluate(item)) for item in node.values]
            return all(values) if isinstance(node.op, ast.And) else any(values)
        if isinstance(node, ast.IfExp):
            return evaluate(node.body if evaluate(node.test) else node.orelse)
        raise ValueError("Unsupported Molang expression")

    try:
        value = evaluate(root)
        if isinstance(value, (int,float,bool)) and math.isfinite(float(value)):
            return float(value)
    except (ValueError, TypeError, ZeroDivisionError, OverflowError):
        pass
    return 0.0


def vector_value(value, seconds, query, default, key_part="post"):
    if isinstance(value, dict):
        # Bedrock keyframes can have separate incoming ("pre") and outgoing
        # ("post") values. Keep the requested side when sampling a keyframe.
        if key_part in value:
            return vector_value(value[key_part], seconds, query, default, key_part)
        if "vector" in value:
            return vector_value(value["vector"], seconds, query, default, key_part)
        if "post" in value:
            return vector_value(value["post"], seconds, query, default, key_part)
        if "pre" in value:
            return vector_value(value["pre"], seconds, query, default, key_part)
        return list(default)
    if isinstance(value, (int, float, str)):
        v = molang(value, seconds, query) if isinstance(value, str) else float(value)
        # Bedrock scalar channels apply the value to X, Y and Z equally.
        return [v, v, v]
    if isinstance(value, (list, tuple)):
        raw = list(value[:3])
        if len(raw) == 1:
            v = molang(raw[0], seconds, query) if isinstance(raw[0], str) else float(raw[0])
            return [v, v, v]
        result = []
        for index, component in enumerate(raw):
            result.append(
                molang(component, seconds, query)
                if isinstance(component, str) else float(component)
            )
        while len(result) < 3:
            result.append(float(default[len(result)]))
        return result
    return list(default)


def sample_channel(channel, seconds, query, default):
    if isinstance(channel, dict):
        keys = []
        for key in channel:
            try:
                keys.append((float(key), key))
            except (TypeError, ValueError):
                pass
        keys.sort(key=lambda item:item[0])
        if keys:
            if seconds <= keys[0][0]:
                return vector_value(channel[keys[0][1]], seconds, query, default, "post")
            if seconds >= keys[-1][0]:
                return vector_value(channel[keys[-1][1]], seconds, query, default, "post")
            for (ta,ka),(tb,kb) in zip(keys,keys[1:]):
                if ta <= seconds <= tb:
                    # Bedrock interpolates away from the previous key's post value
                    # toward the next key's pre value. These can differ at a jump.
                    va = vector_value(channel[ka], ta, query, default, "post")
                    vb = vector_value(channel[kb], tb, query, default, "pre")
                    alpha = (seconds-ta) / max(tb-ta, 1e-8)
                    return [va[i] + (vb[i]-va[i])*alpha for i in range(3)]
        return vector_value(channel, seconds, query, default, "post")
    return vector_value(channel, seconds, query, default, "post")


def convert_animations(animation_json):
    source = animation_json.get("animations", {})
    output = {}
    for full_name, animation in source.items():
        if not isinstance(animation, dict):
            continue
        name = full_name.split(".")[-1]
        if name in {"render", "pose"}:
            # These are showcase-only poses, never used by the battle controller.
            continue
        loop_raw = animation.get("loop", False)
        loop = loop_raw is True or str(loop_raw).lower() == "true"
        declared_length = animation.get("animation_length")
        # Bedrock omits animation_length on many cyclic Molang animations. A
        # one-second guess truncates slow idle cycles and makes them snap back.
        default_length = ANIM_DEFAULT_LOOP_LENGTH if loop else 1.0
        length = max(float(declared_length if declared_length is not None else default_length) or default_length, 1.0/FPS)
        frames = max(2, min(MAX_ANIMATION_FRAMES, int(math.ceil(length*FPS))+1))
        query = {
            "ground_speed": 1 if ("walk" in name or "run" in name) else 0,
            "is_moving": 1 if ("walk" in name or "run" in name) else 0,
            "is_on_ground": 1,
            "is_sprinting": 1 if "run" in name else 0,
        }
        bones_out = {}
        for bone_name, channels in (animation.get("bones", {}) or {}).items():
            if not isinstance(channels, dict):
                continue
            converted = {}
            for source_key, output_key, default in (
                ("rotation","rot",[0,0,0]),
                ("position","pos",[0,0,0]),
                ("scale","scl",[1,1,1]),
            ):
                if source_key not in channels:
                    continue
                values = []
                for frame in range(frames):
                    t = min(length, frame/FPS)
                    vector = sample_channel(channels[source_key], t, query, default)
                    values.extend(round(float(v),5) for v in vector)
                # One key is enough for a constant bone channel. Keeping 15 identical
                # keys per second wastes memory and makes each fight heavier to animate.
                if len(values) > 3 and all(values[i:i+3] == values[:3] for i in range(3, len(values), 3)):
                    values = values[:3]
                converted[output_key] = values
            if converted:
                bones_out[bone_name] = converted
        if bones_out:
            output[name] = {
                "len": length, "loop": loop, "frames": frames,
                "bones": bones_out,
            }

    # Names expected by the movement controller. A missing run/fly clip reuses a safe walk pose.
    fallback_idle = output.get("battle_idle")
    if fallback_idle is None:
        fallback_idle = next((v for v in output.values() if v["loop"]), None)
    if fallback_idle is None:
        fallback_idle = {"len":1.0,"loop":True,"frames":2,"bones":{}}
    output.setdefault("ground_idle", json.loads(json.dumps(fallback_idle)))
    output.setdefault("ground_walk", json.loads(json.dumps(output["ground_idle"])))
    output.setdefault("ground_run", json.loads(json.dumps(output["ground_walk"])))
    output.setdefault("fly", json.loads(json.dumps(output["ground_run"])))
    return output


def convert_species(source):
    stats = source.get("baseStats", {})
    types = [source.get("primaryType", "normal")]
    if source.get("secondaryType"):
        types.append(source["secondaryType"])
    abilities = []
    for raw in source.get("abilities", []):
        hidden = str(raw).startswith("h:")
        ability_id = str(raw).removeprefix("h:").lower()
        if ability_id:
            abilities.append({"id":ability_id,"hidden":hidden})
    learnset = []
    for raw in source.get("moves", []):
        item = str(raw)
        if ":" not in item:
            continue
        how, move = item.split(":",1)
        level = None
        if how.isdigit():
            level, how = int(how), "level"
        if how not in ["level","egg","tm","tutor","legacy","special"]:
            continue
        entry = {"move":move.lower(),"how":how}
        if level is not None:
            entry["level"] = level
        learnset.append(entry)
    return {
        "dex":int(source.get("nationalPokedexNumber",0)),
        "name":source.get("name",""),
        "types":types,
        "stats":{
            "hp":int(stats.get("hp",50)),
            "atk":int(stats.get("attack",50)),
            "def":int(stats.get("defence",50)),
            "spa":int(stats.get("special_attack",50)),
            "spd":int(stats.get("special_defence",50)),
            "spe":int(stats.get("speed",50)),
        },
        "weight_kg":float(source.get("weight",200))/10.0,
        "height_m":float(source.get("height",10))/10.0,
        "abilities":abilities,
        "learnset":learnset,
    }


def download_if_missing(target, url):
    target.parent.mkdir(parents=True, exist_ok=True)
    valid_png = False
    if target.exists() and target.stat().st_size >= 24:
        try:
            with target.open("rb") as stream:
                header = stream.read(24)
            valid_png = header[:8] == bytes((137, 80, 78, 71, 13, 10, 26, 10))
        except OSError:
            valid_png = False
    if not valid_png:
        target.write_bytes(fetch_bytes(url))
    with target.open("rb") as stream:
        if stream.read(8) != bytes((137, 80, 78, 71, 13, 10, 26, 10)):
            raise RuntimeError(f"Downloaded texture is not a valid PNG: {target}")


def process_one(item, raw_base):
    species_id = item["id"]
    target_dir = POKEMON_DIR / species_id
    target_dir.mkdir(parents=True, exist_ok=True)
    species_source = f"common/src/main/resources/data/cobblemon/species/generation1/{species_id}.json"
    metadata = fetch_json(raw_base, species_source)
    species_data = convert_species(metadata)

    model_path = target_dir / "model.json.gz"
    normal_path = target_dir / "texture.png"
    shiny_path = target_dir / "texture_shiny.png"
    source_marker = target_dir / "import_source.txt"
    previous_source = source_marker.read_text(encoding="utf-8").strip() if source_marker.exists() else ""

    # Preserve the project's original hand-tuned models. Imported models are rebuilt
    # when either the converter format or the upstream asset source has changed.
    preserve_existing = species_id in {
        "bulbasaur", "pikachu", "snorlax", "charizard", "blastoise",
        "venusaur", "lucario", "gengar", "garchomp", "greninja", "scizor",
    }
    needs_conversion = not model_path.exists() or model_path.stat().st_size == 0
    if not preserve_existing and previous_source != SOURCE_COMMIT:
        needs_conversion = true
    if model_path.exists() and not preserve_existing and not needs_conversion:
        try:
            with gzip.open(model_path, "rt", encoding="utf-8") as stream:
                existing_model = json.load(stream)
            needs_conversion = int(existing_model.get("converter_version", 0)) < CONVERTER_VERSION
        except (OSError, EOFError, json.JSONDecodeError, AttributeError, TypeError, ValueError):
            needs_conversion = True
    model_source = item["model"]
    animation_source = item["animations"]
    texture_source = item["texture"]
    shiny_source = item["shiny_texture"]

    if needs_conversion:
        model_source, geometry_bytes = resolve_source_asset(item, raw_base, "model", SOURCE_COMMIT)
        animation_source, animation_bytes = resolve_source_asset(item, raw_base, "animations", SOURCE_COMMIT)
        geometry = json.loads(geometry_bytes.decode("utf-8"))
        animations = json.loads(animation_bytes.decode("utf-8"))
        model = convert_geometry(geometry, animations)
        packed = json.dumps(model, separators=(",",":"), ensure_ascii=False).encode("utf-8")
        model_path.write_bytes(gzip.compress(packed, compresslevel=9))

    # Refresh textures when the upstream source changes. The resolver handles default
    # male/female filenames and the source's renamed texture files.
    if not preserve_existing and previous_source != SOURCE_COMMIT:
        texture_source, normal_bytes = resolve_source_asset(item, raw_base, "texture", SOURCE_COMMIT)
        shiny_source, shiny_bytes = resolve_source_asset(item, raw_base, "shiny_texture", SOURCE_COMMIT)
        normal_path.write_bytes(normal_bytes)
        shiny_path.write_bytes(shiny_bytes)
    else:
        if not normal_path.exists() or normal_path.stat().st_size < 24:
            texture_source, normal_bytes = resolve_source_asset(item, raw_base, "texture", SOURCE_COMMIT)
            normal_path.write_bytes(normal_bytes)
        if not shiny_path.exists() or shiny_path.stat().st_size < 24:
            shiny_source, shiny_bytes = resolve_source_asset(item, raw_base, "shiny_texture", SOURCE_COMMIT)
            shiny_path.write_bytes(shiny_bytes)

    for texture_path in (normal_path, shiny_path):
        with texture_path.open("rb") as stream:
            if stream.read(8) != bytes((137, 80, 78, 71, 13, 10, 26, 10)):
                raise RuntimeError(f"Downloaded texture is not a valid PNG: {texture_path}")
    if not preserve_existing:
        source_marker.write_text(SOURCE_COMMIT + "\n", encoding="utf-8")

    attribution = (
        f"{species_data['name']} model, animation and textures\n"
        f"Source: Cable/Cobblemon on GitLab, ref {SOURCE_COMMIT}.\n"
        f"Model: {model_source}\n"
        f"Animations: {animation_source}\n"
        f"Texture: {texture_source}\n"
        f"Shiny texture: {shiny_source}\n"
        "Conversion: Bedrock geometry and animation JSON converted to PokeBrawl's runtime model format.\n"
        "License: Creative Commons Attribution-NonCommercial 3.0 Unported. See game/pokemon/LICENSE-models.txt.\n"
        "Pokémon and Cobblemon are the property of their respective rights holders; this project is not affiliated with them.\n"
    )
    (target_dir / "ATTRIBUTION.txt").write_text(attribution, encoding="utf-8")
    with gzip.open(model_path, "rt", encoding="utf-8") as stream:
        converted = json.load(stream)
    bones = converted.get("bones", [])
    if not bones:
        raise RuntimeError(f"Converted model has no bones: {species_id}")
    vertex_count = 0
    for bone in bones:
        verts = bone.get("verts", [])
        normals = bone.get("normals", [])
        uvs = bone.get("uvs", [])
        if len(verts) != len(normals) or len(verts) * 2 != len(uvs) * 3:
            raise RuntimeError(f"Broken vertex/normal/UV arrays in {species_id}/{bone.get('name')}")
        if len(verts) % 9:
            raise RuntimeError(f"Triangle data is incomplete in {species_id}/{bone.get('name')}")
        vertex_count += len(verts) // 3
    animations_out = converted.get("anims", {})
    if "ground_idle" not in animations_out or "ground_walk" not in animations_out:
        raise RuntimeError(f"Missing required movement animations in {species_id}")
    for clip_name, clip in animations_out.items():
        for bone_name, channels in clip.get("bones", {}).items():
            for channel_name, values in channels.items():
                if len(values) % 3:
                    raise RuntimeError(f"Invalid {clip_name}/{bone_name}/{channel_name} track in {species_id}")
    def has_motion(clip):
        for channels in clip.get("bones", {}).values():
            for values in channels.values():
                if len(values) < 6:
                    continue
                first = values[:3]
                for offset in range(3, len(values), 3):
                    if any(abs(values[offset + axis] - first[axis]) > 0.0001 for axis in range(3)):
                        return True
        return False

    return species_id, species_data, {
        "bones": len(bones),
        "clips": len(animations_out),
        "vertices": vertex_count,
        "idle_motion": has_motion(animations_out.get("ground_idle", {})),
        "walk_motion": has_motion(animations_out.get("ground_walk", {})),
        "animation_names": sorted(animations_out.keys()),
    }


def main():
    global SOURCE_COMMIT
    if not MANIFEST_PATH.exists():
        raise SystemExit(f"Manifest missing: {MANIFEST_PATH}")
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    SOURCE_COMMIT = str(manifest.get("source_branch", "main"))
    raw_base = f"https://gitlab.com/cable-mc/cobblemon/-/raw/{SOURCE_COMMIT}/"
    items = sorted(manifest["pokemon"], key=lambda item:int(item["dex"]))
    if len(items) != 151:
        raise SystemExit(f"Expected 151 species, found {len(items)}")

    print(f"PokeBrawl Gen 1 import - Cobblemon {SOURCE_COMMIT[:10]}")
    print("Existing model.json.gz files are preserved.")
    species_records = {}
    model_reports = {}
    failures = []
    new_models = 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        future_map = {pool.submit(process_one,item,raw_base):item for item in items}
        for future in concurrent.futures.as_completed(future_map):
            item = future_map[future]
            try:
                species_id, data, stats = future.result()
                species_records[species_id] = data
                model_reports[species_id] = stats
                animation_warning = ""
                if not stats["idle_motion"] or not stats["walk_motion"]:
                    animation_warning = " [CHECK ANIMATION]"
                print(f"[{data['dex']:03d}/151] {data['name']} imported{animation_warning} "
                      f"({stats['bones']} bones, {stats['clips']} animations, "
                      f"{stats['vertices']} vertices)")
            except Exception as exc:
                failures.append((item["id"],str(exc)))
                print(f"[ERROR] {item['id']}: {exc}",file=sys.stderr)

    report_lines = [
        "POKEBRAWL GEN 1 IMPORT REPORT",
        f"Source commit: {SOURCE_COMMIT}",
        "Legend: idle/walk = dynamic animation track detected after conversion",
        "",
    ]
    for species_id, data in sorted(species_records.items(), key=lambda pair:int(pair[1]["dex"])):
        stats = model_reports.get(species_id, {})
        report_lines.append(
            f"{data['dex']:03d} {species_id}: bones={stats.get('bones', 0)}, "
            f"vertices={stats.get('vertices', 0)}, clips={stats.get('clips', 0)}, "
            f"idle={stats.get('idle_motion', False)}, walk={stats.get('walk_motion', False)}"
        )
        report_lines.append("  animations: " + ", ".join(stats.get("animation_names", [])))
    report_path = POKEMON_DIR / "gen1_import_report.txt"
    report_path.write_text("\n".join(report_lines) + "\n", encoding="utf-8")

    if failures:
        print(f"\n{len(failures)} species failed. Fix the download/source issue and run this again.")
        print("Already downloaded files are kept, so the next run can resume.")
        for species_id,error in failures:
            print(f" - {species_id}: {error}")
        raise SystemExit(1)

    species_records = dict(sorted(species_records.items(), key=lambda pair:int(pair[1]["dex"])))
    SPECIES_OUTPUT.write_text(
        json.dumps(species_records,ensure_ascii=False,indent=2)+"\n",
        encoding="utf-8"
    )
    print("\nImport finished:")
    print(" - 151 species with model, animations and normal/shiny textures")
    print(f" - Species data: {SPECIES_OUTPUT}")
    print(f" - Diagnostic report: {report_path}")
    print(" - Existing models in the project were preserved.")
    print("\nNow open the game folder in Godot and run PokeBrawl.")


if __name__ == "__main__":
    SOURCE_COMMIT = ""
    main()
