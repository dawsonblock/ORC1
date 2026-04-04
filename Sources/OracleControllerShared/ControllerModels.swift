import Foundation

public struct ControllerSession: Codable, Sendable, Equatable {
    public let id: String
    public let startedAt: Date
    public let hostProcessID: Int32
    public let activeAppName: String?
    public let autoRefreshEnabled: Bool

    public init(
        id: String,
        startedAt: Date,
        hostProcessID: Int32,
        activeAppName: String? = nil,
        autoRefreshEnabled: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.hostProcessID = hostProcessID
        self.activeAppName = activeAppName
        self.autoRefreshEnabled = autoRefreshEnabled
    }
}

public struct ElementFrameSnapshot: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ElementSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let source: String
    public let role: String?
    public let label: String?
    public let value: String?
    public let frame: ElementFrameSnapshot?
    public let enabled: Bool
    public let visible: Bool
    public let focused: Bool
    public let confidence: Double

    public init(
        id: String,
        source: String,
        role: String? = nil,
        label: String? = nil,
        value: String? = nil,
        frame: ElementFrameSnapshot? = nil,
        enabled: Bool = true,
        visible: Bool = true,
        focused: Bool = false,
        confidence: Double = 1
    ) {
        self.id = id
        self.source = source
        self.role = role
        self.label = label
        self.value = value
        self.frame = frame
        self.enabled = enabled
        self.visible = visible
        self.focused = focused
        self.confidence = confidence
    }
}

public struct ObservationSnapshot: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let appName: String?
    public let windowTitle: String?
    public let url: String?
    public let focusedElementID: String?
    public let elements: [ElementSnapshot]

    public init(
        timestamp: Date,
        appName: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        focusedElementID: String? = nil,
        elements: [ElementSnapshot] = []
    ) {
        self.timestamp = timestamp
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.focusedElementID = focusedElementID
        self.elements = elements
    }
}

public struct ScreenshotFrame: Codable, Sendable, Equatable {
    public let base64PNG: String
    public let width: Int
    public let height: Int
    public let windowTitle: String?
    public let capturedAt: Date

    public init(
        base64PNG: String,
        width: Int,
        height: Int,
        windowTitle: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.base64PNG = base64PNG
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
        self.capturedAt = capturedAt
    }
}

public struct ControlSnapshot: Codable, Sendable, Equatable {
    public let capturedAt: Date
    public let observation: ObservationSnapshot
    public let screenshot: ScreenshotFrame?

    public init(capturedAt: Date = Date(), observation: ObservationSnapshot, screenshot: ScreenshotFrame? = nil) {
        self.capturedAt = capturedAt
        self.observation = observation
        self.screenshot = screenshot
    }
}

public enum ActionKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case focus
    case click
    case type
    case press
    case scroll
    case wait

    public var id: String { rawValue }
}

public enum ActionRunDisposition: String, Sendable, Equatable {
    case awaitingApproval
    case rejected
    case blockedByPolicy
    case verifiedExecution
    case observed
    case partialSuccess
    case failed
}

