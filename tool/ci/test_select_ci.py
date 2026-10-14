import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from select_ci import ALL_JOBS, JOB_DEPENDENCIES, pull_request_changes, select_jobs


SCRIPT = Path(__file__).with_name("select_ci.py")


class SelectionTests(unittest.TestCase):
    def selected(self, paths, labels=(), event="pull_request"):
        plan = select_jobs(paths, labels, event)
        self.assertEqual(set(plan), set(ALL_JOBS))
        self.assertTrue(all(type(value) is bool for value in plan.values()))
        for job, dependencies in JOB_DEPENDENCIES.items():
            if plan[job]:
                self.assertTrue(all(plan[dependency] for dependency in dependencies))
        return {job for job, enabled in plan.items() if enabled}

    def test_push_and_manual_runs_are_full(self):
        for event in ("push", "workflow_dispatch"):
            with self.subTest(event=event):
                self.assertEqual(self.selected(["README.md"], event=event), set(ALL_JOBS))

    def test_documentation_only_skips_heavy_jobs(self):
        self.assertEqual(self.selected([
            "README.md", "AGENTS.md", "doc/images/map.png", "LICENSE",
            ".gitignore", ".github/ISSUE_TEMPLATE/bug_report.yml",
            ".agents/skills/release-maplibre-flutter-gpu/agents/openai.yaml",
        ]), set())

    def test_empty_unknown_and_invalid_paths_run_full(self):
        for paths in ([], ["future/runtime.rs"], ["../lib/a.dart"], ["/tmp/a"], ["."], [""]):
            with self.subTest(paths=paths):
                self.assertEqual(self.selected(paths), set(ALL_JOBS))

    def test_common_rendering_and_infrastructure_run_full(self):
        for path in (
            "native/src/bridge_frame.cpp", "native/tests/frame_camera_test.cpp",
            "native/cmake/bridge.cmake", "native/scripts/package_darwin.sh",
            "native/scripts/packaging/darwin_common.sh", "vendor/maplibre-native",
            "lib/src/native/maplibre_ffi.dart", "lib/src/gpu/pass_executor.dart",
            "lib/src/frame/repack/line_vertices.dart", "lib/maplibre_flutter_gpu.dart",
            "lib/src/fill_extrusion/fill_extrusion_renderer.dart", "shaders/line.vert",
            "assets/shaderbundles/MapShaders.shaderbundle", ".github/workflows/ci.yml",
            "tool/ci/select_ci.py", "tool/ci/test_select_ci.py", "hook/build.dart",
            "pubspec.yaml", "pubspec.lock", "e2e/visual/shared/pubspec.lock",
            "examples/gpu_map_scene/pubspec.yaml", ".gitmodules", ".pubignore",
        ):
            with self.subTest(path=path):
                self.assertEqual(self.selected([path]), set(ALL_JOBS))

    def test_runtime_lifecycle_paths_run_full(self):
        for path in (
            "lib/src/widgets/map_gpu_painter.dart", "lib/src/widgets/maplibre_map.dart",
            "lib/src/widgets/map/map_rendering.dart", "lib/src/widgets/map/map_initialization.dart",
            "lib/src/widgets/map/map_frame_snapshot.dart", "lib/src/state/map_render_scheduler.dart",
            "lib/src/state/map_style_session.dart", "lib/src/state/external_camera.dart",
        ):
            with self.subTest(path=path):
                self.assertEqual(self.selected([path]), set(ALL_JOBS))

    def test_unit_test_changes_keep_current_native_quality_dependency(self):
        for path in (
            "test/map_viewport_test.dart", "test/fixtures/example.json",
            "example/test/landmarks_test.dart", "examples/gpu_map_scene/test/scene_test.dart",
            "e2e/visual/runner/test/report_test.dart", "e2e/visual/shared/test/symbol_scene_test.dart",
        ):
            with self.subTest(path=path):
                self.assertEqual(self.selected([path]), {"quality", "linux", "native-contracts"})

    def test_shared_dart_selects_representative_macos(self):
        for path in (
            "lib/src/controller/camera_controller.dart", "lib/src/geo/map_user_location.dart",
            "lib/src/state/map_viewport.dart", "lib/src/state/gesture/gesture_coordinator.dart",
            "lib/src/labels/label_reconciler.dart", "lib/src/sprites/sprite_atlas.dart",
            "lib/src/widgets/symbols/symbol_overlay.dart", "lib/src/widgets/controls/scale_bar.dart",
        ):
            with self.subTest(path=path):
                self.assertEqual(self.selected([path]), {
                    "quality", "native-contracts", "linux", "macos_visual",
                    "macos_functional", "native_macos", "native_ios",
                })

    def test_platform_files_and_build_scripts_select_their_suites(self):
        for platform in ("android", "ios", "macos", "linux", "windows"):
            extension = "ps1" if platform == "windows" else "sh"
            for path in (
                f"{platform}/platform_config", f"native/platforms/{platform}/CMakeLists.txt",
                f"native/scripts/build_{platform}.{extension}",
                f"e2e/visual/run_{platform}.{extension}",
                f"e2e/visual/baseline/{platform}-geometry.png",
            ):
                with self.subTest(path=path):
                    self.assertEqual(self.selected([path]), self.selected(["README.md"], [f"ci:{platform}"]))

    def test_android_does_not_pull_in_ios_tests(self):
        jobs = self.selected(["android/build.gradle"])
        self.assertIn("android_visual", jobs)
        self.assertIn("consumer_android", jobs)
        self.assertIn("firebase_preflight", jobs)
        self.assertNotIn("native_ios", jobs)
        self.assertNotIn("consumer_ios", jobs)
        self.assertNotIn("ios_visual", jobs)

    def test_platform_visual_app_configuration_avoids_unrelated_suites(self):
        for app in ("gpu_app", "maplibre_gl_app"):
            for platform in ("android", "ios", "macos", "linux", "windows"):
                with self.subTest(app=app, platform=platform):
                    path = f"e2e/visual/{app}/{platform}/project.config"
                    self.assertEqual(self.selected([path]), self.selected(["README.md"], [f"ci:{platform}"]))

    def test_platform_visual_app_dependencies_still_run_full(self):
        for app in ("gpu_app", "maplibre_gl_app"):
            with self.subTest(app=app):
                self.assertEqual(self.selected([f"e2e/visual/{app}/ios/pubspec.lock"]), set(ALL_JOBS))

    def test_marker_runners_select_their_platform(self):
        for platform in ("android", "ios"):
            with self.subTest(platform=platform):
                self.assertEqual(self.selected([f"e2e/visual/run_flutter_markers_{platform}.sh"]), self.selected(["README.md"], [f"ci:{platform}"]))

    def test_macos_includes_ios_artifact_without_ios_tests(self):
        jobs = self.selected(["native/scripts/build_macos.sh"])
        self.assertIn("native_ios", jobs)
        self.assertIn("native_macos", jobs)
        self.assertNotIn("ios_visual", jobs)

    def test_darwin_checks_both_consuming_platforms(self):
        jobs = self.selected(["darwin/maplibre_flutter_gpu/Package.swift"])
        self.assertTrue({"consumer_ios", "consumer_macos", "ios_visual", "macos_visual"} <= jobs)
        self.assertNotIn("android_visual", jobs)

    def test_example_code_builds_all_consumers(self):
        jobs = self.selected(["examples/gpu_map_scene/lib/main.dart"])
        self.assertTrue({"consumer_ios", "consumer_macos", "consumer_android"} <= jobs)
        self.assertFalse({"ios_visual", "macos_visual", "android_visual"} & jobs)

    def test_platform_example_change_selects_only_related_consumer(self):
        for platform in ("android", "ios", "macos"):
            with self.subTest(platform=platform):
                jobs = self.selected([f"example/{platform}/project.config"])
                self.assertIn(f"consumer_{platform}", jobs)
                self.assertEqual({job for job in jobs if job.startswith("consumer_")}, {f"consumer_{platform}"})
                self.assertFalse({"ios_visual", "macos_visual", "android_visual"} & jobs)

    def test_shared_visual_changes_cover_all_renderers(self):
        for path in (
            "e2e/visual/shared/lib/src/scenes/geometry.dart",
            "e2e/visual/assets/fixture.png", "e2e/visual/gpu_app/lib/main.dart",
            "e2e/visual/maplibre_gl_app/lib/main.dart", "e2e/visual/runner/lib/src/pixel_match.dart",
        ):
            with self.subTest(path=path):
                jobs = self.selected([path])
                self.assertTrue({"android_visual", "ios_visual", "macos_visual", "macos_functional", "linux_visual", "windows_visual"} <= jobs)

    def test_labels_only_add_to_automatic_selection(self):
        paths = ["android/build.gradle"]
        original = self.selected(paths)
        for label in ("ci:android", "ci:ios", "ci:macos", "ci:linux", "ci:windows", "ci:visual", "ci:full"):
            with self.subTest(label=label):
                self.assertTrue(original <= self.selected(paths, [label]))
        self.assertEqual(self.selected(paths, ["bug"]), original)

    def test_full_and_unknown_ci_labels_fail_closed(self):
        for label in ("ci:full", "CI:FULL", "ci:typo"):
            with self.subTest(label=label):
                self.assertEqual(self.selected(["README.md"], [label]), set(ALL_JOBS))

    def test_mixed_paths_preserve_every_required_suite(self):
        android = self.selected(["android/build.gradle"])
        windows = self.selected(["windows/project.cmake"])
        self.assertEqual(self.selected(["README.md", "android/build.gradle", "windows/project.cmake"]), android | windows)
        self.assertEqual(self.selected(["test/map_test.dart", "future/runtime.rs"]), set(ALL_JOBS))


