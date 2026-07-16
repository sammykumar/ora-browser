@testable import Evo
import Foundation
import os
import Testing

struct HarnessTimeoutTests {
    private struct BoomError: Error, Equatable {}

    /// Structured-concurrency task groups can't return until every child task finishes, even after
    /// `cancelAll()` — cancellation is only a cooperative flag, and an operation parked in
    /// `withCheckedContinuation` never observes it. So the broken implementation doesn't just return
    /// late — it can hang the test runner forever. Race the real call against our own detached timer
    /// so this test fails fast (instead of hanging) when `harnessTimeout` regresses.
    private func withTestCeiling<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            func claimFirstResume() -> Bool {
                resumed.withLock { alreadyResumed -> Bool in
                    if alreadyResumed {
                        return false
                    }
                    alreadyResumed = true
                    return true
                }
            }
            Task {
                do {
                    let value = try await operation()
                    if claimFirstResume() {
                        continuation.resume(returning: value)
                    }
                } catch {
                    if claimFirstResume() {
                        continuation.resume(throwing: error)
                    }
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if claimFirstResume() {
                    continuation.resume(throwing: CeilingExceeded())
                }
            }
        }
    }

    private struct CeilingExceeded: Error {}

    @Test func timeoutFiresWhenOperationHangs() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        do {
            _ = try await withTestCeiling(seconds: 3) {
                try await DebugHarnessRouter.harnessTimeout(seconds: 0.3) {
                    await withCheckedContinuation { (_: CheckedContinuation<Int, Never>) in
                        // never resumes — simulates a hung WKWebView evaluateJavaScript callback
                    }
                }
            }
            Issue.record("expected HarnessError.timeout to be thrown")
        } catch is DebugHarnessRouter.HarnessError {
            let elapsed = clock.now - start
            #expect(elapsed < .seconds(2))
        } catch is CeilingExceeded {
            Issue.record("harnessTimeout did not return within the 3s test ceiling (hung past the 0.3s timeout)")
        } catch {
            Issue.record("expected HarnessError.timeout, got \(error)")
        }
    }

    @Test func valueWinsWhenFastEnough() async throws {
        let result = try await DebugHarnessRouter.harnessTimeout(seconds: 5) {
            try await Task.sleep(nanoseconds: 50_000_000)
            return 42
        }
        #expect(result == 42)
    }

    @Test func operationErrorPropagates() async throws {
        await #expect(throws: BoomError.self) {
            _ = try await DebugHarnessRouter.harnessTimeout(seconds: 5) {
                throw BoomError()
            }
        }
    }
}
