import SwiftUI

/// 테이크 한 칸: 위 라벨 + 영상. 선택된 칸은 테두리 강조.
struct TakeCell: View {
    let take: Take
    let isSelected: Bool
    let isMuted: Bool
    let onSelect: () -> Void

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

    /// `· 1920×1080 · 24fps · 4.00s` (파일명 뒤에 붙는다)
    static func details(_ info: TakeInfo) -> String {
        let fps = abs(info.fps - info.fps.rounded()) < 0.01
            ? String(format: "%.0f", info.fps)
            : String(format: "%.3f", info.fps)
        return String(format: "· %.0f×%.0f · %@fps · %.2fs", info.size.width, info.size.height, fps, info.duration)
    }
}
