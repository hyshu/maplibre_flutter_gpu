#!/usr/bin/env python3
"""Review this branch and interpret its device measurements with the Agent SDK.

Three subcommands cover the parts of the workflow that need judgement. "review"
runs one read only session per dimension of a review set under dimensions/ and
collects findings. "plan" turns those findings into a measurement plan that
obeys house_rules.md. "interpret" reads measurement JSON produced by
device_verify.py and drafts the findings document.

The harness never measures performance itself and never edits the tree. Agents
run with the write tools denied, so a session can only read, search and run
commands. Measurement stays in device_verify.py and in the maplibre_compare
tools, which are deterministic.

Every session carries a dollar ceiling. Reaching it ends that session, so the
worst case cost of a run is the ceiling times the number of sessions.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import config  # noqa: E402

FINDINGS_SCHEMA = {
    "type": "json_schema",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["findings", "coverage"],
        "properties": {
            "findings": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "title",
                        "file",
                        "line",
                        "kind",
                        "confidence",
                        "defect",
                        "trigger",
                        "suggested_fix",
                        "device_check",
                    ],
                    "properties": {
                        "title": {"type": "string"},
                        "file": {"type": "string"},
                        "line": {"type": "integer"},
                        "kind": {
                            "type": "string",
                            "enum": [
                                "correctness",
                                "memory-safety",
                                "lifecycle",
                                "performance",
                                "style",
                            ],
                        },
                        "confidence": {
                            "type": "string",
                            "enum": ["confirmed", "plausible"],
                        },
                        "defect": {"type": "string"},
                        "trigger": {"type": "string"},
                        "suggested_fix": {"type": "string"},
                        "device_check": {"type": "string"},
                    },
                },
            },
            "coverage": {
                "type": "object",
                "additionalProperties": False,
                "required": ["read", "not_read"],
                "properties": {
                    "read": {"type": "array", "items": {"type": "string"}},
                    "not_read": {"type": "array", "items": {"type": "string"}},
                },
            },
        },
    },
}

PLAN_SCHEMA = {
    "type": "json_schema",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["experiments", "skipped"],
        "properties": {
            "experiments": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "name",
                        "hypothesis",
                        "configurations",
                        "scenes",
                        "devices",
                        "runs_per_configuration",
                        "order",
                        "must_record",
                        "decides",
                    ],
                    "properties": {
                        "name": {"type": "string"},
                        "hypothesis": {"type": "string"},
                        "configurations": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "additionalProperties": False,
                                "required": ["label", "dart_defines"],
                                "properties": {
                                    "label": {"type": "string"},
                                    "dart_defines": {
                                        "type": "array",
                                        "items": {"type": "string"},
                                    },
                                },
                            },
                        },
                        "scenes": {"type": "array", "items": {"type": "string"}},
                        "devices": {
                            "type": "array",
                            "items": {"type": "string", "enum": ["android", "ios"]},
                        },
                        "runs_per_configuration": {"type": "integer"},
                        "order": {"type": "string"},
                        "must_record": {"type": "array", "items": {"type": "string"}},
                        "decides": {"type": "string"},
                    },
                },
            },
            "skipped": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["name", "reason"],
                    "properties": {
                        "name": {"type": "string"},
                        "reason": {"type": "string"},
                    },
                },
            },
        },
    },
}

INTERPRET_SCHEMA = {
    "type": "json_schema",
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["markdown", "supported", "withheld", "comparability"],
        "properties": {
            "markdown": {"type": "string"},
            "supported": {"type": "array", "items": {"type": "string"}},
            "withheld": {"type": "array", "items": {"type": "string"}},
            "comparability": {
                "type": "object",
                "additionalProperties": False,
                "required": ["ok", "problems"],
                "properties": {
                    "ok": {"type": "boolean"},
                    "problems": {"type": "array", "items": {"type": "string"}},
                },
            },
        },
    },
}


def house_rules() -> str:
    return config.HOUSE_RULES.read_text()


def sdk():
    """Import the Agent SDK on demand.

    Listing review sets and validating them must work without the SDK
    installed, so nothing imports it at module level.
    """
    import claude_agent_sdk

    return claude_agent_sdk


def session_options(
    budget_usd: float,
    max_turns: int,
    schema: dict,
    extra_dirs: list[Path] | None = None,
) -> ClaudeAgentOptions:
    """Build read only options shared by every session in this harness.

    The write tools are denied rather than merely left out of allowed_tools,
    because allowed_tools only decides what runs without a prompt.
    """
    return sdk().ClaudeAgentOptions(
        model=config.MODEL,
        effort=config.EFFORT,
        fallback_model=config.FALLBACK_MODEL,
        cwd=str(config.PACKAGE_ROOT),
        add_dirs=[str(path) for path in (extra_dirs or [])],
        allowed_tools=config.READ_ONLY_TOOLS,
        disallowed_tools=config.WRITE_TOOLS,
        permission_mode="acceptEdits",
        setting_sources=["project"],
        max_turns=max_turns,
        max_budget_usd=budget_usd,
        output_format=schema,
        env={
            "PATH": f"{config.ADB.parent}:{config.FLUTTER.parent}:"
            + os.environ.get("PATH", "")
        },
    )


async def run_session(
    label: str,
    prompt: str,
    options: ClaudeAgentOptions,
    transcript_path: Path | None = None,
) -> dict:
    """Run one session and return its structured output with session metadata.

    The returned dictionary always holds "label", "ok" and "cost_usd". On
    success it holds "output" with the schema shaped result. On failure it holds
    "error" and the last assistant text, which is where a refusal or a budget
    stop explains itself.
    """
    agent_sdk = sdk()
    started = time.monotonic()
    texts: list[str] = []
    result = None
    async for message in agent_sdk.query(prompt=prompt, options=options):
        if isinstance(message, agent_sdk.AssistantMessage):
            for block in message.content:
                if isinstance(block, agent_sdk.TextBlock):
                    texts.append(block.text)
        elif isinstance(message, agent_sdk.ResultMessage):
            result = message
    elapsed = time.monotonic() - started
    if transcript_path is not None:
        transcript_path.write_text("\n\n".join(texts))
    record = {
        "label": label,
        "model": config.MODEL,
        "effort": config.EFFORT,
        "elapsed_s": round(elapsed, 1),
        "cost_usd": getattr(result, "total_cost_usd", None) if result else None,
        "session_id": getattr(result, "session_id", None) if result else None,
        "stop_reason": getattr(result, "stop_reason", None) if result else None,
        "num_turns": getattr(result, "num_turns", None) if result else None,
    }
    structured = getattr(result, "structured_output", None) if result else None
    if structured:
        record["ok"] = True
        record["output"] = structured
    else:
        record["ok"] = False
        record["error"] = "no structured output"
        record["last_text"] = texts[-1] if texts else ""
        if result is not None and result.is_error:
            record["error"] = f"session error: {result.subtype}"
    return record


def review_prompt(dimension: dict, base: str) -> str:
    paths = dimension["paths"]
    if paths:
        scope = "\n".join(f"- {path}" for path in paths)
        diff_command = (
            f"git diff {base}...HEAD -- " + " ".join(f"'{path}'" for path in paths)
        )
    else:
        scope = "- the whole branch diff"
        diff_command = f"git diff {base}...HEAD"
    return f"""You are reviewing one dimension of a Flutter GPU map rendering branch
