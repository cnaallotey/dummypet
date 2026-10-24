import AppKit

/// A pose describes the dog's skeleton. The renderer draws whatever pose it is
/// given; the brain picks a target pose and the current pose eases toward it.
struct Pose {
    var bodyY: CGFloat = 32
    var bodyAngle: CGFloat = 0
    var headX: CGFloat = 30
    var headY: CGFloat = 16
    var headAngle: CGFloat = 0
    var frontFoot = CGPoint(20, 0)
    var backFoot = CGPoint(-20, 0)
    var pawRaise = CGPoint.zero
    var tailAngle: CGFloat = 0.9
    var tailWag: CGFloat = 0.3
    var earLift: CGFloat = 0
    var eyeOpen: CGFloat = 1
    var mouth: CGFloat = 0
    var tongue: CGFloat = 0
    var walk: CGFloat = 0
    var roll: CGFloat = 0
    var happyEyes: CGFloat = 0
    var legWiggle: CGFloat = 0
    var scratch: CGFloat = 0

    mutating func approach(_ t: Pose, _ k: CGFloat) {
        bodyY = lerp(bodyY, t.bodyY, k)
        bodyAngle = lerp(bodyAngle, t.bodyAngle, k)
        headX = lerp(headX, t.headX, k)
        headY = lerp(headY, t.headY, k)
        headAngle = lerp(headAngle, t.headAngle, k)
        frontFoot = frontFoot.mix(t.frontFoot, k)
        backFoot = backFoot.mix(t.backFoot, k)
        pawRaise = pawRaise.mix(t.pawRaise, k)
        tailAngle = lerp(tailAngle, t.tailAngle, k)
        tailWag = lerp(tailWag, t.tailWag, k)
        earLift = lerp(earLift, t.earLift, k)
        eyeOpen = lerp(eyeOpen, t.eyeOpen, k)
        mouth = lerp(mouth, t.mouth, min(1, k * 1.8))
        tongue = lerp(tongue, t.tongue, k)
        walk = lerp(walk, t.walk, min(1, k * 1.5))
        roll = t.roll
        happyEyes = lerp(happyEyes, t.happyEyes, k)
        legWiggle = lerp(legWiggle, t.legWiggle, k)
        scratch = lerp(scratch, t.scratch, k)
    }

    static let stand = Pose()

    static let sit: Pose = {
        var p = Pose()
        p.bodyY = 22; p.bodyAngle = 0.5
        p.headX = 28; p.headY = 18; p.headAngle = -0.45
        p.frontFoot = CGPoint(19, 0); p.backFoot = CGPoint(-5, 0)
        p.tailAngle = 0.55; p.tailWag = 0.3
        return p
    }()

    static let lie: Pose = {
        var p = Pose()
        p.bodyY = 15
        p.headX = 30; p.headY = 9; p.headAngle = -0.12
        p.frontFoot = CGPoint(44, 3); p.backFoot = CGPoint(-34, 4)
        p.tailAngle = 0.15; p.tailWag = 0.2
        return p
    }()

    static let sleep: Pose = {
        var p = Pose.lie
        p.headX = 31; p.headY = 4; p.headAngle = -0.3
        p.eyeOpen = 0; p.tailWag = 0; p.earLift = -0.15
        return p
    }()

    static let eat: Pose = {
        var p = Pose()
        p.headX = 33; p.headY = -4; p.headAngle = -0.55
        p.tailWag = 0.5
        return p
    }()

    static let sniff: Pose = {
        var p = Pose()
        p.headX = 33; p.headY = -2; p.headAngle = -0.45
        p.tailWag = 0.4; p.tailAngle = 1.1
        return p
    }()

    static let beg: Pose = {
        var p = Pose()
        p.bodyY = 24; p.bodyAngle = 1.1
        p.headX = 34; p.headY = -2; p.headAngle = -1.0
        p.frontFoot = CGPoint(12, 42); p.backFoot = CGPoint(-6, 0)
        p.tailAngle = 1.2; p.tailWag = 0.5; p.earLift = 0.1
        return p
    }()

    static let playBow: Pose = {
        var p = Pose()
        p.bodyY = 27; p.bodyAngle = -0.38
        p.headX = 31; p.headY = 12; p.headAngle = 0.38
        p.frontFoot = CGPoint(40, 0); p.backFoot = CGPoint(-20, 0)
        p.tailAngle = 1.35; p.tailWag = 0.7
        return p
    }()

    static let dig: Pose = {
        var p = Pose()
        p.bodyY = 28; p.bodyAngle = -0.28
        p.headX = 32; p.headY = 8; p.headAngle = 0.1
        p.frontFoot = CGPoint(36, 4); p.backFoot = CGPoint(-20, 0)
        p.tailAngle = 1.3; p.tailWag = 0.5; p.scratch = 1
        return p
    }()

