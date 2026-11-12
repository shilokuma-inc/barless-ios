@testable import Barless
import Foundation
import os
import Testing

/// 「遊ぶ」で値を変えた画像の、無料の枠（1 日 3 回）
@MainActor
struct PlayAllowanceTests {
    /// テストで進められる時計
    nonisolated private final class Clock: Sendable {
        private let date = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))

        var now: Date {
            date.withLock { $0 }
        }

        func advance(hours: Double) {
            date.withLock { $0 = $0.addingTimeInterval(hours * 3600) }
        }
    }

    nonisolated private struct FixedPlan: ProStatusProviding {
        let isPro: Bool
    }

    private func allowance(store: any PlayUsageStoring, clock: Clock, isPro: Bool = false) -> PlayAllowance {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return PlayAllowance(store: store, proStatus: FixedPlan(isPro: isPro), calendar: calendar) { clock.now }
    }

    /// 1 日に 3 回まで書き出せる。透かしは入る
    @Test
    func allowsThreeExportsADay() {
        let allowance = allowance(store: InMemoryPlayUsageStore(), clock: Clock())

        #expect(PlayAllowance.dailyLimit == 3)
        #expect(allowance.addsWatermark)
        #expect(allowance.remainingToday == 3 && allowance.canExport)
        allowance.recordExport()
        allowance.recordExport()
        #expect(allowance.remainingToday == 1 && allowance.canExport)
        allowance.recordExport()
        #expect(allowance.remainingToday == 0 && !allowance.canExport)
        // 使い切った後に数えても、残りは 0 のまま
        allowance.recordExport()
        #expect(allowance.remainingToday == 0 && allowance.usedToday == 4)
    }

    /// 端末の日付が変わると、回数が戻る
    @Test
    func resetsWhenDateChanges() {
        let clock = Clock()
        let allowance = allowance(store: InMemoryPlayUsageStore(), clock: clock)
        allowance.recordExport()
        allowance.recordExport()
        allowance.recordExport()
        #expect(!allowance.canExport)

        clock.advance(hours: 24)

        #expect(allowance.usedToday == 0 && allowance.remainingToday == 3 && allowance.canExport)
        allowance.recordExport()
        #expect(allowance.remainingToday == 2)
    }

    /// 回数は保存先に残り、アプリを起動し直しても続きから数える
    @Test
    func keepsCountAcrossLaunches() {
        let clock = Clock()
        let store = InMemoryPlayUsageStore()
        let first = allowance(store: store, clock: clock)
        first.recordExport()
        first.recordExport()

        let second = allowance(store: store, clock: clock)

        #expect(second.usedToday == 2 && second.remainingToday == 1)
    }

    /// Pro では、回数の制限も透かしも無く、回数を数えない
    @Test
    func proHasNoLimit() {
        let store = InMemoryPlayUsageStore()
        let allowance = allowance(store: store, clock: Clock(), isPro: true)

        #expect(allowance.isPro && !allowance.addsWatermark && allowance.canExport)
        allowance.recordExport()
        #expect(store.load() == nil)
    }

    /// キーチェーンの保存先は、書いた回数を読み戻せる
    @Test
    func keychainStoreRoundTrips() {
        let store = KeychainPlayUsageStore(service: "jp.shilokuma.Barless.tests.\(UUID().uuidString)")
        defer { store.remove() }

        #expect(store.load() == nil)
        store.save(PlayUsage(day: "2026-11-13", count: 1))
        store.save(PlayUsage(day: "2026-11-13", count: 2))

        #expect(store.load() == PlayUsage(day: "2026-11-13", count: 2))
        store.remove()
        #expect(store.load() == nil)
    }
}
