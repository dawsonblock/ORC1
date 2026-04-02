import Foundation

actor Coordinator {
    var state: Int = 0
    enum TState { case none, run(Task<Int, Error>) }
    var ts: TState = .none

    func doIt() async throws -> Int {
        if case .run(let task) = ts { return try await task.value }
        let task = Task { () -> Int in 
            self.state = 1
            try await Task.sleep(nanoseconds: 1000)
            return self.state
        }
        ts = .run(task)
        let res = try await task.value
        ts = .none
        return res
    }
}
