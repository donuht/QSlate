import SwiftUI

/// 창 전체: 테이크 영역 + 재생 막대 + 상태줄. 창 어디에나 영상을 끌어다 놓을 수 있다.
struct ContentView: View {
    @Bindable var model: CompareModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
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
        .frame(minWidth: 560, minHeight: 360)
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
        TakeCell(
            take: take,
            isSelected: take.index == model.selectedIndex,
            isMuted: model.isMuted,
            onSelect: { model.select(take.index) }
        )
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

            Text(verbatim: TimeFormat.clock(model.currentTime))
                .font(.system(.body, design: .monospaced))
            Slider(
                value: Binding(
                    get: { model.currentTime },
                    set: { model.seekAll(to: $0) }
                ),
                in: 0...max(model.duration, 0.01),
                onEditingChanged: { model.scrubbing($0) }
            )
            .controlSize(.small)
            .disabled(model.readyTakes.isEmpty)
            Text(verbatim: TimeFormat.clock(model.duration))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

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
