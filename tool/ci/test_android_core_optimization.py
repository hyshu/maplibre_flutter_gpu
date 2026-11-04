import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
ANDROID_PROJECT = ROOT / "native/platforms/android"
OPTION = "MAPLIBRE_ANDROID_CORE_OPTIMIZE_SPEED"


class AndroidCoreOptimizationTest(unittest.TestCase):
    """Generate the production wrapper with a small dependency graph and no NDK."""

    def test_actual_android_wrapper_changes_only_optimized_core_compilation(self):
        self.assertIsNotNone(shutil.which("cmake"), "CMake is required")
        self.assertIsNotNone(shutil.which("ninja"), "Ninja is required")
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            vendor = work / "vendor"
            vendor.mkdir()
            self._write_vendor(vendor)
            for config in ("Release", "RelWithDebInfo", "Debug", "MinSizeRel"):
                with self.subTest(config=config):
                    baseline, baseline_links = self._configure(work, vendor, config, False)
                    candidate, candidate_links = self._configure(work, vendor, config, None)
                    explicit, explicit_links = self._configure(work, vendor, config, True)
                    self.assertEqual(candidate, explicit)
                    self.assertEqual(candidate_links, explicit_links)
                    self.assertEqual(baseline.keys(), candidate.keys())
                    self.assertEqual(baseline_links, candidate_links)
                    changed = []
                    for source, before in baseline.items():
                        after = candidate[source]
                        if before != after:
                            changed.append(source)
                        if source.startswith("core/") and config in ("Release", "RelWithDebInfo"):
                            before_opt = [flag for flag in before if re.fullmatch(r"-O\w+", flag)]
                            after_opt = [flag for flag in after if re.fullmatch(r"-O\w+", flag)]
                            self.assertEqual(before_opt[-1], "-Oz")
                            self.assertEqual(after_opt, [*before_opt, "-O2"])
                            self.assertEqual(
                                [flag for flag in before if not re.fullmatch(r"-O\w+", flag)],
                                [flag for flag in after if not re.fullmatch(r"-O\w+", flag)],
                            )
                        else:
                            self.assertEqual(before, after, source)
                    self.assertEqual(
                        bool(changed), config in ("Release", "RelWithDebInfo")
                    )

    def _write_vendor(self, vendor):
        (vendor / "CMakeLists.txt").write_text('''
add_library(mbgl-compiler-options INTERFACE)
set(optimized "$<OR:$<CONFIG:Release>,$<CONFIG:RelWithDebInfo>>")
target_compile_options(mbgl-compiler-options INTERFACE
    "$<${optimized}:-Oz>" "$<${optimized}:-flto>")
target_link_libraries(mbgl-compiler-options INTERFACE
    "$<${optimized}:-O2>" "$<${optimized}:-flto>")
add_library(mbgl-core STATIC core.cpp)
target_link_libraries(mbgl-core PRIVATE mbgl-compiler-options)
add_library(vendor-probe STATIC vendor.cpp)
target_link_libraries(vendor-probe PRIVATE mbgl-compiler-options)
add_library(MapLibreNative::Base::jni.hpp INTERFACE IMPORTED GLOBAL)
export(TARGETS mbgl-core mbgl-compiler-options FILE CoreTargets.cmake)
''')
        for name in ("core.cpp", "vendor.cpp"):
            (vendor / name).write_text("int configuration_probe;\n")
        files = {
            "vendor/nunicode.cmake": "add_library(mbgl-vendor-nunicode INTERFACE IMPORTED)\n",
            "platform/android/MapLibreAndroid/src/cpp/http_file_source.cpp":
                'const char* name = "org/maplibre/android/http/NativeHttpRequest";\n',
            "platform/default/src/mln/command_export/headless_backend.cpp": "",
            "platform/default/src/mln/i18n/collator.cpp": "",
            "platform/default/src/mln/i18n/number_format.cpp": "",
            "platform/default/src/mln/text/local_glyph_rasterizer.cpp": "",
            "platform/default/src/mln/util/logging_stderr.cpp": "",
        }
        for name, content in files.items():
            path = vendor / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)

    def _configure(self, work, vendor, config, enabled):
        mode = {None: "default", False: "off", True: "on"}[enabled]
        build = work / f"{config}-{mode}"
        arguments = [
            "cmake", "-S", str(ANDROID_PROJECT), "-B", str(build), "-G", "Ninja",
            "-DANDROID=ON", f"-DMAPLIBRE_NATIVE_SOURCE_DIR={vendor}",
            f"-DCMAKE_BUILD_TYPE={config}", "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
        ]
        if enabled is not None:
            arguments.append(f"-D{OPTION}={'ON' if enabled else 'OFF'}")
        configured = subprocess.run(arguments, capture_output=True, text=True)
        self.assertEqual(configured.returncode, 0, configured.stdout + configured.stderr)
        self.assertIn(
            f"{OPTION}:BOOL={'OFF' if enabled is False else 'ON'}",
            (build / "CMakeCache.txt").read_text(),
        )
        commands = json.loads((build / "compile_commands.json").read_text())
        flags = {}
        for entry in commands:
            words = shlex.split(entry["command"])
            output = words[words.index("-o") + 1]
            source = Path(entry["file"])
            kind = "core" if "mbgl-core.dir/" in output else "other"
            source_key = str(source).replace(str(build), "<build>")
            key = f"{kind}/{source_key}"
            self.assertNotIn(key, flags)
            flags[key] = words[1:words.index("-o")]
        links = []
        for line in (build / "build.ninja").read_text().splitlines():
            if line.startswith(("  LINK_FLAGS =", "  LINK_LIBRARIES =")):
                links.append(line.replace(str(build), "<build>"))
        return flags, links


if __name__ == "__main__":
    unittest.main()
