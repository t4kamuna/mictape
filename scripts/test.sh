#!/bin/sh
# Runs the test suite. With only the Command Line Tools installed (no Xcode),
# SwiftPM does not find the Testing framework on its own, so point it there.
# The Testing+Foundation cross-import overlay ships without its module there,
# so cross-import overlays are turned off.
set -eu
cd "$(dirname "$0")/.."

dev="$(xcode-select -p)"
case "$dev" in
*/CommandLineTools)
	fw="$dev/Library/Developer/Frameworks"
	exec swift test -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xswiftc -F -Xswiftc "$fw" -Xlinker -F -Xlinker "$fw" -Xlinker -rpath -Xlinker "$fw" "$@"
	;;
*)
	exec swift test "$@"
	;;
esac
