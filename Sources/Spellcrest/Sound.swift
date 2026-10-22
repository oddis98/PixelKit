import AVFoundation

/// Sound effects: `Sound.play(.jump)`.
@MainActor public enum Sound {
    /// Plays `<name>` (.wav, .m4a, .mp3 or .caf) from `Assets` or a folder in it at `volume`, from 0 to 1; `pitch`
    /// times as fast and as high, 1 as recorded, 2 an octave up and 0.5 one down, from 0.25 to 4, so hits needn't all
    /// sound the same (`pitch: .random(in: 0.9...1.1)`); and panned from -1, the left, to 1, the right. Sounds can
    /// overlap, up to 8 of a format of file at once, the one nearest its end giving way to another; `stop(_:)` stops one
    /// early. One that's missing or can't be read plays nothing, and the console says why, once.
    public static func play(_ sound: SoundName, volume: Double = 1, pitch: Double = 1, pan: Double = 0) {
        play(sound.name, volume: volume, pitch: pitch, pan: pan)
    }

    /// Plays a sound named in a string.
    @_disfavoredOverload public static func play(_ name: String, volume: Double = 1, pitch: Double = 1, pan: Double = 0) {
        guard let buffer = buffer(name) else { return }
        mixer.play(buffer, name: name, volume: Float(volume), pitch: Float(min(max(pitch, 0.25), 4)), pan: Float(min(max(pan, -1), 1)))
    }

    /// Stops the sound wherever it's playing, before it ends: a fire's crackle as it goes out. Other sounds play on.
    public static func stop(_ sound: SoundName) { stop(sound.name) }

    /// Stops a sound named in a string.
    @_disfavoredOverload public static func stop(_ name: String) { mixer.stop(name) }

    /// From 0 to 1, what every sound's own volume is multiplied by, those playing too: a game's setting for its sound
    /// effects, as `Music.volume` is for its music.
    public static var volume: Double {
        get { Double(mixer.volume) }
        set { mixer.volume = Float(min(max(newValue, 0), 1)) }
    }

    /// Each sound played so far, read in full, by name, with its file and when that last changed, to read it again then.
    static var read: [String: (buffer: AVAudioPCMBuffer, url: URL, modified: Date?)] = [:]
    static let mixer = Mixer()

