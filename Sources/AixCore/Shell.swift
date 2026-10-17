/// A forgiving shell tokenizer: just enough to find each command's words for the safety checks.
public enum Shell {
    static let prefixKeywords: Set<String> = ["if", "then", "else", "elif", "while", "until", "do", "!", "{", "time", "exec", "command", "nohup"]
    static let closingKeywords: Set<String> = ["fi", "done", "esac", "}", "]]"]
    static let headerKeywords: Set<String> = ["for", "case", "select", "function", "[["]

    public static func programs(in script: String) -> [String] {
        commands(in: script).compactMap { $0.first }.filter { !$0.hasPrefix("$") }
    }

    /// Each simple command's words, unquoted, without leading assignments and keywords.
    public static func commands(in script: String) -> [[String]] {
        segments(script).compactMap { seg in
            var words = seg
            while let w = words.first {
                if isAssignment(w) || prefixKeywords.contains(w) || isRedirection(w) {
                    words.removeFirst()
                } else {
                    break
                }
            }
            guard let first = words.first, !closingKeywords.contains(first), !headerKeywords.contains(first) else { return nil }
            return words
        }
    }

    static func isAssignment(_ w: String) -> Bool {
        guard let eq = w.firstIndex(of: "="), eq != w.startIndex else { return false }
        return w[..<eq].allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber } && !w.first!.isNumber
    }

    static func isRedirection(_ w: String) -> Bool {
        let body = w.drop(while: \.isNumber)
        return body.hasPrefix(">") || body.hasPrefix("<")
    }

    /// Splits on unquoted `| || & && ; ( )` and newlines, then into words.
    static func segments(_ s: String) -> [[String]] {
        var result: [[String]] = []
        var words: [String] = []
        var word = ""
        var inWord = false
        var quote: Character? = nil
        let chars = Array(s)
        var i = 0

        func endWord() {
            if inWord { words.append(word) }
            word = ""
            inWord = false
        }
        func endSegment() {
            endWord()
            if !words.isEmpty { result.append(words) }
            words = []
        }

        while i < chars.count {
            let c = chars[i]
            if let q = quote {
                if c == q { quote = nil }
                else if c == "\\" && q == "\"" && i + 1 < chars.count { i += 1; word.append(chars[i]) }
                else { word.append(c) }
                i += 1
                continue
            }
            switch c {
            case "'", "\"":
                quote = c
                inWord = true
            case "\\":
                if i + 1 < chars.count { i += 1; word.append(chars[i]); inWord = true }
            case "$" where i + 1 < chars.count && chars[i + 1] == "(":
                // Keep $( … ) inside the current word; programs inside it aren't checked.
                var depth = 0
                repeat {
                    if chars[i] == "(" { depth += 1 } else if chars[i] == ")" { depth -= 1 }
                    word.append(chars[i])
                    i += 1
                } while i < chars.count && depth > 0
                inWord = true
                continue
            case "`":
                word.append(c)
                i += 1
                while i < chars.count && chars[i] != "`" { word.append(chars[i]); i += 1 }
                if i < chars.count { word.append(chars[i]) }
                inWord = true
            case "&" where word.hasSuffix(">") || (i + 1 < chars.count && chars[i + 1] == ">"):
                word.append(c)  // 2>&1, &>
                inWord = true
            case "|" where word.hasSuffix(">"):
                word.append(c)  // >|
            case "|", "&", ";", "(", ")", "\n":
                endSegment()
            case " ", "\t":
                endWord()
            default:
                word.append(c)
                inWord = true
            }
            i += 1
        }
        endSegment()
        return result
    }
}
