import AppKit

/// A transparent, borderless window covering the whole screen. It ignores the mouse
/// except when the pointer is over the dog or one of its toys.
final class PetWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class PetView: NSView {
    weak var world: World?
    var menuProvider: (() -> NSMenu)?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let w = world else { return }
        ctx.clear(dirtyRect)
        w.draw(ctx)
    }

    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }
    override func mouseDown(with e: NSEvent) { world?.mouseDown(point(e), clicks: e.clickCount) }
    override func mouseDragged(with e: NSEvent) { world?.mouseDragged(point(e)) }
    override func mouseUp(with e: NSEvent) { world?.mouseUp(point(e)) }
    override func rightMouseDown(with e: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: e, for: self)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var window: PetWindow!
    private var view: PetView!
    private var world: World!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var lastDirty = CGRect.zero
    private var hidden = false
    private var titleClock: Double = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        window = PetWindow(screen: screen)
        view = PetView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        window.contentView = view
        world = World(bounds: view.bounds, groundY: groundY(for: screen))
        view.world = world
        view.menuProvider = { [unowned self] in
            let m = NSMenu()
            m.autoenablesItems = false
            self.populate(m)
            return m
        }
        window.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐶"
        statusItem.button?.toolTip = "DummyPet"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func applicationWillTerminate(_ notification: Notification) {
        world?.save()
    }

    private func groundY(for screen: NSScreen) -> CGFloat {
        max(0, screen.visibleFrame.minY - screen.frame.minY) + 2
    }

    @objc private func screensChanged() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        window.setFrame(screen.frame, display: true)
        view.frame = CGRect(origin: .zero, size: screen.frame.size)
        world.resize(bounds: view.bounds, groundY: groundY(for: screen))
        view.needsDisplay = true
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.05)
        lastTick = now

        let m = NSEvent.mouseLocation
        let local = CGPoint(x: m.x - window.frame.minX, y: m.y - window.frame.minY)
        world.update(dt: dt, mouse: local)

        if !hidden {
            let ignore = !world.wantsMouse(at: local)
            if window.ignoresMouseEvents != ignore { window.ignoresMouseEvents = ignore }
            let dirty = world.dirtyRect()
            view.setNeedsDisplay(dirty.union(lastDirty))
            lastDirty = dirty
        }

        titleClock += dt
        if titleClock > 0.5 {
            titleClock = 0
            let title = world.needsAttention ? "🐶💭" : (world.isSleeping ? "🐶💤" : "🐶")
            if statusItem.button?.title != title { statusItem.button?.title = title }
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    private func bar(_ v: Double) -> String {
        let n = Int((v / 10).rounded())
        return String(repeating: "▰", count: n) + String(repeating: "▱", count: 10 - n)
    }

    private func info(_ menu: NSMenu, _ text: String, mono: Bool = false) {
        let it = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        if mono {
            it.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }
        it.isEnabled = false
        menu.addItem(it)
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?, tag: Int = 0, key: String = "",
                     enabled: Bool = true, on: Bool = false) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        it.tag = tag
        it.isEnabled = enabled
        it.state = on ? .on : .off
        menu.addItem(it)
        return it
    }

    private func populate(_ menu: NSMenu) {
        let st = world.stats
        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(string: "\(st.name)  ·  Bond Lv \(st.level)  ·  \(st.moodEmoji) \(st.moodWord)", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
        ])
        header.isEnabled = false
        menu.addItem(header)
        info(menu, "🍖 Food    \(bar(st.hunger))  \(Int(st.hunger))%", mono: true)
        info(menu, "🎾 Fun     \(bar(st.fun))  \(Int(st.fun))%", mono: true)
        info(menu, "⚡️ Energy  \(bar(st.energy))  \(Int(st.energy))%", mono: true)
        info(menu, "🛁 Clean   \(bar(st.hygiene))  \(Int(st.hygiene))%", mono: true)
        info(menu, "✨ XP      \(Int(st.xp)) / \(Int(st.xpForNext)) to Lv \(st.level + 1)", mono: true)
        menu.addItem(.separator())

        let asleep = world.isSleeping
        add(menu, "🍖  Feed", #selector(feed), key: "f")
        add(menu, "🦴  Give a Treat", #selector(treat), key: "t")
        add(menu, "🎾  Play Fetch", #selector(fetch), key: "b")
        add(menu, world.walkMode ? "🏠  End Walk" : "🦮  Go for a Walk", #selector(walk), key: "w", on: world.walkMode)
        add(menu, world.laserMode ? "🔴  Put Laser Away" : "🔴  Laser Pointer", #selector(laser), key: "l", on: world.laserMode)
        add(menu, "🛁  Bath Time", #selector(bath))
        add(menu, "📣  Come Here!", #selector(come), key: "c")
        add(menu, asleep ? "☀️  Wake Up" : "😴  Nap Time", #selector(nap))

        let tricksItem = NSMenuItem(title: "🎪  Tricks", action: nil, keyEquivalent: "")
        let tricks = NSMenu()
        tricks.autoenablesItems = false
        for t in Trick.allCases {
            let unlocked = st.level >= t.level
            let title = unlocked ? "\(t.emoji)  \(t.title)" : "🔒  \(t.title)  (Bond Lv \(t.level))"
            add(tricks, title, #selector(trick(_:)), tag: t.rawValue, enabled: unlocked)
        }
        tricksItem.submenu = tricks
        menu.addItem(tricksItem)

        let poops = world.poopCount
        if poops > 0 { add(menu, "🧹  Scoop the Poop (\(poops))", #selector(scoop)) }
        if world.hasToys { add(menu, "🧺  Put Toys Away", #selector(putAway)) }
        menu.addItem(.separator())

        let statsItem = NSMenuItem(title: "📊  Stats", action: nil, keyEquivalent: "")
        let sm = NSMenu()
        sm.autoenablesItems = false
        let days = max(1, (Calendar.current.dateComponents([.day], from: st.adopted, to: Date()).day ?? 0) + 1)
        info(sm, "📅  Best friends for \(days) day\(days == 1 ? "" : "s")")
        info(sm, "🐾  Steps walked: \(st.steps.formatted())")
        info(sm, "🎾  Fetches: \(st.fetches)")
        info(sm, "🦴  Treats eaten: \(st.treats)")
        info(sm, "🎪  Tricks performed: \(st.tricks)")
        info(sm, "💕  Pets & scritches: \(st.pets)")
        info(sm, "💎  Treasures dug up: \(st.treasures)")
        info(sm, "🧹  Poops scooped: \(st.poopsCleaned)")
        statsItem.submenu = sm
        menu.addItem(statsItem)

        let lookItem = NSMenuItem(title: "🎨  Appearance", action: nil, keyEquivalent: "")
        let look = NSMenu()
        look.autoenablesItems = false
        for (i, c) in Coat.all.enumerated() {
            add(look, c.name, #selector(coat(_:)), tag: i, on: st.coat == i)
        }
        look.addItem(.separator())
        for (i, name) in ["Small", "Medium", "Large"].enumerated() {
            add(look, name, #selector(size(_:)), tag: i, on: st.size == i)
        }
        look.addItem(.separator())
        add(look, "Rename \(st.name)…", #selector(rename))
        lookItem.submenu = look
        menu.addItem(lookItem)

        add(menu, "🔊  Sounds", #selector(toggleSound), on: !st.muted)
        add(menu, hidden ? "👀  Show \(st.name)" : "🙈  Hide \(st.name)", #selector(toggleHide), key: "h")
        menu.addItem(.separator())
        add(menu, "How to Play…", #selector(help))
        add(menu, "Quit DummyPet", #selector(quit), key: "q")
    }

    // MARK: - Actions

    @objc private func feed() { world.feed() }
    @objc private func treat() { world.giveTreat() }
    @objc private func fetch() { world.playFetch() }
    @objc private func walk() { world.toggleWalk() }
    @objc private func laser() { world.toggleLaser() }
    @objc private func bath() { world.bath() }
    @objc private func come() { world.comeHere() }
    @objc private func nap() { world.napOrWake() }
    @objc private func scoop() { world.cleanAllPoop() }
    @objc private func putAway() { world.putAwayToys() }

    @objc private func trick(_ sender: NSMenuItem) {
        if let t = Trick(rawValue: sender.tag) { world.doTrick(t) }
    }

    @objc private func coat(_ sender: NSMenuItem) {
        world.stats.coat = sender.tag
        world.say(["New look! ✨", "Do I look good? 😎", "Fancy!"].randomElement()!, 1.8)
        world.save()
    }

    @objc private func size(_ sender: NSMenuItem) {
        world.stats.size = sender.tag
        world.resize(bounds: world.bounds, groundY: world.groundY)
        world.save()
    }

    @objc private func toggleSound() {
        world.stats.muted.toggle()
        world.sound.muted = world.stats.muted
        world.save()
    }

    @objc private func toggleHide() {
        hidden.toggle()
        if hidden { window.orderOut(nil) } else { window.orderFrontRegardless(); view.needsDisplay = true }
    }

    @objc private func rename() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Rename your dog"
        alert.informativeText = "What should we call your best friend?"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = world.stats.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                world.stats.name = String(name.prefix(20))
                world.say("I'm \(world.stats.name)! 🐶", 2.4)
                world.save()
            }
        }
    }

    @objc private func help() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "How to play with \(world.stats.name)"
        alert.informativeText = """
        • Rub the cursor over your dog to pet it. Keep going for belly rubs!
        • Click to give a pat, double-click to make it bark.
        • Drag to pick it up — toss it gently, it lands on its feet.
        • Play Fetch: the ball sticks to your cursor. Flick the mouse and click to throw.
        • Give a Treat: hold it low to make your dog beg, toss it high for a mid-air catch.
        • Walks: your dog follows the leash on your cursor. Walk it across the screen!
        • Laser Pointer: just move the mouse around and watch the chaos.
        • Click poop to scoop it. Hover over your dog to see how it's feeling.
        • Tricks unlock as your Bond level grows. Right-click the dog any time for this menu.
        """
        alert.addButton(withTitle: "Got it!")
        alert.runModal()
    }

    @objc private func quit() {
        world.save()
        NSApp.terminate(nil)
    }
}
