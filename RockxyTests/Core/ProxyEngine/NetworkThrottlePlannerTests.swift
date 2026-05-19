@testable import Rockxy
import Testing

struct NetworkThrottlePlannerTests {
    @Test("planner returns nil when bandwidth is unlimited")
    func unlimitedBandwidthReturnsNil() {
        #expect(NetworkThrottlePlanner.makePlan(byteCount: 1_024, bytesPerSecond: nil) == nil)
        #expect(NetworkThrottlePlanner.makePlan(byteCount: 1_024, bytesPerSecond: 0) == nil)
    }

    @Test("planner preserves total bandwidth duration")
    func totalBandwidthDuration() throws {
        let plan = try #require(NetworkThrottlePlanner.makePlan(
            byteCount: 1_000,
            bytesPerSecond: 500,
            nowNanos: 1_000
        ))

        #expect(plan.chunks.count == 1)
        #expect(plan.chunks[0].length == 1_000)
        #expect(plan.totalDelayMs == 2_000)
    }

    @Test("planner chains behind existing response backlog")
    func chainsBehindBacklog() throws {
        let plan = try #require(NetworkThrottlePlanner.makePlan(
            byteCount: 500,
            bytesPerSecond: 500,
            nowNanos: 1_000,
            earliestReadyAtNanos: 1_000_001_000
        ))

        #expect(plan.totalDelayMs == 2_000)
        #expect(NetworkThrottlePlanner.millisecondsUntil(nowNanos: 1_000, readyAtNanos: plan.readyAtNanos) == 2_000)
    }
}
