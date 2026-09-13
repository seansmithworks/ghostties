import Testing
@testable import Ghostty

/// Pure coverage for `SpinnerDotFrame.litDots` — the frame-index-to-dot-set
/// mapping the working spinner draws instead of a braille character. Each
/// assertion names the exact dot set its braille frame lights; flip any dot
/// in `litDots` and the matching assertion goes red (e.g. dropping dot 4
/// from frame 0 fails `frameZeroLightsDotsOneTwoFour`, not a generic "8
/// frames" count check).
struct SpinnerDotFrameTests {

    @Test func frameZeroLightsDotsOneTwoFour() {
        // ⠋
        #expect(SpinnerDotFrame.litDots[0] == [1, 2, 4])
    }

    @Test func frameOneLightsDotsOneFourFive() {
        // ⠙
        #expect(SpinnerDotFrame.litDots[1] == [1, 4, 5])
    }

    @Test func frameTwoLightsDotsOneFourFiveSix() {
        // ⠹
        #expect(SpinnerDotFrame.litDots[2] == [1, 4, 5, 6])
    }

    @Test func frameThreeLightsDotsFourFiveSix() {
        // ⠸
        #expect(SpinnerDotFrame.litDots[3] == [4, 5, 6])
    }

    @Test func frameFourLightsDotsThreeFourFiveSix() {
        // ⠼
        #expect(SpinnerDotFrame.litDots[4] == [3, 4, 5, 6])
    }

    @Test func frameFiveLightsDotsThreeFiveSix() {
        // ⠴
        #expect(SpinnerDotFrame.litDots[5] == [3, 5, 6])
    }

    @Test func frameSixLightsDotsTwoThreeSix() {
        // ⠦
        #expect(SpinnerDotFrame.litDots[6] == [2, 3, 6])
    }

    @Test func frameSevenLightsDotsOneTwoThreeSix() {
        // ⠧
        #expect(SpinnerDotFrame.litDots[7] == [1, 2, 3, 6])
    }

    @Test func thereAreExactlyEightFrames() {
        #expect(SpinnerDotFrame.litDots.count == 8)
    }

    @Test func noFrameEverLightsDotSevenOrEight() {
        // The 2×3 grid only has 6 dot positions — confirms the geometry
        // assumption `SessionStatusGlyph.spinnerDotGrid` relies on.
        for dots in SpinnerDotFrame.litDots {
            #expect(dots.isDisjoint(with: [7, 8]))
        }
    }
}
