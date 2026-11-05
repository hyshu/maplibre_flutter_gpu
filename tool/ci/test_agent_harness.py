#!/usr/bin/env python3
"""Cover the deterministic parts of the branch verification harness.

Only device_verify is exercised here. branch_agent needs the Claude Agent SDK,
which CI does not install, and its judgement is not testable this way.
"""

import argparse
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool" / "agents"))

import device_verify  # noqa: E402


def report(label, **overrides):
    """Build a benchmark report shaped like the measurement application's output."""
    base = {
        "schema_version": 3,
        "scene": "liberty",
        "route": "pan-zoom-rotate-return",
        "route_duration_ms": 12000,
        "warmup_rounds": 1,
        "build_mode": "profile",
        "device_pixel_ratio": 2.625,
        "refresh_rate_hz": 90.0,
        "measurement_scope": "map",
        "map_logical_size": {"width": 411.0, "height": 800.0},
        "gpu_revision": label,
        "results": [
            {
                "engine": "gpu",
                "map_idle_observed_before_measurement": True,
                "flutter_build": {"count": 600, "mean_ms": 6.0, "p50_ms": 5.0,
                                  "p95_ms": 9.0},
                "flutter_raster": {"count": 600, "mean_ms": 3.0, "p50_ms": 2.5,
                                   "p95_ms": 4.0},
                "process_cpu_one_core_percent": 180.0,
                "flutter_over_budget_percent": 12.0,
                "android_before": {"pss_kb": 300000},
                "android_after": {"pss_kb": 410000},
            }
        ],
    }
    base.update(overrides)

    return base


