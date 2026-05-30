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
    var message: String
    let systemImage: String?
    let groupKey: String?
}

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published fileprivate(set) var current: ToastItem?
    /// Lifts the toast off the bottom edge — used to clear the
    /// `tabViewBottomAccessory` during uploads.
    @Published var bottomInset: CGFloat = 0

    private var queue: [ToastItem] = []
    private var groupCounts: [String: Int] = [:]
    private var lifecycle: Task<Void, Never>?
    private let displayDuration: Duration = .seconds(2.5)
    private let gapBetween: Duration = .milliseconds(220)
    private var host: UIHostingController<ToastHostView>?

    nonisolated init() {}

    nonisolated func showToast(message: String, systemImage: String? = nil) {
        Task { @MainActor in
            self.enqueue(ToastItem(message: message, systemImage: systemImage, groupKey: nil))
        }
    }

    /// Coalescing toast. While a toast with `groupKey` is queued or visible,
    /// repeated calls bump a counter and replace `{count}` in `pluralFormat`,
    /// so a fan-out (e.g. 50 batch-delete events) collapses into one toast
    /// that updates in place instead of stacking.
    nonisolated func showToast(
        groupKey: String,
        systemImage: String? = nil,
        singular: String,
        pluralFormat: String
    ) {
        Task { @MainActor in
            self.enqueueGrouped(
                groupKey: groupKey,
                systemImage: systemImage,
                singular: singular,
                pluralFormat: pluralFormat
            )
        }
    }

    private func enqueue(_ item: ToastItem) {
        installHostIfNeeded()
        queue.append(item)
        if current == nil { advance() }
    }

    private func enqueueGrouped(
        groupKey: String,
        systemImage: String?,
        singular: String,
        pluralFormat: String
    ) {
        installHostIfNeeded()
        let count = (groupCounts[groupKey] ?? 0) + 1
        groupCounts[groupKey] = count

        if count == 1 {
            queue.append(ToastItem(message: singular, systemImage: systemImage, groupKey: groupKey))
            if current == nil { advance() }
            return
        }

        let updated = pluralFormat.replacingOccurrences(of: "{count}", with: "\(count)")
        if current?.groupKey == groupKey {
            current?.message = updated
            startTimer()
        } else if let idx = queue.firstIndex(where: { $0.groupKey == groupKey }) {
            queue[idx].message = updated
        }
    }

    private func advance() {
        guard !queue.isEmpty else {
            current = nil
            return
        }
        current = queue.removeFirst()
        startTimer()
    }

    private func startTimer() {
        lifecycle?.cancel()
        lifecycle = Task { [weak self, displayDuration, gapBetween] in
            try? await Task.sleep(for: displayDuration)
            if Task.isCancelled { return }
            await MainActor.run {
                // Re-check after the actor hop: a new event may have cancelled us
                // while we were waiting for the main actor.
                guard let self, !Task.isCancelled else { return }
                if let key = self.current?.groupKey {
                    self.groupCounts[key] = nil
                }
                self.current = nil
            }
            try? await Task.sleep(for: gapBetween)
            if Task.isCancelled { return }
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
        // Spring only when a toast appears, dismisses, or is replaced by a
        // different item — not on in-place count bumps.
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: manager.current?.id)
        .animation(.easeInOut(duration: 0.2), value: manager.bottomInset)
        .sensoryFeedback(.impact(weight: .light), trigger: manager.current?.id)
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
                .contentTransition(.numericText())
                .animation(.snappy, value: item.message)
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
