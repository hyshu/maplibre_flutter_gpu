from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class OwnerDispatchTest(unittest.TestCase):
    def test_sync_wait_ends_after_owner_exit_without_releasing_queued_tasks(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        self.assertIsNotNone(compiler, "A C++ compiler is required")
        source = (ROOT / "native/src/bridge_state.hpp").read_text()
        start = source.index("template <typename Operation>\nauto bridge_runOnOwnerSync(")
        end = source.index("template <typename Operation>\nbool bridge_runOnOwnerAsync(", start)
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / "owner_dispatch.inc").write_text(source[start:end])
            binary = work / "owner_dispatch_test"
            subprocess.run(
                [compiler, "-std=c++20", "-pthread", "-I", str(work),
                 str(ROOT / "native/tests/owner_dispatch_test.cpp"),
                 "-o", str(binary)],
                check=True,
            )
            subprocess.run([str(binary)], check=True, timeout=10)


if __name__ == "__main__":
    unittest.main()
