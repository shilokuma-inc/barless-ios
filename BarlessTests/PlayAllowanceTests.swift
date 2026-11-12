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
    func keychainStoreRoundTrips() throws {
        let name = "jp.shilokuma.Barless.tests.\(UUID().uuidString)"
        let store = KeychainPlayUsageStore(service: name, backupSuiteName: name)
        defer { store.remove() }

        #expect(try store.load() == nil)
        try store.save(PlayUsage(day: "2026-11-13", count: 1))
        try store.save(PlayUsage(day: "2026-11-13", count: 2))

        #expect(try store.load() == PlayUsage(day: "2026-11-13", count: 2))
        store.remove()
        #expect(try store.load() == nil)
    }

    /// キーチェーンを読めない・書けないことは、呼び出し元に伝わる。回数は控えに残る
    @Test
    func reportsKeychainFailures() throws {
        let name = "jp.shilokuma.Barless.tests.\(UUID().uuidString)"
        let keychain = FakeKeychain()
        let store = KeychainPlayUsageStore(service: name, keychain: keychain, backupSuiteName: name)
        defer { store.remove() }
        let usage = PlayUsage(day: "2026-11-13", count: 2)

        // 書けないときは投げる。控えには残る
        keychain.setFailure(read: false, write: true)
        #expect(throws: KeychainError.self) { try store.save(usage) }
        #expect(try store.load() == usage)

        // 読めないときは投げる。控えの回数を持たせる
        keychain.setFailure(read: true, write: false)
        #expect(throws: PlayUsageUnreadableError(known: usage)) { try store.load() }
    }

    /// キーチェーンと控えで回数が違うときは、日付が新しいほうを使う。同じ日なら、
    /// キーチェーンを読めない間に数えた分を、キーチェーンの回数に足す
    @Test
    func mergesKeychainAndBackup() {
        func merged(_ stored: PlayUsage?, _ copied: PlayUsage?) -> PlayUsage? {
            KeychainPlayUsageStore.merged(stored: stored, copied: copied)
        }
        let day = "2026-11-13"

        // アプリを入れ直した後（控えは消えて、キーチェーンだけに残っている）
        #expect(merged(PlayUsage(day: day, count: 3), nil) == PlayUsage(day: day, count: 3))
        // キーチェーンに書けなかった後（控えのほうが進んでいる）
        #expect(merged(PlayUsage(day: day, count: 2), PlayUsage(day: day, count: 3)) == PlayUsage(day: day, count: 3))
        #expect(merged(PlayUsage(day: day, count: 3), PlayUsage(day: "2026-11-14", count: 1)) == PlayUsage(day: "2026-11-14", count: 1))
        // 入れ直した後に読めないまま 2 回書き出した（控えは、読めない間の 2 回だけ）
        #expect(merged(PlayUsage(day: day, count: 2), PlayUsage(day: day, count: 2, unconfirmed: 2)) == PlayUsage(day: day, count: 4))
        // 控えに 2 回ある状態から、読めないまま 1 回書き出した（足しすぎない）
        #expect(merged(PlayUsage(day: day, count: 2), PlayUsage(day: day, count: 3, unconfirmed: 1)) == PlayUsage(day: day, count: 3))
        // キーチェーンに何も無かった（読めない間の分も、そのままの回数）
        #expect(merged(nil, PlayUsage(day: day, count: 2, unconfirmed: 2)) == PlayUsage(day: day, count: 2))
    }

    /// キーチェーンに書けなかった回数は、次の機会に書き直す（入れ直して控えが消えても、回数が戻らない）
    @Test
    func retriesSavingAfterKeychainWriteFails() throws {
        let name = "jp.shilokuma.Barless.tests.\(UUID().uuidString)"
        let keychain = FakeKeychain()
        let store = KeychainPlayUsageStore(service: name, keychain: keychain, backupSuiteName: name)
        defer { store.remove() }
        let clock = TestClock()
        let allowance = clock.allowance(store: store)

        keychain.setFailure(read: false, write: true)
        allowance.recordExport()
        allowance.recordExport()
        #expect(allowance.usedToday == 2)
        #expect(try keychain.read(service: name, account: "daily") == nil)

        keychain.setFailure(read: false, write: false)
        allowance.sync()

        // 入れ直した後（控えが無い）でも、キーチェーンから 2 回と読める
        let reinstalled = KeychainPlayUsageStore(service: name, keychain: keychain, backupSuiteName: "\(name).reinstalled")
        defer { reinstalled.remove() }
        #expect(clock.allowance(store: reinstalled).usedToday == 2)
    }

    /// 起動し直したときも、キーチェーンに書けなかった回数を書き直す
    @Test
    func retriesSavingOnNextLaunch() throws {
        let name = "jp.shilokuma.Barless.tests.\(UUID().uuidString)"
        let keychain = FakeKeychain()
        let store = KeychainPlayUsageStore(service: name, keychain: keychain, backupSuiteName: name)
        defer { store.remove() }
        let clock = TestClock()

        keychain.setFailure(read: false, write: true)
        clock.allowance(store: store).recordExport()
        keychain.setFailure(read: false, write: false)
        #expect(clock.allowance(store: store).usedToday == 1)

        let reinstalled = KeychainPlayUsageStore(service: name, keychain: keychain, backupSuiteName: "\(name).reinstalled")
        defer { reinstalled.remove() }
        #expect(clock.allowance(store: reinstalled).usedToday == 1)
    }

    /// 入れ直した後（控えが無い）にキーチェーンを読めないときは、読めるようになったところで、
    /// 読めない間に数えた分を、キーチェーンに残っていた回数へ足す
    @Test
    func addsExportsMadeWhileKeychainWasUnreadable() throws {
        let name = "jp.shilokuma.Barless.tests.\(UUID().uuidString)"
        let keychain = FakeKeychain()
        let store = KeychainPlayUsageStore(service: name, keychain: keychain, backupSuiteName: name)
        defer { store.remove() }
        let clock = TestClock()
        let seeded = clock.allowance(store: KeychainPlayUsageStore(service: name, keychain: keychain, backupSuiteName: "\(name).before"))
        defer { KeychainPlayUsageStore(service: name, keychain: keychain, backupSuiteName: "\(name).before").remove() }
        seeded.recordExport()
        seeded.recordExport()
        let before = try keychain.read(service: name, account: "daily")

        keychain.setFailure(read: true, write: false)
        let allowance = clock.allowance(store: store)
        allowance.recordExport()
        // 読めない間は、キーチェーンに残っている回数を書き換えない
        keychain.setFailure(read: false, write: false)
        #expect(try keychain.read(service: name, account: "daily") == before)

        // 読めない間に起動し直しても、数えた分は控えから続く
        keychain.setFailure(read: true, write: false)
        let relaunched = clock.allowance(store: store)
        #expect(relaunched.usedToday == 1)

        // 読めるようになったら、2 回 + 1 回 = 3 回（使い切り）になり、キーチェーンにも書き戻す
        keychain.setFailure(read: false, write: false)
        relaunched.sync()
        #expect(relaunched.usedToday == 3 && !relaunched.canExport)
        #expect(try store.load() == PlayUsage(day: relaunched.today, count: 3))
        let stored = try #require(try keychain.read(service: name, account: "daily"))
        #expect(try JSONDecoder().decode(PlayUsage.self, from: stored) == PlayUsage(day: relaunched.today, count: 3))
    }
}
