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

    /// 이 테이크의 In(초, 원본 기준). 기본 0.
    var inPoint: Double = 0
    /// 이 테이크의 Out(초, 원본 기준). 기본 = 길이. 이 프레임까지 보여주고 멈춘다.
    var outPoint: Double = 0 {
        didSet { applyOutPoint() }
    }

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

    /// 한 프레임 길이(초)
    var frameDuration: Double { 1 / (info?.fps ?? 24) }

    /// In~Out 구간 길이(초)
    var span: Double { max(0, outPoint - inPoint) }

    var hasCustomIn: Bool { inPoint > InOut.epsilon }
    var hasCustomOut: Bool {
        guard let info else { return false }
        return outPoint < info.duration - InOut.epsilon
    }

    func makeReady(_ info: TakeInfo) {
        state = .ready(info)
        let item = AVPlayerItem(url: url)
        // step(byCount:)는 영상 출력(레이어·VideoOutput)이 붙어 있어야 한 프레임씩 움직인다.
        // 아무것도 안 붙은 플레이어는 한 번에 0.25초(24fps에서 6프레임)씩 뛴다(2026-11-07 실측).
        // 단독 보기로 칸이 화면에서 빠져도 정확하도록 VideoOutput을 항상 하나 붙여 둔다.
        item.add(AVPlayerItemVideoOutput(pixelBufferAttributes: nil))
        let player = AVPlayer(playerItem: item)
        // setRate(_:time:atHostTime:)를 쓰려면 꺼야 한다.
        player.automaticallyWaitsToMinimizeStalling = false
        // 짧은 테이크·Out에 닿은 테이크는 그 프레임에 멈춘다.
        player.actionAtItemEnd = .pause
        player.isMuted = true
        self.player = player
        inPoint = 0
        outPoint = info.duration
        position = 0
        isSoloPlaying = false
    }

    func resetInOut() {
        inPoint = 0
        outPoint = info?.duration ?? 0
    }

    /// 공통 타임라인 t(In 기준 상대 시각)에서 이 테이크가 보여줄 절대 시각.
    func absoluteTime(at t: Double) -> Double {
        guard let info else { return 0 }
        return InOut.absoluteTime(t: t, inPoint: inPoint, outPoint: outPoint, duration: info.duration)
    }

    /// t에서 이 테이크가 이미 자기 Out을 넘어 Out 프레임에 멈춰 있는지
    func isHeld(at t: Double) -> Bool {
        t > span + InOut.epsilon
    }

    /// 앞으로 한 프레임 갈 수 있는 마지막 위치(이 시각의 프레임이 마지막으로 보일 프레임) = Out 프레임, Out이 없으면 원본 마지막 프레임.
    /// `fileLastFrameStart`와 같은 반올림 규칙(`frameStart(near:)`이 거기로 묶는다) — `길이 − 1프레임`은 길이가 프레임 배수보다
    /// 조금 짧은 파일에서 마지막 바로 앞 프레임이 된다.
    var lastFrameStart: Double {
        guard info != nil else { return 0 }
        return frameStart(near: outPoint)
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    /// 원본 마지막 프레임의 시작 시각. 프레임 수는 반올림해 구한다 — 길이가 프레임 배수보다 조금 짧은 파일이 있다
    /// (표본 B: 44프레임인데 길이 1.833008 < 44/24). `길이 − 1프레임`을 내림하면 마지막 바로 앞 프레임이 된다.
    var fileLastFrameStart: Double {
        guard let info else { return 0 }
        let fd = frameDuration
        let frameCount = max(1, (info.duration / fd).rounded())
        let lastStart = (frameCount - 1) * fd
        return lastStart >= info.duration ? max(0, lastStart - fd) : lastStart
    }

    /// 원본 범위(0 ~ 마지막 프레임 시작)로 묶고 그 프레임의 시작에 맞춘 시각
    func frameStart(near seconds: Double) -> Double {
        let fd = frameDuration
        return ((min(max(0, seconds), fileLastFrameStart) / fd) + 1e-6).rounded(.down) * fd
    }

    /// `seconds`가 든 프레임을 보여주려고 허용 오차 0으로 seek할 목표 = 그 프레임의 시작 + ¼프레임(프레임 안쪽).
    /// 프레임 시작 k/fps로 seek하면 pts가 ms로 반올림된 파일(tbn 1000 — 프레임 1의 pts가 0.042 > 1/24)에서 앞 프레임이 보인다(2026-11-07 리뷰).
    /// 표시(위치·시각·In/Out)는 이 값이 아니라 `frameStart(near:)`로 한다.
    func seekTarget(forFrameContaining seconds: Double) -> Double {
        insideLastFrame(frameStart(near: seconds) + frameDuration * 0.25, start: frameStart(near: seconds))
    }

    /// 재생 출발 시각: `seconds`가 이미 그 프레임의 ¼ 안쪽이면 그대로(테이크끼리 시각을 덜 흩뜨린다), 프레임 앞머리면 ¼ 안쪽으로 민다.
    func playStartTarget(forFrameContaining seconds: Double) -> Double {
        let fd = frameDuration
        let start = frameStart(near: seconds)
        let s = max(0, seconds)
        return insideLastFrame(s >= start + fd * 0.25 && s < start + fd ? s : start + fd * 0.25, start: start)
    }

    /// 마지막 프레임이 ¼프레임보다 짧은 파일에서도 길이를 넘지 않게
    private func insideLastFrame(_ target: Double, start: Double) -> Double {
        guard let info else { return target }
        return min(target, max(start, info.duration - 0.001))
    }

    /// 플레이어가 프레임 시작(±0.1ms)에 서 있는가 — 그때만 step(byCount:)가 정확히 한 프레임 간다.
    func isOnFrameStart(_ seconds: Double) -> Bool {
        abs(seconds - frameStart(near: seconds)) <= 1e-4
    }

    /// 플레이어가 지금 실제로 서 있는 절대 시각
    var playerTime: CMTime? { player?.currentTime() }

    /// 화면 표시용 위치(초, 원본 기준). 모델이 이동이 끝날 때·재생 중에 `playerTime`에서 옮겨 적는다(AVPlayer 시각은 관찰되지 않아서).
    var position: Double = 0

    /// 칸 ▶로 이 테이크만 재생 중인가(공통 재생 `isPlaying`과 별개). 모델만 바꾼다.
    var isSoloPlaying = false

    /// 칸 바 호버 썸네일 캐시(처음 쓸 때 만든다). 못 읽은 테이크는 nil.
    @ObservationIgnored private var thumbnailCache: ThumbnailCache?
    var thumbnails: ThumbnailCache? {
        if let thumbnailCache { return thumbnailCache }
        guard let info else { return nil }
        let cache = ThumbnailCache(url: url, fps: info.fps, duration: info.duration)
        thumbnailCache = cache
        return cache
    }
    /// 이미 만든 캐시만(없으면 만들지 않는다)
    var existingThumbnails: ThumbnailCache? { thumbnailCache }

    /// Out은 플레이어의 forwardPlaybackEndTime으로 건다 — 재생이 Out에서 저절로 멈추고 끝 알림이 온다.
    private func applyOutPoint() {
        guard let item = player?.currentItem, let info else { return }
        item.forwardPlaybackEndTime = outPoint < info.duration - InOut.epsilon ? TimeFormat.cmTime(outPoint) : .invalid
    }
}

/// In/Out 타임라인 계산 (순수 함수 — 검증 스크립트도 같이 쓴다)
enum InOut {
    /// 같은 시각으로 볼 오차(초). 가장 빠른 영상(240fps)의 한 프레임보다 훨씬 작다.
    static let epsilon = 0.0001

    /// 공통 t에서 보여줄 절대 시각 = In + t. Out을 넘으면 Out, 길이를 넘으면 마지막 프레임.
    static func absoluteTime(t: Double, inPoint: Double, outPoint: Double, duration: Double) -> Double {
        TimeFormat.clamp(min(inPoint + max(0, t), outPoint), duration: duration)
    }

    /// 첫 테이크 기준 오프셋(프레임). `+3`이면 첫 테이크보다 3프레임 늦은 곳이 In.
    static func offsetFrames(inPoint: Double, referenceIn: Double, fps: Double) -> Int {
        Int(((inPoint - referenceIn) * fps).rounded())
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
