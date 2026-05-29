//
//  Toast.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/29/25.
//

import SwiftUI
import UIKit

struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let systemImage: String?
}

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published fileprivate(set) var current: ToastItem?
    /// Extra distance to lift the toast away from the bottom edge — used to clear the
    /// `tabViewBottomAccessory` when uploads are in flight.
    @Published var bottomInset: CGFloat = 0

    private var queue: [ToastItem] = []
    private var lifecycle: Task<Void, Never>?
    private let displayDuration: Duration = .seconds(2.5)
    private let gapBetween: Duration = .milliseconds(220)

    private var host: UIHostingController<ToastHostView>?

    nonisolated init() {}

    nonisolated func showToast(message: String, systemImage: String? = nil) {
        let item = ToastItem(message: message, systemImage: systemImage)
        Task { @MainActor in
            self.enqueue(item)
        }
    }

    private func enqueue(_ item: ToastItem) {
        installHostIfNeeded()
        queue.append(item)
        if current == nil { advance() }
    }

    private func advance() {
        lifecycle?.cancel()
        guard !queue.isEmpty else {
            current = nil
            return
        }
        current = queue.removeFirst()
        lifecycle = Task { [weak self, displayDuration, gapBetween] in
            try? await Task.sleep(for: displayDuration)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.current = nil }
            try? await Task.sleep(for: gapBetween)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.advance() }
        }
    }

    private func installHostIfNeeded() {
        guard host == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        else { return }

        let hc = UIHostingController(rootView: ToastHostView())
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        hc.view.isUserInteractionEnabled = false
        window.addSubview(hc.view)
        let guide = window.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            hc.view.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            hc.view.topAnchor.constraint(equalTo: guide.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])
        host = hc
    }
}

private struct ToastHostView: View {
    @ObservedObject private var manager = ToastManager.shared

    var body: some View {
        VStack {
            Spacer()
            if let toast = manager.current {
                ToastBanner(item: toast)
                    .padding(.bottom, manager.bottomInset + 64)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: manager.current)
        .animation(.easeInOut(duration: 0.2), value: manager.bottomInset)
        .sensoryFeedbackIfAvailable(trigger: manager.current?.id)
        .accessibilityElement(children: .contain)
        .allowsHitTesting(false)
    }
}

private struct ToastBanner: View {
    let item: ToastItem

    var body: some View {
        HStack(spacing: 10) {
            if let symbol = item.systemImage {
                Image(systemName: symbol)
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
            }
            Text(item.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .modifier(ToastBackgroundModifier())
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.message))
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct ToastBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule(style: .continuous))
        } else {
            content.background(.regularMaterial, in: Capsule(style: .continuous))
        }
    }
}

private extension View {
    @ViewBuilder
    func sensoryFeedbackIfAvailable<T: Equatable>(trigger: T) -> some View {
        if #available(iOS 17.0, *) {
            self.sensoryFeedback(.impact(weight: .light), trigger: trigger)
        } else {
            self
        }
    }
}
