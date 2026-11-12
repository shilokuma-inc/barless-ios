@testable import Barless
import Foundation
import Testing

/// 「遊ぶ」で値を変えた画像の、無料の枠（1 日 3 回）
@MainActor
struct PlayAllowanceTests {
    /// 1 日に 3 回まで書き出せる。透かしは入る
    @Test
    func allowsThreeExportsADay() {
        let allowance = TestClock().allowance()

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
        let clock = TestClock()
        let allowance = clock.allowance()
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
        let clock = TestClock()
        let store = InMemoryPlayUsageStore()
        let first = clock.allowance(store: store)
        first.recordExport()
        first.recordExport()

        let second = clock.allowance(store: store)

        #expect(second.usedToday == 2 && second.remainingToday == 1)
    }

    /// Pro では、回数の制限も透かしも無く、回数を数えない
    @Test
    func proHasNoLimit() {
        let store = InMemoryPlayUsageStore()
        let allowance = TestClock().allowance(store: store, isPro: true)

        #expect(allowance.isPro && !allowance.addsWatermark && allowance.canExport)
        allowance.recordExport()
        #expect(store.load() == nil)
    }

    /// キーチェーンの保存先は、書いた回数を読み戻せる
    @Test
    func keychainStoreRoundTrips() {
        let name = "jp.shilokuma.Barless.tests.\(UUID().uuidString)"
        let store = KeychainPlayUsageStore(service: name, backupSuiteName: name)
        defer { store.remove() }

        #expect(store.load() == nil)
        store.save(PlayUsage(day: "2026-11-13", count: 1))
        store.save(PlayUsage(day: "2026-11-13", count: 2))

        #expect(store.load() == PlayUsage(day: "2026-11-13", count: 2))
        store.remove()
        #expect(store.load() == nil)
    }

    /// キーチェーンを読めない・書けないときも、回数を「まだ使っていない」と扱わない（控えから読む）
    @Test
    func keepsCountWhenKeychainFails() {
        let name = "jp.shilokuma.Barless.tests.\(UUID().uuidString)"
        let keychain = FakeKeychain()
        let store = KeychainPlayUsageStore(service: name, keychain: keychain, backupSuiteName: name)
        defer { store.remove() }

        // 書けないときも、控えに残る
        keychain.setFailure(read: false, write: true)
        store.save(PlayUsage(day: "2026-11-13", count: 2))
        #expect(store.load() == PlayUsage(day: "2026-11-13", count: 2))

        // 読めないときも、控えの回数を返す
        keychain.setFailure(read: true, write: false)
        store.save(PlayUsage(day: "2026-11-13", count: 3))
        #expect(store.load() == PlayUsage(day: "2026-11-13", count: 3))
    }

    /// キーチェーンと控えで回数が違うときは、進んでいるほう（日付が新しいほう、同じ日なら回数が多いほう）を使う
    @Test
    func usesTheMoreAdvancedCount() throws {
        let name = "jp.shilokuma.Barless.tests.\(UUID().uuidString)"
        let keychain = FakeKeychain()
        let store = KeychainPlayUsageStore(service: name, keychain: keychain, backupSuiteName: name)
        defer { store.remove() }
        func encoded(_ usage: PlayUsage) throws -> Data { try JSONEncoder().encode(usage) }

        // アプリを入れ直した後（控えは消えて、キーチェーンだけに残っている）
        try keychain.write(encoded(PlayUsage(day: "2026-11-13", count: 3)), service: name, account: "daily")
        #expect(store.load() == PlayUsage(day: "2026-11-13", count: 3))

        // キーチェーンに書けなかった日の後（控えのほうが新しい）
        keychain.setFailure(read: false, write: true)
        store.save(PlayUsage(day: "2026-11-14", count: 1))
        keychain.setFailure(read: false, write: false)
        #expect(store.load() == PlayUsage(day: "2026-11-14", count: 1))
    }
}
