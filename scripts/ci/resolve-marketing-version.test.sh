#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="${here}/resolve-marketing-version.sh"

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${desc}: expected '${expected}', got '${actual}'" >&2
    exit 1
  fi
  echo "ok: ${desc}"
}

assert_eq "final tag"      "1.4.0" "$("$script" push          v1.4.0        "")"
assert_eq "prerelease tag" "1.4.0" "$("$script" push          v1.4.0-beta.2 "")"
assert_eq "rc tag"         "2.0.0" "$("$script" push          v2.0.0-rc.1   "")"
assert_eq "dispatch input" "1.4.0" "$("$script" workflow_dispatch ""        1.4.0)"

if "$script" push "" "" 2>/dev/null; then
  echo "FAIL: empty result should exit non-zero" >&2
  exit 1
fi
echo "ok: empty result rejected"
echo "ALL PASS"
