#!/usr/bin/env bash
# Resolve the TestFlight marketing version from a CI event.
#
# Usage: resolve-marketing-version.sh <event_name> <ref_name> <dispatch_input>
#   workflow_dispatch -> echoes <dispatch_input> verbatim
#   anything else     -> strips leading 'v' and any '-<suffix>' from <ref_name>
#                        (v1.4.0 -> 1.4.0 ; v1.4.0-beta.2 -> 1.4.0)
set -euo pipefail

event_name="${1:-}"
ref_name="${2:-}"
dispatch_input="${3:-}"

if [[ "$event_name" == "workflow_dispatch" ]]; then
  version="$dispatch_input"
else
  version="${ref_name#v}"     # strip leading v
  version="${version%%-*}"    # strip -beta.N / -rc.N suffix
fi

if [[ -z "$version" ]]; then
  echo "resolve-marketing-version: could not resolve a version from " \
       "event='${event_name}' ref='${ref_name}' input='${dispatch_input}'" >&2
  exit 1
fi

echo "$version"
