#!/usr/bin/env bash
# MOTION-CORE-002: five-consumer contract matrix.
#
# Verifies that each Motion app still resolves, analyzes, tests and
# compiles clean against the shared motion_core/motion_camera pin declared
# in its own pubspec.yaml. Per 02-MOTION-AILESI-ORKESTRASYON.md §7 step 7:
# one consumer failing REJECTS the whole matrix — a 4-out-of-5 pass is not
# an accepted result, so this script always runs every consumer to
# completion (it does not stop at the first failure) and lets
# build_consumer_matrix_json.py apply the pass/fail verdict afterward.
#
# Usage: tools/consumer_matrix.sh
# Output: ../workspace/artifacts/consumer-matrix.json (+ one .log per
# app/step under ../workspace/artifacts/consumer-matrix/ for evidence).
set -uo pipefail

CONSUMERS=(lissom jablab gravita ostinato choreia)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENTURES_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
ARTIFACTS_DIR="$REPO_ROOT/../workspace/artifacts/consumer-matrix"
RESULT_JSON="$REPO_ROOT/../workspace/artifacts/consumer-matrix.json"
CORE_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
STEPS_TSV="$ARTIFACTS_DIR/_steps.tsv"

mkdir -p "$ARTIFACTS_DIR"
: > "$STEPS_TSV"

run_step() {
  # run_step <app> <app_dir> <step_name> <command...>
  local app="$1" app_dir="$2" step="$3"
  shift 3
  local log="$ARTIFACTS_DIR/${app}.${step}.log"
  local start end duration code
  start=$(date +%s)
  ( cd "$app_dir" && "$@" ) > "$log" 2>&1
  code=$?
  end=$(date +%s)
  duration=$((end - start))
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$app" "$step" "$code" "$duration" "$*" "$log" >> "$STEPS_TSV"
  return $code
}

for app in "${CONSUMERS[@]}"; do
  app_dir="$VENTURES_ROOT/$app/app"
  echo "=== $app ==="

  if [ ! -d "$app_dir" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$app" "structure_check" "1" "0" "app dir not found: $app_dir" "" >> "$STEPS_TSV"
    echo "  SKIP: $app_dir does not exist"
    continue
  fi

  app_sha="$(git -C "$app_dir" rev-parse HEAD 2>/dev/null || echo unknown)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$app" "app_sha" "0" "0" "$app_sha" "" >> "$STEPS_TSV"

  if run_step "$app" "$app_dir" pub_get flutter pub get; then
    run_step "$app" "$app_dir" analyze flutter analyze
    run_step "$app" "$app_dir" test flutter test
    # -PallowDebugSigning=true is each app's OWN documented escape hatch for
    # exactly this situation (no android/key.properties on this machine —
    # release keystores are founder secrets that live in ~/.secrets/yula/
    # and must never be present in a session's environment). This proves
    # compileability against the core pin; the resulting APK is debug-signed
    # and MUST NOT be treated as, or promoted to, a real release artifact.
    run_step "$app" "$app_dir" android_release flutter build apk --release -PallowDebugSigning=true
    if [ "$(uname)" = "Darwin" ]; then
      run_step "$app" "$app_dir" ios_release_no_codesign flutter build ios --release --no-codesign
    fi
  else
    echo "  pub_get failed — skipping analyze/test/build for $app (would fail anyway without resolved deps)"
  fi
done

python3 "$SCRIPT_DIR/build_consumer_matrix_json.py" \
  --steps-tsv "$STEPS_TSV" --core-sha "$CORE_SHA" --out "$RESULT_JSON"
exit $?
