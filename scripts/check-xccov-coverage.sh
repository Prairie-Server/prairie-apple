#!/usr/bin/env bash
# Fail CI when scoped xccov line coverage is below a minimum percentage.
#
# Usage:
#   check-xccov-coverage.sh <coverage.json> <min_percent> [path_substr ...]
#
# Defaults path filters to Networking units with dedicated PrairieTests
# coverage (measured ~78% on CI). Whole-folder /Networking/ is ~23% and is
# not a realistic 75% gate. Pass extra substrings to widen/narrow the gate.
#
# Example:
#   check-xccov-coverage.sh coverage.json 75 /Networking/AIModels.swift

# Exit codes:
#   0 — coverage meets or exceeds min_percent
#   1 — coverage below gate, or missing/invalid input

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <coverage.json> <min_percent> [path_substr ...]" >&2
  exit 1
fi

JSON_PATH="$1"
MIN_PERCENT="$2"
shift 2

if [[ ! -f "$JSON_PATH" ]]; then
  echo "error: coverage json not found: $JSON_PATH" >&2
  exit 1
fi

if ! [[ "$MIN_PERCENT" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "error: min_percent must be numeric, got: $MIN_PERCENT" >&2
  exit 1
fi

# Default scope: Networking files PrairieTests primarily cover.
if [[ $# -eq 0 ]]; then
  PATH_FILTERS=(
    "/Networking/AIModels.swift"
    "/Networking/AIJobPoller.swift"
    "/Networking/SubtitleSearchModels.swift"
    "/Networking/TrackSelectionPersistence.swift"
    "/Networking/LAN/PrairieFrame.swift"
  )
else
  PATH_FILTERS=("$@")
fi

PATH_FILTERS_JSON="$(printf '%s\n' "${PATH_FILTERS[@]}" | python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in sys.stdin]))')"
export JSON_PATH MIN_PERCENT PATH_FILTERS_JSON

python3 <<'PY'
import json
import os
import sys

json_path = os.environ["JSON_PATH"]
min_percent = float(os.environ["MIN_PERCENT"])
filters = json.loads(os.environ["PATH_FILTERS_JSON"])

with open(json_path, "r", encoding="utf-8") as f:
    report = json.load(f)

targets = report.get("targets") or []
# Prefer the main app product PrairieTests loads via TEST_HOST.
app_targets = [
    t for t in targets
    if str(t.get("name", "")).endswith(".app")
    and "Prairie" in str(t.get("name", ""))
    and "Tests" not in str(t.get("name", ""))
]
if not app_targets:
    app_targets = [t for t in targets if str(t.get("name", "")).endswith(".app")]
if not app_targets:
    print("error: no .app target found in xccov report", file=sys.stderr)
    sys.exit(1)

target = max(app_targets, key=lambda t: int(t.get("executableLines") or 0))
target_name = target.get("name", "<unknown>")

overall_exec = int(target.get("executableLines") or 0)
overall_cov = int(target.get("coveredLines") or 0)
overall_pct = (100.0 * overall_cov / overall_exec) if overall_exec else 0.0

scoped_exec = 0
scoped_cov = 0
matched_files = 0
for entry in target.get("files") or []:
    path = entry.get("path") or entry.get("name") or ""
    if not any(substr in path for substr in filters):
        continue
    exec_lines = int(entry.get("executableLines") or 0)
    cov_lines = int(entry.get("coveredLines") or 0)
    if exec_lines <= 0:
        continue
    matched_files += 1
    scoped_exec += exec_lines
    scoped_cov += cov_lines

if scoped_exec <= 0:
    print(
        f"error: no executable lines matched filters {filters!r} "
        f"in target {target_name!r}",
        file=sys.stderr,
    )
    sys.exit(1)

scoped_pct = 100.0 * scoped_cov / scoped_exec

print(f"target:            {target_name}")
print(f"overall lines:     {overall_cov}/{overall_exec} ({overall_pct:.2f}%)")
print(f"path filters:      {filters}")
print(f"matched files:     {matched_files}")
print(f"scoped lines:      {scoped_cov}/{scoped_exec} ({scoped_pct:.2f}%)")
print(f"required minimum:  {min_percent:.2f}%")

if scoped_pct + 1e-9 < min_percent:
    print(
        f"FAIL: scoped line coverage {scoped_pct:.2f}% "
        f"is below {min_percent:.2f}%",
        file=sys.stderr,
    )
    sys.exit(1)

print(f"PASS: scoped line coverage {scoped_pct:.2f}% meets {min_percent:.2f}% gate")
PY
