import SwiftUI

/// Icons the TV's Dynamic Island can draw (inline SVGs in island.js) with matching SF Symbols.
enum IslandIcon: String, CaseIterable, Identifiable {
    case bell, message, food, home, heart, star, phone, car, moon, gift, info, timer

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .bell: "bell.fill"
        case .message: "message.fill"
        case .food: "fork.knife"
        case .home: "house.fill"
        case .heart: "heart.fill"
        case .star: "star.fill"
        case .phone: "phone.fill"
        case .car: "car.fill"
        case .moon: "moon.fill"
        case .gift: "gift.fill"
        case .info: "info"
        case .timer: "timer"
        }
    }
}

/// iOS system colours, sent to the TV as hex.
enum IslandColor: String, CaseIterable, Identifiable {
    case blue = "#0a84ff", green = "#30d158", orange = "#ff9f0a", red = "#ff453a"
    case pink = "#ff375f", purple = "#bf5af2", indigo = "#5e5ce6", teal = "#40c8e0"

    var id: String { rawValue }

    var color: Color {
        let v = UInt32(rawValue.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

/// Ready-made notifications for one-tap sending.
struct IslandPreset: Identifiable {
    let title: String
    let text: String
    let icon: IslandIcon
    let color: IslandColor
    var id: String { title }

    static let all: [IslandPreset] = [
        IslandPreset(title: "Dinner is ready", text: "Come to the table", icon: .food, color: .orange),
        IslandPreset(title: "Someone's at the door", text: "Doorbell", icon: .bell, color: .blue),
        IslandPreset(title: "Leaving soon", text: "Get ready, we leave in 10 minutes", icon: .car, color: .teal),
        IslandPreset(title: "Bedtime", text: "Time to wind down", icon: .moon, color: .indigo),
        IslandPreset(title: "Call me", text: "Check your phone", icon: .phone, color: .green),
        IslandPreset(title: "Love you", text: "", icon: .heart, color: .pink)
    ]
}
