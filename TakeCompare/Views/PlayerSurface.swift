import AVKit
import SwiftUI

/// 컨트롤 없는 AVPlayerView. 클릭·키는 받지 않고 SwiftUI 쪽(칸 선택)과 앱 단축키로 넘긴다.
struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> PassivePlayerView {
        let view = PassivePlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = false
        view.player = player
        return view
    }

    func updateNSView(_ view: PassivePlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }

    static func dismantleNSView(_ view: PassivePlayerView, coordinator: ()) {
        view.player = nil
    }
}

final class PassivePlayerView: AVPlayerView {
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
