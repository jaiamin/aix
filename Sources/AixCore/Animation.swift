/// Frame math for the "Generating" indicator: a cycling square/circle/triangle glyph and a highlight that sweeps
/// across the label. Kept free of terminal I/O so it can be tested.
public enum Animation {
    public static let glyphs: [Character] = ["■", "●", "▲"]
    /// Frames each shape stays on screen, so the cycle reads as shapes rather than flicker.
    static let hold = 4

    public static func glyph(_ frame: Int) -> Character {
        glyphs[(frame / hold) % glyphs.count]
    }

    /// Half-width of the highlight, in characters.
    static let band = 3
    /// Frames the label rests unlit between sweeps.
    static let pause = 6

    /// Brightness 0…1 for each of `count` characters at `frame`. The band enters from the left,
    /// leaves on the right, then rests for `pause` frames.
    public static func shimmer(count: Int, frame: Int) -> [Double] {
        let period = count + 2 * band + pause
        let center = frame % period - band
        return (0..<count).map { i in
            max(0, 1 - Double(abs(i - center)) / Double(band))
        }
    }
}
