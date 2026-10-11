"""Exercise release artifact compatibility through the public shell command."""

from pathlib import Path
import subprocess
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[2]
SCRIPT = PROJECT / "tool/ci/verify_release_artifact_source.sh"
EXAMPLES = (
    "example",
    "examples/gpu_map_scene",
    "examples/map_layers",
    "examples/map_style_controls",
    "examples/tv_map_explorer",
)
METADATA_PATHS = (
    "pubspec.yaml",
    "android/src/main/java/org/maplibre/android/http/NativeHttpRequest.java",
    "darwin/maplibre_flutter_gpu.podspec",
    *(f"{package}/pubspec.yaml" for package in EXAMPLES),
    *(f"{package}/pubspec.lock" for package in EXAMPLES),
    "e2e/visual/gpu_app/pubspec.lock",
)


class ReleaseArtifactSourceTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.repository = Path(self.temporary_directory.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Release test")
        self.git("config", "user.email", "release-test@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.hooksPath", str(self.repository / "empty-hooks"))
        for path in METADATA_PATHS:
            self.write(path, (PROJECT / path).read_bytes())
        self.write("README.md", b"Package documentation.\n")
        self.write("lib/src/widgets/maplibre_map.dart", b"Widget map;\n")
        self.write("lib/src/widgets/map/map_view.dart", b"Widget overlay;\n")
        self.source = self.commit()
        self.version = next(
            line.split(b":", 1)[1].strip()
            for line in (self.repository / "pubspec.yaml").read_bytes().splitlines()
            if line.startswith(b"version:")
        )

    def git(self, *arguments):
        return subprocess.check_output(
            ["git", "-C", str(self.repository), *arguments], stderr=subprocess.PIPE
        ).decode().strip()

    def write(self, path, content):
        destination = self.repository / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)

    def commit(self):
        self.git("add", "--all")
        self.git("commit", "-qm", "test: change release fixture")
        return self.git("rev-parse", "HEAD")

    def verify(self, target, source=None):
        return subprocess.run(
            [str(SCRIPT), source or self.source, target, str(self.repository)],
            capture_output=True,
            text=True,
        )

    def assert_allowed(self, target):
        result = self.verify(target)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("source is compatible", result.stdout)

    def assert_rejected(self, target, path):
        result = self.verify(target)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(path, result.stderr)

    def test_identical_source_is_compatible(self):
        self.assert_allowed(self.source)

    def test_widget_release_reuses_unchanged_native_artifacts(self):
        self.write("README.md", b"Updated package documentation.\n")
        self.write("lib/src/widgets/maplibre_map.dart", b"Widget locationMarker;\n")
        self.write("lib/src/widgets/map/map_view.dart", b"Widget markerAboveOverlay;\n")
        for path in METADATA_PATHS:
            content = (self.repository / path).read_bytes()
            if path.endswith(".lock"):
                package = content.index(b"  maplibre_flutter_gpu:\n")
                start = content.index(b"    version:", package)
                end = content.index(b"\n", start)
                content = (
                    content[:start]
                    + content[start:end].replace(self.version, b"9.9.9")
                    + content[end:]
                )
            elif path.endswith(".yaml"):
                content = content.replace(
                    b"version: " + self.version + b"\n", b"version: 9.9.9\n"
                )
            else:
                content = content.replace(self.version, b"9.9.9")
            self.write(path, content)
        self.assert_allowed(self.commit())

    def test_documentation_examples_and_tests_do_not_require_native_builds(self):
        for path in (
            "docs/setup.md",
            "example/lib/main.dart",
            "examples/map_layers/lib/main.dart",
            "e2e/visual/shared/lib/scene.dart",
            "test/map_configuration_test.dart",
        ):
            self.write(path, b"New non-native content.\n")
        self.assert_allowed(self.commit())

    def test_verifier_maintenance_does_not_require_native_builds(self):
        for path in (
            ".agents/skills/release-maplibre-flutter-gpu/SKILL.md",
            "tool/ci/verify_release_artifact_source.sh",
            "tool/ci/verify_release_artifact_source.py",
            "tool/ci/test_verify_release_artifact_source.py",
        ):
            self.write(path, b"Updated release verification.\n")
        self.assert_allowed(self.commit())

    def test_native_contracts_and_unknown_inputs_are_rejected(self):
        for path in (
            "native/bridge.cpp",
            "vendor/maplibre-native/source.cpp",
            "hook/build.dart",
            "lib/src/native/bindings/frame_bindings.dart",
            "lib/src/frame/ubo_abi.dart",
            "shaders/MapShaders.shaderbundle.json",
            "android/build.gradle",
            "darwin/maplibre_flutter_gpu/Package.swift",
            "darwin/maplibre_flutter_gpu/Sources/maplibre_flutter_gpu/Plugin.swift",
            "linux/CMakeLists.txt",
            "windows/CMakeLists.txt",
            "native/scripts/build.sh",
            "tool/ci/archive_native_artifact.sh",
            ".github/workflows/_native-artifacts.yml",
            "unexpected-config.yaml",
        ):
            with self.subTest(path=path):
                self.git("reset", "--hard", self.source)
                self.write(path, b"Changed native input.\n")
                self.assert_rejected(self.commit(), path)

    def test_vendor_gitlink_change_is_rejected(self):
        later = self.commit_readme_change()
        self.git(
            "update-index", "--add", "--cacheinfo", "160000", later,
            "vendor/maplibre-native"
        )
        self.git("commit", "-qm", "test: change vendor revision")
        self.assert_rejected(self.git("rev-parse", "HEAD"), "vendor/maplibre-native")

    def test_version_files_reject_behavior_and_dependency_changes(self):
        changes = {
            "pubspec.yaml": (b"ffi: ^2.1.0", b"ffi: ^3.0.0"),
            "android/src/main/java/org/maplibre/android/http/NativeHttpRequest.java":
                (b"15_000", b"1_000"),
            "darwin/maplibre_flutter_gpu.podspec": (b"'15.0'", b"'14.0'"),
            "example/pubspec.yaml": (b"path: ..", b"path: ../../other"),
            "example/pubspec.lock": (b"path: \"..\"", b"path: \"../other\""),
        }
        for path, (before, after) in changes.items():
            with self.subTest(path=path):
                self.git("reset", "--hard", self.source)
                content = (self.repository / path).read_bytes()
                self.assertIn(before, content)
                self.write(path, content.replace(before, after))
                self.assert_rejected(self.commit(), path)

    def test_other_locked_versions_are_rejected(self):
        path = "example/pubspec.lock"
        content = (self.repository / path).read_bytes()
        start = content.index(b"    version:")
        end = content.index(b"\n", start)
        self.write(
            path, content[:start] + b'    version: "99.99.99"' + content[end:]
        )
        self.assert_rejected(self.commit(), path)

    def test_version_must_match_the_root_package(self):
        path = "darwin/maplibre_flutter_gpu.podspec"
        content = (self.repository / path).read_bytes()
        self.write(path, content.replace(self.version, b"9.9.9"))
        self.assert_rejected(self.commit(), path)

    def test_version_field_cannot_be_removed_or_duplicated(self):
        path = "pubspec.yaml"
        original = (self.repository / path).read_bytes()
        version_line = b"version: " + self.version + b"\n"
        for content in (original.replace(version_line, b""), original + version_line):
            with self.subTest(content=content):
                self.git("reset", "--hard", self.source)
                self.write(path, content)
                result = self.verify(self.commit())
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("expected exactly one stable package version", result.stderr)

    def test_version_file_deletion_is_rejected(self):
        path = "darwin/maplibre_flutter_gpu.podspec"
        (self.repository / path).unlink()
        self.assert_rejected(self.commit(), path)

    def test_widget_symlink_is_rejected(self):
        path = "lib/src/widgets/maplibre_map.dart"
        (self.repository / path).unlink()
        (self.repository / path).symlink_to("../../native/bridge.cpp")
        self.assert_rejected(self.commit(), path)

    def test_metadata_mode_change_is_rejected(self):
        path = "pubspec.yaml"
        (self.repository / path).chmod(0o755)
        self.assert_rejected(self.commit(), path)

    def commit_readme_change(self):
        self.write("README.md", b"Updated documentation.\n")
        return self.commit()

    def test_source_must_be_an_ancestor(self):
        later = self.commit_readme_change()
        result = self.verify(self.source, source=later)
        self.assertNotEqual(result.returncode, 0)

    def test_invalid_commit_is_rejected(self):
        result = self.verify("missing-commit")
        self.assertNotEqual(result.returncode, 0)

    def test_shell_argument_contract_is_preserved(self):
        result = subprocess.run([str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 64)
        self.assertIn("Usage:", result.stderr)


if __name__ == "__main__":
    unittest.main()
