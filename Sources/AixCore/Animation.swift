/// Frames for the "Generating..." indicator.
public enum Animation {
    public static let glyphs: [Character] = ["■", "●", "▲"]
    /// Frames per shape, so it reads as shapes rather than flicker.
    static let hold = 4

    public static func glyph(_ frame: Int) -> Character {
        glyphs[(frame / hold) % glyphs.count]
    }

    static let band = 3
    static let pause = 6

    /// Brightness 0…1 per character: a band sweeps left to right, then rests for `pause` frames.
    public static func shimmer(count: Int, frame: Int) -> [Double] {
        let period = count + 2 * band + pause
        let center = frame % period - band
        return (0..<count).map { i in
            max(0, 1 - Double(abs(i - center)) / Double(band))
        }
    }
}
