#!/usr/bin/env bash
# Runs the Flutter test suite with its build artifacts on the project disk.
#
# `/tmp` on the development machine is a 437 MB tmpfs. A full run needs roughly
# 300 MB there (dart_test.kernel.* + flutter_tools.*), so when a previous run is
# interrupted the next one dies at compile time with
#   FileSystemException: writeFrom failed ... No space left on device
# even though the code is fine. Pointing TMPDIR at build/tmp avoids that.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tmp
export TMPDIR="$PWD/build/tmp"
exec flutter test "$@"
