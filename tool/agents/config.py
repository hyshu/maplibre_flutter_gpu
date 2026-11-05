"""Shared configuration for the branch review and device verification harness.

Device identifiers and tool paths describe the machine this harness runs on.
Update them when the attached hardware or the Flutter and Android SDK
installations change. Both branch_agent.py and device_verify.py read these
values, so a single edit here keeps the review and the measurement in step.
"""

import json
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
AGENTS_DIR = PACKAGE_ROOT / "tool" / "agents"
COMPARE_ROOT = PACKAGE_ROOT.parent / "maplibre_compare"
HOUSE_RULES = AGENTS_DIR / "house_rules.md"

# Review model settings. Fable 5.1 keeps thinking always on, so the harness
# never passes a thinking configuration and controls depth through effort only.
MODEL = "claude-fable-5-1"
EFFORT = "max"
FALLBACK_MODEL = "claude-opus-5-5"

# Cost ceiling applied to every single agent session, in US dollars. The SDK
# stops a session that reaches it, so a runaway review ends instead of billing.
DEFAULT_BUDGET_USD = 8.0
DEFAULT_CONCURRENCY = 3
DEFAULT_MAX_TURNS = 120

# Toolchain paths. adb is not on PATH on this machine.
ADB = Path.home() / "Library/Android/sdk/platform-tools/adb"
FLUTTER = Path.home() / "flutter/bin/flutter"

# Attached hardware used for verification.
ANDROID_DEVICE = "d2a541ec0721"
ANDROID_DEVICE_NAME = "XIG02 (Android 13)"
IOS_DEVICE = "00008101-001904301E2A001E"
IOS_DEVICE_NAME = "iPhone 12 mini, wired"

BASE_REF = "main"

READ_ONLY_TOOLS = ["Read", "Grep", "Glob", "Bash", "Task", "TodoWrite"]
WRITE_TOOLS = ["Write", "Edit", "NotebookEdit"]

# Review dimension sets live as data under dimensions/, one JSON file per
# branch under review. Keeping them out of this module lets the harness sit on
# its own branch while the paths it reviews belong to another one.
DIMENSIONS_DIR = AGENTS_DIR / "dimensions"

DIMENSION_PLATFORMS = ("android", "ios", "shared", "none")


def dimension_sets():
    """Return the available review set names, sorted."""

    return sorted(path.stem for path in DIMENSIONS_DIR.glob("*.json"))


def load_dimension_set(name_or_path):
    """Load one review set by name under dimensions/ or by file path.

    Returns the parsed object with its "dimensions" mapping. Raises
    FileNotFoundError when no such set exists, and ValueError when the file
    does not hold the expected shape.
    """
    candidate = Path(name_or_path)
    if not candidate.suffix:
        candidate = DIMENSIONS_DIR / f"{name_or_path}.json"
    if not candidate.is_file():
        available = ", ".join(dimension_sets()) or "none"
        raise FileNotFoundError(
            f"no review set at {candidate}. Available sets: {available}"
        )
    payload = json.loads(candidate.read_text())
    validate_dimension_set(payload, candidate)

    return payload


def validate_dimension_set(payload, source):
    """Check the shape a review set must have before any session starts."""
    if not isinstance(payload, dict) or "dimensions" not in payload:
        raise ValueError(f"{source} has no dimensions mapping")
    dimensions = payload["dimensions"]
    if not isinstance(dimensions, dict) or not dimensions:
        raise ValueError(f"{source} holds no dimensions")
    owners = {}
    for key, dimension in dimensions.items():
        for field in ("title", "platforms", "paths", "focus"):
            if field not in dimension:
                raise ValueError(f"{source}: dimension {key} has no {field}")
        if dimension["platforms"] not in DIMENSION_PLATFORMS:
            raise ValueError(
                f"{source}: dimension {key} has an unknown platforms value "
                f"{dimension['platforms']!r}"
            )
        if not isinstance(dimension["paths"], list):
            raise ValueError(f"{source}: dimension {key} has a non-list paths")
        for entry in dimension["paths"]:
            if entry in owners:
                raise ValueError(
                    f"{source}: {entry} is claimed by both {owners[entry]} and {key}"
                )
            owners[entry] = key


def missing_paths(dimensions, root=None):
    """Return the reviewed paths that do not exist in the tree.

    A review set names the files of the branch it reviews, so a missing path
    means the wrong branch is checked out rather than a broken set.
    """
    base = Path(root) if root is not None else PACKAGE_ROOT
    absent = []
    for key, dimension in dimensions.items():
        for entry in dimension["paths"]:
            if not (base / entry).exists():
                absent.append((key, entry))

    return absent
