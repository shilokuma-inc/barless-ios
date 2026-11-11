import CoreGraphics
import DeviceCatalog

/// 描くときの色。値は Simulator と実機の画像から測ったもの（docs/verification.md）。
///
/// 色は sRGB で指定する。描き込み先の色空間（実機の画像は Display P3）への変換は Core Graphics に任せる。
struct Palette {
    let appearance: ContentAppearance
    let generation: OSGeneration

    /// 文字・アイコンの色（黒か白）
    func content(alpha: CGFloat = 1) -> CGColor {
        let value: CGFloat = appearance == .darkContent ? 0 : 1
        return CGColor(srgbRed: value, green: value, blue: value, alpha: alpha)
    }

    /// 電波・Wi-Fi の、立っていない棒の濃さ
    var inactiveAlpha: CGFloat {
        generation == .iOS27 ? 0.25 : 0.20
    }

    /// 電池の枠の濃さ（iOS 18〜26）
    let batteryOutlineAlpha: CGFloat = 0.40

    /// 電池の右端の突起の濃さ（iOS 18〜26）
    let batteryNubAlpha: CGFloat = 0.50

    /// 電池の空いている部分と、充電中のマークの濃さ（iOS 27 のカプセル形）。明るい背景では黒の 30%、暗い背景では白の 50%
    var batteryTrackAlpha: CGFloat {
        appearance == .darkContent ? 0.30 : 0.50
    }

    var green: CGColor { CGColor(srgbRed: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1) }

    var yellow: CGColor { CGColor(srgbRed: 255 / 255, green: 204 / 255, blue: 0 / 255, alpha: 1) }

    var red: CGColor {
        generation == .iOS27
            ? CGColor(srgbRed: 255 / 255, green: 56 / 255, blue: 60 / 255, alpha: 1)
            : CGColor(srgbRed: 255 / 255, green: 59 / 255, blue: 48 / 255, alpha: 1)
    }

    /// 電池の残量の部分の色
    func batteryLevel(_ battery: BatterySpec) -> CGColor {
        switch battery.state {
        case .charging: green
        case .lowPower: yellow
        case .normal: battery.level <= BatterySpec.lowLevelThreshold ? red : content()
        }
    }
}
