import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


def function(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


class CameraFrameOrderTest(unittest.TestCase):
    def test_camera_mutations_between_preparation_and_render(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        self.assertIsNotNone(compiler, "A C++ compiler is required")
        source = (ROOT / "native/src/bridge_frame.cpp").read_text()
        prepare = function(source, "static void prepareAsyncRenderOnOwner() {")
        render = function(
            source,
            "static void runAsyncRenderOnOwner(uint64_t preparedCameraRevision) {",
        )
        admission = render[:render.index("    bool published = false;")]
        # Keep production admission and queue behavior, replacing GPU execution.
        admission += "    recordFrame(preparedCameraRevision);\n}\n"
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / "camera_frame_order.inc").write_text(prepare + "\n" + admission)
            binary = work / "camera_frame_order_test"
            subprocess.run(
                [compiler, "-std=c++20", "-I", str(work),
                 str(ROOT / "native/tests/camera_frame_order_test.cpp"),
                 "-o", str(binary)],
                check=True,
            )
            subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    unittest.main()
