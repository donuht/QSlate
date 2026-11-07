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

    /// 프레임 단위 계산용 고정밀 CMTime
    static func cmTime(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1_000_000)
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
    /// `<폴더>/_frames/<원본파일명>_t03.47.png`
    static func destination(for source: URL, seconds: Double, in folder: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        return folder.appendingPathComponent("\(base)_\(TimeFormat.fileTag(seconds)).png")
    }

    static func framesFolder(besides firstFile: URL) -> URL {
        firstFile.deletingLastPathComponent().appendingPathComponent("_frames", isDirectory: true)
    }

    /// 한 장 추출. `seconds`는 이미 그 테이크 길이에 맞게 묶인 값이어야 한다.
    static func exportFrame(from source: URL, at seconds: Double, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: TimeFormat.cmTime(seconds))
        try writePNG(image, to: destination)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw FrameExportError.cannotCreateFile(url)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw FrameExportError.cannotCreateFile(url)
        }
    }
}
