#!/usr/bin/env python3
"""Validate required CI results against the complete selection plan."""

from __future__ import annotations

import json
import os
import sys

from select_ci import ALL_JOBS, JOB_DEPENDENCIES


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value

    return result


def _invalid_constant(value: str) -> None:
    raise ValueError(f"invalid JSON constant {value}")


def _parse_object(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a nonempty JSON object string")
    try:
        parsed = json.loads(
            value,
            object_pairs_hook=_unique_object,
            parse_constant=_invalid_constant,
        )
    except ValueError as error:
        raise ValueError(f"invalid {label}: {error}") from error
    if not isinstance(parsed, dict):
        raise ValueError(f"{label} must be a JSON object")

    return parsed


def _check_keys(actual: dict[str, object], expected: set[str], label: str) -> None:
    missing = expected - actual.keys()
    unknown = actual.keys() - expected
    if missing or unknown:
        details = []
        if missing:
            details.append(f"missing {', '.join(sorted(missing))}")
        if unknown:
            details.append(f"unknown {', '.join(sorted(unknown))}")
        raise ValueError(f"{label} has invalid job keys ({'; '.join(details)})")


def verify_needs(payload: str) -> tuple[list[str], list[str]]:
    """Require selected jobs to succeed and unselected jobs to remain skipped."""
    needs = _parse_object(payload, "CI_NEEDS_JSON")
    _check_keys(needs, {"select", *ALL_JOBS}, "needs")
    selection = needs["select"]
    if not isinstance(selection, dict) or selection.get("result") != "success":
        raise ValueError("select must finish with result 'success'")
    outputs = selection.get("outputs")
    if not isinstance(outputs, dict):
        raise ValueError("select.outputs must contain the jobs plan")
    plan = _parse_object(outputs.get("jobs"), "select.outputs.jobs")
    _check_keys(plan, set(ALL_JOBS), "selection plan")
    for job, selected in plan.items():
        if type(selected) is not bool:
            raise ValueError(f"selection plan value for {job} must be boolean")
    for job in ALL_JOBS:
        if plan[job]:
            for dependency in JOB_DEPENDENCIES.get(job, ()):
                if not plan[dependency]:
                    raise ValueError(
                        f"selected job {job} requires selected dependency {dependency}"
                    )

    selected_jobs = []
    skipped_jobs = []
    for job in ALL_JOBS:
        entry = needs[job]
        if not isinstance(entry, dict):
            raise ValueError(f"needs.{job} must be an object")
        expected = "success" if plan[job] else "skipped"
        actual = entry.get("result")
        if actual != expected:
            raise ValueError(
                f"{job} must finish with result {expected!r}, got {actual!r}"
            )
        (selected_jobs if plan[job] else skipped_jobs).append(job)

    return selected_jobs, skipped_jobs


def main() -> int:
    """Read GitHub Actions needs from the environment and report gate status."""
    try:
        selected, skipped = verify_needs(os.environ.get("CI_NEEDS_JSON", ""))
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)

        return 1
    print(f"Required CI passed. Selected {len(selected)}, skipped {len(skipped)}.")
    if selected:
        print(f"Selected jobs: {', '.join(selected)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
