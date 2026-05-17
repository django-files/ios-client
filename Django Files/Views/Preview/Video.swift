//
//  Video.swift
//  Django Files
//
//  Created by Ralph Luaces on 8/4/25.
//

import SwiftUI
import AVKit
import UIKit

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        context.coordinator.observe(player: player)
        player.play()
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    class Coordinator: NSObject {
        @Binding var isLoading: Bool
        private var statusObservation: NSKeyValueObservation?

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        func observe(player: AVPlayer) {
            guard let item = player.currentItem else { return }
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    switch item.status {
                    case .readyToPlay, .failed:
                        self?.isLoading = false
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }

        deinit {
            statusObservation = nil
        }
    }
}
