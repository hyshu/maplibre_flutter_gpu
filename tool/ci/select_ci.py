#!/usr/bin/env python3
"""Select required CI jobs from pull request changes and additive labels."""

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


ALL_JOBS = (
    "native-contracts", "quality", "linux", "linux_visual", "linux_compat",
    "linux_arm64", "windows", "windows_visual", "windows_arm64",
    "firebase_preflight", "native_ios", "consumer_ios", "package",
    "ios_visual", "macos_visual", "macos_functional", "android_e2e_gate",
    "native_android", "consumer_android", "android_e2e_apks",
    "android_e2e_firebase", "android_visual", "native_macos", "consumer_macos",
)

JOB_DEPENDENCIES = {
    "quality": ("linux",),
    "linux_visual": ("linux",),
    "linux_compat": ("linux",),
    "windows_visual": ("windows",),
    "consumer_ios": ("quality", "native_ios"),
    "package": ("quality", "native_android", "native_macos"),
    "ios_visual": ("quality", "native_ios"),
    "macos_visual": ("quality", "native_macos"),
    "macos_functional": ("quality", "native_macos"),
    "android_e2e_gate": ("quality", "firebase_preflight"),
    "consumer_android": ("quality", "native_android"),
    "android_e2e_apks": (
        "firebase_preflight", "native_android", "consumer_android",
    ),
    "android_e2e_firebase": (
        "quality", "native_android", "consumer_android", "android_e2e_gate",
        "android_e2e_apks",
    ),
    "android_visual": ("android_e2e_firebase",),
    "native_macos": ("native_ios",),
    "consumer_macos": ("quality", "native_macos"),
}

PLATFORM_JOBS = {
    "android": {"consumer_android", "android_visual"},
    "ios": {"consumer_ios", "ios_visual"},
    "macos": {"consumer_macos", "macos_visual", "macos_functional"},
    "linux": {"linux_visual", "linux_compat", "linux_arm64"},
    "windows": {"windows_visual", "windows_arm64"},
}
VISUAL_JOBS = {
    "android_visual", "ios_visual", "macos_visual", "macos_functional",
    "linux_visual", "linux_compat", "linux_arm64", "windows_visual",
    "windows_arm64",
}
BASE_JOBS = {"quality", "native-contracts"}
CONSUMER_JOBS = {"consumer_android", "consumer_ios", "consumer_macos"}
EXAMPLE_NAMES = {"gpu_map_scene", "map_layers", "map_style_controls", "tv_map_explorer"}
SHARED_DART_PREFIXES = (
    "lib/src/state/", "lib/src/controller/", "lib/src/geo/",
    "lib/src/labels/", "lib/src/sprites/", "lib/src/widgets/",
)
GPU_WIDGET_PATHS = {
    "lib/src/widgets/map_gpu_painter.dart",
    "lib/src/widgets/maplibre_map.dart",
    "lib/src/state/map_render_scheduler.dart",
    "lib/src/state/map_style_session.dart",
    "lib/src/state/external_camera.dart",
}


def _is_documentation(path):
    return (
        path.endswith(".md")
        or path in {"LICENSE", ".gitignore", ".github/FUNDING.yml"}
        or path.startswith(("doc/", ".agents/", ".claude/", ".github/ISSUE_TEMPLATE/"))
    )


