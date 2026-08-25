# Comment Style

- Write source comments in concise, natural English.
- Document stable contracts and invariants instead of implementation history, tests, or temporary compatibility details.
- Explain behavior that is not obvious from the code, including ownership, units, null results, errors, and lifecycle requirements.
- Do not merely restate names or operations visible in the code.
- Avoid em dashes, semicolons, and label-style colons in prose. Prefer complete sentences.
- Add documentation to public APIs and to private code only when its contract or purpose is not self-evident.

# Dart Style

- Leave a blank line before a `return` that follows another statement.
- Do not leave that blank line when the preceding line closes a scope or the `return` is the only statement in its scope.
- A one-line control statement still requires a blank line before a following `return`.

# Git Style

- Do not use the `codex/` prefix for branch names or pull request titles. Match existing names and use a Conventional Commit type such as `feat/`, `fix/`, `docs/`, or `chore/` for branches.
- Use Conventional Commits for commit messages and pull request titles.
- Use a lowercase type followed by a concise imperative summary, such as
  `fix: handle missing native library`.
- Name release commits and pull requests `chore: release <version>`.
- Keep pull request titles suitable for use as squash merge commit titles.
