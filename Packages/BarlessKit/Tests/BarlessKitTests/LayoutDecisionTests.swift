import BarlessTestSupport
import DeviceCatalog
import ImageIOKit
import StatusBarAnalyzer
import StatusBarRenderer
import Testing

/// 検証 1: 「大きさで候補 → 時刻の位置と大きさで機種グループと iOS の世代を決める」判定（docs/verification.md）
struct LayoutDecisionTests {
    private func decide(_ fixture: Fixture, catalog: DeviceCatalog, timeText: String?) throws -> LayoutDecision {
        StatusBarAnalyzer
            .analyze(strip: try fixture.loadStrip(), pixelHeight: fixture.height, timeText: timeText, catalog: catalog)
            .decision
    }

    /// 単色の背景（設定アプリ・ライト / ダーク・9:41 / 23:58、実機を含む 125 枚）は、すべて正しい配置に決まる
    @Test
    func resolvesEverySolidBackgroundFixture() throws {
        let catalog = try DeviceCatalog.bundled()
        let fixtures = try Fixtures.supported().filter(\.isSolidBackground)
        #expect(fixtures.count == 125)
        for fixture in fixtures {
            let expected = try #require(fixture.expectedLayout(in: catalog), "\(fixture)")
            let decision = try decide(fixture, catalog: catalog, timeText: fixture.time)
            #expect(decision.layout?.id == expected.id, "\(fixture): \(decision)")
        }
    }

    /// 時刻の文字列が読めなくても、時刻の高さと中心だけで同じ結果になる
    @Test
    func resolvesWithoutTimeText() throws {
        let catalog = try DeviceCatalog.bundled()
        for fixture in try Fixtures.supported().filter(\.isSolidBackground) {
            let expected = try #require(fixture.expectedLayout(in: catalog), "\(fixture)")
            let decision = try decide(fixture, catalog: catalog, timeText: nil)
            #expect(decision.layout?.id == expected.id, "\(fixture): \(decision)")
        }
    }

