import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 시각 표기·계산 도우미. 앱과 검증 스크립트가 같이 쓴다.
enum TimeFormat {
    /// 화면 표시용 `00:03.47` (분:초.백분의일초)
    static func clock(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let minutes = Int(s / 60)
        let rest = s - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, rest)
    }

    /// 파일명용 `t03.47` (초, 소수 둘째 자리)
    static func fileTag(_ seconds: Double) -> String {
        String(format: "t%05.2f", max(0, seconds))
    }

    /// 길이를 넘는 시각은 마지막 프레임(끝 1ms 앞)으로 묶는다.
    static func clamp(_ seconds: Double, duration: Double) -> Double {
        min(max(0, seconds), max(0, duration - 0.001))
    }

    /// 초 → CMTime(마이크로초). **올림**한다.
    /// `CMTime(seconds:preferredTimescale:)`는 버림이라, 프레임 시작 시각(예: 31/24 = 1.2916666…초)을 넣으면
    /// 1.291666초가 되어 경계 바로 앞 = 앞 프레임이 나온다(2026-11-07 실측). 올리면 항상 그 프레임 안쪽 1µs 이내에 선다.
    static func cmTime(_ seconds: Double) -> CMTime {
        let micros = (max(0, seconds) * 1_000_000 - 1e-6).rounded(.up)
        return CMTime(value: CMTimeValue(max(0, micros)), timescale: 1_000_000)
    }
}

enum FrameExportError: LocalizedError {
    case cannotCreateFile(URL)

    var errorDescription: String? {
        switch self {
        case .cannotCreateFile(let url):
            return String(localized: "PNG 파일을 만들 수 없습니다: \(url.path)")
        }
    }
}

/// 지정한 시각의 프레임을 정확히(허용 오차 0) 뽑아 PNG로 저장한다.
enum FrameExporter {
    /// `<폴더>/_frames/<원본파일명>_t03.47.png`. 같은 이름이 이미 있고 **다른 원본 경로**에서 저장한 것이면 `_2`, `_3`…을 붙인다
    /// (다른 폴더의 같은 이름 파일끼리 덮어쓰지 않게). 같은 원본·같은 시각이면 덮어쓴다.
    /// 원본 경로는 저장할 때 PNG 설명(Description) 칸에 적어 둔다 — 이 칸이 없는 예전 파일은 같은 원본으로 보고 덮어쓴다(예전 동작).
    static func destination(for source: URL, seconds: Double, in folder: URL) -> URL {
        let base = "\(source.deletingPathExtension().lastPathComponent)_\(TimeFormat.fileTag(seconds))"
        let sourcePath = sourceKey(source)
        var number = 1
        while true {
            let name = number == 1 ? base : "\(base)_\(number)"
            let url = folder.appendingPathComponent("\(name).png")
            guard FileManager.default.fileExists(atPath: url.path) else { return url }
            guard let saved = savedSourcePath(of: url), saved != sourcePath else { return url }
            number += 1
        }
    }

    /// 원본을 가리키는 값(심볼릭 링크를 풀고 정리한 경로)
    static func sourceKey(_ source: URL) -> String {
        source.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// 저장된 PNG에 적힌 원본 경로. 없으면 nil.
    static func savedSourcePath(of png: URL) -> String? {
        guard let image = CGImageSourceCreateWithURL(png as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let pngInfo = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
              let path = pngInfo[kCGImagePropertyPNGDescription] as? String, !path.isEmpty else { return nil }
        return path
    }

    static func framesFolder(besides firstFile: URL) -> URL {
        firstFile.deletingLastPathComponent().appendingPathComponent("_frames", isDirectory: true)
    }

    /// 한 장 추출. 플레이어의 `currentTime()`을 그대로 받는다(초로 바꾸면 경계에서 앞 프레임으로 밀릴 수 있다).
    static func exportFrame(from source: URL, at time: CMTime, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: time)
        try writePNG(image, to: destination, sourcePath: sourceKey(source))
    }

    /// `sourcePath`가 있으면 PNG 설명 칸에 원본 경로를 적는다(이름 충돌 판단용).
    static func writePNG(_ image: CGImage, to url: URL, sourcePath: String? = nil) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw FrameExportError.cannotCreateFile(url)
        }
        var properties: [CFString: Any] = [:]
        if let sourcePath {
            properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: sourcePath]
        }
        CGImageDestinationAddImage(dest, image, properties.isEmpty ? nil : properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw FrameExportError.cannotCreateFile(url)
        }
    }
}
