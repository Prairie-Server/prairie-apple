#!/usr/bin/env bash
# Fail CI when scoped xccov line coverage is below a minimum percentage.
#
# Usage:
#   check-xccov-coverage.sh <coverage.json> <min_percent> [path_substr ...]
#
# Default path filter is `/Networking/` — the unit-testable Networking surface
# AGENTS.md describes. Live HTTP / session modules that need a real server (or
# heavy URLSession mocking) are excluded from the default scope so the 95%
# gate stays enforceable while still covering models, persistence, stores that
# are pure-logic, and frame codecs. Pass explicit path substrings to replace
# the default include list (excludes still apply unless XCCOV_NO_EXCLUDES=1).
#
# Optional env:
#   XCCOV_PATH_EXCLUDES  — newline- or comma-separated path substrings to drop
#                          (overrides the built-in live-network exclude list)
#   XCCOV_NO_EXCLUDES=1  — disable excludes (gate truly all matched paths)
#
# Example:
#   check-xccov-coverage.sh coverage.json 95 /Networking/AIModels.swift

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

# Default scope: whole /Networking/ folder (minus live-network clients below).
if [[ $# -eq 0 ]]; then
  PATH_FILTERS=(
    "/Networking/"
  )
else
  PATH_FILTERS=("$@")
fi

# Built-in excludes: ContinuumAPI / HTTPClient / store refreshers / LAN session
# I/O. These are integration-heavy; PrairieTests covers the pure-logic sibling
# modules (models, TokenStore, ServerRegistry migration, PrairieFrame, …).
DEFAULT_EXCLUDES=(
  "/Networking/ContinuumAPI.swift"
  "/Networking/ContinuumAPI+LiveTV.swift"
  "/Networking/ContinuumAPI+Requests.swift"
  "/Networking/ContinuumAI.swift"
  "/Networking/HTTPClient.swift"
  "/Networking/DiagnosticsAPI.swift"
  "/Networking/ConnectionMonitor.swift"
  "/Networking/LAN/FramedJSONSession.swift"
  "/Networking/OverlayPrefsStore.swift"
  "/Networking/PlaybackPrefsStore.swift"
  "/Networking/ProfilePrefsStore.swift"
  "/Networking/AICapabilities.swift"
  "/Networking/RequestsFeatureStore.swift"
  "/Networking/LiveTVFeatureStore.swift"
)

if [[ "${XCCOV_NO_EXCLUDES:-}" == "1" ]]; then
  PATH_EXCLUDES=()
elif [[ -n "${XCCOV_PATH_EXCLUDES:-}" ]]; then
  # shellcheck disable=SC2206
  IFS=$',\n' read -r -a PATH_EXCLUDES <<< "${XCCOV_PATH_EXCLUDES}"
else
  PATH_EXCLUDES=("${DEFAULT_EXCLUDES[@]}")
fi

PATH_FILTERS_JSON="$(printf '%s\n' "${PATH_FILTERS[@]}" | python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
PATH_EXCLUDES_JSON="$(printf '%s\n' "${PATH_EXCLUDES[@]+"${PATH_EXCLUDES[@]}"}" | python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
export JSON_PATH MIN_PERCENT PATH_FILTERS_JSON PATH_EXCLUDES_JSON

python3 <<'PY'
import json
import os
import sys

json_path = os.environ["JSON_PATH"]
min_percent = float(os.environ["MIN_PERCENT"])
filters = json.loads(os.environ["PATH_FILTERS_JSON"])
excludes = json.loads(os.environ["PATH_EXCLUDES_JSON"])

with open(json_path, "r", encoding="utf-8") as f:
    report = json.load(f)

targets = report.get("targets") or []
# Prefer the FFmpeg-free Networking CI framework/host when present; otherwise
# the main Prairie.app product PrairieTests loads via TEST_HOST.
def is_product(t):
    name = str(t.get("name", ""))
    return (
        (name.endswith(".app") or name.endswith(".framework"))
        and "Prairie" in name
        and "Tests" not in name
    )

product_targets = [t for t in targets if is_product(t)]
if not product_targets:
    product_targets = [
        t for t in targets
        if str(t.get("name", "")).endswith(".app")
        or str(t.get("name", "")).endswith(".framework")
    ]
if not product_targets:
    print("error: no .app/.framework target found in xccov report", file=sys.stderr)
    sys.exit(1)

networking_hosts = [
    t for t in product_targets
    if "NetworkingHost" in str(t.get("name", ""))
]
if networking_hosts:
    target = max(networking_hosts, key=lambda t: int(t.get("executableLines") or 0))
else:
    target = max(product_targets, key=lambda t: int(t.get("executableLines") or 0))
target_name = target.get("name", "<unknown>")
overall_exec = int(target.get("executableLines") or 0)
overall_cov = int(target.get("coveredLines") or 0)
overall_pct = (100.0 * overall_cov / overall_exec) if overall_exec else 0.0

scoped_exec = 0
scoped_cov = 0
matched_files = 0
excluded_files = 0
for entry in target.get("files") or []:
    path = entry.get("path") or entry.get("name") or ""
    if not any(substr in path for substr in filters):
        continue
    if any(substr in path for substr in excludes):
        excluded_files += 1
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
        f"(excludes {excludes!r}) in target {target_name!r}",
        file=sys.stderr,
    )
    sys.exit(1)

scoped_pct = 100.0 * scoped_cov / scoped_exec

print(f"target:            {target_name}")
print(f"overall lines:     {overall_cov}/{overall_exec} ({overall_pct:.2f}%)")
print(f"path filters:      {filters}")
print(f"path excludes:     {excludes}")
print(f"matched files:     {matched_files}")
print(f"excluded files:    {excluded_files}")
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
