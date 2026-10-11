import AVFoundation

/// Sound effects: `Sound.play("jump")`.
@MainActor public enum Sound {
    static var playing: [AVAudioPlayer] = [] // players stop if released, so keep them until they finish

    /// Plays `Assets/<name>` (.wav, .m4a, .mp3 or .caf) at `volume`, from 0 to 1. Sounds can overlap.
    // ponytail: one AVAudioPlayer per play; move to AVAudioEngine for lower latency or effects
    public static func play(_ name: String, volume: Double = 1) {
        playing.removeAll { !$0.isPlaying }
        let player = audioPlayer(name)
        player.volume = Float(volume)
        player.play()
        playing.append(player)
    }
}

/// Background music: one track at a time, looping. It keeps playing through scene changes and code reloads, and
/// starts over when its file changes.
@MainActor public enum Music {
    static var player: AVAudioPlayer?
    static var track: String?
    static var modified: Date? // of the track's file when it started

    /// Loops `Assets/<name>` (.wav, .m4a, .mp3 or .caf). Playing the track that's already on keeps it going, so a
    /// scene can call this every time it starts.
    public static func play(_ name: String) {
        if name != track { start(name, audioPlayer(name)) }
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

    private static func start(_ name: String, _ new: AVAudioPlayer) {
        player?.stop()
        new.numberOfLoops = -1
        new.volume = Float(volume)
        new.play()
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
    guard let url = soundURL(name) else { fatalError("PixelKit: there's no Assets/\(name).wav, .m4a, .mp3 or .caf") }
    do {
        return try AVAudioPlayer(contentsOf: url)
    } catch {
        fatalError("PixelKit: can't play \(url.path): \(error.localizedDescription)")
    }
}
