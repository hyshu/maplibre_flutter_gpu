from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = ROOT / "vendor/maplibre-native/platform/android/MapLibreAndroid/src/cpp/http_file_source.cpp"
GENERATOR = ROOT / "native/cmake/android_http_source.cmake"


def generate(work, source):
    output = work / "http_file_source.cpp"
    script = work / "generate.cmake"
    script.write_text(
        f'include("{GENERATOR}")\n'
        f'maplibre_generate_android_http_source("{source}" "{output}")\n'
    )
    result = subprocess.run(["cmake", "-P", str(script)], capture_output=True, text=True)
    return result, output


class AndroidHttpCohostingTest(unittest.TestCase):
    def test_generation_changes_only_the_jni_class(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output = generate(Path(directory), UPSTREAM)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                output.read_text(),
                UPSTREAM.read_text().replace(
                    '"org/maplibre/android/http/NativeHttpRequest"',
                    '"dev/maplibre/fluttergpu/NativeHttpRequest"',
                ),
            )

    def test_generation_rejects_changed_or_ambiguous_jni_contract(self):
        for content in ('no class',
                        '"org/maplibre/android/http/NativeHttpRequest"\n' * 2):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                source = work / "upstream.cpp"
                source.write_text(content)
                result, _ = generate(work, source)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("exactly one JNI request class", result.stderr)

    def test_real_java_adapter_is_independent_in_both_load_orders(self):
        java = shutil.which("java")
        javac = shutil.which("javac")
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        self.assertTrue(java and javac and compiler, "A JDK and C++ compiler are required")
        properties = subprocess.run(
            [java, "-XshowSettings:properties", "-version"],
            capture_output=True, text=True, check=True,
        ).stderr
        java_home = Path(re.search(r"^\s*java.home = (.+)$", properties, re.MULTILINE)[1])
        platform = "darwin" if sys.platform == "darwin" else "linux"
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            result, generated = generate(work, UPSTREAM)
            self.assertEqual(result.returncode, 0, result.stderr)
            class_name = re.search(
                r'static constexpr auto Name\(\) \{ return "([^"]+)";',
                generated.read_text(),
            )[1]
            (work / "http_java_class.inc").write_text(
                f'constexpr const char* gpuJavaClass = "{class_name}";\n'
            )
            library = work / ("http_cohosting.dylib" if platform == "darwin" else "http_cohosting.so")
            subprocess.run([
                compiler, "-std=c++20", "-dynamiclib" if platform == "darwin" else "-shared",
                "-fPIC", "-I", str(java_home / "include"),
                "-I", str(java_home / "include" / platform), "-I", str(work),
                str(ROOT / "native/tests/http_cohosting_jni.cpp"), "-o", str(library),
            ], check=True)
            subprocess.run([
                javac, "-d", str(work),
                str(ROOT / "android/src/main/java/dev/maplibre/fluttergpu/NativeHttpRequest.java"),
                str(ROOT / "native/tests/HttpCohosting.java"),
                *map(str, (ROOT / "native/tests/http_sdk_stub").rglob("*.java")),
            ], check=True)
            for order in ("gpu-first", "sdk-first"):
                subprocess.run(
                    [java, "-cp", str(work), "HttpCohosting", str(library), order],
                    check=True, timeout=10,
                )


if __name__ == "__main__":
    unittest.main()
