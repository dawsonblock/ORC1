import Testing

enum MyError: Error { case foo }

struct Runner {
    func run() async throws {
        throw MyError.foo
    }
}

@Test func testAsyncExpect() async {
    let runner = Runner()
    await #expect(throws: MyError.foo) {
        try await runner.run()
    }
}
