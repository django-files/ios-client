//
//  PDF.swift
//  Django Files
//
//  Created by Ralph Luaces on 6/5/25.
//

import SwiftUI
import UIKit
import PDFKit

struct PDFView: UIViewRepresentable {
    let url: URL
    @Binding var isContentScrolling: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PDFKit.PDFView {
        let pdfView = PDFKit.PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        // Detect when the user is panning the PDF body so the parent dismiss
        // gesture is suppressed. Runs simultaneously with PDFKit's own
        // recognizers so scrolling/zooming still works normally.
        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        panGesture.delegate = context.coordinator
        panGesture.cancelsTouchesInView = false
        pdfView.addGestureRecognizer(panGesture)

        return pdfView
    }

    func updateUIView(_ pdfView: PDFKit.PDFView, context: Context) {
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let parent: PDFView

        init(_ parent: PDFView) {
            self.parent = parent
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
                if !parent.isContentScrolling {
                    parent.isContentScrolling = true
                }
            case .ended, .cancelled, .failed:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.parent.isContentScrolling = false
                }
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return true
        }
    }
}
