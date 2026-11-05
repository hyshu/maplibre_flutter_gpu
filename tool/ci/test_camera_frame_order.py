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
    def test_completed_frames_survive_continuous_camera_input(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        self.assertIsNotNone(compiler, "A C++ compiler is required")
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            for name, relative in (
                ("async_renderer", "native/src/frame/async_renderer.cpp"),
                ("camera_dispatch", "native/src/camera/camera_dispatch.hpp"),
                ("camera_query", "native/src/camera/camera_query.cpp"),
            ):
                source = (ROOT / relative).read_text()
                (work / f"{name}.inc").write_text("\n".join(
                    line for line in source.splitlines()
                    if not line.startswith('#include "') and line != "#pragma once"
                ))
            camera = (ROOT / "native/src/bridge_camera.cpp").read_text()
            (work / "camera_partial.inc").write_text("\n".join((
                function(camera, "static mln::AnimationOptions cameraAnimationOptions("),
                function(camera, "MAPLIBRE_API int maplibre_camera_apply_partial("),
            )))
            frames = (ROOT / "native/src/bridge_frame.cpp").read_text()
            snapshot = (ROOT / "native/src/frame/command_snapshot.cpp").read_text()
            (work / "frame_publication_helpers.inc").write_text("\n".join((
                function(frames, "void discardUnacquiredFrameLocked() {"),
                function(frames, "bool bridge_prepareSynchronousMutation() {"),
                function(snapshot, "MAPLIBRE_API int maplibre_frame_get_camera(double* output) {"),
            )))
            binary = work / "async_frame_publication_test"
            subprocess.run(
                [compiler, "-std=c++20", "-pthread", "-I", str(work),
                 str(ROOT / "native/tests/async_frame_publication_test.cpp"),
                 "-o", str(binary)],
                check=True,
            )
            subprocess.run([str(binary)], check=True)

    def test_camera_mutations_between_preparation_and_render(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        self.assertIsNotNone(compiler, "A C++ compiler is required")
        source = (ROOT / "native/src/frame/async_renderer.cpp").read_text()
        prepare = function(source, "static void prepareAsyncRenderOnOwner() {")
        render = function(
            source,
            "static void runAsyncRenderOnOwner() {",
        )
        admission = render[:render.index("    bool published = false;")]
        # Keep production admission and queue behavior, replacing GPU execution.
        admission += "    recordFrame();\n}\n"
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            post = function(source, "static bool postAsyncRenderTask(std::function<void()> task) {")
            (work / "camera_frame_order.inc").write_text(post + "\n" + prepare + "\n" + admission)
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
