import CoreGraphics
import Foundation
import Vision

/// 画像から時刻の文字列を読む処理
public protocol TimeTextRecognizing: Sendable {
    /// 画像の中にある時刻（`9:41` の形）を、上にあるものから順に返す。無ければ空
    func recognizeTimes(in image: CGImage) async throws -> [String]
}

/// Vision の文字認識で時刻を読む。処理は端末の中で完結する
public struct VisionTimeTextRecognizer: TimeTextRecognizing {
    public init() {}

    public func recognizeTimes(in image: CGImage) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // 「9:41」を単語として直されないようにする
        request.usesLanguageCorrection = false
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        let observations = try await request.perform(on: image)
        return observations
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            .compactMap { $0.topCandidates(1).first?.string }
            .compactMap(Self.time(in:))
    }

    /// 文字列の中から時刻（0:00〜23:59）を取り出す
    static func time(in text: String) -> String? {
        // Swift の正規表現は後読み（lookbehind）に対応していないので、手前の 1 文字ごと当てて時刻の部分だけを取り出す
        guard let match = text.firstMatch(of: /(?:^|[^0-9])((?:[01]?[0-9]|2[0-3]):[0-5][0-9])(?![0-9])/) else { return nil }
        return String(match.1)
    }
}
