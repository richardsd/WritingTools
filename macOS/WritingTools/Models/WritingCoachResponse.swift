import Foundation

struct WritingCoachResponse: Codable, Equatable, Sendable {
    struct PriorityImprovement: Codable, Equatable, Identifiable, Sendable {
        let issue: String
        let whyItMatters: String
        let before: String
        let after: String

        var id: String {
            [issue, before, after].joined(separator: "|")
        }

        enum CodingKeys: String, CodingKey {
            case issue
            case whyItMatters = "why_it_matters"
            case before
            case after
        }
    }

    let assessment: String
    let strengths: [String]
    let priorityImprovements: [PriorityImprovement]
    let suggestedRevision: String?
    let followUpPrompts: [String]
    let outOfScopeReason: String?

    enum CodingKeys: String, CodingKey {
        case assessment
        case strengths
        case priorityImprovements = "priority_improvements"
        case suggestedRevision = "suggested_revision"
        case followUpPrompts = "follow_up_prompts"
        case outOfScopeReason = "out_of_scope_reason"
    }

    var trimmedSuggestedRevision: String? {
        let trimmed = suggestedRevision?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    var trimmedOutOfScopeReason: String? {
        let trimmed = outOfScopeReason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    var renderedText: String {
        var sections: [String] = []
        let trimmedAssessment = assessment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAssessment.isEmpty {
            sections.append("Assessment\n\(trimmedAssessment)")
        }

        let validStrengths = strengths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !validStrengths.isEmpty {
            sections.append(
                "Strengths\n" + validStrengths.map { "- \($0)" }.joined(separator: "\n")
            )
        }

        let validImprovements = Array(priorityImprovements.prefix(3)).filter { improvement in
            !improvement.issue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !validImprovements.isEmpty {
            let improvementText = validImprovements.map { improvement in
                """
                - \(improvement.issue.trimmingCharacters(in: .whitespacesAndNewlines))
                  Why it matters: \(improvement.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines))
                  Before: \(improvement.before.trimmingCharacters(in: .whitespacesAndNewlines))
                  After: \(improvement.after.trimmingCharacters(in: .whitespacesAndNewlines))
                """
            }.joined(separator: "\n")
            sections.append("Priority Improvements\n\(improvementText)")
        }

        if let trimmedSuggestedRevision {
            sections.append("Suggested Revision\n\(trimmedSuggestedRevision)")
        }

        if let trimmedOutOfScopeReason {
            sections.append("Out of Scope\n\(trimmedOutOfScopeReason)")
        }

        let validFollowUps = followUpPrompts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !validFollowUps.isEmpty {
            sections.append(
                "Suggested Follow-Ups\n" + validFollowUps.map { "- \($0)" }.joined(separator: "\n")
            )
        }

        return sections.joined(separator: "\n\n")
    }

    static func parse(from rawContent: String) -> WritingCoachResponse? {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let jsonString = extractJSONObject(from: trimmed),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(WritingCoachResponse.self, from: data)
    }

    private static func extractJSONObject(from content: String) -> String? {
        let fencedPattern = #"^```(?:json)?\s*([\s\S]*?)\s*```$"#
        if let regex = try? NSRegularExpression(pattern: fencedPattern),
           let match = regex.firstMatch(
                in: content,
                range: NSRange(content.startIndex..., in: content)
           ),
           let range = Range(match.range(at: 1), in: content) {
            let inner = String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.first == "{", inner.last == "}" {
                return inner
            }
        }

        if content.first == "{", content.last == "}" {
            return content
        }

        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}") else {
            return nil
        }

        let candidate = String(content[start...end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.first == "{"
            && candidate.last == "}"
            ? candidate
            : nil
    }
}

struct WritingCoachStreamingPreview: Equatable, Sendable {
    struct PriorityImprovement: Equatable, Identifiable, Sendable {
        let issue: String?
        let whyItMatters: String?
        let before: String?
        let after: String?

        var id: String {
            [
                issue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                before?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                after?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            ].joined(separator: "|")
        }

        var hasVisibleContent: Bool {
            [issue, whyItMatters, before, after].contains {
                guard let value = $0?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return false
                }
                return !value.isEmpty
            }
        }
    }

    let assessment: String?
    let strengths: [String]
    let priorityImprovements: [PriorityImprovement]
    let suggestedRevision: String?
    let followUpPrompts: [String]
    let outOfScopeReason: String?

    init(
        assessment: String?,
        strengths: [String],
        priorityImprovements: [PriorityImprovement],
        suggestedRevision: String?,
        followUpPrompts: [String],
        outOfScopeReason: String?
    ) {
        self.assessment = Self.trimmed(assessment)
        self.strengths = strengths.compactMap(Self.trimmed)
        self.priorityImprovements = Array(priorityImprovements.prefix(3)).filter(\.hasVisibleContent)
        self.suggestedRevision = Self.trimmed(suggestedRevision)
        self.followUpPrompts = followUpPrompts.compactMap(Self.trimmed)
        self.outOfScopeReason = Self.trimmed(outOfScopeReason)
    }

    init(response: WritingCoachResponse) {
        self.init(
            assessment: response.assessment,
            strengths: response.strengths,
            priorityImprovements: response.priorityImprovements.map { improvement in
                PriorityImprovement(
                    issue: improvement.issue,
                    whyItMatters: improvement.whyItMatters,
                    before: improvement.before,
                    after: improvement.after
                )
            },
            suggestedRevision: response.trimmedSuggestedRevision,
            followUpPrompts: response.followUpPrompts,
            outOfScopeReason: response.trimmedOutOfScopeReason
        )
    }

    var hasVisibleContent: Bool {
        assessment != nil
            || !strengths.isEmpty
            || !priorityImprovements.isEmpty
            || suggestedRevision != nil
            || !followUpPrompts.isEmpty
            || outOfScopeReason != nil
    }

    var renderedText: String {
        var sections: [String] = []

        if let assessment {
            sections.append("Assessment\n\(assessment)")
        }

        if !strengths.isEmpty {
            sections.append(
                "Strengths\n" + strengths.map { "- \($0)" }.joined(separator: "\n")
            )
        }

        if !priorityImprovements.isEmpty {
            let improvementText = priorityImprovements.map { improvement in
                var lines: [String] = []
                if let issue = Self.trimmed(improvement.issue) {
                    lines.append("- \(issue)")
                } else {
                    lines.append("-")
                }
                if let whyItMatters = Self.trimmed(improvement.whyItMatters) {
                    lines.append("  Why it matters: \(whyItMatters)")
                }
                if let before = Self.trimmed(improvement.before) {
                    lines.append("  Before: \(before)")
                }
                if let after = Self.trimmed(improvement.after) {
                    lines.append("  After: \(after)")
                }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n")

            sections.append("Priority Improvements\n\(improvementText)")
        }

        if let suggestedRevision {
            sections.append("Suggested Revision\n\(suggestedRevision)")
        }

        if let outOfScopeReason {
            sections.append("Out of Scope\n\(outOfScopeReason)")
        }

        if !followUpPrompts.isEmpty {
            sections.append(
                "Suggested Follow-Ups\n" + followUpPrompts.map { "- \($0)" }.joined(separator: "\n")
            )
        }

        return sections.joined(separator: "\n\n")
    }

    static func parse(from rawContent: String) -> WritingCoachStreamingPreview? {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let response = WritingCoachResponse.parse(from: trimmed) {
            return WritingCoachStreamingPreview(response: response)
        }

        let extractor = PartialJSONExtractor(content: trimmed)
        let preview = WritingCoachStreamingPreview(
            assessment: extractor.stringValue(forKey: "assessment"),
            strengths: extractor.stringArray(forKey: "strengths"),
            priorityImprovements: extractor.priorityImprovements(),
            suggestedRevision: extractor.nullableStringValue(forKey: "suggested_revision"),
            followUpPrompts: extractor.stringArray(forKey: "follow_up_prompts"),
            outOfScopeReason: extractor.nullableStringValue(forKey: "out_of_scope_reason")
        )

        return preview.hasVisibleContent ? preview : nil
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}

private struct PartialJSONExtractor {
    private let content: String

    init(content: String) {
        self.content = content
    }

    func stringValue(forKey key: String) -> String? {
        guard let valueStart = valueStartIndex(forKey: key) else { return nil }
        return parseStringLikeValue(from: valueStart)
    }

    func nullableStringValue(forKey key: String) -> String? {
        guard let valueStart = valueStartIndex(forKey: key) else { return nil }

        if matchesNull(at: valueStart) {
            return nil
        }

        return parseStringLikeValue(from: valueStart)
    }

    func stringArray(forKey key: String) -> [String] {
        guard let valueStart = valueStartIndex(forKey: key) else { return [] }
        return parseStringArray(from: valueStart)
    }

    func priorityImprovements() -> [WritingCoachStreamingPreview.PriorityImprovement] {
        guard let valueStart = valueStartIndex(forKey: "priority_improvements"),
              let arrayStart = nextNonWhitespaceIndex(from: valueStart),
              arrayStart < content.endIndex,
              content[arrayStart] == "[" else {
            return []
        }

        var improvements: [WritingCoachStreamingPreview.PriorityImprovement] = []
        var cursor = content.index(after: arrayStart)

        while cursor < content.endIndex && improvements.count < 3 {
            cursor = skipWhitespaceAndCommas(from: cursor)
            guard cursor < content.endIndex else { break }

            if content[cursor] == "]" {
                break
            }

            guard content[cursor] == "{",
                  let objectRange = objectRange(from: cursor) else {
                break
            }

            let objectContent = String(content[objectRange])
            let objectExtractor = PartialJSONExtractor(content: objectContent)
            let improvement = WritingCoachStreamingPreview.PriorityImprovement(
                issue: objectExtractor.stringValue(forKey: "issue"),
                whyItMatters: objectExtractor.stringValue(forKey: "why_it_matters"),
                before: objectExtractor.stringValue(forKey: "before"),
                after: objectExtractor.stringValue(forKey: "after")
            )

            if improvement.hasVisibleContent {
                improvements.append(improvement)
            }

            cursor = objectRange.upperBound
        }

        return improvements
    }

    private func valueStartIndex(forKey key: String) -> String.Index? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #""\#(escapedKey)"\s*:\s*"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: content,
                range: NSRange(content.startIndex..., in: content)
              ),
              let range = Range(match.range, in: content) else {
            return nil
        }

        return range.upperBound
    }

    private func parseStringLikeValue(from index: String.Index) -> String? {
        guard let valueStart = nextNonWhitespaceIndex(from: index),
              valueStart < content.endIndex else {
            return nil
        }

        guard content[valueStart] == "\"" else { return nil }
        return parseJSONString(from: valueStart)?.value
    }

    private func parseStringArray(from index: String.Index) -> [String] {
        guard let arrayStart = nextNonWhitespaceIndex(from: index),
              arrayStart < content.endIndex,
              content[arrayStart] == "[" else {
            return []
        }

        var values: [String] = []
        var cursor = content.index(after: arrayStart)

        while cursor < content.endIndex {
            cursor = skipWhitespaceAndCommas(from: cursor)
            guard cursor < content.endIndex else { break }

            if content[cursor] == "]" {
                break
            }

            guard content[cursor] == "\"",
                  let parsed = parseJSONString(from: cursor) else {
                break
            }

            let trimmed = parsed.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                values.append(trimmed)
            }

            cursor = parsed.endIndex
            if !parsed.didTerminate {
                break
            }
        }

        return values
    }

    private func parseJSONString(
        from quoteIndex: String.Index
    ) -> (value: String, endIndex: String.Index, didTerminate: Bool)? {
        guard quoteIndex < content.endIndex, content[quoteIndex] == "\"" else {
            return nil
        }

        var cursor = content.index(after: quoteIndex)
        var value = ""
        var isEscaping = false

        while cursor < content.endIndex {
            let character = content[cursor]

            if isEscaping {
                switch character {
                case "\"", "\\", "/":
                    value.append(character)
                case "b":
                    value.append("\u{08}")
                case "f":
                    value.append("\u{0C}")
                case "n":
                    value.append("\n")
                case "r":
                    value.append("\r")
                case "t":
                    value.append("\t")
                case "u":
                    let hexStart = content.index(after: cursor)
                    var hexCursor = hexStart
                    var hexDigits = ""

                    while hexCursor < content.endIndex,
                          hexDigits.count < 4 {
                        let hexCharacter = content[hexCursor]
                        guard hexCharacter.isHexDigit else { break }
                        hexDigits.append(hexCharacter)
                        hexCursor = content.index(after: hexCursor)
                    }

                    if hexDigits.count == 4,
                       let scalarValue = UInt32(hexDigits, radix: 16),
                       let scalar = UnicodeScalar(scalarValue) {
                        value.append(Character(scalar))
                        cursor = content.index(before: hexCursor)
                    } else {
                        return (value, content.endIndex, false)
                    }
                default:
                    value.append(character)
                }

                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else if character == "\"" {
                return (
                    value,
                    content.index(after: cursor),
                    true
                )
            } else {
                value.append(character)
            }

            cursor = content.index(after: cursor)
        }

        return (value, content.endIndex, false)
    }

    private func objectRange(from startIndex: String.Index) -> Range<String.Index>? {
        guard startIndex < content.endIndex, content[startIndex] == "{" else {
            return nil
        }

        var cursor = startIndex
        var depth = 0
        var inString = false
        var isEscaping = false

        while cursor < content.endIndex {
            let character = content[cursor]

            if inString {
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                if character == "\"" {
                    inString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return startIndex..<content.index(after: cursor)
                    }
                }
            }

            cursor = content.index(after: cursor)
        }

        return startIndex..<content.endIndex
    }

    private func nextNonWhitespaceIndex(from index: String.Index) -> String.Index? {
        var cursor = index
        while cursor < content.endIndex && content[cursor].isWhitespace {
            cursor = content.index(after: cursor)
        }
        return cursor < content.endIndex ? cursor : nil
    }

    private func skipWhitespaceAndCommas(from index: String.Index) -> String.Index {
        var cursor = index
        while cursor < content.endIndex {
            let character = content[cursor]
            if character.isWhitespace || character == "," {
                cursor = content.index(after: cursor)
            } else {
                break
            }
        }
        return cursor
    }

    private func matchesNull(at index: String.Index) -> Bool {
        let remaining = content[index...]
        return remaining.hasPrefix("null")
    }
}
