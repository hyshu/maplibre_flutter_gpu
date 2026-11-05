# Branch review and verification harness

Two entry points. `branch_agent.py` runs Claude Agent SDK sessions for the parts
of the work that need judgement. `device_verify.py` runs the measurements and
keeps them reproducible without a model in the loop.

The split is deliberate. A model reads code and interprets numbers. It does not
decide the measurement procedure, because a procedure that changes between runs
cannot support a performance claim. `house_rules.md` holds the rules both sides
follow, taken from `maplibre_compare/README.md` and `AGENTS.md`.

## Which branch to run this from

This harness lives on its own branch so that it stays out of the diff of the
work it reviews. A review set under `dimensions/` names the files of the branch
it reviews, so those files have to be present in the tree. Merge this branch
into the branch under review, or add a worktree for that branch and merge there.
`branch_agent.py review` stops and lists the absent paths when the wrong branch
is checked out.

## Setup

Keep the virtual environment outside the repository, so that switching branches
never leaves it behind in a tree that does not expect it.

```bash
python3 -m venv ~/.venvs/mlfg-agents
~/.venvs/mlfg-agents/bin/pip install -r tool/agents/requirements.txt
```

The SDK runs the local `claude` binary, so it uses the credentials already
configured on this machine. `claude-fable-5-1` must be reachable through them.
`ANTHROPIC_BASE_URL` is honoured, so a gateway that does not serve that model
will fail the session. `config.FALLBACK_MODEL` covers that case.

Listing and validating review sets needs no SDK, so plain `python3` runs those.

## Review sets

A set is one JSON file under `dimensions/`, holding a `base` ref and one entry
per dimension with its title, platforms, reviewed paths and focus. Paths may not
be claimed by two dimensions of the same set, so parallel sessions never read
the same file twice.

```bash
python3 tool/agents/branch_agent.py dimensions
python3 tool/agents/branch_agent.py dimensions --dimensions android-render-memory
```

The second form marks the dimensions whose paths are absent from the tree.

## Review

```bash
~/.venvs/mlfg-agents/bin/python tool/agents/branch_agent.py review \
  --dimensions android-render-memory
~/.venvs/mlfg-agents/bin/python tool/agents/branch_agent.py review \
  --dimensions android-render-memory --dimension vertex-repack
```

One session per dimension, each read only, each with a dollar ceiling from
`--budget`. Findings land in `tool/agents/out` as one JSON file per dimension
plus `review-summary.json`, sorted so that confirmed memory safety defects come
first.

A finding carries the input that triggers it and the on device check that would
settle it. A finding without a trigger is not reported.

## Plan

```bash
~/.venvs/mlfg-agents/bin/python tool/agents/branch_agent.py plan
```

Turns the findings into experiments with explicit dart-define configurations,
scenes, devices and run counts. It puts an experiment on iOS only when the
change reaches shared Dart or native code, and lists what it skipped and why.

## Measure

```bash
python3 tool/agents/device_verify.py preflight
python3 tool/agents/device_verify.py android \
  --config off=/tmp/candidate-off.apk --config on=/tmp/candidate-on.apk \
  --scene liberty --engine gpu --runs 3 --cpu
python3 tool/agents/device_verify.py summary \
  tool/agents/out/measurements/liberty-*.json
```

`android` rotates the configuration order every round, records the SHA-256 of
each APK, and writes a run manifest. Build the APKs with a freeze script under
`maplibre_compare/tool` first, so the provenance manifest exists. This harness
refuses to build, because an unrecorded build cannot be compared later.

`ios` prints the verified install command for a prebuilt IPA with its hash
filled in. The artifact manifest and its hash stay manual on purpose.

## Interpret

```bash
~/.venvs/mlfg-agents/bin/python tool/agents/branch_agent.py interpret \
  tool/agents/out/measurements/liberty-*.json \
  --question "Does the symbol layer reuse flag earn a default of on?"
```

Checks comparability first and reports every problem it finds, then compares
matched pairs and drafts `findings-draft.md` in the style of the documents under
`maplibre_compare/results`. The draft is a draft. Read it against the raw JSON
before committing anything.

## What this harness does not do

- It does not measure performance by itself and it does not trust a model's
  reading of a number over the recorded JSON.
- It does not edit the tree. Every session denies the write tools.
- It does not decide to turn a flag on. The default stays off unless the
  measurements point the same way across pairs.

## Devices

`config.py` pins the attached hardware. Update it when the hardware changes.
