import AppKit
import AVFoundation
import Observation
import os
import UniformTypeIdentifiers

/// 테이크 2~4개를 한 시계로 묶어 재생·탐색·저장한다.
@MainActor
@Observable
final class CompareModel {
    static let maxTakes = 4

    private(set) var takes: [Take] = []
    /// 공통 타임라인 현재 시각 t(초). **In 기준 상대 시각** — 줄 세운 상태(`isAligned`)에서 각 테이크는 자기 In + t를 보여준다.
    /// 칸 조작으로 흩어지면 0으로 돌아간다 — 다음 공통 조작은 각자 In(t = 0)에서 다시 줄 세운다.
    private(set) var currentTime: Double = 0
    /// 모든 테이크가 자기 In + t에 서 있는가. 칸 조작(그 테이크만 탐색)이 false로, 공통 조작(재생·슬라이더·← →·Home/End)이 true로 만든다.
    private(set) var isAligned = true
    private(set) var isPlaying = false
    var loopEnabled = true
    private(set) var isMuted = false
    /// 칸 바 위 호버 썸네일 켬/끔(보기 메뉴 · T · 공통 줄 버튼). 앱을 다시 켜도 유지 — UserDefaults `showBarThumbnails`, 기본 켬.
    /// 끄면 바가 썸네일 캐시를 받지 않아 말풍선도, 썸네일 생성 요청도, 캐시도 없다.
    private(set) var showBarThumbnails = UserDefaults.standard.object(forKey: CompareModel.barThumbnailsKey) as? Bool ?? true
    static let barThumbnailsKey = "showBarThumbnails"
    /// 선택한 테이크(0부터) — 소리, In/Out, ⌥화살표(그 테이크만 이동)의 대상
    private(set) var selectedIndex = 0
    /// 보기 모드: 격자 / 한 테이크만 크게 / 두 테이크 겹쳐 보기(A 아래, B 위)
    enum ViewMode: Equatable {
        case grid
        case solo(Int)
        case overlay(a: Int, b: Int)
    }

    /// 겹쳐 보기 방식: 갈라보기(세로선 왼쪽 A, 오른쪽 B) / 겹치기(B 반투명)
    enum OverlayStyle: Equatable {
        case wipe
        case blend
    }

    /// 겹쳐 보기 배율: 화면 맞춤 / B 원본 픽셀 1:1 / 2:1
    enum OverlayZoom: Equatable, CaseIterable {
        case fit
        case actual
        case double

        /// 화면 픽셀 대비 B 원본 픽셀 배율. 맞춤이면 nil.
        var pixelScale: Double? {
            switch self {
            case .fit: nil
            case .actual: 1
            case .double: 2
            }
        }
    }

    private(set) var viewMode: ViewMode = .grid
    /// 겹쳐 보기 방식(툴바 갈라보기·겹치기). 겹쳐 보기가 아닐 때도 마지막 값을 기억한다.
    private(set) var overlayStyle: OverlayStyle = .wipe
    /// 갈라보기 세로선 위치(화면 폭 대비 0~1, 기본 0.5). 선 왼쪽 = A, 오른쪽 = B
    private(set) var wipePosition: Double = 0.5
    /// 겹치기에서 B의 불투명도(0~1, 기본 0.5)
    private(set) var blendOpacity: Double = 0.5
    private(set) var overlayZoom: OverlayZoom = .fit
    /// 확대 상태의 팬(화면 pt, 가운데 기준 이동량). 뷰가 끌기로 바꾼다.
    var overlayPan: CGSize = .zero

    /// 창 전체로 보는 테이크(0부터). 단독 보기가 아니면 nil.
    var soloIndex: Int? {
        if case .solo(let index) = viewMode { return index }
        return nil
    }

    /// 겹쳐 보기 중인 두 테이크(A 아래, B 위). 겹쳐 보기가 아니면 nil.
    var overlayPair: (a: Int, b: Int)? {
        if case .overlay(let a, let b) = viewMode { return (a, b) }
        return nil
    }

    var isOverlay: Bool { overlayPair != nil }
    /// 프레임 이동 자가진단 중에는 다른 이동을 받지 않는다.
    private(set) var isDiagnosing = false

    // 상태줄
    private(set) var statusMessage = ""
    /// 상태줄을 누르면 Finder에서 선택해 보여줄 파일들
    private(set) var statusRevealURLs: [URL] = []

    // 재생 내부 상태
    /// 타임라인 시계 역할을 하는 테이크(구간이 가장 긴 테이크)의 플레이어에 건 관찰자
    @ObservationIgnored private var observedPlayer: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var seeksInFlight = 0
    @ObservationIgnored private var pendingSeek: Double?
    /// 공통 재생 출발 번호 — 출발 준비(seek) 중에 정지·재출발이 끼어들면 늦게 온 준비는 버린다.
    @ObservationIgnored private var playGeneration = 0
    /// 출발 준비 중인 플레이어들과 아직 안 끝난 seek 수.
    @ObservationIgnored private var launchRunners: [(Take, AVPlayer, CMTime)] = []
    @ObservationIgnored private var launchRemaining = 0
    /// step(byCount:)가 아직 반영되지 않았다(실측 약 2ms). 반영 전에 다음 step을 부르면 앞의 것이 묻힌다(3번 눌러 1프레임만 감).
    @ObservationIgnored private var stepInFlight = false
    /// 진행 중인 이동이 다 끝난 뒤에 차례로 할 일(프레임 이동·In/Out·저장)
    @ObservationIgnored private var afterSeekActions: [@MainActor () -> Void] = []
    @ObservationIgnored private var resumeAfterScrub = false
    /// 공통 슬라이더를 잡고 있는 중 — 이 동안 I/O는 받지 않는다(재생 중 잡았으면 표시가 어긋난다).
    @ObservationIgnored private(set) var isScrubbing = false
    /// 칸 바 끌기: 테이크별로 아직 반영하지 않은 마지막 목표(원본 기준 초). 테이크마다 따로 둬야
    /// 손잡이를 놓고 바로 다른 칸을 잡아도 앞 테이크의 마지막 목표가 사라지지 않는다.
    @ObservationIgnored private var takeScrubTargets: [Int: (seconds: Double, note: String?)] = [:]
    /// 칸 ▶(그 테이크만 재생) 중인 테이크별 관찰자: 위치 갱신용 주기 관찰자 + 끝(Out·파일 끝) 알림
    @ObservationIgnored private var soloObservers: [Int: (player: AVPlayer, time: Any, end: NSObjectProtocol)] = [:]
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.jasonhwangfilm.qslate", category: "step")

    init() {
        statusMessage = String(localized: "mp4·mov 2~4개를 창에 끌어다 놓거나 ⌘O로 여세요")
    }

    // MARK: - 파생 값

    var readyTakes: [Take] { takes.filter(\.isReady) }

    /// 타임라인 범위 = 테이크들의 (Out − In) 중 가장 긴 것
    var range: Double { readyTakes.map(\.span).max() ?? 0 }

    /// 타임라인 시계 = 구간이 가장 긴 테이크(같으면 앞 번호). 이 테이크는 t 범위 안에서 멈춰 있지 않는다.
    var masterTake: Take? {
        readyTakes.reduce(nil) { best, take in
            guard let best else { return take }
            return take.span > best.span + InOut.epsilon ? take : best
        }
    }

    /// 오프셋 기준 테이크 — 첫 테이크(못 읽었으면 첫 정상 테이크)
    var referenceTake: Take? {
        if let first = takes.first, first.isReady { return first }
        return readyTakes.first
    }

    var selectedTake: Take? {
        guard selectedIndex < takes.count, takes[selectedIndex].isReady else { return nil }
        return takes[selectedIndex]
    }

    var hasTakes: Bool { !takes.isEmpty }

    var hasAnyInOut: Bool { readyTakes.contains { $0.hasCustomIn || $0.hasCustomOut } }

    /// 첫 테이크 기준 이 테이크의 In 오프셋(프레임, 첫 테이크 fps 기준)
    func offsetFrames(of take: Take) -> Int {
        guard let ref = referenceTake, let fps = ref.info?.fps else { return 0 }
        return InOut.offsetFrames(inPoint: take.inPoint, referenceIn: ref.inPoint, fps: fps)
    }

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
        viewMode = .grid
        overlayZoom = .fit
        overlayPan = .zero
        currentTime = 0
        isAligned = true

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

