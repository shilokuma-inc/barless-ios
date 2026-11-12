//
//  ScreenshotDemo.swift
//  Barless
//
//  App Store 用スクリーンショットの撮影モード。
//  Tools/capture_screenshots.sh が次の起動引数でアプリを起動し、目的の画面をデモデータで開かせる。
//
//    -screenshot-demo -screenshot-scene <Scene の rawValue> -AppleLanguages (<言語>) -AppleLocale <ロケール>
//
//  画面を足すときは、Scene に case を足し、Barless.swift の rootView で開く画面を返し、
//  AppStore/screenshots.json の scenes に同じ rawValue を足す（突き合わせは Tools/app_store_config.py が行う）。
//  デモデータは実データと混ざらないよう、撮影モードのときだけメモリ上やインメモリのストアに用意する。
//

import Foundation

enum ScreenshotDemo {
    /// 撮る画面。rawValue が AppStore/screenshots.json の scene と対応する
    enum Scene: String {
        case home
        /// 「隠す」の結果（作り物のスクリーンショットを開いた状態）
        case editor
        /// 「整える」の結果を、元の画像と比較している状態
        case tidy
        /// 書き出し
        case export
        /// 自動で消せなかったとき（大きさが変わった画像を開いた状態）
        case unrecognized
        /// 手動調整（大きさが変わった画像で、調整の画面を開いた状態）
        case manual
    }

    /// 撮影モードで起動しているか
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-screenshot-demo")

    /// 撮影モードで開く画面。撮影モードでないときと、知らない値を渡されたときは nil
    static let scene: Scene? = {
        guard isEnabled else {
            return nil
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshot-scene"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return Scene(rawValue: arguments[index + 1])
    }()

    /// 作り物のスクリーンショットを開いた編集。写真の選択を通らずに、編集と書き出しの画面を出せる
    @MainActor
    static func sampleSession(opening: EditSession.Opening = EditSession.Opening()) -> EditSession {
        // 絵を描いて PNG にするのは重いので、メインスレッドの外で作る
        EditSession(source: { @concurrent in try SampleScreenshot.pngData() }, opening: opening)
    }

    /// 大きさが変わった作り物のスクリーンショットを開いた編集。自動では消せないので、手動調整の画面を出せる
    @MainActor
    static func resavedSession(opening: EditSession.Opening = EditSession.Opening()) -> EditSession {
        EditSession(source: { @concurrent in try SampleScreenshot.resavedPNGData() }, opening: opening)
    }
}
