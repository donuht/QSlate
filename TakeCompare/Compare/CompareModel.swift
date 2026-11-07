import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

/// 테이크 2~4개를 한 시계로 묶어 재생·탐색·저장한다.
@MainActor
@Observable
final class CompareModel {
    static let maxTakes = 4

    private(set) var takes: [Take] = []
    /// 타임라인 현재 시각(초). 가장 긴 테이크 기준.
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    var loopEnabled = true
    private(set) var isMuted = false
    /// 소리를 내는 테이크(0부터)
    private(set) var selectedIndex = 0
    /// 창 전체로 보는 테이크(0부터). nil이면 격자.
    private(set) var soloIndex: Int?

    // 상태줄
    private(set) var statusMessage = ""
    /// 상태줄을 누르면 Finder에서 선택해 보여줄 파일들
    private(set) var statusRevealURLs: [URL] = []

    // 재생 내부 상태
    @ObservationIgnored private var master: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var seeksInFlight = 0
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var resumeAfterScrub = false
    @ObservationIgnored private var loadGeneration = 0

    init() {
        statusMessage = String(localized: "mp4·mov 2~4개를 창에 끌어다 놓거나 ⌘O로 여세요")
    }

    // MARK: - 파생 값

    var readyTakes: [Take] { takes.filter(\.isReady) }

    /// 타임라인 길이 = 가장 긴 테이크
    var duration: Double { readyTakes.compactMap(\.info?.duration).max() ?? 0 }

    /// 한 프레임 이동 기준 fps — 첫 테이크(못 읽었으면 첫 정상 테이크)
    var stepFPS: Double {
        if let fps = takes.first?.info?.fps { return fps }
        return readyTakes.first?.info?.fps ?? 24
    }

    var hasTakes: Bool { !takes.isEmpty }

    // MARK: - 열기

    func open(_ urls: [URL]) {
        let movies = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
        }
        let skippedNonMovie = urls.count - movies.count

        guard !movies.isEmpty else {
            setStatus(String(localized: "열 수 있는 영상 파일(mp4·mov)이 없습니다"))
            return
        }
        guard movies.count >= 2 else {
            setStatus(String(localized: "비교하려면 2개 이상 필요합니다 — 영상 2~4개를 한꺼번에 끌어다 놓으세요"))
            return
        }

        let chosen = Array(movies.prefix(Self.maxTakes))
        let ignored = movies.count - chosen.count

        teardown()
        loadGeneration += 1
        let generation = loadGeneration
        takes = chosen.enumerated().map { Take(url: $0.element, index: $0.offset) }
        selectedIndex = 0
        soloIndex = nil
        currentTime = 0

        if ignored > 0 {
            setStatus(String(localized: "\(movies.count)개 중 앞의 4개만 열었습니다 — 5번째부터는 무시했습니다"))
        } else if skippedNonMovie > 0 {
            setStatus(String(localized: "영상이 아닌 파일 \(skippedNonMovie)개는 건너뛰었습니다"))
        } else {
            setStatus(String(localized: "여는 중…"))
        }
        let keepStatus = ignored > 0 || skippedNonMovie > 0

