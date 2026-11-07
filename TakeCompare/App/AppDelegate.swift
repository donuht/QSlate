import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 명시적 진입점 (Ledge와 같은 방식).
@main
enum TakeCompareMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

/// 창 하나짜리 앱. 메뉴·단축키를 모델로 넘긴다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let model = CompareModel()
    private var window: NSWindow?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(target: self)
        makeWindow()
        installKeyMonitor()
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Dock·Finder "다음으로 열기"로 넘어온 파일
    func application(_ application: NSApplication, open urls: [URL]) {
        model.open(urls)
    }

    private func makeWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TakeCompare"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 360)
        let hosting = NSHostingView(rootView: ContentView(model: model))
        // SwiftUI가 창 크기를 정하지 않게 — 창 크기는 사용자·기억값이 정한다.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        // 창 크기·위치 기억 (저장된 값이 있으면 복원)
        window.setFrameAutosaveName("TakeCompareMainWindow")
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    // MARK: - 키보드

    /// 수식키 없는 단축키(스페이스·화살표·숫자 등)는 여기서 먼저 처리한다.
    /// 슬라이더·버튼이 포커스를 가져가도 같은 동작을 하도록. ⌘ 단축키는 메뉴로 넘긴다.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NSEvent는 Sendable이 아니라 필요한 값만 꺼내 메인 액터 안으로 넘긴다.
            let key = KeyPress(event)
            let handled = MainActor.assumeIsolated {
                guard let self, key.windowNumber == self.window?.windowNumber else { return false }
                return self.handleKey(key)
            }
            return handled ? nil : event
        }
    }

    /// 키 모니터가 쓰는 키 입력 값
    private struct KeyPress: Sendable {
        let keyCode: UInt16
        let modifierFlags: NSEvent.ModifierFlags
        let charactersIgnoringModifiers: String?
        let windowNumber: Int

        init(_ event: NSEvent) {
            keyCode = event.keyCode
            modifierFlags = event.modifierFlags
            charactersIgnoringModifiers = event.charactersIgnoringModifiers
            windowNumber = event.windowNumber
        }
    }

    private func handleKey(_ event: KeyPress) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.contains(.command), !mods.contains(.control) else { return false }
        let shift = mods.contains(.shift)
        let option = mods.contains(.option)

        switch event.keyCode {
        case 123, 124:                                                              // ← →
            let sign = event.keyCode == 123 ? -1 : 1
            switch (option, shift) {
            case (false, false): model.step(frames: sign)                           // 모든 테이크 1프레임
            case (false, true): model.step(seconds: Double(sign))                   // 모든 테이크 1초
            case (true, false): model.nudgeSelected(frames: sign)                   // 선택 테이크만 1프레임
            case (true, true): model.nudgeSelected(seconds: Double(sign))           // 선택 테이크만 1초
            }
            return true
        default: break
        }
        guard !shift else { return false }

        // 글자 키는 한글 입력 상태에서도 되도록 자판 위치(keyCode)도 같이 본다.
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        func isKey(_ char: String, _ code: UInt16) -> Bool { chars == char || event.keyCode == code }

        if option {
            if isKey("i", 34) { model.clearIn(); return true }
            if isKey("o", 31) { model.clearOut(); return true }
            return false
        }

        switch event.keyCode {
        case 49: model.togglePlay(); return true                                   // 스페이스
        case 115: model.goToStart(); return true                                   // Home
        case 119: model.goToEnd(); return true                                     // End
        case 53: model.showGrid(); return true                                     // Esc
        default: break
        }
        switch chars {
        case "1", "2", "3", "4":
            model.toggleSolo(Int(chars)! - 1)
            return true
        default: break
        }
        if isKey("i", 34) { model.markIn(); return true }
        if isKey("o", 31) { model.markOut(); return true }
        if isKey("l", 37) { model.toggleLoop(); return true }
        if isKey("m", 46) { model.toggleMute(); return true }
        return false
    }

    // MARK: - 메뉴 동작

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie]
        panel.message = String(localized: "비교할 테이크 2~4개를 고르세요")
        panel.prompt = String(localized: "열기")
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated { self?.model.open(urls) }
        }
    }

    @objc func saveAllFrames(_ sender: Any?) { model.saveFrames(onlySelected: false) }
    @objc func saveSelectedFrame(_ sender: Any?) { model.saveFrames(onlySelected: true) }
    @objc func showGrid(_ sender: Any?) { model.showGrid() }
    @objc func showSolo(_ sender: NSMenuItem) { model.toggleSolo(sender.tag) }
    @objc func togglePlay(_ sender: Any?) { model.togglePlay() }
    @objc func stepBackFrame(_ sender: Any?) { model.step(frames: -1) }
    @objc func stepForwardFrame(_ sender: Any?) { model.step(frames: 1) }
    @objc func stepBackSecond(_ sender: Any?) { model.step(seconds: -1) }
    @objc func stepForwardSecond(_ sender: Any?) { model.step(seconds: 1) }
    @objc func goToStart(_ sender: Any?) { model.goToStart() }
    @objc func goToEnd(_ sender: Any?) { model.goToEnd() }
    @objc func toggleLoop(_ sender: Any?) { model.toggleLoop() }
    @objc func toggleMute(_ sender: Any?) { model.toggleMute() }
    @objc func markIn(_ sender: Any?) { model.markIn() }
    @objc func markOut(_ sender: Any?) { model.markOut() }
    @objc func clearIn(_ sender: Any?) { model.clearIn() }
    @objc func clearOut(_ sender: Any?) { model.clearOut() }
    @objc func clearAllInOut(_ sender: Any?) { model.clearAllInOut() }
    @objc func nudgeBackFrame(_ sender: Any?) { model.nudgeSelected(frames: -1) }
    @objc func nudgeForwardFrame(_ sender: Any?) { model.nudgeSelected(frames: 1) }
    @objc func nudgeBackSecond(_ sender: Any?) { model.nudgeSelected(seconds: -1) }
    @objc func nudgeForwardSecond(_ sender: Any?) { model.nudgeSelected(seconds: 1) }
    @objc func runStepSelfTest(_ sender: Any?) { model.runStepSelfTest() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasReady = !model.readyTakes.isEmpty
        switch item.action {
        case #selector(saveAllFrames(_:)), #selector(saveSelectedFrame(_:)),
             #selector(togglePlay(_:)), #selector(stepBackFrame(_:)), #selector(stepForwardFrame(_:)),
             #selector(stepBackSecond(_:)), #selector(stepForwardSecond(_:)),
             #selector(goToStart(_:)), #selector(goToEnd(_:)), #selector(clearAllInOut(_:)):
            if item.action == #selector(togglePlay(_:)) {
                item.title = model.isPlaying ? String(localized: "정지") : String(localized: "재생")
            }
            return hasReady
        case #selector(markIn(_:)), #selector(markOut(_:)), #selector(clearIn(_:)), #selector(clearOut(_:)),
             #selector(nudgeBackFrame(_:)), #selector(nudgeForwardFrame(_:)),
             #selector(nudgeBackSecond(_:)), #selector(nudgeForwardSecond(_:)):
            return model.selectedTake != nil && !model.isDiagnosing
        case #selector(runStepSelfTest(_:)):
            return hasReady && !model.isDiagnosing
        case #selector(showGrid(_:)):
            item.state = model.soloIndex == nil ? .on : .off
            return model.hasTakes
        case #selector(showSolo(_:)):
            item.state = model.soloIndex == item.tag ? .on : .off
            return item.tag < model.takes.count
        case #selector(toggleLoop(_:)):
            item.state = model.loopEnabled ? .on : .off
            return true
        case #selector(toggleMute(_:)):
            item.state = model.isMuted ? .on : .off
            return true
        default:
            return true
        }
    }
}
