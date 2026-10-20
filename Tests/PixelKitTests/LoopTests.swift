import Testing
@testable import PixelKit

/// The updates each of a run of frames runs, `elapsed` seconds after the one before.
private func updates(_ elapsed: [Double]) -> [Int] {
    var pace = Pace()
    return elapsed.map { pace.updates(after: $0) }
}

@Test func aFrameDrawnALittleLateStillRunsOneUpdate() {
    let step = Loop.step
    #expect(updates(Array(repeating: step, count: 600)) == Array(repeating: 1, count: 600))
    // Late, then on time again, or early to make up for it: never two updates and then none, the picture standing still
    // and then jumping, up to just under half an update late.
    for late in [0.001, 0.003, 0.005, 0.008] {
        #expect(updates([step, step + late, step - late, step, step + late, step, step - late, step]) == Array(repeating: 1, count: 8))
    }
    #expect(updates([step * 1.002, step * 0.998, step * 1.002]) == [1, 1, 1]) // a display a hair off 60 Hz
    #expect(updates([step, step * 2, step * 3 + 0.001, step]) == [1, 2, 3, 1]) // refreshes missed: the frame after catches up
}

@Test func afterAStallTheGameSlowsDownForAMomentAndThenRunsAsSteadilyAsBefore() {
    #expect(updates([5]) == [Pace.most] && updates([5.005]) == [Pace.most]) // not 300 updates at once
    // A stall used to leave no time over, where a frame 3 ms late ran two updates and the next one none.
    #expect(updates([5.005, Loop.step + 0.003, Loop.step - 0.003, Loop.step]) == [Pace.most, 1, 1, 1])
}

@Test func atOtherRatesTheUpdatesAddUpToTheTime() {
    #expect(updates(Array(repeating: 1.0 / 30, count: 30)) == Array(repeating: 2, count: 30)) // a display at 30 Hz
    for rate in [50.0, 72, 120] { // a second of frames at each runs a second of updates, a frame at most one more than due
        let frames = updates(Array(repeating: 1 / rate, count: Int(rate)))
        #expect(frames.reduce(0, +) == 60 && frames.allSatisfy { $0 <= 2 })
    }
}
