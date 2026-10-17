import AVFoundation

/// Sound effects: `Sound.play(.jump)`.
@MainActor public enum Sound {
    /// Plays `<name>` (.wav, .m4a, .mp3 or .caf) from `Assets` or a folder in it at `volume`, from 0 to 1. Sounds can
    /// overlap, up to 8 of a format of file at once, the one nearest its end giving way to another.
    public static func play(_ sound: SoundName, volume: Double = 1) { play(sound.name, volume: volume) }

    /// Plays a sound named in a string.
    @_disfavoredOverload public static func play(_ name: String, volume: Double = 1) {
        mixer.play(buffer(name), volume: Float(volume))
    }

    /// Each sound played so far, read in full, by name, with its file and when that last changed, to read it again then.
    static var read: [String: (buffer: AVAudioPCMBuffer, url: URL, modified: Date?)] = [:]
    static let mixer = Mixer()

    /// The sound `name`, read from its file the first time it plays.
    static func buffer(_ name: String) -> AVAudioPCMBuffer {
        if let sound = read[name] { return sound.buffer }
        guard let url = soundURL(name) else { fatalError("PixelKit: Assets has no \(name).wav, .m4a, .mp3 or .caf") }
        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(max(1, file.length))) else {
                fatalError("PixelKit: can't play \(url.path): it's too long to hold")
            }
            try file.read(into: buffer)
            let sound = stereo(buffer)
            read[name] = (sound, url, modificationDate(url))
            return sound
        } catch {
            fatalError("PixelKit: can't play \(url.path): \(error.localizedDescription)")
        }
    }

    /// Forgets the sounds whose files changed, saved by the editor or gone, so they're read again when they next play.
    static func forgetChanged() {
        read = read.filter { modificationDate($0.value.url) == $0.value.modified }
    }
}

/// Where sound effects play: an `AVAudioEngine`, its main mixer adding up voices, each a player kept for a format of
/// sound and started once, the usual format's as the game starts and others' as they're first needed. A sound is a
/// buffer scheduled on one, with no file read and no audio queue started, which an `AVAudioPlayer` for each sound took
/// about 10 ms of the main thread to do.
@MainActor final class Mixer {
    let engine: AVAudioEngine
    /// The voices for each format of sound, and until when each is busy, in `CACurrentMediaTime()`'s seconds.
    var voices: [(format: AVAudioFormat, voices: [(player: AVAudioPlayerNode, until: Double)])] = []
    static let most = 8 // of a format at once

    /// The game's, playing to the output; a test's, rendering offline.
    init(engine: AVAudioEngine = AVAudioEngine()) { self.engine = engine }

    /// Plays `buffer` at `volume` on a voice for its format: a free one, a new one, or the one nearest its end.
    func play(_ buffer: AVAudioPCMBuffer, volume: Float) {
        guard running() else { return } // with no output to play to, as in a test without audio, it's skipped
        let now = CACurrentMediaTime()
        let group = voices.firstIndex { $0.format == buffer.format } ?? {
            voices.append((buffer.format, []))
            return voices.count - 1
        }()
        let i: Int
        switch voice(voices[group].voices.map(\.until), now: now, most: Mixer.most) {
        case let .free(free): i = free
        case let .cut(cut): i = cut
        case .new:
            voices[group].voices.append((player(for: buffer.format), 0))
            i = voices[group].voices.count - 1
        }
        let player = voices[group].voices[i].player
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        voices[group].voices[i].until = now + Double(buffer.frameLength) / buffer.format.sampleRate
    }

    /// Starts the engine with voices for the usual format of sound, two channels at 44.1 kHz, which a mono one is read
    /// into, so the first sounds needn't wait for them: starting took about 110 ms on a Mac and 25 on an iPhone
    /// simulator, and each voice a few more. The loop does it as the game starts, while its first frames take their
    /// time anyway; other formats get theirs as they first play.
    func prepare() {
        guard let usual = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2), !voices.contains(where: { $0.format == usual }) else { return }
        // Made before it starts, so they're in its graph from the first sound: the engine takes one made while it runs
        // in its own time, a few milliseconds.
        voices.append((usual, (0..<Mixer.most).map { _ in (player(for: usual), 0) }))
        _ = running()
    }

    /// A voice for sounds of `format`, on the main mixer, which takes any rate and channels, playing if the engine is.
    func player(for format: AVAudioFormat) -> AVAudioPlayerNode {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        if engine.isRunning { player.play() } // which a stopped engine refuses; `running` plays them once it's started
        return player
    }

    /// Whether the engine runs, starting it and its voices again if it doesn't: at the first sound, and after an
    /// interruption on iOS or a change of output stopped it.
    func running() -> Bool {
        if engine.isRunning { return true }
        #if os(iOS)
        _ = audioSession
        #endif
        _ = engine.mainMixerNode // connects the mixer to the output, which starting wants
        do { try engine.start() } catch { return false }
        for group in voices { for voice in group.voices { voice.player.play() } }
        return true
    }
}

