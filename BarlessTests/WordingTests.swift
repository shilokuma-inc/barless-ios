@testable import Barless
import Foundation
import Testing

/// 文言の決まり（README の「文言の決まり」）が守られているか。アプリに入っている日本語の文言をすべて見る
struct WordingTests {
    /// 許可の確認画面に出る説明文。iOS の文と並ぶので、これだけは句点を付ける
    private static let permissionKey = "NSPhotoLibraryAddUsageDescription"

    /// アプリに入っている日本語の文言（キー → 日本語）
    private func japaneseStrings(table: String) throws -> [String: String] {
        let path = try #require(Bundle.main.path(forResource: "ja", ofType: "lproj"))
        let url = URL(fileURLWithPath: path).appendingPathComponent("\(table).strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(table).strings を読めない")
    }

    /// 画面の文言には、句点を付けない
    @Test
    func japaneseStringsHaveNoPeriod() throws {
        let strings = try japaneseStrings(table: "Localizable")
        #expect(strings.count >= 60)
        let offenders = strings.filter { $0.value.contains("。") }
        #expect(offenders.isEmpty, "句点がある: \(offenders)")
    }

    /// 呼び方は「スクショ」にそろえる（読み上げ用の文言も同じ）
    @Test
    func japaneseStringsSayScreenshotTheSameWay() throws {
        let strings = try japaneseStrings(table: "Localizable")
        let offenders = strings.filter { $0.value.contains("スクリーンショット") }
        #expect(offenders.isEmpty, "「スクリーンショット」がある: \(offenders)")
    }

    /// 句点を付けるのは、許可の確認画面に出る説明文だけ
    @Test
    func onlyPermissionTextEndsWithPeriod() throws {
        let strings = try japaneseStrings(table: "InfoPlist")
        let permission = try #require(strings[Self.permissionKey])
        #expect(permission.hasSuffix("。"))
        let others = strings.filter { $0.key != Self.permissionKey && $0.value.contains("。") }
        #expect(others.isEmpty, "句点がある: \(others)")
    }
}
