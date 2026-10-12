import AVFoundation

/// Sound effects: `Sound.play(.jump)`.
@MainActor public enum Sound {
    static var playing: [AVAudioPlayer] = [] // players stop if released, so keep them until they finish

    /// Plays `<name>` (.wav, .m4a, .mp3 or .caf) from `Assets` or a folder in it at `volume`, from 0 to 1. Sounds can
    /// overlap.
    public static func play(_ sound: SoundName, volume: Double = 1) { play(sound.name, volume: volume) }

    /// Plays a sound named in a string.
    // ponytail: one AVAudioPlayer per play; move to AVAudioEngine for lower latency or effects
    @_disfavoredOverload public static func play(_ name: String, volume: Double = 1) {
        playing.removeAll { !$0.isPlaying }
        let player = audioPlayer(name)
        player.volume = Float(volume)
        player.play()
        playing.append(player)
    }
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
