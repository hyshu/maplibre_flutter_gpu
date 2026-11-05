#!/usr/bin/env python3
"""Keep the Darwin Objective-C class rename list complete.

The bridge archive carries the Darwin sources that MapLibre Native compiles into
mbgl-core. Objective-C registers a class process wide, so any class those
sources define collides with the MapLibre GL SDK in an application that links
both. native/cmake/darwin_objc_class_names.cmake renames them, and
native/scripts/packaging/darwin_common.sh fails a packaged archive that still
defines an original name.

That check needs a build. This test needs only the sources, so a vendor update
that introduces another class fails here first.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
RENAMES = ROOT / "native/cmake/darwin_objc_class_names.cmake"
VENDOR = ROOT / "vendor/maplibre-native"
DARWIN_CMAKE = VENDOR / "platform/darwin/darwin.cmake"
SHARED_HEADERS = VENDOR / "platform/darwin/include/mln/interface"

RENAME_PATTERN = re.compile(r"^\s*((?:MLN|MBGL)[A-Za-z0-9_]+)=([A-Za-z0-9_]+)\s*$")
OBJC_CLASS_PATTERN = re.compile(r"^@(?:interface|implementation)\s+([A-Za-z0-9_]+)")
SDK_PREFIXES = ("MLN", "MBGL")


def load_renames():
    pairs = {}
    for line in RENAMES.read_text().splitlines():
        match = RENAME_PATTERN.match(line)
        if match:
            pairs[match.group(1)] = match.group(2)

    return pairs


def core_darwin_sources():
    """Return the Darwin sources that darwin.cmake compiles into mbgl-core."""
    text = DARWIN_CMAKE.read_text()
    paths = []
    for match in re.finditer(
        r"\$\{PROJECT_SOURCE_DIR\}/(platform/darwin/core/[A-Za-z0-9_./]+\.mm?)", text
    ):
        path = VENDOR / match.group(1)
        if path.exists():
            paths.append(path)

    return paths


def declared_classes(paths):
    found = {}
    for path in paths:
        for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            match = OBJC_CLASS_PATTERN.match(line)
            if match:
                found.setdefault(match.group(1), f"{path.relative_to(VENDOR)}:{number}")

    return found


@unittest.skipUnless(DARWIN_CMAKE.exists(), "MapLibre Native submodule is not checked out")
class DarwinObjcClassNameTest(unittest.TestCase):
    def test_rename_list_is_not_empty(self):
        self.assertTrue(load_renames(), f"no Old=New pairs parsed from {RENAMES}")

    def test_renamed_names_are_bridge_specific(self):
        for original, renamed in load_renames().items():
            self.assertFalse(
                renamed.startswith(SDK_PREFIXES),
                f"{original} is renamed to {renamed}, which keeps an SDK prefix",
            )
            self.assertNotEqual(original, renamed)

    def test_renamed_names_are_unique(self):
        renames = load_renames()
        self.assertEqual(
            len(set(renames.values())), len(renames), "two classes share one new name"
        )

    def test_every_sdk_class_in_core_sources_is_renamed(self):
        sources = core_darwin_sources()
        self.assertTrue(sources, "no Darwin core sources found in darwin.cmake")
        renames = load_renames()
        missing = {
            name: where
            for name, where in declared_classes(sources).items()
            if name.startswith(SDK_PREFIXES) and name not in renames
        }
        self.assertEqual(
            missing,
            {},
            "add these classes to native/cmake/darwin_objc_class_names.cmake",
        )

    def test_every_sdk_class_in_shared_headers_is_renamed(self):
        headers = sorted(SHARED_HEADERS.glob("*.h"))
        self.assertTrue(headers, f"no shared headers found under {SHARED_HEADERS}")
        renames = load_renames()
        missing = {
            name: where
            for name, where in declared_classes(headers).items()
            if name.startswith(SDK_PREFIXES) and name not in renames
        }
        self.assertEqual(
            missing,
            {},
            "add these classes to native/cmake/darwin_objc_class_names.cmake",
        )

    def test_renamed_classes_still_exist_in_the_vendored_sources(self):
        """A rename for a class the vendor removed hides a stale entry."""
        known = declared_classes(core_darwin_sources() + sorted(SHARED_HEADERS.glob("*.h")))
        for original in load_renames():
            self.assertIn(
                original,
                known,
                f"{original} is renamed but no vendored Darwin source declares it",
            )


if __name__ == "__main__":
    unittest.main()
