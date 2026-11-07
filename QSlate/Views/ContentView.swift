import SwiftUI

/// 창 전체: 테이크 영역 + 재생 막대 + 상태줄. 창 어디에나 영상을 끌어다 놓을 수 있다.
struct ContentView: View {
    @Bindable var model: CompareModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ViewModeToolbar(model: model)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            Divider()
            stage
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            transport
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            Divider()
            statusBar
        }
        .frame(minWidth: 1100, minHeight: 700)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.open(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    // MARK: - 테이크 영역

    @ViewBuilder
    private var stage: some View {
        if !model.hasTakes {
            emptyState
        } else if let pair = model.overlayPair, pair.a < model.takes.count, pair.b < model.takes.count {
            OverlayScreen(model: model, a: pair.a, b: pair.b)
        } else if let solo = model.soloIndex, solo < model.takes.count {
            cell(model.takes[solo])
        } else if model.takes.count <= 2 {
            HStack(spacing: 8) {
                ForEach(model.takes) { cell($0) }
            }
        } else {
            // 3~4개: 2×2 격자. 3개면 오른쪽 아래 칸은 비운다.
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    cell(model.takes[0])
                    cell(model.takes[1])
                }
                GridRow {
                    cell(model.takes[2])
                    if model.takes.count > 3 {
                        cell(model.takes[3])
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }

    private func cell(_ take: Take) -> some View {
        TakeCell(take: take, model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("비교할 테이크를 끌어다 놓으세요")
                .font(.title3.weight(.semibold))
            Text("mp4·mov 2~4개 · ⌘O로 열기")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
    }

    // MARK: - 재생 막대

    private var transport: some View {
        HStack(spacing: 10) {
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "재생/정지 (스페이스)"))
            .disabled(model.readyTakes.isEmpty)

            // t / 범위 (In 기준 상대 시각). 칸 조작으로 흩어져 있으면 t 자리에 —
            Text(verbatim: "\(model.isAligned ? TimeFormat.clock(model.currentTime) : "—") / \(TimeFormat.clock(model.range))")
                .font(.system(.body, design: .monospaced))
                .help(model.isAligned
                      ? String(localized: "In 기준 시각 / 범위(가장 긴 In~Out)")
                      : String(localized: "칸 조작으로 줄이 흩어짐 — 재생·슬라이더·← →를 쓰면 각자 In 기준으로 다시 맞춘다"))
            Slider(
                value: Binding(
                    get: { model.currentTime },
                    set: { model.seekAll(to: $0) }
                ),
                in: 0...max(model.range, 0.01),
                onEditingChanged: { model.scrubbing($0) }
            )
            .controlSize(.small)
            .disabled(model.readyTakes.isEmpty || model.isDiagnosing)

            // 전체 1프레임 (←/→) — 길게 누르면 반복
            HStack(spacing: 2) {
                Button {} label: {
                    Image(systemName: "backward.frame").frame(width: 22, height: 20)
                }
                .buttonStyle(StripButtonStyle(onPress: { model.step(frames: -1) }))
                .help(String(localized: "모든 테이크 1프레임 뒤로 — 길게 누르면 반복 (←)"))
                .accessibilityLabel(Text(verbatim: String(localized: "모든 테이크 1프레임 뒤로 — 길게 누르면 반복 (←)")))
                .accessibilityAction { model.step(frames: -1) }
                Button {} label: {
                    Image(systemName: "forward.frame").frame(width: 22, height: 20)
                }
                .buttonStyle(StripButtonStyle(onPress: { model.step(frames: 1) }))
                .help(String(localized: "모든 테이크 1프레임 앞으로 — 길게 누르면 반복 (→)"))
                .accessibilityLabel(Text(verbatim: String(localized: "모든 테이크 1프레임 앞으로 — 길게 누르면 반복 (→)")))
                .accessibilityAction { model.step(frames: 1) }
            }
            .disabled(model.readyTakes.isEmpty || model.isDiagnosing)

            Toggle(isOn: $model.loopEnabled) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.button)
            .help(String(localized: "루프 (L)"))

            Button {
                model.toggleMute()
            } label: {
                Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "전체 음소거 (M)"))

            Button {
                model.saveFrames(onlySelected: false)
            } label: {
                Label(String(localized: "지금 프레임 저장"), systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)
            .help(String(localized: "지금 프레임을 모든 테이크에서 PNG로 저장 (⌘S)"))
            .disabled(model.readyTakes.isEmpty || model.isDiagnosing)

            Button(String(localized: "인·아웃 모두 초기화")) {
                model.clearAllInOut()
            }
            .controlSize(.small)
            .help(String(localized: "모든 테이크의 In/Out을 초기화"))
            .disabled(!model.hasAnyInOut || model.isDiagnosing)
        }
    }

    // MARK: - 상태줄

    private var statusBar: some View {
        HStack(spacing: 6) {
            if model.statusRevealURLs.isEmpty {
                Text(verbatim: model.statusMessage)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    model.revealStatusFiles()
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: model.statusMessage)
                        Image(systemName: "arrow.up.forward.square")
                    }
                }
                .buttonStyle(.link)
                .help(String(localized: "Finder에서 보기"))
            }
            Spacer(minLength: 0)
            if model.soloIndex != nil {
                Text("단독 보기 — 같은 숫자 또는 Esc로 격자")
                    .foregroundStyle(.secondary)
            } else if model.isOverlay {
                Group {
                    if model.overlayStyle == .wipe {
                        Text("갈라보기 — 선을 끌거나 [ ] (⇧ 10%) · \\ 또는 Esc로 격자")
                    } else {
                        Text("겹치기 — [ ]로 투명도 (⇧ 10%) · ⇧\\ 또는 Esc로 격자")
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

// MARK: - 보기 모드 줄

/// 창 맨 위 줄: 왼쪽에 열린 파일 수·범위, 오른쪽에 보기 모드 4개(전체 보기·단독·갈라보기·겹치기).
struct ViewModeToolbar: View {
    let model: CompareModel

    private enum Mode { case grid, solo, wipe, blend }

    private var current: Mode {
        switch model.viewMode {
        case .grid: .grid
        case .solo: .solo
        case .overlay: model.overlayStyle == .wipe ? .wipe : .blend
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: info)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                modeButton(.grid, "square.grid.2x2", String(localized: "전체 보기"), String(localized: "전체 보기 — 격자 (Esc · 0)"), enabled: model.hasTakes) {
                    model.showGrid()
                }
                modeButton(.solo, "rectangle", String(localized: "단독"), String(localized: "단독 — 선택한 테이크만 크게 (1~4)"), enabled: model.hasTakes) {
                    model.showSoloSelected()
                }
                modeButton(.wipe, "rectangle.split.2x1", String(localized: "갈라보기"), String(localized: "갈라보기 — 세로선 왼쪽 A, 오른쪽 B (\\)"), enabled: model.canOverlay) {
                    model.showOverlay(.wipe)
                }
                modeButton(.blend, "square.on.square", String(localized: "겹치기"), String(localized: "겹치기 — B를 반투명으로 위에 (⇧\\)"), enabled: model.canOverlay) {
                    model.showOverlay(.blend)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
        }
        .frame(height: 26)
    }

    /// `테이크 2개 · 범위 00:03.00`
    private var info: String {
        guard model.hasTakes else { return String(localized: "열린 테이크 없음") }
        let count = model.readyTakes.count
        return String(localized: "테이크 \(count)개 · 범위 \(TimeFormat.clock(model.range))")
    }

    private func modeButton(_ mode: Mode, _ symbol: String, _ title: String, _ help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let isOn = current == mode && model.hasTakes
        return Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(verbatim: title)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 5).fill(isOn ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
