import Foundation
import SwiftUI

enum AssistantMode: String, CaseIterable {
    case idle
    case wakeDetected
    case recording
    case transcribing
    case thinking
    case speaking
    case error

    var localizedTitle: String {
        let kk = OnboardingStore.shared.profile.language == .kazakh
        switch self {
        case .idle:          return kk ? "Күту режимі"  : "Ожидание"
        case .wakeDetected:  return kk ? "Оянды"        : "Активирован"
        case .recording:     return kk ? "Тыңдап тұр"  : "Слушаю"
        case .transcribing:  return kk ? "Түсінуде"     : "Понимаю"
        case .thinking:      return kk ? "Ойлануда"     : "Думаю"
        case .speaking:      return kk ? "Сөйлеп тұр"  : "Говорю"
        case .error:         return kk ? "Қате"          : "Ошибка"
        }
    }

    var sfSymbol: String {
        switch self {
        case .idle:          return "circle.fill"
        case .wakeDetected:  return "ear.fill"
        case .recording:     return "mic.fill"
        case .transcribing:  return "waveform"
        case .thinking:      return "brain"
        case .speaking:      return "speaker.wave.3.fill"
        case .error:         return "exclamationmark.circle.fill"
        }
    }

    // Orb outer gradient colors (dark → vibrant)
    var gradientColors: [Color] {
        switch self {
        case .idle:         return [Color(hex: "334155"), Color(hex: "0F172A")]
        case .wakeDetected: return [Color(hex: "64748B"), Color(hex: "1E293B")]
        case .recording:    return [Color(hex: "F59E0B"), Color(hex: "92400E")]
        case .transcribing: return [Color(hex: "C084FC"), Color(hex: "4C1D95")]
        case .thinking:     return [Color(hex: "8B5CF6"), Color(hex: "4C1D95")]
        case .speaking:     return [Color(hex: "34D399"), Color(hex: "064E3B")]
        case .error:        return [Color(hex: "EF4444"), Color(hex: "7F1D1D")]
        }
    }

    // Glow and accent color
    var accentColor: Color {
        switch self {
        case .idle:         return Color(hex: "475569")
        case .wakeDetected: return Color(hex: "94A3B8")
        case .recording:    return Color(hex: "F59E0B")
        case .transcribing: return Color(hex: "A78BFA")
        case .thinking:     return Color(hex: "8B5CF6")
        case .speaking:     return Color(hex: "34D399")
        case .error:        return Color(hex: "EF4444")
        }
    }

    // Inner circle fill
    var innerColor: Color {
        switch self {
        case .idle:         return Color(hex: "1E293B").opacity(0.82)
        case .wakeDetected: return Color(hex: "1E293B").opacity(0.82)
        case .recording:    return Color(hex: "1C0800").opacity(0.78)
        case .transcribing: return Color(hex: "1A0050").opacity(0.78)
        case .thinking:     return Color(hex: "1A0050").opacity(0.78)
        case .speaking:     return Color(hex: "012B1D").opacity(0.78)
        case .error:        return Color(hex: "1C0000").opacity(0.78)
        }
    }

    // Animation pulse strength (0 = static, 1 = max)
    var pulseFactor: Double {
        switch self {
        case .idle:         return 0.0
        case .wakeDetected: return 0.5
        case .recording:    return 0.9
        case .transcribing: return 0.5
        case .thinking:     return 0.7
        case .speaking:     return 0.7
        case .error:        return 0.2
        }
    }

    var isListening: Bool { self == .idle }

    var shouldPauseWakeListener: Bool {
        switch self {
        case .recording, .transcribing, .thinking, .speaking: return true
        default: return false
        }
    }
}
