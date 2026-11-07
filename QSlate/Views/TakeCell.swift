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
                Text(verbatim: Self.details(info))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .onTapGesture { model.select(index) }
    }

    /// `· 1920×1080 · 24fps · 4.00s` (파일명 뒤에 붙는다)
    static func details(_ info: TakeInfo) -> String {
        let fps = abs(info.fps - info.fps.rounded()) < 0.01
            ? String(format: "%.0f", info.fps)
            : String(format: "%.3f", info.fps)
        return String(format: "· %.0f×%.0f · %@fps · %.2fs", info.size.width, info.size.height, fps, info.duration)
    }
}

// MARK: - 칸 조작 줄

/// 영상 바로 아래 조작 줄. 이동 버튼·바는 **이 테이크의 재생 위치만** 옮긴다(In/Out·다른 테이크는 그대로 — 자유 탐색).
/// 누르면 이 칸이 선택된다. 줄은 공통 조작(재생·슬라이더·← →)을 하면 각자 In 기준으로 다시 선다.
///
///     ▶ [00:01.25]  |◀ ◀◀ ◀ ▶ ▶▶ ▶|   [In 00:00.50] +3f [Out 00:03.20] ↺   🔊 ⤢   (맨 앞 ▶/❚❚ = 이 테이크만 재생/정지)
///     ──────────[■■■■■■■■■■■■■■|■■■]──────────   ← 자기 타임라인 바(끌어서 스크럽)
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
                    onScrub: { phase in
                        switch phase {
                        case .began: model.takeScrubbing(index, began: true)
                        case .moved(let seconds): model.seekTake(index, toAbsolute: seconds)
                        case .ended: model.takeScrubbing(index, began: false)
                        }
                    }
                )
                .frame(height: 10)
                .disabled(disabled)
                .help(String(localized: "끌어서 이 테이크 위치만 이동 (In/Out은 그대로)"))
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
        Button(action: repeats ? {} : action) {
            Image(systemName: symbol)
                .imageScale(.small)
                .frame(width: 22, height: 20)
        }
        .buttonStyle(StripButtonStyle(highlighted: highlighted, onPress: repeats ? action : nil))
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(Text(verbatim: help))
        .disabled(disabled)
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
struct TakeBar: View {
    enum ScrubPhase {
        case began
        case moved(Double)
        case ended
    }

    let duration: Double
    let inPoint: Double
    let outPoint: Double
    let position: Double
    let onScrub: (ScrubPhase) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let scale = duration > 0 ? width / duration : 0
            let start = min(max(0, inPoint * scale), width)
            let end = min(max(start, outPoint * scale), width)
            let x = min(max(0, position * scale), width)
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
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onScrub(.began)
                        }
                        guard width > 0 else { return }
                        let fraction = min(max(0, value.location.x / width), 1)
                        onScrub(.moved(fraction * duration))
                    }
                    .onEnded { _ in
                        isDragging = false
                        onScrub(.ended)
                    }
            )
        }
        .accessibilityHidden(true)
    }
}
