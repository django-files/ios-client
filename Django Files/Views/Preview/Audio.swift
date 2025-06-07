//
//  Audio.swift
//  Django Files
//
//  Created by Ralph Luaces on 6/5/25.
//

import SwiftUI
import AVKit

class AudioPlayerViewModel: ObservableObject {
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerItemObserver: NSKeyValueObservation?
    
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var currentTimeString = "00:00"
    @Published var durationString = "00:00"
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.overrideOutputAudioPort(.speaker)
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    func setupPlayer(with url: URL) {
        configureAudioSession()
        player = AVPlayer(url: url)
        
        // Add periodic time observer
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self = self,
                  let duration = self.player?.currentItem?.duration.seconds,
                  !duration.isNaN else { return }
            
            let currentTime = time.seconds
            self.progress = currentTime / duration
            self.currentTimeString = self.formatTime(currentTime)
            self.durationString = self.formatTime(duration)
        }
        
        // Observe player item status for completion
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                             object: player?.currentItem,
                                             queue: .main) { [weak self] _ in
            self?.handlePlaybackCompletion()
        }
        
        // Update duration when item is ready
        Task {
            if let duration = try? await player?.currentItem?.asset.load(.duration) as? CMTime,
               !duration.seconds.isNaN {
                await MainActor.run {
                    self.durationString = self.formatTime(duration.seconds)
                }
            }
        }
    }
    
    private func handlePlaybackCompletion() {
        isPlaying = false
        // Reset to beginning
        seek(to: 0)
    }
    
    func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            // If we're at the end, seek to beginning before playing
            if let currentTime = player?.currentTime().seconds,
               let duration = player?.currentItem?.duration.seconds,
               currentTime >= duration {
                seek(to: 0)
            }
            player?.play()
            isPlaying = true
        }
    }
    
    func seek(to progress: Double) {
        guard let duration = player?.currentItem?.duration else { return }
        let time = CMTime(seconds: progress * duration.seconds, preferredTimescale: 600)
        player?.seek(to: time)
    }
    
    func skipForward() {
        guard let currentTime = player?.currentTime().seconds else { return }
        seek(to: (currentTime + 15) / (player?.currentItem?.duration.seconds ?? currentTime + 15))
    }
    
    func skipBackward() {
        guard let currentTime = player?.currentTime().seconds else { return }
        seek(to: (currentTime - 15) / (player?.currentItem?.duration.seconds ?? currentTime))
    }
    
    func cleanup() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        NotificationCenter.default.removeObserver(self)
        player?.pause()
        player = nil
    }
    
    private func formatTime(_ timeInSeconds: Double) -> String {
        let minutes = Int(timeInSeconds / 60)
        let seconds = Int(timeInSeconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
    }
}


struct AudioPlayerView: View {
    let url: URL
    @StateObject private var playerViewModel = AudioPlayerViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 50))
                .foregroundColor(.gray)
                .padding(.bottom)

            HStack {
                Text(playerViewModel.currentTimeString)
                    .font(.caption)
                    .monospacedDigit()
                
                Slider(value: $playerViewModel.progress, in: 0...1) { editing in
                    if !editing {
                        playerViewModel.seek(to: playerViewModel.progress)
                    }
                }
                
                Text(playerViewModel.durationString)
                    .font(.caption)
                    .monospacedDigit()
            }
            .padding(.horizontal)
            
            // Playback Controls
            HStack(spacing: 30) {
                Button(action: { playerViewModel.skipBackward() }) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                
                Button(action: { playerViewModel.togglePlayback() }) {
                    Image(systemName: playerViewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                
                Button(action: { playerViewModel.skipForward() }) {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
            }
        }
        .onAppear {
            playerViewModel.setupPlayer(with: url)
        }
        .onDisappear {
            playerViewModel.cleanup()
        }
    }
}

