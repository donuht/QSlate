import SwiftUI

/// 칸 바 위 호버 말풍선: 그 지점 프레임 썸네일(폭 160pt, 비율 유지) + `00:01.25 · 30f`.
/// 요청한 프레임이 아직 없으면 바로 앞에 받은 썸네일을 대신 보여준다(빈칸으로 깜빡이지 않게).
struct BarThumbnailBubble: View {
    let cache: ThumbnailCache
    let frame: Int
    let aspect: Double

    static let width: CGFloat = 160

    var body: some View {
        // revision을 읽어 두면 새 썸네일이 들어올 때 다시 그린다.
        let _ = cache.revision
        let image = cache.image(for: frame) ?? cache.latestImage
        let height = (Self.width / CGFloat(max(aspect, 0.1))).rounded()
        VStack(spacing: 3) {
            ZStack {
                Color.black
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: Self.width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(verbatim: "\(TimeFormat.clock(Double(frame) * cache.frameDuration)) · \(frame)f")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.white)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.82))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
        )
    }
}
