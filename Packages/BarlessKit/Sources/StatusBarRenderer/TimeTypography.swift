import CoreGraphics
import CoreText
import DeviceCatalog
import Foundation
import os

#if canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
#endif

/// 時刻の文字の組み方（フォントの大きさと位置）。
///
/// カタログには「撮ったときの文字列」と「インクの矩形」しか無いので、そこから大きさと位置を求める。
/// 時刻は中央ぞろえ（文字列の送り幅の中心が機種ごとに一定）なので、別の文字列でも同じ中心に置けば位置が合う。
/// フォントはシステムフォント（SF Pro はアプリに同梱しない。docs/spec.md §5-3）。
public struct TimeTypography: Sendable, Equatable {
    /// 画素の 8% 以上が覆われていれば「インクあり」と数える（実測スクリプト analyze.py のしきい値に合わせた値）
    static let coverageThreshold: CGFloat = 0.08
    /// 輪郭の幅・高さ（px。小数）に対して、インクとして数えられる画素数が平均でどれだけ増えるか
    static let rasterInflation: CGFloat = 1 - 2 * coverageThreshold
    /// 探すフォントサイズの範囲と刻み（pt）
    static let fontSizes = stride(from: CGFloat(9), through: 26, by: 0.25)

    /// フォントの大きさ（pt）
    public let fontSize: CGFloat
    /// フォントの太さ（`UIFont.Weight` の値。semibold は 0.3）
    public let weight: CGFloat
    /// 文字列の送り幅の中心（px）
    public let centerX: CGFloat
    /// ベースライン（px。下向きが正）
    public let baselineY: CGFloat
    /// 1pt あたりの px
    public let scale: CGFloat

    public init(fontSize: CGFloat, weight: CGFloat, centerX: CGFloat, baselineY: CGFloat, scale: CGFloat) {
        self.fontSize = fontSize
        self.weight = weight
        self.centerX = centerX
        self.baselineY = baselineY
        self.scale = scale
    }

    /// 実測（文字列とインクの矩形の組）に合うように、大きさと位置を求める。
    /// 実測が複数あれば（9:41 と 23:58 など）、すべてにいちばん合う大きさを選ぶ
    public init(samples: [TimeSample], scale: Int, weight: CGFloat = TimeTypography.defaultWeight) {
        precondition(!samples.isEmpty, "実測が 1 つ以上要る")
        let scale = CGFloat(scale)
        var best = (size: CGFloat(17), error: CGFloat.greatestFiniteMagnitude)
        for size in Self.fontSizes {
            var error: CGFloat = 0
            for sample in samples {
                let bounds = TextOutline(text: sample.text, fontSize: size, weight: weight).bounds
                // 輪郭の大きさ（小数）から、インクとして数えられる画素数の見込みを出して比べる
                let widthError = bounds.width * scale + Self.rasterInflation - CGFloat(sample.ink.width)
                let heightError = bounds.height * scale + Self.rasterInflation - CGFloat(sample.ink.height)
                error += widthError * widthError + heightError * heightError
            }
            if error < best.error { best = (size, error) }
        }
        // 位置は最初の実測（カタログでは 9:41）に合わせる。「整える」でいちばんよく描く文字列をぴったり合わせるため。
        // 文字列が変わると中心は 1px ほど揺れる（docs/verification.md）ので、平均しても全体としては良くならない
        let anchor = samples[0]
        let outline = TextOutline(text: anchor.text, fontSize: best.size, weight: weight)
        let originX = CGFloat(anchor.ink.midX) - outline.bounds.midX * scale
        self.init(
            fontSize: best.size,
            weight: weight,
            centerX: originX + outline.advance / 2 * scale,
            baselineY: CGFloat(anchor.ink.midY) + outline.bounds.midY * scale,
            scale: scale
        )
    }

    /// カタログの配置から求める。当てはめは 1 回だけ行い、同じ配置の 2 回目からは覚えておいた結果を返す
    public init(layout: StatusBarLayout, weight: CGFloat = TimeTypography.defaultWeight) {
        let key = CacheKey(layout: layout, weight: weight)
        if let cached = Self.cache.withLock({ $0[key] }) {
            self = cached
            return
        }
        // カタログの配置には必ず 1 つ以上の実測がある（無ければ 9:41 を帯の左端に置いたものとして扱う）
        let fallback = TimeSample(text: "9:41", ink: PixelRect(x: 0, y: layout.inkTop, width: 1, height: layout.inkBottom - layout.inkTop))
        self.init(samples: layout.timeSamples.isEmpty ? [fallback] : layout.timeSamples, scale: layout.scale, weight: weight)
        let fitted = self
        Self.cache.withLock { $0[key] = fitted }
    }

    private struct CacheKey: Hashable {
        let layout: StatusBarLayout
        let weight: CGFloat
    }

    private static let cache = OSAllocatedUnfairLock<[CacheKey: TimeTypography]>(initialState: [:])

    /// ステータスバーの時刻の太さ（semibold）
    public static let defaultWeight: CGFloat = 0.3

    /// 文字の輪郭（px 座標・左上が原点）
    public func path(for text: String) -> CGPath {
        let outline = TextOutline(text: text, fontSize: fontSize, weight: weight)
        var transform = CGAffineTransform(translationX: centerX - outline.advance / 2 * scale, y: baselineY)
            .scaledBy(x: scale, y: -scale)
        return outline.path.copy(using: &transform) ?? outline.path
    }

    /// その文字列を描いたときにインクが載る範囲の見込み（px）
    public func inkRect(for text: String) -> PixelRect {
        let bounds = path(for: text).boundingBoxOfPath
        guard !bounds.isNull, !bounds.isEmpty else { return PixelRect(x: Int(centerX), y: Int(baselineY), width: 0, height: 0) }
        let minX = Int((bounds.minX + Self.coverageThreshold).rounded(.down))
        let minY = Int((bounds.minY + Self.coverageThreshold).rounded(.down))
        let maxX = Int((bounds.maxX - Self.coverageThreshold).rounded(.up))
        let maxY = Int((bounds.maxY - Self.coverageThreshold).rounded(.up))
        return PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// システムフォントで組んだ文字列の輪郭。原点はベースラインの左端、上向きが正、単位は pt
struct TextOutline {
    let path: CGPath
    /// 輪郭を囲む矩形
    let bounds: CGRect
    /// 文字列の送り幅
    let advance: CGFloat

    init(text: String, fontSize: CGFloat, weight: CGFloat) {
        let font = PlatformFont.systemFont(ofSize: fontSize, weight: PlatformFont.Weight(rawValue: weight)) as CTFont
        let attributes = [kCTFontAttributeName as NSAttributedString.Key: font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            // 代替フォントに置き換わった run は、その run のフォントで輪郭を取る
            let runFont = Self.font(of: run) ?? font
            for index in 0..<count {
                var transform = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                if let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[index], &transform) {
                    path.addPath(glyphPath)
                }
            }
        }
        self.path = path
        self.bounds = path.isEmpty ? .zero : path.boundingBoxOfPath
        self.advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func font(of run: CTRun) -> CTFont? {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let value = attributes[kCTFontAttributeName] as AnyObject?, CFGetTypeID(value) == CTFontGetTypeID() else {
            return nil
        }
        // 型は直前に CFGetTypeID で確かめている（CoreFoundation の型は as? で変換できない）
        return unsafeDowncast(value, to: CTFont.self)
    }
}
