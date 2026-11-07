import AppKit
import SwiftUI

/// 테이크 한 칸: 위 라벨 + 영상 + 아래 조작 줄(그 테이크만 움직이는 버튼들과 자기 타임라인 바). 선택된 칸은 테두리 강조.
struct TakeCell: View {
    let take: Take
    let model: CompareModel

    private var index: Int { take.index }
    private var isSelected: Bool { model.selectedIndex == index }

    var body: some View {
        VStack(spacing: 4) {
            label
            ZStack {
                Color.black
                switch take.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .ready:
                    PlayerSurface(player: take.player)
                case .failed(let reason):
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                        Text("열 수 없음")
                            .font(.headline)
                        Text(verbatim: reason)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .contentShape(Rectangle())
            .onTapGesture { model.select(index) }
            if take.isReady {
                TakeStrip(take: take, model: model)
                    .zIndex(1) // 바 호버 썸네일이 위 칸 영상(AVPlayerView) 뒤로 들어가지 않게
            }
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(index + 1)")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
            Text(verbatim: take.fileName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            if let info = take.info {
                TakeDetails(info: info, mixedFps: model.hasMixedFps)
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .onTapGesture { model.select(index) }
    }
}

/// `· 1920×1080 · 24fps · 4.00s` (파일명 뒤에 붙는다). 테이크끼리 fps가 다르면 fps를 노란 배지로.
struct TakeDetails: View {
    let info: TakeInfo
    let mixedFps: Bool

    var body: some View {
        let fps = abs(info.fps - info.fps.rounded()) < 0.01
            ? String(format: "%.0f", info.fps)
            : String(format: "%.3f", info.fps)
        HStack(spacing: 0) {
            Text(verbatim: String(format: "· %.0f×%.0f · ", info.size.width, info.size.height))
            Text(verbatim: "\(fps)fps")
                .foregroundStyle(mixedFps ? Color.black : Color.secondary)
                .padding(.horizontal, mixedFps ? 3 : 0)
                .background(RoundedRectangle(cornerRadius: 3).fill(mixedFps ? Color.yellow : Color.clear))
                .help(mixedFps ? String(localized: "테이크끼리 fps가 다릅니다 — 공통 1프레임은 기준 테이크(구간이 가장 긴 테이크)의 한 프레임") : "")
            Text(verbatim: String(format: " · %.2fs", info.duration))
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

// MARK: - 칸 조작 줄

/// 영상 바로 아래 조작 줄. 이동 버튼·바는 **이 테이크의 재생 위치만** 옮긴다(In/Out·다른 테이크는 그대로 — 자유 탐색).
/// 누르면 이 칸이 선택된다. 줄은 공통 조작(재생·슬라이더·← →)을 하면 각자 In 기준으로 다시 선다.
///
///     ▶ [00:01.25]  |◀ ◀◀ ◀ ▶ ▶▶ ▶|   [In 00:00.50] +3f [Out 00:03.20] ↺   🔊 ⤢   (맨 앞 ▶/❚❚ = 이 테이크만 재생/정지)
///     ─────────▐║║▌■■■■■■■■■■■■■|■■■▐║║▌─────────   ← 자기 타임라인 바(끌어서 스크럽, 양 끝 손잡이를 끌면 In/Out)
struct TakeStrip: View {
    let take: Take
    let model: CompareModel

    private var index: Int { take.index }
    private var disabled: Bool { model.isDiagnosing }

    var body: some View {
        VStack(spacing: 5) {
            buttonRow
            if let info = take.info {
                TakeBar(
                    duration: info.duration,
                    inPoint: take.inPoint,
                    outPoint: take.outPoint,
                    position: take.position,
                    hasCustomIn: take.hasCustomIn,
                    hasCustomOut: take.hasCustomOut,
                    // 썸네일을 끄면 캐시를 넘기지 않는다 — 말풍선·생성 요청·캐시 모두 없음
                    thumbnails: model.showBarThumbnails ? take.thumbnails : nil,
                    aspect: info.size.height > 0 ? info.size.width / info.size.height : 16 / 9,
                    onScrub: { phase in
                        switch phase {
                        case .began: model.takeScrubbing(index, began: true)
                        case .moved(let seconds): model.seekTake(index, toAbsolute: seconds)
                        case .ended: model.takeScrubbing(index, began: false)
                        }
                    },
                    onTrim: { handle, phase in
                        switch phase {
                        case .began: model.takeScrubbing(index, began: true)
                        case .moved(let seconds):
                            switch handle {
                            case .inPoint: model.setIn(index, to: seconds)
                            case .outPoint: model.setOut(index, to: seconds)
                            }
                        case .ended: model.takeScrubbing(index, began: false)
                        }
                    }
                )
                .disabled(disabled)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .frame(height: 56)
    }

    private var buttonRow: some View {
        HStack(spacing: 2) {
            // 이 테이크의 절대 시각(원본 기준)
            Text(verbatim: TimeFormat.clock(take.position))
                .font(.system(.callout, design: .monospaced))
                .monospacedDigit()
                .help(String(localized: "이 테이크의 시각 (원본 기준)"))
                .padding(.trailing, 6)
                .fixedSize()

            stripButton("backward.end", String(localized: "이 테이크 In으로 (In이 없으면 처음)")) { model.goToTakeIn(index) }
            stripButton("backward", String(localized: "이 테이크 위치만 1초 뒤로 (⌥⇧←)")) { model.moveTake(index, seconds: -1) }
            stripButton("backward.frame", String(localized: "이 테이크 위치만 1프레임 뒤로 — 길게 누르면 반복 (⌥←)"), repeats: true) { model.moveTake(index, frames: -1) }
            // 이 테이크만 재생/정지 (다른 테이크는 그대로)
            stripButton(take.isSoloPlaying ? "pause.fill" : "play.fill",
                        String(localized: "이 테이크만 재생/정지"),
                        highlighted: take.isSoloPlaying) { model.togglePlayTake(index) }

            stripButton("forward.frame", String(localized: "이 테이크 위치만 1프레임 앞으로 — 길게 누르면 반복 (⌥→)"), repeats: true) { model.moveTake(index, frames: 1) }
            stripButton("forward", String(localized: "이 테이크 위치만 1초 앞으로 (⌥⇧→)")) { model.moveTake(index, seconds: 1) }
            stripButton("forward.end", String(localized: "이 테이크 Out으로 (Out이 없으면 끝)")) { model.goToTakeOut(index) }

            Spacer(minLength: 8)

            inOutButton(
                title: "In",
                value: take.hasCustomIn ? TimeFormat.clock(take.inPoint) : nil,
                help: String(localized: "이 테이크가 지금 보여주는 프레임을 In으로 (I) — 공통 재생은 각자 In부터 같이 간다")
            ) { model.markIn(index) }
            let offset = model.offsetFrames(of: take)
            if offset != 0 {
                Text(verbatim: "\(CompareModel.signed(offset))f")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help(String(localized: "첫 테이크 기준 In 오프셋(프레임)"))
                    .fixedSize()
            }
            inOutButton(
                title: "Out",
                value: take.hasCustomOut ? TimeFormat.clock(take.outPoint) : nil,
                help: String(localized: "이 테이크가 지금 보여주는 프레임을 Out으로 (O)")
            ) { model.markOut(index) }
            stripButton("arrow.counterclockwise", String(localized: "이 테이크 In/Out 초기화 (⌥I · ⌥O)")) { model.clearInOut(index) }
                .disabled(disabled || !(take.hasCustomIn || take.hasCustomOut))

            Spacer(minLength: 8)

            let soundOn = model.selectedIndex == index && !model.isMuted
            stripButton(soundOn ? "speaker.wave.2.fill" : "speaker.wave.2",
                        soundOn ? String(localized: "이 테이크의 소리가 납니다") : String(localized: "이 테이크 소리 켜기 (하나만)"),
                        highlighted: soundOn) { model.soundOn(index) }
            let isSolo = model.soloIndex == index
            stripButton("arrow.up.left.and.arrow.down.right",
                        isSolo ? String(localized: "격자로 돌아가기 (\(index + 1) 또는 Esc)") : String(localized: "이 테이크만 크게 보기 (\(index + 1))"),
                        highlighted: isSolo) { model.toggleSolo(index) }
        }
        .frame(height: 24)
    }

    private func stripButton(
        _ symbol: String,
        _ help: String,
        repeats: Bool = false,
        highlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: repeats ? {} : action) {
            Image(systemName: symbol)
                .imageScale(.small)
                .frame(width: 22, height: 20)
        }
        .buttonStyle(StripButtonStyle(highlighted: highlighted, onPress: repeats ? action : nil))
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(Text(verbatim: help))
        .disabled(disabled)
        return Group {
            if repeats {
                // 반복 버튼은 마우스 '누름'에 반응하므로, 접근성·자동화의 AXPress에도 한 번 동작하게 한다.
                button.accessibilityAction { action() }
            } else {
                button
            }
        }
    }

    /// `[ In 00:00.50 ]` / 미설정이면 `[ In — ]`
    private func inOutButton(title: String, value: String?, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(verbatim: title)
                    .fontWeight(.semibold)
                Text(verbatim: value ?? "—")
                    .foregroundStyle(value == nil ? Color.secondary : Color.primary)
            }
            .font(.system(.caption, design: .monospaced))
            .fixedSize()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
        .disabled(disabled)
    }
}

/// 조작 줄 아이콘 버튼. `onPress`가 있으면 누르는 순간 한 번, 0.4초 뒤부터 초당 8회 반복한다(놓으면 멈춤).
struct StripButtonStyle: ButtonStyle {
    var highlighted = false
    var onPress: (() -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        StripButtonBody(configuration: configuration, highlighted: highlighted, onPress: onPress)
    }
}

private struct StripButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let highlighted: Bool
    let onPress: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        configuration.label
            .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.18 : (isHovering ? 0.08 : 0)))
            )
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onChange(of: configuration.isPressed) { _, pressed in
                guard let onPress else { return }
                repeatTask?.cancel()
                repeatTask = nil
                guard pressed else { return }
                onPress()
                repeatTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    while !Task.isCancelled {
                        onPress()
                        try? await Task.sleep(for: .milliseconds(125))
                    }
                }
            }
            .onDisappear {
                repeatTask?.cancel()
                repeatTask = nil
            }
    }
}

/// 칸 아래 자기 타임라인 바: 전체 길이 대비 In~Out 구간(강조색), 바깥은 흐리게, 현재 위치는 세로선. 끌어서 이 테이크만 스크럽.
/// In~Out 양 끝에는 트림 손잡이(세로 줄무늬 2줄)가 있어 끌면 그 표식만 옮긴다 — 손잡이가 바 스크럽보다 우선.
///
///     ░░░░░░░▐║║▌████████|██████▐║║▌░░░░░░   ← ▐║║▌ = In·Out 손잡이(바보다 위아래 3pt 큼), 미설정이면 바 양 끝에 흐리게
struct TakeBar: View {
    enum ScrubPhase {
        case began
        case moved(Double)
        case ended
    }

