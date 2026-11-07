import AVFoundation
import AppKit
import SwiftUI

// MARK: - 배치 계산 (순수 함수 — 화면 밖 렌더 검증도 같은 코드를 쓴다)

/// 겹쳐 보기 화면에서 두 영상과 B를 잘라낼 영역의 자리.
/// - 맞춤: 두 영상 모두 화면 전체에 aspect fit(가운데 정렬) — 해상도가 달라도 같은 크기로 겹친다.
/// - 100%/200%: 기준(두 테이크 중 큰 해상도) 원본 픽셀 1:1·2:1 크기의 사각형을 가운데 + 팬만큼 옮겨 두고, 두 영상 모두 그 안에 aspect fit.
/// - B 자르기: 갈라보기면 선 오른쪽(화면 기준, 팬과 무관), 겹치기면 화면 전체.
struct OverlayLayout: Equatable {
    var videoRect: CGRect
    var clipB: CGRect

    static func compute(
        bounds: CGRect,
        style: CompareModel.OverlayStyle,
        wipe: Double,
        pixelScale: Double?,
        referenceSize: CGSize,
        backingScale: CGFloat,
        pan: CGSize
    ) -> OverlayLayout {
        let videoRect: CGRect
        if let pixelScale, referenceSize.width > 0, referenceSize.height > 0 {
            let scale = CGFloat(pixelScale) / max(backingScale, 1)
            let size = CGSize(width: referenceSize.width * scale, height: referenceSize.height * scale)
            let p = clampPan(pan, videoSize: size, bounds: bounds.size)
            videoRect = CGRect(x: bounds.midX - size.width / 2 + p.width,
                               y: bounds.midY - size.height / 2 + p.height,
                               width: size.width, height: size.height)
        } else {
            videoRect = bounds
        }
        let clipB: CGRect
        switch style {
        case .wipe:
            let x = bounds.minX + bounds.width * CGFloat(min(max(0, wipe), 1))
            clipB = CGRect(x: x, y: bounds.minY, width: bounds.maxX - x, height: bounds.height)
        case .blend:
            clipB = bounds
        }
        return OverlayLayout(videoRect: videoRect, clipB: clipB)
    }

    /// 팬 한계: 영상이 화면보다 큰 만큼의 절반까지(작으면 0 — 가운데 고정)
    static func clampPan(_ pan: CGSize, videoSize: CGSize, bounds: CGSize) -> CGSize {
        let mx = max(0, (videoSize.width - bounds.width) / 2)
        let my = max(0, (videoSize.height - bounds.height) / 2)
        return CGSize(width: min(max(-mx, pan.width), mx), height: min(max(-my, pan.height), my))
    }

    /// `rect` 안에 `content` 비율로 aspect fit(가운데)
    static func aspectFit(_ content: CGSize, in rect: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0 else { return rect }
        let s = min(rect.width / content.width, rect.height / content.height)
        let size = CGSize(width: content.width * s, height: content.height * s)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// 정지 이미지 두 장을 같은 배치로 합성한다(화면 밖 렌더 검증용 — AVPlayerLayer는 화면 밖 캡처에 안 찍힌다).
    /// 좌표는 CoreGraphics(아래가 0) — 세로 방향과 무관하게 좌우만 자르므로 결과는 화면과 같다.
    func draw(a: CGImage, b: CGImage, style: CompareModel.OverlayStyle, opacity: Double, bounds: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: bounds)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(bounds)
        ctx.draw(a, in: Self.aspectFit(CGSize(width: a.width, height: a.height), in: videoRect))
        ctx.clip(to: clipB)
        if style == .blend { ctx.setAlpha(CGFloat(opacity)) }
        ctx.draw(b, in: Self.aspectFit(CGSize(width: b.width, height: b.height), in: videoRect))
        ctx.restoreGState()
    }
}

// MARK: - 두 플레이어를 겹쳐 그리는 NSView

