import SwiftUI
import Testing

@testable import AbakusUI

@MainActor
@Suite struct MotionTests {
    @Test func aMotionIsASystemTimingCurve() {
        let motion = Motion(.easeOut, .milliseconds(250), .movement)
        #expect(motion.animation(reduceMotion: false) == .timingCurve(.easeOut, duration: 0.25))
        #expect(
            motion.animation(duration: .milliseconds(100), reduceMotion: false)
                == .timingCurve(.easeOut, duration: 0.1))
    }

    @Test func reduceMotionStopsMovementButKeepsFades() {
        #expect(Motion(.easeInOut, .milliseconds(250), .movement).animation(reduceMotion: true) == nil)
        #expect(
            Motion(.easeInOut, .milliseconds(250), .fade).animation(reduceMotion: true)
                == .timingCurve(.easeInOut, duration: 0.25))
    }

    @Test func theGlowIsAFadeAndEverythingThatMovesIsMovement() {
        #expect(RegisterEffects.glowPhase.kind == .fade)
        #expect(RegisterEffects.notifierFade.kind == .fade)
        for motion in [
            RegisterEffects.schedulerSlide,
            BudgetStyle.groupResize, BudgetStyle.headerResize, BudgetStyle.indicatorMove,
        ] {
            #expect(motion.kind == .movement)
        }
    }
}
