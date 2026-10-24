import AppKit

/// Everything that lives on the overlay: the dog, its toys, and all the little effects.
final class World {
    private(set) var bounds: CGRect
    private(set) var groundY: CGFloat
    var stats: PetData
    let sound = Sound()
    let dog = Dog()

    private(set) var items: [Item] = []
    private var bowl: Bowl?
    private var particles: [Particle] = []
    private var bubble: Bubble?
    private var butterfly: Butterfly?
    private var flowers: [Flower] = []
    private var flowerFade: CGFloat = 0

    private(set) var walkMode = false
    private(set) var laserMode = false
    private var laserTime: CGFloat = 0
    private var walkDistance: CGFloat = 0

    private var mouse = CGPoint(-1000, -1000)
    private var mouseVel = CGPoint.zero
    private var mouseDelta: CGFloat = 0
    private(set) var time: Double = 0
    private var hoverTime: CGFloat = 0
    private var hudAlpha: CGFloat = 0
    private var rubAccum: CGFloat = 0
    private var rubStreak = 0
    private var lastRubTime: Double = -10
    private var lastHeartTime: Double = -10
    private(set) var heldItem: Item?
    private var draggingDog = false
    private var dogGrab = CGPoint.zero
    private var pressPoint: CGPoint?
    private var nextButterfly: Double = rndD(60, 150)
    private var nextNeed: Double = 45
    private var poopDue: Double?
    private var saveClock: Double = 0
    private var greeting: String
    private let gravity: CGFloat = 1700

    // Geometry cached once per frame
    private(set) var headWorld = CGPoint.zero
    private(set) var mouthWorld = CGPoint.zero
    private(set) var collarWorld = CGPoint.zero
    private(set) var bodyWorld = CGPoint.zero

