@testable import Barless
import Foundation
import os

/// テストで進められる時計
nonisolated final class TestClock: Sendable {
    private let date = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))

    var now: Date {
        date.withLock { $0 }
    }

    func advance(hours: Double) {
        date.withLock { $0 = $0.addingTimeInterval(hours * 3600) }
    }

    /// この時計と、世界標準時の暦で日付を決める、無料の枠
    @MainActor
    func allowance(store: any PlayUsageStoring = InMemoryPlayUsageStore(), isPro: Bool = false) -> PlayAllowance {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return PlayAllowance(store: store, proStatus: FixedPlan(isPro: isPro), calendar: calendar) { [self] in now }
    }
}

/// 決まった答えを返す、Pro かどうかの判定
nonisolated struct FixedPlan: ProStatusProviding {
    let isPro: Bool
}

/// メモリの中に持つ、キーチェーンの代わり。読み書きを失敗させられる
nonisolated final class FakeKeychain: KeychainAccessing {
    private struct State {
        var items: [String: Data] = [:]
        var failsToRead = false
        var failsToWrite = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func setFailure(read: Bool, write: Bool) {
        state.withLock {
            $0.failsToRead = read
            $0.failsToWrite = write
        }
    }

    func read(service: String, account: String) throws -> Data? {
        try state.withLock { state in
            if state.failsToRead { throw KeychainError(status: errSecInteractionNotAllowed) }
            return state.items["\(service)/\(account)"]
        }
    }

    func write(_ data: Data, service: String, account: String) throws {
        try state.withLock { state in
            if state.failsToWrite { throw KeychainError(status: errSecInteractionNotAllowed) }
            state.items["\(service)/\(account)"] = data
        }
    }

    func delete(service: String, account: String) {
        state.withLock { $0.items["\(service)/\(account)"] = nil }
    }
}
