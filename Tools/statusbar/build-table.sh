#!/bin/zsh
# 撮った画像を測り直して、docs/device-table.json と docs/device-table.md を作る。
# 使い方: build-table.sh [撮った画像のディレクトリ（省略時は Tools/statusbar/simshots）]
# 測定や表の生成に失敗したときは、docs の今のファイルを変えない（一時ファイルに作り、全部できてから置き換える）。
here="${0:A:h}"; root="${here:h:h}"; shots="${1:-$here/simshots}"
[[ -d "$shots" ]] || { echo "画像のディレクトリがありません: $shots" >&2; exit 1; }
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
python3 "$here/analyze.py" "$shots" > "$tmp/device-table.json" \
  || { echo "測定に失敗しました（docs/device-table.* は変えていません）" >&2; exit 1; }
{ cat "$here/device-table.head.md" && python3 "$here/make-table.py" "$tmp/device-table.json"; } > "$tmp/device-table.md" \
  || { echo "表の生成に失敗しました（docs/device-table.* は変えていません）" >&2; exit 1; }
mv "$tmp/device-table.json" "$root/docs/device-table.json" && mv "$tmp/device-table.md" "$root/docs/device-table.md"
