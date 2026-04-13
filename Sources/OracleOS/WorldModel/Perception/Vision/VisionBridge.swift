// VisionBridge.swift - HTTP client to the Python vision sidecar
//
// Oracle OS calls the vision sidecar when the AX tree can't find
// what the agent needs (web apps with generic AXGroup roles, dynamic
// content, etc.).
//
// Architecture:
//   Oracle OS (Swift) --HTTP--> Vision Sidecar (Python) --MLX--> ShowUI-2B
//
// The sidecar runs on localhost:9876. VisionBridge auto-starts it when
// needed via the `oracle-vision` launcher script.
//
// VisionBridge handles:
//   1. Health check (is the sidecar running?)
//   2. VLM grounding (find element coordinates from screenshot + description)
//   3. Sidecar lifecycle management (auto-start, track PID)

import Foundation

/// Bridge between Oracle OS and the Python vision sidecar.
/// All methods are synchronous (blocking) because the MCP server is synchronous.
public enum VisionBridge {
    private struct VisionHTTPPayload {
        let data: Data
        let statusCode: Int
    }

    enum SidecarAvailability: Equatable {
        case ready
        case warming
        case degraded(String)
        case unavailable(VisionRequestFailure)

        var isUsable: Bool {
            switch self {
            case .ready, .warming:
                return true
            case .degraded, .unavailable:
                return false
            }
        }

        var diagnostic: String? {
            switch self {
            case .ready, .warming:
                return nil
            case .degraded(let message):
                return message
            case .unavailable(let failure):
                return failure.description
            }
        }
    }

    enum VisionRequestFailure: Error, Sendable, Equatable, CustomStringConvertible {
        case invalidURL(String)
        case requestEncodingFailed
        case timedOut
        case network(code: Int?, description: String)
        case http(statusCode: Int, message: String?)
        case sidecar(String)
        case decode(type: String, description: String)
        case emptyResponse

        var description: String {
            switch self {
            case .invalidURL(let url):
                return "Invalid vision sidecar URL: \(url)"
            case .requestEncodingFailed:
                return "Failed to encode vision request body"
            case .timedOut:
                return "Vision sidecar request timed out"
            case .network(_, let description):
                return description
            case .http(let statusCode, let message):
                if let message, !message.isEmpty {
                    return "Vision sidecar returned HTTP \(statusCode): \(message)"
                }
                return "Vision sidecar returned HTTP \(statusCode)"
            case .sidecar(let message):
                return message
            case .decode(let type, let description):
                return "Failed to decode \(type) from vision sidecar response: \(description)"
            case .emptyResponse:
                return "Vision sidecar returned no response body"
            }
        }
    }

    /// Default sidecar URL. Can be overridden via ORACLE_VISION_URL env var.
    private static let baseURL: String = {
        if let url = ProcessInfo.processInfo.environment["ORACLE_VISION_URL"] {
            return url
        }
        let port = ProcessInfo.processInfo.environment["ORACLE_VISION_PORT"] ?? "9876"
        return "http://127.0.0.1:\(port)"
    }()

    /// Timeout for health checks (short — just checking if process is alive).
    private static let healthTimeout: TimeInterval = 2.0

    /// Timeout for VLM grounding (model inference can take 3-5s on first call,
    /// then 0.5-3s on subsequent calls with warm model).
    private static let groundTimeout: TimeInterval = 30.0

    /// Timeout for the first grounding call which also loads the model (~10-15s).
    private static let firstGroundTimeout: TimeInterval = 60.0

    /// Sidecar lifecycle state machine.
    public enum SidecarState: Sendable {
        case stopped
        case starting
        case warming
        case ready
        case failed
    }

    /// Thread-safe container for mutable sidecar state.
    private final class SidecarLifecycle: @unchecked Sendable {
        private let lock = NSLock()
        private var _state: SidecarState = .stopped
        private var _process: (any BackgroundProcess)?
        private var _hasCompletedFirstGround = false
        private var _configuredAdapter: (any ProcessAdapter)?

        var state: SidecarState {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _state
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _state = newValue
            }
        }

