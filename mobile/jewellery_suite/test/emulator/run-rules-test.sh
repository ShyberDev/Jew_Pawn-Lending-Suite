#!/usr/bin/env bash
# Run the Firestore rules test against the emulator.
#
# `firebase emulators:exec` spawns its script with firebase-tools' bundled
# CommonJS node, which refuses to load an ES module (the v10 client SDK is ESM
# only). So the emulator is started here and the test runs with the node on
# PATH. No Firebase project, no credentials, no data: `demo-` project ids are
# always emulated.
set -uo pipefail
cd "$(dirname "$0")"

LOG="$(mktemp)"
firebase emulators:start --only firestore --project demo-jewellery-suite \
  >"$LOG" 2>&1 &
EMU=$!

cleanup() {
  kill "$EMU" 2>/dev/null
  pkill -f "cloud-fire""store-emulator" 2>/dev/null
  rm -f "$LOG" firestore-debug.log ui-debug.log
}
trap cleanup EXIT INT TERM

ready=""
for _ in $(seq 1 120); do
  if grep -q "All emulators ready" "$LOG"; then ready=1; break; fi
  if ! kill -0 "$EMU" 2>/dev/null; then break; fi
  sleep 1
done

if [ -z "$ready" ]; then
  cat "$LOG" >&2
  echo "The Firestore emulator did not become ready." >&2
  exit 1
fi

node firestore_rules.test.mjs