    var scale: CGFloat { [0.85, 1.15, 1.5][clamp(stats.size, 0, 2)] }
    var coat: Coat { Coat.all[clamp(stats.coat, 0, Coat.all.count - 1)] }
    var needsAttention: Bool { min(stats.hunger, stats.fun, stats.energy, stats.hygiene) < 25 }
    var isSleeping: Bool { dog.act == .sleep || dog.act == .yawn }
    var poopCount: Int { items.filter { $0.kind == .poop }.count }
    var hasToys: Bool { items.contains { $0.kind != .poop } }
    private var minX: CGFloat { 50 * scale }
    private var maxX: CGFloat { max(minX + 1, bounds.width - 50 * scale) }
    private var isNight: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 23 || h < 6
    }

    private static let casual: Set<Act> = [.idle, .sit, .lie, .wander, .sniff, .playBow, .comeHere,
                                           .dig, .butterfly, .zoomies, .stretch]

    init(bounds: CGRect, groundY: CGFloat) {
        self.bounds = bounds
        self.groundY = groundY
        var s = PetData.load()
        let away = s.catchUp()
        if s.visits == 0 {
            greeting = "Hi! I'm \(s.name)! 🐶 Right-click me!"
        } else if away > 3 * 3600 {
            greeting = "You're back!! I missed you 💕"
        } else {
            greeting = ["Hi again! 👋", "Hiii! 🐾", "Woof! 😄"].randomElement()!
        }
        s.visits += 1
        stats = s
        sound.muted = stats.muted
        dog.x = -60 * scale
        dog.targetX = bounds.width * rnd(0.25, 0.6)
        setAct(.enter)
        updateFrames()
    }

    func resize(bounds: CGRect, groundY: CGFloat) {
        self.bounds = bounds
        self.groundY = groundY
        dog.x = clamp(dog.x, minX, maxX)
        for it in items { it.pos.x = clamp(it.pos.x, it.radius, bounds.width - it.radius) }
        if !flowers.isEmpty { makeFlowers() }
    }

    func save() { stats.save() }

    // MARK: - Frame update

    func update(dt rawDt: Double, mouse m: CGPoint) {
        let dt = CGFloat(rawDt)
        time += rawDt
        let delta = m - mouse
        if rawDt > 0 && mouse.x > -999 {
            mouseVel = mouseVel.mix(delta * (1 / dt), 0.45)
            mouseDelta = delta.length
        }
        mouse = m

        updateStats(rawDt)
        updateInteraction(dt)
        brain(dt)
        updatePose(dt)
        updateItems(dt)
        updateBowl(dt)
        updateButterfly(dt)
        updateParticles(dt)
        updateTimers(rawDt)
    }

    private func updateStats(_ dt: Double) {
        let sleeping = dog.act == .sleep
        let poops = Double(poopCount)
        stats.hunger -= dt * 100 / (3.5 * 3600)
        stats.fun -= dt * 100 / (2.5 * 3600) * (sleeping ? 0.3 : 1) + poops * dt * 0.004
        if sleeping {
            stats.energy += dt * 100 / (6 * 60)
        } else {
            stats.energy -= dt * 100 / (4 * 3600)
        }
        stats.hygiene -= dt * 100 / (10 * 3600) + poops * dt * 0.008
        clampStats()
    }

    private func clampStats() {
        stats.hunger = clamp(stats.hunger, 0, 100)
        stats.fun = clamp(stats.fun, 0, 100)
        stats.energy = clamp(stats.energy, 0, 100)
        stats.hygiene = clamp(stats.hygiene, 0, 100)
    }

    private func addFun(_ v: Double) { stats.fun += v; clampStats() }

    private func addXP(_ v: Double) {
        let before = stats.level
        stats.xp += v
        let after = stats.level
        if after > before { levelUp(after) }
    }

    private func levelUp(_ lvl: Int) {
        sound.play(.chime)
        for _ in 0..<40 {
            emit(.confetti, headWorld + CGPoint(rnd(-30, 30), rnd(10, 40)),
                 vel: CGPoint(rnd(-180, 180), rnd(150, 420)), life: rndD(1.4, 2.4), size: rnd(5, 9),
                 color: [rgb(0.98, 0.4, 0.45), rgb(0.35, 0.7, 0.98), rgb(0.99, 0.8, 0.25), rgb(0.45, 0.85, 0.5), rgb(0.75, 0.5, 0.95)].randomElement()!,
                 gravity: 400, vrot: rnd(-8, 8), drag: 1.2)
        }
        let learned = Trick.allCases.filter { $0.level == lvl }.map { $0.title }
        var msg = "Bond level \(lvl)! 🎉"
        if !learned.isEmpty { msg += " I learned \(learned.joined(separator: " & "))!" }
        say(msg, 4.5)
        save()
    }

    // MARK: - Pointer interaction (polled every frame, works even when clicks pass through)

    private func updateInteraction(_ dt: CGFloat) {
        let d = dog
        if let h = heldItem {
            h.pos = mouse
            h.vel = mouseVel
        }
        if draggingDog {
            d.x = clamp(mouse.x - dogGrab.x, minX, maxX)
            d.y = max(0, mouse.y - groundY - dogGrab.y)
            d.vx = 0; d.vy = 0
        }
        let over = dogHitRect().contains(mouse)
        if over && !draggingDog && heldItem == nil { hoverTime += dt } else { hoverTime = 0 }
        hudAlpha = lerp(hudAlpha, hoverTime > 0.8 ? 1 : 0, min(1, dt * 8))

        if over && !draggingDog && heldItem == nil && mouseDelta > 0.5 {
            rubAccum += mouseDelta
            lastRubTime = time
            if d.act == .bath {
                d.actTime += Double(mouseDelta) * 0.003
                if chance(0.4) {
                    emit(.bubble, mouse + CGPoint(rnd(-8, 8), rnd(-8, 8)), vel: CGPoint(rnd(-15, 15), rnd(30, 60)),
                         life: rndD(0.8, 1.4), size: rnd(3, 7), color: rgb(1, 1, 1))
                }
            }
            if rubAccum > 150 * scale {
                rubAccum = 0
                petted()
            }
        }
        if time - lastRubTime > 1.5 { rubStreak = 0 }
    }

    private func petted() {
        let d = dog
        rubStreak = time - lastHeartTime < 2 ? rubStreak + 1 : 1
        lastHeartTime = time
        d.happyTimer = 1.6
        emit(.heart, headWorld + CGPoint(rnd(-12, 12), 20 * scale), vel: CGPoint(rnd(-20, 20), rnd(50, 80)),
             life: rndD(1.1, 1.5), size: rnd(6, 9) * scale, color: rgb(0.96, 0.33, 0.45))
        addFun(1.5)
        stats.pets += 1
        addXP(0.6)
        if d.act == .sleep || d.act == .bath { return }
        if rubStreak >= 4 && [Act.idle, .sit, .lie].contains(d.act) {
            setAct(.bellyUp)
            if chance(0.6) { say("Belly rubs!! 🥰", 1.8) }
        } else if chance(0.06) {
            sound.play(.yip, volume: 0.5)
        }
    }

    func wantsMouse(at p: CGPoint) -> Bool {
        if heldItem != nil || draggingDog || pressPoint != nil { return true }
        if dogHitRect().contains(p) { return true }
        for it in items where !it.carried {
            if it.pos.distance(to: p) < it.radius + 12 { return true }
        }
        return false
    }

    func mouseDown(_ p: CGPoint, clicks: Int) {
        mouse = p
        if heldItem != nil { return }
        if let it = items.first(where: { !$0.carried && $0.kind != .poop && $0.pos.distance(to: p) < $0.radius + 12 }) {
            it.held = true
            it.thrown = false
            heldItem = it
            sound.play(.pop, volume: 0.6)
            return
        }
        if let pp = items.first(where: { $0.kind == .poop && $0.pos.distance(to: p) < $0.radius + 14 }) {
            cleanPoop(pp)
            return
        }
        if dogHitRect().contains(p) {
            pressPoint = p
            if clicks >= 2 && dog.act != .sleep { doubleClickDog() }
        }
    }

    func mouseDragged(_ p: CGPoint) {
        mouse = p
        if let pp = pressPoint, !draggingDog, p.distance(to: pp) > 6 { startDrag(from: pp) }
    }

    func mouseUp(_ p: CGPoint) {
        mouse = p
        if let h = heldItem {
            release(h)
        } else if draggingDog {
            releaseDog()
        } else if pressPoint != nil {
            clickDog()
        }
        pressPoint = nil
    }

    private func release(_ it: Item) {
        var v = mouseVel
        if v.length > 2800 { v = v.normalized * 2800 }
        it.held = false
        it.vel = v
        it.thrown = true
        heldItem = nil
        if v.length > 500 { sound.play(.whoosh, volume: 0.5) }
    }

    private func startDrag(from pp: CGPoint) {
        let d = dog
        draggingDog = true
        pressPoint = nil
        dogGrab = pp - CGPoint(d.x, groundY + d.y)
        dropCarried()
        if d.act == .sleep { say("!?", 1.2) } else if chance(0.45) { say(["Wheee!", "Hey! 😳", "Up we go!", "Where are we going?"].randomElement()!, 1.6) }
        setAct(.dragged)
    }

    private func releaseDog() {
        let d = dog
        draggingDog = false
        d.vx = clamp(mouseVel.x * 0.6, -900, 900)
        d.vy = clamp(mouseVel.y * 0.6, -200, 1100)
        if d.y > 2 || d.vy > 50 {
            setAct(.falling)
        } else {
            d.vx = 0; d.vy = 0
            setAct(.sit, 1.5)
        }
    }

    private func clickDog() {
        let d = dog
        switch d.act {
        case .sleep, .yawn:
            say(["😠 Hey! I was napping…", "Five more minutes… 😪", "Huh?! 😵‍💫"].randomElement()!)
            addFun(-2)
            setAct(.sit, 2)
        case .bath, .shake, .bellyUp:
            petted()
        default:
            d.happyTimer = 1.2
            emit(.heart, headWorld + CGPoint(0, 22 * scale), vel: CGPoint(0, 70), life: 1.2, size: 8 * scale, color: rgb(0.96, 0.33, 0.45))
            addFun(1)
            addXP(0.5)
            if chance(0.25) { bark() }
        }
    }

    private func doubleClickDog() {
        bark()
        say(["Woof! 🐶", "Bork!", "Arf arf!", "Yip! 😄"].randomElement()!, 1.4)
    }

    private func bark() {
        dog.barkTimer = 0.22
        sound.play(dog.y > 0 ? .yip : .bark)
    }

    // MARK: - Brain

    private func setAct(_ a: Act, _ dur: Double = 0) {
        dog.act = a
        dog.actTime = 0
        dog.actDuration = dur
        dog.subTimer = 0
        if a != .trick { dog.xEyes = false; dog.rollLocked = false }
        if a != .bath { dog.foam = a == .shake ? dog.foam : 0 }
        if a != .shake { dog.wobble = 0 }
    }

    private func crossed(_ x: Double, _ dt: CGFloat) -> Bool {
        let t = dog.actTime
        return t >= x && t - Double(dt) < x
    }

    @discardableResult
    private func moveDog(toward x: CGFloat, speed: CGFloat, _ dt: CGFloat, stop: CGFloat = 6, face: Bool = true) -> Bool {
        let d = dog
        let dx = x - d.x
        if abs(dx) <= stop { return true }
        let dir: CGFloat = dx > 0 ? 1 : -1
        if face { d.facing = dir }
        d.speed = lerp(d.speed, speed, min(1, dt * 5))
        let step = min(abs(dx), max(d.speed, 20) * dt)
        d.x += step * dir
        d.moved = true
        return abs(x - d.x) <= stop
    }

    private func jump(toHeight h: CGFloat, toward x: CGFloat) {
        let d = dog
        guard d.onGround, d.jumpCooldown <= 0 else { return }
        let need = max(20, h)
        d.vy = min(sqrt(2 * gravity * need), 950)
        d.vx = clamp((x - d.x) * 2.2, -320, 320)
        if abs(x - d.x) > 2 { d.facing = x > d.x ? 1 : -1 }
        d.jumpCooldown = 0.7
        d.y = 0.5
        stats.energy -= 0.3
    }

    private func decide() {
        let d = dog
        let st = stats
        d.sniffing = false
        if laserMode { setAct(.laser); return }
        if walkMode { setAct(.walkies); return }
        if st.energy < 12 || (isNight && st.energy < 40) { setAct(.yawn, 1.6); return }
        if let b = bowl, b.food > 0.02, st.hunger < 95 { setAct(.goEat); return }
        if let due = poopDue, time > due { setAct(.poop, 2.4); return }
        if butterfly != nil && st.energy > 15 { setAct(.butterfly); return }
        let r = Double.random(in: 0..<1)
        if st.fun > 70 && st.energy > 55 && r < 0.07 { setAct(.zoomies, rndD(3.5, 5.5)); return }
        if r < 0.15 && st.energy > 25 { setAct(.dig, 3.2); return }
        if r < 0.48 {
            var tx = rnd(minX + 20, maxX - 20)
            if abs(tx - d.x) < 120 {
                tx = d.x < bounds.midX ? min(maxX, d.x + rnd(150, 400)) : max(minX, d.x - rnd(150, 400))
            }
            d.targetX = tx
            setAct(.wander)
            return
        }
        if r < 0.56 {
            d.targetX = clamp(d.x + d.facing * rnd(40, 120), minX, maxX)
            setAct(.sniff, rndD(2.5, 4))
            return
        }
        if r < 0.64 && mouse.y < groundY + 350 && mouse.x > 0 { setAct(.comeHere); return }
        if r < 0.72 { setAct(.lie, rndD(5, 12)); return }
        if r < 0.78 {
            setAct(.playBow, 1.8)
            if items.contains(where: { $0.kind == .ball }) && chance(0.6) { say("Play with me? 🎾") }
            return
        }
        setAct(.sit, rndD(3, 8))
    }

    private func fetchTarget() -> Item? {
        let cands = items.filter { !$0.carried && !$0.held && ($0.kind == .treat || ($0.kind == .ball && $0.thrown)) }
        return cands.min(by: { abs($0.pos.x - dog.x) < abs($1.pos.x - dog.x) })
    }

    private func interrupts() {
        let d = dog
        let isCasual = World.casual.contains(d.act)
        guard isCasual || d.act == .walkies || d.act == .laser else { return }
        if (heldItem != nil || fetchTarget() != nil) && stats.energy > 4 {
            setAct(.fetch)
            return
        }
        if laserMode && d.act != .laser { setAct(.laser); return }
        if walkMode && d.act != .walkies && !laserMode { setAct(.walkies); return }
        if !walkMode && d.act == .walkies { decide(); return }
        if !laserMode && d.act == .laser { decide(); return }
    }

    private func brain(_ dt: CGFloat) {
        let d = dog
        let s = scale
        d.actTime += Double(dt)
        d.moved = false

        // Ballistics whenever the dog is off the ground (jumps, tosses).
        if d.act != .dragged && (d.y > 0 || d.vy > 0) {
            d.vy -= gravity * dt
            d.y += d.vy * dt
            d.x += d.vx * dt
            if d.x < minX { d.x = minX; d.vx = abs(d.vx) * 0.5 }
            if d.x > maxX { d.x = maxX; d.vx = -abs(d.vx) * 0.5 }
            let ceiling = bounds.height - groundY - 90 * s
            if d.y > ceiling { d.y = ceiling; d.vy = min(d.vy, 0) }
            if d.y <= 0 {
                let impact = -d.vy
                d.y = 0; d.vy = 0; d.vx = 0
                landed(impact)
            }
        }

        interrupts()

        switch d.act {
        case .enter:
            if moveDog(toward: d.targetX, speed: 300 * s, dt, stop: 8) {
                say(greeting, 4)
                bark()
                setAct(.sit, 3)
            }

        case .idle, .sit, .lie, .playBow:
            if d.act == .lie && stats.energy < 25 && d.actTime > 3 { setAct(.sleep); break }
            if d.actTime > d.actDuration { decide() }

        case .stretch:
            if crossed(0.7, dt) { sound.play(.whine, volume: 0.4) }
            if d.actTime > d.actDuration { decide() }

        case .wander:
            if moveDog(toward: d.targetX, speed: 85 * s, dt) {
                setAct(chance(0.5) ? .sit : .idle, rndD(2, 6))
            } else if d.actTime > 20 {
                decide()
            }

        case .sniff:
            moveDog(toward: d.targetX, speed: 28 * s, dt)
            if d.actTime > d.actDuration { decide() }

        case .comeHere:
            let tx = clamp(mouse.x, minX, maxX)
            if moveDog(toward: tx, speed: 320 * s, dt, stop: 50 * s) {
                d.facing = mouse.x >= d.x ? 1 : -1
                d.happyTimer = 1.5
                setAct(.sit, rndD(3, 6))
            } else if d.actTime > 8 {
                setAct(.sit, 2)
            }

        case .yawn:
            if crossed(0.3, dt) { sound.play(.whine, volume: 0.35) }
            if d.actTime > d.actDuration { setAct(.sleep) }

        case .sleep:
            d.subTimer -= dt
            if d.subTimer <= 0 {
                d.subTimer = 1.3
                emit(.zzz, headWorld + CGPoint(d.facing * 10 * s, 16 * s), vel: CGPoint(d.facing * 12, 26),
                     life: 2.4, size: rnd(12, 17) * s, text: chance(0.5) ? "z" : "Z", rot: rnd(-0.3, 0.3))
            }
            if stats.energy >= 99.5 && d.actTime > 20 {
                say("☀️ Good nap!", 2)
                setAct(.stretch, 1.8)
            }

        case .goEat:
            guard let b = bowl, b.food > 0.01 else { setAct(.sit, 2); break }
            let side: CGFloat = d.x < b.x ? -1 : 1
            let tx = b.x + side * 43 * s
            if moveDog(toward: tx, speed: 300 * s, dt, stop: 4) {
                d.x = tx
                d.facing = -side
                setAct(.eat)
            }

        case .eat:
            guard var b = bowl else { setAct(.sit, 2); break }
            d.subTimer -= dt
            if d.subTimer <= 0 {
                d.subTimer = 0.32
                sound.play(.crunch, volume: 0.7)
                for _ in 0..<2 {
                    emit(.crumb, mouthWorld, vel: CGPoint(rnd(-60, 60), rnd(40, 120)), life: 0.8, size: rnd(1.4, 2.4) * s,
                         color: rgb(0.55, 0.32, 0.15), gravity: 600)
                }
            }
            let bite = min(b.food, 0.13 * dt)
            b.food -= bite
            bowl = b
            stats.hunger += Double(bite) * 65
            clampStats()
            if b.food <= 0.001 || stats.hunger >= 100 {
                if stats.hunger >= 100 { b.food = max(b.food, 0.0); bowl = b }
                say(["Yum! 😋", "That hit the spot!", "Delicious! 🍖", "*burp* 😅"].randomElement()!)
                addXP(3)
                d.lickTimer = 1.4
                if poopDue == nil && chance(0.45) { poopDue = time + rndD(25, 70) }
                setAct(.sit, 2)
            }

        case .fetch:
            fetchBrain(dt)

        case .carryBack:
            guard d.carrying != nil else { decide(); break }
            if d.onGround {
                let tx = clamp(mouse.x, minX, maxX)
                if moveDog(toward: tx, speed: 280 * s, dt, stop: 70 * s) {
                    d.facing = mouse.x >= d.x ? 1 : -1
                    dropCarried()
                    stats.fetches += 1
                    addFun(7)
                    stats.energy -= 2
                    addXP(4)
                    hearts(2)
                    d.pantTimer = 4
                    if chance(0.35) { say(["Again! Again!", "Throw it! 🎾", "😁", "I'm the best at this"].randomElement()!) }
                    setAct(.sit, 3)
                }
            }
            if d.actTime > 25 { dropCarried(); decide() }

        case .walkies:
            walkBrain(dt)

        case .laser:
            laserTime += dt
            let tx = clamp(mouse.x, minX, maxX)
            let h = mouse.y - groundY
            if d.onGround {
                moveDog(toward: tx, speed: (stats.energy < 15 ? 200 : 470) * s, dt, stop: 8)
                if abs(tx - d.x) < 70 * s && h > 50 * s && h < 240 * s {
                    jump(toHeight: h - 35 * s, toward: tx)
                } else if abs(tx - d.x) < 30 * s && h < 40 * s && chance(Double(dt) * 1.5) {
                    jump(toHeight: 25 * s, toward: tx + d.facing * 30)
                }
            }
            addFun(Double(dt) * 1.2)
            stats.energy -= Double(dt) * 0.6
            if laserTime > 30 || stats.energy < 5 {
                laserMode = false
                d.pantTimer = 6
                say(["Where'd it go?! 🔴", "I almost had it!", "I'll get it next time 😤"].randomElement()!)
                setAct(.sit, 3)
            }

        case .trick:
            trickBrain(dt)

        case .bath:
            d.foam = min(1, CGFloat(d.actTime / 3.5))
            if chance(Double(dt) * 22) {
                emit(.bubble, bodyWorld + CGPoint(rnd(-40, 40) * s, rnd(-5, 40) * s), vel: CGPoint(rnd(-15, 15), rnd(25, 60)),
                     life: rndD(1, 2), size: rnd(3, 8) * s, color: rgb(1, 1, 1))
            }
            if chance(Double(dt) * 1.2) { sound.play(.splash, volume: 0.35) }
            if d.actTime > d.actDuration { setAct(.shake, 1.4) }

        case .shake:
            let u = CGFloat(d.actTime / d.actDuration)
            d.wobble = sin(CGFloat(d.actTime) * 48) * 0.2 * (1 - u)
            d.foam = max(0, d.foam - dt * 2.5)
            for _ in 0..<3 {
                emit(.droplet, bodyWorld + CGPoint(rnd(-30, 30) * s, rnd(-5, 20) * s),
                     vel: CGPoint(rnd(-320, 320), rnd(60, 300)), life: rndD(0.5, 0.9), size: rnd(1.8, 3) * s,
                     color: rgb(0.5, 0.7, 1), gravity: 900)
            }
            if d.actTime > d.actDuration {
                stats.hygiene = 100
                addXP(4)
                addFun(3)
                sparkles(around: bodyWorld, n: 8)
                say(["So fresh! ✨", "I smell like flowers 🌸", "Never again. …okay, maybe."].randomElement()!)
                setAct(.sit, 2)
            }

        case .dragged:
            break

        case .falling:
            if d.onGround && d.actTime > 0.1 { setAct(.sit, 1.5) }

        case .dig:
            if chance(Double(dt) * 30) {
                let back = CGPoint(d.x + d.facing * 30 * s, groundY + 4)
                emit(.dust, back, vel: CGPoint(-d.facing * rnd(80, 200), rnd(80, 220)), life: rndD(0.5, 0.9),
                     size: rnd(2, 4) * s, color: rgb(0.55, 0.40, 0.25), gravity: 700)
            }
            if d.actTime > d.actDuration { findTreasure() }

        case .zoomies:
            d.subTimer -= dt
            if d.subTimer <= 0 || abs(d.x - d.targetX) < 25 {
                d.targetX = d.x < bounds.midX ? maxX - rnd(0, 200) : minX + rnd(0, 200)
                d.subTimer = rnd(0.8, 1.8)
            }
            moveDog(toward: d.targetX, speed: 480 * s, dt, stop: 20)
            if chance(Double(dt) * 18) {
                emit(.dust, CGPoint(d.x - d.facing * 30 * s, groundY + 2), vel: CGPoint(-d.facing * rnd(20, 60), rnd(10, 40)),
                     life: 0.6, size: rnd(2, 4) * s, color: rgb(0.7, 0.62, 0.5))
            }
            stats.energy -= Double(dt) * 1.2
            addFun(Double(dt) * 0.8)
            if d.actTime > d.actDuration {
                d.pantTimer = 7
                setAct(.lie, 3)
            }

        case .poop:
            if d.actTime > d.actDuration {
                poopDue = nil
                if poopCount < 6 {
                    let r = 11 * s
                    items.append(Item(.poop, at: CGPoint(clamp(d.x - d.facing * 38 * s, r, bounds.width - r), groundY + r * 0.5), radius: r))
                }
                stats.hygiene -= 4
                clampStats()
                if chance(0.5) { say(["😌", "Oops 💩", "…what? Dogs do that.", "Much better."].randomElement()!, 1.8) }
                setAct(.idle, 1.2)
            }

        case .butterfly:
            guard let b = butterfly else { decide(); break }
            if d.onGround {
                moveDog(toward: b.pos.x - d.facing * 30 * s, speed: 320 * s, dt, stop: 10)
                let h = b.pos.y - groundY
                if abs(b.pos.x - d.x) < 90 * s && h < 210 * s { jump(toHeight: h - 40 * s, toward: b.pos.x) }
            }
            addFun(Double(dt) * 0.5)
            if d.actTime > 15 { decide() }

        case .bellyUp:
            if time - lastRubTime > 2.5 { setAct(.lie, 1.5) }
        }

        if !d.moved { d.speed = lerp(d.speed, 0, min(1, dt * 10)) }
        if d.act != .enter { d.x = clamp(d.x, minX, maxX) }
    }

    private func fetchBrain(_ dt: CGFloat) {
        let d = dog
        let s = scale
        if let held = heldItem {
            // Waiting for the throw: hover under the cursor, maybe beg.
            let tx = clamp(held.pos.x, minX, maxX)
            if d.onGround {
                let arrived = moveDog(toward: tx, speed: 300 * s, dt, stop: 55 * s)
                if arrived {
                    d.facing = held.pos.x >= d.x ? 1 : -1
                    d.begging = held.kind == .treat && held.pos.y - groundY < 280 * s
                    if !d.begging && chance(Double(dt) * 1.2) { jump(toHeight: 25 * s, toward: d.x) }
                } else {
                    d.begging = false
                }
            }
            return
        }
        d.begging = false
        guard let target = fetchTarget() else { setAct(.sit, 2); return }
        if d.onGround {
            if (target.pos.x - d.x) * d.facing < 0 { d.facing = -d.facing }
            let tx = target.pos.x - d.facing * 40 * s
            moveDog(toward: tx, speed: (stats.energy < 20 ? 200 : 370) * s, dt, stop: 3, face: false)
            let h = target.pos.y - groundY
            let dx = target.pos.x - d.x
            if h > 55 * s && h < 240 * s && abs(dx) < 120 * s && target.vel.y < 250 {
                jump(toHeight: h - 42 * s, toward: target.pos.x - d.facing * 30 * s)
            }
        }
        let low = target.pos.y - groundY < 30 * s
        let near = abs(mouthWorld.x - target.pos.x) < 24 * s
        if mouthWorld.distance(to: target.pos) < target.radius + 18 * s || (low && near && d.onGround) {
            catchItem(target)
        } else if d.actTime > 25 {
            target.thrown = false
            say("😮‍💨 I give up…")
            setAct(.lie, 4)
        }
    }

    private func catchItem(_ it: Item) {
        let d = dog
        if it.kind == .treat {
            items.removeAll { $0 === it }
            eatTreat(midair: d.y > 10)
        } else {
            it.carried = true
            it.thrown = false
            d.carrying = it
            sound.play(.squeak, volume: 0.7)
            if d.y > 20 { say(["Got it!", "Nice catch, me! 😎"].randomElement()!, 1.2); addXP(2) }
            setAct(.carryBack)
        }
    }

    private func eatTreat(midair: Bool) {
        let d = dog
        stats.hunger += 8
        addFun(midair ? 8 : 5)
        stats.treats += 1
        addXP(midair ? 4 : 2)
        clampStats()
        sound.play(.crunch)
        for _ in 0..<6 {
            emit(.crumb, mouthWorld, vel: CGPoint(rnd(-90, 90), rnd(40, 160)), life: 0.9, size: rnd(1.5, 2.6) * scale,
                 color: rgb(0.85, 0.72, 0.5), gravity: 700)
        }
        hearts(2)
        d.lickTimer = 1.3
        if chance(0.6) { say(midair ? "Mid-air snack! 😎" : ["Yum! 😋", "Tasty!", "More? 🥺", "Nom nom"].randomElement()!, 1.6) }
        if d.onGround { setAct(.sit, 1.8) } else { setAct(.falling) }
    }

    private func dropCarried() {
        guard let it = dog.carrying else { return }
        it.carried = false
        it.pos = mouthWorld
        it.vel = CGPoint(dog.facing * 50, 40)
        dog.carrying = nil
    }

    private func walkBrain(_ dt: CGFloat) {
        let d = dog
        let s = scale
        let tx = clamp(mouse.x, minX, maxX)
        let dx = tx - d.x
        if let due = poopDue, time > due, abs(dx) < 140 * s { setAct(.poop, 2.4); return }
        if d.tired {
            d.sniffing = false
            if d.onGround && abs(dx) > 260 * s {
                // Being dragged along by the leash
                moveDog(toward: tx, speed: 90 * s, dt, stop: 240 * s)
            } else {
                d.facing = dx >= 0 ? 1 : -1
            }
            return
        }
        let oldX = d.x
        if abs(dx) > 85 * s {
            d.sniffing = false
            let sp = min(abs(dx) * 1.6 + 40 * s, (stats.energy < 20 ? 170 : 380) * s)
            if d.onGround { moveDog(toward: tx, speed: sp, dt, stop: 60 * s) }
        } else {
            d.subTimer -= dt
            if d.subTimer <= 0 {
                d.sniffing = chance(0.5)
                d.subTimer = rnd(1.5, 4)
                if d.sniffing, let f = flowers.first(where: { abs($0.x - (d.x + d.facing * 40 * s)) < 30 * s && $0.kind > 0 }) {
                    say(f.kind == 1 ? "🌼 *sniff sniff*" : "🌷 ooh", 1.4)
                }
            }
            if d.sniffing { moveDog(toward: d.x + d.facing * 20, speed: 18 * s, dt, stop: 1) }
        }
        let moved = abs(d.x - oldX)
        walkDistance += moved
        addFun(Double(moved / (100 * s)) * 0.5)
        stats.energy -= Double(moved / (100 * s)) * 0.2
        if stats.energy < 6 && !d.tired {
            d.tired = true
            say("I'm pooped… 😮‍💨 carry me?", 3)
        }
    }

    private func trickBrain(_ dt: CGFloat) {
        let d = dog
        let s = scale
        let t = d.actTime
        switch d.trick {
        case .sit:
            if t > 1.6 { finishTrick() }
        case .speak:
            if crossed(0.3, dt) || crossed(0.85, dt) { bark() }
            if crossed(0.3, dt) { say("Woof! Woof! 🗣️", 1.4) }
            if t > 1.6 { finishTrick() }
        case .beg:
            if crossed(0.4, dt) { sound.play(.whine, volume: 0.4) }
            if t > 2.4 { finishTrick() }
        case .spin:
            if t < 1.3 {
                let step = Int(t / 0.13)
                if step != d.spinStep { d.spinStep = step; d.facing = -d.facing }
                if crossed(0.1, dt) { jump(toHeight: 18 * s, toward: d.x) }
            } else {
                finishTrick()
            }
        case .highFive:
            if crossed(0.8, dt) {
                sound.play(.pop)
                let paw = DogFrames(dog: d, scale: s, groundY: groundY).fromLocal(d.pose.frontFoot + d.pose.pawRaise)
                sparkles(around: paw, n: 5)
                emit(.text, paw + CGPoint(0, 16), vel: CGPoint(0, 50), life: 1.2, size: 18, text: "✋")
            }
            if t > 1.8 { finishTrick() }
        case .rollOver:
            d.rollLocked = true
            d.roll = 2 * .pi * smoothstep(CGFloat((t - 0.35) / 0.9))
            if t > 0.35 && t < 1.25 { d.x += d.facing * 45 * s * dt; d.moved = true; d.speed = 0 }
            if t > 1.6 { d.roll = 0; finishTrick() }
        case .playDead:
            d.xEyes = t > 0.6 && t < 3.0
            if crossed(0.25, dt) { say("Bang! 💥 …x_x", 2) }
            if t > 3.6 { say("Ta-da! ✨", 1.4); finishTrick() }
        case .backflip:
            if crossed(0.3, dt) {
                d.vy = 680; d.y = 0.5; d.vx = 0
                sound.play(.whoosh)
            }
            if t > 0.3 {
                d.rollLocked = true
                let flight = Double(2 * 680 / gravity)
                d.roll = 2 * .pi * CGFloat(clamp((t - 0.3) / flight, 0, 1))
                if t > 0.4 && d.onGround {
                    d.roll = 0
                    sparkles(around: bodyWorld, n: 10)
                    say("🤸 Nailed it!", 1.6)
                    finishTrick()
                }
            }
        }
    }

    private func finishTrick() {
        stats.tricks += 1
        addFun(4)
        stats.energy -= 1.5
        clampStats()
        addXP(5)
        hearts(3)
        dog.rollLocked = false
        dog.xEyes = false
        setAct(.sit, 1.6)
    }

    private func landed(_ impact: CGFloat) {
        let d = dog
        if impact > 300 {
            for _ in 0..<8 {
                emit(.dust, CGPoint(d.x + rnd(-30, 30) * scale, groundY + 2), vel: CGPoint(rnd(-90, 90), rnd(10, 60)),
                     life: 0.6, size: rnd(2.5, 4.5) * scale, color: rgb(0.75, 0.68, 0.58))
            }
        }
        if d.act == .falling {
            if impact > 550 {
                sound.play(.boing, volume: 0.6)
                say(["Wheee! 🤪", "Again!! 😆", "Whoa!", "I can fly! (briefly)"].randomElement()!, 1.6)
                for i in 0..<4 {
                    emit(.sparkle, headWorld + CGPoint(CGFloat(i) * 9 - 13, 22 * scale), vel: CGPoint(0, 15), life: 1, size: 5,
                         color: rgb(1, 0.85, 0.3), vrot: 4)
                }
            }
            setAct(.sit, 1.5)
        }
    }

    private func findTreasure() {
        let loot: [(String, String)] = [("🦴", "a bone"), ("🧦", "your sock"), ("🪙", "a coin"), ("🥏", "a frisbee"),
                                        ("🧸", "a teddy"), ("🍂", "a leaf"), ("🔑", "your keys?!"), ("🪱", "a worm"), ("💎", "a DIAMOND")]
        let pick = chance(0.04) ? loot[8] : loot[Int.random(in: 0..<8)]
        let spot = CGPoint(dog.x + dog.facing * 40 * scale, groundY + 10)
        emit(.text, spot, vel: CGPoint(0, 60), life: 2, size: 24, text: pick.0)
        sparkles(around: spot + CGPoint(0, 10), n: 6)
        sound.play(.pop)
        say("Found \(pick.1)! \(pick.0)", 2.6)
        stats.treasures += 1
        stats.hygiene -= 6
        clampStats()
        addXP(3)
        addFun(3)
        setAct(.sit, 2.5)
    }

    // MARK: - Commands (menu)

    private var busy: Bool { [Act.dragged, .falling].contains(dog.act) }

    private func wakeIfNeeded() {
        if isSleeping { setAct(.idle, 0.2) }
    }

    func feed() {
        let s = scale
        if bowl == nil {
            var x = dog.x + dog.facing * 150 * s
            if x < 80 || x > bounds.width - 80 { x = dog.x - dog.facing * 150 * s }
            bowl = Bowl(x: clamp(x, 60, bounds.width - 60))
        }
        bowl?.food = 1
        bowl?.emptyTime = 0
        sound.play(.pop)
        if let b = bowl {
            for i in 0..<14 {
                emit(.crumb, CGPoint(b.x + rnd(-14, 14) * s, groundY + 70 * s + CGFloat(i) * 6), vel: CGPoint(rnd(-10, 10), -40),
                     life: 0.7, size: rnd(2, 3) * s, color: rgb(0.62, 0.38, 0.18), gravity: 900)
            }
        }
        if isSleeping && stats.hunger > 50 { return }
        if !busy && dog.act != .eat {
            say(["Food!! 🍖", "Is that for me?! 😍", "DINNER!"].randomElement()!, 1.6)
            setAct(.goEat)
        }
    }

    func giveTreat() {
        if let h = heldItem { items.removeAll { $0 === h && $0.kind == .treat }; h.held = false; heldItem = nil }
        let it = Item(.treat, at: mouse, radius: 10 * scale)
        it.held = true
        items.append(it)
        heldItem = it
        wakeIfNeeded()
        if chance(0.6) { say(["A treat?! 🦴", "Gimme gimme 🥺", "I'll be good, I promise!"].randomElement()!, 1.8) }
        sound.play(.pop)
    }

    func playFetch() {
        if let h = heldItem, h.kind == .ball { return }
        if let h = heldItem { h.held = false; heldItem = nil }
        if let c = dog.carrying { c.carried = false; dog.carrying = nil }
        let ball: Item
        if let existing = items.first(where: { $0.kind == .ball }) {
            ball = existing
            ball.carried = false
        } else {
            ball = Item(.ball, at: mouse, radius: 9 * scale)
            items.append(ball)
        }
        ball.held = true
        ball.thrown = false
        heldItem = ball
        wakeIfNeeded()
        if !busy { setAct(.fetch) }
        say(["🎾!!", "Throw it! Throw it!", "Ball?! BALL!"].randomElement()!, 1.6)
        sound.play(.squeak, volume: 0.6)
    }

    func putAwayToys() {
        items.removeAll { $0.kind != .poop }
        heldItem = nil
        dog.carrying = nil
        if dog.act == .fetch || dog.act == .carryBack { decide() }
    }

    func toggleWalk() {
        if walkMode {
            walkMode = false
            let steps = Int(walkDistance / (9 * scale))
            stats.steps += steps
            addXP(Double(steps) / 40)
            say(steps > 20 ? "Great walk! 🐾 \(steps) steps" : "That's it? 🥺", 3)
            if dog.act == .walkies { setAct(.sit, 3) }
            dog.tired = false
        } else {
            if laserMode { laserMode = false }
            walkMode = true
            walkDistance = 0
            dog.tired = false
            makeFlowers()
            sound.play(.yip)
            say(["Walkies!! 🦮", "OUTSIDE?! 😍", "Let's goooo!"].randomElement()!, 1.8)
            if isSleeping || World.casual.contains(dog.act) { setAct(.walkies) }
        }
        save()
    }

    func toggleLaser() {
        if laserMode {
            laserMode = false
            if dog.act == .laser { setAct(.sit, 2) }
        } else {
            laserMode = true
            laserTime = 0
            wakeIfNeeded()
            say("!!! 🔴", 1.2)
            if World.casual.contains(dog.act) || dog.act == .walkies { setAct(.laser) }
        }
    }

    func bath() {
        if busy { return }
        dropCarried()
        sound.play(.splash)
        say(["A bath?! 😨", "Noooo not the bath", "…fine. 😑"].randomElement()!, 1.8)
        addFun(-3)
        setAct(.bath, 6.5)
    }

    func comeHere() {
        if busy || [Act.bath, .shake, .eat, .trick].contains(dog.act) { return }
        if isSleeping { say("*yawn* coming… 😪", 1.4) } else if chance(0.4) { say("Coming! 🐾", 1.2) }
        setAct(.comeHere)
    }

    func napOrWake() {
        if isSleeping {
            say("😪 I'm up, I'm up!", 1.6)
            setAct(.stretch, 1.8)
        } else {
            if walkMode { toggleWalk() }
            if laserMode { laserMode = false }
            dropCarried()
            setAct(.yawn, 1.6)
        }
    }

    func doTrick(_ t: Trick) {
        if stats.level < t.level { say("I haven't learned that yet! (Bond Lv \(t.level)) 🤔", 2.4); return }
        if busy || [Act.bath, .shake].contains(dog.act) { return }
        if isSleeping { say("😴 …zzz… (try waking me first)", 2); return }
        if stats.energy < 8 { say("Too tired… 😴", 1.8); return }
        dropCarried()
        if abs(mouse.x - dog.x) > 4 { dog.facing = mouse.x > dog.x ? 1 : -1 }
        dog.trick = t
        dog.spinStep = 0
        setAct(.trick)
    }

    func cleanAllPoop() {
        for p in items where p.kind == .poop { cleanPoop(p) }
    }

    private func cleanPoop(_ p: Item) {
        items.removeAll { $0 === p }
        sparkles(around: p.pos, n: 6)
        sound.play(.pop)
        stats.poopsCleaned += 1
        stats.hygiene += 3
        clampStats()
        addXP(2)
        if chance(0.3) { say(["Thanks! 🧹", "Sorry about that 😅", "You're the best human"].randomElement()!, 1.6) }
    }

    func say(_ text: String, _ dur: Double = 2.6) {
        bubble = Bubble(text: text, life: dur, born: time)
    }

    // MARK: - Pose

    private func targetPose() -> Pose {
        let d = dog
        let t = CGFloat(time)
        var p: Pose
        switch d.act {
        case .sit: p = .sit
        case .lie: p = .lie
        case .sleep: p = .sleep
        case .yawn: p = d.actTime < 1.2 ? .yawn : .sleep
        case .stretch: p = .playBow; p.mouth = d.actTime > 0.5 ? 0.9 : 0; p.eyeOpen = 0.3
        case .eat:
            p = .eat
            p.mouth = 0.35 + 0.35 * sin(t * 14)
        case .sniff:
            p = .sniff
            p.headY += sin(t * 9) * 2
        case .bath: p = .wet
        case .shake: p = .stand; p.earLift = sin(t * 40) * 0.6; p.eyeOpen = 0.2
        case .dragged: p = .dangle
        case .falling: p = .jump
        case .dig: p = .dig
        case .poop: p = .squat
        case .bellyUp: p = .bellyUp
        case .playBow: p = .playBow
        case .trick: p = trickPose()
        case .walkies:
            if d.tired { p = .sit } else if d.sniffing { p = .sniff; p.headY += sin(t * 9) * 2 } else { p = .stand }
        case .fetch:
            if d.begging {
                p = .beg
                p.frontFoot.y += sin(t * 8) * 3
            } else if let target = fetchTarget(), target.pos.y - groundY < 30 * scale, abs(target.pos.x - d.x) < 80 * scale {
                p = .sniff
            } else {
                p = .stand
                p.tailWag = 0.7
            }
        case .carryBack: p = .stand; p.tailWag = 0.7
        case .enter, .idle, .wander, .goEat, .zoomies, .laser, .butterfly, .comeHere:
            p = .stand
        }

        let airborne = d.y > 1 && d.act != .dragged
        let flipping = d.act == .trick && (d.trick == .backflip || d.trick == .spin)
        if airborne && !flipping { p = .jump }

        p.walk = min(1.6, d.speed / (95 * scale))
        if d.act != .sleep && d.act != .bath {
            if d.happyTimer > 0 || stats.fun > 75 {
                p.tailWag *= 1.6
            } else if stats.fun < 25 && World.casual.contains(d.act) {
                p.tailWag *= 0.3
                p.tailAngle -= 0.6
            }
        }
        if d.happyTimer > 0 && d.act != .sleep { p.happyEyes = 1 }
        if d.pantTimer > 0 || d.act == .zoomies || d.act == .laser { p.tongue = max(p.tongue, 1); p.mouth = max(p.mouth, 0.35) }
        if d.lickTimer > 0 { p.tongue = max(p.tongue, 0.6) }
        if d.barkTimer > 0 { p.mouth = 1 }
        if (d.act == .idle || d.act == .sit) && mouse.distance(to: headWorld) < 170 * scale && !dogHitRect().contains(mouse) {
            p.headAngle += 0.28
        }
        if stats.energy < 20 && d.act != .sleep { p.eyeOpen = min(p.eyeOpen, 0.6) }
        d.tailSpeed = d.happyTimer > 0 || d.act == .fetch || d.act == .carryBack ? 18 : 10
        return p
    }

    private func trickPose() -> Pose {
        let d = dog
        let t = d.actTime
        switch d.trick {
        case .sit: return .sit
        case .speak:
            var p = Pose.sit
            p.headAngle = -0.65
            return p
        case .beg:
            var p = Pose.beg
            p.frontFoot.y += sin(CGFloat(time) * 8) * 3
            return p
        case .spin: return .stand
        case .highFive:
            var p = Pose.sit
            if t > 0.35 && t < 1.5 { p.pawRaise = CGPoint(10, 34) }
            return p
        case .rollOver: return .lie
        case .playDead: return t > 0.3 && t < 3.0 ? .playDead : .lie
        case .backflip: return t < 0.3 ? .crouch : .jump
        }
    }

    private func updatePose(_ dt: CGFloat) {
        let d = dog
        let target = targetPose()
        d.pose.approach(target, 1 - exp(-12 * dt))
        d.facingSmooth = lerp(d.facingSmooth, d.facing, 1 - exp(-14 * dt))
        if !d.rollLocked { d.roll = lerp(d.roll, target.roll, 1 - exp(-7 * dt)) }
        if d.speed > 2 {
            d.phase += min(30, 3 + d.speed / (5.5 * scale)) * dt
        }
        updateFrames()
    }

    private func updateFrames() {
        let fr = DogFrames(dog: dog, scale: scale, groundY: groundY)
        headWorld = fr.fromHead(.zero)
        mouthWorld = fr.fromHead(CGPoint(19, -11))
        collarWorld = fr.fromBody(neckGeometry(dog.pose).collar)
        bodyWorld = fr.fromBody(.zero)
    }

    // MARK: - World props

    private func updateItems(_ dt: CGFloat) {
        let w = bounds.width
        let top = bounds.height
        for it in items {
            if it.held { continue }
            if it.carried { it.pos = mouthWorld; it.spin = 0; continue }
            if it.kind == .poop { continue }
            it.vel.y -= 1500 * dt
            it.pos += it.vel * dt
            let floor = groundY + it.radius
            if it.pos.y < floor {
                it.pos.y = floor
                if it.vel.y < -90 {
                    let bounce: CGFloat = it.kind == .ball ? 0.58 : 0.3
                    if it.kind == .ball && it.vel.y < -350 { sound.play(.boing, volume: Float(min(0.4, -it.vel.y / 3000))) }
                    it.vel.y = -it.vel.y * bounce
                } else {
                    it.vel.y = 0
                }
                it.vel.x *= max(0, 1 - dt * (it.kind == .ball ? 1.6 : 5))
            }
            if it.pos.x < it.radius { it.pos.x = it.radius; it.vel.x = abs(it.vel.x) * 0.6 }
            if it.pos.x > w - it.radius { it.pos.x = w - it.radius; it.vel.x = -abs(it.vel.x) * 0.6 }
            if it.pos.y > top - it.radius { it.pos.y = top - it.radius; it.vel.y = -abs(it.vel.y) * 0.5 }
            it.spin -= it.vel.x * dt / it.radius
        }
    }

    private func updateBowl(_ dt: CGFloat) {
        guard var b = bowl else { return }
        if b.food <= 0.001 {
            b.emptyTime += dt
            if b.emptyTime > 4 { b.alpha -= dt * 2 }
            if b.alpha <= 0 { bowl = nil; return }
        } else {
            b.alpha = min(1, b.alpha + dt * 4)
        }
        bowl = b
    }

    private func updateButterfly(_ dt: CGFloat) {
        if butterfly == nil && time > nextButterfly && !walkMode && !laserMode && !isSleeping {
            let fromLeft = chance(0.5)
            let y = groundY + rnd(80, 170) * scale
            let colors = [rgb(0.98, 0.6, 0.2), rgb(0.6, 0.45, 0.95), rgb(0.35, 0.7, 0.98), rgb(0.98, 0.45, 0.65)]
            butterfly = Butterfly(pos: CGPoint(fromLeft ? -20 : bounds.width + 20, y), baseY: y,
                                  vx: (fromLeft ? 1 : -1) * rnd(55, 95), phase: rnd(0, 6), color: colors.randomElement()!)
            if World.casual.contains(dog.act) && chance(0.7) { say("🦋 !!!", 1.4) }
        }
        guard var b = butterfly else { return }
        b.phase += dt
        b.pos.x += b.vx * dt
        if b.pos.distance(to: mouthWorld) < 90 * scale {
            b.baseY += 170 * dt
        } else {
            b.baseY = max(groundY + 60 * scale, b.baseY - 12 * dt)
        }
        b.baseY = min(b.baseY, bounds.height - 40)
        b.pos.y = b.baseY + sin(b.phase * 2.2) * 26
        if b.pos.x < -40 || b.pos.x > bounds.width + 40 {
            butterfly = nil
            nextButterfly = time + rndD(120, 300)
        } else {
            butterfly = b
        }
    }

    private func makeFlowers() {
        flowers = []
        let colors = [rgb(1, 1, 1), rgb(0.98, 0.55, 0.7), rgb(0.7, 0.55, 0.98), rgb(0.98, 0.35, 0.35), rgb(0.99, 0.75, 0.3)]
        var x = rnd(10, 40)
        while x < bounds.width {
            let k = Int.random(in: 0..<10)
            flowers.append(Flower(x: x, kind: k < 5 ? 0 : (k < 8 ? 1 : 2), height: rnd(8, 16),
                                  color: colors.randomElement()!, phase: rnd(0, 6)))
            x += rnd(18, 60)
        }
    }

    private func updateParticles(_ dt: CGFloat) {
        flowerFade = lerp(flowerFade, walkMode ? 1 : 0, min(1, dt * 2))
        if !walkMode && flowerFade < 0.01 { flowers = [] }

        var alive: [Particle] = []
        alive.reserveCapacity(particles.count)
        for var p in particles {
            p.life -= Double(dt)
            if p.life <= 0 { continue }
            p.vel.y -= p.gravity * dt
            if p.drag > 0 { p.vel = p.vel * max(0, 1 - p.drag * dt) }
            p.pos += p.vel * dt
            p.rot += p.vrot * dt
            if p.kind == .bubble { p.pos.x += sin(CGFloat(time) * 4 + p.size) * 0.3 }
            if (p.kind == .crumb || p.kind == .droplet || p.kind == .dust) && p.pos.y < groundY {
                p.pos.y = groundY
                p.vel = .zero
                p.gravity = 0
            }
            alive.append(p)
        }
        particles = alive
    }

    private func updateTimers(_ dt: Double) {
        let d = dog
        d.happyTimer -= dt
        d.pantTimer -= dt
        d.lickTimer -= dt
        d.barkTimer -= dt
        d.jumpCooldown -= dt
        d.blinking -= dt
        d.blinkTimer -= dt
        if d.blinkTimer <= 0 {
            d.blinking = 0.12
            d.blinkTimer = rndD(2.5, 6)
        }
        if var b = bubble {
            b.life -= dt
            bubble = b.life > 0 ? b : nil
        }
        if time > nextNeed {
            nextNeed = time + rndD(40, 75)
            let needs: [(Double, String)] = [(stats.hunger, "I'm hungry… 🍖"), (stats.fun, "I'm bored… 🎾"),
                                              (stats.energy, "So sleepy… 😴"), (stats.hygiene, "I'm a bit stinky… 🛁")]
            if let worst = needs.min(by: { $0.0 < $1.0 }), worst.0 < 25, !isSleeping, bubble == nil {
                say(worst.1, 3)
                sound.play(.whine, volume: 0.3)
            }
        }
        saveClock += dt
        if saveClock > 30 { saveClock = 0; save() }
    }

    // MARK: - Effects

    private func emit(_ k: PKind, _ p: CGPoint, vel: CGPoint = .zero, life: Double = 1, size: CGFloat = 8,
                      color: CGColor = rgb(1, 1, 1), text: String = "", gravity: CGFloat = 0,
                      rot: CGFloat = 0, vrot: CGFloat = 0, drag: CGFloat = 0) {
        if particles.count > 600 { return }
        particles.append(Particle(k, p, vel: vel, life: life, size: size, color: color, text: text,
                                  gravity: gravity, rot: rot, vrot: vrot, drag: drag))
    }

    private func hearts(_ n: Int) {
        for i in 0..<n {
            emit(.heart, headWorld + CGPoint(rnd(-14, 14), 18 * scale + CGFloat(i) * 6), vel: CGPoint(rnd(-25, 25), rnd(50, 85)),
                 life: rndD(1.1, 1.6), size: rnd(6, 9) * scale, color: rgb(0.96, 0.33, 0.45))
        }
    }

    private func sparkles(around c: CGPoint, n: Int) {
        for _ in 0..<n {
            let a = rnd(0, 2 * .pi)
            emit(.sparkle, c + CGPoint(cos(a), sin(a)) * rnd(4, 20), vel: CGPoint(cos(a), sin(a)) * rnd(30, 90),
                 life: rndD(0.6, 1.1), size: rnd(4, 7), color: rgb(1, 0.86, 0.3), vrot: rnd(-5, 5), drag: 2)
        }
    }

    // MARK: - Layout

    func dogHitRect() -> CGRect {
        let s = scale
        return CGRect(x: dog.x - 56 * s, y: groundY + dog.y - 4, width: 112 * s, height: 80 * s)
    }

    private func bubbleLayout() -> (CGRect, NSAttributedString, CGPoint)? {
        guard let b = bubble else { return nil }
        let str = NSAttributedString(string: b.text, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.13, alpha: 1),
        ])
        let sz = str.size()
        let w = sz.width + 24, h = sz.height + 12
        var anchor = headWorld + CGPoint(0, 26 * scale)
        anchor.y = max(anchor.y, groundY + 70 * scale)
        if hudAlpha > 0.05 { anchor.y += 90 * hudAlpha }
        let x = clamp(anchor.x - w / 2, 8, max(8, bounds.width - w - 8))
        let y = min(anchor.y + 10, bounds.height - h - 30)
        return (CGRect(x: x, y: y, width: w, height: h), str, anchor)
    }

    private func hudRect() -> CGRect {
        let w: CGFloat = 176, h: CGFloat = 86
        let top = max(headWorld.y, groundY + 60 * scale) + 26 * scale
        return CGRect(x: clamp(dog.x - w / 2, 8, max(8, bounds.width - w - 8)), y: min(top, bounds.height - h - 30), width: w, height: h)
    }

    func dirtyRect() -> CGRect {
        let s = scale
        var r = dogHitRect().insetBy(dx: -50 * s, dy: -40 * s)
        r = r.union(CGRect(x: headWorld.x - 40 * s, y: headWorld.y - 40 * s, width: 80 * s, height: 80 * s))
        for it in items {
            r = r.union(CGRect(x: it.pos.x - it.radius - 30, y: it.pos.y - it.radius - 30, width: it.radius * 2 + 60, height: it.radius * 2 + 80))
        }
        if let b = bowl { r = r.union(CGRect(x: b.x - 40 * s, y: groundY - 8, width: 80 * s, height: 50 * s)) }
        for p in particles {
            let e = p.size * 2 + 20
            r = r.union(CGRect(x: p.pos.x - e, y: p.pos.y - e, width: e * 2, height: e * 2))
        }
        if let b = butterfly { r = r.union(CGRect(x: b.pos.x - 25, y: b.pos.y - 25, width: 50, height: 50)) }
        if !flowers.isEmpty { r = r.union(CGRect(x: 0, y: groundY - 4, width: bounds.width, height: 36 * s)) }
        if walkMode {
            let a = collarWorld, b = mouse
            r = r.union(CGRect(x: min(a.x, b.x) - 30, y: min(a.y, b.y) - 120, width: abs(a.x - b.x) + 60, height: abs(a.y - b.y) + 160))
        }
        if laserMode { r = r.union(CGRect(x: mouse.x - 30, y: mouse.y - 30, width: 60, height: 60)) }
        if let bl = bubbleLayout() {
            r = r.union(bl.0.insetBy(dx: -24, dy: -24)).union(CGRect(x: bl.2.x - 10, y: bl.2.y - 10, width: 20, height: 30))
        }
        if hudAlpha > 0.01 || hoverTime > 0 { r = r.union(hudRect().insetBy(dx: -10, dy: -10)) }
        return r.integral
    }

    // MARK: - Drawing

    func draw(_ ctx: CGContext) {
        let s = scale
        if flowerFade > 0.01 {
            ctx.saveGState()
            ctx.setAlpha(flowerFade)
            for f in flowers { drawFlower(ctx, f, groundY: groundY, scale: s, time: time) }
            ctx.restoreGState()
        }
        if let b = bowl { drawBowl(ctx, b, groundY: groundY, scale: s) }
        for it in items where it.kind == .poop { drawPoop(ctx, at: it.pos, r: it.radius, time: time) }
        for it in items where it.kind != .poop && !it.carried && !it.held { drawProp(ctx, it) }

        var look = CGPoint.zero
        var focus: CGPoint? = mouse.x > -999 && mouse.distance(to: headWorld) < 700 ? mouse : nil
        if let target = fetchTarget(), dog.act == .fetch { focus = target.pos }
        if let b = butterfly, dog.act == .butterfly { focus = b.pos }
        if let f = focus {
            let v = (f - headWorld).normalized
            look = CGPoint(v.x * (dog.facing >= 0 ? 1 : -1), v.y)
        }
        drawDog(ctx, dog: dog, coat: coat, scale: s, groundY: groundY, time: time, look: look,
                dirt: CGFloat(clamp((40 - stats.hygiene) / 40, 0, 1)))

        for it in items where it.carried { drawProp(ctx, it) }
        for p in particles { drawParticle(ctx, p) }
        if let b = butterfly { drawButterfly(ctx, b, time: time) }
        if walkMode { drawLeash(ctx, from: collarWorld, to: mouse) }
        for it in items where it.held { drawProp(ctx, it) }
        if laserMode { drawLaser(ctx, at: mouse, time: time) }
        drawHUD(ctx)
        drawBubble(ctx)
    }

    private func drawProp(_ ctx: CGContext, _ it: Item) {
        switch it.kind {
        case .ball: drawBall(ctx, at: it.pos, r: it.radius, spin: it.spin)
        case .treat: drawBone(ctx, at: it.pos, r: it.radius, spin: it.spin + (it.carried ? 0 : 0.3))
        case .poop: drawPoop(ctx, at: it.pos, r: it.radius, time: time)
        }
    }

    private func drawBubble(_ ctx: CGContext) {
        guard let b = bubble, let bl = bubbleLayout() else { return }
        let (rect, str, anchor) = bl
        let age = time - b.born
        let pop = CGFloat(min(1, age / 0.15))
        let fade = CGFloat(min(1, b.life / 0.3))
        ctx.saveGState()
        ctx.setAlpha(fade)
        let pivot = CGPoint(rect.midX, rect.minY)
        ctx.translateBy(x: pivot.x, y: pivot.y)
        ctx.scaleBy(x: 0.6 + 0.4 * pop, y: 0.6 + 0.4 * pop)
        ctx.translateBy(x: -pivot.x, y: -pivot.y)

        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: 11, cornerHeight: 11)
        let tx = clamp(anchor.x, rect.minX + 14, rect.maxX - 14)
        path.move(to: CGPoint(tx - 7, rect.minY + 1))
        path.addLine(to: CGPoint(tx + (anchor.x - tx) * 0.5, rect.minY - 9))
        path.addLine(to: CGPoint(tx + 7, rect.minY + 1))
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: rgb(0, 0, 0, 0.25))
        ctx.addPath(path); ctx.setFillColor(rgb(1, 1, 1, 0.97)); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 11, cornerHeight: 11, transform: nil))
        ctx.setStrokeColor(rgb(0, 0, 0, 0.08)); ctx.setLineWidth(1); ctx.strokePath()
        str.draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 6))
        ctx.restoreGState()
    }

    private func drawHUD(_ ctx: CGContext) {
        guard hudAlpha > 0.01 else { return }
        let r = hudRect()
        ctx.saveGState()
        ctx.setAlpha(hudAlpha)
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: rgb(0, 0, 0, 0.3))
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.setFillColor(rgb(0.11, 0.11, 0.14, 0.88)); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        let title = NSAttributedString(string: "\(stats.name) · Lv \(stats.level) \(stats.moodEmoji)", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.white,
        ])
        title.draw(at: CGPoint(x: r.minX + 12, y: r.maxY - 20))

        let rows: [(String, Double)] = [("🍖", stats.hunger), ("🎾", stats.fun), ("⚡️", stats.energy), ("🛁", stats.hygiene)]
        for (i, row) in rows.enumerated() {
            let y = r.maxY - 36 - CGFloat(i) * 13
            let icon = NSAttributedString(string: row.0, attributes: [.font: NSFont.systemFont(ofSize: 9)])
            icon.draw(at: CGPoint(x: r.minX + 11, y: y - 2))
            let barX = r.minX + 30, barW = r.width - 42
            ctx.addPath(CGPath(roundedRect: CGRect(x: barX, y: y + 1, width: barW, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.setFillColor(rgb(1, 1, 1, 0.14)); ctx.fillPath()
            let v = CGFloat(row.1 / 100)
            let color = row.1 > 60 ? rgb(0.42, 0.86, 0.48) : (row.1 > 30 ? rgb(0.99, 0.78, 0.3) : rgb(0.96, 0.42, 0.42))
            if v > 0.01 {
                ctx.addPath(CGPath(roundedRect: CGRect(x: barX, y: y + 1, width: max(6, barW * v), height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil))
                ctx.setFillColor(color); ctx.fillPath()
            }
        }
        ctx.restoreGState()
    }
}
