import CoreGraphics
import SwiftUI

/// スクリーンショットを、画面に収まる大きさで表示する。ステータスバーの帯には緑の印を付ける
struct ScreenshotCanvas: View {
    let image: CGImage
    /// ステータスバーの帯の高さ（px。画像の上端から）。`nil` なら印を付けない
    var bandHeight: Int?
    /// 左下に出す札（「元の画像」など）
    var tag: LocalizedStringKey?

    /// 画像の左右に空けておく幅。帯の印（画像の 10pt 外側）が画面の端にかからないようにする
    private static let sideInset: CGFloat = 28
    /// 帯の印と画像のすき間
    private static let markOffset: CGFloat = 10
    /// 帯の印の上に出す「ステータスバー」の文字のために、画像の上に空けておく高さ
    private static let labelSpace: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let topSpace = bandHeight == nil ? 0 : Self.labelSpace
            let size = fittedSize(in: CGSize(width: proxy.size.width, height: proxy.size.height - topSpace))
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if let tag {
                        Text(tag)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .padding(10)
                    }
                }
                .overlay(alignment: .top) {
                    if let bandHeight, image.height > 0 {
                        bandMark(height: size.height * CGFloat(bandHeight) / CGFloat(image.height))
                    }
                }
                .padding(.top, topSpace)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// 帯の左右に立てる緑の線と、左の線の上に出す「ステータスバー」の文字。
    /// 文字を線の横に置くと、画面の幅が狭い機種で入りきらないので、上に置く
    private func bandMark(height: CGFloat) -> some View {
        let offset = Self.markOffset
        return Color.clear
            .frame(height: height)
            .overlay(alignment: .leading) {
                line.offset(x: -Self.markOffset)
            }
            .overlay(alignment: .trailing) {
                line.offset(x: Self.markOffset)
            }
            .overlay(alignment: .topLeading) {
                Text("Status bar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .fixedSize()
                    .alignmentGuide(.leading) { $0[.leading] + offset }
                    .alignmentGuide(.top) { $0[.bottom] + 5 }
            }
            .accessibilityHidden(true)
    }

    private var line: some View {
        Theme.accent.frame(width: 1.5)
    }

    /// 縦横比を保ったまま、`container` に収まる大きさ
    private func fittedSize(in container: CGSize) -> CGSize {
        let width = CGFloat(max(1, image.width))
        let height = CGFloat(max(1, image.height))
        let available = CGSize(width: max(1, container.width - 2 * Self.sideInset), height: max(1, container.height))
        let scale = min(available.width / width, available.height / height)
        return CGSize(width: width * scale, height: height * scale)
    }
}
