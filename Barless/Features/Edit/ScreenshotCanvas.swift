import CoreGraphics
import SwiftUI

/// スクリーンショットを、画面に収まる大きさで表示する。ステータスバーの帯には緑の印を付ける
struct ScreenshotCanvas: View {
    /// 元の画像と見比べる表示。境の左に元の画像、右に結果を出す
    struct Comparison {
        let before: CGImage
        /// 境の位置（0〜1。画像の左端が 0）
        let position: Binding<CGFloat>
    }

    let image: CGImage
    /// ステータスバーの帯の高さ（px。画像の上端から）。`nil` なら印を付けない
    var bandHeight: Int?
    /// 左下に出す札（「BEFORE」）
    var tag: String?
    /// 比較の表示。`nil` なら `image` だけを出す
    var comparison: Comparison?

    /// 画像の左右に空けておく幅。帯の印（画像の 10pt 外側）が画面の端にかからないようにする
    private static let sideInset: CGFloat = 28
    /// 帯の印と画像のすき間
    private static let markOffset: CGFloat = 10
    /// 帯の印の上に出す「ステータスバー」の文字のために、画像の上に空けておく高さ
    private static let labelSpace: CGFloat = 18
    /// 比較のつまみの大きさ
    private static let knobSize: CGFloat = 40

    var body: some View {
        GeometryReader { proxy in
            let topSpace = bandHeight == nil ? 0 : Self.labelSpace
            let size = fittedSize(in: CGSize(width: proxy.size.width, height: proxy.size.height - topSpace))
            let bandPoints = bandHeight.map { size.height * CGFloat($0) / CGFloat(max(1, image.height)) } ?? 0
            picture(size: size)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if let tag {
                        TagLabel(text: tag)
                            .padding(10)
                    }
                }
                .overlay {
                    if let comparison {
                        divider(size: size, position: comparison.position.wrappedValue, tagsTop: bandPoints + 10)
                    }
                }
                .overlay(alignment: .top) {
                    if bandHeight != nil {
                        bandMark(height: bandPoints)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            comparison?.position.wrappedValue = min(1, max(0, value.location.x / max(1, size.width)))
                        },
                    isEnabled: comparison != nil
                )
                .padding(.top, topSpace)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// 結果の画像。比較のときは、境の左側だけ元の画像を重ねる
    private func picture(size: CGSize) -> some View {
        scaled(image, to: size)
            .overlay(alignment: .leading) {
                if let comparison {
                    scaled(comparison.before, to: size)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: size.width * comparison.position.wrappedValue)
                        }
                }
            }
    }

    private func scaled(_ image: CGImage, to size: CGSize) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
    }

    /// 比較の境の線・つまみ・左右の札
    private func divider(size: CGSize, position: CGFloat, tagsTop: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HStack {
                TagLabel(text: "BEFORE")
                Spacer(minLength: 0)
                TagLabel(text: "AFTER")
            }
            .padding(.horizontal, 8)
            .padding(.top, tagsTop)
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: size.height)
                .shadow(color: .black.opacity(0.4), radius: 3)
                .offset(x: size.width * position - 1)
            Image(systemName: "arrow.left.and.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: Self.knobSize, height: Self.knobSize)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
                .offset(x: size.width * position - Self.knobSize / 2, y: size.height / 2 - Self.knobSize / 2)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
            .allowsHitTesting(false)
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

/// 画像の上に載せる小さな札（BEFORE / AFTER）。どの言語でも同じ表記にする
private struct TagLabel: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.bold))
            .kerning(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
