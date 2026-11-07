import AVFoundation
import Observation
import os

/// 칸 바 호버 썸네일: 테이크 한 개의 작은 프레임 이미지를 비동기로 만들고 프레임 번호로 기억한다(최근 200장, LRU).
///
/// - 속도용이라 허용 오차는 앞뒤 1프레임(정확한 프레임은 화면이 보여준다), 크기는 최대 320px.
/// - **한 번에 한 장만** 만든다. 같은 이벤트 처리 안에서 쏟아진 요청은 모아 마지막 것만 다음 런루프 차례에 시작하고,
///   만드는 중에 새 요청이 오면 그 요청이 대기 자리를 차지하며(앞선 대기는 버림) 진행 중인 생성은
///   `cancelAllCGImageGeneration()`으로 끊는다 — 마우스가 빨리 지나가면 마지막 요청만 만들어진다.
@MainActor
@Observable
final class ThumbnailCache {
    static let capacity = 200
    static let maxPixelSize = 320

    /// 확인용 숫자(검증 스크립트·로그)
    struct Stats: Equatable {
        var requests = 0
        var cacheHits = 0
        var started = 0
        var generated = 0
        var cancelled = 0
        var failed = 0
    }

    /// 가장 최근에 손에 들어온 썸네일(요청한 프레임이 아직 없을 때 대신 보여준다)
    private(set) var latestFrame: Int?
    @ObservationIgnored private(set) var latestImage: CGImage?
    /// 화면 갱신용 — 새 이미지가 들어올 때마다 1씩
    private(set) var revision = 0
    @ObservationIgnored private(set) var stats = Stats()

    @ObservationIgnored let frameDuration: Double
    @ObservationIgnored let frameCount: Int
    @ObservationIgnored private let generator: AVAssetImageGenerator
    @ObservationIgnored private var images: [Int: CGImage] = [:]
    /// 오래된 것부터(앞) 최근 것(뒤)
    @ObservationIgnored private var order: [Int] = []
    @ObservationIgnored private var inFlight: Int?
    @ObservationIgnored private var pending: Int?
    @ObservationIgnored private var startScheduled = false
    @ObservationIgnored private let log = Logger(subsystem: "com.jasonhwangfilm.qslate", category: "thumbnail")

    init(url: URL, fps: Double, duration: Double) {
        let fd = 1 / max(fps, 1)
        frameDuration = fd
        frameCount = max(1, Int((duration / fd).rounded()))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Self.maxPixelSize, height: Self.maxPixelSize)
        let tolerance = CMTime(seconds: fd, preferredTimescale: 1_000_000)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        self.generator = generator
    }

    /// 원본 기준 초 → 프레임 번호(0 ~ 마지막)
    func frame(at seconds: Double) -> Int {
        min(max(0, Int((seconds / frameDuration + 1e-6).rounded(.down))), frameCount - 1)
    }

    func image(for frame: Int) -> CGImage? { images[frame] }

    /// 그 프레임의 썸네일을 요청한다. 있으면 바로(캐시 적중), 없으면 만들기 시작하거나 대기 자리를 차지한다.
    func request(frame rawFrame: Int) {
        let frame = min(max(0, rawFrame), frameCount - 1)
        stats.requests += 1
        if let image = images[frame] {
            stats.cacheHits += 1
            touch(frame)
            deliver(frame, image)
            pending = nil
            if inFlight != nil { generator.cancelAllCGImageGeneration() }
            return
        }
        if let current = inFlight {
            guard current != frame else {
                pending = nil
                return
            }
            // 진행 중인 것은 끊고 이 요청만 남긴다.
            if pending == nil { generator.cancelAllCGImageGeneration() }
            pending = frame
            return
        }
        // 같은 이벤트 처리 안에서 쏟아진 요청은 모아서 마지막 것만 시작한다(다음 런루프 차례에).
        pending = frame
        guard !startScheduled else { return }
        startScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.startScheduled = false
            guard self.inFlight == nil, let next = self.pending else { return }
            self.pending = nil
            if let cached = self.images[next] {
                self.deliver(next, cached)
            } else {
                self.start(next)
            }
        }
    }

    private func start(_ frame: Int) {
        inFlight = frame
        stats.started += 1
        // 프레임 가운데 시각을 달라고 한다(앞뒤 1프레임 허용).
        let time = CMTime(seconds: (Double(frame) + 0.5) * frameDuration, preferredTimescale: 1_000_000)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] _, image, _, result, _ in
            let box = ImageBox(image: image)
            Task { @MainActor in self?.finished(frame, box.image, result) }
        }
    }

    private func finished(_ frame: Int, _ image: CGImage?, _ result: AVAssetImageGenerator.Result) {
        if inFlight == frame { inFlight = nil }
        switch result {
        case .succeeded:
            if let image {
                stats.generated += 1
                store(frame, image)
                log.debug("thumbnail frame \(frame) 생성 (누적 \(self.stats.generated))")
                // 대기 중인 다른 요청이 있으면 이 이미지는 캐시에만 넣고 화면은 대기 쪽을 기다린다.
                if pending == nil || pending == frame { deliver(frame, image) }
            } else {
                stats.failed += 1
            }
        case .cancelled:
            stats.cancelled += 1
        case .failed:
            stats.failed += 1
        @unknown default:
            stats.failed += 1
        }
        if inFlight == nil, let next = pending {
            pending = nil
            if let cached = images[next] {
                deliver(next, cached)
            } else {
                start(next)
            }
        }
    }

    private func store(_ frame: Int, _ image: CGImage) {
        images[frame] = image
        touch(frame)
        while order.count > Self.capacity {
            images.removeValue(forKey: order.removeFirst())
        }
    }

    private func touch(_ frame: Int) {
        if let at = order.lastIndex(of: frame) { order.remove(at: at) }
        order.append(frame)
    }

    private func deliver(_ frame: Int, _ image: CGImage) {
        latestFrame = frame
        latestImage = image
        revision += 1
    }

    var cachedCount: Int { images.count }
    var isIdle: Bool { inFlight == nil && pending == nil }

    /// 바를 떠나면: 진행 중·대기 요청을 버린다(캐시는 둔다).
    func cancelPending() {
        pending = nil
        if inFlight != nil { generator.cancelAllCGImageGeneration() }
    }
}

/// 생성 콜백(다른 스레드)에서 메인으로 이미지를 넘기는 상자. CGImage는 만든 뒤 바뀌지 않는다.
private struct ImageBox: @unchecked Sendable {
    let image: CGImage?
}
