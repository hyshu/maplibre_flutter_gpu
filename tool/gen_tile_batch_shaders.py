#!/usr/bin/env python3
"""Generates the tile-batched shader variants from their per-tile sources.

Run from the repository root after editing a per-tile fill, line, or circle
shader: `python3 tool/gen_tile_batch_shaders.py`. A batched vertex shader
replaces the drawable UBO with an array of members, selects the member from
the vertex index, and emits the tile clip reference. A batched fragment shader
discards fragments outside their tile's region of the tile mask. Dashed lines
also index their tile properties per member.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHADERS = ROOT / "shaders"
MANIFEST = SHADERS / "MapShaders.shaderbundle.json"
MEMBERS = 8

# (source stem, manifest base name)
VERTEX_SOURCES = [
    ("fill", "Fill"),
    ("fill_dd", "FillDD"),
    ("fill_outline", "FillOutline"),
    ("fill_outline_triangulated", "FillOutlineTriangulated"),
    ("fill_outline_triangulated_dd", "FillOutlineTriangulatedDD"),
    ("fill_outline_triangulated_packed", "FillOutlineTriangulatedPacked"),
    ("line", "Line"),
    ("line_dd", "LineDD"),
    ("line_packed", "LinePacked"),
    ("line_sdf", "LineSDF"),
    ("line_sdf_dd", "LineSDFDD"),
    ("line_sdf_packed", "LineSDFPacked"),
    ("line_gradient", "LineGradient"),
    ("line_gradient_dd", "LineGradientDD"),
    ("line_gradient_packed", "LineGradientPacked"),
    ("circle", "Circle"),
    ("circle_dd", "CircleDD"),
]
FRAGMENT_SOURCES = [
    ("fill", "Fill"),
    ("fill_dd", "FillDD"),
    ("fill_outline", "FillOutline"),
    ("fill_outline_triangulated", "FillOutlineTriangulated"),
    ("fill_outline_triangulated_dd", "FillOutlineTriangulatedDD"),
    ("line", "Line"),
    ("line_dd", "LineDD"),
    ("line_sdf", "LineSDF"),
    ("line_sdf_dd", "LineSDFDD"),
    ("line_gradient", "LineGradient"),
    ("line_gradient_dd", "LineGradientDD"),
    ("circle", "Circle"),
    ("circle_dd", "CircleDD"),
]

BLOCK = re.compile(
    r"layout\(binding = (\d+)\) uniform (\w+) \{(.*?)\}\s*(\w*)\s*;", re.DOTALL
)


SCALARS = {"float", "uint", "int"}


def parse_members(body: str) -> list[tuple[str, str]]:
    """Returns (type, name) pairs in declaration order."""
    members: list[tuple[str, str]] = []
    for declaration in body.split(";"):
        declaration = re.sub(r"//.*", "", declaration).strip()
        if not declaration:
            continue
        parts = declaration.split()
        kind = parts[0]
        for name in " ".join(parts[1:]).split(","):
            name = name.strip()
            if name:
                members.append((kind, name))
    return members


def std140_layout(members: list[tuple[str, str]]) -> tuple[list[tuple[str, str, int]], int]:
    """Returns (type, name, float offset) per member and the member stride in vec4s."""
    sizes = {"mat4": 16, "vec4": 4, "vec2": 2, "float": 1, "uint": 1, "int": 1}
    aligns = {"mat4": 4, "vec4": 4, "vec2": 2, "float": 1, "uint": 1, "int": 1}
    offset = 0
    placed: list[tuple[str, str, int]] = []
    for kind, name in members:
        if kind not in sizes:
            raise ValueError(f"unsupported member type {kind} {name}")
        align = aligns[kind]
        offset = (offset + align - 1) // align * align
        placed.append((kind, name, offset))
        offset += sizes[kind]
    stride = (offset + 3) // 4
    return placed, stride


def field_expression(kind: str, offset: int, member: str) -> str:
    """Expression reading one field of member [member] from its vec4 slots.

    [member] is the index of the member's first vec4 uniform. Unsigned fields
    are stored as whole floats by the renderer because the OpenGL ES uniform
    path uploads floats only.
    """
    vec = f"{{prefix}}{member + offset // 4}"
    component = "xyzw"[offset % 4]
    if kind == "mat4":
        return "mat4(" + ", ".join(f"{{prefix}}{member + offset // 4 + column}" for column in range(4)) + ")"
    if kind == "vec4":
        return vec
    if kind == "vec2":
        pair = "xy" if offset % 4 == 0 else "zw"
        return f"{vec}.{pair}"
    if kind == "float":
        return f"{vec}.{component}"
    if kind == "uint":
        return f"uint({vec}.{component})"
    return f"int({vec}.{component})"


GLSL_TYPES = {"mat4": "mat4", "vec4": "vec4", "vec2": "vec2", "float": "float", "uint": "uint", "int": "int"}


def batch_block(source: str, block_name: str, array_name: str, slot: str) -> str:
    """Turns a uniform block into one vec4 uniform per member slot.

    Impeller's shader bundles reject struct members inside uniform blocks, and
    its OpenGL ES uniform path never fills array members, so every member's
    vec4 slots become separate uniforms and each field becomes a function that
    switches on the member index.
    """
    match = next(m for m in BLOCK.finditer(source) if m.group(2) == block_name)
    binding, _, body, instance = match.groups()
    members, stride = std140_layout(parse_members(body))
    prefix = f"{array_name}_"
    replacement = f"layout(binding = {binding}) uniform {block_name}Batch {{\n"
    for index in range(MEMBERS * stride):
        replacement += f"    vec4 {prefix}{index};\n"
    replacement += "};\n"
    macro_prefix = f"{instance}_" if instance else ""
    for kind, name, offset in members:
        function = f"batch_{macro_prefix}{name}"
        replacement += f"{GLSL_TYPES[kind]} {function}(uint member) {{\n    switch (member) {{\n"
        for member in range(MEMBERS):
            expression = field_expression(kind, offset, member * stride).replace("{prefix}", prefix)
            replacement += f"        case {member}u: return {expression};\n"
        default = field_expression(kind, offset, 0).replace("{prefix}", prefix)
        replacement += f"        default: return {default};\n    }}\n}}\n"
        replacement += f"#define {macro_prefix}{name} {function}({slot})\n"
    result = source[: match.start()] + replacement + source[match.end() :]
    if instance:
        result = re.sub(rf"\b{instance}\.(\w+)", rf"{instance}_\1", result)
    return result


def header(kind: str, stem: str) -> str:
    return (
        f"// Generated by tool/gen_tile_batch_shaders.py from {stem}.{kind}.\n"
        f"// Edit the per-tile source and regenerate instead of this file.\n"
    )


def vertex(stem: str) -> str:
    source = (SHADERS / f"{stem}.vert").read_text()
    drawable = next(m.group(2) for m in BLOCK.finditer(source) if m.group(1) == "0")
    source = batch_block(source, drawable, "drawables", "tile_slot")
    source = source.replace(
        "#version 460 core\n",
        '#version 460 core\n\n#include "tile_batch_vertex.glsl"\n',
        1,
    )
    source = source.replace(
        "void main() {\n",
        "void main() {\n"
        "    uint tile_slot = tile_batch_slot();\n"
        "    v_tile_id = tile_batch_id(tile_slot);\n"
        "    v_tile_slot = float(tile_slot);\n",
        1,
    )
    return header("vert", stem) + source


def fragment(stem: str) -> str:
    source = (SHADERS / f"{stem}.frag").read_text()
    tile_props = [m.group(2) for m in BLOCK.finditer(source) if m.group(2).endswith("TilePropsUBO")]
    for block in tile_props:
        source = batch_block(source, block, "tile_props", "tile_slot")
    source = source.replace(
        "#version 460 core\n",
        '#version 460 core\n\n#include "tile_batch_fragment.glsl"\n',
        1,
    )
    source = source.replace(
        "void main() {\n",
        "void main() {\n"
        "    uint tile_slot = uint(v_tile_slot + 0.5);\n"
        "    tile_batch_clip();\n",
        1,
    )
    return header("frag", stem) + source


def main() -> None:
    manifest = json.loads(MANIFEST.read_text())
    for stem, name in VERTEX_SOURCES:
        target = f"{stem}_batched.vert"
        (SHADERS / target).write_text(vertex(stem))
        manifest[f"{name}BatchedVertex"] = {"type": "vertex", "file": target}
    for stem, name in FRAGMENT_SOURCES:
        target = f"{stem}_batched.frag"
        (SHADERS / target).write_text(fragment(stem))
        manifest[f"{name}BatchedFragment"] = {"type": "fragment", "file": target}
    manifest["TileMaskIdVertex"] = {"type": "vertex", "file": "tile_mask_id.vert"}
    manifest["TileMaskIdFragment"] = {"type": "fragment", "file": "tile_mask_id.frag"}
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
