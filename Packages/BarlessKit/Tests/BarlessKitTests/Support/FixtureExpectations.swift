import BarlessTestSupport
import DeviceCatalog
import ImageIOKit
import StatusBarRenderer

extension Fixture {
    /// この画像を撮った機種・iOS に対応する配置（カタログの実測の元から引く）
    func expectedLayout(in catalog: DeviceCatalog) -> StatusBarLayout? {
        catalog.layouts.first { $0.sources.contains("\(device)__\(runtime)") }
    }

    var contentAppearance: ContentAppearance {
        appearance == "light" ? .darkContent : .lightContent
    }

    /// 画像に写っているステータスバーの中身（撮影時に `simctl status_bar override` で指定した値）
    var spec: StatusBarSpec {
        StatusBarSpec(
            time: time,
            cellularBars: cellularBars,
            wifiBars: wifiBars,
            battery: batteryLevel.map { BatterySpec(level: Double($0) / 100, state: showsChargingBolt ? .charging : .normal) }
        )
    }

    /// 「充電済み」を指定した画像のうち、iOS 26 と 27 の Simulator は緑 + 稲妻で表示する（iOS 18.6 は黒い満タン）
    private var showsChargingBolt: Bool {
        batteryState == "charged" && runtime != "iOS-18-6"
    }
}