    /// 아직 읽는 중인 테이크가 있는가 — 이때는 재생(공통·칸)을 받지 않는다.
    var isLoading: Bool { takes.contains(where: \.isLoading) }

    private func didFinishLoading(keepStatus: Bool) {
        let ready = readyTakes
        if selectedTake == nil, let first = ready.first { selectedIndex = first.index }
        // 로딩 중 재생은 막지만, 혹시 돌고 있으면 멈추고 처음에 줄 세운다.
        if isPlaying { pause() }
        rebindMaster()
        applyAudio()
        seekAll(to: 0)

        guard !keepStatus else { return }
        let failed = takes.count - ready.count
        if ready.isEmpty {
            setStatus(String(localized: "열린 테이크가 없습니다 — 모든 파일을 읽지 못했습니다"))
        } else if failed > 0 {
            setStatus(String(localized: "\(takes.count)개 중 \(failed)개를 열지 못했습니다 — 나머지로 비교합니다"))
        } else {
            setStatus(String(localized: "\(takes.count)개 열림 — 스페이스 재생, I/O 인·아웃, ⌥←→ 선택 테이크만 1프레임, ⌘S 지금 프레임 저장"))
        }
        if hasMixedFps, let master = masterTake {
            setStatus(statusMessage + " · " + String(localized: "fps가 다릅니다 — 공통 1프레임은 테이크 \(master.index + 1) 기준"))
        }
    }

    /// 열린 테이크들의 fps가 서로 다른가(24·30 섞임 등)
    var hasMixedFps: Bool {
        let rates = readyTakes.compactMap { $0.info?.fps }
        guard let first = rates.first else { return false }
        return rates.contains { abs($0 - first) > 0.001 }
    }

