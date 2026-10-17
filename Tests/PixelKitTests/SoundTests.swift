import AVFoundation
import Testing
@testable import PixelKit

@Test func aSoundGoesOnAFreeVoiceThenANewOneThenTheOneNearestItsEnd() {
    #expect(voice([], now: 1, most: 2) == .new)
    #expect(voice([0.5, 3], now: 1, most: 2) == .free(0))
    #expect(voice([1, 3], now: 1, most: 2) == .free(0)) // just ended
    #expect(voice([2], now: 1, most: 2) == .new)
    #expect(voice([3, 2], now: 1, most: 2) == .cut(1))
}

@MainActor @Test func aSoundIsReadOnceAndAgainWhenItsFileChangesAndPlaysAtItsVolume() throws {
    _ = try silentTracks()
    Sound.read = [:] // what other tests' folders had of the same names
    Sound.play("b", volume: 0)
    let b = try #require(Sound.read["b"])
    #expect(b.url.lastPathComponent == "b.m4a")
    Sound.play("b", volume: 0.5)
    #expect(Sound.read["b"]?.buffer === b.buffer) // read once
    // With output to play to, each is on a voice of its own for b's format, the second at half volume.
    if Sound.mixer.engine.isRunning {
        let voices = try #require(Sound.mixer.voices.first { $0.format == b.buffer.format }?.voices)
        #expect(voices.count >= 2 && voices.contains { $0.player.volume == 0.5 })
    }
    Sound.forgetChanged()
    #expect(Sound.read["b"]?.buffer === b.buffer) // its file didn't change
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 10)], ofItemAtPath: "Assets/b.m4a")
    Sound.forgetChanged()
    #expect(Sound.read["b"] == nil)
    Sound.play("b", volume: 0)
    #expect(Sound.read["b"] != nil && Sound.read["b"]?.buffer !== b.buffer)
    // A hundred sounds in a few milliseconds, where an AVAudioPlayer for each took about 10 ms.
    let start = ContinuousClock.now
    for _ in 0..<100 { Sound.play("a", volume: 0) }
    #expect(ContinuousClock.now - start < .milliseconds(100))
}

@MainActor @Test func soundsComeOutOfTheMixerAtTheirVolumesAndAddUp() throws {
    let engine = AVAudioEngine(), format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    try engine.enableManualRenderingMode(.offline, format: try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)),
                                         maximumFrameCount: 4096)
    let mixer = Mixer(engine: engine)
    let mono = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)) // a second at 0.5, as a mono file reads
    mono.frameLength = 44100
    for i in 0..<44100 { mono.floatChannelData![0][i] = 0.5 }
    let sound = stereo(mono) // as Sound reads it
    #expect(sound.format.channelCount == 2 && sound.frameLength == 44100 && sound.floatChannelData![1][100] == 0.5)
    let out = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024))
    /// Whether the output comes to `value`, both sides, all through a block, within 20 blocks (half the sound): a
    /// buffer starts a moment after it's scheduled, by the clock, which rendering offline races ahead of, and the
    /// mixer eases a voice from its last volume to its next over a block, so a change doesn't click.
    func settles(at value: Float) throws -> Bool {
        for _ in 0..<20 {
            #expect(try engine.renderOffline(1024, to: out) == .success)
            if [0, 1].allSatisfy({ side in [0, 512, 1023].allSatisfy { abs(out.floatChannelData![side][$0] - value) < 0.001 } }) { return true }
        }
        return false
    }
    mixer.prepare() // as the game starts: its usual voices, then the engine
    #expect(engine.isRunning && mixer.voices.first?.voices.count == Mixer.most && mixer.voices.first?.format == sound.format)
    #expect(try settles(at: 0)) // nothing plays yet
    mixer.play(sound, volume: 0.5)
    #expect(try settles(at: 0.25)) // at its volume
    mixer.play(sound, volume: 1) // on a second voice, over the first
    #expect(try settles(at: 0.75))
}
