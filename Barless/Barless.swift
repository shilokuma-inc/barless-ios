//
//  Barless.swift
//  Barless
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

@main
struct Barless: App {
    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    /// 撮影モード（ScreenshotDemo）のときは、撮る画面を開く
    @ViewBuilder private var rootView: some View {
        switch ScreenshotDemo.scene {
        case .home, nil:
            HomeView()
        case .editor:
            HomeView(initialSession: ScreenshotDemo.sampleSession())
        case .tidy:
            HomeView(initialSession: ScreenshotDemo.sampleSession(opening: .init(mode: .tidy, isComparing: true)))
        case .export:
            HomeView(initialSession: ScreenshotDemo.sampleSession(opening: .init(isExporting: true)))
        case .unrecognized:
            HomeView(initialSession: ScreenshotDemo.resavedSession())
        case .manual:
            HomeView(initialSession: ScreenshotDemo.resavedSession(opening: .init(isAdjusting: true)))
        }
    }
}
