import SwiftUI
import AVFoundation
import NewsCore

/// Plays a published audio version supplied by the publication (HTTPS only).
@MainActor
@Observable
final class ArticleAudioPlayer {
    private(set) var isPlaying = false
    private(set) var elapsed: Double = 0
    private(set) var failed = false
    private var player: AVPlayer?
    private var observer: Any?

    func toggle(_ audio: ArticleAudio) {
        if player == nil {
            let item = AVPlayerItem(url: audio.url)
            let player = AVPlayer(playerItem: item)
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    self?.elapsed = time.seconds
                    if item.status == .failed { self?.failed = true; self?.isPlaying = false }
                }
            }
            self.player = player
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        }
        if isPlaying { player?.pause() } else { player?.play() }
        isPlaying.toggle()
    }

    func skip(_ seconds: Double) {
        guard let player else { return }
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func stop() {
        player?.pause()
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player = nil
        isPlaying = false
    }
}

struct ArticleAudioView: View {
    let audio: ArticleAudio
    @State private var player = ArticleAudioPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(audio.title ?? "Listen to this article", systemImage: "headphones")
                .font(.subheadline.weight(.semibold))
            if let narration = audio.narration {
                Text(narration).font(.footnote).foregroundStyle(Palette.secondaryText)
            }
            HStack(spacing: 16) {
                Button { player.skip(-15) } label: { Image(systemName: "gobackward.15").frame(width: 44, height: 44) }
                    .accessibilityLabel("Back 15 seconds")
                Button { player.toggle(audio) } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                        .frame(width: 52, height: 52)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.skip(30) } label: { Image(systemName: "goforward.30").frame(width: 44, height: 44) }
                    .accessibilityLabel("Forward 30 seconds")
                Spacer()
                Text(timeLabel).font(.footnote.monospacedDigit()).foregroundStyle(Palette.secondaryText)
                    .accessibilityLabel("Elapsed \(Int(player.elapsed)) seconds")
            }
            .foregroundStyle(Palette.accent)
            if player.failed {
                Text("The audio couldn't be played.").font(.footnote).foregroundStyle(Palette.warning)
            }
        }
        .cardSurface()
        .onDisappear { player.stop() }
    }

    private var timeLabel: String {
        func fmt(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
        if let total = audio.durationSeconds { return "\(fmt(player.elapsed)) / \(fmt(total))" }
        return fmt(player.elapsed)
    }
}

/// On-device read-aloud using the system voice. Clearly labelled as a local feature:
/// it is not a recording by the publication.
@MainActor
@Observable
final class ReadAloudController: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(article: Article) {
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            return
        }
        var parts = [article.summary.headline]
        if let standfirst = article.summary.standfirst { parts.append(standfirst) }
        for block in article.blocks {
            switch block {
            case .heading(_, let t), .paragraph(let t): parts.append(t.plainText)
            case .list(_, let items): parts.append(contentsOf: items.map(\.text.plainText))
            case .quote(let paragraphs, let attribution):
                parts.append(contentsOf: paragraphs.map(\.plainText))
                if let attribution { parts.append(attribution) }
            default: break
            }
        }
        let utterance = AVSpeechUtterance(string: parts.joined(separator: "\n\n"))
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
