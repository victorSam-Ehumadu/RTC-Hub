#!/usr/bin/env bash
# macOS / Linux twin of run.ps1 — see that file for the reasoning.
#
#   ./run.sh            live, against Supabase (needs env.json)
#   ./run.sh demo       offline UI walkthrough, no project and no keys
#
# Extra arguments are passed through to `flutter run`.

set -euo pipefail
cd "$(dirname "$0")"

mode="${1:-live}"
[ $# -gt 0 ] && shift || true

flags=()

if [ "$mode" = "demo" ]; then
  flags+=(--dart-define=DEMO=true)
  echo "DEMO mode - canned data, Supabase is never contacted."
  echo "Bypasses RLS by construction; never use it to show an access rule works."
else
  if [ ! -f env.json ]; then
    echo "env.json not found." >&2
    echo "Copy env.example.json to env.json and fill in the project URL and anon key," >&2
    echo "or run  ./run.sh demo  to browse the UI with no backend." >&2
    exit 1
  fi
  if grep -q 'your-project-id\|your-anon-key' env.json; then
    echo "env.json still holds the placeholder values from env.example.json." >&2
    echo "Ask the project owner for the real URL and anon key (never service_role)." >&2
    exit 1
  fi
  flags+=(--dart-define-from-file=env.json)
  echo "LIVE mode"
fi

echo "flutter run ${flags[*]} $*"
exec flutter run "${flags[@]}" "$@"