public struct ActionRequest: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: ActionKind
    public let appName: String?
    public let windowTitle: String?
    public let query: String?
    public let role: String?
    public let domID: String?
    public let text: String?
    public let clearExisting: Bool
    public let x: Double?
    public let y: Double?
    public let button: String?
    public let count: Int?
    public let key: String?
    public let modifiers: [String]?
    public let direction: String?
    public let amount: Int?
    public let waitCondition: String?
    public let waitValue: String?
    public let timeout: Double?
    public let interval: Double?
    public let approvalRequestID: String?

    public init(
        id: UUID = UUID(),
        kind: ActionKind,
        appName: String? = nil,
        windowTitle: String? = nil,
        query: String? = nil,
        role: String? = nil,
        domID: String? = nil,
        text: String? = nil,
        clearExisting: Bool = false,
        x: Double? = nil,
        y: Double? = nil,
        button: String? = nil,
        count: Int? = nil,
        key: String? = nil,
        modifiers: [String]? = nil,
        direction: String? = nil,
        amount: Int? = nil,
        waitCondition: String? = nil,
        waitValue: String? = nil,
        timeout: Double? = nil,
        interval: Double? = nil,
        approvalRequestID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.appName = appName
        self.windowTitle = windowTitle
        self.query = query
        self.role = role
        self.domID = domID
        self.text = text
        self.clearExisting = clearExisting
        self.x = x
        self.y = y
        self.button = button
        self.count = count
        self.key = key
        self.modifiers = modifiers
        self.direction = direction
        self.amount = amount
        self.waitCondition = waitCondition
        self.waitValue = waitValue
        self.timeout = timeout
        self.interval = interval
        self.approvalRequestID = approvalRequestID
    }

    public var displayTitle: String {
        switch kind {
        case .focus:
            return "Focus \(appName ?? "App")"
        case .click:
            return "Click \(query ?? domID ?? coordinateLabel)"
        case .type:
            return "Type into \(query ?? domID ?? "Focused Field")"
        case .press:
            return "Press \(key ?? "Key")"
        case .scroll:
            return "Scroll \(direction ?? "down")"
        case .wait:
            return "Wait for \(waitCondition ?? "Condition")"
        }
    }

    public var requiresConfirmation: Bool {
        let riskyTerms = [query, domID, text, key, waitValue]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return riskyTerms.contains("delete")
            || riskyTerms.contains("trash")
            || riskyTerms.contains("submit")
            || riskyTerms.contains("send")
            || riskyTerms.contains("purchase")
            || riskyTerms.contains("password")
    }

    private var coordinateLabel: String {
        if let x, let y {
            return "(\(Int(x)), \(Int(y)))"
        }
        return "Target"
    }
}

