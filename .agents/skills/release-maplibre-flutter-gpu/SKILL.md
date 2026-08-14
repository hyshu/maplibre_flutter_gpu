---
name: release-maplibre-flutter-gpu
description: Prepare and publish releases of the maplibre_flutter_gpu Dart and Flutter package through a reviewed release PR, CI artifacts, pub.dev publication, and version tagging. Use when asked to prepare a release, bump a package version, draft release notes, run publish checks, create a release PR, publish to pub.dev, or tag a published version in this repository.
---

# Release MapLibre Flutter GPU

Prepare one stable package version from the protected `main` branch. Preserve
the relationship between reviewed source, native artifacts, pub.dev contents,
and the version tag.

## Safety gates

- Preserve unrelated worktree changes. Stop when their ownership or release
  scope is unclear.
- Never publish from a feature branch, pull request ref, dirty tree, or commit
  other than the reviewed commit merged into `main`.
- Present the proposed CHANGELOG entry and its diff to the user. Do not stage,
  commit, push, or create a pull request until the user explicitly approves it.
  Present it again after every CHANGELOG revision.
- Present a Japanese translation beside every proposed English CHANGELOG entry
  so the user can review its meaning. Keep the translation out of
  `CHANGELOG.md` unless the user explicitly requests otherwise.
- Treat CHANGELOG approval and publication approval as separate decisions.
  Request explicit approval immediately before `dart pub publish`.
- Do not use `--force` or `--skip-validation` when publishing.
- Stop on any version, tag, commit, artifact, checksum, dry-run, or CI mismatch.
- Treat the four desktop archives as immutable build-hook dependencies. Never
  change their manifest URL or checksums without verifying the exact release
  assets first.

## Inspect the release baseline

1. Confirm the repository and fetch current refs.

   ```sh
   gh repo view --json nameWithOwner --jq .nameWithOwner
   git fetch origin main --tags
   git status --short --branch
   ```

   Require `hyshu/maplibre_flutter_gpu`. Start from a clean worktree unless the
   existing changes are already confirmed release work.

2. Read the current version from `pubspec.yaml`. Validate the requested target
   as a stable `major.minor.patch` version greater than the current version.

3. Require the annotated tag `v<current-version>` to exist locally and on the
   remote. Require it to resolve to the published release commit. Confirm the
   target version is absent from both Git tags and the pub.dev package API.

4. Use `v<current-version>..origin/main` as the release-note baseline. Inspect
   commits, pull requests, and diffs. Describe user-visible behavior rather than
   copying commit titles.

## Prepare the release pull request

1. Create or reuse `chore/release-<target-version>` from current `origin/main`.

2. Update these version surfaces to the target version.

   - `pubspec.yaml`
   - `example/pubspec.yaml`
   - `examples/gpu_map_scene/pubspec.yaml`
   - `examples/map_style_controls/pubspec.yaml`
   - `darwin/maplibre_flutter_gpu.podspec`
   - The package version in the Android HTTP User-Agent

3. Regenerate lockfiles with `flutter pub get`. Do not edit generated lockfiles
   by hand. Regenerate the three example lockfiles and
   `e2e/visual/gpu_app/pubspec.lock`, whose path dependency records the package
   version.

4. Add `## <target-version>` at the top of `CHANGELOG.md`. Keep entries concise,
   factual, and relevant to package users. Include packaging fixes when they
   change the installed package.

5. Keep `/.agents/` in `.pubignore` so the repository Skill does not enter the
   pub archive.

6. Update this Skill only when the release procedure itself changed.

7. Run preliminary checks that work with an intentionally dirty release tree.

   ```sh
   git diff --check
   flutter test test/package_configuration_test.dart
   ./tool/ci/check_publish.sh --metadata-only
   ```

8. Show the full proposed English CHANGELOG section, a Japanese translation for
   review, and `git diff -- CHANGELOG.md`. Keep only the English entry in the
   file. Stop for explicit user approval. Do not continue from silence or a
   general request to release.

