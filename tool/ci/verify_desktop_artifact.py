#!/usr/bin/env python3
"""Verify desktop bridge exports, dependencies, and stable ABI values."""

from __future__ import annotations

import argparse
import ctypes
from pathlib import Path
import re
import shutil
import subprocess
import sys


API_PATTERN = re.compile(
    r"\bMAPLIBRE_API\b(?:(?!\bMAPLIBRE_API\b).)*?"
    r"\b(maplibre_[A-Za-z0-9_]+)\s*\(",
    re.DOTALL,
)
SYMBOL_PATTERN = re.compile(r"\bmaplibre_[A-Za-z0-9_]+\b")
WINDOWS_EXPORT_PATTERN = re.compile(
    r"^\s*\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+"
    r"(maplibre_[A-Za-z0-9_]+)(?:\s|$)",
    re.MULTILINE,
)
REQUIRED_SESSION_EXPORTS = {
    "maplibre_session_create",
    "maplibre_session_release",
    "maplibre_session_select",
    "maplibre_shutdown_all",
}
EXPECTED_STRIDES = {
    "maplibre_frame_get_command_stride": 400,
    "maplibre_get_label_stride": 344,
    "maplibre_get_label_static_stride": 200,
    "maplibre_get_label_dynamic_stride": 152,
}


def run_tool(arguments: list[str]) -> str:
    result = subprocess.run(
        arguments,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    return result.stdout


def source_exports(source_directory: Path) -> set[str]:
    exports: set[str] = set()
    for source in sorted(source_directory.glob("*.cpp")):
        exports.update(API_PATTERN.findall(source.read_text(encoding="utf-8")))
    missing_session_exports = REQUIRED_SESSION_EXPORTS - exports
    if missing_session_exports:
        missing = ", ".join(sorted(missing_session_exports))
        raise RuntimeError(f"bridge sources omit session exports: {missing}")
    if len(exports) < 70:
        raise RuntimeError(
            f"bridge source export scan found only {len(exports)} functions"
        )

    return exports


def library_exports(platform: str, library: Path) -> set[str]:
    if platform == "linux":
        output = run_tool(
            ["nm", "--dynamic", "--defined-only", "--extern-only", str(library)]
        )
        return set(SYMBOL_PATTERN.findall(output))

    output = run_tool(["dumpbin", "/nologo", "/exports", str(library)])

    return set(WINDOWS_EXPORT_PATTERN.findall(output))


def verify_exports(expected: set[str], actual: set[str]) -> None:
    missing = expected - actual
    unexpected = actual - expected
    if missing:
        raise RuntimeError(f"missing bridge exports: {', '.join(sorted(missing))}")
    if unexpected:
        raise RuntimeError(
            f"unexpected bridge exports: {', '.join(sorted(unexpected))}"
        )


def verify_linux_dependencies(library: Path) -> None:
    undefined = run_tool(["nm", "--dynamic", "--undefined-only", str(library)])
    if re.search(r"\bglX[A-Za-z0-9_]*\b", undefined):
        raise RuntimeError("FlutterGPU bridge unexpectedly references GLX")

    objdump = shutil.which("objdump")
    if not objdump:
        return
    dependencies = run_tool([objdump, "-p", str(library)])
    if re.search(r"\bNEEDED\s+lib(?:Open)?GL(?:X|dispatch)?\.so", dependencies):
        raise RuntimeError("FlutterGPU bridge unexpectedly links an OpenGL library")


def verify_runtime_abi(library: Path) -> None:
    bridge = ctypes.CDLL(str(library.resolve()))
    create = bridge.maplibre_session_create
    create.argtypes = []
    create.restype = ctypes.c_void_p
    select = bridge.maplibre_session_select
    select.argtypes = [ctypes.c_void_p]
    select.restype = None
    release = bridge.maplibre_session_release
    release.argtypes = [ctypes.c_void_p]
    release.restype = None

    first = create()
    second = create()
    if not first or not second or first == second:
        raise RuntimeError("bridge did not allocate two distinct sessions")
    try:
        select(first)
        for name, expected in EXPECTED_STRIDES.items():
            function = getattr(bridge, name)
            function.restype = ctypes.c_int
            actual = function()
            if actual != expected:
                raise RuntimeError(f"{name} returned {actual}, expected {expected}")
        select(second)
        select(first)
    finally:
        select(None)
        release(first)
        release(second)


def parse_arguments() -> argparse.Namespace:
    repository_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("linux", "windows"), required=True)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument(
        "--source-directory",
        type=Path,
        default=repository_root / "native" / "src",
    )

    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    library = arguments.library
    if not library.is_file():
        raise RuntimeError(f"bridge not found: {library}")

    expected = source_exports(arguments.source_directory)
    actual = library_exports(arguments.platform, library)
    verify_exports(expected, actual)
    if arguments.platform == "linux":
        verify_linux_dependencies(library)
    verify_runtime_abi(library)
    print(f"Verified {len(expected)} bridge exports and desktop ABI: {library}")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