    static let dangle: Pose = {
        var p = Pose()
        p.bodyY = 34; p.bodyAngle = 0.12; p.headAngle = 0.05
        p.frontFoot = CGPoint(24, 6); p.backFoot = CGPoint(-18, 8)
        p.tailAngle = -0.6; p.tailWag = 0.15; p.earLift = 0.55
        p.legWiggle = 1; p.mouth = 0.25
        return p
    }()

    static let jump: Pose = {
        var p = Pose()
        p.bodyAngle = 0.05
        p.frontFoot = CGPoint(32, 16); p.backFoot = CGPoint(-30, 12)
        p.earLift = 0.5; p.tailAngle = 1.0; p.mouth = 0.35
        return p
    }()

    static let squat: Pose = {
        var p = Pose()
        p.bodyY = 24; p.bodyAngle = 0.3
        p.headX = 30; p.headY = 16; p.headAngle = -0.3
        p.frontFoot = CGPoint(21, 0); p.backFoot = CGPoint(-9, 0)
        p.tailAngle = 1.7; p.tailWag = 0; p.eyeOpen = 0.45
        return p
    }()

    static let bellyUp: Pose = {
        var p = Pose.lie
        p.roll = .pi
        p.frontFoot = CGPoint(20, -12); p.backFoot = CGPoint(-19, -12)
        p.legWiggle = 0.9; p.happyEyes = 1; p.tongue = 0.8; p.tailWag = 0.6
        // Upside down, so a negative head offset keeps the head above the ground.
        p.bodyY = 17; p.headY = -3; p.headAngle = 0.25
        return p
    }()

    static let playDead: Pose = {
        var p = Pose.bellyUp
        p.legWiggle = 0; p.happyEyes = 0; p.tongue = 1; p.tailWag = 0
        return p
    }()

    static let wet: Pose = {
        var p = Pose.sit
        p.earLift = -0.5; p.tailAngle = 0.2; p.tailWag = 0; p.eyeOpen = 0.7
        return p
    }()

    static let yawn: Pose = {
        var p = Pose.sit
        p.mouth = 1; p.eyeOpen = 0.15; p.headAngle = -0.25
        return p
    }()

    static let crouch: Pose = {
        var p = Pose()
        p.bodyY = 25
        p.frontFoot = CGPoint(24, 0); p.backFoot = CGPoint(-16, 0)
        p.tailWag = 0.8
        return p
    }()
}

enum Act: Hashable {
    case enter, idle, wander, sit, lie, sleep, yawn, stretch
    case goEat, eat, fetch, carryBack
    case walkies, laser, trick, bath, shake
    case dragged, falling, dig, zoomies, sniff, poop
    case butterfly, comeHere, bellyUp, playBow
}

enum Trick: Int, CaseIterable {
    case sit, speak, beg, spin, highFive, rollOver, playDead, backflip

    var title: String {
        switch self {
        case .sit: return "Sit"
        case .speak: return "Speak"
        case .beg: return "Beg"
        case .spin: return "Spin"
        case .highFive: return "High Five"
        case .rollOver: return "Roll Over"
        case .playDead: return "Play Dead"
        case .backflip: return "Backflip"
        }
    }

    var emoji: String {
        switch self {
        case .sit: return "🪑"
        case .speak: return "🗣️"
        case .beg: return "🥺"
        case .spin: return "🌀"
        case .highFive: return "✋"
        case .rollOver: return "🔄"
        case .playDead: return "💫"
        case .backflip: return "🤸"
        }
    }

    /// Bond level at which the dog learns this trick.
    var level: Int { [1, 1, 2, 2, 3, 3, 4, 6][rawValue] }
}

final class Dog {
    var x: CGFloat = -60
    var y: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var facing: CGFloat = 1
    var facingSmooth: CGFloat = 1
    var speed: CGFloat = 0
    var moved = false
    var phase: CGFloat = 0
    var pose = Pose.stand
    var roll: CGFloat = 0
    var rollLocked = false
    var wobble: CGFloat = 0

    var act: Act = .enter
    var actTime: Double = 0
    var actDuration: Double = 0
    var targetX: CGFloat = 0
    var trick: Trick = .sit
    var subTimer: CGFloat = 0
    var spinStep = 0

    var carrying: Item?
    var sniffing = false
    var tired = false
    var begging = false
    var xEyes = false
    var foam: CGFloat = 0
    var tailSpeed: CGFloat = 10

    var blinkTimer: Double = 3
    var blinking: Double = 0
    var happyTimer: Double = 0
    var pantTimer: Double = 0
    var lickTimer: Double = 0
    var barkTimer: Double = 0
    var jumpCooldown: Double = 0

    var onGround: Bool { y <= 0 && vy <= 0 }
}

enum ItemKind { case ball, treat, poop }

