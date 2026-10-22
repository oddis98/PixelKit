import AVFoundation
import Testing
@testable import Spellcrest

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
        #expect(voices.count >= 2 && voices.contains { $0.fader.volume == 0.5 })
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
    // The sounds' volume, a game's setting, turns down both of those already playing, then all of them off.
    mixer.volume = 0.5
    #expect(try settles(at: 0.375))
    mixer.volume = 0
    #expect(try settles(at: 0))
}

@MainActor @Test func theSoundsVolumeIsTheMixersFromNothingToAll() {
    defer { Sound.volume = 1 }
    Sound.volume = 0.3
    #expect(Sound.mixer.volume == 0.3 && Sound.mixer.engine.mainMixerNode.outputVolume == 0.3 && abs(Sound.volume - 0.3) < 0.0001)
    Sound.volume = 2
    #expect(Sound.volume == 1)
    Sound.volume = -1
    #expect(Sound.volume == 0)
}

@MainActor @Test func soundsPlayAtTheirPitchPannedAndStopByNameLeavingTheRest() throws {
    let stereo = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
    let engine = AVAudioEngine()
    try engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: 4096)
    let mixer = Mixer(engine: engine)
    let sound = try #require(AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 44100)) // a second at 0.5, both sides
    sound.frameLength = 44100
    for side in 0..<2 { for i in 0..<44100 { sound.floatChannelData![side][i] = 0.5 } }
    let out = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024))
    /// How long the output sounds over `seconds`, and how loud each side is in all, rendering offline.
    func listen(_ seconds: Double) throws -> (sounding: Double, left: Double, right: Double) {
        var (frames, left, right) = (0, 0.0, 0.0)
        for _ in 0..<Int(seconds * 44100 / 1024) {
            #expect(try engine.renderOffline(1024, to: out) == .success)
            for i in 0..<Int(out.frameLength) {
                let (l, r) = (out.floatChannelData![0][i], out.floatChannelData![1][i])
                if abs(l) + abs(r) > 0.01 { frames += 1 }
                (left, right) = (left + Double(abs(l)), right + Double(abs(r)))
            }
        }
        return (Double(frames) / 44100, left, right)
    }
    mixer.prepare()
    // Twice as fast, it's over in half a second, and all the way left, it's on the left; the right hears under a
    // hundredth of it, as the mixer eases a voice's pan from its last over a block, as it does its volume.
    mixer.play(sound, volume: 1, pitch: 2, pan: -1)
    let fast = try listen(1)
    #expect(abs(fast.sounding - 0.5) < 0.03 && fast.left > 10000 && fast.right < fast.left / 100)
    mixer.play(sound, volume: 1, pitch: 0.5, pan: 1) // half as fast: two seconds, on the right
    let slow = try listen(2.5)
    #expect(abs(slow.sounding - 2) < 0.05 && slow.right > 40000 && slow.left < slow.right / 100)

    // Stopped by its name, every voice playing it goes quiet at once, and other sounds play on.
    mixer.play(sound, name: "crackle", volume: 1)
    mixer.play(sound, name: "crackle", volume: 1)
    #expect(try listen(0.1).sounding > 0.05)
    mixer.stop("crackle")
    #expect(try listen(0.2).sounding < 0.03) // a block or so as the mixer eases them off
    mixer.play(sound, name: "hum", volume: 1)
    mixer.stop("crackle") // none of it plays now: the hum plays on
    #expect(try listen(0.3).sounding > 0.25)
}
