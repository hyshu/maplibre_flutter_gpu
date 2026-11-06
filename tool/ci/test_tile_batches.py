import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
MLN = ROOT / "vendor/maplibre-native"
INCLUDES = [
    ROOT / "native/src",
    MLN / "include",
    MLN / "src",
    MLN / "platform/default/include",
    MLN / "vendor/maplibre-native-base/include",
    MLN / "vendor/maplibre-native-base/deps/variant/include",
    MLN / "vendor/maplibre-native-base/deps/geometry.hpp/include",
    MLN / "vendor/maplibre-native-base/deps/geojson.hpp/include",
    MLN / "vendor/expected-lite/include",
    MLN / "vendor/unordered_dense/include",
]


class TileBatchesTest(unittest.TestCase):
    def test_batching_concatenates_compatible_tiles(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        self.assertIsNotNone(compiler, "A C++ compiler is required")
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "tile_batches_test"
            command = [compiler, "-std=c++20", "-O1", "-DMLN_RENDER_BACKEND_COMMAND_EXPORT=1",
                       "-DMLN_USE_UNORDERED_DENSE=1"]
            for include in INCLUDES:
                command += ["-isystem", str(include)]
            command += [
                str(ROOT / "native/tests/tile_batches_test.cpp"),
                str(ROOT / "native/src/commands/tile_batches.cpp"),
                str(MLN / "src/mln/command_export/draw_command.cpp"),
                "-o", str(binary),
            ]
            subprocess.run(command, check=True)
            subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
