import AppKit
import SwiftUI

/// A system animation; under Reduce Motion a movement happens at once while a fade still plays.
struct Motion: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case movement
        case fade
    }

    let curve: UnitCurve
    let duration: Duration
    let kind: Kind

    init(_ curve: UnitCurve, _ duration: Duration, _ kind: Kind) {
        self.curve = curve
        self.duration = duration
        self.kind = kind
    }

    @MainActor static var isReduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func animation(duration: Duration? = nil, reduceMotion: Bool) -> Animation? {
        if reduceMotion && kind == .movement { return nil }
        return .timingCurve(curve, duration: (duration ?? self.duration).seconds)
    }
}

extension Duration {
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

struct Glow: ViewModifier {
    let color: Color
    let intensity: Double

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.65 * intensity), radius: 5 * intensity)
            .shadow(color: color.opacity(0.65 * intensity), radius: 5 * intensity)
            .shadow(color: color.opacity(0.65 * intensity), radius: 5 * intensity)
    }
}

extension View {
    func glow(_ color: Color, intensity: Double) -> some View {
        modifier(Glow(color: color, intensity: intensity))
    }
}

enum RegisterEffects {
    static let glowPhase = Motion(.easeInOut, .milliseconds(750), .fade)
    static let notifierFade = Motion(.easeInOut, .milliseconds(250), .fade)
    static let schedulerSlide = Motion(.easeIn, .milliseconds(300), .movement)
}

extension Animation {
    @MainActor static func motion(_ motion: Motion, duration: Duration? = nil) -> Animation? {
        motion.animation(duration: duration, reduceMotion: Motion.isReduced)
    }
}
