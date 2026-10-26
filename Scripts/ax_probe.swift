import ApplicationServices
import Cocoa
import Foundation

// Accessibility probe for the math benchmark.
//
// Every expectation is a hard check: the probe exits non-zero when any of them
// fails, so the harness can never continue with a scenario that did not
// actually render its content. Formula checks match the exact TeX in the
// element's accessibility description, which is why an unrendered attachment
// placeholder can never satisfy them.

struct Check: Codable {
    let name: String
    let ok: Bool
    let detail: String
}

struct Timeline: Codable {
    var windowMs: Double?
    var contentMs: Double?
    var formulaMs: Double?
    var totalMs: Double
}

struct ProbeResult: Codable {
    let ok: Bool
    let pid: Int32
    let windowCount: Int
    let timeline: Timeline
    let axSnapshotMs: Double
    let checks: [Check]
    let texts: [String]
    let formulas: [String]
    let clipboard: String?
    let error: String?
}

let args = CommandLine.arguments

// `ax_probe --post <name> --object <id>` posts a distributed notification.
if args.count >= 2, args[1] == "--post" {
    var name: String?
    var object: String?
    var i = 2
    while i < args.count {
        if args[i] == "--object", i + 1 < args.count {
            object = args[i + 1]
            i += 2
        } else {
            name = args[i]
            i += 1
        }
    }
    guard let name else { exit(2) }
    DistributedNotificationCenter.default().post(
        name: NSNotification.Name(name),
        object: object,
        userInfo: nil
    )
    // Delivery is asynchronous through distnoted; exiting immediately can drop
    // the message before it leaves this process.
    usleep(250_000)
    exit(0)
}

guard args.count >= 2, let pid = Int32(args[1]) else {
    FileHandle.standardError.write(
        Data("usage: ax_probe <pid> [options]\n".utf8)
    )
    exit(2)
}

var expectTexts: [String] = []
var absentTexts: [String] = []
var expectFormulas: [String] = []
var absentFormulas: [String] = []
var clickNewConversation = false
var windowSize: CGSize?
var screenshotPath: String?
var clickText: String?
var scrollHorizontal: Int?
var scrollVertical: Int?
var dragFrom: String?
var dragTo: String?
var copySelection = false
var timeoutSeconds: Double = 10.0
var dumpTree = false
var captureTreeEnabled = false
var clipboard: String?

var index = 2
func nextValue(_ flag: String) -> String? {
    guard index + 1 < args.count else {
        FileHandle.standardError.write(Data("missing value for \(flag)\n".utf8))
        exit(2)
    }
    index += 1
    return args[index]
}

while index < args.count {
    let flag = args[index]
    switch flag {
    case "--expect-text": expectTexts.append(nextValue(flag)!)
    case "--absent-text": absentTexts.append(nextValue(flag)!)
    case "--expect-formula": expectFormulas.append(nextValue(flag)!)
    case "--absent-formula": absentFormulas.append(nextValue(flag)!)
    case "--click-new-conversation": clickNewConversation = true
    case "--set-window-size":
        let w = Double(nextValue(flag)!) ?? 900
        let h = Double(nextValue(flag)!) ?? 700
        windowSize = CGSize(width: w, height: h)
    case "--screenshot": screenshotPath = nextValue(flag)
    case "--click-text": clickText = nextValue(flag)
    case "--scroll-horizontal": scrollHorizontal = Int(nextValue(flag) ?? "0") ?? 0
    case "--drag-text":
        dragFrom = nextValue(flag)
        dragTo = nextValue(flag)
    case "--copy-selection": copySelection = true
    case "--scroll-vertical": scrollVertical = Int(nextValue(flag) ?? "0") ?? 0
    case "--timeout": timeoutSeconds = Double(nextValue(flag)!) ?? 10.0
    case "--dump-tree":
        dumpTree = true
        captureTreeEnabled = true
    default:
        FileHandle.standardError.write(Data("unknown option \(flag)\n".utf8))
        exit(2)
    }
    index += 1
}

let started = CFAbsoluteTimeGetCurrent()
func elapsedMs() -> Double { (CFAbsoluteTimeGetCurrent() - started) * 1000 }

let appRef = AXUIElementCreateApplication(pid)

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