    /// The sound `name`, read from its file the first time it plays, unless `readAhead` has; nil when it's missing or
    /// can't be read, which the console says, once.
    static func buffer(_ name: String) -> AVAudioPCMBuffer? {
        if let sound = read[name] { return sound.buffer }
        guard let url = soundURL(name) else {
            say(once: "\(name) sound", "Spellcrest: Assets has no \(name).wav, .m4a, .mp3 or .caf, so it plays nothing")
            return nil
        }
        do {
            guard let sound = try readSound(url) else {
                say(once: "\(name) sound", "Spellcrest: can't play \(url.path): it's too long to hold")
                return nil
            }
            read[name] = (sound, url, modificationDate(url))
            return sound
        } catch {
            say(once: "\(name) sound", "Spellcrest: can't play \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// In an app, reads its sounds up to 10 seconds long in the background as the game starts, so none is read from its
    /// file on the main thread as it first plays, 2 to 4 ms on an iPhone. Longer ones, like music, are read as they first
    /// play, and in the editor every one is, so a sound saved meanwhile is the new one.
    static func readAhead() {
        guard !assetsCanChange else { return }
        DispatchQueue.global(qos: .utility).async {
            for name in bundledNames(["wav", "m4a", "mp3", "caf"]) {
                guard let url = soundURL(name), let sound = try? readSound(url, longest: 10) else { continue }
                let handed = Handed(value: sound)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { if read[name] == nil { read[name] = (handed.value, url, modificationDate(url)) } }
                }
            }
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
    /// The voices for each format of sound.
    var voices: [(format: AVAudioFormat, voices: [Strip])] = []
    static let most = 8 // of a format at once
    /// `Sound.volume`: the main mixer's, which adds up the voices, so it reaches those playing.
    var volume: Float = 1 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    /// A voice: a player, a varispeed for a sound's pitch, and a mixer of its own on the main mixer for its volume and
    /// pan, which a player's own `volume` and `pan` don't reach through an effect.
    struct Strip {
        let player: AVAudioPlayerNode
        let speed: AVAudioUnitVarispeed
        let fader: AVAudioMixerNode
        var until = 0.0 // when it's free, in `CACurrentMediaTime()`'s seconds
        var sound = "" // the name of the sound on it, for `Sound.stop(_:)`
    }

    /// The game's, playing to the output; a test's, rendering offline.
    init(engine: AVAudioEngine = AVAudioEngine()) { self.engine = engine }

    /// Plays `buffer`, the sound `name`, at `volume`, `pitch` times as fast and high, and panned by `pan`, on a voice for
    /// its format: a free one, a new one, or the one nearest its end.
    func play(_ buffer: AVAudioPCMBuffer, name: String = "", volume: Float, pitch: Float = 1, pan: Float = 0) {
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
            voices[group].voices.append(strip(for: buffer.format))
            i = voices[group].voices.count - 1
        }
        let strip = voices[group].voices[i]
        (strip.fader.volume, strip.fader.pan, strip.speed.rate) = (volume, pan, pitch)
        strip.player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        voices[group].voices[i].until = now + Double(buffer.frameLength) / buffer.format.sampleRate / Double(pitch)
        voices[group].voices[i].sound = name
    }

    /// Stops every voice still playing the sound `name`, leaving each ready for the next sound.
    func stop(_ name: String) {
        let now = CACurrentMediaTime()
        for group in voices.indices {
            for i in voices[group].voices.indices where voices[group].voices[i].sound == name && voices[group].voices[i].until > now {
                let player = voices[group].voices[i].player
                player.stop() // which forgets what it had to play, and stops it
                if engine.isRunning { player.play() }
                voices[group].voices[i].until = 0
            }
        }
    }

    /// Starts the engine with voices for the usual format of sound, two channels at 44.1 kHz, which a mono one is read
    /// into, so the first sounds needn't wait for them: starting took about 110 ms on a Mac and 25 on an iPhone
    /// simulator, and each voice a few more. The loop does it as the game starts, while its first frames take their
    /// time anyway; other formats get theirs as they first play.
    func prepare() {
        guard let usual = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2), !voices.contains(where: { $0.format == usual }) else { return }
        // Made before it starts, so they're in its graph from the first sound: the engine takes one made while it runs
        // in its own time, a few milliseconds. Eight strips of three nodes started in 45 to 48 ms on the M6 Mac, where
        // eight players alone took 100 to 140.
        voices.append((usual, (0..<Mixer.most).map { _ in strip(for: usual) }))
        _ = running()
    }

    /// A voice for sounds of `format`, on the main mixer, which takes any rate and channels, playing if the engine is.
    func strip(for format: AVAudioFormat) -> Strip {
        let strip = Strip(player: AVAudioPlayerNode(), speed: AVAudioUnitVarispeed(), fader: AVAudioMixerNode())
        for node in [strip.player, strip.speed, strip.fader] { engine.attach(node) }
        engine.connect(strip.player, to: strip.speed, format: format)
        engine.connect(strip.speed, to: strip.fader, format: format)
        engine.connect(strip.fader, to: engine.mainMixerNode, format: format)
        if engine.isRunning { strip.player.play() } // which a stopped engine refuses; `running` plays them once it's started
        return strip
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

/// The sound in the file at `url`, read in full and in two channels (`stereo`); nil when it's longer than `longest`
/// seconds, or too long to hold.
func readSound(_ url: URL, longest: Double = .infinity) throws -> AVAudioPCMBuffer? {
    let file = try AVAudioFile(forReading: url)
    guard Double(file.length) <= longest * file.processingFormat.sampleRate,
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(max(1, file.length))) else { return nil }
    try file.read(into: buffer)
    return stereo(buffer)
}

/// A value made on one thread and handed to another, which alone uses it from then on.
struct Handed<Value>: @unchecked Sendable {
    let value: Value
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
/// with the game in the editor, and starts over when its file changes. Its players are made, started and stopped on a
/// queue of their own, off the main thread: on an iPhone, starting a track took 25 to 47 ms, and stopping the old one
/// after its fade about as long, each a frame or two missed at every door and every dusk.
@MainActor public enum Music {
    /// The players' work, in the order it's asked for.
    nonisolated static let queue = DispatchQueue(label: "Spellcrest music")
    /// The track's player, and those fading out, used on `queue` only.
    nonisolated(unsafe) static var player: AVAudioPlayer?
    nonisolated(unsafe) static var fading: [ObjectIdentifier: AVAudioPlayer] = [:]
    static var playing: String? // the track asked for, by name
    static var modified: Date? // of the track's file when it started
    /// While the game is paused in the editor, the track holds its place, and one that starts meanwhile waits.
    static var paused = false {
        didSet { hold() }
    }
    /// The same for the game's own pause (`pause()`), kept apart from the editor's, so the music plays only while neither
    /// holds it.
    static var held = false {
        didSet { hold() }
    }

    /// The track on, as `play(_:fade:)` asked for it, though its file may not be there; nil once it's stopped.
    public static var track: SoundName? { playing.map(SoundName.init) }

    /// Loops `<name>` (.wav, .m4a, .mp3 or .caf) from `Assets` or a folder in it. Playing the track that's already on
    /// keeps it going, so a scene can call this every time it starts. Given a `fade` in seconds, the old track fades out
    /// as this one fades in, so a house's music doesn't cut into the village's. One that's missing or can't be read
    /// stops the music, and the console says why, once; where files can change, it plays once its file is there.
    public static func play(_ track: SoundName, fade: Double = 0) { play(track.name, fade: fade) }

    /// Loops a track named in a string, like one named after a map.
    @_disfavoredOverload public static func play(_ name: String, fade: Double = 0) {
        guard name != playing else { return }
        guard let url = soundURL(name) else {
            say(once: "\(name) music", "Spellcrest: Assets has no \(name).wav, .m4a, .mp3 or .caf, so the music stops")
            stop(fade: fade)
            (playing, modified) = (name, nil) // so it starts once its file is there
            return
        }
        start(name, url, fade: fade)
    }

    /// Holds the track's place, for a game's own pause menu, as the editor's Pause does, until `resume()`; a track that
    /// starts meanwhile waits too.
    public static func pause() { held = true }

    /// Plays the track on from where `pause()` held it.
    public static func resume() { held = false }

    /// Stops the music, fading it out over `fade` seconds, or at once without one.
    public static func stop(fade: Double = 0) {
        playing = nil
        queue.async {
            guard let old = player else { return }
            player = nil
            fadeOut(old, over: fade)
        }
    }

    /// From 0 to 1, kept between them.
    public static var volume = 1.0 {
        didSet {
            volume = min(max(volume, 0), 1)
            let volume = Float(volume)
            queue.async { player?.volume = volume }
        }
    }

    /// Holds the track's place while either pause does, and plays it on once neither does.
    private static func hold() {
        let held = paused || held
        queue.async { if held { player?.pause() } else { player?.play() } }
    }

    /// Starts the track over if its file changed. One that can't be read yet, like a file still being saved, leaves the
    /// old one playing until it changes again.
    static func restartIfChanged() {
        guard let playing, let url = soundURL(playing), modificationDate(url) != modified else { return }
        start(playing, url, ifReadable: true)
    }

    /// Plays the file at `url` as the track `name`, looping, in place of the one playing, which fades out over `fade`
    /// seconds as this one fades in.
    private static func start(_ name: String, _ url: URL, fade: Double = 0, ifReadable: Bool = false) {
        (playing, modified) = (name, modificationDate(url))
        let (volume, held) = (Float(volume), paused || held)
        queue.async {
            #if os(iOS)
            _ = audioSession
            #endif
            let new: AVAudioPlayer
            do { new = try AVAudioPlayer(contentsOf: url) } catch {
                if ifReadable { return }
                print("Spellcrest: can't play \(url.path), so the music stops: \(error.localizedDescription)")
                if let old = player { fadeOut(old, over: fade) }
                player = nil
                return
            }
            if let old = player { fadeOut(old, over: fade) }
            new.numberOfLoops = -1
            new.volume = fade > 0 ? 0 : volume
            if !held { new.play() }
            if fade > 0 { new.setVolume(volume, fadeDuration: fade) }
            player = new
        }
    }

    /// Fades `old` out over `fade` seconds, playing on until it's silent, then stops it, or stops it at once. On `queue`.
    nonisolated private static func fadeOut(_ old: AVAudioPlayer, over fade: Double) {
        guard fade > 0 else { return old.stop() }
        old.setVolume(0, fadeDuration: fade)
        let id = ObjectIdentifier(old)
        fading[id] = old
        queue.asyncAfter(deadline: .now() + fade) { fading.removeValue(forKey: id)?.stop() }
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