/// `buffer` in two channels, a mono one's in both, as an `AVAudioPlayer` plays it: the mixer would pan one channel to
/// the middle, 3 dB down.
func stereo(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
    guard buffer.format.channelCount == 1, let mono = buffer.floatChannelData,
          let format = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 2),
          let both = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, buffer.frameLength)), let into = both.floatChannelData else { return buffer }
    both.frameLength = buffer.frameLength
    for channel in 0..<2 { into[channel].update(from: mono[0], count: Int(buffer.frameLength)) }
    return both
}

/// Which voice a sound goes on, of voices busy until `until`, in seconds as `now` is.
enum Voice: Equatable {
    case free(Int), new, cut(Int)
}

/// The first voice that's free, or else a new one while there are fewer than `most`, or else the one that's nearest
/// its end, to be cut off.
func voice(_ until: [Double], now: Double, most: Int) -> Voice {
    if let free = until.firstIndex(where: { $0 <= now }) { return .free(free) }
    if until.count < most { return .new }
    return .cut(until.indices.min { until[$0] < until[$1] } ?? 0)
}

/// Background music: one track at a time, looping. It keeps playing through scene changes and code reloads, pauses
/// with the game in the editor, and starts over when its file changes.
@MainActor public enum Music {
    static var player: AVAudioPlayer?
    static var track: String?
    static var modified: Date? // of the track's file when it started
    /// While the game is paused, the track holds its place, and one that starts meanwhile waits.
    static var paused = false {
        didSet { if paused { player?.pause() } else { player?.play() } }
    }

    /// Loops `<name>` (.wav, .m4a, .mp3 or .caf) from `Assets` or a folder in it. Playing the track that's already on
    /// keeps it going, so a scene can call this every time it starts. Given a `fade` in seconds, the old track fades out
    /// as this one fades in, so a house's music doesn't cut into the village's.
    public static func play(_ track: SoundName, fade: Double = 0) { play(track.name, fade: fade) }

    /// Loops a track named in a string, like one named after a map.
    @_disfavoredOverload public static func play(_ name: String, fade: Double = 0) {
        if name != track { start(name, audioPlayer(name), fade: fade) }
    }

    /// Stops the music.
    public static func stop() {
        player?.stop()
        (player, track) = (nil, nil)
    }

    /// From 0 to 1.
    public static var volume = 1.0 {
        didSet { player?.volume = Float(volume) }
    }

    /// Starts the track over if its file changed. One that can't be read yet, like a file still being saved, waits.
    static func restartIfChanged() {
        guard let track, let url = soundURL(track), modificationDate(url) != modified,
              let new = try? AVAudioPlayer(contentsOf: url) else { return }
        start(track, new)
    }

    private static func start(_ name: String, _ new: AVAudioPlayer, fade: Double = 0) {
        if let old = player, fade > 0 {
            old.setVolume(0, fadeDuration: fade)
            Task { // the old player plays on until it's silent
                try? await Task.sleep(for: .seconds(fade))
                old.stop()
            }
        } else {
            player?.stop()
        }
        new.numberOfLoops = -1
        new.volume = fade > 0 ? 0 : Float(volume)
        if !paused { new.play() }
        if fade > 0 { new.setVolume(Float(volume), fadeDuration: fade) }
        (player, track, modified) = (new, name, new.url.flatMap(modificationDate))
    }
}

/// `Assets/<name>` with the first of these file types that exists.
func soundURL(_ name: String) -> URL? {
    ["wav", "m4a", "mp3", "caf"].lazy.map { assetURL("\(name).\($0)") }.first { FileManager.default.fileExists(atPath: $0.path) }
}

#if os(iOS)
/// Sounds mix with other apps' audio, and the silent switch mutes them. Set before the first sound or track plays.
private let audioSession: Void = { try? AVAudioSession.sharedInstance().setCategory(.ambient) }()
#endif

func audioPlayer(_ name: String) -> AVAudioPlayer {
    #if os(iOS)
    _ = audioSession
    #endif
    guard let url = soundURL(name) else { fatalError("PixelKit: Assets has no \(name).wav, .m4a, .mp3 or .caf") }
    do {
        return try AVAudioPlayer(contentsOf: url)
    } catch {
        fatalError("PixelKit: can't play \(url.path): \(error.localizedDescription)")
    }
}