    /// ホーム画面（壁紙）: 41 枚のうち 39 枚は正しく決まる。残りは「決められない」になり、間違った配置には決めない。
    /// 決められないのは、時刻のすぐ後ろをウィジェットの輪郭が横切る iPhone SE の 2 枚
    @Test
    func neverPicksWrongLayoutOnWallpaper() throws {
        let catalog = try DeviceCatalog.bundled()
        let fixtures = try Fixtures.supported().filter { !$0.isSolidBackground }
        #expect(fixtures.count == 41)
        var undecided: [String] = []
        for fixture in fixtures {
            let expected = try #require(fixture.expectedLayout(in: catalog), "\(fixture)")
            let decision = try decide(fixture, catalog: catalog, timeText: fixture.time)
            if let layout = decision.layout {
                #expect(layout.id == expected.id, "\(fixture): \(decision)")
            } else {
                undecided.append(fixture.name)
            }
        }
        #expect(undecided.sorted() == [
            "iPhone-SE-3rd-generation__iOS-26-5__dark-home", "iPhone-SE-3rd-generation__iOS-27-0__dark-home"
        ])
    }

    /// 時刻で決まる機種と、時刻では差が付かず電池の形で iOS の世代を決める機種（iPhone 11 系・SE）がある
    @Test
    func usesBatteryStyleOnlyWhereTimeCannotTell() throws {
        let catalog = try DeviceCatalog.bundled()
        let needsBattery: Set<String> = ["iPhone-SE-3rd-generation", "iPhone-11", "iPhone-11-Pro", "iPhone-11-Pro-Max"]
        // 候補が 1 つしか無い大きさ（iPhone 13 mini などは世代ごとに 1 つずつあるので、ここには入らない）
        for fixture in try Fixtures.supported().filter(\.isSolidBackground) {
            guard case let .resolved(match, evidence) = try decide(fixture, catalog: catalog, timeText: fixture.time) else {
                Issue.record("\(fixture): 決まらなかった")
                continue
            }
            #expect(evidence == (needsBattery.contains(fixture.device) ? .batteryStyle : .time), "\(fixture)")
            #expect(match.timeError <= 1.0, "\(fixture): 時刻のずれ \(match.timeError)pt")
        }
    }

    @Test
    func reportsUnsupportedAndUnknownSizes() throws {
        let catalog = try DeviceCatalog.bundled()
        let duo = try #require(try Fixtures.all().first { $0.device == "iPhone-Duo" })
        guard case let .unsupported(screen) = try decide(duo, catalog: catalog, timeText: duo.time) else {
            Issue.record("iPhone Duo は対象外として返す")
            return
        }
        #expect(screen.models == ["iPhone Duo"])
        // SNS で再圧縮された画像など、カタログに無い大きさ
        let resized = Bitmap(width: 1080, height: 200, fill: .white)
        let analysis = StatusBarAnalyzer.analyze(strip: resized, pixelHeight: 2337, timeText: "9:41", catalog: catalog)
        #expect(analysis.decision == .unknownSize)
        #expect(analysis.scan == nil)
        #expect(analysis.eraseMask() == nil)
    }

    /// 電池の残量や背景の色が変わっても、電池の形で世代を取り違えない。
    /// iOS 27 の電池は、残量が少ないと「残量の色 → 空いている部分の薄い色」の境目が左端の近くに来る。
    /// これを iOS 18〜26 の「枠の内側のすき間」と取り違えないこと（時刻では決まらない iPhone 11 系・SE を、描いた画像で確かめる）
    @Test(arguments: [0.05, 0.12, 0.5, 1.0])
    func tellsGenerationFromBatteryAtAnyLevel(level: Double) throws {
        let catalog = try DeviceCatalog.bundled()
        let groups = ["750x1334-a", "828x1792-a", "1125x2436-a", "1242x2688-a"]
        let backgrounds: [(color: RGB, appearance: ContentAppearance)] = [
            (RGB(red: 242, green: 242, blue: 247), .darkContent),
            (RGB(red: 0, green: 180, blue: 200), .darkContent),
            (RGB(red: 0, green: 180, blue: 200), .lightContent),
            (RGB(red: 128, green: 128, blue: 128), .darkContent),
            (RGB(red: 128, green: 128, blue: 128), .lightContent),
            (.black, .lightContent)
        ]
        let spec = StatusBarSpec(time: "9:41", cellularBars: 4, wifiBars: 3, battery: BatterySpec(level: level))
        for layout in catalog.layouts where groups.contains(layout.group) {
            for background in backgrounds {
                var strip = Bitmap(width: layout.pixelWidth, height: 72 * layout.scale, fill: background.color)
                try StatusBarRenderer().render(spec, layout: layout, appearance: background.appearance, into: &strip)
                let analysis = StatusBarAnalyzer.analyze(strip: strip, pixelHeight: layout.pixelHeight, timeText: "9:41", catalog: catalog)
                #expect(
                    analysis.decision.layout?.id == layout.id,
                    "\(layout.id) 残量 \(level) 背景 \(background.color) \(background.appearance): \(analysis.decision.layout?.id ?? "決められない")"
                )
            }
        }
    }

    /// 上端の切り出しが短すぎて帯が入りきらない画像では、落ちずに「決められない」を返す
    @Test
    func doesNotCrashOnTooShortStrip() throws {
        let catalog = try DeviceCatalog.bundled()
        let fixture = try #require(try Fixtures.all().first { $0.name == "iPhone-17__iOS-27-0__light-full" })
        let short = try fixture.loadStrip().cropped(x: 0, y: 0, width: fixture.width, height: 40)
        let analysis = StatusBarAnalyzer.analyze(strip: short, pixelHeight: fixture.height, timeText: "9:41", catalog: catalog)
        guard case .ambiguous = analysis.decision else {
            Issue.record("決められないはず: \(analysis.decision)")
            return
        }
        #expect(analysis.eraseMask() == nil)
    }

    /// 背景の種類と文字の色も、単色の画像ではすべて正しく出る
    @Test
    func classifiesBackgroundAndAppearance() throws {
        let catalog = try DeviceCatalog.bundled()
        for fixture in try Fixtures.supported().filter(\.isSolidBackground) {
            let analysis = StatusBarAnalyzer.analyze(
                strip: try fixture.loadStrip(), pixelHeight: fixture.height, timeText: fixture.time, catalog: catalog
            )
            #expect(analysis.background == .solid, "\(fixture)")
            #expect(analysis.appearance == fixture.contentAppearance, "\(fixture)")
        }
    }
}
