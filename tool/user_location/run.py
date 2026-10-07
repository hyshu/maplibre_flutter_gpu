#!/usr/bin/env python3
"""Run the manual iOS location comparison against MapLibre Native."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent
BUILD = ROOT / "build" / "user_location"


def run(command, cwd, log, extra_env=None):
    env = os.environ.copy()
    env.update(extra_env or {})
    log.parent.mkdir(parents=True, exist_ok=True)
    print(" ".join(map(str, command)), flush=True)
    with log.open("w") as output:
        subprocess.run(command, cwd=cwd, env=env, stdout=output,
                       stderr=subprocess.STDOUT, check=True, timeout=900)


def clear_capture(implementation):
    output = BUILD / "captures" / implementation
    output.mkdir(parents=True, exist_ok=True)
    for image in output.glob(f"{implementation}-*.png"):
        image.unlink()
    (output / "metadata.json").unlink(missing_ok=True)
    return output


def prepare_reference():
    app = BUILD / "reference_app"
    app.mkdir(parents=True, exist_ok=True)
    shutil.copytree(
        ROOT / "e2e/visual/maplibre_gl_app/ios", app / "ios",
        dirs_exist_ok=True,
        ignore=shutil.ignore_patterns("Pods", ".symlinks", "ephemeral", "build"),
    )
    (app / "pubspec.yaml").write_text("""name: user_location_reference
publish_to: none
version: 1.0.0+1
environment:
  sdk: ^3.13.0
dependencies:
  flutter:
    sdk: flutter
  maplibre_gl: 0.26.2
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
flutter:
  uses-material-design: false
""")
    for directory in ["lib", "integration_test", "test_driver"]:
        (app / directory).mkdir(exist_ok=True)
    (app / "lib/main.dart").write_text("void main() {}\n")
    shutil.copy(SOURCE / "NativeReference.swift", app / "ios/Runner/AppDelegate.swift")
    shutil.copy(SOURCE / "reference_test.dart.template", app / "integration_test/reference_test.dart")
    shutil.copy(SOURCE / "scenarios.dart", app / "integration_test/scenarios.dart")
    shutil.copy(SOURCE / "driver.dart.template", app / "test_driver/driver.dart")
    return app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="Booted iOS Simulator UDID")
    parser.add_argument("--only", choices=["native", "gpu"])
    parser.add_argument("--check-templates", action="store_true")
    args = parser.parse_args()
    if args.check_templates:
        with tempfile.TemporaryDirectory(prefix="user-location-dart-") as temporary:
            files = []
            for source in SOURCE.glob("*.dart.template"):
                target = Path(temporary) / source.name.removesuffix(".template")
                shutil.copy(source, target)
                files.append(str(target))
            subprocess.run(["dart", "format", "--output=none", "--set-exit-if-changed", *files], check=True)
        return
    if not args.device:
        parser.error("--device is required unless --check-templates is used")
    logs = BUILD / "logs"
    if args.only != "gpu":
        app = prepare_reference()
        run(["flutter", "pub", "get"], app, logs / "native-pub-get.log")
        output = clear_capture("native")
        run(
            ["flutter", "drive", "--driver=test_driver/driver.dart",
             "--target=integration_test/reference_test.dart", "-d", args.device],
            app, logs / "native-capture.log",
            {"USER_LOCATION_OUTPUT": str(output)},
        )
    if args.only != "native":
        app = ROOT / "e2e/visual/gpu_app"
        driver = app / "build/user_location_driver.dart"
        driver.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(SOURCE / "driver.dart.template", driver)
        output = clear_capture("gpu")
        run(
            ["flutter", "drive", f"--driver={driver}",
             "--target=integration_test/user_location_test.dart", "-d", args.device],
            app, logs / "gpu-capture.log",
            {"USER_LOCATION_OUTPUT": str(output)},
        )
    print(f"Captures and logs: {BUILD}")


if __name__ == "__main__":
    main()