        var process: (any BackgroundProcess)? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _process
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _process = newValue
            }
        }

        var hasCompletedFirstGround: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _hasCompletedFirstGround
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _hasCompletedFirstGround = newValue
            }
        }

        var configuredAdapter: (any ProcessAdapter)? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _configuredAdapter
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _configuredAdapter = newValue
            }
        }

        /// Atomically transition from an expected state to a new state.
        /// Returns true if the transition was performed.
        @discardableResult
        func transition(from expected: SidecarState, to desired: SidecarState) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard _state == expected else { return false }
            _state = desired
            return true
        }
    }

    private static let lifecycle = SidecarLifecycle()

    /// Called by RuntimeBootstrap to inject the shared process adapter.
    /// If not called before the first startSidecar(), a fresh DefaultProcessAdapter
    /// is used as fallback — this preserves existing behaviour when VisionBridge is
    /// used outside the bootstrapped runtime.
    public static func configure(processAdapter: any ProcessAdapter) {
        lifecycle.configuredAdapter = processAdapter
    }

    // MARK: - Health Check

    /// Check if the vision sidecar is running and responsive.
    public static func isAvailable() -> Bool {
        currentAvailability().isUsable
    }

    /// Get detailed health status from the sidecar.
    public static func healthCheck() -> VisionHealthResponse? {
        try? healthCheckResult().get()
    }

    // MARK: - VLM Grounding

    /// Result from a VLM grounding call.
    public struct GroundResult {
        /// X coordinate in logical screen points.
        public let x: Double
        /// Y coordinate in logical screen points.
        public let y: Double
        /// Confidence (0-1). 0 means coordinates couldn't be parsed.
        public let confidence: Double
        /// Raw model output text.
        public let raw: String
        /// Method used: "full-screen" or "crop-based".
        public let method: String
        /// Inference time in milliseconds.
        public let inferenceMs: Int
    }

    /// Find precise coordinates for a UI element using VLM grounding.
    ///
    /// Auto-starts the vision sidecar if it's not already running.
    ///
    /// - Parameters:
    ///   - imageBase64: Base64-encoded PNG screenshot
    ///   - description: What to find (e.g., "Compose button", "Send button")
    ///   - screenWidth: Logical screen width in points (default 1728)
    ///   - screenHeight: Logical screen height in points (default 1117)
    ///   - cropBox: Optional crop region [x1, y1, x2, y2] in logical points.
    ///              When provided, the sidecar crops the image first, runs VLM
    ///              on the crop, then maps coordinates back to full screen.
    ///              This dramatically improves accuracy for overlapping panels.
    /// - Returns: GroundResult with coordinates, or nil if grounding failed.
    public static func ground(
        imageBase64: String,
        description: String,
        screenWidth: Double = 1728,
        screenHeight: Double = 1117,
        cropBox: [Double]? = nil
    ) -> GroundResult? {
        // Auto-start sidecar if not running
        if !isAvailable() {
            Log.info("Vision sidecar not running, attempting auto-start...")
            if !startSidecar() {
                Log.warn("Vision sidecar auto-start failed")
                return nil
            }
        }

        let req = VisionGroundRequest(
            image: imageBase64,
            description: description,
            screenW: screenWidth,
            screenH: screenHeight,
            cropBox: cropBox
        )

        // Use longer timeout for first call (model needs to load ~10-15s)
        let timeout = lifecycle.hasCompletedFirstGround ? groundTimeout : firstGroundTimeout

        let response: VisionGroundResponse
        switch httpPostTyped(
            path: VisionSidecarEndpoint.ground,
            body: req,
            as: VisionGroundResponse.self,
            timeout: timeout
        ) {
        case .success(let decoded):
            response = decoded
        case .failure(let failure):
            if case .timedOut = failure, lifecycle.hasCompletedFirstGround == false {
                switch currentAvailability() {
                case .warming:
                    Log.warn(
                        "Vision sidecar /ground timed out while the sidecar remained reachable; the model may still be warming"
                    )
                case .degraded(let message):
                    Log.warn(
                        "Vision sidecar /ground timed out while health was degraded: \(message)"
                    )
                case .ready, .unavailable:
                    break
                }
            }
            logRequestFailure(failure, prefix: "Vision sidecar /ground request failed")
            return nil
        }

        lifecycle.hasCompletedFirstGround = true
        return GroundResult(
            x: response.x,
            y: response.y,
            confidence: response.confidence ?? 0,
            raw: response.raw ?? "",
            method: response.method,
            inferenceMs: response.inferenceMs ?? 0
        )
    }

    // MARK: - Element Detection

    /// Detect all interactive elements on screen using YOLO.
    public static func detect(
        imageBase64: String,
        screenWidth: Double = 1728,
        screenHeight: Double = 1117
    ) -> VisionDetectResponse? {
        let req = VisionDetectRequest(
            image: imageBase64, screenW: screenWidth, screenH: screenHeight)
        switch httpPostTyped(
            path: VisionSidecarEndpoint.detect,
            body: req,
            as: VisionDetectResponse.self,
            timeout: groundTimeout
        ) {
        case .success(let response):
            return response
        case .failure(let failure):
            logRequestFailure(failure, prefix: "Vision sidecar /detect request failed")
            return nil
        }
    }

    // MARK: - Screen Parsing

    /// Parse screen into a structured element map.
    public static func parse(
        imageBase64: String,
        screenWidth: Double = 1728,
        screenHeight: Double = 1117
    ) -> VisionParseResponse? {
        let req = VisionParseRequest(
            image: imageBase64, screenW: screenWidth, screenH: screenHeight)
        switch httpPostTyped(
            path: VisionSidecarEndpoint.parse,
            body: req,
            as: VisionParseResponse.self,
            timeout: groundTimeout
        ) {
        case .success(let response):
            return response
        case .failure(let failure):
            logRequestFailure(failure, prefix: "Vision sidecar /parse request failed")
            return nil
        }
    }

    // MARK: - Sidecar Lifecycle

    /// Attempt to start the vision sidecar process.
    /// Looks for `oracle-vision` launcher script, then falls back to running server.py directly.
    /// Uses a state machine to prevent concurrent double-start attempts.
    @discardableResult
    public static func startSidecar() -> Bool {
        // Check if already running or already degraded.
        switch currentAvailability() {
        case .ready:
            lifecycle.state = .ready
            Log.info("Vision sidecar already running and ready")
            return true
        case .warming:
            lifecycle.state = .warming
            Log.info("Vision sidecar already running and warming")
            return true
        case .degraded(let message):
            lifecycle.state = .failed
            Log.warn(message)
            return false
        case .unavailable:
            break
        }

        // Atomically claim the starting transition; if another caller is already
        // starting, wait for that attempt to finish instead of double-starting.
        guard
            lifecycle.transition(from: .stopped, to: .starting)
                || lifecycle.transition(from: .failed, to: .starting)
        else {
            // Another start is in progress — wait for it.
            if lifecycle.state == .starting {
                Log.info("Vision sidecar start already in progress, waiting...")
                let availability = waitForSidecarAvailability()
                lifecycle.state = lifecycleState(for: availability)
                switch availability {
                case .ready, .warming:
                    return true
                case .degraded, .unavailable:
                    return false
                }
            }
            if lifecycle.state == .ready || lifecycle.state == .warming { return true }
            return false
        }

        let adapter: any ProcessAdapter
        if let configured = lifecycle.configuredAdapter {
            adapter = configured
        } else {
            // FALLBACK EXCEPTION: Not configured via RuntimeBootstrap.configure(processAdapter:).
            // Expected in: CLI setup (oracle doctor/setup), standalone test contexts.
            // In MCP/Controller runtime, bootstrap always configures before first startSidecar().
            Log.warn(
                "[VisionBridge] Using local DefaultProcessAdapter — not configured via bootstrap (expected in CLI/test contexts only)"
            )
            adapter = DefaultProcessAdapter()
        }

        // Strategy 1: Use oracle-vision launcher script (handles venv/Python resolution)
        if let launcher = findOracleVisionBinary() {
            Log.info("Starting vision sidecar via \(launcher)")

            do {
                let bgProcess = try adapter.spawnBackground(
                    SystemCommand(executable: launcher, arguments: ["--idle-timeout", "600"]),
                    in: nil
                )
                lifecycle.process = bgProcess
            } catch {
                Log.error("Failed to start vision sidecar via launcher: \(error)")
                lifecycle.state = .failed
                return false
            }

            let availability = waitForSidecarAvailability()
            switch availability {
            case .ready:
                lifecycle.state = .ready
                Log.info(
                    "Vision sidecar started ready (PID \(lifecycle.process?.processIdentifier ?? 0))"
                )
                return true
            case .warming:
                lifecycle.state = .warming
                Log.info(
                    "Vision sidecar started and is still warming (PID \(lifecycle.process?.processIdentifier ?? 0))"
                )
                return true
            case .degraded(let message):
                return failSidecarStart(
                    launchedProcess: lifecycle.process,
                    message: "Vision sidecar launched but reported degraded health: \(message)"
                )
            case .unavailable(let failure):
                return failSidecarStart(
                    launchedProcess: lifecycle.process,
                    message:
                        "Vision sidecar launched but not responding after 10s: \(failure.description)"
                )
            }
        }

        // Strategy 2: Run server.py directly with best available Python
        if let script = findServerScript() {
            Log.info("Starting vision sidecar from \(script)")

            guard let python = findPython() else {
                Log.warn("No Python with mlx_vlm found — cannot start vision sidecar")
                lifecycle.state = .failed
                return false
            }

            do {
                let bgProcess = try adapter.spawnBackground(
                    SystemCommand(
                        executable: python, arguments: [script, "--idle-timeout", "600"]),
                    in: nil
                )
                lifecycle.process = bgProcess
            } catch {
                Log.error("Failed to start vision sidecar: \(error)")
                lifecycle.state = .failed
                return false
            }

            let availability = waitForSidecarAvailability()
            switch availability {
            case .ready:
                lifecycle.state = .ready
                Log.info(
                    "Vision sidecar started ready (PID \(lifecycle.process?.processIdentifier ?? 0))"
                )
                return true
            case .warming:
                lifecycle.state = .warming
                Log.info(
                    "Vision sidecar started and is still warming (PID \(lifecycle.process?.processIdentifier ?? 0))"
                )
                return true
            case .degraded(let message):
                return failSidecarStart(
                    launchedProcess: lifecycle.process,
                    message: "Vision sidecar launched but reported degraded health: \(message)"
                )
            case .unavailable(let failure):
                return failSidecarStart(
                    launchedProcess: lifecycle.process,
                    message:
                        "Vision sidecar launched but not responding after 10s: \(failure.description)"
                )
            }
        }

        return failSidecarStart(message: "Could not find or start vision sidecar")
    }

    @discardableResult
    static func failSidecarStart(
        launchedProcess: (any BackgroundProcess)? = nil,
        message: String
    ) -> Bool {
        let process = launchedProcess ?? lifecycle.process
        process?.terminate()
        if let terminatedPID = process?.processIdentifier,
            lifecycle.process?.processIdentifier == terminatedPID
        {
            lifecycle.process = nil
        } else if process == nil {
            lifecycle.process = nil
        }
        lifecycle.state = .failed
        Log.warn(message)
        return false
    }

    static func waitForSidecarAvailability(
        maxAttempts: Int = 100,
        sleep: (TimeInterval) -> Void = defaultStartupSleep,
        availabilityProbe: () -> SidecarAvailability = defaultAvailabilityProbe
    ) -> SidecarAvailability {
        var lastFailure: VisionRequestFailure = .timedOut
        for _ in 0..<maxAttempts {
            let availability = availabilityProbe()
            switch availability {
            case .ready, .warming, .degraded:
                return availability
            case .unavailable(let failure):
                lastFailure = failure
                sleep(0.1)
            }
        }

        return .unavailable(lastFailure)
    }

    /// Wait for the sidecar to become responsive (up to 10 seconds).
    static func waitForSidecar(
        maxAttempts: Int = 100,
        sleep: (TimeInterval) -> Void = defaultStartupSleep,
        availabilityProbe: () -> SidecarAvailability = defaultAvailabilityProbe
    ) -> Bool {
        switch waitForSidecarAvailability(
            maxAttempts: maxAttempts,
            sleep: sleep,
            availabilityProbe: availabilityProbe
        ) {
        case .ready, .warming:
            return true
        case .degraded(let message):
            Log.warn("Vision sidecar reported degraded health during startup: \(message)")
            return false
        case .unavailable(let failure):
            let timeoutSeconds = Double(maxAttempts) * 0.1
            Log.warn(
                "Vision sidecar started but not responding after \(timeoutSeconds)s: \(failure.description)"
            )
            return false
        }
    }

    static func lifecycleState(for availability: SidecarAvailability) -> SidecarState {
        switch availability {
        case .ready:
            return .ready
        case .warming:
            return .warming
        case .degraded, .unavailable:
            return .failed
        }
    }

    static func assessSidecarAvailability(_ response: VisionHealthResponse) -> SidecarAvailability {
        if let loadError = response.vlmLoadError?.trimmingCharacters(in: .whitespacesAndNewlines),
            !loadError.isEmpty
        {
            return .degraded("Vision sidecar model load failed: \(loadError)")
        }

        if response.modelExists == false {
            return .degraded("Vision sidecar model path not found: \(response.modelPath)")
        }

        switch response.status {
        case "ready":
            return .ready
        case "idle":
            return .warming
        default:
            return .degraded(
                "Vision sidecar reported unexpected health status '\(response.status)'")
        }
    }

    static func currentAvailability() -> SidecarAvailability {
        switch healthCheckResult() {
        case .success(let response):
            return assessSidecarAvailability(response)
        case .failure(let failure):
            return .unavailable(failure)
        }
    }

    static func availabilityDiagnostic() -> String? {
        currentAvailability().diagnostic
    }

    private static func defaultStartupSleep(_ interval: TimeInterval) {
        Thread.sleep(forTimeInterval: interval)
    }

    private static func defaultAvailabilityProbe() -> SidecarAvailability {
        currentAvailability()
    }

    /// Find the oracle-vision launcher script/binary.
    private static func findOracleVisionBinary() -> String? {
        let executableDirectory = (ProcessInfo.processInfo.arguments[0] as NSString)
            .deletingLastPathComponent
        let candidates: [String] = [
            OracleProductPaths.visionInstallDirectory.appendingPathComponent(
                "oracle-vision", isDirectory: false
            ).path,
            OracleProductPaths.bundledVisionBootstrapDirectory?.appendingPathComponent(
                "oracle-vision", isDirectory: false
            ).path,
            "/opt/homebrew/bin/oracle-vision",
            "/usr/local/bin/oracle-vision",
            executableDirectory + "/oracle-vision",
            executableDirectory + "/../vision-sidecar/oracle-vision",
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Find the server.py script in expected locations.
    private static func findServerScript() -> String? {
        let executableDirectory = (ProcessInfo.processInfo.arguments[0] as NSString)
            .deletingLastPathComponent
        let bundledVisionDirectory = OracleProductPaths.bundledVisionBootstrapDirectory
        let candidates: [String] = [
            OracleProductPaths.visionInstallDirectory.appendingPathComponent(
                "server.py", isDirectory: false
            ).path,
            bundledVisionDirectory?.appendingPathComponent("server.py", isDirectory: false).path,
            "/opt/homebrew/share/oracle-os/vision-sidecar/server.py",
            "/usr/local/share/oracle-os/vision-sidecar/server.py",
            executableDirectory + "/vision-sidecar/server.py",
            (executableDirectory as NSString).deletingLastPathComponent
                + "/vision-sidecar/server.py",
            ((executableDirectory as NSString).deletingLastPathComponent as NSString)
                .deletingLastPathComponent + "/vision-sidecar/server.py",
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Find the best Python executable with mlx_vlm available.
    /// Returns nil if no suitable Python is found.
    private static func findPython() -> String? {
        // Check venv first (most likely to have mlx_vlm)
        let candidates = [
            OracleProductPaths.visionInstallDirectory
                .appendingPathComponent(".venv/bin/python3", isDirectory: false)
                .path,
            NSHomeDirectory() + "/.oracle-os/venv/bin/python3",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        // Homebrew Python
        for path in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    // MARK: - Model Path Resolution

    /// Check if the ShowUI-2B model exists at any known location.
    /// Returns the path if found, nil otherwise.
    public static func findModelPath() -> String? {
        let candidates = [
            OracleProductPaths.visionModelDirectory.path,
            "/opt/homebrew/share/oracle-os/models/ShowUI-2B",
            NSHomeDirectory() + "/.oracle-os/models/ShowUI-2B",
            NSHomeDirectory() + "/.oracle-os/models/llm/ShowUI-2B-bf16-8bit",
        ]

        for path in candidates {
            let safetensors = (path as NSString).appendingPathComponent("model.safetensors")
            let config = (path as NSString).appendingPathComponent("config.json")
            if FileManager.default.fileExists(atPath: safetensors)
                && FileManager.default.fileExists(atPath: config)
            {
                return path
            }
        }
        return nil
    }

    // MARK: - HTTP Helpers

    private static func healthCheckResult() -> Result<VisionHealthResponse, VisionRequestFailure> {
        httpGetTyped(
            path: VisionSidecarEndpoint.health, as: VisionHealthResponse.self,
            timeout: healthTimeout)
    }

    /// Synchronous HTTP GET, decoded into a typed Decodable response.
    private static func httpGetTyped<R: Decodable>(
        path: String, as type: R.Type, timeout: TimeInterval
    ) -> Result<R, VisionRequestFailure> {
        guard let url = URL(string: baseURL + path) else {
            return .failure(.invalidURL(baseURL + path))
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        switch performRawRequest(request) {
        case .success(let payload):
            return decodeTypedResponse(payload, as: type)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    /// Synchronous HTTP POST with a typed Encodable body, decoded into a typed Decodable response.
    private static func httpPostTyped<B: Encodable, R: Decodable>(
        path: String,
        body: B,
        as type: R.Type,
        timeout: TimeInterval
    ) -> Result<R, VisionRequestFailure> {
        guard let url = URL(string: baseURL + path) else {
            return .failure(.invalidURL(baseURL + path))
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return .failure(.requestEncodingFailed)
        }
        request.httpBody = jsonData
        switch performRawRequest(request) {
        case .success(let payload):
            return decodeTypedResponse(payload, as: type)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    /// Perform a synchronous URLSession request. Blocks the calling thread
    /// using a semaphore (acceptable since MCP server is single-threaded).
    /// Returns the raw response payload on success.
    private static func performRawRequest(_ request: URLRequest) -> Result<
        VisionHTTPPayload, VisionRequestFailure
    > {
        let semaphore = DispatchSemaphore(value: 0)

        // Use nonisolated Sendable box to shuttle data across the closure boundary.
        // The class must be nonisolated to escape @MainActor default isolation,
        // since the URLSession completion handler runs on a background thread.
        nonisolated final class ResponseBox: @unchecked Sendable {
            var data: Data?
            var error: (any Error)?
            var response: URLResponse?
        }
        let box = ResponseBox()

        // Use a detached session to avoid MainActor issues
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { data, response, error in
            box.data = data
            box.error = error
            box.response = response
            semaphore.signal()
        }
        task.resume()

        // Bounded wait: use the URLRequest's own timeout + 5s grace period.
        // This prevents indefinite blocking when called from @MainActor context
        // (e.g. ObservationBuilder → VisionScanner → VisionBridge).
        let deadline = DispatchTime.now() + request.timeoutInterval + 5.0
        let waitResult = semaphore.wait(timeout: deadline)
        if waitResult == .timedOut {
            task.cancel()
            return .failure(.timedOut)
        }

        if let error = box.error {
            let nsError = error as NSError
            return .failure(.network(code: nsError.code, description: error.localizedDescription))
        }

        guard let response = box.response as? HTTPURLResponse,
            let data = box.data
        else {
            return .failure(.emptyResponse)
        }

        return .success(VisionHTTPPayload(data: data, statusCode: response.statusCode))
    }

    static func extractErrorMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var parts: [String] = []
            if let error = object["error"] as? String, !error.isEmpty {
                parts.append(error)
            }
            if let detail = object["detail"] as? String, !detail.isEmpty {
                parts.append(detail)
            }
            if let suggestion = object["suggestion"] as? String, !suggestion.isEmpty {
                parts.append("Suggestion: \(suggestion)")
            }
            if !parts.isEmpty {
                return parts.joined(separator: " | ")
            }
        }

        guard
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }
        return raw
    }

    private static func decodeTypedResponse<R: Decodable>(
        _ payload: VisionHTTPPayload,
        as type: R.Type
    ) -> Result<R, VisionRequestFailure> {
        if payload.statusCode >= 400 {
            return .failure(
                .http(
                    statusCode: payload.statusCode, message: extractErrorMessage(from: payload.data)
                ))
        }

        do {
            let decoded = try JSONDecoder().decode(R.self, from: payload.data)
            if let errorCarrier = decoded as? any VisionSidecarErrorCarrier,
                let error = errorCarrier.error?.trimmingCharacters(in: .whitespacesAndNewlines),
                !error.isEmpty
            {
                return .failure(.sidecar(error))
            }
            return .success(decoded)
        } catch {
            return .failure(
                .decode(type: String(describing: R.self), description: error.localizedDescription))
        }
    }

    private static func logRequestFailure(
        _ failure: VisionRequestFailure,
        prefix: String
    ) {
        switch failure {
        case .network(let code, _)
        where code == NSURLErrorCannotConnectToHost
            || code == NSURLErrorTimedOut
            || code == NSURLErrorNetworkConnectionLost:
            Log.debug("\(prefix): \(failure.description)")
        case .network(let code, _) where code == NSURLErrorNotConnectedToInternet:
            Log.debug("\(prefix): \(failure.description)")
        case .timedOut:
            Log.warn("\(prefix): \(failure.description)")
        default:
            Log.warn("\(prefix): \(failure.description)")
        }
    }
}
