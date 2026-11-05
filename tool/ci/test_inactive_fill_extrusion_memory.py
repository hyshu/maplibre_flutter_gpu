import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "vendor/maplibre-native/src/mln/renderer"


def function(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


class InactiveFillExtrusionMemoryTest(unittest.TestCase):
    def test_integration_checks_preserve_core_build_configuration(self):
        cmake = (ROOT / "native/platforms/android/CMakeLists.txt").read_text()
        target = cmake[cmake.index("if(MAPLIBRE_BUILD_OFFLINE_MEMORY_TEST)"):]
        self.assertNotIn("-UNDEBUG", target)
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        self.assertIsNotNone(compiler, "A C++ compiler is required")
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source = work / "check.cpp"
            source.write_text('''#include "test_check.hpp"
int main() {
    int calls = 0;
    MAPLIBRE_TEST_CHECK(++calls == 1);
    return calls != 1;
}
''')
            for ndebug in (False, True):
                with self.subTest(ndebug=ndebug):
                    binary = work / f"check_{ndebug}"
                    subprocess.run([
                        compiler, "-std=c++20", *(["-DNDEBUG"] if ndebug else []),
                        "-I", str(ROOT / "native/tests"), str(source), "-o", str(binary),
                    ], check=True)
                    subprocess.run([str(binary)], check=True)

    def test_production_reclamation_ownership_and_policy(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        self.assertIsNotNone(compiler, "A C++ compiler is required")
        layer = (CORE / "layers/render_fill_extrusion_layer.cpp").read_text()
        orchestrator = (CORE / "render_orchestrator.cpp").read_text()
        implementation = "\n".join((
            function(layer, "std::size_t RenderFillExtrusionLayer::releaseInactiveRenderData() {"),
            function(orchestrator, "void RenderOrchestrator::releaseInactiveFillExtrusionData() {"),
        ))
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / "inactive_fill_extrusion.inc").write_text(implementation)
            for android, command_export in ((1, 1), (0, 1), (1, 0)):
                with self.subTest(android=android, command_export=command_export):
                    binary = work / f"inactive_fe_{android}_{command_export}"
                    subprocess.run([
                        compiler, "-std=c++20", f"-DTEST_ANDROID={android}",
                        f"-DTEST_COMMAND_EXPORT={command_export}", "-I", str(work),
                        str(ROOT / "native/tests/inactive_fill_extrusion_memory_test.cpp"),
                        "-o", str(binary),
                    ], check=True)
                    subprocess.run([str(binary)], check=True)

    def test_reclamation_follows_final_visibility_and_explicit_trim(self):
        source = (CORE / "render_orchestrator.cpp").read_text()
        visibility = source.index("markLayerRenderable(updateList[i], changes);")
        final_update = source.index("    renderTreeParameters->loaded =", visibility)
        reclamation = source.index("    releaseInactiveFillExtrusionData();", visibility)
        source_update_end = source.index("        addChanges(changes);\n    }", visibility)
        self.assertLess(source_update_end, reclamation)
        self.assertLess(reclamation, final_update)
        memory = function(source, "void RenderOrchestrator::reduceMemoryUse() {")
        self.assertLess(memory.index("releaseInactiveFillExtrusionData();"),
                        memory.index("entry.second->reduceMemoryUse();"))


if __name__ == "__main__":
    unittest.main()
