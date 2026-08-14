#!/usr/bin/env python3

import hashlib
import json
import pathlib
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: verify_desktop_release_manifest.py <manifest> <artifact-dir>"
        )
    manifest_path = pathlib.Path(sys.argv[1])
    artifact_directory = pathlib.Path(sys.argv[2])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 1:
        raise SystemExit("error: unsupported desktop artifact manifest")
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list) or len(artifacts) != 4:
        raise SystemExit("error: desktop manifest must contain four artifacts")

    targets: set[tuple[str, str]] = set()
    for artifact in artifacts:
        target = (artifact["os"], artifact["architecture"])
        targets.add(target)
        archive = artifact_directory / artifact["archive"]
        actual = hashlib.sha256(archive.read_bytes()).hexdigest()
        if actual != artifact["sha256"]:
            raise SystemExit(
                f"error: checksum mismatch for {archive.name}: "
                f"expected {artifact['sha256']}, found {actual}"
            )
    expected = {
        ("linux", "x64"),
        ("linux", "arm64"),
        ("windows", "x64"),
        ("windows", "arm64"),
    }
    if targets != expected:
        raise SystemExit("error: desktop manifest target set is incomplete")


if __name__ == "__main__":
    main()
