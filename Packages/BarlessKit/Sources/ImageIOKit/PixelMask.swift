import Foundation

/// 画像の一部（矩形）を覆う 2 値のマスク。`true` の画素が対象（消す・インクがある など）
public struct PixelMask: Sendable, Equatable {
    /// 画像の中でマスクが覆う範囲の左上（px）
    public let originX: Int
    public let originY: Int
    public let width: Int
    public let height: Int
    public var bits: [Bool] { storage }
    @usableFromInline var storage: [Bool]

    public init(originX: Int, originY: Int, width: Int, height: Int) {
        precondition(width > 0 && height > 0, "大きさは 1 以上にする")
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
        self.storage = [Bool](repeating: false, count: width * height)
    }

    /// 画像の座標で読み書きする。マスクの範囲の外は常に `false`（書き込みは無視する）
    @inlinable
    public subscript(x: Int, y: Int) -> Bool {
        get {
            let localX = x - originX
            let localY = y - originY
            guard localX >= 0, localY >= 0, localX < width, localY < height else { return false }
            return storage[localY * width + localX]
        }
        set {
            let localX = x - originX
            let localY = y - originY
            guard localX >= 0, localY >= 0, localX < width, localY < height else { return }
            storage[localY * width + localX] = newValue
        }
    }

    public var count: Int {
        storage.reduce(0) { $0 + ($1 ? 1 : 0) }
    }

    public var isEmpty: Bool {
        !storage.contains(true)
    }

    /// 上下左右に `radius` px 広げる（正方形の範囲。マスクの範囲の外には広がらない）
    public func dilated(by radius: Int) -> PixelMask {
        guard radius > 0 else { return self }
        // 横に広げてから縦に広げる
        var horizontal = self
        for y in 0..<height {
            for x in 0..<width where storage[y * width + x] {
                for target in max(0, x - radius)...min(width - 1, x + radius) {
                    horizontal.storage[y * width + target] = true
                }
            }
        }
        var result = horizontal
        for y in 0..<height {
            for x in 0..<width where horizontal.storage[y * width + x] {
                for target in max(0, y - radius)...min(height - 1, y + radius) {
                    result.storage[target * width + x] = true
                }
            }
        }
        return result
    }
}
