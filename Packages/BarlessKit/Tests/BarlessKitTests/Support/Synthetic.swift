import CoreGraphics
import DeviceCatalog
import Foundation
import ImageIO
import ImageIOKit
import StatusBarRenderer
import UniformTypeIdentifiers

/// 検証用に作る背景
enum SyntheticBackground: String, CaseIterable {
    /// 上から下へ直線的に変わる
    case vertical
    /// 左から右へ直線的に変わる
    case horizontal
    /// 斜めに直線的に変わる
    case diagonal
    /// 円形に広がる（直線的ではない）
    case radial

    /// - Parameter isLight: 明るい背景（黒い文字用）か、暗い背景（白い文字用）か
    func make(width: Int, height: Int, isLight: Bool) -> Bitmap {
        let from = isLight ? (red: 255.0, green: 236.0, blue: 210.0) : (red: 16.0, green: 28.0, blue: 72.0)
        let to = isLight ? (red: 250.0, green: 170.0, blue: 150.0) : (red: 84.0, green: 20.0, blue: 96.0)
        var bitmap = Bitmap(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let ratio = min(1, max(0, position(x: Double(x) / Double(width), y: Double(y) / Double(height))))
                bitmap[x, y] = RGB(
                    red: UInt8((from.red + (to.red - from.red) * ratio).rounded()),
                    green: UInt8((from.green + (to.green - from.green) * ratio).rounded()),
                    blue: UInt8((from.blue + (to.blue - from.blue) * ratio).rounded())
                )
            }
        }
        return bitmap
    }

    /// 0〜1 の位置（x・y は幅・高さに対する割合）から、色の混ぜ具合を出す
    private func position(x: Double, y: Double) -> Double {
        switch self {
        case .vertical: y
        case .horizontal: x
        case .diagonal: (x + y) / 2
        case .radial: ((x - 0.3) * (x - 0.3) * 4 + (y - 1.2) * (y - 1.2)).squareRoot() / 1.6
        }
    }
}

/// 検証用に作る「輪郭のある背景」。斜めの線を境に 2 つの色に分かれる（空と建物の縁、のような背景の代わり）
struct SyntheticEdge {
    /// 境の線が通る点（px）
    let throughX: Int
    let throughY: Int
    /// 1 行下がるごとに、境が右へ動く幅（px）
    var slope = 0.6

    /// - Parameter isLight: 明るい背景（黒い文字用）か、暗い背景（白い文字用）か
    func make(width: Int, height: Int, isLight: Bool) -> Bitmap {
        let base = isLight ? RGB(red: 232, green: 236, blue: 240) : RGB(red: 18, green: 24, blue: 44)
        let other = isLight ? RGB(red: 150, green: 132, blue: 120) : RGB(red: 150, green: 140, blue: 130)
        var bitmap = Bitmap(width: width, height: height, fill: base)
        for y in 0..<height {
            let boundary = Int((Double(throughX) + slope * Double(y - throughY)).rounded())
            for x in min(width, max(0, boundary))..<width {
                bitmap[x, y] = other
            }
        }
        return bitmap
    }
}

/// 輪郭を通す場所
enum EdgePlacement: String, CaseIterable {
    /// 電池の後ろを斜めに通る（消すと、輪郭がぼやけた跡が残る）
    case behindBattery
    /// 電池の後ろをまっすぐ縦に通る（上下の基準の行で色が同じなので、インクとしては拾えない）
    case verticalBehindBattery
    /// 文字もアイコンも無い所（消去とは関係ないので、そのまま残るべき）
    case awayFromInk

    /// その配置で、輪郭が通る点（帯の高さの中央）
    func edge(for layout: StatusBarLayout, timeText: String) -> SyntheticEdge {
        let middleY = (layout.inkTop + layout.inkBottom) / 2
        switch self {
        case .behindBattery:
            return SyntheticEdge(throughX: Int(layout.battery.midX), throughY: middleY)
        case .verticalBehindBattery:
            return SyntheticEdge(throughX: Int(layout.battery.midX), throughY: middleY, slope: 0)
        case .awayFromInk:
            // 文字・アイコンのあいだの、いちばん広いすき間の中央
            let time = TimeTypography(layout: layout).inkRect(for: timeText)
            let rects = [time, layout.cellular, layout.wifi, layout.battery, layout.carrier].compactMap { $0 }.sorted { $0.x < $1.x }
            var widest = (x: layout.pixelWidth / 2, width: 0)
            for (left, right) in zip(rects, rects.dropFirst()) where right.x - left.maxX > widest.width {
                widest = ((left.maxX + right.x) / 2, right.x - left.maxX)
            }
            return SyntheticEdge(throughX: widest.x, throughY: middleY)
        }
    }
}

enum Synthetic {
    /// JPEG で保存し直す（SNS やメッセージアプリを通って再圧縮された画像の代わり）。大きさは変えない
    static func recompressed(_ bitmap: Bitmap, quality: Double) throws -> Bitmap {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageCodecError.cannotEncode
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, try bitmap.makeCGImage(), options)
        guard CGImageDestinationFinalize(destination) else { throw ImageCodecError.cannotEncode }
        return try Bitmap(cgImage: ImageDecoder.decode(data: output as Data))
    }

    /// 背景の色のまわりで、画素ごとに少しずつ色が揺れる画像（写真や模様の代わり）
    static func noise(width: Int, height: Int, base: RGB) -> Bitmap {
        var bitmap = Bitmap(width: width, height: height, fill: base)
        var state: UInt32 = 20_261_112
        func next() -> Int {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Int(state >> 24) % 17 - 8
        }
        func shift(_ value: UInt8) -> UInt8 {
            UInt8(min(255, max(0, Int(value) + next())))
        }
        for y in 0..<height {
            for x in 0..<width {
                bitmap[x, y] = RGB(red: shift(base.red), green: shift(base.green), blue: shift(base.blue))
            }
        }
        return bitmap
    }

    /// 単色の背景で撮った画像のインク（文字・アイコン）を、別の背景に移す。
    /// 画素ごとに「撮った画像と、その背景の色との差」をそのまま新しい背景に足す
    static func transplantInk(from shot: Bitmap, onto background: Bitmap, scale: Int) -> Bitmap {
        let base = shot[shot.width / 2, 4 * scale]
        var result = background
        let corner = 4 * scale
        for y in 0..<min(shot.height, background.height) {
            for x in 0..<min(shot.width, background.width) {
                // Simulator の画像は四隅が黒く欠けているので、そこは移さない
                if y < corner && (x < corner || x >= shot.width - corner) { continue }
                let pixel = shot[x, y]
                guard pixel != base else { continue }
                let under = background[x, y]
                func shift(_ value: UInt8, _ from: UInt8, _ to: UInt8) -> UInt8 {
                    UInt8(min(255, max(0, Int(value) + Int(to) - Int(from))))
                }
                result[x, y] = RGB(
                    red: shift(under.red, base.red, pixel.red),
                    green: shift(under.green, base.green, pixel.green),
                    blue: shift(under.blue, base.blue, pixel.blue)
                )
            }
        }
        return result
    }
}
