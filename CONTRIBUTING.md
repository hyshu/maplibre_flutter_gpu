# Contributing

Thank you for helping improve MapLibre Flutter GPU.

The package is in beta. API and runtime behavior may change. Small and focused
pull requests are easier to review and test.

## Before you start

Search existing issues before opening a new one. Open an issue before starting
a large API, native bridge, ABI, or rendering change.

Use the issue forms for bug reports, feature requests, and Android compatibility
reports. Remove API keys, access tokens, private style URLs, and personal data
from all examples and logs.

## Development environment

CI uses Flutter 3.47.0. The package requires Dart 3.13 or later and Flutter
3.47.0 or later.

Clone the repository with its submodules.

```bash
git clone --recurse-submodules https://github.com/hyshu/maplibre_flutter_gpu.git
cd maplibre_flutter_gpu
flutter pub get
```

For an existing clone, initialize or update the submodules.

```bash
git submodule update --init --recursive
```

Native changes also require the platform toolchain for the target platform.
The CI workflows are the reference for tool versions and system packages.

## Repository layout

- `lib/` contains the public Dart API and Flutter GPU renderer.
- `native/` contains the native bridge and platform build scripts.
- `vendor/maplibre-native/` is the MapLibre Native submodule.
- `shaders/` contains the map shaders.
- `test/` contains package tests.
- `example/` and `examples/` contain runnable examples.
- `e2e/visual/` contains visual and functional end-to-end tests.

## Working on a change

Keep changes focused. Add or update tests for changed behavior. Update public
API documentation and the README when user-facing behavior changes.

Do not edit `lib/src/native/abi_generated.dart` by hand. Regenerate it after a
native ABI layout change.

```bash
dart run tool/gen_abi.dart
```

Run the relevant native build script after changing the native bridge.

```bash
./native/scripts/build_android.sh arm64-v8a
./native/scripts/build_linux.sh
./native/scripts/package_darwin.sh all
```

Use `native/scripts/build_windows.ps1` on Windows. Test every architecture or
platform affected by the change when practical.

## Validation

Use targeted checks while developing.

```bash
dart format lib test
dart analyze
flutter test
```

Run the project quality script before opening a pull request.

```bash
./tool/ci/quality.sh
```

The script checks formatting, analysis, package tests, line coverage, generated
shader bundles, and the working tree. It expects intentional changes to be
staged or committed before its final clean diff check.

Run visual tests for rendering changes on an affected platform. Include before
and after images when output changes intentionally. GitHub Actions runs the full
platform and architecture matrix, so contributors do not need to reproduce the
entire matrix locally.

## Code style

Write source comments in concise, natural English. Document stable contracts,
ownership, units, errors, and lifecycle requirements when they are not obvious.
Document public APIs.

Leave a blank line before a `return` that follows another statement. Do not add
that blank line when the preceding line closes a scope or the `return` is the
only statement in its scope.

## Commits and pull requests

Use Conventional Commits for commit messages and pull request titles.

```text
fix: handle missing native library
feat: add camera bounds support
```

Use `chore: release <version>` for release commits and release pull requests.
Keep the title suitable for a squash merge commit.

In the pull request description, include:

- the problem and chosen approach
- related issues
- tests that were run
- affected platforms, architectures, and build modes
- screenshots or visual reports for rendering changes
- compatibility or migration notes for API changes
