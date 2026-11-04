import ctypes
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "native/platforms/android/vertex_repack.cpp"


class VertexRepackTest(unittest.TestCase):
    def test_real_android_export_converts_and_validates(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        self.assertIsNotNone(compiler, "A C++ compiler is required")
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            binary = work / "vertex_repack_test"
            subprocess.run([
                compiler, "-std=c++20", "-O2", "-DNDEBUG", "-Wall", "-Wextra", "-Werror",
                "-I", str(ROOT / "native/src"),
                str(ROOT / "native/tests/vertex_repack_test.cpp"), str(WRAPPER), "-o", str(binary),
            ], check=True)
            subprocess.run([str(binary)], check=True, timeout=30)

    def test_optional_c_abi_survives_hidden_visibility(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        self.assertIsNotNone(compiler, "A C++ compiler is required")
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / "vertex_repack.so"
            subprocess.run([
                compiler, "-std=c++20", "-O2", "-DNDEBUG", "-fPIC", "-fvisibility=hidden",
                "-dynamiclib" if sys.platform == "darwin" else "-shared",
                "-I", str(ROOT / "native/src"), str(WRAPPER), "-o", str(library),
            ], check=True)
            native = ctypes.CDLL(str(library))
            repack = native.maplibre_repack_vertices_v1
            repack.argtypes = [ctypes.c_uint32, ctypes.c_void_p, ctypes.c_size_t,
                              ctypes.c_uint32, ctypes.c_void_p, ctypes.c_size_t]
            repack.restype = ctypes.c_int32
            source = ctypes.create_string_buffer(struct.pack("<hhHHhh", -32768, 32767, 65535, 32768, -1, 0))
            output = ctypes.create_string_buffer(24)
            self.assertEqual(repack(1, source, 12, 1, output, 24), 1)
            self.assertEqual(output.raw, struct.pack("<6f", -32768, 32767, 65535, 32768, -1, 0))
            before = output.raw
            self.assertEqual(repack(1, source, 11, 1, output, 24), -1)
            self.assertEqual(output.raw, before)
            self.assertEqual(repack(0, source, 12, 1, output, 24), 0)
            self.assertEqual(output.raw, before)


if __name__ == "__main__":
    unittest.main()
