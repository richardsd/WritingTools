import SwiftUI

struct WritingCoachMessageView: View {
    let response: WritingCoachResponse
    let fontSize: CGFloat
    let onPromptTap: ((String) -> Void)?

    private var strengths: [String] {
        response.strengths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var improvements: [WritingCoachResponse.PriorityImprovement] {
        Array(response.priorityImprovements.prefix(3)).filter { improvement in
            !improvement.issue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var followUps: [String] {
        response.followUpPrompts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            coachSection(title: "Assessment") {
                Text(response.assessment.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: fontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !strengths.isEmpty {
                coachSection(title: "Strengths") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(strengths.enumerated()), id: \.offset) { _, strength in
                            Label {
                                Text(strength)
                                    .font(.system(size: fontSize))
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            if !improvements.isEmpty {
                coachSection(title: "Priority Improvements") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(improvements) { improvement in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(improvement.issue.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.system(size: fontSize, weight: .semibold))

                                Text(improvement.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.system(size: fontSize))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                comparisonBlock(
                                    title: "Before",
                                    text: improvement.before
                                )
                                comparisonBlock(
                                    title: "After",
                                    text: improvement.after
                                )
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }

            if let outOfScopeReason = response.trimmedOutOfScopeReason {
                coachSection(title: "Why There’s No Suggested Revision") {
                    Text(outOfScopeReason)
                        .font(.system(size: fontSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let suggestedRevision = response.trimmedSuggestedRevision {
                coachSection(title: "Suggested Revision") {
                    Text(suggestedRevision)
                        .font(.system(size: fontSize))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !followUps.isEmpty {
                coachSection(title: "Suggested Follow-Ups") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(followUps.enumerated()), id: \.offset) { _, prompt in
                            Button(action: {
                                onPromptTap?(prompt)
                            }) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.top, 2)
                                    Text(prompt)
                                        .font(.system(size: fontSize))
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(onPromptTap == nil ? 0.03 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(onPromptTap == nil)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func coachSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: fontSize * 0.95, weight: .semibold))
                .foregroundStyle(.secondary)

            content()
        }
    }

    @ViewBuilder
    private func comparisonBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: fontSize * 0.9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: fontSize))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
