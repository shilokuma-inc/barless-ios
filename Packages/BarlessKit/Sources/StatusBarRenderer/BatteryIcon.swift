import CoreGraphics
import DeviceCatalog
import Foundation

/// 電池。iOS 18〜26 は「枠 + 中身 + 突起」、iOS 27 は枠のないカプセル形。
/// 寸法の比は Simulator の画像から測ったもの（iPhone 16 の 3 倍の画像で、iOS 18〜26 の本体は 25×13pt、iOS 27 は 26.3×13.7pt）
struct BatteryIcon {
    let layout: StatusBarLayout

    private var body: CGRect { layout.batteryBody.outline }
    private var nub: CGRect { layout.batteryNub.outline }

    func draw(_ battery: BatterySpec, palette: Palette, in context: CGContext) {
        // 充電中のマークのまわりは背景が見えるように抜くので、本体は 1 枚の層に描いてから抜く
        context.withLayer(alpha: 1) {
            if layout.generation == .iOS27 {
                drawCapsule(battery, palette: palette, in: context)
            } else {
                drawOutlined(battery, palette: palette, in: context)
            }
            if battery.state == .charging {
                context.setBlendMode(.clear)
                strokeAndFill(boltPath, color: palette.content(), lineWidth: body.height * 0.15, in: context)
                context.setBlendMode(.normal)
            }
        }
        drawNub(battery, palette: palette, in: context)
        if battery.state == .charging {
            context.withLayer(alpha: palette.batteryTrackAlpha) {
                strokeAndFill(boltPath, color: palette.content(), lineWidth: body.height * 0.03, in: context)
            }
        }
    }

    // MARK: - iOS 18〜26

    /// 枠（太さ 1）・すき間（1）・中身の順に内側へ並ぶ。単位は本体の高さの 1/13
    private func drawOutlined(_ battery: BatterySpec, palette: Palette, in context: CGContext) {
        let unit = body.height / 13
        let frame = body.insetBy(dx: unit / 2, dy: unit / 2)
        context.addPath(CGPath(roundedRect: frame, cornerWidth: 3.5 * unit, cornerHeight: 3.5 * unit, transform: nil))
        context.setStrokeColor(palette.content(alpha: palette.batteryOutlineAlpha))
        context.setLineWidth(unit)
        context.strokePath()

        let inner = body.insetBy(dx: 2 * unit, dy: 2 * unit)
        let level = CGRect(x: inner.minX, y: inner.minY, width: inner.width * battery.level, height: inner.height)
        guard level.width > 0 else { return }
        let radius = min(2 * unit, level.width / 2)
        context.addPath(CGPath(roundedRect: level, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(palette.batteryLevel(battery))
        context.fillPath()
    }

    // MARK: - iOS 27

    /// 本体全体が残量の目盛り。空いている部分は薄い色、残量の部分を左から塗る
    private func drawCapsule(_ battery: BatterySpec, palette: Palette, in context: CGContext) {
        let radius = body.height * 0.317
        let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(shape)
        context.setFillColor(palette.content(alpha: palette.batteryTrackAlpha))
        context.fillPath()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        // 残量の部分が半透明の地と重ならないよう、いったん抜いてから塗る
        let level = CGRect(x: body.minX, y: body.minY, width: body.width * battery.level, height: body.height)
        context.setBlendMode(.clear)
        context.fill(level)
        context.setBlendMode(.normal)
        context.setFillColor(palette.batteryLevel(battery))
        context.fill(level)
        context.restoreGState()
    }

    // MARK: - 突起と充電中のマーク

    /// 右端の突起。左はまっすぐで、右の角が丸い
    private func drawNub(_ battery: BatterySpec, palette: Palette, in context: CGContext) {
        let radius = min(nub.width, nub.height / 2) * 0.9
        let path = CGMutablePath()
        path.move(to: CGPoint(x: nub.minX, y: nub.minY))
        path.addArc(tangent1End: CGPoint(x: nub.maxX, y: nub.minY), tangent2End: CGPoint(x: nub.maxX, y: nub.midY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: nub.maxX, y: nub.maxY), tangent2End: CGPoint(x: nub.minX, y: nub.maxY), radius: radius)
        path.addLine(to: CGPoint(x: nub.minX, y: nub.maxY))
        path.closeSubpath()
        context.addPath(path)
        if layout.generation == .iOS27 {
            // 満タンのときは残量と同じ色、それ以外は空いている部分と同じ色
            let isFull = battery.level >= 1
            context.setFillColor(isFull ? palette.batteryLevel(battery) : palette.content(alpha: palette.batteryTrackAlpha))
        } else {
            context.setFillColor(palette.content(alpha: palette.batteryNubAlpha))
        }
        context.fillPath()
    }

    /// 充電中の稲妻。本体の中心について点対称で、本体の上下に少しはみ出す。座標は本体の高さを 1 とした中心からの位置
    private var boltPath: CGPath {
        let half: [CGPoint] = [
            CGPoint(x: 0.110, y: -0.517), CGPoint(x: 0.188, y: -0.517), CGPoint(x: 0.044, y: -0.102),
            CGPoint(x: 0.317, y: -0.102), CGPoint(x: 0.329, y: -0.049)
        ]
        let points = (half + half.map { CGPoint(x: -$0.x, y: -$0.y) }).map {
            CGPoint(x: body.midX + $0.x * body.height, y: body.midY + $0.y * body.height)
        }
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    private func strokeAndFill(_ path: CGPath, color: CGColor, lineWidth: CGFloat, in context: CGContext) {
        context.addPath(path)
        context.setFillColor(color)
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.setLineJoin(.round)
        context.drawPath(using: .fillStroke)
    }
}
