import AbakusCore
import AbakusUI
import AppKit
import SwiftUI

struct SnapshotOptions {
    var output: URL
    var account: String?
    var scale = 2
    var collapsedSidebar = false
    var width: CGFloat?
    var height: CGFloat?
    var selectNewest = 0
    var expandSplits = false
    var edit: EditHarness.State?
    var ops: OpsHarness.State?
    var nativeMenus = false
    var ui: UIHarness.State?
    var budget: BudgetHarness.State?
    var month: DateWithoutTime?
    var testEdits = false
    var trace = false
    var colorScheme = ColorScheme.light
    var contrast = ColorSchemeContrast.standard

    init(arguments: [String]) throws {
        var output: String?
        var remaining = arguments[...]
        func value(of flag: String) throws -> String {
            guard let value = remaining.popFirst() else { throw SnapshotError.invalid("\(flag) needs a value") }
            return value
        }
        func number<Number: LosslessStringConvertible & Comparable>(of flag: String, atLeast minimum: Number) throws
            -> Number
        {
            let text = try value(of: flag)
            guard let number = Number(text), number >= minimum else {
                throw SnapshotError.invalid("\(flag) \(text) is not a number of at least \(minimum)")
            }
            return number
        }
        func state<State: RawRepresentable<String>>(of flag: String) throws -> State {
            let text = try value(of: flag)
            guard let state = State(rawValue: text) else { throw SnapshotError.invalid("unknown \(flag) \(text)") }
            return state
        }
        while let argument = remaining.popFirst() {
            switch argument {
            case "--account": account = try value(of: argument)
            case "--scale": scale = try number(of: argument, atLeast: 1)
            case "--collapsed-sidebar": collapsedSidebar = true
            case "--width": width = CGFloat(try number(of: argument, atLeast: 1.0))
            case "--height": height = CGFloat(try number(of: argument, atLeast: 1.0))
            case "--expand-splits": expandSplits = true
            case "--select": selectNewest = try number(of: argument, atLeast: 0)
            case "--edit": edit = try state(of: argument)
            case "--native-menus": nativeMenus = true
            case "--ops": ops = try state(of: argument)
            case "--ui": ui = try state(of: argument)
            case "--budget": budget = try state(of: argument)
            case "--month":
                let text = try value(of: argument)
                guard let first = DateWithoutTime(string: text + "-01") else {
                    throw SnapshotError.invalid("--month \(text) is not a month like 2023-05")
                }
                month = first
            case "--test-edits": testEdits = true
            case "--trace": trace = true
            case "--dark": colorScheme = .dark
            case "--increase-contrast": contrast = .increased
            case _ where argument.hasPrefix("-"): throw SnapshotError.invalid("unknown option \(argument)")
            default:
                guard output == nil else { throw SnapshotError.invalid("a second output path \(argument)") }
                output = argument
            }
        }
        guard let output else { throw SnapshotError.usage }
        if nativeMenus && ops != .keys {
            throw SnapshotError.invalid("--native-menus needs --ops keys: a native menu elsewhere waits for a click")
        }
        if budget == nil && (month != nil || testEdits) {
            throw SnapshotError.invalid("--month and --test-edits need --budget")
        }
        self.output = URL(fileURLWithPath: output)
    }
}

enum SnapshotError: Error, CustomStringConvertible {
    case usage
    case invalid(String)
    case unknownAccount(String)
    case render

    var description: String {
        switch self {
        case .usage: Self.usageText
        case .invalid(let problem): problem + "\n" + Self.usageText
        case .unknownAccount(let name): "no account named \(name)"
        case .render: "rendering failed"
        }
    }

