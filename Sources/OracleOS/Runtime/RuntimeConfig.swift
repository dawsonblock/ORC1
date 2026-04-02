import Foundation

public struct RuntimeConfig: Sendable {
    public let policyMode: PolicyMode
    public let approvalRequiredSurfaces: Set<RuntimeSurface>
    public let blockedApplications: [String]
    public let protectedOperations: Set<ProtectedOperation>
    public let traceDirectory: URL
    public let recipesDirectory: URL
    public let controllerApprovalRequiredForRiskyActions: Bool
    public let approvalsDirectory: URL
    public let projectMemoryDirectory: URL
    public let experimentsDirectory: URL

    public init(
        policyMode: PolicyMode,
        approvalRequiredSurfaces: Set<RuntimeSurface>,
        blockedApplications: [String],
        protectedOperations: Set<ProtectedOperation>,
        traceDirectory: URL,
        recipesDirectory: URL,
        controllerApprovalRequiredForRiskyActions: Bool,
        approvalsDirectory: URL,
        projectMemoryDirectory: URL,
        experimentsDirectory: URL
    ) {
        self.policyMode = policyMode
        self.approvalRequiredSurfaces = approvalRequiredSurfaces
        self.blockedApplications = blockedApplications
        self.protectedOperations = protectedOperations
        self.traceDirectory = traceDirectory
        self.recipesDirectory = recipesDirectory
        self.controllerApprovalRequiredForRiskyActions = controllerApprovalRequiredForRiskyActions
        self.approvalsDirectory = approvalsDirectory
        self.projectMemoryDirectory = projectMemoryDirectory
        self.experimentsDirectory = experimentsDirectory
    }

    public static func live(policyMode: PolicyMode? = nil) -> RuntimeConfig {
        try? OracleProductPaths.ensureUserDirectories()

        return RuntimeConfig(
            policyMode: policyMode ?? PolicyEngine.defaultMode(),
            approvalRequiredSurfaces: [.controller, .mcp, .cli, .recipe],
            blockedApplications: ["Terminal", "iTerm", "Hyper", "System Settings", "Keychain Access"],
            protectedOperations: Set(ProtectedOperation.allCases),
            traceDirectory: ExperienceStore.traceRootDirectory(),
            recipesDirectory: OracleProductPaths.recipesDirectory,
            controllerApprovalRequiredForRiskyActions: true,
            approvalsDirectory: OracleProductPaths.approvalsDirectory,
            projectMemoryDirectory: OracleProductPaths.projectMemoryDirectory,
            experimentsDirectory: OracleProductPaths.experimentsDirectory
        )
    }

    /// Test configuration with in-memory/temp paths suitable for unit tests.
    public static func test() -> RuntimeConfig {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return RuntimeConfig(
            policyMode: .open,
            approvalRequiredSurfaces: [],
            blockedApplications: [],
            protectedOperations: [],
            traceDirectory: tempDir.appendingPathComponent("traces"),
            recipesDirectory: tempDir.appendingPathComponent("recipes"),
            controllerApprovalRequiredForRiskyActions: false,
            approvalsDirectory: tempDir.appendingPathComponent("approvals"),
            projectMemoryDirectory: tempDir.appendingPathComponent("memory"),
            experimentsDirectory: tempDir.appendingPathComponent("experiments")
        )
    }
}
