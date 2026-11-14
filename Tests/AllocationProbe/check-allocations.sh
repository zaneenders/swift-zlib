#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
platform=$(uname -s)
[[ $platform == Linux || $platform == Darwin ]] || { echo 'Requires Linux/glibc or macOS.' >&2; exit 1; }
mkdir -p .build
probe_directory=$(mktemp -d "$PWD/.build/allocation-probe.XXXXXX")
trap 'rm -rf "$probe_directory"' EXIT
arguments=(-c release)
if [[ $platform == Linux ]]; then
  # The existing C interoperability tests import zlib; Linux needs a module map.
  echo '#include <zlib.h>' > "$probe_directory/shim.h"
  cat > "$probe_directory/module.modulemap" <<'MAP'
module zlib [system] {
  header "shim.h"
  link "z"
  export *
}
MAP
  arguments+=(-Xcc "-fmodule-map-file=$probe_directory/module.modulemap")
fi
swift test "${arguments[@]}"
products=$(swift build -c release --show-bin-path)
if [[ $platform == Linux ]]; then
  cc -std=c11 -O2 -Wall -Wextra -Werror -shared -fPIC Tests/AllocationProbe/AllocationProbe.c -o "$probe_directory/probe.so"
  env SWIFT_ZLIB_ALLOCATIONS=1 LD_PRELOAD="$probe_directory/probe.so" \
    "$products/ZlibTests-test-runner" --testing-library swift-testing \
    --filter streamingDeflaterReusesWorkingStorageWithoutAllocations
else
  cc -std=c11 -O2 -Wall -Wextra -Werror -dynamiclib Tests/AllocationProbe/AllocationProbe.c -o "$probe_directory/probe.dylib"
  runtime=$(swiftc -print-target-info | plutil -extract paths.runtimeResourcePath raw -o - -)
  helper="$runtime/../../libexec/swift/pm/swiftpm-testing-helper"
  platform_developer="$(xcrun --show-sdk-platform-path)/Developer"
  env SWIFT_ZLIB_ALLOCATIONS=1 DYLD_INSERT_LIBRARIES="$probe_directory/probe.dylib" \
    DYLD_FRAMEWORK_PATH="$platform_developer/Library/Frameworks" \
    DYLD_LIBRARY_PATH="$runtime/macosx:$runtime/macosx/testing:$platform_developer/usr/lib" \
    "$helper" --test-bundle-path "$products/ZlibTests.xctest/Contents/MacOS/ZlibTests" \
    --testing-library swift-testing --filter streamingDeflaterReusesWorkingStorageWithoutAllocations
fi
