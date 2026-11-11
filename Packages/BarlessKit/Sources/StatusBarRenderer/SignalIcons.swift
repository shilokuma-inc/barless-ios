import CoreGraphics
import DeviceCatalog
import Foundation

extension PixelRect {
    /// 実測の矩形（インクが載った画素の範囲）から、輪郭の位置の見込みを出す。
    /// アンチエイリアスで外側に約 0.4px ずつ広がって測られているので、その分だけ縮める
    var outline: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
            .insetBy(dx: Self.antialiasInset, dy: Self.antialiasInset)
    }

    static let antialiasInset: CGFloat = 0.4
}

extension CGContext {
    /// `body` で描いたものを 1 枚の層にまとめ、全体を `alpha` の濃さで重ねる
    func withLayer(alpha: CGFloat, _ body: () -> Void) {
        saveGState()
        setAlpha(alpha)
        beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        endTransparencyLayer()
        restoreGState()
    }
}

/// 電波（棒 4 本）。SF Symbols は使わず、実測した棒の位置にそのまま描く（docs/spec.md §5-3）
struct CellularIcon {
    let layout: StatusBarLayout

    /// 棒 1 本の形。iOS 18〜26 は角を少し丸めた長方形、iOS 27 は上下が半円
    func barPath(_ index: Int) -> CGPath {
        let rect = layout.cellularBars[index].outline
        let radius = min(layout.generation == .iOS27 ? rect.width / 2 : rect.width / 3, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    func draw(activeBars: Int, palette: Palette, in context: CGContext) {
        for index in layout.cellularBars.indices {
            context.addPath(barPath(index))
            context.setFillColor(palette.content(alpha: index < activeBars ? 1 : palette.inactiveAlpha))
            context.fillPath()
        }
    }
}

/// Wi-Fi（扇形の 3 つの帯）。扇の要（かなめ）は実測の矩形の下端中央にある
struct WiFiIcon {
    let layout: StatusBarLayout

    private var tip: CGPoint {
        let rect = layout.wifi.outline
        return CGPoint(x: rect.midX, y: rect.maxY)
    }

    /// 帯の外側と内側の半径（要からの距離）。0 番目がいちばん外
    private func radii(_ index: Int) -> (outer: CGFloat, inner: CGFloat) {
        let band = layout.wifiBands[index]
        let outer = tip.y - (CGFloat(band.top) + PixelRect.antialiasInset)
        let inner = tip.y - (CGFloat(band.bottom) - PixelRect.antialiasInset)
        return (outer, max(0, inner))
    }

    /// 扇の開きの半分（ラジアン）。いちばん外の帯の幅が、実測の矩形の幅に合うように決める
    private var halfAngle: CGFloat {
        let halfWidth = layout.wifi.outline.width / 2
        let outermost = radii(0)
        if layout.generation == .iOS27 {
            // 端が丸い（線の太さの半分だけ外に出る）ので、その分を引いてから中心線の半径で割る
            let thickness = outermost.outer - outermost.inner
            return asin(min(1, max(0, (halfWidth - thickness / 2) / ((outermost.outer + outermost.inner) / 2))))
        }
        return asin(min(1, max(0, halfWidth / outermost.outer)))
    }

    /// 要から半径 `radius`・上向きから `angle`（右回りが正）の点
    private func point(radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: tip.x + radius * sin(angle), y: tip.y - radius * cos(angle))
    }

    /// 半径 `radius` の弧を `-limit`〜`limit` で折れ線にする
    private func arc(radius: CGFloat, limit: CGFloat, reversed: Bool = false) -> [CGPoint] {
        let steps = 24
        let points = (0...steps).map { point(radius: radius, angle: -limit + 2 * limit * CGFloat($0) / CGFloat(steps)) }
        return reversed ? points.reversed() : points
    }

    /// 点を順につないで閉じた多角形（`addLines(between:)` は呼ぶたびに別の図形を始めるので、1 つにまとめてから渡す）
    private static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    func draw(activeBars: Int, palette: Palette, in context: CGContext) {
        for index in layout.wifiBands.indices {
            // 帯は外から 3 本目・2 本目・1 本目（根元）の順
            let isActive = layout.wifiBands.count - index <= activeBars
            let color = palette.content()
            // 線と塗りが重なるところで濃くならないよう、不透明で描いてからまとめて薄くする
            context.withLayer(alpha: isActive ? 1 : palette.inactiveAlpha) {
                if layout.generation != .iOS27 {
                    drawSector(index, color: color, in: context)
                } else if index == layout.wifiBands.count - 1 {
                    drawRoundedRoot(index, color: color, in: context)
                } else {
                    drawRoundedArc(index, color: color, in: context)
                }
            }
        }
    }

    /// iOS 18〜26: 端をまっすぐ切った扇形の帯（根元は要までつながる）
    private func drawSector(_ index: Int, color: CGColor, in context: CGContext) {
        let (outer, inner) = radii(index)
        let inside = inner > 0 ? arc(radius: inner, limit: halfAngle, reversed: true) : [tip]
        context.addPath(Self.polygon(arc(radius: outer, limit: halfAngle) + inside))
        context.setFillColor(color)
        context.fillPath()
    }

    /// iOS 27: 端が丸い弧（太い線として描く）
    private func drawRoundedArc(_ index: Int, color: CGColor, in context: CGContext) {
        let (outer, inner) = radii(index)
        let path = CGMutablePath()
        path.addLines(between: arc(radius: (outer + inner) / 2, limit: halfAngle))
        context.addPath(path)
        context.setStrokeColor(color)
        context.setLineWidth(outer - inner)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    /// iOS 27: 角を丸めた扇形（内側に縮めた扇形を、丸い角の線で縁取って作る）
    private func drawRoundedRoot(_ index: Int, color: CGColor, in context: CGContext) {
        let outer = radii(index).outer
        let corner = outer * 0.14
        let innerRadius = outer - corner
        let limit = halfAngle - asin(min(1, corner / innerRadius))
        let apex = CGPoint(x: tip.x, y: tip.y - corner / sin(halfAngle))
        context.addPath(Self.polygon(arc(radius: innerRadius, limit: limit) + [apex]))
        context.setFillColor(color)
        context.setStrokeColor(color)
        context.setLineWidth(corner * 2)
        context.setLineJoin(.round)
        context.drawPath(using: .fillStroke)
    }
}
