import DeviceCatalog
import Foundation
import Testing

struct DeviceCatalogTests {
    @Test
    func loadsBundledCatalog() throws {
        let catalog = try DeviceCatalog.bundled()
        #expect(catalog.schemaVersion == DeviceCatalog.supportedSchemaVersion)
        #expect(catalog.layouts.count == 25)
        #expect(Set(catalog.layouts.map(\.id)).count == catalog.layouts.count, "id が重複している")
    }

    /// 大きさだけでは配置が 1 つに決まらない（docs/device-table.md §0-1）
    @Test
    func sameSizeCanHaveSeveralLayouts() throws {
        let catalog = try DeviceCatalog.bundled()
        let candidates = catalog.candidates(pixelWidth: 1206, pixelHeight: 2622)
        #expect(candidates.map(\.id).sorted() == ["1206x2622-a/ios18-26", "1206x2622-a/ios27", "1206x2622-b/ios27"])
        #expect(Set(candidates.map(\.group)) == ["1206x2622-a", "1206x2622-b"])
        // 同じ配置の機種は 1 つのグループにまとまる
        let notch = try #require(catalog.layout(id: "1170x2532-a/ios18-26"))
        #expect(notch.models == ["iPhone 12", "iPhone 16e", "iPhone 17e"])
    }

    @Test
    func reportsUnsupportedAndUnknownSizes() throws {
        let catalog = try DeviceCatalog.bundled()
        // iPhone Duo は時刻などが縦に並ぶ別の配置なので、自動判定の対象にしていない
        #expect(catalog.candidates(pixelWidth: 1398, pixelHeight: 2034).isEmpty)
        #expect(catalog.unsupportedScreen(pixelWidth: 1398, pixelHeight: 2034)?.reason == "vertical-layout")
        #expect(catalog.candidates(pixelWidth: 1000, pixelHeight: 2000).isEmpty)
        #expect(catalog.unsupportedScreen(pixelWidth: 1000, pixelHeight: 2000) == nil)
    }

    @Test
    func everyLayoutIsConsistent() throws {
        for layout in try DeviceCatalog.bundled().layouts {
            let screen = PixelRect(x: 0, y: 0, width: layout.pixelWidth, height: layout.pixelHeight)
            #expect(layout.id == "\(layout.group)/\(layout.generation.rawValue)")
            #expect([2, 3].contains(layout.scale), "\(layout.id)")
            #expect(layout.cellularBars.count == 4, "\(layout.id)")
            #expect(layout.wifiBands.count == 3, "\(layout.id)")
            #expect(!layout.timeSamples.isEmpty, "\(layout.id)")
            #expect((layout.carrier != nil) == (layout.style == .centeredTime), "\(layout.id)")
            let rects = [layout.cellular, layout.wifi, layout.battery, layout.batteryBody, layout.batteryNub]
            for rect in rects + layout.timeSamples.map(\.ink) {
                #expect(rect.intersection(screen) == rect, "\(layout.id): 画面の外にはみ出している")
                #expect(rect.y >= layout.inkTop && rect.maxY <= layout.inkBottom, "\(layout.id): インクの上下の範囲から外れている")
            }
        }
    }

    @Test
    func rejectsUnknownSchemaVersion() {
        let json = Data(#"{"schemaVersion": 99, "updatedAt": "2026-11-12", "unsupported": [], "layouts": []}"#.utf8)
        #expect(throws: DeviceCatalogError.unsupportedSchema(99)) {
            try DeviceCatalog(data: json)
        }
    }
}

struct PixelRectTests {
    @Test
    func geometry() {
        let rect = PixelRect(x: 10, y: 20, width: 30, height: 40)
        #expect(rect.maxX == 40)
        #expect(rect.maxY == 60)
        #expect(rect.midX == 25)
        #expect(rect.insetBy(dx: -2, dy: 1) == PixelRect(x: 8, y: 21, width: 34, height: 38))
        #expect(rect.union(PixelRect(x: 0, y: 50, width: 5, height: 20)) == PixelRect(x: 0, y: 20, width: 40, height: 50))
        #expect(rect.intersection(PixelRect(x: 35, y: 0, width: 100, height: 30)) == PixelRect(x: 35, y: 20, width: 5, height: 10))
        #expect(rect.intersection(PixelRect(x: 100, y: 100, width: 5, height: 5)).width == 0)
        #expect(rect.maxEdgeDistance(to: PixelRect(x: 12, y: 20, width: 30, height: 37)) == 3)
    }
}
