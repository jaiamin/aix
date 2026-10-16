/// A 3×3 cube-grid loader that fits on one text line, drawn with two Braille characters.
/// Braille cells are 2 dots wide, so columns 0–1 live in the first character and column 2 in
/// the left half of the second; the spacing stays even across the boundary.
public enum Cube {
    public static let period = 10
    /// How many frames each dot stays dark as the wave passes.
    static let gap = 3

    /// Bit for (row, col) inside one Braille character (col 0 or 1, row 0–2). Uses the cell's
    /// bottom three dot rows: the top three sit above the text's baseline and look raised.
    static func bit(row: Int, col: Int) -> UInt32 {
        [[0x02, 0x10], [0x04, 0x20], [0x40, 0x80]][row][col]
    }

    /// Whether a dot is lit. Dots on the same anti-diagonal share a phase, so a dark band
    /// sweeps corner to corner, like the classic cube-grid spinner.
    public static func isLit(row: Int, col: Int, frame: Int) -> Bool {
        let phase = ((frame - (row + col)) % period + period) % period
        return phase >= gap
    }

    public static func frame(_ n: Int) -> String {
        var left: UInt32 = 0, right: UInt32 = 0
        for row in 0..<3 {
            for col in 0..<3 where isLit(row: row, col: col, frame: n) {
                if col < 2 { left |= bit(row: row, col: col) } else { right |= bit(row: row, col: 0) }
            }
        }
        return String(UnicodeScalar(0x2800 + left)!) + String(UnicodeScalar(0x2800 + right)!)
    }
}
