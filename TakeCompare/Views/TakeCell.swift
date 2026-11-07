import SwiftUI

/// 테이크 한 칸: 위 라벨 + 영상. 선택된 칸은 테두리 강조.
struct TakeCell: View {
    let take: Take
    let isSelected: Bool
    let isMuted: Bool
    /// 첫 테이크 기준 In 오프셋(프레임)
    let offsetFrames: Int
    /// 공통 타임라인 t — 이 테이크는 자기 In + t를 보여준다
    let timelineTime: Double
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            label
            if take.isReady {
                inOutLine
            }
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
            if let info = take.info {
                RangeBar(
                    duration: info.duration,
                    inPoint: take.inPoint,
                    outPoint: take.outPoint,
                    position: take.absoluteTime(at: timelineTime)
                )
                .frame(height: 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(take.index + 1)")
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
            if isSelected {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(isMuted ? Color.secondary : Color.accentColor)
                    .help(isMuted ? String(localized: "전체 음소거 중") : String(localized: "이 테이크의 소리가 납니다"))
            }
        }
        .frame(height: 18)
    }

    /// `In 00:00.50 · Out 00:03.20 · 오프셋 +3f` — 기본값인 칸은 `—`, 오프셋 0이면 생략
    private var inOutLine: some View {
        HStack(spacing: 0) {
            Text(verbatim: Self.inOutText(take: take, offsetFrames: offsetFrames))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(take.hasCustomIn || take.hasCustomOut || offsetFrames != 0 ? Color.primary : Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 13)
    }

    static func inOutText(take: Take, offsetFrames: Int) -> String {
        let inText = take.hasCustomIn ? TimeFormat.clock(take.inPoint) : "—"
        let outText = take.hasCustomOut ? TimeFormat.clock(take.outPoint) : "—"
        var text = "In \(inText) · Out \(outText)"
        if offsetFrames != 0 {
            text += " · " + String(localized: "오프셋 \(CompareModel.signed(offsetFrames))f")
        }
        return text
    }

    /// `· 1920×1080 · 24fps · 4.00s` (파일명 뒤에 붙는다)
    static func details(_ info: TakeInfo) -> String {
        let fps = abs(info.fps - info.fps.rounded()) < 0.01
            ? String(format: "%.0f", info.fps)
            : String(format: "%.3f", info.fps)
        return String(format: "· %.0f×%.0f · %@fps · %.2fs", info.size.width, info.size.height, fps, info.duration)
    }
}

/// 칸 아래 4px 바: 전체 길이 대비 In~Out 구간(강조색)과 현재 위치(선). 표시 전용.
struct RangeBar: View {
    let duration: Double
    let inPoint: Double
    let outPoint: Double
    let position: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let scale = duration > 0 ? width / duration : 0
            let start = min(max(0, inPoint * scale), width)
            let end = min(max(start, outPoint * scale), width)
            let x = min(max(0, position * scale), width)
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.25))
                Rectangle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: max(1, end - start))
                    .offset(x: start)
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2)
                    .offset(x: min(x, width - 2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
