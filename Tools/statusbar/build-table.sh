#!/bin/zsh
# 撮った画像を測り直して、docs/device-table.json と docs/device-table.md を作る。
# 使い方: build-table.sh [撮った画像のディレクトリ（省略時は Tools/statusbar/simshots）]
here="${0:A:h}"; root="${here:h:h}"; shots="${1:-$here/simshots}"
[[ -d "$shots" ]] || { echo "画像のディレクトリがありません: $shots" >&2; exit 1; }
python3 "$here/analyze.py" "$shots" > "$root/docs/device-table.json" \
  && { cat "$here/device-table.head.md"; python3 "$here/make-table.py" "$root/docs/device-table.json"; } > "$root/docs/device-table.md"