def _jobs_for_path(path):
    if _is_documentation(path):
        return set()
    if PurePosixPath(path).name in {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml"}:
        return set(ALL_JOBS)
    if path.startswith(("test/", "e2e/visual/runner/test/", "e2e/visual/shared/test/")):
        return set(BASE_JOBS)

    for platform, jobs in PLATFORM_JOBS.items():
        if path.startswith((f"{platform}/", f"native/platforms/{platform}/")):
            return BASE_JOBS | jobs
        if path in {f"native/scripts/build_{platform}.sh", f"native/scripts/build_{platform}.ps1"}:
            return BASE_JOBS | jobs
    if path.startswith("darwin/"):
        return BASE_JOBS | PLATFORM_JOBS["ios"] | PLATFORM_JOBS["macos"]

    parts = PurePosixPath(path).parts
    example_parts = None
    if parts[0] == "example":
        example_parts = parts[1:]
    elif len(parts) > 2 and parts[0] == "examples" and parts[1] in EXAMPLE_NAMES:
        example_parts = parts[2:]
    if example_parts:
        category = example_parts[0]
        if category == "test":
            return set(BASE_JOBS)
        if category in {"android", "ios", "macos"}:
            return BASE_JOBS | {f"consumer_{category}"}
        if category in {"linux", "windows"}:
            return BASE_JOBS | PLATFORM_JOBS[category]
        if category in {"lib", "assets", "integration_test"}:
            return BASE_JOBS | CONSUMER_JOBS
        return set(ALL_JOBS)

    for platform, jobs in PLATFORM_JOBS.items():
        if path in {f"e2e/visual/run_{platform}.sh", f"e2e/visual/run_{platform}.ps1"}:
            return BASE_JOBS | jobs
        if path.startswith(f"e2e/visual/baseline/{platform}-"):
            return BASE_JOBS | jobs
        if any(path.startswith(f"e2e/visual/{app}/{platform}/") for app in ("gpu_app", "maplibre_gl_app")):
            return BASE_JOBS | jobs
    for platform in ("android", "ios"):
        if path == f"e2e/visual/run_flutter_markers_{platform}.sh":
            return BASE_JOBS | PLATFORM_JOBS[platform]
    if path.startswith("e2e/visual/"):
        return BASE_JOBS | VISUAL_JOBS

    if (
        path.endswith(".dart")
        and path.startswith(SHARED_DART_PREFIXES)
        and path not in GPU_WIDGET_PATHS
        and not path.startswith("lib/src/widgets/map/")
    ):
        return BASE_JOBS | {"macos_visual", "macos_functional"}
    return set(ALL_JOBS)


def select_jobs(changed_paths, labels, event_name):
    """Return every job with a boolean selection, including artifact dependencies.

    Labels only add checks. Empty or unrecognized changes run the full suite.
    """
    if event_name != "pull_request" or not changed_paths:
        return dict.fromkeys(ALL_JOBS, True)

    selected = set()
    for path in changed_paths:
        if (
            not isinstance(path, str) or not PurePosixPath(path).parts
            or path.startswith("/") or ".." in path.split("/")
        ):
            return dict.fromkeys(ALL_JOBS, True)
        selected.update(_jobs_for_path(path))
    for label in labels:
        label = label.casefold()
        if label == "ci:visual":
            selected.update(BASE_JOBS | VISUAL_JOBS)
        elif label.startswith("ci:"):
            platform = label.removeprefix("ci:")
            if platform not in PLATFORM_JOBS:
                return dict.fromkeys(ALL_JOBS, True)
            selected.update(BASE_JOBS | PLATFORM_JOBS[platform])

    pending = list(selected)
    while pending:
        for dependency in JOB_DEPENDENCIES.get(pending.pop(), ()):
            if dependency not in selected:
                selected.add(dependency)
                pending.append(dependency)
    return {job: job in selected for job in ALL_JOBS}


def pull_request_changes(event):
    """Read both sides of changes, including renamed and deleted files.

    Invalid event data or an unavailable Git comparison raises an error so the
    selection job cannot approve an incomplete plan.
    """
    pull_request = event["pull_request"]
    base_sha = pull_request["base"]["sha"]
    head_sha = pull_request["head"]["sha"]
    for sha in (base_sha, head_sha):
        if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", sha):
            raise ValueError("Pull request base and head must be full Git commit IDs")
    result = subprocess.run(
        ["git", "diff", "--no-renames", "--name-only", "-z", f"{base_sha}...{head_sha}", "--"],
        check=True, stdout=subprocess.PIPE,
    )
    paths = os.fsdecode(result.stdout).split("\0")
    labels = pull_request["labels"]
    if not isinstance(labels, list) or any(
        not isinstance(label, dict) or not isinstance(label.get("name"), str)
        for label in labels
    ):
        raise ValueError("Pull request labels must include their names")
    return [path for path in paths if path], [label["name"] for label in labels]


def main():
    """Write a complete plan for GitHub Actions or fail without an output."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-path", default=os.environ.get("GITHUB_EVENT_PATH"))
    parser.add_argument("--event-name", default=os.environ.get("GITHUB_EVENT_NAME"))
    args = parser.parse_args()
    if not args.event_name:
        parser.error("--event-name or GITHUB_EVENT_NAME is required")
    try:
        paths, labels = [], []
        if args.event_name == "pull_request":
            if not args.event_path:
                raise ValueError("Pull request event data is required")
            paths, labels = pull_request_changes(json.loads(Path(args.event_path).read_text()))
        jobs = select_jobs(paths, labels, args.event_name)
        encoded = json.dumps(jobs, separators=(",", ":"))
        if output_path := os.environ.get("GITHUB_OUTPUT"):
            with open(output_path, "a", encoding="utf-8") as output:
                output.write(f"jobs={encoded}\n")
        print(encoded)
        if summary_path := os.environ.get("GITHUB_STEP_SUMMARY"):
            selected = ", ".join(job for job, enabled in jobs.items() if enabled) or "None"
            skipped = ", ".join(job for job, enabled in jobs.items() if not enabled) or "None"
            reasons = [
                {"path": path, "jobs": sorted(_jobs_for_path(path))}
                for path in paths
            ]
            with open(summary_path, "a", encoding="utf-8") as summary:
                summary.write(
                    f"### CI selection\n\nSelected: {selected}\n\nSkipped: {skipped}\n\n"
                    "Non-PR events and unknown changes run full CI. Labels only add jobs. "
                    "Artifact dependencies are included automatically.\n\n"
                    "<details><summary>Changed paths and requested checks</summary>\n\n"
                    f"```json\n{json.dumps({'event': args.event_name, 'labels': labels, 'changes': reasons}, indent=2)}\n```\n\n"
                    "</details>\n"
                )
    except (KeyError, TypeError, ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Cannot safely select CI jobs: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