before it is proposed for merge. The branch holds Android render and memory
work across 25 commits.

Dimension: {dimension['title']}

Scope:
{scope}

Start by reading the diff:

    {diff_command}

Then read the current files at HEAD around every hunk, and read the tests that
cover them. Use `git log {base}..HEAD --oneline` when the intent of a hunk is
unclear, and read the commit that introduced it.

{dimension['focus']}

Rules you must follow:

{house_rules()}

Report every defect you can tie to a concrete input or state. For each one, set
"confidence" to "confirmed" only when you traced the triggering path through
the code you read. Set "device_check" to the measurement or on device
observation that would settle it, or to an empty string when code reading
settles it. In "coverage", list the files you actually read and the files in
scope you did not read. An empty findings list is a valid answer when the
dimension is sound.
"""


def plan_prompt(findings: list[dict], base: str) -> str:
    payload = json.dumps(findings, indent=2, ensure_ascii=False)
    return f"""You are planning device verification for a Flutter GPU map rendering
branch. The review findings below came from a static review of the branch diff.

The measurement application lives at {config.COMPARE_ROOT}. Read its README and
its tool directory before planning. Attached hardware:

- android: {config.ANDROID_DEVICE_NAME}, adb serial {config.ANDROID_DEVICE}
- ios: {config.IOS_DEVICE_NAME}, device id {config.IOS_DEVICE}

Rules you must follow:

{house_rules()}

Findings:

{payload}

Produce the smallest set of experiments that would decide the open questions on
this branch, including the flags that currently default to off. Use the scene
names the measurement application defines. Express each configuration as the
exact dart-define arguments to pass to a profile build. Put an experiment on
ios only when the change it tests reaches shared Dart or native code, and list
every experiment you leave out under "skipped" with its reason. Keep
"runs_per_configuration" at three or more and state the alternation in "order".
Prefer reusing an existing provenance and build script in
{config.COMPARE_ROOT}/tool over proposing a new one, and name the script you
would reuse in "must_record".
"""


def interpret_prompt(result_paths: list[Path], question: str) -> str:
    listed = "\n".join(f"- {path}" for path in result_paths)
    return f"""You are interpreting device measurements of a Flutter GPU map rendering
