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
- Never use a normal CI or Release preparation run as `artifact_run_id`. Their
  artifact contracts differ. Only a successful Release artifacts run contains
  all seven standard native artifact names accepted by Release preparation.
- When desktop artifacts change, finalize their checksums and update
  `hook/desktop_artifacts.json` in the release pull request. Never add a second
  manifest-only pull request after merging the release pull request.

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

5. Decide whether the desktop artifacts need rebuilding. Compare the current
   manifest's artifact source with `origin/main`. Rebuild when the diff changes
   native sources, vendor revisions, build hooks, desktop build configuration,
   or native build and packaging scripts. Keep the existing immutable assets
   when only Dart code, documentation, examples, tests, release metadata, or
   this Skill changed.

## Bootstrap changed desktop artifacts

Skip this section when the existing desktop assets remain compatible.

1. Run Release artifacts on the exact protected `origin/main` commit before
   preparing the release pull request. First list existing Release artifacts
   runs for that SHA and reuse or wait for an existing run instead of
   dispatching a duplicate.

   ```sh
   gh workflow run release-artifacts.yml --ref main
   ```

2. Require the workflow and every native build job to succeed. Require these
   seven standard artifacts.

   - `native-android-arm64-v8a`
   - `native-android-x86_64`
   - `native-darwin`
   - `native-linux-x64`
   - `native-linux-arm64`
   - `native-windows-x64`
   - `native-windows-arm64`

3. Download the four desktop archives and their `.sha256` files into a new
   temporary directory. Verify every sidecar, archive member, platform, and
   architecture. Calculate the SHA-256 values independently.

4. Prepare the manifest values for the release pull request. Use the immutable
   asset URL under `releases/download/v<target-version>/` and the independently
   verified checksums. Do not create the GitHub Release or package tag yet.
   Record the Release artifacts run ID and exact source SHA.

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

5. When desktop artifacts were rebuilt, update
   `hook/desktop_artifacts.json` with the prepared `v<target-version>` asset URL
   and verified SHA-256 values. Keep this update in the same release pull
   request as the version and CHANGELOG changes.

6. Keep `/.agents/` in `.pubignore` so the repository Skill does not enter the
   pub archive.

7. Update this Skill only when the release procedure itself changed.

8. Run preliminary checks that work with an intentionally dirty release tree.

   ```sh
   git diff --check
   flutter test test/package_configuration_test.dart
   ./tool/ci/check_publish.sh --metadata-only
   ```

9. Show the full proposed English CHANGELOG section, a Japanese translation for
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
   results in the pull request summary. When desktop artifacts changed, also
   include the Release artifacts run ID, source SHA, verified checksums,
   planned Release asset URL, and manifest update.

5. Wait for every required PR check. Require `Publish readiness` to complete its
   native-artifact-backed pub dry-run. Do not merge without user authorization.

## Finalize artifacts from merged main

1. Fetch `origin/main` after merge and resolve its exact commit. This may be a
   squash merge commit, so never substitute the pull request head SHA.

2. Select the successful Release artifacts run containing all seven standard
   artifacts. Never select a normal CI or Release preparation run. The
   pre-pull-request run may be reused when the full diff from its source SHA to
   the merge SHA contains only approved release metadata, CHANGELOG,
   `.pubignore`, this Skill, and the verified
   `hook/desktop_artifacts.json` update. Stop if any native source, vendor
   revision, build hook behavior, build configuration, or native build and
   packaging script changed. Release preparation enforces this allowlist too.

3. When the manifest points to new `v<target-version>` assets, download and
   reverify the four desktop archives from the selected artifact run. Stop for
   explicit user approval before creating the GitHub Release and uploading the
   eight archive and `.sha256` assets. Target the exact merge SHA. This may
   create a temporary lightweight `v<target-version>` tag. Do not move any
   existing tag or replace any existing asset.

4. Verify every manifest URL resolves to the uploaded immutable GitHub Release
   asset and every downloaded asset has the recorded SHA-256.

5. Before dispatching, list Release preparation runs for the exact merge SHA.
   Match both the SHA and Release artifacts run ID shown in the run title.
   Reuse or wait for an existing matching run instead of dispatching the same
   preparation twice.

   ```sh
   gh workflow run release-prepare.yml --ref main \
     -f artifact_run_id="$CI_RUN_ID"
   ```

6. Wait for the release preparation run. Download
   `release-bundle-<merge-sha>` into a new temporary directory.

7. Verify all bundle evidence.

   - `release-manifest.txt` names `hyshu/maplibre_flutter_gpu` and the exact
     merge SHA.
   - `SHA256SUMS` validates every native archive.
   - `pub-dry-run.log` reports the expected version and exactly the accepted
     checked-in gitlink warning involving `vendor/maplibre-native`.
   - Android arm64 and x86_64 archives and the Darwin archive are present.
   - Linux and Windows x64 and ARM64 archives match
     `hook/desktop_artifacts.json` byte for byte.

8. Create an isolated detached worktree at the exact merge SHA. Install only
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

4. After publication succeeds, ensure `v<target-version>` is an annotated tag
   on the exact merge SHA. If the desktop asset Release created a lightweight
   tag, replace only that tag object while preserving its peeled commit. Push
   the annotated tag and verify its peeled remote commit. Never rewrite the
   release commit.

5. Create a GitHub Release only when desktop build-hook assets require one or
   the user requests one. Desktop asset publication always requires explicit
   approval.

6. Report the pub.dev version, tag, commit, and any temporary artifacts left for
   cleanup.