public struct ActionRunResult: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let request: ActionRequest
    public let success: Bool
    public let verified: Bool
    public let message: String?
    public let failureClass: String?
    public let verificationStatus: String?
    public let method: String?
    public let elapsedMs: Double
    public let resultingObservation: ObservationSnapshot?
    public let approvalRequestID: String?
    public let approvalStatus: String?
    public let protectedOperation: String?
    public let appProtectionProfile: String?
    public let blockedByPolicy: Bool
    public let executedThroughExecutor: Bool
    public let policyMode: String?
    public let commandCategory: String?
    public let commandSummary: String?
    public let workspaceRelativePath: String?
    public let buildResultSummary: String?
    public let testResultSummary: String?
    public let patchID: String?

    public init(
        id: UUID = UUID(),
        request: ActionRequest,
        success: Bool,
        verified: Bool,
        message: String? = nil,
        failureClass: String? = nil,
        verificationStatus: String? = nil,
        method: String? = nil,
        elapsedMs: Double,
        resultingObservation: ObservationSnapshot? = nil,
        approvalRequestID: String? = nil,
        approvalStatus: String? = nil,
        protectedOperation: String? = nil,
        appProtectionProfile: String? = nil,
        blockedByPolicy: Bool = false,
        executedThroughExecutor: Bool = false,
        policyMode: String? = nil,
        commandCategory: String? = nil,
        commandSummary: String? = nil,
        workspaceRelativePath: String? = nil,
        buildResultSummary: String? = nil,
        testResultSummary: String? = nil,
        patchID: String? = nil
    ) {
        self.id = id
        self.request = request
        self.success = success
        self.verified = verified
        self.message = message
        self.failureClass = failureClass
        self.verificationStatus = verificationStatus
        self.method = method
        self.elapsedMs = elapsedMs
        self.resultingObservation = resultingObservation
        self.approvalRequestID = approvalRequestID
        self.approvalStatus = approvalStatus
        self.protectedOperation = protectedOperation
        self.appProtectionProfile = appProtectionProfile
        self.blockedByPolicy = blockedByPolicy
        self.executedThroughExecutor = executedThroughExecutor
        self.policyMode = policyMode
        self.commandCategory = commandCategory
        self.commandSummary = commandSummary
        self.workspaceRelativePath = workspaceRelativePath
        self.buildResultSummary = buildResultSummary
        self.testResultSummary = testResultSummary
        self.patchID = patchID
    }

    public var isApprovalPending: Bool {
        approvalStatus == "pending"
    }

    public var disposition: ActionRunDisposition {
        if isApprovalPending {
            return .awaitingApproval
        }
        if approvalStatus == "rejected" || failureClass == "approval_rejected" {
            return .rejected
        }
        if blockedByPolicy {
            return .blockedByPolicy
        }
        if failureClass == "partial_success" {
            return .partialSuccess
        }
        if executedThroughExecutor {
            return verified ? .verifiedExecution : (success ? .partialSuccess : .failed)
        }
        return success ? .observed : .failed
    }

    public var statusLabel: String {
        switch disposition {
        case .awaitingApproval:
            return "Awaiting Approval"
        case .rejected:
            return "Rejected"
        case .blockedByPolicy:
            return "Blocked"
        case .verifiedExecution:
            return "Verified"
        case .observed:
            return "Observed"
        case .partialSuccess:
            return "Partial"
        case .failed:
            return "Failed"
        }
    }

    public var executionPathSummary: String {
        switch disposition {
        case .awaitingApproval:
            return "Awaiting approval before runtime execution"
        case .rejected:
            return "Approval rejected before runtime execution"
        case .blockedByPolicy:
            return "Blocked before execution by policy"
        case .verifiedExecution:
            return "Executed through the verified runtime path"
        case .observed:
            return request.kind == .wait
                ? "Observed wait condition in the host bridge"
                : "Completed outside the verified runtime path"
        case .partialSuccess:
            return "Executed through the verified runtime path with a partial outcome"
        case .failed:
            return executedThroughExecutor
                ? "Failed after entering the verified runtime path"
                : "Did not enter the verified runtime path"
        }
    }

    public var summaryText: String {
        switch disposition {
        case .awaitingApproval:
            return "Action awaiting approval before runtime execution."
        case .rejected:
            return message ?? "Action approval was rejected."
        case .blockedByPolicy:
            return "Action blocked by policy before execution."
        case .observed:
            return message ?? (request.kind == .wait ? "Condition evaluated." : "Action completed.")
        case .partialSuccess:
            return message ?? "Action completed with a partial outcome."
        case .verifiedExecution:
            return message ?? "Action completed through the verified runtime path."
        case .failed:
            return message ?? "Action failed."
        }
    }

    public func rejectedApprovalResult(message: String = "Action approval was rejected.") -> ActionRunResult {
        ActionRunResult(
            id: id,
            request: request,
            success: false,
            verified: false,
            message: message,
            failureClass: "approval_rejected",
            verificationStatus: verificationStatus,
            method: method,
            elapsedMs: elapsedMs,
            resultingObservation: resultingObservation,
            approvalRequestID: approvalRequestID,
            approvalStatus: "rejected",
            protectedOperation: protectedOperation,
            appProtectionProfile: appProtectionProfile,
            blockedByPolicy: false,
            executedThroughExecutor: false,
            policyMode: policyMode,
            commandCategory: commandCategory,
            commandSummary: commandSummary,
            workspaceRelativePath: workspaceRelativePath,
            buildResultSummary: buildResultSummary,
            testResultSummary: testResultSummary,
            patchID: patchID
        )
    }
}

public struct ApprovalRequestDocument: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let createdAt: Date
    public let surface: String
    public let toolName: String?
    public let appName: String?
    public let displayTitle: String
    public let reason: String
    public let riskLevel: String
    public let protectedOperation: String
    public let status: String
    public let appProtectionProfile: String

    public init(
        id: String,
        createdAt: Date,
        surface: String,
        toolName: String? = nil,
        appName: String? = nil,
        displayTitle: String,
        reason: String,
        riskLevel: String,
        protectedOperation: String,
        status: String,
        appProtectionProfile: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.surface = surface
        self.toolName = toolName
        self.appName = appName
        self.displayTitle = displayTitle
        self.reason = reason
        self.riskLevel = riskLevel
        self.protectedOperation = protectedOperation
        self.status = status
        self.appProtectionProfile = appProtectionProfile
    }
}