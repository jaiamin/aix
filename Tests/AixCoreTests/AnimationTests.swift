import Testing
@testable import AixCore

@Suite struct AnimationTests {
    @Test func glyphsCycleSquareCircleTriangle() {
        let seen = (0..<12).map(Animation.glyph)
        #expect(seen == ["■", "■", "■", "■", "●", "●", "●", "●", "▲", "▲", "▲", "▲"])
        #expect(Animation.glyph(12) == "■")
    }

    @Test func shimmerSweepsLeftToRight() {
        let peak = { (frame: Int) in Animation.shimmer(count: 10, frame: frame).firstIndex(of: 1) }
        #expect(peak(3) == 0)
        #expect(peak(8) == 5)
        #expect(peak(12) == 9)
    }

    @Test func shimmerRestsBetweenSweeps() {
        // After the band leaves the right edge, every character is unlit for a while.
        let resting = (0..<30).filter { Animation.shimmer(count: 10, frame: $0).allSatisfy { $0 == 0 } }
        #expect(resting.count >= 3)
        #expect(Animation.shimmer(count: 10, frame: 5).allSatisfy { (0...1).contains($0) })
    }
}
