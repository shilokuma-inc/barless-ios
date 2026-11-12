import BarlessTestSupport
import DeviceCatalog
import ImageIOKit
import Testing

/// 検証 2（消去）: ステータスバーを消した結果を、インクが無い背景と比べる（docs/verification.md）
struct EraseVerificationTests {
    /// 単色の背景（設定アプリ・実機を含む 125 枚）: 帯の中が背景の色と完全に同じになる
    @Test
    func erasesCompletelyOnSolidBackground() throws {
        let catalog = try DeviceCatalog.bundled()
        for fixture in try Fixtures.supported().filter(\.isSolidBackground) {
            let strip = try fixture.loadStrip()
            let background = Verification.flatBackground(of: strip, scale: fixture.scale)
            let (_, result) = try #require(
                Verification.erase(fixture, input: strip, background: background, kind: "solid", catalog: catalog), "\(fixture)"
            )
            #expect(result.detected == "solid", "\(fixture)")
            #expect(result.maxDifference == 0, "\(fixture): 消し残しがある（差の最大 \(result.maxDifference)）")
        }
    }

    /// JPEG で保存し直した画像（品質 0.7）: 判定は変わらない。文字のまわりに薄いにじみが残るが、差は 32/255 以内
    @Test
    func toleratesRecompression() throws {
        let catalog = try DeviceCatalog.bundled()
        for fixture in try Fixtures.supported().filter(\.isSolidBackground) {
            let strip = try fixture.loadStrip()
            let input = try Synthetic.recompressed(strip, quality: 0.7)
            let background = Verification.flatBackground(of: strip, scale: fixture.scale)
            let (output, result) = try #require(
                Verification.erase(fixture, input: input, background: background, kind: "jpeg", catalog: catalog), "\(fixture)"
            )
            #expect(result.isLayoutCorrect, "\(fixture)")
            #expect(result.maxDifference <= 32, "\(fixture): 差の最大 \(result.maxDifference)")
            // 文字のまわりのにじみを、背景の輪郭と取り違えない
            #expect(!output.analysis.mayLeaveTraces, "\(fixture)")
        }
    }

    /// グラデーションの背景: Simulator のインクを作った背景に移し、消した結果を元の背景と比べる。
    /// 直線的に変わる背景（縦・横・斜め）は丸めの誤差まで、円形でも数段階の差で戻る。機種と iOS の世代の判定も変わらない。
    /// 対象は配置ごとに 1 機種（ライトとダーク）
    @Test(arguments: SyntheticBackground.allCases)
    func restoresSyntheticGradient(kind: SyntheticBackground) throws {
        let catalog = try DeviceCatalog.bundled()
        let limit = kind == .radial ? 6 : 2
        let fixtures = try Verification.representatives(in: catalog, variants: ["light-full", "dark-full"])
        #expect(fixtures.count == 48)
        for fixture in fixtures {
            let strip = try fixture.loadStrip()
            let background = kind.make(width: strip.width, height: strip.height, isLight: fixture.appearance == "light")
            let input = Synthetic.transplantInk(from: strip, onto: background, scale: fixture.scale)
            let (output, result) = try #require(
                Verification.erase(fixture, input: input, background: background, kind: kind.rawValue, catalog: catalog),
                "\(fixture) \(kind)"
            )
            #expect(result.isLayoutCorrect, "\(fixture) \(kind)")
            #expect(output.analysis.appearance == fixture.contentAppearance, "\(fixture) \(kind)")
            #expect(result.detected != "complex", "\(fixture) \(kind)")
            #expect(result.maxDifference <= limit, "\(fixture) \(kind): 差の最大 \(result.maxDifference)")
        }
    }
}
