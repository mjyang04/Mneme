import Foundation

public struct Chunker: Sendable {
    public let targetChars: Int
    public let overlapChars: Int

    public init(targetChars: Int = 1_200, overlapChars: Int = 150) {
        precondition(targetChars > 0)
        precondition(overlapChars >= 0 && overlapChars < targetChars)
        self.targetChars = targetChars
        self.overlapChars = overlapChars
    }

    public func chunk(_ text: String) -> [Chunk] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let characters = Array(text)
        var chunks: [Chunk] = []
        var start = 0
        var ordinal = 0

        while start < characters.count {
            var end = min(start + targetChars, characters.count)
            if end < characters.count {
                let earliestBreak = max(start + targetChars - overlapChars, start + 1)
                if let breakIndex = lastBreak(in: characters, from: earliestBreak, to: end) {
                    end = breakIndex
                }
            }

            let body = String(characters[start..<end])
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(Chunk(
                    ordinal: ordinal,
                    text: body,
                    locator: TextLocator(startChar: start, endChar: end)
                ))
                ordinal += 1
            }

            if end >= characters.count {
                break
            }
            start = max(end - overlapChars, start + 1)
        }

        return chunks
    }

    private func lastBreak(in characters: [Character], from: Int, to: Int) -> Int? {
        var index = to - 1
        while index > from {
            if characters[index] == "\n" {
                return index + 1
            }
            index -= 1
        }
        return nil
    }
}
