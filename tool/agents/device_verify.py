#!/usr/bin/env python3
"""Drive device measurements for this branch without a model in the loop.

This script owns the parts of verification that must be reproducible. It checks
the attached hardware, runs the measurement application through the existing
maplibre_compare tools in an alternating order, and summarizes matched
configurations. No step here calls a model, so a repeated run of the same
command produces the same measurement procedure.

Subcommands:

    preflight   Report whether the Android and iOS devices are ready
    android     Run alternating measurements of prebuilt APKs on Android
    ios         Print the verified install command for a prebuilt IPA
    summary     Check comparability and compare matched configurations

Build the APKs and the IPA with a freeze script under
maplibre_compare/tool so that the provenance manifest records the source and
binary hashes. This script refuses to build, because a build that is not
recorded cannot be compared later.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import statistics
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import config  # noqa: E402

RUN_NAME = re.compile(r"^(?P<scene>[^-]+)-(?P<label>.+)-r(?P<run>\d+)\.json$")

COMPARABLE_FIELDS = (
    "scene",
    "route",
    "route_duration_ms",
    "warmup_rounds",
    "build_mode",
    "device_pixel_ratio",
    "refresh_rate_hz",
    "measurement_scope",
)


def run(command: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True)


def adb(*args: str) -> str:
    result = run([str(config.ADB), "-s", config.ANDROID_DEVICE, *args])

    return result.stdout.strip()


def command_preflight(args: argparse.Namespace) -> int:
    ok = True
    print(f"adb       {config.ADB}")
    print(f"flutter   {config.FLUTTER}")
    for path in (config.ADB, config.FLUTTER, config.COMPARE_ROOT):
        if not path.exists():
            print(f"missing: {path}")
            ok = False
    devices = run([str(config.ADB), "devices"]).stdout
    attached = [
        line.split()[0] for line in devices.splitlines()[1:] if "\tdevice" in line
    ]
    print(f"\nandroid target {config.ANDROID_DEVICE} ({config.ANDROID_DEVICE_NAME})")
    if config.ANDROID_DEVICE not in attached:
        print(f"  not attached. attached: {attached or 'none'}")
        ok = False
    else:
        print(f"  model          {adb('shell', 'getprop', 'ro.product.model')}")
        print(f"  android        {adb('shell', 'getprop', 'ro.build.version.release')}")
        print(f"  battery level  {_battery('level')}")
        print(f"  charging       {_charging()}")
        print(f"  thermal status {_thermal()}")
    others = [item for item in attached if item != config.ANDROID_DEVICE]
    if others:
        print(f"  note: other adb targets present, pass -s explicitly: {others}")
    print(f"\nios target {config.IOS_DEVICE} ({config.IOS_DEVICE_NAME})")
    listing = run(["xcrun", "devicectl", "list", "devices"]).stdout
    line = next(
        (item for item in listing.splitlines() if config.IOS_DEVICE in item), None
    )
    if line is None:
        print("  not listed by devicectl")
        ok = False
    else:
        state = "connected" if "connected" in line else line.split()[-2:]
        print(f"  state          {state}")
        if "connected" not in line:
            print("  attach by cable and unlock before measuring")
            ok = False
    print("\nready" if ok else "\nnot ready")

    return 0 if ok else 1


def _battery(field: str) -> str:
    output = adb("shell", "dumpsys", "battery")
    for line in output.splitlines():
        if line.strip().startswith(f"{field}:"):
            return line.split(":", 1)[1].strip()

    return "unknown"


def _charging() -> str:
    """Name the live power sources, which must match across measurements."""
    output = adb("shell", "dumpsys", "battery")
    live = [
        line.strip().split(" powered")[0]
        for line in output.splitlines()
        if "powered:" in line and line.strip().endswith("true")
    ]

    return ", ".join(live) if live else "not charging"


def _thermal() -> str:
    output = adb("shell", "dumpsys", "thermalservice")
    for line in output.splitlines():
        if "Thermal Status" in line:
            return line.split(":", 1)[-1].strip()

    return "unknown"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)

    return digest.hexdigest()


def parse_config(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected label=path/to/app.apk")
    label, _, path = value.partition("=")
    resolved = Path(path).expanduser().resolve()
    if not resolved.exists():
        raise argparse.ArgumentTypeError(f"no such file: {resolved}")

    return label, resolved


def command_android(args: argparse.Namespace) -> int:
    if len(args.config) < 1:
        print("pass at least one --config label=app.apk", file=sys.stderr)

        return 2
    args.out.mkdir(parents=True, exist_ok=True)
    tool = config.COMPARE_ROOT / "tool" / "run_apk_profile.py"
    if not tool.exists():
        print(f"missing measurement tool: {tool}", file=sys.stderr)

        return 2
    manifest = {
        "device": config.ANDROID_DEVICE,
        "scene": args.scene,
        "engine": args.engine,
        "runs_per_configuration": args.runs,
        "configurations": [
            {"label": label, "apk": str(path), "sha256": sha256(path)}
            for label, path in args.config
        ],
        "order": "rotated by round so that each configuration leads once",
        "outputs": [],
    }
    failures = 0
    for index in range(args.runs):
        # Rotate the order every round. A fixed order lets thermal drift and
        # cache warmth land on the same configuration every time.
        rotated = args.config[index % len(args.config) :] + args.config[
            : index % len(args.config)
        ]
        for label, apk in rotated:
            output = args.out / f"{args.scene}-{label}-r{index + 1}.json"
            command = [
                sys.executable,
                str(tool),
                str(apk),
                "--device",
                config.ANDROID_DEVICE,
                "--flutter",
                str(config.FLUTTER),
                "--scene",
                args.scene,
                "--engine",
                args.engine,
                "--startup-settle",
                str(args.startup_settle),
                "--output",
                str(output),
            ]
            if args.cpu:
                command.append("--cpu")
            print(f"[run {index + 1}/{args.runs}] {label} -> {output.name}", flush=True)
            result = run(command, cwd=config.COMPARE_ROOT)
            manifest["outputs"].append(
                {
                    "label": label,
                    "run": index + 1,
                    "output": str(output),
                    "returncode": result.returncode,
                }
            )
            if result.returncode != 0:
                failures += 1
                print(result.stdout[-2000:])
                print(result.stderr[-2000:], file=sys.stderr)
                if not args.keep_going:
                    break
        else:
            continue
        break
    (args.out / "run-manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    )
    print(f"\n{len(manifest['outputs'])} runs recorded, {failures} failed")
    print(f"manifest written to {args.out / 'run-manifest.json'}")

    return 1 if failures else 0


def command_ios(args: argparse.Namespace) -> int:
    """Print the verified iOS measurement command rather than running it.

    The iOS tool requires the IPA hash and an artifact manifest produced by a
    freeze script, so the operator supplies those paths deliberately.
    """
    ipa = args.ipa.expanduser().resolve()
    tool = config.COMPARE_ROOT / "tool" / "run_ios_profile_preserving_install_v3.py"
    print(f"ipa sha256 {sha256(ipa)}")
    print("\nrun this from the measurement project, once per run:\n")
    for index in range(args.runs):
        output = args.out / f"{args.scene}-{args.label}-r{index + 1}.json"
        print(
            f"python3 {tool} {ipa} \\\n"
            f"  --expected-sha256 {sha256(ipa)} \\\n"
            f"  --artifact-manifest <provenance manifest json> \\\n"
            f"  --expected-manifest-sha256 <manifest sha256> \\\n"
            f"  --device {config.IOS_DEVICE} \\\n"
            f"  --flutter {config.FLUTTER} \\\n"
            f"  --engine {args.engine} --scene {args.scene} \\\n"
            f"  --output {output}\n"
        )

    return 0


def load_runs(paths: list[Path]) -> dict[str, list[dict]]:
    grouped: dict[str, list[dict]] = {}
    for path in paths:
        match = RUN_NAME.match(path.name)
        label = match.group("label") if match else path.stem
        grouped.setdefault(label, []).append(json.loads(path.read_text()))

    return grouped


def metric(entry: dict, path: str) -> float | None:
    current: object = entry
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]

    return float(current) if isinstance(current, (int, float)) else None


def command_summary(args: argparse.Namespace) -> int:
    grouped = load_runs(sorted(args.results))
    if not grouped:
        print("no measurement files given", file=sys.stderr)

        return 2
    problems: list[str] = []
    reference: dict | None = None
    for label, reports in grouped.items():
        if len(reports) < 3:
            problems.append(f"{label} has {len(reports)} runs, fewer than three")
        for report in reports:
            if reference is None:
                reference = report
                continue
            for field in COMPARABLE_FIELDS:
                if report.get(field) != reference.get(field):
                    problems.append(
                        f"{field} differs: {reference.get(field)} and {report.get(field)}"
                    )
            if report.get("map_logical_size") != reference.get("map_logical_size"):
                problems.append("map_logical_size differs between runs")
    metrics = {
        "build p50 ms": "flutter_build.p50_ms",
        "build p95 ms": "flutter_build.p95_ms",
        "raster p50 ms": "flutter_raster.p50_ms",
        "raster p95 ms": "flutter_raster.p95_ms",
        "cpu one core %": "process_cpu_one_core_percent",
        "over budget %": "flutter_over_budget_percent",
    }
    engines = sorted(
        {
            entry.get("engine")
            for reports in grouped.values()
            for entry in _results(reports)
        }
    )
    for engine in engines:
        print(f"\nengine {engine}")
        header = f"{'metric':16}" + "".join(f"{label:>18}" for label in grouped)
        print(header)
        for name, path in metrics.items():
            row = f"{name:16}"
            for label in grouped:
                values = [
                    value
                    for value in (
                        metric(entry, path)
                        for entry in _results(grouped[label])
                        if entry.get("engine") == engine
                    )
                    if value is not None
                ]
                row += f"{statistics.median(values):>18.3f}" if values else f"{'n/a':>18}"
            print(row)
        row = f"{'end pss MB':16}"
        for label in grouped:
            values = [
                value / 1024
                for value in (
                    metric(entry, "android_after.pss_kb")
                    for entry in _results(grouped[label])
                    if entry.get("engine") == engine
                )
                if value is not None
            ]
            row += f"{statistics.median(values):>18.1f}" if values else f"{'n/a':>18}"
        print(row)
        idle = f"{'idle observed':16}"
        for label in grouped:
            observed = [
                bool(entry.get("map_idle_observed_before_measurement"))
                for entry in _results(grouped[label])
                if entry.get("engine") == engine
            ]
            idle += f"{sum(observed)}/{len(observed):<16}" if observed else f"{'n/a':>18}"
        print(idle)
    print("\nmedian of per run values. Compare matched pairs, not these columns alone.")
    if problems:
        print("\ncomparability problems:")
        for problem in dict.fromkeys(problems):
            print(f"- {problem}")

        return 1
    print("\ncomparability checks passed")

    return 0


def _results(reports: list[dict]) -> list[dict]:
    return [entry for report in reports for entry in report.get("results", [])]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--out",
        type=Path,
        default=config.AGENTS_DIR / "out" / "measurements",
        help="directory for measurement reports",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    preflight = sub.add_parser("preflight", help="check the attached devices")
    preflight.set_defaults(func=command_preflight)

    android = sub.add_parser("android", help="run alternating APK measurements")
    android.add_argument(
        "--config",
        type=parse_config,
        action="append",
        default=[],
        help="label=path/to/app.apk, repeatable",
    )
    android.add_argument("--scene", default="liberty")
    android.add_argument("--engine", choices=["gl", "gpu", "both"], default="gpu")
    android.add_argument("--runs", type=int, default=3)
    android.add_argument("--startup-settle", type=float, default=30)
    android.add_argument("--cpu", action="store_true")
    android.add_argument("--keep-going", action="store_true")
    android.set_defaults(func=command_android)

    ios = sub.add_parser("ios", help="print the verified iOS measurement command")
    ios.add_argument("ipa", type=Path)
    ios.add_argument("--label", default="candidate")
    ios.add_argument("--scene", default="liberty")
    ios.add_argument("--engine", choices=["gpu", "gl"], default="gpu")
    ios.add_argument("--runs", type=int, default=3)
    ios.set_defaults(func=command_ios)

    summary = sub.add_parser("summary", help="compare matched configurations")
    summary.add_argument("results", type=Path, nargs="+")
    summary.set_defaults(func=command_summary)

    return parser


def main() -> int:
    args = build_parser().parse_args()

    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