    private static var usageText: String {
        "usage: Snapshot <out.png> [--account <name>] [--scale 2] [--collapsed-sidebar] "
            + "[--width 1020] [--height 700] [--dark] [--increase-contrast] [--select <newest n rows>] "
            + "[--expand-splits] [--trace] [--edit "
            + EditHarness.State.allCases.map(\.rawValue).joined(separator: "|") + "] [--ops "
            + OpsHarness.State.allCases.map(\.rawValue).joined(separator: "|") + "] [--native-menus] [--ui "
            + UIHarness.State.allCases.map(\.rawValue).joined(separator: "|") + "] [--budget "
            + BudgetHarness.State.allCases.map(\.rawValue).joined(separator: "|")
            + " [--month 2023-05] [--test-edits]]"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

@MainActor
func selection(named name: String?, in budget: Budget) throws -> SidebarSelection? {
    switch name {
    case nil: return nil
    case Account.allAccountsName: return .allAccounts
    case "Budget": return .budget
    case let name?:
        guard let account = budget.account(named: name) else { throw SnapshotError.unknownAccount(name) }
        return .account(account.id)
    }
}

/// AppKit hands out its Increase Contrast appearances only while the setting is on, so they come from the system bundle.
@MainActor
func appearance(_ scheme: ColorScheme, contrast: ColorSchemeContrast) -> NSAppearance? {
    let standard = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    guard contrast == .increased,
        let bundle = Bundle(path: "/System/Library/CoreServices/SystemAppearance.bundle")
    else { return standard }
    let name = NSAppearance.Name(scheme == .dark ? "DarkAquaAX" : "AquaAX")
    return NSAppearance(appearanceNamed: name, bundle: bundle) ?? standard
}

/// SwiftUI resolves its styles inside split view columns and `Color(nsColor:)` from the workspace's setting, not from
/// the environment, so this process alone is told that Increase Contrast is on.
@MainActor
func reportIncreasedContrast() {
    guard
        let method = class_getInstanceMethod(
            NSWorkspace.self, #selector(getter: NSWorkspace.accessibilityDisplayShouldIncreaseContrast))
    else { return }
    let increased: @convention(block) (NSWorkspace) -> Bool = { _ in true }
    method_setImplementation(method, imp_implementationWithBlock(increased))
}

/// Alerts show the app icon, which this unbundled process lacks, so it is compiled as `tools/make_app.sh` does and kept
/// until the icon document changes.
@MainActor
func useAppIcon() {
    let files = FileManager.default
    let document = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../Abakus/AppIcon.icon").standardized
    guard
        let cache = files.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "AbakusSnapshot")
    else { return }
    let icns = cache.appending(path: "AppIcon.icns")
    func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
    let sources = (files.enumerator(at: document, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
    if !files.fileExists(atPath: icns.path) || sources.contains(where: { modified($0) > modified(icns) }) {
        try? files.createDirectory(at: cache, withIntermediateDirectories: true)
        let actool = Process()
        actool.executableURL = URL(filePath: "/usr/bin/xcrun")
        actool.arguments = [
            "actool", document.path, "--compile", cache.path, "--platform", "macosx", "--minimum-deployment-target",
            "26.0", "--app-icon", "AppIcon", "--output-partial-info-plist", cache.appending(path: "icon.plist").path,
        ]
        actool.standardOutput = FileHandle.nullDevice
        guard (try? actool.run()) != nil else { return }
        actool.waitUntilExit()
    }
    if let icon = NSImage(contentsOf: icns) { NSApplication.shared.applicationIconImage = icon }
}

@MainActor
func render(_ options: SnapshotOptions) throws {
    useAppIcon()
    if options.contrast == .increased { reportIncreasedContrast() }
    NSApplication.shared.appearance = appearance(options.colorScheme, contrast: options.contrast)
    let budget: Budget
    let store: BudgetStore
    if options.budget != nil {
        budget = try BudgetReference.budget(testEdits: options.testEdits)
        store = BudgetStore(budget: budget, today: { BudgetReference.today })
    } else {
        budget = DemoBudget.make(today: .today())
        store = BudgetStore(budget: budget)
    }
    let model = AppModel(
        store: store,
        selection: options.budget != nil ? .budget : try selection(named: options.account, in: store.budget),
        defaults: nil)
    if options.collapsedSidebar { model.sidebar.toggleSidebar() }
    if options.expandSplits {
        for transaction in model.register.transactions where transaction.isSplit {
            model.register.toggleSplit(transaction.id)
        }
    }
    if options.selectNewest > 0 {
        for id in model.register.transactionIds.prefix(options.selectNewest) {
            model.register.rowClicked(
                model.register.rows.first { $0.id == id }!, column: nil, modifiers: .command)
        }
    }
    var size = MainWindowMetrics.defaultSize
    size.width = options.width ?? size.width
    size.height = options.height ?? size.height
    let menus = options.nativeMenus ? nil : SnapshotMenus()
    let host = NSHostingView(
        rootView: SnapshotWindowContent(model: model, menus: menus)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, options.colorScheme)
            .environment(\._colorSchemeContrast, options.contrast))
    host.frame = NSRect(origin: .zero, size: size)
    host.sceneBridgingOptions = .all
    // SwiftUI gives the app's window a full-size content view, which runs the sidebar up under the toolbar.
    let window = NSWindow(
        contentRect: host.frame, styleMask: MainWindowMetrics.styleMask.union(.fullSizeContentView),
        backing: .buffered, defer: false)
    window.contentView = host
    // Beyond every screen, so the user neither sees the window, its sheets and child windows nor points at them; SwiftUI
    // presents sheets only on a window that is ordered in.
    let screens = NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }
    window.setFrameOrigin(NSPoint(x: screens.minX - size.width - 100, y: screens.minY))
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    host.layoutSubtreeIfNeeded()
    if let state = options.edit {
        try EditHarness(model: model, window: window, trace: options.trace).run(state)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
    }
    if let state = options.ui {
        try UIHarness(model: model, edit: EditHarness(model: model, window: window)).run(state)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
    }
    if let state = options.budget {
        try BudgetHarness(model: model, edit: EditHarness(model: model, window: window)).run(
            state, month: options.month)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
    }
    if let state = options.ops {
        try OpsHarness(model: model, edit: EditHarness(model: model, window: window), menus: menus).run(state)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
    }
    drawAsKey(window)
    let rep = try capture(window, scale: options.scale)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.render }
    try png.write(to: options.output)
    print("wrote \(options.output.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
}

/// Tells the window and its frontmost sheet that they are main and key, as in the active app, without activating it:
/// `makeKey` would take the keyboard from the user's frontmost app.
@MainActor
func drawAsKey(_ window: NSWindow) {
    var key = window
    while let sheet = key.attachedSheet { key = sheet }
    window.becomeMain()
    key.becomeKey()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}

/// The window server draws what `cacheDisplay` leaves out: the sidebar's glass, selection material and vibrant text,
/// and the shape, material and shadow of sheets, alerts and child windows.
@MainActor
func capture(_ window: NSWindow, scale: Int) throws -> NSBitmapImageRep {
    typealias CreateImage =
        @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
    typealias CreateImageFromArray = @convention(c) (CGRect, CFArray, CGWindowImageOption) -> Unmanaged<CGImage>?
    // Swift hides the deprecated calls, which still capture the process's own windows without screen recording access.
    let library = dlopen(nil, RTLD_NOW)
    guard let single = dlsym(library, "CGWindowListCreateImage"),
        let multiple = dlsym(library, "CGWindowListCreateImageFromArray")
    else { throw SnapshotError.render }
    window.displayIfNeeded()
    func windowImage() -> CGImage? {
        unsafeBitCast(single, to: CreateImage.self)(
            .null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]
        )?.takeRetainedValue()
    }
    // A cold window server, as on a CI runner, hands out the window blank for a while after it was ordered in.
    let deadline = Date().addingTimeInterval(10)
    var drawn: CGImage?
    repeat {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        drawn = windowImage()
    } while drawn.map(isBlank) ?? true && Date() < deadline
    let frame = window.frame
    guard
        let image = drawn, !isBlank(image),
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(frame.width) * scale, pixelsHigh: Int(frame.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else { throw SnapshotError.render }
    rep.size = frame.size
    let target = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
    context.cgContext.interpolationQuality = .high
    context.cgContext.draw(image, in: target)
    var ids = attachedWindows(of: window).map { UnsafeRawPointer(bitPattern: $0.windowNumber) }
    guard !ids.isEmpty else { return rep }
    // The window server's coordinates start at the top left of the main screen.
    let bounds = CGRect(
        x: frame.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - frame.maxY, width: frame.width,
        height: frame.height)
    guard let windows = CFArrayCreate(nil, &ids, ids.count, nil),
        let attached = unsafeBitCast(multiple, to: CreateImageFromArray.self)(bounds, windows, .bestResolution)?
            .takeRetainedValue()
    else { throw SnapshotError.render }
    context.cgContext.draw(attached, in: target)
    return rep
}

/// Every pixel alike, as in a window the window server has not drawn yet.
func isBlank(_ image: CGImage) -> Bool {
    let side = 32
    var pixels = [UInt32](repeating: 0, count: side * side)
    let drawn = pixels.withUnsafeMutableBytes { buffer in
        guard
            let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return true
    }
    return drawn && Set(pixels).count == 1
}

/// Sheets, alerts and child windows such as the search suggestions, with their own sheets and child windows.
@MainActor
func attachedWindows(of window: NSWindow) -> [NSWindow] {
    let attached = (window.childWindows ?? []) + [window.attachedSheet].compactMap { $0 }
    return attached.filter(\.isVisible).flatMap { [$0] + attachedWindows(of: $0) }
}

do {
    let options = try SnapshotOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    try MainActor.assumeIsolated { try render(options) }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