class PullRequestChangesTests(unittest.TestCase):
    def event(self, base="a" * 40, head="b" * 40, labels=None):
        return {"pull_request": {"base": {"sha": base}, "head": {"sha": head}, "labels": labels or []}}

    def test_reads_nul_delimited_paths_without_rename_detection(self):
        with mock.patch("select_ci.subprocess.run", return_value=subprocess.CompletedProcess([], 0, b"old/source.dart\0new/source.dart\0path with space.dart\0")) as run:
            paths, labels = pull_request_changes(self.event(labels=[{"name": "ci:ios"}]))
        self.assertEqual(paths, ["old/source.dart", "new/source.dart", "path with space.dart"])
        self.assertEqual(labels, ["ci:ios"])
        self.assertEqual(run.call_args.args[0], ["git", "diff", "--no-renames", "--name-only", "-z", f"{'a' * 40}...{'b' * 40}", "--"])
        self.assertTrue(run.call_args.kwargs["check"])

    def test_rejects_missing_or_malformed_commit_ids(self):
        for event in ({}, self.event(base="main"), self.event(head="--help"), self.event(base=None)):
            with self.subTest(event=event), mock.patch("select_ci.subprocess.run") as run:
                with self.assertRaises((KeyError, ValueError)):
                    pull_request_changes(event)
                run.assert_not_called()

    def test_git_failure_propagates(self):
        with mock.patch("select_ci.subprocess.run", side_effect=subprocess.CalledProcessError(128, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                pull_request_changes(self.event())

    def test_rejects_malformed_label_data(self):
        with mock.patch("select_ci.subprocess.run", return_value=subprocess.CompletedProcess([], 0, b"README.md\0")):
            with self.assertRaises(ValueError):
                pull_request_changes(self.event(labels=[{}]))

    def test_rename_to_documentation_still_selects_deleted_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args], stderr=subprocess.DEVNULL).decode().strip()

            git("init")
            git("config", "user.name", "CI test")
            git("config", "user.email", "ci@example.invalid")
            (root / "native").mkdir()
            (root / "native/runtime.cpp").write_text("int removed_runtime;\n")
            git("add", ".")
            git("commit", "-m", "initial")
            base = git("rev-parse", "HEAD")
            git("mv", "native/runtime.cpp", "README.md")
            git("commit", "-m", "rename source")
            head = git("rev-parse", "HEAD")
            original_run = subprocess.run
            with mock.patch("select_ci.subprocess.run", side_effect=lambda *args, **kwargs: original_run(*args, cwd=directory, **kwargs)):
                paths, labels = pull_request_changes(self.event(base, head))
            self.assertEqual(set(paths), {"native/runtime.cpp", "README.md"})
            self.assertTrue(all(select_jobs(paths, labels, "pull_request").values()))


class CommandTests(unittest.TestCase):
    def test_manual_run_exports_complete_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            summary = Path(directory) / "summary"
            env = dict(os.environ, GITHUB_OUTPUT=str(output), GITHUB_STEP_SUMMARY=str(summary))
            result = subprocess.run([sys.executable, str(SCRIPT), "--event-name", "workflow_dispatch"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(output.read_text().removeprefix("jobs=")), dict.fromkeys(ALL_JOBS, True))
            self.assertIn("Selected:", summary.read_text())
            self.assertIn("Skipped:", summary.read_text())

    def test_invalid_pr_event_does_not_export_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            event = Path(directory) / "event.json"
            event.write_text("{}")
            env = dict(os.environ, GITHUB_OUTPUT=str(output))
            result = subprocess.run([sys.executable, str(SCRIPT), "--event-name", "pull_request", "--event-path", str(event)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
