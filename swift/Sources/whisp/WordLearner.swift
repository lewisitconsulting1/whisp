import Foundation

/// Auto-learns the personal dictionary the way Wispr Flow does: proper nouns
/// and acronyms that keep showing up in cleaned transcripts get promoted to
/// dictionary.txt after a few sightings, so future mishearings self-correct.
enum WordLearner {
    static let countsURL = PersonalDictionary.fileURL
        .deletingLastPathComponent()
        .appendingPathComponent("learned_counts.json")

    /// promote a candidate after this many sightings
    private static let promoteAfter = 3
    /// very common sentence-openers/pronouns that slip through the heuristic
    private static let stoplist: Set<String> = [
        "I", "I'm", "I'll", "I've", "Monday", "Tuesday", "Wednesday", "Thursday",
        "Friday", "Saturday", "Sunday", "January", "February", "March", "April",
        "May", "June", "July", "August", "September", "October", "November",
        "December", "Mr", "Mrs", "Ms", "Dr", "OK", "Okay", "TV", "AM", "PM",
    ]

    /// Scan a cleaned transcript, bump counts for candidate terms, and return
    /// any terms newly promoted into the dictionary.
    static func observe(_ text: String) -> [String] {
        let candidates = extractCandidates(from: text)
        guard !candidates.isEmpty else { return [] }

        let existing = Set(PersonalDictionary.terms().map { normalize($0) })
        var counts = loadCounts()
        var promoted: [String] = []

        for term in candidates {
            let key = normalize(term)
            guard !existing.contains(key) else { continue }
            let n = (counts[term] ?? 0) + 1
            if n >= promoteAfter {
                counts.removeValue(forKey: term)
                promoted.append(term)
            } else {
                counts[term] = n
            }
        }

        if !promoted.isEmpty {
            append(promoted)
        }
        saveCounts(counts)
        return promoted
    }

    /// Proper-noun/acronym heuristic: capitalized words NOT at sentence start,
    /// runs of adjacent capitalized words ("Priya Nguyen"), mixed-case
    /// identifiers ("PostgreSQL", "iPhone") and 2+ letter acronyms anywhere.
    static func extractCandidates(from text: String) -> [String] {
        var results: [String] = []
        let sentences = text.split(omittingEmptySubsequences: true, whereSeparator: { ".!?\n".contains($0) })
        for sentence in sentences {
            let words = sentence.split(separator: " ").map {
                $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "'")))
            }.filter { !$0.isEmpty }

            var i = 0
            while i < words.count {
                let word = words[i]
                let isFirst = (i == 0)
                if isCandidate(word, sentenceStart: isFirst) {
                    // greedily absorb following capitalized words into one term
                    var phrase = [word]
                    var j = i + 1
                    while j < words.count, isCapitalized(words[j]), !stoplist.contains(words[j]) {
                        phrase.append(words[j])
                        j += 1
                    }
                    let term = phrase.joined(separator: " ")
                    if !stoplist.contains(term) {
                        results.append(term)
                    }
                    i = j
                } else {
                    i += 1
                }
            }
        }
        return results
    }

    private static func isCandidate(_ word: String, sentenceStart: Bool) -> Bool {
        guard word.count >= 2, !stoplist.contains(word) else { return false }
        let body = word.dropFirst()
        let hasInnerUpper = body.contains(where: \.isUppercase)
        let isAcronym = word.count >= 2 && word.allSatisfy { $0.isUppercase || $0.isNumber } && word.contains(where: \.isUppercase)
        // mixed case / acronyms count anywhere, plain Capitalized only mid-sentence
        if isAcronym || hasInnerUpper { return true }
        if sentenceStart { return false }
        return word.first?.isUppercase == true && word.count >= 3
    }

    private static func isCapitalized(_ word: String) -> Bool {
        word.first?.isUppercase == true && word.count >= 2
    }

    private static func normalize(_ term: String) -> String {
        // dictionary entries may carry "(often misheard as ...)" hints
        term.split(separator: "(").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? term.lowercased()
    }

    private static func append(_ terms: [String]) {
        PersonalDictionary.ensureExists()
        guard let handle = try? FileHandle(forWritingTo: PersonalDictionary.fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        let line = terms.joined(separator: "\n") + "\n"
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private static func loadCounts() -> [String: Int] {
        guard let data = try? Data(contentsOf: countsURL),
              let counts = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return counts
    }

    private static func saveCounts(_ counts: [String: Int]) {
        if let data = try? JSONEncoder().encode(counts) {
            try? data.write(to: countsURL)
        }
    }
}