## Validate and open the pull request

Continue only after CHANGELOG approval.

1. Run the `skill-creator` quick validator against
   `.agents/skills/release-maplibre-flutter-gpu`.

2. Review the complete diff and stage only release files. Keep release content,
   release automation, and Skill changes in separate focused commits. They may
   share one pull request.

3. Run `./tool/ci/quality.sh` from the clean commit. Fix failures before pushing.
   Ask for CHANGELOG approval again if a fix changes release notes.

4. Push the `chore/` branch and create a pull request against `main`. Include
   the version bump, release notes, version-surface fixes, Skill, and validation
   results in the pull request summary.

5. Wait for every required PR check. Require `Publish readiness` to complete its
   native-artifact-backed pub dry-run. Do not merge without user authorization.

## Prepare artifacts from merged main

1. Fetch `origin/main` after merge and resolve its exact commit. This may be a
   squash merge commit, so never substitute the pull request head SHA.

2. Select a successful native-artifact run. Prefer a `push` run for the exact
   merge SHA. An earlier successful run may be reused when every later change
   is demonstrably unrelated to native build inputs or packaging, such as
   README, CHANGELOG, funding, version metadata, or this Skill. Inspect the full
   diff from the artifact source SHA to the merge SHA and stop if it changes
   native sources, vendor revisions, build hooks, artifact manifests, or native
   build and packaging scripts.

3. Before dispatching, list release preparation runs for the exact merge SHA.
   Match both the SHA and `artifact_run_id` shown in the run title. Reuse or wait
   for an existing matching run instead of dispatching the same preparation
   twice.

   ```sh
   gh workflow run release-prepare.yml --ref main \
     -f artifact_run_id="$CI_RUN_ID"
   ```

4. Wait for the release preparation run. Download
   `release-bundle-<merge-sha>` into a new temporary directory.

5. Verify all bundle evidence.

   - `release-manifest.txt` names `hyshu/maplibre_flutter_gpu` and the exact
     merge SHA.
   - `SHA256SUMS` validates every native archive.
   - `pub-dry-run.log` reports the expected version and exactly the accepted
     checked-in gitlink warning involving `vendor/maplibre-native`.
   - Android arm64 and x86_64 archives and the Darwin archive are present.
   - Linux and Windows x64 and ARM64 archives match
     `hook/desktop_artifacts.json` byte for byte.

6. Require every URL in `hook/desktop_artifacts.json` to resolve to an immutable
   GitHub Release asset with the recorded SHA-256. If the release does not
   exist, stop and request explicit approval before creating it. Do not use an
   expiring Actions artifact URL as a build-hook endpoint.

7. Create an isolated detached worktree at the exact merge SHA. Install only
   the Android and Darwin artifacts with `tool/ci/install_native_artifacts.sh`.
   Desktop binaries stay outside the pub package. Run
   `./tool/ci/check_publish.sh` there and require zero warnings. The isolated
   worktree expectation differs from the accepted CI bundle gitlink warning.

## Publish and tag

1. Present the target version, merge SHA, main CI run, release preparation run,
   manifest, checksum result, and final dry-run result. Stop for explicit
   publication approval.

2. Run the interactive command from the verified worktree with a TTY.

   ```sh
   dart pub publish
   ```

3. Read the target version from the pub.dev version API. Download its
   `archive_url`, calculate SHA-256, and require it to equal the API's
   `archive_sha256`. Inspect that downloaded archive for the Android arm64 and
   x86_64 libraries, Darwin XCFramework, shader bundle, build hook, and desktop
   artifact manifest. Confirm it excludes raw Linux and Windows libraries.

4. Create annotated tag `v<target-version>` on the exact merge SHA only after
   publication succeeds. Push that tag and verify its peeled remote commit.

5. Create a GitHub Release only when the user requests one.

6. Report the pub.dev version, tag, commit, and any temporary artifacts left for
   cleanup.