    enum Handle {
        case inPoint
        case outPoint
    }

    let duration: Double
    let inPoint: Double
    let outPoint: Double
    let position: Double
    /// In·Out이 설정돼 있는가(미설정이면 손잡이를 흐리게)
    var hasCustomIn = false
    var hasCustomOut = false
    /// 호버 썸네일(없으면 말풍선 없음 — 보기 → 바 위 썸네일 미리보기를 끄면 nil)
    var thumbnails: ThumbnailCache?
    /// 영상 가로/세로
    var aspect: Double = 16 / 9
    let onScrub: (ScrubPhase) -> Void
    /// 손잡이 끌기(없으면 손잡이를 그리지 않는다). `.moved`의 값은 원본 기준 초.
    var onTrim: ((Handle, ScrubPhase) -> Void)?

    /// 바 두께
    static let barHeight: CGFloat = 10
    /// 손잡이: 폭 8pt, 바보다 위아래 3pt씩 크다
    static let handleWidth: CGFloat = 8
    static let handleOverhang: CGFloat = 3
    /// 손잡이 히트 영역은 그린 것보다 좌우 4pt 넓다
    static let handleSlop: CGFloat = 4
    /// 뷰 전체 높이(손잡이 높이)
    static var height: CGFloat { barHeight + handleOverhang * 2 }