final class Item {
    let kind: ItemKind
    var pos: CGPoint
    var vel = CGPoint.zero
    var radius: CGFloat
    var spin: CGFloat = 0
    var held = false
    var carried = false
    var thrown = false
    var airTime: Double = 0

    init(_ kind: ItemKind, at pos: CGPoint, radius: CGFloat) {
        self.kind = kind
        self.pos = pos
        self.radius = radius
    }
}

enum PKind { case heart, zzz, crumb, bubble, droplet, dust, sparkle, text, confetti }

struct Particle {
    var kind: PKind
    var pos: CGPoint
    var vel: CGPoint
    var life: Double
    let maxLife: Double
    var size: CGFloat
    var rot: CGFloat
    var vrot: CGFloat
    var gravity: CGFloat
    var drag: CGFloat
    var color: CGColor
    var text: String

    init(_ kind: PKind, _ pos: CGPoint, vel: CGPoint, life: Double, size: CGFloat, color: CGColor,
         text: String, gravity: CGFloat, rot: CGFloat, vrot: CGFloat, drag: CGFloat) {
        self.kind = kind; self.pos = pos; self.vel = vel
        self.life = life; self.maxLife = life; self.size = size
        self.color = color; self.text = text; self.gravity = gravity
        self.rot = rot; self.vrot = vrot; self.drag = drag
    }

    var fade: CGFloat { CGFloat(clamp(life / maxLife, 0, 1)) }
}

struct Bubble {
    var text: String
    var life: Double
    let born: Double
}

struct Butterfly {
    var pos: CGPoint
    var baseY: CGFloat
    var vx: CGFloat
    var phase: CGFloat
    var color: CGColor
}

struct Flower {
    var x: CGFloat
    var kind: Int
    var height: CGFloat
    var color: CGColor
    var phase: CGFloat
}

struct Bowl {
    var x: CGFloat
    var food: CGFloat = 1
    var emptyTime: CGFloat = 0
    var alpha: CGFloat = 0
}

enum CoatPattern { case plain, spots, husky, shiba }

struct Coat {
    let name: String
    let base: CGColor
    let shade: CGColor
    let dark: CGColor
    let belly: CGColor
    let muzzle: CGColor
    let outline: CGColor
    let pointy: Bool
    let pattern: CoatPattern

    init(_ name: String, base b: (CGFloat, CGFloat, CGFloat), dark d: (CGFloat, CGFloat, CGFloat),
         belly e: (CGFloat, CGFloat, CGFloat), pointy: Bool, pattern: CoatPattern,
         outline o: (CGFloat, CGFloat, CGFloat) = (0.27, 0.17, 0.10)) {
        self.name = name
        base = rgb(b.0, b.1, b.2)
        shade = rgb(b.0 * 0.84, b.1 * 0.84, b.2 * 0.84)
        dark = rgb(d.0, d.1, d.2)
        belly = rgb(e.0, e.1, e.2)
        muzzle = rgb((b.0 + e.0 * 2) / 3, (b.1 + e.1 * 2) / 3, (b.2 + e.2 * 2) / 3)
        outline = rgb(o.0, o.1, o.2)
        self.pointy = pointy
        self.pattern = pattern
    }

    static let all: [Coat] = [
        Coat("Golden Retriever", base: (0.89, 0.65, 0.35), dark: (0.74, 0.48, 0.24), belly: (0.98, 0.86, 0.64), pointy: false, pattern: .plain),
        Coat("Chocolate Lab", base: (0.48, 0.30, 0.19), dark: (0.34, 0.20, 0.12), belly: (0.62, 0.44, 0.31), pointy: false, pattern: .plain, outline: (0.18, 0.10, 0.06)),
        Coat("Dalmatian", base: (0.98, 0.97, 0.95), dark: (0.13, 0.13, 0.14), belly: (1, 1, 1), pointy: false, pattern: .spots, outline: (0.22, 0.22, 0.24)),
        Coat("Husky", base: (0.55, 0.58, 0.64), dark: (0.33, 0.35, 0.40), belly: (0.97, 0.97, 0.98), pointy: true, pattern: .husky, outline: (0.16, 0.17, 0.20)),
        Coat("Shiba Inu", base: (0.90, 0.52, 0.24), dark: (0.74, 0.37, 0.15), belly: (0.99, 0.93, 0.82), pointy: true, pattern: .shiba),
        Coat("Midnight Lab", base: (0.21, 0.20, 0.21), dark: (0.12, 0.12, 0.13), belly: (0.33, 0.32, 0.33), pointy: false, pattern: .plain, outline: (0.04, 0.04, 0.05)),
        Coat("Cotton Samoyed", base: (0.99, 0.98, 0.96), dark: (0.90, 0.88, 0.85), belly: (1, 1, 1), pointy: true, pattern: .plain, outline: (0.45, 0.42, 0.40)),
    ]
}
