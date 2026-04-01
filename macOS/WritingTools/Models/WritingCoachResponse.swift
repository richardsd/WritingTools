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
