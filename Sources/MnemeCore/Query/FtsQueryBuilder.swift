import Foundation

public enum FtsQueryBuilder {
    public static func build(_ query: String) -> String {
        let terms = queryTerms(query)
        return terms.map(quote).joined(separator: " OR ")
    }

    public static func indexText(_ text: String) -> String {
        let bigrams = cjkBigrams(in: text)
        guard !bigrams.isEmpty else {
            return text
        }
        return text + "\n" + bigrams.joined(separator: " ")
    }

    static func queryTerms(_ text: String) -> [String] {
        var terms: [String] = []
        var latin = ""
        var cjkRun = ""

        func flushLatin() {
            if !latin.isEmpty {
                terms.append(latin.lowercased())
                latin = ""
            }
        }

        func flushCJK() {
            if !cjkRun.isEmpty {
                let chars = Array(cjkRun)
                if chars.count == 1 {
                    terms.append(String(chars[0]))
                } else {
                    for index in 0..<(chars.count - 1) {
                        terms.append(String(chars[index...index + 1]))
                    }
                }
                cjkRun = ""
            }
        }

        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                flushLatin()
                cjkRun.append(String(scalar))
            } else if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                flushCJK()
                latin.append(String(scalar))
            } else {
                flushLatin()
                flushCJK()
            }
        }
        flushLatin()
        flushCJK()

        var seen: Set<String> = []
        return terms.filter { term in
            guard !term.isEmpty, !seen.contains(term) else {
                return false
            }
            seen.insert(term)
            return true
        }
    }

    private static func cjkBigrams(in text: String) -> [String] {
        var result: [String] = []
        var run: [Character] = []

        func flushRun() {
            if run.count >= 2 {
                for index in 0..<(run.count - 1) {
                    result.append(String(run[index...index + 1]))
                }
            }
            run.removeAll()
        }

        for character in text {
            if character.unicodeScalars.allSatisfy(isCJK) {
                run.append(character)
            } else {
                flushRun()
            }
        }
        flushRun()
        return result
    }

    private static func quote(_ term: String) -> String {
        "\"\(term.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case
            0x3040...0x309F, // Hiragana
            0x30A0...0x30FF, // Katakana
            0x31F0...0x31FF, // Katakana phonetic extensions
            0x3400...0x4DBF, // CJK Unified Ideographs Extension A
            0x4E00...0x9FFF, // CJK Unified Ideographs
            0xAC00...0xD7AF, // Hangul syllables
            0xF900...0xFAFF, // CJK Compatibility Ideographs
            0xFF66...0xFF9F, // Halfwidth Katakana
            0x20000...0x2A6DF, // CJK Unified Ideographs Extension B
            0x2A700...0x2B73F,
            0x2B740...0x2B81F,
            0x2B820...0x2CEAF,
            0x2CEB0...0x2EBEF,
            0x30000...0x3134F:
            true
        default:
            false
        }
    }
}