/// A는 아래 AVPlayerLayer, B는 위 AVPlayerLayer. **B는 `masksToBounds` 클립 레이어 안에 있다** —
/// 클립 레이어의 frame을 선 오른쪽만큼으로 줄이고 bounds.origin을 같은 만큼 옮겨, 안쪽 B 영상은 화면에서 한 픽셀도 밀리지 않고
/// '가려지기'만 한다(SwiftUI `mask`는 AVPlayerView에 안 먹을 수 있어서 CALayer로 직접 자른다). 겹치기는 클립 레이어 opacity.
final class OverlayPlayersView: NSView {
    private let layerA = AVPlayerLayer()
    private let layerB = AVPlayerLayer()
    private let clipB = CALayer()

    var playerA: AVPlayer? { didSet { if layerA.player !== playerA { layerA.player = playerA } } }
    var playerB: AVPlayer? { didSet { if layerB.player !== playerB { layerB.player = playerB } } }
    var style: CompareModel.OverlayStyle = .wipe { didSet { if style != oldValue { needsLayout = true } } }
    var wipe: Double = 0.5 { didSet { if wipe != oldValue { needsLayout = true } } }
    var opacity: Double = 0.5 { didSet { if opacity != oldValue { needsLayout = true } } }
    var pixelScale: Double? { didSet { if pixelScale != oldValue { needsLayout = true } } }
    var referenceSize: CGSize = .zero { didSet { if referenceSize != oldValue { needsLayout = true } } }
    var pan: CGSize = .zero { didSet { if pan != oldValue { needsLayout = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        root.masksToBounds = true
        layer = root
        wantsLayer = true
        for player in [layerA, layerB] {
            player.videoGravity = .resizeAspect
            player.backgroundColor = NSColor.clear.cgColor
        }
        clipB.masksToBounds = true
        clipB.addSublayer(layerB)
        root.addSublayer(layerA)
        root.addSublayer(clipB)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let layout = OverlayLayout.compute(
            bounds: bounds, style: style, wipe: wipe, pixelScale: pixelScale,
            // 레이어 좌표는 아래가 0, SwiftUI 끌기는 아래로 + — 세로 팬만 뒤집어 넘긴다.
            referenceSize: referenceSize, backingScale: window?.backingScaleFactor ?? 2,
            pan: CGSize(width: pan.width, height: -pan.height)
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layerA.frame = layout.videoRect
        clipB.frame = layout.clipB
        // 클립 레이어 안의 좌표를 화면 좌표와 같게 — B 영상은 제자리, 클립만 줄어든다.
        clipB.bounds = CGRect(origin: layout.clipB.origin, size: layout.clipB.size)
        layerB.frame = layout.videoRect
        clipB.opacity = style == .blend ? Float(opacity) : 1
        CATransaction.commit()
    }

    func detach() {
        layerA.player = nil
        layerB.player = nil
    }
}

struct OverlaySurface: NSViewRepresentable {
    let playerA: AVPlayer?
    let playerB: AVPlayer?
    let style: CompareModel.OverlayStyle
    let wipe: Double
    let opacity: Double
    let pixelScale: Double?
    let referenceSize: CGSize
    let pan: CGSize

    func makeNSView(context: Context) -> OverlayPlayersView {
        let view = OverlayPlayersView(frame: .zero)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: OverlayPlayersView, context: Context) {
        view.playerA = playerA
        view.playerB = playerB
        view.style = style
        view.wipe = wipe
        view.opacity = opacity
        view.pixelScale = pixelScale
        view.referenceSize = referenceSize
        view.pan = pan
    }

    static func dismantleNSView(_ view: OverlayPlayersView, coordinator: ()) {
        view.detach()
    }
}

// MARK: - 겹쳐 보기 화면

/// 겹쳐 보기: 위 겹침 바(A/B·⇄·배율·투명도) + 겹친 영상(갈라보기 선·라벨) + 아래 A·B 조작 줄 두 개.
struct OverlayScreen: View {
    let model: CompareModel
    let a: Int
    let b: Int

    var body: some View {
        let takeA = model.takes[a], takeB = model.takes[b]
        VStack(spacing: 6) {
            OverlayBar(model: model, a: a, b: b)
            OverlayStage(model: model, takeA: takeA, takeB: takeB)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(alignment: .top, spacing: 12) {
                labeledStrip("A", takeA)
                labeledStrip("B", takeB)
            }
            .zIndex(1)   // 바 호버 썸네일이 영상 위로 올라오게
        }
    }

    private func labeledStrip(_ letter: String, _ take: Take) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                OverlayLetter(letter: letter)
                Text(verbatim: "\(take.index + 1) · \(take.fileName)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let info = take.info {
                    TakeDetails(info: info, mixedFps: model.hasMixedFps)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .onTapGesture { model.select(take.index) }
            if take.isReady {
                TakeStrip(take: take, model: model)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// `A` / `B` 작은 글자 배지
struct OverlayLetter: View {
    let letter: String

    var body: some View {
        Text(verbatim: letter)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.35)))
    }
}

/// 겹침 바: `A [1 · 파일 ▾] ⇄ B [2 · 파일 ▾]      배율 [맞춤|100%|200%]   (겹치기) 투명도 ──●── 50%`
struct OverlayBar: View {
    let model: CompareModel
    let a: Int
    let b: Int

    var body: some View {
        HStack(spacing: 8) {
            OverlayLetter(letter: "A")
            takePicker(isA: true, help: String(localized: "A — 아래, 선 왼쪽"))
            Button {
                model.flipOverlay()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "A/B 뒤집기"))
            .accessibilityLabel(Text("A/B 뒤집기"))
            OverlayLetter(letter: "B")
            takePicker(isA: false, help: String(localized: "B — 위, 선 오른쪽"))

            Spacer(minLength: 12)

            if model.overlayStyle == .wipe {
                Text(verbatim: String(format: "%.0f%%", model.wipePosition * 100))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help(String(localized: "갈라보기 선 위치 — 끌거나 [ ] (⇧는 10%)"))
            } else {
                Text("투명도")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { model.blendOpacity }, set: { model.setBlendOpacity($0) }),
                    in: 0...1
                )
                .controlSize(.small)
                .frame(width: 140)
                .help(String(localized: "B의 불투명도 — [ ] (⇧는 10%)"))
                Text(verbatim: String(format: "%3.0f%%", model.blendOpacity * 100))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 36, alignment: .trailing)
            }

            Picker(String(localized: "배율"), selection: Binding(get: { model.overlayZoom }, set: { model.setOverlayZoom($0) })) {
                Text("맞춤").tag(CompareModel.OverlayZoom.fit)
                Text(verbatim: "100%").tag(CompareModel.OverlayZoom.actual)
                Text(verbatim: "200%").tag(CompareModel.OverlayZoom.double)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help(String(localized: "배율 — 100%·200%는 큰 쪽 원본 픽셀 1:1·2:1. 영상을 끌어 이동, 더블클릭으로 맞춤"))
        }
        .frame(height: 24)
    }

