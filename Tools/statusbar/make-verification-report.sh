#!/bin/zsh
# 検証結果（docs/verification/results.md と docs/verification/images/）を作り直す。
# BarlessKit のテスト（VerificationReportTests）を macOS の上で流すだけなので、Simulator は要らない。
# 使い方: make-verification-report.sh [出力先（省略時は docs/verification）]
here="${0:A:h}"; root="${here:h:h}"; out="${1:-$root/docs/verification}"
mkdir -p "$out" && out="${out:A}" || exit 1
rm -rf "$out/images"
cd "$root/Packages/BarlessKit" && BARLESS_REPORT_DIR="$out" swift test --filter VerificationReportTests
