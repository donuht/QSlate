import AVFoundation
import Observation

/// 테이크 한 개의 영상 정보. 비동기로 읽어서 메인으로 넘기므로 Sendable 값만 담는다.
struct TakeInfo: Sendable, Equatable {
    /// 회전(preferredTransform)을 반영한 화면상 크기
    var size: CGSize
    var fps: Double
    var duration: Double
}

/// 테이크를 열지 못한 사유
struct TakeLoadFailure: Error, Sendable {
    var message: String
}

/// 비교 중인 테이크 한 개. 플레이어는 정상적으로 읽힌 경우에만 만든다.
@MainActor
@Observable
final class Take: Identifiable {
    let id = UUID()
    let url: URL
    /// 0부터 시작. 화면·단축키 번호는 index + 1
    let index: Int

    enum State {
        case loading
        case ready(TakeInfo)
        case failed(String)
    }

    var state: State = .loading
    private(set) var player: AVPlayer?

    init(url: URL, index: Int) {
        self.url = url
        self.index = index
    }

    var fileName: String { url.lastPathComponent }
    var baseName: String { url.deletingPathExtension().lastPathComponent }

    var info: TakeInfo? {
        if case .ready(let info) = state { return info }
        return nil
    }

    var isReady: Bool { info != nil }

    func makeReady(_ info: TakeInfo) {
        state = .ready(info)
        let player = AVPlayer(playerItem: AVPlayerItem(url: url))
        // setRate(_:time:atHostTime:)를 쓰려면 꺼야 한다.
        player.automaticallyWaitsToMinimizeStalling = false
        // 짧은 테이크는 끝에서 마지막 프레임에 멈춘다.
        player.actionAtItemEnd = .pause
        player.isMuted = true
        self.player = player
    }

    /// 이 테이크에서 보여줄 시각. 길이를 넘으면 마지막 프레임(끝 1ms 앞)에 묶는다.
    func clampedTime(_ seconds: Double) -> Double {
        guard let info else { return 0 }
        return TimeFormat.clamp(seconds, duration: info.duration)
    }
}

/// 파일에서 영상 정보를 읽는다. 메인 밖에서 돌며 AVAsset을 바깥으로 내보내지 않는다.
enum TakeLoader {
    static func load(_ url: URL) async -> Result<TakeInfo, TakeLoadFailure> {
        let asset = AVURLAsset(url: url)
        do {
            let (playable, duration, tracks) = try await asset.load(.isPlayable, .duration, .tracks)
            guard let video = tracks.first(where: { $0.mediaType == .video }) else {
                return .failure(TakeLoadFailure(message: String(localized: "영상 트랙이 없습니다")))
            }
            let (natural, transform, fps, decodable) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .isDecodable)
            guard playable, decodable else {
                return .failure(TakeLoadFailure(message: String(localized: "재생할 수 없는 형식입니다 (코덱 미지원)")))
            }
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            let size = CGSize(width: abs(rect.width), height: abs(rect.height))
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else {
                return .failure(TakeLoadFailure(message: String(localized: "길이를 읽을 수 없습니다")))
            }
            return .success(TakeInfo(size: size, fps: fps > 0 ? Double(fps) : 24, duration: seconds))
        } catch {
            return .failure(TakeLoadFailure(message: error.localizedDescription))
        }
    }
}
