import Cocoa
import Carbon.HIToolbox
import ServiceManagement

// RightType for macOS (menu-bar MVP). The correction logic is the original
// Rust core (rt_fix); this file only handles keys, text delivery and the menu.

func dlog(_ m: String) {
    let line = "\(Date()) \(m)\n"
    if let h = FileHandle(forWritingAtPath: "/tmp/righttype.log") { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { try? line.write(toFile: "/tmp/righttype.log", atomically: false, encoding: .utf8) }
}
let marker: Int64 = 0x5254_5950  // tags events we post ourselves so the tap ignores them

final class App: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var tap: CFMachPort?
    var asked = false
    var spellOn = UserDefaults.standard.object(forKey: "spell") as? Bool ?? true
    var idleTimer: Timer?
    var enabled = true
    var buffer = String.UnicodeScalarView()
    var lastFix: (original: String, fixed: String, trail: String)?
    let toggleItem = NSMenuItem()
    enum Mode: Int { case manual, suggest, auto }
    var mode: Mode = Mode(rawValue: UserDefaults.standard.object(forKey: "mode") as? Int ?? 1) ?? .suggest
    var modeItems: [NSMenuItem] = []
    var pending: (word: String, fixed: String, trail: String)?
    var panel: NSPanel?
    var label: NSTextField?
    var hideTimer: Timer?
    let statusLine = NSMenuItem()

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(contentsOfFile: Bundle.main.path(forResource: "menuTemplate", ofType: "png") ?? "") {
            img.isTemplate = true; img.size = NSSize(width: 18, height: 18)
            item.button?.image = img
        } else { item.button?.title = "Aก" }
        let m = NSMenu()
        toggleItem.title = "เปิดใช้งาน / Enabled"
        toggleItem.action = #selector(toggle); toggleItem.target = self; toggleItem.state = .on
        m.addItem(toggleItem)
        m.addItem(.separator())
        for (i, t) in ["Manual – แก้เมื่อกด ⇧⌫ เท่านั้น", "Suggest – เตือนแล้วกด Tab เพื่อแก้", "Auto – แก้ให้เองทันที"].enumerated() {
            let mi = NSMenuItem(title: t, action: #selector(pickMode(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = i; mi.state = i == mode.rawValue ? .on : .off
            m.addItem(mi); modeItems.append(mi)
        }
        let sp = NSMenuItem(title: "แก้คำไทยสะกดผิด (กด Tab)", action: #selector(toggleSpell(_:)), keyEquivalent: "")
        sp.target = self; sp.state = spellOn ? .on : .off; m.addItem(sp)
        let lg = NSMenuItem(title: "เปิดอัตโนมัติตอนเข้าเครื่อง", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        lg.target = self; m.addItem(lg)
        // First run: start at login by default (the user can turn it off here).
        if !UserDefaults.standard.bool(forKey: "loginAsked") {
            UserDefaults.standard.set(true, forKey: "loginAsked")
            try? SMAppService.mainApp.register()
        }
        lg.state = launchAtLogin ? .on : .off
        m.addItem(.separator())
        m.addItem(withTitle: "แก้ข้อความที่เลือก (⌃⌥Space)", action: #selector(fixSelectionMenu), keyEquivalent: "").target = self
        m.addItem(.separator())
        statusLine.isEnabled = false; m.addItem(statusLine); updateStatus()
        m.addItem(withTitle: "ตั้งค่าสิทธิ์ Accessibility…", action: #selector(openPrivacy), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "ออก / Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m
        startTap()
    }

    func updateStatus() {
        statusLine.title = AXIsProcessTrusted() ? "✓ ได้รับสิทธิ์ Accessibility แล้ว" : "⚠︎ ยังไม่ได้รับสิทธิ์ Accessibility"
    }
    @objc func pickMode(_ s: NSMenuItem) {
        mode = Mode(rawValue: s.tag) ?? .suggest
        UserDefaults.standard.set(mode.rawValue, forKey: "mode")
        for m in modeItems { m.state = m.tag == s.tag ? .on : .off }
        hideHint()
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    @objc func toggleLogin(_ s: NSMenuItem) {
        do {
            if launchAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSLog("login item: \(error)") }
        s.state = launchAtLogin ? .on : .off
    }

    @objc func toggleSpell(_ s: NSMenuItem) {
        spellOn.toggle(); s.state = spellOn ? .on : .off
        UserDefaults.standard.set(spellOn, forKey: "spell")
    }

    @objc func toggle() {
        enabled.toggle(); toggleItem.state = enabled ? .on : .off
        item.button?.alphaValue = enabled ? 1 : 0.4
    }
    @objc func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func fixSelectionMenu() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.fixSelection() } }

    // MARK: event tap
    func startTap() {
        // Ask once; afterwards just poll quietly until permission is granted.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: !asked] as CFDictionary
        asked = true
        dlog("trusted=\(AXIsProcessTrusted()) listen=\(CGPreflightListenEventAccess())")
        if !AXIsProcessTrustedWithOptions(opts) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.startTap(); self.updateStatus() }
            return
        }
        if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            let app = Unmanaged<App>.fromOpaque(refcon!).takeUnretainedValue()
            return app.handle(type, event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mask), callback: cb,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.startTap() }
            return
        }
        tap = t
        dlog("tap created")
        updateStatus()
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown { buffer.removeAll(); lastFix = nil; return Unmanaged.passUnretained(event) }
        guard enabled, event.getIntegerValueField(.eventSourceUserData) != marker else {
            return Unmanaged.passUnretained(event)
        }
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let f = event.flags
        if f.contains(.maskControl) && f.contains(.maskAlternate) && key == kVK_Space {
            DispatchQueue.main.async { self.fixSelection() }
            return nil
        }
        if key == kVK_Tab, let p = pending, !f.contains(.maskCommand), !f.contains(.maskControl) {
            hideHint()
            let a = Array(p.word.unicodeScalars), b = Array(p.fixed.unicodeScalars)
            var k = 0
            while k < a.count, k < b.count, a[k] == b[k] { k += 1 }
            var tail = String.UnicodeScalarView(); tail.append(contentsOf: b[k...])
            replace(deleting: a.count - k + p.trail.unicodeScalars.count, with: String(tail) + p.trail)
            selectLayout(thai: p.fixed.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) })
            lastFix = (p.word, p.fixed, p.trail)
            return nil
        }
        idleTimer?.invalidate()
        if key != kVK_Space { hideHint() }
        if f.contains(.maskCommand) || f.contains(.maskControl) {
            buffer.removeAll(); lastFix = nil
            return Unmanaged.passUnretained(event)
        }
        if key == kVK_Delete {
            if f.contains(.maskShift) {
                if fixLastWord() { return nil }
                return Unmanaged.passUnretained(event)
            }
            if !buffer.isEmpty { buffer.removeLast() }
            lastFix = nil
            return Unmanaged.passUnretained(event)
        }
        switch key {
        case kVK_Return, kVK_Tab, kVK_Escape, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete, kVK_ANSI_KeypadEnter:
            buffer.removeAll(); lastFix = nil
            return Unmanaged.passUnretained(event)
        default: break
        }
        var len = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &len, unicodeString: &chars)
        if len > 0 {
            buffer.append(contentsOf: String(utf16CodeUnits: chars, count: len).unicodeScalars)
            if buffer.count > 200 { buffer.removeFirst(buffer.count - 200) }
            lastFix = nil
            hideHint()
            if spellOn { scheduleSpell() }
            if key == kVK_Space, mode != .manual { checkBoundary() }
            else if mode != .manual, !f.contains(.maskCommand) {
                // Long Thai has no spaces: judge the run while it is typed.
                let all = String(buffer)
                let run = String(all.reversed().prefix { !$0.isWhitespace }.reversed())
                if run.count >= 3, run.unicodeScalars.allSatisfy({ $0.isASCII }), let fixed = live(run) {
                    if mode == .auto {
                        replace(deleting: run.unicodeScalars.count - 1, with: fixed)
                        selectLayout(thai: true)
                        lastFix = (run, fixed, "")
                        return nil  // the final key is folded into the fix
                    }
                    pending = (run, fixed, "")
                    showHint("\(fixed)   ⇥ Tab เพื่อแก้")
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: suggest / auto at a word boundary
    func checkBoundary() {
        let all = String(buffer)
        guard all.hasSuffix(" ") else { return }
        let head = String(all.dropLast())
        let word = String(head.reversed().prefix { !$0.isWhitespace }.reversed())
        guard !word.isEmpty, let fixed = fix(word), fixed != word else { spellCheck(trail: " "); return }
        if mode == .auto {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                self.replace(deleting: (word + " ").unicodeScalars.count, with: fixed + " ")
                self.selectLayout(thai: fixed.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) })
                self.lastFix = (word, fixed, " ")
            }
        } else {
            pending = (word, fixed, " ")
            showHint("\(fixed)   ⇥ Tab เพื่อแก้")
        }
    }

    // MARK: Thai spelling (hint only, never silent)
    func scheduleSpell() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.spellCheck(trail: "") }
    }

    func spellCheck(trail: String) {
        guard spellOn, pending == nil else { return }
        let all = String(buffer)
        let head = trail.isEmpty ? all : String(all.dropLast(trail.count))
        let run = String(head.reversed().prefix { !$0.isWhitespace }.reversed())
        guard run.unicodeScalars.contains(where: { (0x0E00...0x0E7F).contains($0.value) }),
              let p = rt_spell(run) else { return }
        defer { rt_free(p) }
        let fixed = String(cString: p)
        pending = (run, fixed, trail)
        showHint("✎ \(String(fixed.suffix(14)))   ⇥ Tab เพื่อแก้คำสะกด")
    }

    func caretPoint() -> NSPoint {
        // Ask the focused UI element for the caret; fall back to the mouse.
        let sys = AXUIElementCreateSystemWide()
        var el: CFTypeRef?
        if AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &el) == .success,
           let el = el {
            var range: CFTypeRef?
            if AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
               let range = range {
                var b: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(el as! AXUIElement, kAXBoundsForRangeParameterizedAttribute as CFString, range, &b) == .success,
                   let b = b {
                    var r = CGRect.zero
                    if AXValueGetValue(b as! AXValue, .cgRect, &r), r.height > 0, r.height < 200 {
                        let h = NSScreen.screens.first?.frame.height ?? 0
                        return NSPoint(x: r.minX, y: h - r.maxY)  // AX is top-left origin
                    }
                }
            }
        }
        let m = NSEvent.mouseLocation
        return NSPoint(x: m.x, y: m.y - 20)
    }

    func showHint(_ text: String) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 30),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .popUpMenu; p.isOpaque = false; p.backgroundColor = .clear
            p.hasShadow = true; p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = NSVisualEffectView(frame: p.contentView!.bounds)
            v.material = .hudWindow; v.state = .active; v.wantsLayer = true
            v.layer?.cornerRadius = 8; v.layer?.masksToBounds = true
            let l = NSTextField(labelWithString: "")
            l.font = .systemFont(ofSize: 14, weight: .medium); l.textColor = .labelColor
            v.addSubview(l); p.contentView = v
            panel = p; label = l
        }
        label?.stringValue = text; label?.sizeToFit()
        let w = (label?.frame.width ?? 100) + 24
        label?.setFrameOrigin(NSPoint(x: 12, y: 6))
        let pt = caretPoint()
        panel?.setFrame(NSRect(x: pt.x, y: pt.y - 34, width: w, height: 30), display: true)
        panel?.orderFrontRegardless()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.hideHint() }
    }

    func hideHint() {
        pending = nil; hideTimer?.invalidate(); panel?.orderOut(nil)
    }

    // MARK: fix the last typed word
    @discardableResult
    func fixLastWord() -> Bool {
        let all = String(buffer)
        // Undo: pressing again right after a fix restores the original.
        if let l = lastFix, all.hasSuffix(l.fixed + l.trail) {
            replace(deleting: (l.fixed + l.trail).unicodeScalars.count, with: l.original + l.trail)
            selectLayout(thai: l.original.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) })
            lastFix = nil
            return true
        }
        let trail = String(all.reversed().prefix { $0.isWhitespace }.reversed())
        let head = String(all.dropLast(trail.count))
        let word = String(head.reversed().prefix { !$0.isWhitespace }.reversed())
        guard !word.isEmpty, let fixed = fix(word), fixed != word else { return false }
        replace(deleting: (word + trail).unicodeScalars.count, with: fixed + trail)
        selectLayout(thai: fixed.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) })
        lastFix = (word, fixed, trail)
        return true
    }

    func live(_ s: String) -> String? {
        guard let p = rt_live(s) else { return nil }
        defer { rt_free(p) }
        return String(cString: p)
    }

    func fix(_ s: String) -> String? {
        guard let p = rt_fix(s) else { return nil }
        defer { rt_free(p) }
        return String(cString: p)
    }

    func replace(deleting n: Int, with text: String) {
        for _ in 0..<n { post(key: CGKeyCode(kVK_Delete), text: nil) }
        let u = Array(text.utf16)
        var i = 0
        while i < u.count {
            var j = min(i + 16, u.count)
            if j < u.count, UTF16.isLeadSurrogate(u[j - 1]) { j -= 1 }
            post(key: 0, text: Array(u[i..<j])); i = j
        }
        buffer.removeLast(min(n, buffer.count)); buffer.append(contentsOf: text.unicodeScalars)
    }

    func post(key: CGKeyCode, text: [UniChar]?) {
        let src = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else { continue }
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.flags = []
            if let t = text { e.keyboardSetUnicodeString(stringLength: t.count, unicodeString: t) }
            e.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: fix selected text via clipboard
    func fixSelection() {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        chord(kVK_ANSI_C)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let sel = pb.string(forType: .string)
            if let s = sel, let fixed = self.fix(s) {
                pb.clearContents(); pb.setString(fixed, forType: .string)
                self.chord(kVK_ANSI_V)
                self.selectLayout(thai: fixed.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) })
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.restore(saved) }
            } else { self.restore(saved) }
        }
    }
    func restore(_ s: String?) {
        let pb = NSPasteboard.general; pb.clearContents()
        if let s = s { pb.setString(s, forType: .string) }
    }
    func chord(_ key: Int) {
        let src = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: down)
            e?.flags = .maskCommand
            e?.setIntegerValueField(.eventSourceUserData, value: marker)
            e?.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: input source
    func selectLayout(thai: Bool) {
        let list = TISCreateInputSourceList(["TISPropertyInputSourceType": kTISTypeKeyboardLayout] as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource] ?? []
        func id(_ s: TISInputSource) -> String {
            guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
            return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
        }
        let want = list.first { thai ? id($0).contains("Thai") : (id($0).hasSuffix(".ABC") || id($0).hasSuffix(".US")) }
        if let w = want { TISSelectInputSource(w) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
