#!/bin/zsh
# iOS 26 / 27 の Simulator で、機種ごとにステータスバーのスクショを撮る（3 並列）。
# 引数でランタイムを変えられる: run-26-27.sh iOS-18-6
# 出力先は CAP_OUT（省略時は Tools/statusbar/simshots。.gitignore で除外している）
here="${0:A:h}"; export CAP_OUT="${CAP_OUT:-$here/simshots}"; mkdir -p "$CAP_OUT"
if (( $# )); then runtimes=("$@"); else runtimes=(iOS-26-5 iOS-27-0); fi
types=(iPhone-18-Pro iPhone-18-Pro-Max iPhone-Air iPhone-17e iPhone-17 iPhone-16 iPhone-16-Plus iPhone-16e iPhone-15 iPhone-14-Plus iPhone-13-mini iPhone-12 iPhone-11 iPhone-11-Pro iPhone-11-Pro-Max iPhone-SE-3rd-generation iPhone-Xs iPhone-Xs-Max)
{ for t in $types; do for r in $runtimes; do [[ -f "$CAP_OUT/${t}__${r}__dark-home.png" ]] || echo "$t $r"; done; done
  [[ "${runtimes[*]}" == *27-0* && ! -f "$CAP_OUT/iPhone-Duo__iOS-27-1__dark-home.png" ]] && echo "iPhone-Duo iOS-27-1"
} | xargs -P 3 -L 1 "$here/capture.sh" 2>&1
