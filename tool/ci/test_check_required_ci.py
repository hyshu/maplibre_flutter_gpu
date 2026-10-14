"""Exercise the required gate with complete, skipped, and invalid CI results."""

import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

from check_required_ci import verify_needs
from select_ci import ALL_JOBS, JOB_DEPENDENCIES


SCRIPT = Path(__file__).with_name("check_required_ci.py")


def needs_fixture(selected=()):
    """Create a complete GitHub Actions needs payload for a selected job set."""
    selected = set(selected)
    plan = {job: job in selected for job in ALL_JOBS}

    return {
        "select": {"result": "success", "outputs": {"jobs": json.dumps(plan)}},
        **{
            job: {"result": "success" if plan[job] else "skipped", "outputs": {}}
            for job in ALL_JOBS
        },
    }


class RequiredCiTest(unittest.TestCase):
    def verify(self, needs):
        return verify_needs(json.dumps(needs))

    def test_full_run_requires_every_job(self):
        selected, skipped = self.verify(needs_fixture(ALL_JOBS))
        self.assertEqual(selected, list(ALL_JOBS))
        self.assertEqual(skipped, [])

    def test_no_selected_jobs_can_pass_with_valid_plan(self):
        selected, skipped = self.verify(needs_fixture())
        self.assertEqual(selected, [])
        self.assertEqual(skipped, list(ALL_JOBS))

    def test_partial_selection_keeps_skipped_jobs_out_of_gate(self):
        selected, skipped = self.verify(needs_fixture(("native-contracts",)))
        self.assertEqual(selected, ["native-contracts"])
        self.assertEqual(set(skipped), set(ALL_JOBS) - {"native-contracts"})

    def test_selected_job_must_succeed(self):
        for job in ALL_JOBS:
            for outcome in ("failure", "cancelled", "skipped", "neutral", "", None):
                with self.subTest(job=job, outcome=outcome):
                    needs = needs_fixture(ALL_JOBS)
                    needs[job]["result"] = outcome
                    with self.assertRaisesRegex(ValueError, job):
                        self.verify(needs)

    def test_unselected_job_must_be_skipped(self):
        for outcome in ("success", "failure", "cancelled", "neutral", "", None):
            with self.subTest(outcome=outcome):
                needs = needs_fixture()
                needs[ALL_JOBS[0]]["result"] = outcome
                with self.assertRaisesRegex(ValueError, "result 'skipped'"):
                    self.verify(needs)

    def test_missing_and_malformed_job_results_are_rejected(self):
        for entry in ({}, None, "success", [], {"result": True}):
            with self.subTest(entry=entry):
                needs = needs_fixture(ALL_JOBS)
                needs[ALL_JOBS[0]] = entry
                with self.assertRaisesRegex(ValueError, ALL_JOBS[0]):
                    self.verify(needs)

    def test_selector_must_succeed_even_when_nothing_is_selected(self):
        for outcome in ("failure", "cancelled", "skipped", "neutral", "", None):
            with self.subTest(outcome=outcome):
                needs = needs_fixture()
                needs["select"]["result"] = outcome
                with self.assertRaisesRegex(ValueError, "select must finish"):
                    self.verify(needs)

    def test_incomplete_and_unknown_needs_are_rejected(self):
        for missing in ("select", *ALL_JOBS):
            with self.subTest(missing=missing):
                needs = needs_fixture()
                del needs[missing]
                with self.assertRaisesRegex(ValueError, "needs has invalid job keys"):
                    self.verify(needs)
        needs = needs_fixture()
        needs["new_job"] = {"result": "success"}
        with self.assertRaisesRegex(ValueError, "unknown new_job"):
            self.verify(needs)

    def test_plan_requires_every_known_job_and_no_unknown_jobs(self):
        complete = {job: False for job in ALL_JOBS}
        for missing in ALL_JOBS:
            with self.subTest(missing=missing):
                plan = complete.copy()
                del plan[missing]
                needs = needs_fixture()
                needs["select"]["outputs"]["jobs"] = json.dumps(plan)
                with self.assertRaisesRegex(ValueError, "selection plan.*missing"):
                    self.verify(needs)
        complete["new_job"] = False
        needs = needs_fixture()
        needs["select"]["outputs"]["jobs"] = json.dumps(complete)
        with self.assertRaisesRegex(ValueError, "unknown new_job"):
            self.verify(needs)

    def test_plan_values_must_be_json_booleans(self):
        for value in (0, 1, "true", "false", None, [], {}):
            with self.subTest(value=value):
                needs = needs_fixture()
                plan = {job: False for job in ALL_JOBS}
                plan[ALL_JOBS[0]] = value
                needs["select"]["outputs"]["jobs"] = json.dumps(plan)
                with self.assertRaisesRegex(ValueError, "must be boolean"):
                    self.verify(needs)

    def test_malformed_plan_and_outputs_are_rejected(self):
        for outputs in (
            None, {}, "jobs", {"jobs": None}, {"jobs": {}}, {"jobs": ""},
            {"jobs": "{"}, {"jobs": "null"}, {"jobs": "[]"}, {"jobs": "{}"},
            {"jobs": '{"duplicate": true, "duplicate": false}'},
            {"jobs": '{"invalid": NaN}'},
        ):
            with self.subTest(outputs=outputs):
                needs = needs_fixture()
                needs["select"]["outputs"] = outputs
                with self.assertRaises(ValueError):
                    self.verify(needs)

    def test_selected_jobs_require_dependency_closure(self):
        for job, dependencies in JOB_DEPENDENCIES.items():
            for dependency in dependencies:
                with self.subTest(job=job, dependency=dependency):
                    needs = needs_fixture(set(ALL_JOBS) - {dependency})
                    with self.assertRaisesRegex(
                        ValueError, "requires selected dependency"
                    ):
                        self.verify(needs)

    def test_malformed_needs_json_is_rejected(self):
        for payload in (
            "", " ", "{", "null", "[]", "true", "{}",
            '{"select": {}, "select": {}}', '{"invalid": Infinity}',
        ):
            with self.subTest(payload=payload):
                with self.assertRaises(ValueError):
                    verify_needs(payload)

    def run_cli(self, payload):
        environment = os.environ.copy()
        environment.pop("CI_NEEDS_JSON", None)
        if payload is not None:
            environment["CI_NEEDS_JSON"] = payload

        return subprocess.run(
            [sys.executable, str(SCRIPT)],
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_cli_reports_selected_and_skipped_counts(self):
        result = self.run_cli(json.dumps(needs_fixture(("native-contracts",))))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"Selected 1, skipped {len(ALL_JOBS) - 1}", result.stdout)
        self.assertIn("Selected jobs: native-contracts", result.stdout)

    def test_cli_failure_names_failed_job_without_traceback(self):
        needs = needs_fixture(ALL_JOBS)
        needs["quality"]["result"] = "cancelled"
        result = self.run_cli(json.dumps(needs))
        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "quality must finish with result 'success', got 'cancelled'",
            result.stderr,
        )
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_requires_needs_environment(self):
        result = self.run_cli(None)
        self.assertEqual(result.returncode, 1)
        self.assertIn("CI_NEEDS_JSON", result.stderr)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
