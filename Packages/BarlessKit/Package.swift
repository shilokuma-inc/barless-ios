// swift-tools-version: 6.0
import PackageDescription

// キレスク / Barless の画像処理のコア。アプリ本体・共有シート拡張・ショートカットから同じものを使う（docs/spec.md §7）。
// macOS も対象にしているのは、Simulator を起動せずに `swift test` でテストを回すため。
// 画素を 1 つずつ触る処理は、最適化なし（Debug）だと 10 倍以上遅い。Debug でもエディタとテストが実用の速さで動くよう、
// 画像を扱うターゲットは Debug でも最適化をかける（ローカルパッケージなので unsafeFlags を使える）
let optimized: [SwiftSetting] = [.unsafeFlags(["-O"], .when(configuration: .debug))]

let package = Package(
    name: "BarlessKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BarlessKit", targets: ["ImageIOKit"])
    ],
    targets: [
        // 画素の入れ物・デコード・メタデータ・書き出し
        .target(name: "ImageIOKit", swiftSettings: optimized),
        // テスト用: Simulator と実機の画像（上端の切り出し）とその一覧
        .target(
            name: "BarlessTestSupport",
            dependencies: ["ImageIOKit"],
            path: "Tests/BarlessTestSupport",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "BarlessKitTests",
            dependencies: ["BarlessTestSupport", "ImageIOKit"],
            swiftSettings: optimized
        )
    ],
    swiftLanguageModes: [.v6]
)
