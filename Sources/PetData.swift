import Foundation

/// Everything about the pet that survives a relaunch.
struct PetData: Codable {
    var name = "Biscuit"
    var coat = 0
    var size = 1
    var muted = false
    var hunger: Double = 80
    var fun: Double = 80
    var energy: Double = 90
    var hygiene: Double = 90
    var xp: Double = 0
    var steps = 0
    var fetches = 0
    var treats = 0
    var treasures = 0
    var poopsCleaned = 0
    var tricks = 0
    var pets = 0
    var visits = 0
    var adopted = Date()
    var lastSaved = Date()

    var level: Int { Int((xp / 25).squareRoot()) + 1 }
    var xpForNext: Double { Double(level * level) * 25 }
    var mood: Double { (hunger + fun + energy + hygiene) / 4 }
    var moodEmoji: String {
        switch mood {
        case 75...: return "😄"
        case 50..<75: return "🙂"
        case 30..<50: return "😐"
        default: return "😢"
        }
    }
    var moodWord: String {
        switch mood {
        case 75...: return "Ecstatic"
        case 50..<75: return "Happy"
        case 30..<50: return "Meh"
        default: return "Needs you"
        }
    }

    private static let key = "petData.v1"

    static func load() -> PetData {
        if let raw = UserDefaults.standard.data(forKey: key),
           let d = try? JSONDecoder().decode(PetData.self, from: raw) {
            return d
        }
        return PetData()
    }

    func save() {
        var copy = self
        copy.lastSaved = Date()
        if let raw = try? JSONEncoder().encode(copy) {
            UserDefaults.standard.set(raw, forKey: PetData.key)
        }
    }

    /// Applies the time spent away (gently — nobody gets hurt while you're gone).
    /// Returns how long the app was closed, in seconds.
    mutating func catchUp() -> Double {
        let away = max(0, Date().timeIntervalSince(lastSaved))
        let t = min(away, 10 * 3600)
        hunger = max(15, hunger - t * 100 / (3.5 * 3600))
        fun = max(15, fun - t * 100 / (5 * 3600))
        hygiene = max(20, hygiene - t * 100 / (10 * 3600))
        energy = min(100, energy + t * 100 / (30 * 60))
        return away
    }
}