class ParseConfigTest(unittest.TestCase):
    def test_requires_label(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            device_verify.parse_config("/tmp/app.apk")

    def test_requires_existing_file(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            device_verify.parse_config("on=/tmp/does-not-exist-9e3f.apk")

    def test_accepts_existing_file(self):
        with tempfile.NamedTemporaryFile(suffix=".apk") as handle:
            label, path = device_verify.parse_config(f"on={handle.name}")
        self.assertEqual(label, "on")
        self.assertEqual(path.name, Path(handle.name).name)


class MetricTest(unittest.TestCase):
    def test_reads_nested_value(self):
        entry = {"flutter_build": {"p95_ms": 9.5}}
        self.assertEqual(device_verify.metric(entry, "flutter_build.p95_ms"), 9.5)

    def test_missing_path_is_none(self):
        self.assertIsNone(device_verify.metric({}, "flutter_build.p95_ms"))
        self.assertIsNone(device_verify.metric({"a": 1}, "a.b"))

    def test_non_numeric_is_none(self):
        self.assertIsNone(device_verify.metric({"a": "x"}, "a"))


class SummaryTest(unittest.TestCase):
    def write(self, directory, name, payload):
        path = Path(directory) / name
        path.write_text(json.dumps(payload))

        return path

    def run_summary(self, paths):
        args = argparse.Namespace(results=paths)
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = device_verify.command_summary(args)

        return code, buffer.getvalue()

    def test_groups_runs_by_label(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [
                self.write(directory, f"liberty-{label}-r{run}.json", report(label))
                for label in ("off", "on")
                for run in (1, 2, 3)
            ]
            code, output = self.run_summary(paths)
        self.assertEqual(code, 0)
        self.assertIn("comparability checks passed", output)
        self.assertIn("off", output)
        self.assertIn("on", output)

    def test_flags_too_few_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [
                self.write(directory, "liberty-on-r1.json", report("on")),
                self.write(directory, "liberty-on-r2.json", report("on")),
            ]
            code, output = self.run_summary(paths)
        self.assertEqual(code, 1)
        self.assertIn("fewer than three", output)

    def test_flags_mismatched_viewport(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [
                self.write(directory, f"liberty-off-r{run}.json", report("off"))
                for run in (1, 2, 3)
            ]
            paths += [
                self.write(
                    directory,
                    f"liberty-on-r{run}.json",
                    report("on", map_logical_size={"width": 411.0, "height": 914.0}),
                )
                for run in (1, 2, 3)
            ]
            code, output = self.run_summary(paths)
        self.assertEqual(code, 1)
        self.assertIn("map_logical_size differs", output)

    def test_flags_mismatched_device_pixel_ratio(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [
                self.write(directory, f"liberty-off-r{run}.json", report("off"))
                for run in (1, 2, 3)
            ]
            paths += [
                self.write(
                    directory,
                    f"liberty-on-r{run}.json",
                    report("on", device_pixel_ratio=3.0),
                )
                for run in (1, 2, 3)
            ]
            code, output = self.run_summary(paths)
        self.assertEqual(code, 1)
        self.assertIn("device_pixel_ratio differs", output)

    def test_reports_idle_observation_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            payload = report("on")
            payload["results"][0]["map_idle_observed_before_measurement"] = False
            paths = [
                self.write(directory, "liberty-on-r1.json", payload),
                self.write(directory, "liberty-on-r2.json", report("on")),
                self.write(directory, "liberty-on-r3.json", report("on")),
            ]
            code, output = self.run_summary(paths)
        self.assertEqual(code, 0)
        self.assertIn("idle observed", output)
        self.assertIn("2/3", output)


class DimensionSetTest(unittest.TestCase):
    """A review set names another branch's files, so only its shape is checked here."""

    def setUp(self):
        import config

        self.config = config

    def write_set(self, directory, payload):
        path = Path(directory) / "temp-set.json"
        path.write_text(json.dumps(payload))

        return path

    def valid_payload(self):
        return {
            "name": "temp",
            "base": "main",
            "dimensions": {
                "one": {
                    "title": "One",
                    "platforms": "shared",
                    "paths": ["lib/a.dart"],
                    "focus": "Look at a.",
                },
                "two": {
                    "title": "Two",
                    "platforms": "android",
                    "paths": ["lib/b.dart"],
                    "focus": "Look at b.",
                },
            },
        }

    def test_repository_sets_are_listed(self):
        self.assertTrue(self.config.dimension_sets(), "no review set under dimensions/")

    def test_repository_sets_validate(self):
        for name in self.config.dimension_sets():
            payload = self.config.load_dimension_set(name)
            self.assertTrue(payload["dimensions"], f"{name} holds no dimensions")

    def test_repository_sets_declare_a_base_ref(self):
        for name in self.config.dimension_sets():
            payload = self.config.load_dimension_set(name)
            self.assertTrue(payload.get("base"), f"{name} declares no base ref")

    def test_repository_sets_have_non_empty_focus(self):
        for name in self.config.dimension_sets():
            for key, dimension in self.config.load_dimension_set(name)["dimensions"].items():
                self.assertTrue(dimension["focus"].strip(), f"{name}: {key} has no focus")

    def test_loads_a_set_by_path(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_set(directory, self.valid_payload())
            payload = self.config.load_dimension_set(str(path))
        self.assertEqual(sorted(payload["dimensions"]), ["one", "two"])

    def test_unknown_name_lists_the_available_sets(self):
        with self.assertRaises(FileNotFoundError) as caught:
            self.config.load_dimension_set("no-such-set")
        self.assertIn("Available sets", str(caught.exception))

    def test_rejects_a_set_without_dimensions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_set(directory, {"name": "temp"})
            with self.assertRaises(ValueError):
                self.config.load_dimension_set(str(path))

    def test_rejects_an_empty_dimensions_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_set(directory, {"dimensions": {}})
            with self.assertRaises(ValueError):
                self.config.load_dimension_set(str(path))

    def test_rejects_a_missing_field(self):
        payload = self.valid_payload()
        del payload["dimensions"]["one"]["focus"]
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_set(directory, payload)
            with self.assertRaises(ValueError) as caught:
                self.config.load_dimension_set(str(path))
        self.assertIn("focus", str(caught.exception))

    def test_rejects_an_unknown_platforms_value(self):
        payload = self.valid_payload()
        payload["dimensions"]["one"]["platforms"] = "windows"
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_set(directory, payload)
            with self.assertRaises(ValueError) as caught:
                self.config.load_dimension_set(str(path))
        self.assertIn("platforms", str(caught.exception))

    def test_rejects_a_path_claimed_twice(self):
        payload = self.valid_payload()
        payload["dimensions"]["two"]["paths"] = ["lib/a.dart"]
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_set(directory, payload)
            with self.assertRaises(ValueError) as caught:
                self.config.load_dimension_set(str(path))
        self.assertIn("lib/a.dart", str(caught.exception))

    def test_missing_paths_names_the_absent_entries(self):
        payload = self.valid_payload()
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "lib").mkdir()
            (Path(directory) / "lib/a.dart").write_text("")
            absent = self.config.missing_paths(payload["dimensions"], root=directory)
        self.assertEqual(absent, [("two", "lib/b.dart")])


if __name__ == "__main__":
    unittest.main()