    private func takePicker(isA: Bool, help: String) -> some View {
        let model = model
        let selection = isA ? a : b
        return Picker(help, selection: Binding(
            get: { selection },
            set: { isA ? model.setOverlayA($0) : model.setOverlayB($0) }
        )) {
            ForEach(model.readyTakes) { take in
                Text(verbatim: "\(take.index + 1) · \(take.fileName)").tag(take.index)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .frame(maxWidth: 260)
        .help(help)
    }
}

/// 겹친 영상 + 갈라보기 선(끌기)·A/B 라벨·확대 팬
struct OverlayStage: View {
    let model: CompareModel
    let takeA: Take
    let takeB: Take

    @State private var dragKind: DragKind?
    @State private var panStart: CGSize = .zero
    @State private var hoveringLine = false
    @State private var cursor: CursorKind = .none

    private enum DragKind { case line, pan }
    private enum CursorKind { case none, resize, hand }

    /// 선을 잡을 수 있는 거리(pt)
    private static let grabDistance: CGFloat = 6

    /// 배율 기준: 두 테이크 중 큰 해상도(업스케일 비교면 결과물 쪽)
    private var referenceSize: CGSize {
        let sa = takeA.info?.size ?? .zero, sb = takeB.info?.size ?? .zero
        return sa.width * sa.height > sb.width * sb.height ? sa : sb
    }

    private var isZoomed: Bool { model.overlayZoom != .fit }
    private var isWipe: Bool { model.overlayStyle == .wipe }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let lineX = size.width * CGFloat(model.wipePosition)
            ZStack(alignment: .topLeading) {
                OverlaySurface(
                    playerA: takeA.player,
                    playerB: takeB.player,
                    style: model.overlayStyle,
                    wipe: model.wipePosition,
                    opacity: model.blendOpacity,
                    pixelScale: model.overlayZoom.pixelScale,
                    referenceSize: referenceSize,
                    pan: model.overlayPan
                )
                if isWipe {
                    wipeLine(height: size.height)
                        .offset(x: lineX - 0.75)
                        .allowsHitTesting(false)
                    if hoveringLine || dragKind == .line {
                        handle
                            .position(x: lineX, y: size.height / 2)
                            .allowsHitTesting(false)
                    }
                }
                HStack {
                    sourceTab("A", takeA)
                    Spacer(minLength: 8)
                    sourceTab("B", takeB)
                }
                .padding(8)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let nearLine = isWipe && abs(point.x - lineX) <= Self.grabDistance
                    hoveringLine = nearLine
                    setCursor(nearLine ? .resize : (isZoomed ? .hand : .none))
                case .ended:
                    hoveringLine = false
                    if dragKind == nil { setCursor(.none) }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragKind == nil {
                            if isWipe, abs(value.startLocation.x - lineX) <= Self.grabDistance {
                                dragKind = .line
                            } else if isZoomed {
                                dragKind = .pan
                                panStart = model.overlayPan
                            } else {
                                return
                            }
                        }
                        switch dragKind {
                        case .line:
                            guard size.width > 0 else { return }
                            model.setWipePosition(Double(value.location.x / size.width))
                        case .pan:
                            model.overlayPan = clampedPan(
                                CGSize(width: panStart.width + value.translation.width,
                                       height: panStart.height + value.translation.height),
                                in: size)
                        case nil:
                            break
                        }
                    }
                    .onEnded { _ in
                        dragKind = nil
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    if isZoomed { model.setOverlayZoom(.fit) }
                }
            )
            .onDisappear { setCursor(.none) }
        }
        .background(Color.black)
        .clipped()
    }

    /// 1.5pt 흰 선 + 0.5pt 검은 외곽
    private func wipeLine(height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 1.5, height: height)
            .overlay(Rectangle().stroke(Color.black.opacity(0.8), lineWidth: 0.5))
    }

    /// 선 위에 마우스가 있을 때만 보이는 손잡이
    private var handle: some View {
        Image(systemName: "arrow.left.and.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.black)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.white))
            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 2)
    }

    /// Topaz의 소스 탭처럼 영상 위 모서리에 작은 반투명 라벨
    private func sourceTab(_ letter: String, _ take: Take) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: letter).fontWeight(.bold)
            Text(verbatim: "\(take.index + 1) · \(take.fileName)")
                .lineLimit(1)
                .truncationMode(.middle)
            if letter == "B", model.overlayStyle == .blend {
                Text(verbatim: String(format: "%.0f%%", model.blendOpacity * 100))
            }
        }
        .font(.caption)
        .foregroundStyle(Color.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.55)))
        .frame(maxWidth: 320, alignment: letter == "A" ? .leading : .trailing)
    }

    private func clampedPan(_ pan: CGSize, in bounds: CGSize) -> CGSize {
        guard let scale = model.overlayZoom.pixelScale else { return .zero }
        let backing = NSApp.keyWindow?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let s = CGFloat(scale) / max(backing, 1)
        let video = CGSize(width: referenceSize.width * s, height: referenceSize.height * s)
        return OverlayLayout.clampPan(pan, videoSize: video, bounds: bounds)
    }

    private func setCursor(_ kind: CursorKind) {
        guard kind != cursor else { return }
        if cursor != .none { NSCursor.pop() }
        cursor = kind
        switch kind {
        case .none: break
        case .resize: NSCursor.resizeLeftRight.push()
        case .hand: NSCursor.openHand.push()
        }
    }
}
