import AVFoundation
import Metal
import Testing
@testable import PixelKit

/// A folder whose Assets hold a.wav and b.m4a, a tenth of a second of silence each, made the current directory.
@MainActor func silentTracks() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "music-\(UUID())")
    try FileManager.default.createDirectory(at: folder.appending(path: "Assets"), withIntermediateDirectories: true)
    FileManager.default.changeCurrentDirectoryPath(folder.path) // games load Assets/ relative to here
    for (file, format) in [("a.wav", kAudioFormatLinearPCM), ("b.m4a", kAudioFormatMPEG4AAC)] {
        let audio = try AVAudioFile(forWriting: folder.appending(path: "Assets/\(file)"),
                                    settings: [AVFormatIDKey: format, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1])
        let silence = try #require(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4410))
        silence.frameLength = 4410
        try audio.write(from: silence)
    }
    return folder
}

@MainActor @Test func musicKeepsItsTrackSwitchesStopsPausesWithTheGameAndStartsOverWhenTheFileChanges() throws {
    _ = try silentTracks()
    Music.volume = 0
    defer { Music.stop(); Music.volume = 1 }

    Music.play("a")
    let a = try #require(Music.player)
    Music.play("a")
    #expect(Music.player === a && a.isPlaying)
    Music.play("b")
    let b = try #require(Music.player)
    #expect(b !== a && !a.isPlaying && b.url?.lastPathComponent == "b.m4a")

    Music.restartIfChanged()
    #expect(Music.player === b) // the file didn't change
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 10)], ofItemAtPath: "Assets/b.m4a")
    Music.restartIfChanged()
    #expect(Music.player !== b && Music.track == "b" && Music.player?.isPlaying == true)

    // Pausing the game holds the track's place, and one that starts or restarts meanwhile waits for the resume.
    let loop = Loop(resolution: Size(8, 8), device: try #require(MTLCreateSystemDefaultDevice()))
    let playing = try #require(Music.player)
    loop.paused = true
    #expect(!playing.isPlaying)
    loop.paused = false
    #expect(Music.player === playing && playing.isPlaying) // resumed, not started over
    loop.paused = true
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 20)], ofItemAtPath: "Assets/b.m4a")
    Music.restartIfChanged()
    #expect(Music.player !== playing && Music.player?.isPlaying == false)
    Music.play("a")
    #expect(Music.track == "a" && Music.player?.isPlaying == false)
    loop.paused = false
    #expect(Music.player?.isPlaying == true)

    Music.stop()
    #expect(Music.player == nil && Music.track == nil)

    Sound.play("b", volume: 0)
    #expect(Sound.playing.last?.url?.lastPathComponent == "b.m4a" && Sound.playing.last?.volume == 0)
}

@MainActor @Test func musicFadesFromOneTrackIntoTheNext() async throws {
    _ = try silentTracks()
    Music.volume = 0
    defer { Music.stop(); Music.volume = 1 }
    Music.play("a")
    let a = try #require(Music.player)
    Music.play("b", fade: 0.2)
    #expect(Music.track == "b" && Music.player !== a && a.isPlaying) // still on while it fades out
    try await Task.sleep(for: .seconds(0.5))
    #expect(!a.isPlaying)
}