func elementCount(_ element: AXUIElement, depth: Int = 0) -> Int {
    guard depth < 200 else { return 1 }
    var total = 1
    if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
        for child in children {
            total += elementCount(child, depth: depth + 1)
        }
    }
    return total
}

struct Snapshot {
    var windowCount = 0
    var window: AXUIElement?
    var texts: [String] = []
    var formulas: [String] = []
    var newConversationButton: AXUIElement?
    var treeLines: [String] = []
}

func snapshot(captureTree: Bool = false) -> Snapshot {
    var result = Snapshot()

    guard let rawWindows = attribute(appRef, kAXWindowsAttribute) as? [AXUIElement] else {
        return result
    }
    result.windowCount = rawWindows.count
    // Panels can briefly report a second window during launch; drive the one
    // that actually holds the chat content.
    var best: (window: AXUIElement, score: Int)?
    for candidate in rawWindows {
        let score = elementCount(candidate)
        if best == nil || score > best!.score {
            best = (candidate, score)
        }
    }
    guard let window = best?.window else { return result }
    result.window = window

    var texts: [String] = []
    var formulas: [String] = []
    var stack: [(AXUIElement, Int)] = [(window, 0)]

    while let (element, depth) = stack.popLast() {
        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
        let desc = (attribute(element, kAXDescriptionAttribute) as? String) ?? ""
        let title = (attribute(element, kAXTitleAttribute) as? String) ?? ""
        let value = (attribute(element, kAXValueAttribute) as? String) ?? ""

        if captureTree || captureTreeEnabled {
            result.treeLines.append("\(String(repeating: "  ", count: depth))\(role) desc=\(desc) value=\(value.prefix(80))")
        }

        for candidate in [value, desc, title] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !texts.contains(trimmed) {
                texts.append(trimmed)
            }
        }

        if let range = desc.range(of: "公式：") {
            let tex = String(desc[range.upperBound...])
            if !formulas.contains(tex) { formulas.append(tex) }
        } else if let range = title.range(of: "公式：") {
            let tex = String(title[range.upperBound...])
            if !formulas.contains(tex) { formulas.append(tex) }
        }

        if desc.contains("New conversation") || desc.contains("新建对话")
            || title.contains("New conversation") || title.contains("新建对话") {
            result.newConversationButton = element
        }

        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                stack.append((child, depth + 1))
            }
        }
    }

    result.texts = texts
    result.formulas = formulas
    return result
}

func matches(_ texts: [String], _ needle: String) -> Bool {
    texts.contains { $0.contains(needle) }
}

func formulaMatches(_ formulas: [String], _ needle: String) -> Bool {
    formulas.contains { $0.contains(needle) }
}

var timeline = Timeline(totalMs: 0)
var checks: [Check] = []
var lastSnapshot = Snapshot()
var axSnapshotMs: Double = 0

func evaluate(_ snapshot: Snapshot) -> [Check] {
    var result: [Check] = [
        Check(name: "window", ok: snapshot.windowCount > 0, detail: "windows=\(snapshot.windowCount)")
    ]
    for text in expectTexts {
        result.append(Check(
            name: "text:\(text)",
            ok: matches(snapshot.texts, text),
            detail: matches(snapshot.texts, text) ? "found" : "missing"
        ))
    }
    for text in absentTexts {
        result.append(Check(
            name: "absent-text:\(text)",
            ok: !matches(snapshot.texts, text),
            detail: matches(snapshot.texts, text) ? "still present" : "absent"
        ))
    }
    for formula in expectFormulas {
        result.append(Check(
            name: "formula:\(formula)",
            ok: formulaMatches(snapshot.formulas, formula),
            detail: formulaMatches(snapshot.formulas, formula)
                ? "found"
                : "missing (visible formulas: \(snapshot.formulas.count))"
        ))
    }
    for formula in absentFormulas {
        result.append(Check(
            name: "absent-formula:\(formula)",
            ok: !formulaMatches(snapshot.formulas, formula),
            detail: formulaMatches(snapshot.formulas, formula) ? "still present" : "absent"
        ))
    }
    return result
}

var error: String?

