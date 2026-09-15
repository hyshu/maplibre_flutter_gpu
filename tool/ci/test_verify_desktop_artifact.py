"""Regression tests for desktop bridge export verification."""

from pathlib import Path
import tempfile
import unittest

from verify_desktop_artifact import (
    REQUIRED_SESSION_EXPORTS,
    source_exports,
    verify_exports,
)


class DesktopExportsTest(unittest.TestCase):
    def test_exports_survive_translation_unit_moves(self):
        exports = REQUIRED_SESSION_EXPORTS | {
            f"maplibre_test_{index}" for index in range(70)
        }
        label_exports = {
            "maplibre_get_labels",
            "maplibre_get_label_static_records",
            "maplibre_get_label_dynamic_records",
        }
        declarations = "\n".join(
            f"MAPLIBRE_API const void* {name}(void) {{ return nullptr; }}"
            for name in sorted(label_exports)
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "bridge.cpp").write_text(
                "\n".join(
                    f"MAPLIBRE_API void {name}(void) {{}}"
                    for name in sorted(exports)
                ),
                encoding="utf-8",
            )
            labels = root / "bridge_labels.cpp"
            labels.write_text(declarations, encoding="utf-8")
            before = source_exports(root)
            self.assertEqual(before, exports | label_exports)

            destination = root / "labels" / "session"
            destination.mkdir(parents=True)
            labels.rename(destination / "label_session.cpp")
            self.assertEqual(source_exports(root), before)

    def test_missing_exports_are_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "missing bridge exports"):
            verify_exports({"maplibre_get_labels"}, set())

    def test_unexpected_exports_are_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "unexpected bridge exports"):
            verify_exports(set(), {"maplibre_private_helper"})

    def test_sources_without_session_exports_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            with self.assertRaisesRegex(RuntimeError, "omit session exports"):
                source_exports(Path(temporary_directory))


if __name__ == "__main__":
    unittest.main()
