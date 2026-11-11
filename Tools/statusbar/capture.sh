#!/bin/zsh
# 使い方: CAP_OUT=<出力ディレクトリ> capture.sh <devicetype の末尾> <runtime の末尾 (例: iOS-27-0)>
# 一時的な Simulator を作り、ステータスバーを上書きして設定アプリのスクショを撮り、Simulator を消す。
# 4 枚のうち 1 枚でも撮れなかった・表示を固定できなかったときは、撮れた分も消して 0 以外で終わる（撮り直せるように）。
dt="$1"; rt="$2"; out="${CAP_OUT:?}"
name="KiresukuProbe-$dt-$rt"
udid=$(xcrun simctl create "$name" "com.apple.CoreSimulator.SimDeviceType.$dt" "com.apple.CoreSimulator.SimRuntime.$rt" 2>/dev/null) || { echo "SKIP $dt $rt (作成不可)"; exit 0; }
trap 'xcrun simctl shutdown $udid >/dev/null 2>&1; xcrun simctl delete $udid >/dev/null 2>&1' EXIT
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || { echo "FAIL boot $dt $rt"; exit 1; }
failed=0
run() { # 失敗したら覚えておく。$1=何をしているか、残り=コマンド
  local what="$1"; shift
  "$@" >/dev/null 2>&1 || { echo "FAIL $what $dt $rt"; failed=1; }
}
shot() { # $1=ラベル
  sleep 3; run "shot $1" xcrun simctl io "$udid" screenshot "$out/${dt}__${rt}__$1.png"
}
run "appearance light" xcrun simctl ui "$udid" appearance light
run "override full" xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --dataNetwork wifi --wifiMode active --wifiBars 3 --operatorName "Carrier"
run "launch Settings" xcrun simctl launch "$udid" com.apple.Preferences; sleep 6
shot light-full
run "override low" xcrun simctl status_bar "$udid" override --time "23:58" --batteryState discharging --batteryLevel 12 --cellularMode active --cellularBars 1 --dataNetwork 5g --wifiMode failed --wifiBars 0 --operatorName "Carrier"
shot light-low
run "appearance dark" xcrun simctl ui "$udid" appearance dark
run "override full" xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --dataNetwork wifi --wifiMode active --wifiBars 3 --operatorName "Carrier"
shot dark-full
xcrun simctl terminate "$udid" com.apple.Preferences >/dev/null 2>&1; sleep 2
shot dark-home
if (( failed )); then
  rm -f "$out/${dt}__${rt}__"{light-full,light-low,dark-full,dark-home}.png
  echo "FAIL $dt $rt（撮れた分も消しました。もう一度流すと撮り直します）"
  exit 1
fi
echo "OK $dt $rt"
