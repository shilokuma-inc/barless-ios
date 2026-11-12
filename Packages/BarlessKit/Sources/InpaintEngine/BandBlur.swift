import ImageIOKit

/// 画像の上端の帯を、文字とアイコンが読めなくなる強さでぼかす。
///
/// 背景が写真や模様で、まわりから埋めると跡が残るときに使う。帯の中の画素だけを読むので、
/// 帯の下の画像には左右されない（上端だけを切り出した画像でも、全体でも、同じ結果になる）
public struct BandBlur: Sendable {
    /// 平均をとる回数。3 回くり返すと、ガウスぼかしに近い、なめらかな結果になる
    static let passes = 3

    public init() {}

    /// ぼかしの半径（px）。帯の高さの 1/3 にする。時刻の文字の高さ（帯の 1/4 ほど）より大きいので、形が残らない
    public static func radius(forBandHeight bandHeight: Int) -> Int {
        max(2, bandHeight / 3)
    }

    /// 上端から `bandHeight` 行をぼかした画像を返す。帯の下は変えない
    public func blur(_ bitmap: Bitmap, bandHeight: Int) -> Bitmap {
        let height = min(bandHeight, bitmap.height)
        let width = bitmap.width
        guard height > 0 else { return bitmap }
        let radius = Self.radius(forBandHeight: height)
        var channels = [[Int]](repeating: [Int](repeating: 0, count: width * height), count: 3)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = bitmap[x, y]
                channels[0][y * width + x] = Int(pixel.red)
                channels[1][y * width + x] = Int(pixel.green)
                channels[2][y * width + x] = Int(pixel.blue)
            }
        }
        for index in channels.indices {
            for _ in 0..<Self.passes {
                channels[index] = Self.averaged(channels[index], width: width, height: height, radius: radius, alongRows: true)
                channels[index] = Self.averaged(channels[index], width: width, height: height, radius: radius, alongRows: false)
            }
        }
        var result = bitmap
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * width + x
                result[x, y] = RGB(
                    red: UInt8(clamping: channels[0][offset]),
                    green: UInt8(clamping: channels[1][offset]),
                    blue: UInt8(clamping: channels[2][offset])
                )
            }
        }
        return result
    }

    /// 前後 `radius` 画素の平均に置き換える（横か縦の 1 方向）。端の外は、端の画素が続いているとみなす
    static func averaged(_ values: [Int], width: Int, height: Int, radius: Int, alongRows: Bool) -> [Int] {
        let lineLength = alongRows ? width : height
        let lineCount = alongRows ? height : width
        let window = 2 * radius + 1
        var result = values
        var prefix = [Int](repeating: 0, count: lineLength + 1)
        for line in 0..<lineCount {
            func index(_ position: Int) -> Int {
                alongRows ? line * width + position : position * width + line
            }
            for position in 0..<lineLength {
                prefix[position + 1] = prefix[position] + values[index(position)]
            }
            let first = values[index(0)]
            let last = values[index(lineLength - 1)]
            for position in 0..<lineLength {
                let low = position - radius
                let high = position + radius
                var sum = prefix[min(high, lineLength - 1) + 1] - prefix[max(low, 0)]
                if low < 0 { sum += -low * first }
                if high > lineLength - 1 { sum += (high - lineLength + 1) * last }
                result[index(position)] = (sum + window / 2) / window
            }
        }
        return result
    }
}
