"""Check source compatibility without validating artifact contents or checksums."""

from pathlib import Path
import re
import subprocess
import sys


VERSION = rb"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
PUBSPEC_VERSION = (
    rb"^version:[ \t]+(?P<quote>['\"]?)(?P<version>"
    + VERSION
    + rb")(?P=quote)[ \t]*(?:#[^\r\n]*)?\r?$"
)
PODSPEC_VERSION = (
    rb"^[ \t]*s\.version[ \t]*=[ \t]*(?P<quote>['\"])(?P<version>"
    + VERSION
    + rb")(?P=quote)[ \t]*\r?$"
)
USER_AGENT_VERSION = (
    rb'^[ \t]*request\.setRequestProperty\("User-Agent", "maplibre_flutter_gpu/'
    rb"(?P<version>" + VERSION + rb')"\);[ \t]*\r?$'
)
LOCK_VERSION = (
    rb"^    version:[ \t]+(?P<quote>['\"]?)(?P<version>"
    + VERSION
    + rb")(?P=quote)[ \t]*\r?$"
)
EXAMPLE_PACKAGES = (
    "example",
    "examples/gpu_map_scene",
    "examples/map_layers",
    "examples/map_style_controls",
    "examples/tv_map_explorer",
)
VERSION_FILES = {
    "pubspec.yaml": PUBSPEC_VERSION,
    "darwin/maplibre_flutter_gpu.podspec": PODSPEC_VERSION,
    "android/src/main/java/org/maplibre/android/http/NativeHttpRequest.java":
        USER_AGENT_VERSION,
    **{f"{package}/pubspec.yaml": PUBSPEC_VERSION for package in EXAMPLE_PACKAGES},
}
LOCKFILES = {
    *(f"{package}/pubspec.lock" for package in EXAMPLE_PACKAGES),
    "e2e/visual/gpu_app/pubspec.lock",
}
NON_NATIVE_FILES = {
    "README.md",
    "CONTRIBUTING.md",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "CHANGELOG.md",
    ".pubignore",
    ".agents/skills/release-maplibre-flutter-gpu/SKILL.md",
    "hook/desktop_artifacts.json",
    "tool/ci/verify_release_artifact_source.sh",
    "tool/ci/verify_release_artifact_source.py",
    "tool/ci/test_verify_release_artifact_source.py",
}


def _git(repository: Path, *arguments: str) -> bytes:
    return subprocess.check_output(
        ["git", "--literal-pathspecs", "-C", str(repository), *arguments]
    )


def _version_match(content: bytes, pattern: bytes) -> re.Match:
    matches = list(re.finditer(pattern, content, re.MULTILINE))
    if len(matches) != 1:
        raise ValueError("expected exactly one stable package version")
    return matches[0]


def _normalize_version(content: bytes, pattern: bytes, expected: bytes) -> bytes:
    match = _version_match(content, pattern)
    if match["version"] != expected:
        raise ValueError("version does not match the root pubspec")
    start, end = match.span("version")
    return content[:start] + b"<package-version>" + content[end:]


def _normalize_lockfile(content: bytes, expected: bytes) -> bytes:
    # Only the path dependency's version may change. Other locked inputs stay fixed.
    pattern = rb"^  maplibre_flutter_gpu:\r?\n(?P<body>(?:    [^\n]*\n)+)"
    blocks = list(re.finditer(pattern, content, re.MULTILINE))
    if len(blocks) != 1:
        raise ValueError("expected one maplibre_flutter_gpu lockfile entry")
    block = blocks[0]
    body = block["body"]
    if not re.search(rb"^    source: path\r?$", body, re.MULTILINE):
        raise ValueError("expected a path dependency")
    normalized = _normalize_version(body, LOCK_VERSION, expected)
    start, end = block.span("body")
    return content[:start] + normalized + content[end:]


def _non_native_path(path: str) -> bool:
    if path in NON_NATIVE_FILES:
        return True
    if path.startswith("lib/src/widgets/") and path.endswith(".dart"):
        return True
    if path.startswith("docs/") and path.endswith(".md"):
        return True
    if path.startswith("test/"):
        return True
    return path.startswith(("example/", "examples/", "e2e/")) and path.endswith(
        (".dart", ".md")
    )


def verify_source(repository: Path, artifact_source: str, release: str) -> None:
    """Require ancestry and allow only changes outside native artifact contracts."""
    source = _git(repository, "rev-parse", "--verify", f"{artifact_source}^{{commit}}")
    target = _git(repository, "rev-parse", "--verify", f"{release}^{{commit}}")
    source_sha = source.decode().strip()
    target_sha = target.decode().strip()
    _git(repository, "merge-base", "--is-ancestor", source_sha, target_sha)
    versions = [
        _version_match(
            _git(repository, "show", f"{commit}:pubspec.yaml"), PUBSPEC_VERSION
        )["version"]
        for commit in (source_sha, target_sha)
    ]
    changes = _git(
        repository, "diff", "--name-only", "--no-renames", "-z", source_sha, target_sha
    )
    for raw_path in changes.split(b"\0"):
        if not raw_path:
            continue
        path = raw_path.decode("utf-8", errors="surrogateescape")
        try:
            if path not in VERSION_FILES and path not in LOCKFILES:
                if not _non_native_path(path):
                    raise ValueError("native input, native-facing Dart, or unclassified path")
            entries = [
                _git(repository, "ls-tree", "-z", commit, "--", path)
                for commit in (source_sha, target_sha)
            ]
            modes = [entry.split(b" ", 1)[0] if entry else None for entry in entries]
            if any(mode not in (None, b"100644", b"100755") for mode in modes):
                raise ValueError("only regular files are allowed")
            if all(modes) and modes[0] != modes[1]:
                raise ValueError("file mode changed")
            if path in VERSION_FILES or path in LOCKFILES:
                if not all(modes):
                    raise ValueError("version files must exist in both commits")
                contents = [
                    _git(repository, "show", f"{commit}:{path}")
                    for commit in (source_sha, target_sha)
                ]
                normalized = [
                    _normalize_lockfile(content, version)
                    if path in LOCKFILES
                    else _normalize_version(content, VERSION_FILES[path], version)
                    for content, version in zip(contents, versions)
                ]
                if normalized[0] != normalized[1]:
                    raise ValueError("changes beyond the package version")
        except ValueError as error:
            raise ValueError(
                f"artifact source is incompatible with release change: {path} ({error})"
            ) from error


def main() -> None:
    try:
        verify_source(Path(sys.argv[3]), sys.argv[1], sys.argv[2])
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"error: {error}") from error
    print("Release artifact source is compatible with the release commit.")


if __name__ == "__main__":
    main()
