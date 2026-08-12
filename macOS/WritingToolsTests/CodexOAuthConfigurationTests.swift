import Foundation
import XCTest
@testable import WritingTools

final class CodexOAuthConfigurationTests: XCTestCase {
    func testCatalogIsGroupedInCurrentPickerOrder() {
        XCTAssertEqual(
            CodexOAuthModel.models(in: .recommended),
            [.gpt56Sol, .gpt56Terra, .gpt56Luna]
        )
        XCTAssertEqual(
            CodexOAuthModel.models(in: .preview),
            [.gpt53CodexSpark]
        )
        XCTAssertEqual(
            CodexOAuthModel.models(in: .older),
            [.gpt55, .gpt54, .gpt54Mini]
        )
    }

    func testLegacyGPT54SelectionsUseDocumentedMigrationTargets() {
        let flagship = CodexOAuthModel.migrateLegacyModel("gpt-5.4")
        XCTAssertEqual(flagship.model, .gpt56Terra)
        XCTAssertNotNil(flagship.notice)

        let mini = CodexOAuthModel.migrateLegacyModel("gpt-5.4-mini")
        XCTAssertEqual(mini.model, .gpt56Luna)
        XCTAssertNotNil(mini.notice)
    }

    func testExplicitOlderModelSelectionRemainsAvailable() {
        let resolution = CodexOAuthModel.resolveSavedModel("gpt-5.4")

        XCTAssertEqual(resolution.model, .gpt54)
        XCTAssertNil(resolution.notice)
    }

    func testUnavailableLegacyModelFallsBackToSol() {
        let resolution = CodexOAuthModel.migrateLegacyModel("gpt-5.2-codex")

        XCTAssertEqual(resolution.model, .gpt56Sol)
        XCTAssertNotNil(resolution.notice)
    }

    func testReasoningEffortIsClampedToModelCapabilities() {
        XCTAssertEqual(
            CodexReasoningEffort.max.normalized(for: .gpt56Sol),
            .max
        )
        XCTAssertEqual(
            CodexReasoningEffort.max.normalized(for: .gpt55),
            .xhigh
        )
        XCTAssertEqual(
            CodexReasoningEffort.max.normalized(for: .gpt53CodexSpark),
            .xhigh
        )
    }

    func testOAuthRequestBodyIncludesModelReasoningAndInstructions() throws {
        let body = try CodexOAuthRequestBuilder.makeBody(
            modelID: CodexOAuthModel.gpt56Terra.rawValue,
            reasoningEffort: .high,
            systemPrompt: "Rewrite clearly.",
            userPrompt: "Draft",
            images: []
        )

        XCTAssertEqual(body["model"] as? String, "gpt-5.6-terra")
        XCTAssertEqual(body["instructions"] as? String, "Rewrite clearly.")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["store"] as? Bool, false)

        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: String])
        XCTAssertEqual(reasoning["effort"], "high")

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let firstInput = try XCTUnwrap(input.first)
        XCTAssertEqual(firstInput["role"] as? String, "user")

        let content = try XCTUnwrap(firstInput["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "input_text")
        XCTAssertEqual(content.first?["text"] as? String, "Draft")
    }

    func testSparkRejectsImageInputBeforeNetworkRequest() {
        XCTAssertThrowsError(
            try CodexOAuthRequestBuilder.makeBody(
                modelID: CodexOAuthModel.gpt53CodexSpark.rawValue,
                reasoningEffort: .high,
                systemPrompt: nil,
                userPrompt: "Describe this image",
                images: [Data([0x01])]
            )
        ) { error in
            guard case CodexOAuthRequestError.imagesNotSupported = error else {
                return XCTFail("Expected imagesNotSupported, got \(error)")
            }
        }
    }
}