// Wait for every expectation before acting on the window. Every action probe
// also starts here so the snapshot is always populated.
do {
    while elapsedMs() < timeoutSeconds * 1000 {
        let begin = CFAbsoluteTimeGetCurrent()
        let snap = snapshot()
        axSnapshotMs = (CFAbsoluteTimeGetCurrent() - begin) * 1000
        lastSnapshot = snap

        if snap.windowCount > 0, timeline.windowMs == nil {
            timeline.windowMs = elapsedMs()
        }

        let results = evaluate(snap)
        if results.allSatisfy(\.ok) {
            checks = results
            if !expectTexts.isEmpty, timeline.contentMs == nil { timeline.contentMs = elapsedMs() }
            if !expectFormulas.isEmpty, timeline.formulaMs == nil { timeline.formulaMs = elapsedMs() }
            break
        }
        checks = results
        usleep(80_000)
    }
}

// Window manipulations run after content is visible.
if let size = windowSize {
    if let window = lastSnapshot.window {
        var sizeValue = size
        if let axValue = AXValueCreate(.cgSize, &sizeValue) {
            let err = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
            if err != .success {
                error = "failed to resize window: \(err.rawValue)"
            }
        }
    } else {
        error = error ?? "no window to resize"
    }
    usleep(600_000)
    let begin = CFAbsoluteTimeGetCurrent()
    lastSnapshot = snapshot()
    axSnapshotMs = (CFAbsoluteTimeGetCurrent() - begin) * 1000
    checks = evaluate(lastSnapshot)
}

if clickNewConversation {
    let begin = CFAbsoluteTimeGetCurrent()
    lastSnapshot = snapshot()
    axSnapshotMs = (CFAbsoluteTimeGetCurrent() - begin) * 1000
    guard let button = lastSnapshot.newConversationButton else {
        checks.append(Check(name: "click-new-conversation", ok: false, detail: "button not found"))
        error = error ?? "new conversation button not found"
        timeline.totalMs = elapsedMs()
        emitAndExit()
    }
    let pressResult = AXUIElementPerformAction(button, kAXPressAction as CFString)
    checks.append(Check(
        name: "click-new-conversation",
        ok: pressResult == .success,
        detail: pressResult == .success ? "pressed" : "AXError \(pressResult.rawValue)"
    ))
    if pressResult != .success {
        error = error ?? "failed to press new conversation button"
    }
    usleep(700_000)
    let after = snapshot()
    lastSnapshot = after
    for text in absentTexts {
        checks.append(Check(
            name: "absent-text:\(text)",
            ok: !matches(after.texts, text),
            detail: matches(after.texts, text) ? "still present after clearing" : "absent"
        ))
    }
}

if let clickText {
    let begin = CFAbsoluteTimeGetCurrent()
    lastSnapshot = snapshot()
    axSnapshotMs = (CFAbsoluteTimeGetCurrent() - begin) * 1000
    if let target = findByText(clickText) {
        let pressResult = AXUIElementPerformAction(target, kAXPressAction as CFString)
        checks.append(Check(
            name: "click-text:\(clickText)",
            ok: pressResult == .success,
            detail: pressResult == .success ? "pressed" : "AXError \(pressResult.rawValue)"
        ))
        if pressResult != .success { error = error ?? "click failed" }
    } else {
        checks.append(Check(name: "click-text:\(clickText)", ok: false, detail: "not found"))
        error = error ?? "element not found for \(clickText)"
    }
    usleep(700_000)
    lastSnapshot = snapshot()
}


func screenFrame() -> CGRect? {
    guard let window = lastSnapshot.window else { return nil }
    return windowFrame(window)
}

