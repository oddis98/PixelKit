import AVFoundation

@MainActor public enum Sound {
    static var playing: [AVAudioPlayer] = [] // players stop if released, so keep them until they finish

    /// Plays `Assets/<name>.wav`. Sounds can overlap.
    // ponytail: one AVAudioPlayer per play; move to AVAudioEngine for music, looping or lower latency
    public static func play(_ name: String) {
        playing.removeAll { !$0.isPlaying }
        let url = assetURL("\(name).wav")
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            playing.append(player)
        } catch {
            fatalError("PixelKit: can't play \(url.path): \(error.localizedDescription)")
        }
    }
}
