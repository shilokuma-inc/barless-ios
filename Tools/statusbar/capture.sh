#!/bin/zsh
# 使い方: CAP_OUT=<出力ディレクトリ> capture.sh <devicetype の末尾> <runtime の末尾 (例: iOS-27-0)>
# 一時的な Simulator を作り、ステータスバーを上書きして設定アプリのスクショを撮り、Simulator を消す。
dt="$1"; rt="$2"; out="${CAP_OUT:?}"
name="KiresukuProbe-$dt-$rt"
udid=$(xcrun simctl create "$name" "com.apple.CoreSimulator.SimDeviceType.$dt" "com.apple.CoreSimulator.SimRuntime.$rt" 2>/dev/null) || { echo "SKIP $dt $rt (作成不可)"; exit 0; }
trap 'xcrun simctl shutdown $udid >/dev/null 2>&1; xcrun simctl delete $udid >/dev/null 2>&1' EXIT
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || { echo "FAIL boot $dt $rt"; exit 0; }
shot() { # $1=ラベル
  sleep 3; xcrun simctl io "$udid" screenshot "$out/${dt}__${rt}__$1.png" >/dev/null 2>&1 || echo "FAIL shot $dt $rt $1"
}
xcrun simctl ui "$udid" appearance light
xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --dataNetwork wifi --wifiMode active --wifiBars 3 --operatorName "Carrier"
xcrun simctl launch "$udid" com.apple.Preferences >/dev/null 2>&1; sleep 6
shot light-full
xcrun simctl status_bar "$udid" override --time "23:58" --batteryState discharging --batteryLevel 12 --cellularMode active --cellularBars 1 --dataNetwork 5g --wifiMode failed --wifiBars 0 --operatorName "Carrier"
shot light-low
xcrun simctl ui "$udid" appearance dark
xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --dataNetwork wifi --wifiMode active --wifiBars 3 --operatorName "Carrier"
shot dark-full
xcrun simctl terminate "$udid" com.apple.Preferences >/dev/null 2>&1; sleep 2
shot dark-home
echo "OK $dt $rt"
