import AppKit

/// 메뉴바: 앱 · 파일 · 보기 · 창. 수식키 없는 단축키는 표시용이며 실제 처리는 AppDelegate 키 모니터가 먼저 한다.
@MainActor
enum MainMenu {
    static func build(target: AppDelegate) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu(target)))
        main.addItem(submenu(viewMenu(target)))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        _ mods: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil,
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        item.target = target
        item.tag = tag
        return item
    }

    private static func key(_ functionKey: Int) -> String {
        String(Character(UnicodeScalar(UInt32(functionKey))!))
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "TakeCompare")
        menu.addItem(item(String(localized: "TakeCompare에 관하여"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "TakeCompare 가리기"), #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item(String(localized: "기타 가리기"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item(String(localized: "모두 보기"), #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "TakeCompare 종료"), #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(_ t: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: String(localized: "파일"))
        menu.addItem(item(String(localized: "열기…"), #selector(AppDelegate.openDocument(_:)), "o", target: t))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "프레임 저장 (모든 테이크)"), #selector(AppDelegate.saveAllFrames(_:)), "s", target: t))
        menu.addItem(item(String(localized: "프레임 저장 (선택한 테이크)"), #selector(AppDelegate.saveSelectedFrame(_:)), "s", [.command, .shift], target: t))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "창 닫기"), #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func viewMenu(_ t: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: String(localized: "보기"))
        menu.addItem(item(String(localized: "격자"), #selector(AppDelegate.showGrid(_:)), "\u{1b}", [], target: t))
        for n in 1...CompareModel.maxTakes {
            menu.addItem(item(String(localized: "테이크 \(n)만 보기"), #selector(AppDelegate.showSolo(_:)), "\(n)", [], target: t, tag: n - 1))
        }
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "재생"), #selector(AppDelegate.togglePlay(_:)), " ", [], target: t))
        menu.addItem(item(String(localized: "한 프레임 뒤로"), #selector(AppDelegate.stepBackFrame(_:)), key(NSLeftArrowFunctionKey), [], target: t))
        menu.addItem(item(String(localized: "한 프레임 앞으로"), #selector(AppDelegate.stepForwardFrame(_:)), key(NSRightArrowFunctionKey), [], target: t))
        menu.addItem(item(String(localized: "1초 뒤로"), #selector(AppDelegate.stepBackSecond(_:)), key(NSLeftArrowFunctionKey), [.shift], target: t))
        menu.addItem(item(String(localized: "1초 앞으로"), #selector(AppDelegate.stepForwardSecond(_:)), key(NSRightArrowFunctionKey), [.shift], target: t))
        menu.addItem(item(String(localized: "처음으로"), #selector(AppDelegate.goToStart(_:)), key(NSHomeFunctionKey), [], target: t))
        menu.addItem(item(String(localized: "끝으로"), #selector(AppDelegate.goToEnd(_:)), key(NSEndFunctionKey), [], target: t))
        menu.addItem(.separator())
        let left = key(NSLeftArrowFunctionKey), right = key(NSRightArrowFunctionKey)
        menu.addItem(item(String(localized: "In 설정 (선택한 테이크)"), #selector(AppDelegate.markIn(_:)), "i", [], target: t))
        menu.addItem(item(String(localized: "Out 설정 (선택한 테이크)"), #selector(AppDelegate.markOut(_:)), "o", [], target: t))
        menu.addItem(item(String(localized: "In 초기화 (선택한 테이크)"), #selector(AppDelegate.clearIn(_:)), "i", [.option], target: t))
        menu.addItem(item(String(localized: "Out 초기화 (선택한 테이크)"), #selector(AppDelegate.clearOut(_:)), "o", [.option], target: t))
        menu.addItem(item(String(localized: "인·아웃 모두 초기화"), #selector(AppDelegate.clearAllInOut(_:)), target: t))
        menu.addItem(item(String(localized: "선택한 테이크 위치만 1프레임 뒤로"), #selector(AppDelegate.moveBackFrame(_:)), left, [.option], target: t))
        menu.addItem(item(String(localized: "선택한 테이크 위치만 1프레임 앞으로"), #selector(AppDelegate.moveForwardFrame(_:)), right, [.option], target: t))
        menu.addItem(item(String(localized: "선택한 테이크 위치만 1초 뒤로"), #selector(AppDelegate.moveBackSecond(_:)), left, [.option, .shift], target: t))
        menu.addItem(item(String(localized: "선택한 테이크 위치만 1초 앞으로"), #selector(AppDelegate.moveForwardSecond(_:)), right, [.option, .shift], target: t))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "루프"), #selector(AppDelegate.toggleLoop(_:)), "l", [], target: t))
        menu.addItem(item(String(localized: "전체 음소거"), #selector(AppDelegate.toggleMute(_:)), "m", [], target: t))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "프레임 이동 자가진단"), #selector(AppDelegate.runStepSelfTest(_:)), target: t))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "창"))
        menu.addItem(item(String(localized: "최소화"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item(String(localized: "확대/축소"), #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "모두 앞으로 가져오기"), #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
