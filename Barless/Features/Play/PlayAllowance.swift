import Foundation
import Observation
import os
import Security

/// Pro かどうか。課金の実装でつなぐ（いまは常に無料）
nonisolated protocol ProStatusProviding: Sendable {
    var isPro: Bool { get }
}

/// 課金が入るまでの仮の状態。常に無料として扱う
nonisolated struct FreePlan: ProStatusProviding {
    var isPro: Bool { false }
}

/// その日に、値を変えた画像を書き出した回数
nonisolated struct PlayUsage: Codable, Equatable, Sendable {
    /// 端末の日付（`2026-11-13`）
    var day: String
    var count: Int
}

/// 回数の保存先（テストと撮影モードでは、メモリの中だけに持つ）
nonisolated protocol PlayUsageStoring: Sendable {
    func load() -> PlayUsage?
    func save(_ usage: PlayUsage)
}

/// 「遊ぶ」で値を変えた画像の、無料の枠。1 日に書き出せる回数と、透かしを入れるかどうかを決める。
///
/// 「隠す」「整える」と、値を変えていない画像は、対象にしない。Pro では、回数の制限も透かしも無い
@MainActor
@Observable
final class PlayAllowance {
    /// 無料で、1 日に書き出せる回数
    static let dailyLimit = 3

    /// アプリ全体で使う 1 つ。撮影モード（UI テストを含む）では、メモリの中だけに持ち、起動のたびに戻す
    static let shared = PlayAllowance(
        store: ScreenshotDemo.isEnabled ? InMemoryPlayUsageStore(count: ScreenshotDemo.playUsedCount) : KeychainPlayUsageStore()
    )

    private let store: any PlayUsageStoring
    private let proStatus: any ProStatusProviding
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var usage: PlayUsage?

    /// - Parameters:
    ///   - calendar: 日付を決める暦。既定は、端末の設定（タイムゾーンなど）の変更に追従するもの
    ///   - now: いまの時刻（テストで日付を進めるのに使う）
    init(
        store: any PlayUsageStoring,
        proStatus: any ProStatusProviding = FreePlan(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.proStatus = proStatus
        self.calendar = calendar
        self.now = now
        self.usage = store.load()
    }

    var isPro: Bool {
        proStatus.isPro
    }

    /// 値を変えた画像に、透かしを入れるか
    var addsWatermark: Bool {
        !isPro
    }

    /// 今日、すでに書き出した回数。日付が変わっていれば 0
    var usedToday: Int {
        guard let usage, usage.day == today else { return 0 }
        return usage.count
    }

    /// 今日の残りの回数（無料のとき）
    var remainingToday: Int {
        max(0, Self.dailyLimit - usedToday)
    }

    /// 値を変えた画像を、いま書き出せるか
    var canExport: Bool {
        isPro || remainingToday > 0
    }

    /// 値を変えた画像を 1 枚書き出した。無料のときだけ数える
    func recordExport() {
        guard !isPro else { return }
        let updated = PlayUsage(day: today, count: usedToday + 1)
        usage = updated
        store.save(updated)
    }

    /// 端末の日付（その地域の暦で、年月日だけ。`2026-11-13`）
    var today: String {
        let components = calendar.dateComponents([.year, .month, .day], from: now())
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

/// メモリの中だけに持つ保存先
nonisolated final class InMemoryPlayUsageStore: PlayUsageStoring {
    private let usage: OSAllocatedUnfairLock<PlayUsage?>

    /// - Parameter count: 今日すでに使ったことにする回数（撮影モードで、使い切った状態から始めるのに使う）
    init(count: Int = 0, day: String? = nil) {
        let today = day ?? Self.today()
        usage = OSAllocatedUnfairLock(initialState: count > 0 ? PlayUsage(day: today, count: count) : nil)
    }

    func load() -> PlayUsage? {
        usage.withLock { $0 }
    }

    func save(_ usage: PlayUsage) {
        self.usage.withLock { $0 = usage }
    }

    private static func today() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

/// キーチェーンに持つ保存先。アプリを入れ直しても、その日の回数が残る
nonisolated struct KeychainPlayUsageStore: PlayUsageStoring {
    var service = "jp.shilokuma.Barless.play-usage"
    var account = "daily"

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    func load() -> PlayUsage? {
        var item: CFTypeRef?
        let request = query.merging([kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 }
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(PlayUsage.self, from: data)
    }

    func save(_ usage: PlayUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        let attributes = query.merging([kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock]) { $1 }
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// 保存した回数を消す（テストの後片付け）
    func remove() {
        SecItemDelete(query as CFDictionary)
    }
}