    /// 시계 테이크가 바뀌었으면(In/Out을 바꿔 구간 길이가 달라졌을 때) 관찰자를 새 플레이어로 옮긴다.
    private func rebindMaster() {
        let player = masterTake?.player
        guard player !== observedPlayer else { return }
        unbindMaster()
        guard let player else { return }
        observedPlayer = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, self.seeksInFlight == 0 else { return }
                self.currentTime = self.timelineTimeFromMaster() ?? self.currentTime
                self.refreshPositions()
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.masterDidReachEnd() }
        }
    }

    private func unbindMaster() {
        if let timeObserver, let observedPlayer { observedPlayer.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        observedPlayer = nil
    }

    /// 시계 테이크 플레이어가 실제로 선 시각에서 t를 읽는다.
    private func timelineTimeFromMaster() -> Double? {
        guard let master = masterTake, let time = master.playerTime?.seconds, time.isFinite else { return nil }
        return min(max(0, time - master.inPoint), range)
    }

    /// 시계 테이크가 지금 보여주는 프레임의 **시작**에 해당하는 t — 정지한 자리를 프레임 중간으로 남기지 않는다.
    private func timelineFrameTimeFromMaster() -> Double? {
        guard let master = masterTake, let time = master.playerTime?.seconds, time.isFinite else { return nil }
        return min(max(0, master.frameStart(near: time) - master.inPoint), range)
    }

    /// 시계 테이크의 마지막 프레임(Out 프레임, 없으면 원본 마지막 프레임)에 해당하는 t
    private var lastFrameTime: Double {
        guard let master = masterTake else { return range }
        return min(max(0, master.lastFrameStart - master.inPoint), range)
    }

    private func teardown() {
        for index in Array(soloObservers.keys) { removeSoloObservers(index) }
        for take in takes { take.isSoloPlaying = false }
        pauseAll()
        isPlaying = false
        // 출발 준비 중이던 옛 플레이어를 놓고, 늦게 온 준비 완료는 버린다.
        playGeneration += 1
        launchRunners = []
        launchRemaining = 0
        isScrubbing = false
        resumeAfterScrub = false
        unbindMaster()
        pendingSeek = nil
        seeksInFlight = 0
        stepInFlight = false
        afterSeekActions = []
        takeScrubTargets = [:]
        isDiagnosing = false
        isAligned = true
        for take in takes { take.player?.replaceCurrentItem(with: nil) }
    }

    // MARK: - 재생

    /// 스페이스·공통 ▶: 칸 ▶로 도는 테이크가 있으면 먼저 전부 멈추기만 한다(한 번 더 누르면 공통 재생 = 줄 세워 In부터).
    func togglePlay() {
        if isAnySoloPlaying {
            stopAllSolo(snap: true)
            setStatus(String(localized: "모든 테이크 정지"))
            return
        }
        isPlaying ? pause() : play()
    }

    func play() {
        guard !isDiagnosing, !isScrubbing else { return }
        guard !isLoading else {
            setStatus(String(localized: "불러오는 중…"))
            return
        }
        guard masterTake != nil else { return }
        guard range > InOut.epsilon else {
            setStatus(Self.noRangeMessage)
            return
        }
        stopAllSolo(snap: false)
        // 흩어져 있으면(currentTime = 0) 각자 In부터, 끝(시계 테이크의 마지막 프레임)에 있으면 처음부터
        if !isAligned || currentTime >= lastFrameTime - 0.01 { currentTime = 0 }
        startSynchronized(at: currentTime)
    }

    private static var noRangeMessage: String { String(localized: "재생할 구간이 없습니다 (In과 Out이 같음)") }

    /// 모든 플레이어를 같은 host time에 출발시킨다. 각 테이크의 출발 시각은 자기 In + t.
    /// 출발 전에 모든 플레이어를 자기 출발 시각으로 **먼저 정확히 세운다** — Out(forwardPlaybackEndTime)이나 파일 끝에
    /// 서 있는 플레이어는 setRate(_:time:atHostTime:)만으로는 움직이지 않는다(2026-11-07 실측: rate=1인데 위치가 Out에 머묾).
    private func startSynchronized(at t: Double) {
        pendingSeek = nil
        isPlaying = true
        isAligned = true
        currentTime = t
        playGeneration += 1
        let generation = playGeneration

        var runners: [(Take, AVPlayer, CMTime)] = []
        for take in readyTakes {
            guard let player = take.player else { continue }
            // 출발 시각 In + t는 프레임 안쪽으로(ms 타임스케일 파일에서 앞 프레임으로 출발하지 않게)
            let itemTime = TimeFormat.cmTime(take.playStartTarget(forFrameContaining: take.absoluteTime(at: t)))
            player.pause()
            if t >= take.span - 0.0005 {
                // 이 테이크는 이미 자기 Out을 넘었다 — Out 프레임에 둔다.
                player.seek(to: itemTime, toleranceBefore: .zero, toleranceAfter: .zero)
                continue
            }
            runners.append((take, player, itemTime))
        }
        guard !runners.isEmpty else {
            // 돌 테이크가 없다(모든 테이크 In == Out, 또는 이미 모두 끝) — 재생 상태로 남기지 않는다.
            isPlaying = false
            launchRunners = []
            launchRemaining = 0
            if range <= InOut.epsilon { setStatus(Self.noRangeMessage) }
            refreshPositions()
            return
        }

        launchRunners = runners
        launchRemaining = runners.count
        for (_, player, itemTime) in runners {
            player.seek(to: itemTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    // 그새 정지·재출발이 있었으면 이 출발은 버린다.
                    guard self.playGeneration == generation else { return }
                    self.launchRemaining -= 1
                    guard self.launchRemaining == 0, self.isPlaying else { return }
                    self.launch()
                }
            }
        }
    }

    /// 준비가 끝난 플레이어들을 0.1초 뒤 같은 host time에 출발시킨다.
    private func launch() {
        let hostClock = CMClockGetHostTimeClock()
        let startHost = CMTimeAdd(CMClockGetTime(hostClock), CMTime(value: 1, timescale: 10))
        for (_, player, itemTime) in launchRunners {
            if player.status == .readyToPlay {
                player.setRate(1, time: itemTime, atHostTime: startHost)
            } else {
                // 아직 준비 전이면 동기 시작을 쓸 수 없다(예외). 일반 재생으로 대신한다.
                player.play()
            }
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        playGeneration += 1
        pauseAll()
        // 멈춘 뒤 모두 같은 t로 다시 맞춘다 — 시계 테이크가 보여주던 프레임의 시작으로 스냅(프레임 중간 t가 남으면
        // 뒤이은 1프레임 이동이 2프레임을 가거나 제자리에 서고, I/O가 프레임 중간 값이 된다).
        seekAll(to: timelineFrameTimeFromMaster() ?? currentTime)
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
            playGeneration += 1
            pauseAll()
            // 파일 끝(마지막 프레임의 끝)에 두지 않고 시계 테이크의 마지막 프레임 시작에 모두 세운다.
            seekAll(to: lastFrameTime)
        }
    }

    func toggleLoop() {
        loopEnabled.toggle()
        setStatus(loopEnabled ? String(localized: "루프 켬") : String(localized: "루프 끔"))
    }

    // MARK: - 탐색

    /// 모든 테이크를 같은 t로 정확히 이동(각자 In + t) — 공통 조작은 전부 여기로 와서 줄을 다시 세운다.
    /// 끄는 중엔 앞선 이동이 끝날 때까지 마지막 값만 남긴다.
    func seekAll(to t: Double) {
        stopAllSolo(snap: false)
        let t = min(max(0, t), range)
        currentTime = t
        isAligned = true
        if seeksInFlight > 0 {
            pendingSeek = t
            return
        }
        let players = readyTakes.compactMap { take in take.player.map { (take, $0) } }
        guard !players.isEmpty else { return }
        seeksInFlight = players.count
        for (take, player) in players {
            let target = take.seekTarget(forFrameContaining: take.absoluteTime(at: t))
            player.seek(to: TimeFormat.cmTime(target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in self?.seekFinished() }
            }
        }
    }

    private func seekFinished() {
        seeksInFlight = max(0, seeksInFlight - 1)
        guard seeksInFlight == 0 else { return }
        refreshPositions()
        if let next = pendingSeek {
            pendingSeek = nil
            seekAll(to: next)
            return
        }
        runQueuedActions()
    }

    private var isSettled: Bool { seeksInFlight == 0 && !stepInFlight }

    /// 진행 중인 이동(seek·step)이 없으면 바로, 있으면 끝난 뒤 들어온 순서대로 한다. 이동 중의 currentTime()은 믿을 수 없어서.
    private func whenSettled(_ action: @escaping @MainActor () -> Void) {
        if isSettled && afterSeekActions.isEmpty {
            action()
        } else {
            afterSeekActions.append(action)
        }
    }

    /// 쌓인 일을 하나씩 — 앞의 일이 다시 이동을 시작하면 그게 끝날 때까지 기다린다.
    private func runQueuedActions() {
        while isSettled, !afterSeekActions.isEmpty {
            afterSeekActions.removeFirst()()
        }
    }

    /// 쌓인 일을 하는 도중에 부른다: 지금 시작한 이동이 끝나면 **바로 다음 차례로**(뒤에 쌓인 일보다 먼저) action.
    private func nextWhenSettled(_ action: @escaping @MainActor () -> Void) {
        if isSettled {
            action()
        } else {
            afterSeekActions.insert(action, at: 0)
        }
    }

    /// 공통 조작 준비: 진행 중 이동이 끝난 뒤, 칸 조작으로 흩어져 있으면 먼저 모두 자기 In(t = 0)에 줄 세우고 action.
    private func whenAligned(_ action: @escaping @MainActor () -> Void) {
        whenSettled { [weak self] in
            guard let self else { return }
            if self.isAligned {
                action()
            } else {
                self.seekAll(to: 0)
                self.nextWhenSettled(action)
            }
        }
    }

    /// 한 테이크의 플레이어를 원본 기준 `seconds`가 든 프레임에 세운다(목표는 프레임 안쪽 — `Take.seekTarget`).
    private func seekPlayer(of take: Take, toFrameContaining seconds: Double) {
        seekPlayer(of: take, toAbsolute: take.seekTarget(forFrameContaining: seconds))
    }

    /// 한 테이크의 플레이어만 원본 기준 `seconds`로 정확히 세운다(그 시각 그대로 — 자가진단 뒤 원래 자리로 되돌릴 때).
    private func seekPlayer(of take: Take, toAbsolute seconds: Double) {
        guard let player = take.player else { return }
        seeksInFlight += 1
        player.seek(to: TimeFormat.cmTime(seconds), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.seekFinished() }
        }
    }

    /// 화면 표시용 `Take.position`을 플레이어가 보여주는 프레임의 시작 시각으로 옮겨 적는다(플레이어는 프레임 안쪽에 서 있다).
    private func refreshPositions() {
        for take in readyTakes {
            guard let seconds = take.playerTime?.seconds, seconds.isFinite else { continue }
            let shown = take.frameStart(near: seconds)
            guard abs(shown - take.position) > 1e-7 else { continue }
            take.position = shown
        }
    }

    /// 칸 조작이 줄을 흩뜨렸다 — 공통 t는 의미가 없어지므로 0으로(다음 공통 조작은 각자 In부터).
    private func scatter() {
        guard isAligned else { return }
        isAligned = false
        currentTime = 0
    }

    /// In/Out을 바꾼 뒤: 지금 모든 테이크가 우연히 자기 In + t에 서 있으면 줄 선 상태, 아니면 흩어진 상태.
    private func updateAlignment() {
        let t = currentTime
        let aligned = readyTakes.allSatisfy { take in
            guard let seconds = take.playerTime?.seconds, seconds.isFinite else { return false }
            // 같은 프레임을 보여주는가(플레이어는 프레임 안쪽에 서 있다)
            return abs(take.frameStart(near: seconds) - take.frameStart(near: take.absoluteTime(at: t))) < take.frameDuration * 0.5
        }
        isAligned = aligned
        if !aligned { currentTime = 0 }
    }

    /// 슬라이더를 잡고 놓을 때
    func scrubbing(_ began: Bool) {
        isScrubbing = began
        if began {
            stopAllSolo(snap: false)
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

    /// 모든 테이크 한 프레임 앞(+1)/뒤(-1) — 각 테이크가 자기 프레임 하나만큼(프레임 시작이면 `AVPlayerItem.step(byCount:)`,
    /// 프레임 중간이면 그 프레임 시작 ± 1프레임으로 seek). 자기 In·Out 경계에 닿은 테이크는 그 자리에 둔다.
    func step(frames: Int) {
        guard !isDiagnosing else { return }
        stopAllSolo(snap: false)
        if isPlaying { pause() }
        whenAligned { [weak self] in self?.performFrameStep(frames) }
    }

    private func performFrameStep(_ frames: Int) {
        guard let master = masterTake else { return }
        if hasMixedFps {
            performMasterFrameStep(frames)
            return
        }
        let t = currentTime
        var stepped: [(AVPlayer, CMTime)] = []
        var held: [Take] = []
        var masterTarget: Double?
        for take in readyTakes {
            if take.isHeld(at: t) {
                held.append(take)
                continue
            }
            guard let target = frameStepTarget(take, frames: frames) else { continue }
            if take === master { masterTarget = target }
            moveOneFrame(take, frames: frames, to: target, stepped: &stepped)
        }
        // 새 t = 시계 테이크가 갈 프레임의 시작(프레임 단위로 깔끔한 값). 시계가 경계라 못 갔으면 그대로.
        if let masterTarget { currentTime = min(max(0, masterTarget - master.inPoint), range) }
        let newT = currentTime
        // Out에 멈춰 있던 테이크가 다시 구간 안으로 들어왔으면 정확히 세운다.
        for take in held where !take.isHeld(at: newT) {
            seekPlayer(of: take, toFrameContaining: take.absoluteTime(at: newT))
        }
        finishFrameMove(stepped)
    }

    /// 한 프레임 이동의 목표 = 지금 보여주는 프레임의 시작 ± frames. 자기 In~마지막 프레임(Out) 밖이면 nil(그 자리에 둔다).
    private func frameStepTarget(_ take: Take, frames: Int) -> Double? {
        let fd = take.frameDuration
        let target = take.frameStart(near: absoluteNow(take)) + fd * Double(frames)
        let inside = frames > 0
            ? target <= take.lastFrameStart + fd * 0.01
            : target >= take.inPoint - fd * 0.01
        return inside ? target : nil
    }

    /// 한 테이크를 `target`(프레임 시작) 프레임으로: 프레임 시작에 서 있으면 step(byCount:), 프레임 중간(정지·슬라이더 자리)이면
    /// 프레임 안쪽으로 허용 오차 0 seek. step(byCount:)는 프레임 중간에서 부르면 가장 가까운 프레임 시작으로 반올림한 뒤 움직여
    /// (실측: 10.5f에서 +1 → 12f, −1 → 10f) 2프레임을 가거나 제자리에 선다.
    private func moveOneFrame(_ take: Take, frames: Int, to target: Double, stepped: inout [(AVPlayer, CMTime)]) {
        guard let player = take.player, let item = player.currentItem else { return }
        let now = player.currentTime()
        if take.isOnFrameStart(now.seconds), frames > 0 ? item.canStepForward : item.canStepBackward {
            item.step(byCount: frames)
            stepped.append((player, now))
        } else {
            seekPlayer(of: take, toFrameContaining: target)
        }
    }

    /// step(byCount:)로 움직인 플레이어가 반영될 때까지 다음 이동을 묶어 둔다(seek은 seekFinished가 맡는다).
    private func finishFrameMove(_ stepped: [(AVPlayer, CMTime)]) {
        guard !stepped.isEmpty else { return }
        stepInFlight = true
        Task { [weak self] in
            await Self.waitUntilMoved(stepped)
            guard let self else { return }
            self.stepInFlight = false
            self.refreshPositions()
            self.runQueuedActions()
        }
    }

    /// fps가 섞였을 때의 공통 1프레임: **기준 테이크(master, 구간이 가장 긴 테이크)의 한 프레임만큼** 시간을 옮긴다.
    /// 테이크마다 자기 1프레임을 가면 24fps·30fps가 한 번에 8ms씩 벌어진다 — master만 한 프레임 가고,
    /// 나머지는 자기 In + t를 포함하는 자기 프레임에 선다.
    private func performMasterFrameStep(_ frames: Int) {
        guard let master = masterTake, let target = frameStepTarget(master, frames: frames) else { return }
        var stepped: [(AVPlayer, CMTime)] = []
        moveOneFrame(master, frames: frames, to: target, stepped: &stepped)
        currentTime = min(max(0, target - master.inPoint), range)
        let newT = currentTime
        for take in readyTakes where take !== master {
            seekPlayer(of: take, toFrameContaining: take.absoluteTime(at: newT))
        }
        finishFrameMove(stepped)
    }

    /// step(byCount:)는 비동기다(실측 약 2ms 뒤 currentTime() 반영). 모든 플레이어의 시각이 바뀌거나 시간이 다 될 때까지 기다린다.
    private static func waitUntilMoved(_ players: [(AVPlayer, CMTime)], timeout: Double = 0.5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if players.allSatisfy({ $0.0.currentTime() != $0.1 }) { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    func step(seconds: Double) {
        guard !isDiagnosing else { return }
        stopAllSolo(snap: false)
        if isPlaying { pause() }
        whenSettled { [weak self] in
            guard let self else { return }
            // 흩어져 있으면 각자 In(t = 0)에서 다시 줄 세워 1초
            self.seekAll(to: (self.isAligned ? self.currentTime : 0) + seconds)
        }
    }

    func goToStart() {
        guard !isDiagnosing else { return }
        if isPlaying { pause() }
        seekAll(to: 0)
    }

    func goToEnd() {
        guard !isDiagnosing else { return }
        if isPlaying { pause() }
        // 파일 끝 시각(range)이 아니라 마지막 프레임 시작으로 — 표시 시각과 보이는 프레임이 맞게(루프 끔 끝 도달과 동일)
        seekAll(to: lastFrameTime)
    }

    // MARK: - In/Out

    /// I/O·칸 조작 공통 준비(칸 지정): 그 칸을 선택하고, 재생을 멈추고, 이동이 끝난 뒤 그 테이크로 action을 부른다.
    private func withTake(_ index: Int, _ action: @escaping @MainActor (Take) -> Void) {
        guard !isDiagnosing else { return }
        guard index >= 0, index < takes.count, takes[index].isReady else {
            setStatus(String(localized: "테이크 \(index + 1)을(를) 쓸 수 없습니다"))
            return
        }
        let take = takes[index]
        if selectedIndex != index { select(index) }
        if isPlaying { pause() }
        // 이 칸만 재생 중이면 그 프레임에 세운 뒤 동작한다(다른 칸 재생은 그대로).
        stopSolo(take, snap: true)
        whenSettled { action(take) }
    }

    /// 키보드·메뉴용: 선택한 테이크로 `withTake`
    private func withSelectedTake(_ action: @escaping @MainActor (Take) -> Void) {
        guard !isDiagnosing else { return }
        guard selectedTake != nil else {
            setStatus(String(localized: "선택한 테이크가 없습니다 — 칸을 클릭하거나 숫자키로 고르세요"))
            return
        }
        withTake(selectedIndex, action)
    }

    /// 플레이어가 서 있는 절대 시각(이동이 끝난 뒤 부른다)
    private func absoluteNow(_ take: Take) -> Double {
        let seconds = take.playerTime?.seconds ?? .nan
        return seconds.isFinite ? seconds : take.position
    }

    /// I: 선택 테이크의 In = 그 테이크가 지금 보여주는 프레임(원본 기준 절대 시각). 다른 테이크·공통 t는 그대로.
    func markIn() {
        guard !rejectWhileScrubbing() else { return }
        withSelectedTake { [weak self] take in self?.performMarkIn(take) }
    }

    /// 칸 조작 줄 [In]
    func markIn(_ index: Int) {
        guard !rejectWhileScrubbing() else { return }
        withTake(index) { [weak self] take in self?.performMarkIn(take) }
    }

    /// 공통 슬라이더를 끄는 중이면 I/O를 받지 않고 안내한다.
    private func rejectWhileScrubbing() -> Bool {
        guard isScrubbing else { return false }
        setStatus(String(localized: "슬라이더를 끄는 중에는 In/Out을 찍지 않습니다 — 놓은 뒤 다시 누르세요"))
        return true
    }

    private func performMarkIn(_ take: Take) {
        // 플레이어는 프레임 안쪽에 서 있다 — In은 그 프레임의 시작 시각(k/fps)으로 적는다.
        let now = take.frameStart(near: absoluteNow(take))
        var note = ""
        if take.hasCustomOut, now >= take.outPoint - InOut.epsilon {
            // In이 Out과 같거나 뒤 — Out을 지운다(Out을 다시 찾으라는 뜻).
            note = " — " + String(localized: "Out(\(TimeFormat.clock(take.outPoint)))보다 뒤라 Out을 지웠습니다")
            take.outPoint = take.info?.duration ?? take.outPoint
        }
        take.inPoint = now
        inOutChanged()
        setStatus(String(localized: "테이크 \(take.index + 1) In = \(TimeFormat.clock(now))") + offsetNote(take) + note)
    }

    /// O: 선택 테이크의 Out = 그 테이크가 지금 보여주는 프레임. In이 없으면 In = 0(처음)으로 본다.
    func markOut() {
        guard !rejectWhileScrubbing() else { return }
        withSelectedTake { [weak self] take in self?.performMarkOut(take) }
    }

    /// 칸 조작 줄 [Out]
    func markOut(_ index: Int) {
        guard !rejectWhileScrubbing() else { return }
        withTake(index) { [weak self] take in self?.performMarkOut(take) }
    }

    private func performMarkOut(_ take: Take) {
        let now = take.frameStart(near: absoluteNow(take))
        // 손잡이 끌기와 같은 규칙: Out은 In보다 최소 1프레임 뒤. 같은 프레임이면 구간이 0이라 재생할 게 없다.
        guard now >= take.inPoint + take.frameDuration - InOut.epsilon else {
            setStatus(String(localized: "Out이 In(\(TimeFormat.clock(take.inPoint)))과 같거나 앞이라 무시했습니다 — 테이크 \(take.index + 1)"))
            return
        }
        take.outPoint = now
        inOutChanged()
        setStatus(String(localized: "테이크 \(take.index + 1) Out = \(TimeFormat.clock(now))"))
    }

    /// ⌥I
    func clearIn() {
        withSelectedTake { [weak self] take in self?.performClear(take, inPoint: true, outPoint: false) }
    }

    func clearIn(_ index: Int) {
        withTake(index) { [weak self] take in self?.performClear(take, inPoint: true, outPoint: false) }
    }

    /// ⌥O
    func clearOut() {
        withSelectedTake { [weak self] take in self?.performClear(take, inPoint: false, outPoint: true) }
    }

    func clearOut(_ index: Int) {
        withTake(index) { [weak self] take in self?.performClear(take, inPoint: false, outPoint: true) }
    }

    /// 칸 조작 줄 ↺: 그 테이크의 In/Out 둘 다 초기화
    func clearInOut(_ index: Int) {
        withTake(index) { [weak self] take in self?.performClear(take, inPoint: true, outPoint: true) }
    }

    /// In/Out 초기화. 표식만 지운다 — 화면은 그대로.
    private func performClear(_ take: Take, inPoint clearIn: Bool, outPoint clearOut: Bool) {
        if clearIn { take.inPoint = 0 }
        if clearOut { take.outPoint = take.info?.duration ?? take.outPoint }
        inOutChanged()
        switch (clearIn, clearOut) {
        case (true, true): setStatus(String(localized: "테이크 \(take.index + 1) In/Out 초기화"))
        case (true, false): setStatus(String(localized: "테이크 \(take.index + 1) In 초기화"))
        default: setStatus(String(localized: "테이크 \(take.index + 1) Out 초기화"))
        }
    }

    /// 보기 → 인·아웃 모두 초기화
    func clearAllInOut() {
        guard !isDiagnosing, hasTakes else { return }
        if isPlaying { pause() }
        stopAllSolo(snap: true)
        whenSettled { [weak self] in
            guard let self else { return }
            for take in self.readyTakes { take.resetInOut() }
            self.inOutChanged()
            self.setStatus(String(localized: "모든 테이크의 In/Out을 초기화했습니다"))
        }
    }

    /// In/Out이 바뀐 뒤: 시계 테이크를 다시 고르고 줄 선 상태인지 다시 본다. **아무 테이크도 옮기지 않는다.**
    private func inOutChanged() {
        rebindMaster()
        if currentTime > range { currentTime = range }
        updateAlignment()
    }

    /// 상태줄용 ` · 오프셋 +3f` (첫 테이크가 아니면)
    private func offsetNote(_ take: Take) -> String {
        guard take !== referenceTake else { return "" }
        let offset = offsetFrames(of: take)
        return " · " + String(localized: "오프셋 \(Self.signed(offset))f")
    }

    static func signed(_ n: Int) -> String {
        n > 0 ? "+\(n)" : "\(n)"
    }

    // MARK: - 테이크 하나만 탐색 (칸 조작 줄·⌥화살표)
    //
    // 그 테이크의 재생 위치만 옮긴다. In/Out은 건드리지 않고 다른 테이크도 그대로 — 줄이 흩어진다(isAligned = false).
    // 정렬은 In에서만 나온다: 공통 조작을 하면 모두 자기 In + t로 다시 줄 선다.

    /// ⌥← / ⌥→: 선택 테이크만 1프레임
    func moveSelected(frames: Int) {
        withSelectedTake { [weak self] take in self?.performMove(take, frames: frames) }
    }

    /// ⌥⇧← / ⌥⇧→: 선택 테이크만 1초
    func moveSelected(seconds: Double) {
        withSelectedTake { [weak self] take in self?.performMove(take, seconds: seconds) }
    }

    /// 칸 조작 줄 ◀ / ▶: 그 테이크만 1프레임
    func moveTake(_ index: Int, frames: Int) {
        withTake(index) { [weak self] take in self?.performMove(take, frames: frames) }
    }

    /// 칸 조작 줄 ◀◀ / ▶▶: 그 테이크만 1초
    func moveTake(_ index: Int, seconds: Double) {
        withTake(index) { [weak self] take in self?.performMove(take, seconds: seconds) }
    }

    /// 칸 조작 줄 |◀: 그 테이크의 In으로(In이 없으면 처음)
    func goToTakeIn(_ index: Int) {
        withTake(index) { [weak self] take in self?.performTakeSeek(take, toAbsolute: take.inPoint) }
    }

    /// 칸 조작 줄 ▶|: 그 테이크의 Out으로(Out이 없으면 마지막 프레임)
    func goToTakeOut(_ index: Int) {
        withTake(index) { [weak self] take in
            self?.performTakeSeek(take, toAbsolute: take.hasCustomOut ? take.outPoint : take.fileLastFrameStart)
        }
    }

    /// 칸 아래 바를 끌 때: 그 테이크만 원본 기준 `seconds`(그 프레임의 시작으로 맞춤)로.
    /// 끄는 중 쏟아지는 값은 앞 이동이 끝날 때까지 마지막 하나만 남긴다.
    func seekTake(_ index: Int, toAbsolute seconds: Double) {
        guard !isDiagnosing, index >= 0, index < takes.count, takes[index].isReady else { return }
        queueTakeSeek(index, toAbsolute: seconds, note: nil)
    }

    /// `seekTake` 본체: 그 칸을 고르고 재생을 멈춘 뒤, 앞 이동이 끝나면 마지막 목표 하나로만 간다.
    /// `note`가 있으면 이동 뒤 상태줄에 위치 대신 그 글을 띄운다(손잡이 끌기 — `테이크 2 In = …`).
    private func queueTakeSeek(_ index: Int, toAbsolute seconds: Double, note: String?) {
        if selectedIndex != index { select(index) }
        if isPlaying { pause() }
        stopSolo(takes[index], snap: false)
        let alreadyQueued = takeScrubTargets[index] != nil
        takeScrubTargets[index] = (seconds, note)
        guard !alreadyQueued else { return }
        whenSettled { [weak self] in
            guard let self, let target = self.takeScrubTargets.removeValue(forKey: index) else { return }
            guard index < self.takes.count else { return }
            self.performTakeSeek(self.takes[index], toAbsolute: target.seconds, note: target.note)
        }
    }

    // MARK: - 바 손잡이로 In/Out 끌기
    //
    // 칸 바의 In·Out 손잡이를 끌 때. 그 표식 하나만 바꾸고(위치 계산은 `frameStart(near:)`로 프레임 시작에 맞춤),
    // 그 테이크만 그 프레임으로 옮겨 보여준다(seekTake와 같은 큐 — 놓으면 그 자리에 머문다). 다른 테이크·다른 표식은 그대로.
    // In < Out을 지킨다(최소 1프레임). 넘으면 상대 표식 바로 옆에 붙어 멈춘다. 끝(처음·파일 끝)까지 끌면 표식 없음으로 돌아간다.

    /// In 손잡이: In = `seconds`가 든 프레임(최대 Out 프레임 − 1프레임). 0이면 In 없음(처음).
    func setIn(_ index: Int, to seconds: Double) {
        guard !isDiagnosing, !rejectWhileScrubbing(), index >= 0, index < takes.count, takes[index].isReady else { return }
        let take = takes[index]
        let fd = take.frameDuration
        // Out 프레임(Out이 없으면 원본 마지막 프레임)의 바로 앞 프레임까지
        let maxIn = take.lastFrameStart - fd
        guard maxIn > -fd * 0.5 else {
            setStatus(String(localized: "테이크 \(index + 1): Out이 첫 프레임이라 In을 옮길 수 없습니다"))
            return
        }
        let target = min(take.frameStart(near: seconds), take.frameStart(near: maxIn))
        if abs(target - take.inPoint) > InOut.epsilon {
            take.inPoint = target
            inOutChanged()
        }
        let note = target <= InOut.epsilon
            ? String(localized: "테이크 \(index + 1) In 없음 (처음부터)")
            : String(localized: "테이크 \(index + 1) In = \(TimeFormat.clock(target))") + offsetNote(take)
        queueTakeSeek(index, toAbsolute: target, note: note)
    }

    /// Out 손잡이: Out = `seconds`가 든 프레임(최소 In 프레임 + 1프레임). 원본 마지막 프레임이면 Out 없음(끝).
    func setOut(_ index: Int, to seconds: Double) {
        guard !isDiagnosing, !rejectWhileScrubbing(), index >= 0, index < takes.count, takes[index].isReady,
              let duration = takes[index].info?.duration else { return }
        let take = takes[index]
        let fd = take.frameDuration
        let last = take.fileLastFrameStart
        let minOut = take.frameStart(near: take.inPoint) + fd
        guard minOut <= last + fd * 0.5 else {
            setStatus(String(localized: "테이크 \(index + 1): In이 마지막 프레임이라 Out을 옮길 수 없습니다"))
            return
        }
        let target = max(take.frameStart(near: seconds), take.frameStart(near: minOut))
        // 원본 마지막 프레임 = Out 없음(파일 끝까지)
        let newOut = target >= last - InOut.epsilon ? duration : target
        if abs(newOut - take.outPoint) > InOut.epsilon {
            take.outPoint = newOut
            inOutChanged()
        }
        let note = newOut >= duration - InOut.epsilon
            ? String(localized: "테이크 \(index + 1) Out 없음 (끝까지)")
            : String(localized: "테이크 \(index + 1) Out = \(TimeFormat.clock(target))")
        queueTakeSeek(index, toAbsolute: target, note: note)
    }

    /// 칸 아래 바를 잡을 때: 그 칸을 고르고 재생을 멈춘다. 놓을 때는 아무것도 하지 않는다(그 자리에 둔다).
    func takeScrubbing(_ index: Int, began: Bool) {
        guard began, !isDiagnosing, index >= 0, index < takes.count, takes[index].isReady else { return }
        if selectedIndex != index { select(index) }
        if isPlaying { pause() }
        stopSolo(takes[index], snap: false)
    }

    private func performMove(_ take: Take, frames: Int) {
        guard frames != 0, take.player != nil else { return }
        let fd = take.frameDuration
        // 지금 보여주는 프레임의 시작 ± frames (프레임 중간에 서 있어도 정확히 frames만큼)
        let target = take.frameStart(near: absoluteNow(take)) + fd * Double(frames)
        guard target >= -fd * 0.01, target <= take.fileLastFrameStart + fd * 0.01 else {
            setStatus(edgeNote(take, forward: frames > 0))
            return
        }
        scatter()
        var stepped: [(AVPlayer, CMTime)] = []
        moveOneFrame(take, frames: frames, to: target, stepped: &stepped)
        finishFrameMove(stepped)
        setStatus(positionNote(take, at: take.frameStart(near: target)))
    }

    private func performMove(_ take: Take, seconds: Double) {
        let now = absoluteNow(take)
        let target = take.frameStart(near: now + seconds)
        guard abs(target - take.frameStart(near: now)) > InOut.epsilon else {
            setStatus(edgeNote(take, forward: seconds > 0))
            return
        }
        scatter()
        seekPlayer(of: take, toFrameContaining: target)
        setStatus(positionNote(take, at: target))
    }

    private func performTakeSeek(_ take: Take, toAbsolute seconds: Double, note: String? = nil) {
        let target = take.frameStart(near: seconds)
        if abs(target - take.frameStart(near: absoluteNow(take))) > InOut.epsilon {
            scatter()
            seekPlayer(of: take, toFrameContaining: target)
        }
        setStatus(note ?? positionNote(take, at: target))
    }

    /// `테이크 2 위치 00:00.21 (5f)` — 원본 기준
    private func positionNote(_ take: Take, at seconds: Double) -> String {
        let frame = Int((seconds / take.frameDuration + 1e-6).rounded(.down))
        return String(localized: "테이크 \(take.index + 1) 위치 \(TimeFormat.clock(seconds)) (\(frame)f)")
    }

    private func edgeNote(_ take: Take, forward: Bool) -> String {
        forward
            ? String(localized: "테이크 \(take.index + 1): 이미 마지막 프레임입니다")
            : String(localized: "테이크 \(take.index + 1): 이미 처음입니다")
    }

    /// 칸 조작 줄 🔊: 이 테이크 소리만 켠다(하나만). 전체 음소거 중이면 푼다.
    func soundOn(_ index: Int) {
        guard index >= 0, index < takes.count else { return }
        selectedIndex = index
        isMuted = false
        applyAudio()
        setStatus(String(localized: "테이크 \(index + 1) 소리"))
    }

    // MARK: - 테이크 하나만 재생 (칸 조작 줄 ▶/❚❚)
    //
    // 그 테이크만 지금 위치에서 재생한다. 다른 테이크는 그대로(각자 칸 ▶로 따로 돌 수도 있다) — 줄이 흩어진다.
    // Out이 있으면 Out 프레임에서(forwardPlaybackEndTime), 없으면 파일 끝에서 멈춘다. 루프가 켜져 있으면 In~Out을 그 테이크만 반복한다.
    // 소리는 🔊가 그 테이크에 있을 때만(선택을 바꾸지 않는다).

    /// 칸 ▶로 도는 테이크가 하나라도 있는가
    var isAnySoloPlaying: Bool { takes.contains(where: \.isSoloPlaying) }

    /// 칸 조작 줄 ▶/❚❚
    func togglePlayTake(_ index: Int) {
        guard !isDiagnosing, index >= 0, index < takes.count, takes[index].isReady else { return }
        let take = takes[index]
        guard take.isSoloPlaying || !isLoading else {
            setStatus(String(localized: "불러오는 중…"))
            return
        }
        if take.isSoloPlaying {
            stopSolo(take, snap: true)
            setStatus(positionNote(take, at: take.frameStart(near: absoluteNow(take))))
            return
        }
        if isPlaying {
            // 공통 재생을 멈추고 이 테이크만 계속 간다. 다른 테이크는 지금 보이는 프레임에 세운다(줄을 다시 세우지 않는다).
            isPlaying = false
            for other in readyTakes where other !== take {
                other.player?.pause()
                seekPlayer(of: other, toFrameContaining: absoluteNow(other))
            }
            scatter()
            if let player = take.player, player.rate != 0, absoluteNow(take) < soloEnd(take) - take.frameDuration * 0.5 {
                beginSolo(take)   // 이미 도는 중 — 그대로 이어 간다
                setStatus(String(localized: "테이크 \(index + 1)만 재생"))
                return
            }
        }
        whenSettled { [weak self] in self?.playTake(take) }
    }

    /// 칸 ▶ 재생이 멈출 자리: Out이 있으면 Out, 없으면 마지막 프레임
    private func soloEnd(_ take: Take) -> Double {
        take.hasCustomOut ? take.frameStart(near: take.outPoint) : take.fileLastFrameStart
    }

    private func playTake(_ take: Take) {
        // 기다리는 사이 공통 재생이 시작됐으면 공통 쪽을 따른다.
        guard !isDiagnosing, !isPlaying, take.isReady, !take.isSoloPlaying, let player = take.player else { return }
        let fd = take.frameDuration
        guard soloEnd(take) - take.inPoint >= fd * 0.5 else {
            setStatus(String(localized: "테이크 \(take.index + 1): In~Out 구간이 1프레임보다 짧아 재생할 수 없습니다"))
            return
        }
        scatter()
        beginSolo(take)
        if absoluteNow(take) >= soloEnd(take) - fd * 0.5 {
            // Out(없으면 끝)에 있거나 넘었다 — In(없으면 처음)부터
            restartSolo(take)
        } else {
            player.play()
        }
        setStatus(String(localized: "테이크 \(take.index + 1)만 재생"))
    }

    /// In(없으면 처음)으로 정확히 옮긴 뒤 다시 재생
    private func restartSolo(_ take: Take) {
        take.player?.pause()
        let start = TimeFormat.cmTime(take.seekTarget(forFrameContaining: take.inPoint))
        take.player?.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak take] finished in
            Task { @MainActor in
                guard finished, let take, take.isSoloPlaying else { return }
                take.player?.play()
            }
        }
    }

    /// 솔로 상태로 표시하고 위치 갱신·끝 감지 관찰자를 건다.
    private func beginSolo(_ take: Take) {
        guard let player = take.player else { return }
        let index = take.index
        removeSoloObservers(index)
        take.isSoloPlaying = true
        let time = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, index < self.takes.count else { return }
                let take = self.takes[index]
                guard take.isSoloPlaying, let seconds = take.playerTime?.seconds, seconds.isFinite else { return }
                take.position = take.frameStart(near: seconds)
            }
        }
        let end = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.soloDidReachEnd(index) }
        }
        soloObservers[index] = (player, time, end)
    }

    /// Out(forwardPlaybackEndTime) 또는 파일 끝에 닿았다: 루프면 In부터 다시, 아니면 그 프레임에 멈춘다.
    private func soloDidReachEnd(_ index: Int) {
        guard index < takes.count else { return }
        let take = takes[index]
        guard take.isSoloPlaying else { return }
        if loopEnabled {
            restartSolo(take)
            return
        }
        stopSolo(take, snap: false)
        let end = soloEnd(take)
        seekPlayer(of: take, toFrameContaining: end)
        setStatus(positionNote(take, at: end))
    }

    /// 그 테이크의 칸 ▶ 재생을 멈춘다. `snap`이면 지금 보이는 프레임의 시작에 정확히 세운다(뒤이은 In/Out·저장이 프레임 단위로 맞게).
    private func stopSolo(_ take: Take, snap: Bool) {
        guard take.isSoloPlaying else { return }
        take.isSoloPlaying = false
        removeSoloObservers(take.index)
        take.player?.pause()
        if snap {
            seekPlayer(of: take, toFrameContaining: absoluteNow(take))
        } else {
            refreshPositions()
        }
    }

    private func stopAllSolo(snap: Bool) {
        for take in takes where take.isSoloPlaying { stopSolo(take, snap: snap) }
    }

    private func removeSoloObservers(_ index: Int) {
        guard let entry = soloObservers.removeValue(forKey: index) else { return }
        entry.player.removeTimeObserver(entry.time)
        NotificationCenter.default.removeObserver(entry.end)
    }

    // MARK: - 프레임 이동 자가진단

    /// 보기 → 프레임 이동 자가진단: 모든 테이크를 step(byCount:)로 ±1프레임 10회 왕복하며
    /// currentTime() 변화량이 정확히 1/fps인지 본다. 끝나면 원래 자리로 되돌린다.
    func runStepSelfTest() {
        guard !isDiagnosing, !readyTakes.isEmpty else { return }
        if isPlaying { pause() }
        stopAllSolo(snap: true)
        // 부르는 즉시 켠다 — 앞선 이동이 끝나길 기다리는 사이에 들어온 키 입력이 큐에 쌓였다가 진단 도중에 실행되지 않게.
        isDiagnosing = true
        setStatus(String(localized: "프레임 이동 자가진단 중…"))
        whenSettled { [weak self] in
            guard let self else { return }
            let t = self.currentTime
            let wasAligned = self.isAligned
            let positions = self.readyTakes.map { ($0, self.absoluteNow($0)) }
            Task { [weak self] in
                guard let self else { return }
                let result = self.hasMixedFps
                    ? await self.selfTestMasterRoundTrips(10)
                    : await self.selfTestRoundTrips(10)
                self.isDiagnosing = false
                if wasAligned {
                    self.seekAll(to: t)
                } else {
                    // 흩어진 채였으면 각 테이크를 원래 자리로
                    for (take, seconds) in positions { self.seekPlayer(of: take, toAbsolute: seconds) }
                }
                self.setStatus(result)
            }
        }
    }

    private func selfTestRoundTrips(_ count: Int) async -> String {
        struct Probe { let take: Take; let player: AVPlayer; let item: AVPlayerItem; let direction: Int }
        let probes: [Probe] = readyTakes.compactMap { take in
            guard let player = take.player, let item = player.currentItem, let info = take.info else { return nil }
            let now = player.currentTime().seconds
            // 끝 프레임 근처면 뒤로 먼저 간다.
            let direction = now + 2 * take.frameDuration < info.duration ? 1 : -1
            return Probe(take: take, player: player, item: item, direction: direction)
        }
        // 프레임 중간에서 step(byCount:)하면 **가장 가까운 프레임 시작으로 반올림한 뒤** ±1프레임 간다 — Δ가 1/fps가 아니다
        // (실측 2026-11-07: 10.5f에서 +1 → 12f(Δ 1.5f), −1 → 10f(Δ −0.5f). 앱이 세우는 프레임 안쪽 k+¼에서는 +1 → k+1(Δ 0.75f)).
        // 측정 전에 한 번 갔다 와서(+1·−1, 끝 근처면 −1·+1) 프레임 시작(파일의 실제 pts)에 세운다.
        for leg in [1, -1] {
            let before = probes.map { $0.player.currentTime() }
            for probe in probes { probe.item.step(byCount: probe.direction * leg) }
            await Self.waitUntilMoved(Array(zip(probes.map(\.player), before)))
        }
        var exact = 0
        var failures: [String] = []
        for trip in 1...count {
            var tripOK = true
            for leg in [1, -1] {
                let before = probes.map { $0.player.currentTime() }
                for probe in probes { probe.item.step(byCount: probe.direction * leg) }
                await Self.waitUntilMoved(Array(zip(probes.map(\.player), before)))
                for (probe, start) in zip(probes, before) {
                    let delta = (probe.player.currentTime() - start).seconds
                    let expected = probe.take.frameDuration * Double(probe.direction * leg)
                    let ok = abs(delta - expected) < probe.take.frameDuration * 0.01
                    log.info("selftest trip \(trip) take \(probe.take.index + 1): Δ=\(delta, format: .fixed(precision: 6)) 기대 \(expected, format: .fixed(precision: 6)) \(ok ? "OK" : "FAIL")")
                    if !ok {
                        tripOK = false
                        if failures.count < 3 {
                            failures.append(String(format: "T%d Δ%.4f≠%.4f", probe.take.index + 1, delta, expected))
                        }
                    }
                }
            }
            if tripOK { exact += 1 }
        }
        let summary = String(localized: "프레임 이동 자가진단: \(exact)/\(count) 정확 (테이크 \(probes.count)개 × ±1프레임 왕복 \(count)회)")
        return failures.isEmpty ? summary : summary + " — " + failures.joined(separator: ", ")
    }

    /// fps가 섞였을 때의 자가진단(공통 1프레임과 같은 방식): master는 step(byCount:)로 ±1프레임 — 변화량이 1/fps_master인지,
    /// 나머지는 자기 In + t로 seek — `|t_i − (In_i + t)| < 자기 프레임 길이`인지 본다.
    private func selfTestMasterRoundTrips(_ count: Int) async -> String {
        guard let master = masterTake, let mPlayer = master.player, let mItem = mPlayer.currentItem, let info = master.info else {
            return String(localized: "프레임 이동 자가진단: 기준 테이크가 없습니다")
        }
        let others: [(Take, AVPlayer)] = readyTakes.compactMap { take in
            guard take !== master, let player = take.player else { return nil }
            return (take, player)
        }
        let direction = mPlayer.currentTime().seconds + 2 * master.frameDuration < min(info.duration, master.outPoint) ? 1 : -1

        /// master를 한 프레임 옮기고 나머지를 In + t로 세운 뒤 (master 변화량, 나머지 오차들)을 돌려준다.
        func leg(_ frames: Int) async -> (delta: Double, errors: [(Take, Double)]) {
            let before = mPlayer.currentTime()
            mItem.step(byCount: frames)
            await Self.waitUntilMoved([(mPlayer, before)])
            let after = mPlayer.currentTime()
            let t = after.seconds - master.inPoint
            for (take, player) in others {
                // 앱의 공통 1프레임과 같은 자리(자기 In + t가 든 자기 프레임 안쪽)
                await Self.seekExactly(player, to: TimeFormat.cmTime(take.seekTarget(forFrameContaining: take.absoluteTime(at: t))))
            }
            let errors = others.map { take, player in (take, abs(player.currentTime().seconds - take.absoluteTime(at: t))) }
            return ((after - before).seconds, errors)
        }

        _ = await leg(direction)       // 프레임 시작에 세운다(프레임 중간에서 step하면 반올림돼 Δ가 1/fps가 아니다)
        _ = await leg(-direction)
        var exact = 0
        var failures: [String] = []
        for trip in 1...count {
            var tripOK = true
            for sign in [1, -1] {
                let (delta, errors) = await leg(direction * sign)
                let expected = master.frameDuration * Double(direction * sign)
                var ok = abs(delta - expected) < master.frameDuration * 0.01
                log.info("selftest(master) trip \(trip) take \(master.index + 1): Δ=\(delta, format: .fixed(precision: 6)) 기대 \(expected, format: .fixed(precision: 6)) \(ok ? "OK" : "FAIL")")
                if !ok, failures.count < 3 {
                    failures.append(String(format: "T%d Δ%.4f≠%.4f", master.index + 1, delta, expected))
                }
                for (take, error) in errors where error >= take.frameDuration {
                    ok = false
                    if failures.count < 3 { failures.append(String(format: "T%d 오차 %.4f", take.index + 1, error)) }
                }
                if !ok { tripOK = false }
            }
            if tripOK { exact += 1 }
        }
        let summary = String(localized: "프레임 이동 자가진단: \(exact)/\(count) 정확 (fps 섞임 — 테이크 \(master.index + 1) 기준 ±1프레임 왕복 \(count)회, 나머지 \(others.count)개는 In + t)")
        return failures.isEmpty ? summary : summary + " — " + failures.joined(separator: ", ")
    }

    /// 허용 오차 0 seek이 끝날 때까지 기다린다.
    private static func seekExactly(_ player: AVPlayer, to time: CMTime) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in continuation.resume() }
        }
    }

    // MARK: - 보기·소리

    /// 숫자키: 그 테이크만 창 전체로. 같은 키를 다시 누르면 격자로.
    func toggleSolo(_ index: Int) {
        guard index < takes.count, takes[index].isReady else { return }
        if soloIndex == index {
            viewMode = .grid
        } else {
            viewMode = .solo(index)
            select(index)
        }
    }

    /// 툴바 단독: 선택한 테이크만 크게
    func showSoloSelected() {
        guard selectedIndex < takes.count, takes[selectedIndex].isReady else { return }
        viewMode = .solo(selectedIndex)
    }

    func showGrid() {
        viewMode = .grid
    }

    // MARK: - 겹쳐 보기 (갈라보기·겹치기)

    /// 겹쳐 볼 수 있는가(정상 테이크 2개 이상)
    var canOverlay: Bool { readyTakes.count >= 2 }

    /// 툴바 갈라보기·겹치기: 그 방식으로 겹쳐 본다. A = 선택한 테이크, B = A의 다음 번호(없으면 이전).
    /// 이미 겹쳐 보는 중이면 A·B는 그대로 두고 방식만 바꾼다.
    func showOverlay(_ style: OverlayStyle) {
        guard canOverlay else {
            setStatus(String(localized: "겹쳐 보려면 열린 테이크가 2개 이상 필요합니다"))
            return
        }
        overlayStyle = style
        guard overlayPair == nil else { return }
        let a = takes.indices.contains(selectedIndex) && takes[selectedIndex].isReady ? selectedIndex : readyTakes[0].index
        guard let b = defaultPartner(of: a) else { return }
        overlayZoom = .fit
        overlayPan = .zero
        viewMode = .overlay(a: a, b: b)
        if selectedIndex != a { select(a) }
    }

    /// `\`·`⇧\`: 같은 방식으로 겹쳐 보는 중이면 격자로, 아니면 그 방식으로 겹쳐 본다.
    func toggleOverlay(_ style: OverlayStyle) {
        if isOverlay, overlayStyle == style {
            viewMode = .grid
        } else {
            showOverlay(style)
        }
    }

    /// A의 짝: A 다음 번호의 정상 테이크, 없으면 A 이전 번호 중 가장 가까운 것
    func defaultPartner(of a: Int) -> Int? {
        let ready = readyTakes.map(\.index).filter { $0 != a }
        return ready.first { $0 > a } ?? ready.last { $0 < a }
    }

    /// 겹침 바 A 팝업. B와 같은 테이크를 고르면 A·B를 맞바꾼다. A가 선택 테이크가 된다(소리).
    func setOverlayA(_ index: Int) {
        guard let pair = overlayPair, takes.indices.contains(index), takes[index].isReady, index != pair.a else { return }
        viewMode = .overlay(a: index, b: index == pair.b ? pair.a : pair.b)
        select(index)
    }

    /// 겹침 바 B 팝업. A와 같은 테이크를 고르면 맞바꾼다.
    func setOverlayB(_ index: Int) {
        guard let pair = overlayPair, takes.indices.contains(index), takes[index].isReady, index != pair.b else { return }
        viewMode = .overlay(a: index == pair.a ? pair.b : pair.a, b: index)
    }

    /// ⇄: A·B 뒤집기(선 왼쪽·아래 ↔ 선 오른쪽·위)
    func flipOverlay() {
        guard let pair = overlayPair else { return }
        viewMode = .overlay(a: pair.b, b: pair.a)
    }

    func setWipePosition(_ position: Double) {
        wipePosition = min(max(0, position), 1)
    }

    /// `[` `]`: 갈라보기면 선을, 겹치기면 투명도를 `delta`(0~1)만큼
    func nudgeOverlay(by delta: Double) {
        guard isOverlay else { return }
        switch overlayStyle {
        case .wipe: setWipePosition(wipePosition + delta)
        case .blend: setBlendOpacity(blendOpacity + delta)
        }
    }

    func setBlendOpacity(_ opacity: Double) {
        blendOpacity = min(max(0, opacity), 1)
    }

    func setOverlayZoom(_ zoom: OverlayZoom) {
        overlayZoom = zoom
        overlayPan = .zero
    }

    func select(_ index: Int) {
        guard index < takes.count else { return }
        selectedIndex = index
        applyAudio()
    }

    /// 보기 → 바 위 썸네일 미리보기 (T)
    func toggleBarThumbnails() {
        setBarThumbnails(!showBarThumbnails)
    }

    func setBarThumbnails(_ on: Bool) {
        showBarThumbnails = on
        UserDefaults.standard.set(on, forKey: Self.barThumbnailsKey)
        // 끄는 순간 기다리던 생성 요청은 버린다(이미 만든 캐시는 그대로 두고, 끈 동안은 새로 만들지 않는다).
        if !on { for take in takes { take.existingThumbnails?.cancelPending() } }
        setStatus(on ? String(localized: "바 위 썸네일 미리보기 켬 (T)") : String(localized: "바 위 썸네일 미리보기 끔 (T)"))
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

    /// 지금 보이는 프레임을 PNG로. `onlySelected`면 선택한 테이크 한 장만.
    /// 저장 직전 각 플레이어의 `currentTime()`을 그대로 넘긴다. 파일명은 그 테이크의 원본 기준 절대 시각(보여주는 프레임의 시작).
    func saveFrames(onlySelected: Bool) {
        guard !isDiagnosing else { return }
        if isPlaying { pause() }
        stopAllSolo(snap: true)
        guard let first = takes.first else {
            setStatus(String(localized: "저장할 테이크가 없습니다"))
            return
        }
        let targets = onlySelected ? takes.filter { $0.index == selectedIndex && $0.isReady } : readyTakes
        guard !targets.isEmpty else {
            setStatus(String(localized: "저장할 수 있는 테이크가 없습니다"))
            return
        }
        let folder = FrameExporter.framesFolder(besides: first.url)
        setStatus(String(localized: "프레임 저장 중…"))
        whenSettled { [weak self] in
            guard let self else { return }
            let t = self.currentTime
            let jobs = targets.map { take in
                let time = take.playerTime ?? TimeFormat.cmTime(take.seekTarget(forFrameContaining: take.absoluteTime(at: t)))
                // 뽑기는 플레이어 시각 그대로(이미 그 프레임 안쪽), 파일명은 그 프레임의 시작 시각
                return (source: take.url, time: time, nameSeconds: take.frameStart(near: time.seconds))
            }
            Task { await self.export(jobs, to: folder) }
        }
    }

    private func export(_ jobs: [(source: URL, time: CMTime, nameSeconds: Double)], to folder: URL) async {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            setStatus(String(localized: "저장 폴더를 만들 수 없습니다: \(error.localizedDescription)"))
            return
        }
        var saved: [URL] = []
        var failures: [String] = []
        for job in jobs {
            let dest = FrameExporter.destination(for: job.source, seconds: job.nameSeconds, in: folder)
            do {
                try await FrameExporter.exportFrame(from: job.source, at: job.time, to: dest)
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
