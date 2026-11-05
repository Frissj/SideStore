#!/bin/bash
set -euo pipefail
test_build=$(mktemp -d)
trap 'rm -rf "$test_build"' EXIT
common=Dependencies/minimuxer/Common
swiftc -swift-version 5 -emit-module -emit-library -module-name MinimuxerCommon \
  "$common/ConcurrencyUtils.swift" "$common/MinimuxerConstants.swift" \
  "$common/PairingProtocol.swift" "$common/PairingFile.swift" \
  -emit-module-path "$test_build/MinimuxerCommon.swiftmodule" -o "$test_build/libMinimuxerCommon.dylib"
swiftc -swift-version 5 -I "$test_build" -L "$test_build" -lMinimuxerCommon \
  -Xlinker -rpath -Xlinker "$test_build" \
  scripts/ci/pairing-import-tests/Support.swift \
  SideStore/Core/Pairing/PairingFileManager.swift \
  scripts/ci/pairing-import-tests/main.swift -o "$test_build/pairing-import-tests"
PAIRING_TEST_DIR="$test_build/records" "$test_build/pairing-import-tests"