branch and drafting the findings document.

Measurement files:
{listed}

Read every file. They are benchmark reports from the application at
{config.COMPARE_ROOT}. The fields that matter are the top level scene,
device_pixel_ratio, map_logical_size, refresh_rate_hz, route_duration_ms and
gpu_revision, and per result engine, flutter_build, flutter_raster,
camera_apply, process_cpu_one_core_percent, flutter_over_budget_percent,
map_idle_observed_before_measurement, android_before and android_after.

Question to answer: {question}

Rules you must follow:

{house_rules()}

First check comparability. Set "comparability".ok to false and list every
problem when the files disagree on scene, viewport, map logical size, device
pixel ratio, refresh rate or route duration, or when a configuration has fewer
than three runs. Then compute the median of the per run p50 and p95 values for
each configuration and compare matched pairs.

Write "markdown" as a findings section in the style of the existing documents
under {config.COMPARE_ROOT}/results. State the numbers with units, then state
what the measurement does not show. List every claim the data supports in
"supported" and every claim a reader might expect but the data does not support
in "withheld". Recommend keeping a flag default off when the per pair
differences do not point the same way.
"""


async def command_review(args: argparse.Namespace) -> int:
    payload = config.load_dimension_set(args.dimensions)
    dimensions = payload["dimensions"]
    keys = args.dimension or list(dimensions)
    unknown = [key for key in keys if key not in dimensions]
    if unknown:
        print(f"unknown dimension: {', '.join(unknown)}", file=sys.stderr)

        return 2
    selected = {key: dimensions[key] for key in keys}
    absent = config.missing_paths(selected)
    if absent and not args.allow_missing_paths:
        print(
            f"{len(absent)} reviewed paths do not exist in this tree. "
            "Check out the branch this set reviews, or pass --allow-missing-paths.",
            file=sys.stderr,
        )
        for key, entry in absent:
            print(f"  {key}: {entry}", file=sys.stderr)

        return 2
    base = args.base or payload.get("base", config.BASE_REF)
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    semaphore = asyncio.Semaphore(args.concurrency)

    async def one(key: str) -> dict:
        dimension = dimensions[key]
        async with semaphore:
            print(f"[review] {key}: {dimension['title']}", flush=True)
            record = await run_session(
                label=key,
                prompt=review_prompt(dimension, base),
                options=session_options(
                    budget_usd=args.budget,
                    max_turns=args.max_turns,
                    schema=FINDINGS_SCHEMA,
                ),
                transcript_path=out / f"review-{key}.txt",
            )
        (out / f"review-{key}.json").write_text(
            json.dumps(record, indent=2, ensure_ascii=False) + "\n"
        )
        findings = record.get("output", {}).get("findings", []) if record["ok"] else []
        cost = record.get("cost_usd")
        print(
            f"[review] {key}: {len(findings)} findings, "
            f"{'ok' if record['ok'] else record.get('error')}, "
            f"${cost if cost is not None else 0:.2f}",
            flush=True,
        )

        return record

    records = await asyncio.gather(*(one(key) for key in keys))
    summary = summarize(records)
    (out / "review-summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n"
    )
    print(
        f"\n{summary['finding_count']} findings across {len(records)} dimensions, "
        f"${summary['cost_usd']:.2f} total"
    )
    print(f"written to {out}")

    return 0 if all(record["ok"] for record in records) else 1


def summarize(records: list[dict]) -> dict:
    findings: list[dict] = []
    for record in records:
        if not record["ok"]:
            continue
        for finding in record["output"].get("findings", []):
            findings.append({"dimension": record["label"], **finding})
    order = {"confirmed": 0, "plausible": 1}
    kind_order = {
        "memory-safety": 0,
        "correctness": 1,
        "lifecycle": 2,
        "performance": 3,
        "style": 4,
    }
    findings.sort(
        key=lambda item: (
            order.get(item.get("confidence"), 9),
            kind_order.get(item.get("kind"), 9),
            item.get("file", ""),
        )
    )

    return {
        "model": config.MODEL,
        "effort": config.EFFORT,
        "finding_count": len(findings),
        "cost_usd": round(
            sum(record.get("cost_usd") or 0.0 for record in records), 4
        ),
        "sessions": [
            {
                key: record.get(key)
                for key in ("label", "ok", "error", "cost_usd", "session_id", "stop_reason")
            }
            for record in records
        ],
        "findings": findings,
    }


async def command_plan(args: argparse.Namespace) -> int:
    summary = json.loads(args.findings.read_text())
    findings = summary.get("findings", summary)
    record = await run_session(
        label="plan",
        prompt=plan_prompt(findings, args.base),
        options=session_options(
            budget_usd=args.budget,
            max_turns=args.max_turns,
            schema=PLAN_SCHEMA,
            extra_dirs=[config.COMPARE_ROOT],
        ),
        transcript_path=args.out / "plan.txt",
    )
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "measure-plan.json").write_text(
        json.dumps(record, indent=2, ensure_ascii=False) + "\n"
    )
    if not record["ok"]:
        print(f"plan failed: {record.get('error')}", file=sys.stderr)

        return 1
    experiments = record["output"]["experiments"]
    print(f"{len(experiments)} experiments, ${record.get('cost_usd') or 0:.2f}")
    for experiment in experiments:
        devices = ", ".join(experiment["devices"])
        print(
            f"- {experiment['name']}: {len(experiment['configurations'])} configs "
            f"x {experiment['runs_per_configuration']} runs on {devices}"
        )

    return 0


async def command_interpret(args: argparse.Namespace) -> int:
    paths = sorted(args.results)
    if not paths:
        print("no measurement files given", file=sys.stderr)

        return 2
    args.out.mkdir(parents=True, exist_ok=True)
    record = await run_session(
        label="interpret",
        prompt=interpret_prompt(paths, args.question),
        options=session_options(
            budget_usd=args.budget,
            max_turns=args.max_turns,
            schema=INTERPRET_SCHEMA,
            extra_dirs=[config.COMPARE_ROOT],
        ),
        transcript_path=args.out / "interpret.txt",
    )
    (args.out / "interpret.json").write_text(
        json.dumps(record, indent=2, ensure_ascii=False) + "\n"
    )
    if not record["ok"]:
        print(f"interpret failed: {record.get('error')}", file=sys.stderr)

        return 1
    output = record["output"]
    draft = args.out / "findings-draft.md"
    draft.write_text(output["markdown"].rstrip() + "\n")
    comparability = output["comparability"]
    if not comparability["ok"]:
        print("comparability problems:")
        for problem in comparability["problems"]:
            print(f"- {problem}")
    print(f"draft written to {draft}, ${record.get('cost_usd') or 0:.2f}")

    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    # Shared options live on a parent parser so that they are accepted after the
    # subcommand, which is where an operator types them.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--budget",
        type=float,
        default=config.DEFAULT_BUDGET_USD,
        help="dollar ceiling for each session",
    )
    common.add_argument("--max-turns", type=int, default=config.DEFAULT_MAX_TURNS)
    common.add_argument(
        "--out",
        type=Path,
        default=config.AGENTS_DIR / "out",
        help="directory for session records and drafts",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    review = sub.add_parser(
        "review", parents=[common], help="static review of the branch diff"
    )
    review.add_argument(
        "--dimension",
        action="append",
        help="dimension key, repeatable. Defaults to every dimension",
    )
    review.add_argument(
        "--dimensions",
        required=True,
        help="review set name under dimensions/, or a path to one",
    )
    review.add_argument(
        "--base",
        default=None,
        help="base ref for the diff. Defaults to the set's own base",
    )
    review.add_argument(
        "--allow-missing-paths",
        action="store_true",
        help="review anyway when some reviewed paths are absent",
    )
    review.add_argument("--concurrency", type=int, default=config.DEFAULT_CONCURRENCY)
    review.set_defaults(func=command_review)

    plan = sub.add_parser(
        "plan", parents=[common], help="draft a device measurement plan"
    )
    plan.add_argument(
        "--findings",
        type=Path,
        default=config.AGENTS_DIR / "out" / "review-summary.json",
    )
    plan.add_argument("--base", default=config.BASE_REF)
    plan.set_defaults(func=command_plan)

    interpret = sub.add_parser(
        "interpret", parents=[common], help="interpret measurement JSON"
    )
    interpret.add_argument("results", type=Path, nargs="+")
    interpret.add_argument(
        "--question",
        default="Do these measurements support turning the candidate on by default?",
    )
    interpret.set_defaults(func=command_interpret)

    listing = sub.add_parser(
        "dimensions", help="list review sets, or one set's dimensions"
    )
    listing.add_argument(
        "--dimensions", help="review set name or path. Omitted, lists the sets"
    )
    listing.set_defaults(func=None)

    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.command == "dimensions":
        if not args.dimensions:
            for name in config.dimension_sets():
                payload = config.load_dimension_set(name)
                print(
                    f"{name:24} {len(payload['dimensions']):2} dimensions  "
                    f"{payload.get('description', '')}"
                )

            return 0
        payload = config.load_dimension_set(args.dimensions)
        absent = {entry for _, entry in config.missing_paths(payload["dimensions"])}
        for key, dimension in payload["dimensions"].items():
            gone = sum(1 for entry in dimension["paths"] if entry in absent)
            state = f"{gone} absent" if gone else "present"
            print(
                f"{key:22} {dimension['platforms']:8} {state:10} {dimension['title']}"
            )

        return 0

    return asyncio.run(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