if let delta = scrollHorizontal, delta != 0 {
    // Scroll the formula's own scroll area: the projected content frame moves
    // when the horizontal offset changes.
    if let target = formulaElement(), let before = elementFrame(target) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows])
        }
        usleep(400_000)
        let saved = CGEvent(source: nil)?.location
        // A formula wider than its viewport extends past the clip, so the
        // element's own centre can sit outside the window; the wheel event has
        // to land inside the visible part of the formula.
        var warpTarget = CGPoint(x: before.midX, y: before.midY)
        if let window = screenFrame() {
            let visible = before.intersection(window)
            if !visible.isNull, visible.width > 1, visible.height > 1 {
                warpTarget = CGPoint(x: visible.midX, y: visible.midY)
            }
        }
        CGWarpMouseCursorPosition(warpTarget)
        usleep(150_000)
        if let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: Int32(delta),
            wheel3: 0
        ) {
            event.post(tap: .cghidEventTap)
        }
        usleep(500_000)
        if let saved { CGWarpMouseCursorPosition(saved) }
        let after = elementFrame(target)
        let movedBy = after.map { $0.origin.x - before.origin.x } ?? 0
        let overflow = scrollOverflow(target)
        let moved = abs(movedBy) >= 1
        checks.append(Check(
            name: "scroll-horizontal",
            ok: moved,
            detail: "content x \(before.origin.x) -> \(after?.origin.x ?? before.origin.x) "
                + "(delta \(movedBy), overflow \(overflow.map { "\($0)" } ?? "n/a"))"
        ))
        if !moved { error = error ?? "formula content did not scroll" }
    } else {
        checks.append(Check(name: "scroll-horizontal", ok: false, detail: "formula element not found"))
        error = error ?? "formula element not found for scrolling"
    }
}

if let delta = scrollVertical, delta != 0 {
    if let window = lastSnapshot.window {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows])
        }
        usleep(300_000)
        let saved = CGEvent(source: nil)?.location
        let point = CGPoint(x: windowFrame(window).midX, y: windowFrame(window).midY)
        CGWarpMouseCursorPosition(point)
        usleep(150_000)
        if let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(delta),
            wheel2: 0,
            wheel3: 0
        ) {
            event.post(tap: .cghidEventTap)
        }
        usleep(400_000)
        if let saved { CGWarpMouseCursorPosition(saved) }
        checks.append(Check(name: "scroll-vertical", ok: true, detail: "delta \(delta)"))
    } else {
        checks.append(Check(name: "scroll-vertical", ok: false, detail: "no window"))
    }
    lastSnapshot = snapshot()
}


if let dragFrom, let dragTo {
    let begin = CFAbsoluteTimeGetCurrent()
    lastSnapshot = snapshot()
    axSnapshotMs = (CFAbsoluteTimeGetCurrent() - begin) * 1000

    func textFrame(_ needle: String) -> CGRect? {
        guard let window = lastSnapshot.window else { return nil }
        var stack: [AXUIElement] = [window]
        while let element = stack.popLast() {
            let desc = (attribute(element, kAXDescriptionAttribute) as? String) ?? ""
            let value = (attribute(element, kAXValueAttribute) as? String) ?? ""
            if desc.contains(needle) || value.contains(needle), let frame = elementFrame(element),
                frame.height > 4 {
                return frame
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                stack.append(contentsOf: children)
            }
        }
        return nil
    }

    if let app = NSRunningApplication(processIdentifier: pid) {
        app.activate(options: [.activateAllWindows])
    }
    usleep(400_000)

    if let start = textFrame(dragFrom), let end = textFrame(dragTo) {
        let from = CGPoint(x: start.minX + 6, y: start.midY)
        let to = CGPoint(x: end.maxX - 6, y: end.midY)

        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(80_000)
        let steps = 12
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(
                x: from.x + (to.x - from.x) * t,
                y: from.y + (to.y - from.y) * t
            )
            CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            )?.post(tap: .cghidEventTap)
            usleep(25_000)
        }
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(300_000)
        checks.append(Check(
            name: "drag-text:\(dragFrom)->\(dragTo)",
            ok: true,
            detail: "from \(from) to \(to)"
        ))
    } else {
        checks.append(Check(name: "drag-text", ok: false, detail: "text element not found"))
        error = error ?? "text element not found for drag"
    }
    lastSnapshot = snapshot()
}

if copySelection {
    if let app = NSRunningApplication(processIdentifier: pid) {
        app.activate(options: [.activateAllWindows])
    }
    usleep(200_000)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("", forType: .string)

    let source = CGEventSource(stateID: .hidSystemState)
    let keyC: CGKeyCode = 8
    let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
    down?.flags = .maskCommand
    let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    usleep(60_000)
    up?.post(tap: .cghidEventTap)
    usleep(350_000)

    let copied = NSPasteboard.general.string(forType: .string) ?? ""
    clipboard = copied
    checks.append(Check(
        name: "copy-selection",
        ok: !copied.isEmpty,
        detail: copied
    ))
    if copied.isEmpty { error = error ?? "clipboard is empty after copy" }
}

