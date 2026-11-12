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
    /// `count` のうち、保存先を読めない間に数えた回数。読めたときに、保存先の回数へ足す
    var unconfirmed = 0
}

/// 回数の保存先（テストと撮影モードでは、メモリの中だけに持つ）
nonisolated protocol PlayUsageStoring: Sendable {
    /// 保存してある回数（無ければ `nil`）。読めなかったときは投げる
    func load() throws(PlayUsageUnreadableError) -> PlayUsage?
    /// 書けなかったときは投げる
    func save(_ usage: PlayUsage) throws
}

/// 保存先を読めなかった
nonisolated struct PlayUsageUnreadableError: Error, Equatable {
    /// 読めなくても分かっている回数（控えの回数。無ければ `nil`）
    var known: PlayUsage?
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
    /// 保存先を読めていない（次の機会に読み直す）
    private var needsLoad = false
    /// 保存先に書けていない（次の機会に書き直す）
    private var needsSave = false

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
        load()
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
        sync()
        var updated = PlayUsage(day: today, count: usedToday + 1)
        if needsLoad {
            // 保存先を読めていない間の分は、読めたときに保存先の回数へ足せるように、分けて数えておく
            updated.unconfirmed = (usage?.day == today ? usage?.unconfirmed ?? 0 : 0) + 1
        }
        usage = updated
        save(updated)
    }

    /// 保存先を読めなかった・保存先に書けなかったときに、やり直す。
    /// 「遊ぶ」を始めるときと、回数を数える前に呼ぶ
    func sync() {
        if needsLoad { load() }
        if needsSave, let usage { save(usage) }
    }

    private func load() {
        do {
            usage = try store.load()
            needsLoad = false
            // 読めない間・書けない間の分を合わせた回数を、保存先に書き戻す
            if let usage { save(usage) }
        } catch {
            // 読めない間は、分かっている回数（控え）から数える。読み直しに失敗しても、数えた分は捨てない
            usage = usage ?? error.known
            needsLoad = true
        }
    }

    private func save(_ usage: PlayUsage) {
        do {
            try store.save(usage)
            needsSave = false
        } catch {
            needsSave = true
        }
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

/// キーチェーンの読み書き（テストで、失敗するものに差し替える）
nonisolated protocol KeychainAccessing: Sendable {
    /// 読めたらデータ、項目が無ければ `nil`。それ以外の失敗は投げる
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String)
}

/// キーチェーンの失敗（結果のコードを持つ）
nonisolated struct KeychainError: Error, Equatable {
    let status: OSStatus
}

/// iOS のキーチェーン
nonisolated struct SystemKeychain: KeychainAccessing {
    private func query(service: String, account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    func read(service: String, account: String) throws -> Data? {
        var item: CFTypeRef?
        let request = query(service: service, account: account).merging([kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 }
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return data
    }

    func write(_ data: Data, service: String, account: String) throws {
        let query = query(service: service, account: account)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            let attributes = query.merging([kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock]) { $1 }
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete(service: String, account: String) {
        SecItemDelete(query(service: service, account: account) as CFDictionary)
    }
}

/// キーチェーンに持つ保存先。アプリを入れ直しても、その日の回数が残る。
///
/// キーチェーンを読めない・書けないときに、回数を「まだ使っていない」と扱わないように、同じ回数を
/// アプリの設定（`UserDefaults`）にも控えておく。読むときは、両方を合わせた回数を返す。
/// 読めなかった・書けなかったことは呼び出し元に伝え、呼び出し元が次の機会にやり直す
nonisolated struct KeychainPlayUsageStore: PlayUsageStoring {
    var service = "jp.shilokuma.Barless.play-usage"
    var account = "daily"
    var keychain: any KeychainAccessing = SystemKeychain()
    /// 控えを置く `UserDefaults` の名前。`nil` なら標準のもの
    var backupSuiteName: String?

    private var backup: UserDefaults {
        backupSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    private var backupKey: String {
        "\(service).\(account)"
    }

    func load() throws(PlayUsageUnreadableError) -> PlayUsage? {
        let copied = backup.data(forKey: backupKey).flatMap(Self.decode)
        let stored: PlayUsage?
        do {
            stored = try keychain.read(service: service, account: account).flatMap(Self.decode)
        } catch {
            // 分かっているのは、控えの回数だけ
            throw PlayUsageUnreadableError(known: copied)
        }
        return Self.merged(stored: stored, copied: copied)
    }

    func save(_ usage: PlayUsage) throws {
        let data = try JSONEncoder().encode(usage)
        // キーチェーンに書けなくても、控えには残す
        backup.set(data, forKey: backupKey)
        // 読めない間に数えた回数は、キーチェーンに書かない（残っている回数を、少ない回数で上書きしないため）
        guard usage.unconfirmed == 0 else { return }
        try keychain.write(data, service: service, account: account)
    }

    /// キーチェーンの回数と、控えの回数を合わせる。日付が新しいほうを使う。同じ日なら、
    /// 読めない間に数えた分をキーチェーンの回数に足す（控えの回数のほうが多ければ、控えの回数）
    static func merged(stored: PlayUsage?, copied: PlayUsage?) -> PlayUsage? {
        guard let stored else { return copied.map { PlayUsage(day: $0.day, count: $0.count) } }
        guard let copied, copied.day >= stored.day else { return PlayUsage(day: stored.day, count: stored.count) }
        guard copied.day == stored.day else { return PlayUsage(day: copied.day, count: copied.count) }
        return PlayUsage(day: stored.day, count: max(stored.count + copied.unconfirmed, copied.count))
    }

    /// 保存した回数を消す（テストの後片付け）
    func remove() {
        keychain.delete(service: service, account: account)
        backup.removeObject(forKey: backupKey)
    }

    private static func decode(_ data: Data) -> PlayUsage? {
        try? JSONDecoder().decode(PlayUsage.self, from: data)
    }
}
