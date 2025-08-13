//
//  Video.swift
//  Django Files
//
//  Created by Ralph Luaces on 8/4/25.
//

import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let url: URL
    @Binding var isLoading: Bool
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
            } else {
                Color.black
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    private func setupPlayer() {
        isLoading = true
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer

        // Monitor the player item status
        if let currentItem = newPlayer.currentItem {
            // Check initial status
            if currentItem.status == .readyToPlay {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            } else if currentItem.status == .failed {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }

            // Set up status observation
            let _ = currentItem.observe(\.status, options: [.new]) { item, _ in
                DispatchQueue.main.async {
                    switch item.status {
                    case .readyToPlay:
                        self.isLoading = false
                    case .failed:
                        self.isLoading = false
                    case .unknown:
                        // Keep loading
                        break
                    @unknown default:
                        break
                    }
                }
            }

            // Set up periodic checking for video readiness (fallback)
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                if currentItem.status == .readyToPlay {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                    timer.invalidate()
                } else if currentItem.status == .failed {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                    timer.invalidate()
                }
            }
        }
    }

    private func cleanupPlayer() {
        player?.pause()
        player = nil
    }
}