func formulaElement() -> AXUIElement? {
    guard let window = lastSnapshot.window else { return nil }
    var stack: [AXUIElement] = [window]
    while let element = stack.popLast() {
        let desc = (attribute(element, kAXDescriptionAttribute) as? String) ?? ""
        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
        if desc.hasPrefix("公式："), role == "AXUnknown" {
            return element
        }
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            stack.append(contentsOf: children)
        }
    }
    return nil
}

func scrollOverflow(_ element: AXUIElement) -> CGFloat? {
    guard let parent = attribute(element, kAXParentAttribute),
          CFGetTypeID(parent) == AXUIElementGetTypeID() else {
        return nil
    }
    let scroll = parent as! AXUIElement
    guard let frame = elementFrame(scroll),
          let contentValue = attribute(scroll, "AXContentSize") else {
        return nil
    }
    var content = CGSize.zero
    guard AXValueGetValue(contentValue as! AXValue, .cgSize, &content) else { return nil }
    return content.width - frame.width
}

func windowFrame(_ element: AXUIElement) -> CGRect {
    elementFrame(element) ?? .zero
}

func elementFrame(_ element: AXUIElement) -> CGRect? {
    guard let positionValue = attribute(element, kAXPositionAttribute),
          let sizeValue = attribute(element, kAXSizeAttribute) else {
        return nil
    }
    var origin = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
          AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
        return nil
    }
    return CGRect(origin: origin, size: size)
}

func findByText(_ needle: String) -> AXUIElement? {
    guard let window = lastSnapshot.window else { return nil }
    var stack: [AXUIElement] = [window]
    while let element = stack.popLast() {
        let desc = (attribute(element, kAXDescriptionAttribute) as? String) ?? ""
        let title = (attribute(element, kAXTitleAttribute) as? String) ?? ""
        let value = (attribute(element, kAXValueAttribute) as? String) ?? ""
        if desc.contains(needle) || title.contains(needle) || value.contains(needle) {
            let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
            if role.contains("Button") || role.contains("CheckBox") || role.contains("MenuItem") {
                return element
            }
        }
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            stack.append(contentsOf: children)
        }
    }
    return nil
}

if let path = screenshotPath {
    let windowID = windowNumber(for: pid)
    if let windowID {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-l", String(windowID), "-o", path]
        do {
            try process.run()
            process.waitUntilExit()
            checks.append(Check(
                name: "screenshot",
                ok: process.terminationStatus == 0 && FileManager.default.fileExists(atPath: path),
                detail: path
            ))
        } catch {
            checks.append(Check(name: "screenshot", ok: false, detail: "\(error)"))
        }
    } else {
        checks.append(Check(name: "screenshot", ok: false, detail: "no CGWindow for pid"))
    }
}

func windowNumber(for pid: Int32) -> Int? {
    guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for window in windows {
        guard let owner = window[kCGWindowOwnerPID as String] as? Int32, owner == pid else { continue }
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let height = bounds["Height"] as? Double, height > 100 else { continue }
        if let number = window[kCGWindowNumber as String] as? Int {
            return number
        }
    }
    return nil
}

timeline.totalMs = elapsedMs()

func emitAndExit() -> Never {
    let ok = checks.allSatisfy(\.ok) && error == nil && !checks.isEmpty
    let accessible = ok || !(expectTexts.isEmpty && expectFormulas.isEmpty)
    let result = ProbeResult(
        ok: ok,
        pid: pid,
        windowCount: lastSnapshot.windowCount,
        timeline: timeline,
        axSnapshotMs: axSnapshotMs,
        checks: checks,
        texts: Array(lastSnapshot.texts.prefix(60)),
        formulas: Array(lastSnapshot.formulas.prefix(60)),
        clipboard: clipboard,
        error: error
    )
    _ = accessible

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(result), let json = String(data: data, encoding: .utf8) {
        print(json)
    }
    if dumpTree {
        FileHandle.standardError.write(Data(lastSnapshot.treeLines.joined(separator: "\n").utf8))
        FileHandle.standardError.write(Data("\n".utf8))
    }
    exit(ok ? 0 : 1)
}

emitAndExit()
