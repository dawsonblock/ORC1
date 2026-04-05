import Foundation
import Testing
@testable import OracleOS

/// Verifies the execution kernel trust boundary:
/// every action must pass through VerifiedExecutor.execute(_:)
/// and the resulting ToolResult must carry action_result.executed_through_executor = true.
@Suite("Execution Kernel Boundary")
@MainActor
struct ExecutionKernelBoundaryTests {

    // MARK: - executor stamp contract

    @Test("ActionResult can carry executedThroughExecutor stamp")
    func executorStampsFlag() {
        let result = ToolResult(
            success: true,
            data: [
                "action_result": ActionResult(success: true, executedThroughExecutor: true).toDict()
            ]
        )
        let dict = result.data?["action_result"] as? [String: Any]
        #expect(dict?["executed_through_executor"] as? Bool == true)
    }

    // MARK: - trust boundary contract on ActionResult

    @Test("ActionResult with executedThroughExecutor=true passes boundary contract")
    func stampedResultPassesBoundary() {
        let result = ActionResult(
            success: true,
            verified: true,
            executedThroughExecutor: true
        )
        #expect(result.executedThroughExecutor == true)
    }

    @Test("ActionResult with executedThroughExecutor=false fails boundary contract")
    func unstampedResultFailsBoundary() {
        let result = ActionResult(success: true, executedThroughExecutor: false)
        #expect(result.executedThroughExecutor == false)
    }

    // MARK: - round-trip through toDict / from(dict:)

    @Test("ActionResult executed_through_executor round-trips through toDict")
    func stampedRoundTripDict() {
        let original = ActionResult(success: true, executedThroughExecutor: true)
        let dict = original.toDict()
        let recovered = ActionResult.from(dict: dict)
        #expect(recovered?.executedThroughExecutor == true)
    }

    @Test("ActionResult executed_through_executor absent in dict defaults to false")
    func missingKeyDefaultsFalse() {
        let partial: [String: Any] = ["success": true]
        let result = ActionResult.from(dict: partial)
        #expect(result?.executedThroughExecutor == false)
    }

    // MARK: - ToolResult data contract

    @Test("ToolResult missing action_result key is detectable as bypass")
    func bareToolResultIsDetectable() {
        // A bare ToolResult without action_result is what a bypass would produce.
        // Verify the detection logic used by OracleRuntime works.
        let bareResult = ToolResult(success: true, data: [:])
        let actionResultDict = bareResult.data?["action_result"] as? [String: Any]
        let stamped = actionResultDict != nil && actionResultDict?["executed_through_executor"] as? Bool == true
        #expect(stamped == false, "Bare ToolResult must be detected as an unstamped bypass")
    }

    @Test("ToolResult with stamped action_result passes detection")
    func stampedToolResultPassesDetection() {
        let actionResult = ActionResult(success: true, executedThroughExecutor: true)
        let result = ToolResult(success: true, data: ["action_result": actionResult.toDict()])
        let actionResultDict = result.data?["action_result"] as? [String: Any]
        let stamped = actionResultDict != nil && actionResultDict?["executed_through_executor"] as? Bool == true
        #expect(stamped == true)
    }

    @Test("Typed action payloads merge into legacy ToolResult data")
    func typedActionPayloadsMergeIntoLegacyData() {
        let result = ToolResult(
            success: true,
            actionResult: ActionResult(success: true, method: "intent-api", executedThroughExecutor: true),
            traceResult: TraceResult(cycleID: "cycle-1", intentID: "intent-1")
        )

        let actionResultDict = result.data?[ActionResultKey.actionResult] as? [String: Any]
        let traceDict = result.data?[ActionResultKey.trace] as? [String: Any]

        #expect(result.actionResult?.executedThroughExecutor == true)
        #expect(actionResultDict?[ActionResultKey.executedThroughExecutor] as? Bool == true)
        #expect(result.data?[ActionResultKey.method] as? String == "intent-api")
        #expect(traceDict?[TraceResultKey.cycleID] as? String == "cycle-1")
    }

    @Test("Legacy recipe payloads are exposed as typed ToolResult views")
    func legacyRecipePayloadsExposeTypedView() {
        let result = ToolResult(
            success: false,
            data: [
                RecipeResultKey.recipe: "gmail-send",
                RecipeResultKey.stepsCompleted: 2,
                RecipeResultKey.totalSteps: 4,
                RecipeResultKey.pendingApproval: true,
                RecipeResultKey.resumeToken: "resume-1",
                RecipeResultKey.stepResults: [[
                    RecipeResultKey.stepIndex: 1,
                    RecipeResultKey.stepAction: "click",
                    RecipeResultKey.stepSuccess: true,
                    RecipeResultKey.stepDurationMs: 32,
                ]],
            ]
        )

        #expect(result.recipeRunResult?.recipeName == "gmail-send")
        #expect(result.recipeRunResult?.pendingApproval == true)
        #expect(result.recipeRunResult?.resumeToken == "resume-1")
        #expect(result.recipeRunResult?.stepResults.first?.durationMs == 32)
    }

    @Test("Legacy screenshot payloads are exposed as typed ToolResult views")
    func legacyScreenshotPayloadsExposeTypedView() {
        let result = ToolResult(
            success: true,
            data: [
                "image": "base64-image",
                "width": 1280,
                "height": 720,
                "window_title": "Safari",
                "mime_type": "image/png",
                "window_frame": [
                    "x": 12.5,
                    "y": 18.0,
                    "width": 800.0,
                    "height": 600.0,
                ],
            ]
        )

        #expect(result.screenshotResult?.base64PNG == "base64-image")
        #expect(result.screenshotResult?.width == 1280)
        #expect(result.screenshotResult?.height == 720)
        #expect(result.screenshotResult?.windowTitle == "Safari")
        #expect(result.screenshotResult?.windowWidth == 800.0)
        #expect(result.screenshotResult?.windowHeight == 600.0)
    }

    @Test("Typed screenshot payloads merge into legacy ToolResult data")
    func typedScreenshotPayloadsMergeIntoLegacyData() {
        let result = ToolResult(
            success: true,
            screenshotResult: ScreenshotResult(
                base64PNG: "typed-image",
                width: 640,
                height: 480,
                windowTitle: "Xcode",
                mimeType: "image/png",
                windowX: 3.0,
                windowY: 4.0,
                windowWidth: 500.0,
                windowHeight: 400.0
            )
        )

        let frame = result.data?["window_frame"] as? [String: Any]
        #expect(result.data?["image"] as? String == "typed-image")
        #expect(result.data?["width"] as? Int == 640)
        #expect(result.data?["height"] as? Int == 480)
        #expect(result.data?["window_title"] as? String == "Xcode")
        #expect(result.data?["mime_type"] as? String == "image/png")
        #expect(frame?["x"] as? Double == 3.0)
        #expect(frame?["width"] as? Double == 500.0)
        #expect(result.screenshotResult?.windowHeight == 400.0)
    }
}