        Task {
            await withTaskGroup(of: (Int, Result<TakeInfo, TakeLoadFailure>).self) { group in
                for take in self.takes {
                    let url = take.url
                    let index = take.index
                    group.addTask { (index, await TakeLoader.load(url)) }
                }
                for await (index, result) in group {
                    guard generation == self.loadGeneration, index < self.takes.count else { return }
                    switch result {
                    case .success(let info): self.takes[index].makeReady(info)
                    case .failure(let failure): self.takes[index].state = .failed(failure.message)
                    }
                }
            }
            guard generation == self.loadGeneration else { return }
            self.didFinishLoading(keepStatus: keepStatus)
        }
    }

    private func didFinishLoading(keepStatus: Bool) {
        let ready = readyTakes
        // 가장 긴 테이크가 타임라인 시계
        master = ready.max { ($0.info?.duration ?? 0) < ($1.info?.duration ?? 0) }?.player
        if let master {
            timeObserver = master.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self, self.isPlaying, self.seeksInFlight == 0 else { return }
                    self.currentTime = min(time.seconds, self.duration)
                }
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: master.currentItem,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.masterDidReachEnd() }
            }
        }
        applyAudio()
        seekAll(to: 0)

        guard !keepStatus else { return }
        let failed = takes.count - ready.count
        if ready.isEmpty {
            setStatus(String(localized: "열린 테이크가 없습니다 — 모든 파일을 읽지 못했습니다"))
        } else if failed > 0 {
            setStatus(String(localized: "\(takes.count)개 중 \(failed)개를 열지 못했습니다 — 나머지로 비교합니다"))
        } else {
            setStatus(String(localized: "\(takes.count)개 열림 — 스페이스 재생, 1~4 단독 보기, ⌘S 프레임 저장"))
        }
    }

    private func teardown() {
        pauseAll()
        isPlaying = false
        if let timeObserver, let master { master.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        master = nil
        pendingSeek = nil
        seeksInFlight = 0
        for take in takes { take.player?.replaceCurrentItem(with: nil) }
    }

    // MARK: - 재생

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard master != nil else { return }
        // 끝에 있으면 처음부터
        if currentTime >= duration - 0.01 { currentTime = 0 }
        startSynchronized(at: currentTime)
    }

    /// 모든 플레이어를 같은 host time에 같은 미디어 시각으로 출발시킨다.
    private func startSynchronized(at seconds: Double) {
        pendingSeek = nil
        isPlaying = true
        let hostClock = CMClockGetHostTimeClock()
        let startHost = CMTimeAdd(CMClockGetTime(hostClock), CMTime(value: 1, timescale: 10)) // 0.1초 뒤
        for take in readyTakes {
            guard let player = take.player, let info = take.info else { continue }
            if seconds >= info.duration - 0.001 {
                // 이 테이크는 이미 끝 — 마지막 프레임에 둔다.
                player.pause()
                player.seek(to: TimeFormat.cmTime(take.clampedTime(seconds)), toleranceBefore: .zero, toleranceAfter: .zero)
                continue
            }
            let itemTime = TimeFormat.cmTime(seconds)
            if player.status == .readyToPlay {
                player.setRate(1, time: itemTime, atHostTime: startHost)
            } else {
                // 아직 준비 전이면 동기 시작을 쓸 수 없다(예외). 일반 재생으로 대신한다.
                player.seek(to: itemTime, toleranceBefore: .zero, toleranceAfter: .zero)
                player.play()
            }
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        pauseAll()
        let t = master.map { $0.currentTime().seconds } ?? currentTime
        // 멈춘 뒤 모두 같은 시각으로 다시 맞춘다(프레임 단위로 일치).
        seekAll(to: min(max(0, t.isFinite ? t : currentTime), duration))
    }

    private func pauseAll() {
        for take in takes { take.player?.pause() }
    }

    private func masterDidReachEnd() {
        guard isPlaying else { return }
        if loopEnabled {
            currentTime = 0
            startSynchronized(at: 0)
        } else {
            isPlaying = false
            pauseAll()
            currentTime = duration
        }
    }

    func toggleLoop() {
        loopEnabled.toggle()
        setStatus(loopEnabled ? String(localized: "루프 켬") : String(localized: "루프 끔"))
    }

    // MARK: - 탐색

    /// 모든 테이크를 같은 시각으로 정확히 이동. 끄는 중엔 앞선 이동이 끝날 때까지 마지막 값만 남긴다.
    func seekAll(to seconds: Double) {
        let t = min(max(0, seconds), duration)
        currentTime = t
        if seeksInFlight > 0 {
            pendingSeek = t
            return
        }
        let players = readyTakes.compactMap { take in take.player.map { (take, $0) } }
        guard !players.isEmpty else { return }
        seeksInFlight = players.count
        for (take, player) in players {
            player.seek(to: TimeFormat.cmTime(take.clampedTime(t)), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in self?.seekFinished() }
            }
        }
    }

    private func seekFinished() {
        seeksInFlight = max(0, seeksInFlight - 1)
        guard seeksInFlight == 0, let next = pendingSeek else { return }
        pendingSeek = nil
        seekAll(to: next)
    }

    /// 슬라이더를 잡고 놓을 때
    func scrubbing(_ began: Bool) {
        if began {
            resumeAfterScrub = isPlaying
            if isPlaying {
                isPlaying = false
                pauseAll()
            }
        } else if resumeAfterScrub {
            resumeAfterScrub = false
            // 진행 중 이동이 끝난 뒤의 시각에서 출발
            startSynchronized(at: pendingSeek ?? currentTime)
        }
    }

    /// 한 프레임 앞(+1)/뒤(-1). 첫 테이크 fps 기준. 프레임 경계 오차를 피하려고 프레임 안쪽 1/4 지점에 선다.
    func step(frames: Int) {
        if isPlaying { pause() }
        let fps = stepFPS
        let current = Int(floor(currentTime * fps + 1e-6))
        let last = max(0, Int(ceil(duration * fps)) - 1)
        let target = min(max(0, current + frames), last)
        seekAll(to: min((Double(target) + 0.25) / fps, duration))
    }

    func step(seconds: Double) {
        if isPlaying { pause() }
        seekAll(to: currentTime + seconds)
    }

    func goToStart() {
        if isPlaying { pause() }
        seekAll(to: 0)
    }

    func goToEnd() {
        if isPlaying { pause() }
        seekAll(to: duration)
    }

    // MARK: - 보기·소리

    /// 숫자키: 그 테이크만 창 전체로. 같은 키를 다시 누르면 격자로.
    func toggleSolo(_ index: Int) {
        guard index < takes.count else { return }
        if soloIndex == index {
            soloIndex = nil
        } else {
            soloIndex = index
            select(index)
        }
    }

    func showGrid() {
        soloIndex = nil
    }

    func select(_ index: Int) {
        guard index < takes.count else { return }
        selectedIndex = index
        applyAudio()
    }

    func toggleMute() {
        isMuted.toggle()
        applyAudio()
        setStatus(isMuted ? String(localized: "전체 음소거") : String(localized: "소리 켬 — 선택한 테이크만 들립니다"))
    }

    private func applyAudio() {
        for take in takes {
            take.player?.isMuted = isMuted || take.index != selectedIndex
        }
    }

    // MARK: - 프레임 저장

    /// 현재 시각의 프레임을 PNG로. `onlySelected`면 선택한 테이크 한 장만.
    func saveFrames(onlySelected: Bool) {
        if isPlaying { pause() }
        guard let first = takes.first else {
            setStatus(String(localized: "저장할 테이크가 없습니다"))
            return
        }
        let targets = onlySelected ? takes.filter { $0.index == selectedIndex && $0.isReady } : readyTakes
        guard !targets.isEmpty else {
            setStatus(String(localized: "저장할 수 있는 테이크가 없습니다"))
            return
        }
        let t = currentTime
        let folder = FrameExporter.framesFolder(besides: first.url)
        let jobs = targets.map { (source: $0.url, seconds: $0.clampedTime(t)) }
        setStatus(String(localized: "프레임 저장 중…"))

        Task {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                setStatus(String(localized: "저장 폴더를 만들 수 없습니다: \(error.localizedDescription)"))
                return
            }
            var saved: [URL] = []
            var failures: [String] = []
            for job in jobs {
                let dest = FrameExporter.destination(for: job.source, seconds: t, in: folder)
                do {
                    try await FrameExporter.exportFrame(from: job.source, at: job.seconds, to: dest)
                    saved.append(dest)
                } catch {
                    failures.append("\(job.source.lastPathComponent): \(error.localizedDescription)")
                }
            }
            let path = folder.path
            if failures.isEmpty {
                setStatus(String(localized: "\(saved.count)장 저장 → \(path)"), reveal: saved)
            } else {
                let reason = failures.joined(separator: " / ")
                setStatus(String(localized: "\(saved.count)장 저장, \(failures.count)장 실패 → \(path) (\(reason))"), reveal: saved)
            }
        }
    }

    // MARK: - 상태줄

    func setStatus(_ message: String, reveal: [URL] = []) {
        statusMessage = message
        statusRevealURLs = reveal
    }

    func revealStatusFiles() {
        guard !statusRevealURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(statusRevealURLs)
    }
}
