#!/usr/bin/env python3
"""Assembles consumer-matrix.json from consumer_matrix.sh's raw step log
(TSV: app, step, exitCode, durationSeconds, command, artifact/log path).

Verdict rule (02-MOTION-AILESI-ORKESTRASYON.md §7 step 7): a consumer is
`passed` only if every required step ran and exited 0. One consumer
failing makes `matrix_passed` false and `task_state` REJECTED — there is
no partial-credit "4 of 5 is close enough" path.
"""
import argparse
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
import json

EXPECTED_CONSUMERS = ["lissom", "jablab", "gravita", "ostinato", "choreia"]
REQUIRED_STEPS = ["pub_get", "analyze", "test", "android_release"]
PSEUDO_STEPS = {"app_sha", "structure_check"}
KNOWN_ISSUES_PATH = Path(__file__).resolve().with_name("consumer_matrix_known_issues.json")


def load_known_issues():
    if not KNOWN_ISSUES_PATH.exists():
        return {}
    data = json.loads(KNOWN_ISSUES_PATH.read_text(encoding="utf-8"))
    data.pop("_readme", None)
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--steps-tsv", required=True)
    parser.add_argument("--core-sha", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    known_issues = load_known_issues()

    by_app_steps = defaultdict(list)
    app_sha = {}
    structural_errors = {}

    with open(args.steps_tsv, encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line:
                continue
            app, step, code, duration, command, artifact = line.split("\t", 5)
            if step == "app_sha":
                app_sha[app] = command  # SHA value was carried in the command field
                continue
            if step == "structure_check":
                structural_errors[app] = command
                continue
            by_app_steps[app].append({
                "step": step,
                "command": command,
                "exitCode": int(code),
                "durationSeconds": int(duration),
                "log": artifact,
            })

    consumers = []
    matrix_passed = True
    for app in EXPECTED_CONSUMERS:
        if app in structural_errors:
            consumers.append({
                "app": app,
                "appSha": None,
                "coreSha": args.core_sha,
                "steps": [],
                "missingRequiredSteps": REQUIRED_STEPS,
                "passed": False,
                "error": structural_errors[app],
            })
            matrix_passed = False
            continue

        steps = by_app_steps.get(app, [])
        present = {s["step"] for s in steps}
        missing = [s for s in REQUIRED_STEPS if s not in present]
        failed = [s["step"] for s in steps if s["exitCode"] != 0]
        app_passed = not missing and not failed and bool(steps)
        if not app_passed:
            matrix_passed = False

        # Known-issue annotations NEVER flip passed/failed — they only
        # attach an auditable root-cause note so a REJECTED verdict caused
        # by a pre-existing, unrelated app-side gap is not misread as a
        # core regression. See consumer_matrix_known_issues.json.
        app_known_issues = known_issues.get(app, {})
        annotated_failures = {
            step_name: app_known_issues[step_name]
            for step_name in failed
            if step_name in app_known_issues
        }
        unexplained_failures = [s for s in failed if s not in app_known_issues]

        consumers.append({
            "app": app,
            "appSha": app_sha.get(app),
            "coreSha": args.core_sha,
            "steps": steps,
            "missingRequiredSteps": missing,
            "failedSteps": failed,
            "knownIssues": annotated_failures,
            "unexplainedFailures": unexplained_failures,
            "passed": app_passed,
        })

    all_unexplained = [f"{c['app']}.{s}" for c in consumers for s in c["unexplainedFailures"]]

    result = {
        "task_id": "MOTION-CORE-002",
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "core_sha": args.core_sha,
        "consumers": consumers,
        "matrix_passed": matrix_passed,
        "task_state": "ACCEPTED" if matrix_passed else "REJECTED",
        "all_failures_explained_as_pre_existing": matrix_passed or not all_unexplained,
        "unexplained_failures": all_unexplained,
    }

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write("\n")

    summary = {c["app"]: c["passed"] for c in consumers}
    print(json.dumps({
        "matrix_passed": matrix_passed,
        "task_state": result["task_state"],
        "all_failures_explained_as_pre_existing": result["all_failures_explained_as_pre_existing"],
        "per_app": summary,
    }, indent=2))
    return 0 if matrix_passed else 1


if __name__ == "__main__":
    sys.exit(main())