    private enum DragMode {
        case scrub
        /// grab = 잡은 점과 손잡이가 가리키는 x의 차이(잡자마자 튀지 않게)
        case trim(Handle, grab: CGFloat)
    }

    @State private var dragMode: DragMode?
    /// 마우스(또는 끌기)가 가리키는 바 위 x — nil이면 말풍선 없음
    @State private var pointerX: CGFloat?
    @State private var isHovering = false
    @State private var cursorPushed = false

    private var isDragging: Bool { dragMode != nil }
    private var trimming: Handle? {
        if case .trim(let handle, _) = dragMode { return handle }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let scale = duration > 0 ? width / duration : 0
            let start = min(max(0, inPoint * scale), width)
            let end = min(max(start, outPoint * scale), width)
            let x = min(max(0, position * scale), width)
            ZStack(alignment: .leading) {
                bar(width: width, start: start, end: end, x: x)
                    .frame(height: Self.barHeight)
                if onTrim != nil {
                    TrimHandleView(dim: !hasCustomIn, active: trimming == .inPoint)
                        .offset(x: handleLeft(start, width: width))
                    TrimHandleView(dim: !hasCustomOut, active: trimming == .outPoint)
                        .offset(x: handleLeft(end, width: width))
                }
            }
            .frame(width: width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width, start: start, end: end))
            .overlay(alignment: .topLeading) {
                if let pointerX, let thumbnails, width > 0 {
                    // 손잡이를 끄는 중이면 말풍선은 손잡이(실제로 멈춘 자리)를 따라가고 그 프레임을 보여준다.
                    let anchorX = trimming == .inPoint ? start : trimming == .outPoint ? end : pointerX
                    let seconds = trimming == .inPoint ? inPoint : trimming == .outPoint ? outPoint : Double(pointerX / width) * duration
                    let frame = thumbnails.frame(at: seconds)
                    // 말풍선 가운데를 마우스 x에(바 양 끝에서는 안쪽으로 붙임), 세로는 바 **위**에.
                    // 정렬 가이드는 호버 중 다시 계산되지 않아 따라오지 않았다 — 명시적 offset으로 둔다.
                    let bubbleWidth = BarThumbnailBubble.width + 8
                    let left = min(max(0, anchorX - bubbleWidth / 2), max(0, width - bubbleWidth))
                    BarThumbnailBubble(cache: thumbnails, frame: frame, aspect: aspect)
                        .fixedSize()
                        .offset(x: left, y: -(BarThumbnailBubble.totalHeight(aspect: aspect) + 6))
                        .allowsHitTesting(false)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    isHovering = true
                    if !isDragging { setResizeCursor(handle(at: point.x, width: width, start: start, end: end) != nil) }
                    // 손잡이를 끄는 중에는 말풍선 위치·요청을 끌기가 맡는다.
                    if trimming == nil { pointAt(point.x, width: width) }
                case .ended:
                    isHovering = false
                    if !isDragging {
                        setResizeCursor(false)
                        leave()
                    }
                }
            }
            .onChange(of: inPoint) { _, new in if trimming == .inPoint { requestThumbnail(at: new) } }
            .onChange(of: outPoint) { _, new in if trimming == .outPoint { requestThumbnail(at: new) } }
            // 썸네일을 끄면 남아 있던 포인터 상태를 지워, 다시 켤 때 그림 없는 말풍선이 뜨지 않게
            .onChange(of: thumbnails == nil) { _, off in if off { leave() } }
        }
        .frame(height: Self.height)
        .onDisappear { setResizeCursor(false) }
        .accessibilityHidden(true)
    }

    /// 손잡이 왼쪽 x: 가리키는 지점(edge)에 손잡이 가운데를 두되, 바 안으로 붙인다.
    private func handleLeft(_ edge: CGFloat, width: CGFloat) -> CGFloat {
        min(max(0, edge - Self.handleWidth / 2), max(0, width - Self.handleWidth))
    }

    /// x가 손잡이(좌우 4pt 여유 포함) 위인가. 두 손잡이가 겹치면 In~Out 가운데보다 왼쪽은 In, 오른쪽은 Out.
    private func handle(at x: CGFloat, width: CGFloat, start: CGFloat, end: CGFloat) -> Handle? {
        guard onTrim != nil, width > 0 else { return nil }
        func hit(_ edge: CGFloat) -> Bool {
            let left = handleLeft(edge, width: width)
            return x >= left - Self.handleSlop && x <= left + Self.handleWidth + Self.handleSlop
        }
        switch (hit(start), hit(end)) {
        case (true, true): return x < (start + end) / 2 ? .inPoint : .outPoint
        case (true, false): return .inPoint
        case (false, true): return .outPoint
        default: return nil
        }
    }

    private func dragGesture(width: CGFloat, start: CGFloat, end: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    if let grabbed = handle(at: value.startLocation.x, width: width, start: start, end: end), let onTrim {
                        let edge = grabbed == .inPoint ? start : end
                        dragMode = .trim(grabbed, grab: value.startLocation.x - edge)
                        setResizeCursor(true)
                        onTrim(grabbed, .began)
                        requestThumbnail(at: grabbed == .inPoint ? inPoint : outPoint)
                    } else {
                        dragMode = .scrub
                        onScrub(.began)
                    }
                }
                guard width > 0 else { return }
                switch dragMode {
                case .trim(let grabbed, let grab):
                    let edgeX = min(max(0, value.location.x - grab), width)
                    let seconds = Double(edgeX / width) * duration
                    onTrim?(grabbed, .moved(seconds))
                    // 말풍선을 켜 둔다(위치·프레임은 손잡이가 실제로 멈춘 자리). 썸네일 요청은 In/Out 값이 바뀔 때
                    // onChange에서 하므로, 상대 손잡이에 붙어 멈춘 뒤 포인터 프레임을 따로 요청하지 않는다.
                    pointerX = edgeX
                default:
                    let fraction = min(max(0, value.location.x / width), 1)
                    onScrub(.moved(fraction * duration))
                    // 끄는 중에도 말풍선이 따라간다(어디로 가는지 보이게).
                    pointAt(value.location.x, width: width)
                }
            }
            .onEnded { value in
                let mode = dragMode
                dragMode = nil
                switch mode {
                case .trim(let grabbed, _):
                    onTrim?(grabbed, .ended)
                default:
                    onScrub(.ended)
                }
                if isHovering {
                    setResizeCursor(handle(at: value.location.x, width: width, start: start, end: end) != nil)
                    pointAt(value.location.x, width: width)
                } else {
                    setResizeCursor(false)
                    leave()
                }
            }
    }

    /// 말풍선을 x로 옮기고 그 프레임 썸네일을 요청한다.
    private func pointAt(_ rawX: CGFloat, width: CGFloat) {
        guard width > 0, let thumbnails else { return }
        let x = min(max(0, rawX), width)
        pointerX = x
        thumbnails.request(frame: thumbnails.frame(at: Double(x / width) * duration))
    }

    private func requestThumbnail(at seconds: Double) {
        guard let thumbnails else { return }
        thumbnails.request(frame: thumbnails.frame(at: seconds))
    }

    private func leave() {
        pointerX = nil
        thumbnails?.cancelPending()
    }

    /// 손잡이 위(또는 손잡이를 끄는 중)에서 좌우 리사이즈 커서
    private func setResizeCursor(_ on: Bool) {
        guard on != cursorPushed else { return }
        if on { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        cursorPushed = on
    }

    private func bar(width: CGFloat, start: CGFloat, end: CGFloat, x: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.secondary.opacity(0.22))
            Rectangle()
                .fill(Color.accentColor.opacity(isDragging ? 1 : 0.8))
                .frame(width: max(1, end - start))
                .offset(x: start)
            Rectangle()
                .fill(Color.primary)
                .frame(width: 2)
                .offset(x: min(max(0, x - 1), width - 2))
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

/// 트림 손잡이 하나: 폭 8pt · 높이 16pt 둥근 사각형, 안에 세로 줄무늬 2줄(프리미어·파컷의 트림 손잡이처럼).
/// 미설정 표식이면 50%로 흐리게, 끄는 중이면 흰 테두리.
struct TrimHandleView: View {
    let dim: Bool
    let active: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.accentColor)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5)
                    .strokeBorder(active ? Color.white : Color.black.opacity(0.45), lineWidth: 1)
            )
            .overlay(
                HStack(spacing: 2) {
                    Capsule().fill(Color.white.opacity(0.9)).frame(width: 1, height: 8)
                    Capsule().fill(Color.white.opacity(0.9)).frame(width: 1, height: 8)
                }
            )
            .frame(width: TakeBar.handleWidth, height: TakeBar.height)
            .opacity(dim && !active ? 0.5 : 1)
            .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
            .allowsHitTesting(false)
    }
}
