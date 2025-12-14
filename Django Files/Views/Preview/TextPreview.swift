//
//  TextPreview.swift
//  Django Files
//
//  Created by Ralph Luaces on 6/5/25.
//

import SwiftUI
import HighlightSwift

struct TextPreview: View {
    let content: Data?
    let mimeType: String
    let fileName: String
    let isLoading: Bool
    let error: Error?
    @Binding var isContentScrolling: Bool
    
    var body: some View {
        if isLoading {
            HStack {
                Spacer()
                LoadingView()
                    .frame(width: 100, height: 100)
                Spacer()
            }
        } else if let content = content, let text = String(data: content, encoding: .utf8) {
            TextScrollView(
                text: text,
                language: determineLanguage(from: mimeType, fileName: fileName),
                isContentScrolling: $isContentScrolling
            )
            .ignoresSafeArea()
        } else if error != nil {
            Text("Unable to decode text content")
                .foregroundColor(.red)
        }
    }
    
    // Helper function to determine the highlight language based on file type
    private func determineLanguage(from mimeType: String, fileName: String) -> HighlightLanguage {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        
        switch fileExtension {
        case "swift":
            return .swift
        case "py", "python":
            return .python
        case "js", "javascript":
            return .javaScript
        case "java":
            return .java
        case "cpp", "c", "h", "hpp":
            return .cPlusPlus
        case "html":
            return .html
        case "css":
            return .css
        case "json":
            return .json
        case "md", "markdown":
            return .markdown
        case "sh", "bash":
            return .bash
        case "rb", "ruby":
            return .ruby
        case "go":
            return .go
        case "rs":
            return .rust
        case "php":
            return .php
        case "sql":
            return .sql
        case "ts", "typescript":
            return .typeScript
        case "yaml", "yml":
            return .yaml
        default:
            // For plain text or unknown types
            if mimeType == "text/plain" {
                return .plaintext
            }
            // Try to determine from mime type if extension didn't match
            let mimePrimeType = mimeType.split(separator: "/").first?.lowercased() ?? ""
            let mimeSubtype = mimeType.split(separator: "/").last?.lowercased() ?? ""

            switch mimePrimeType {
            case "application":
                switch mimeSubtype {
                    case "json", "x-ndjson":
                        return .json
                default:
                    return .plaintext
                }
            case "text":
                switch mimeSubtype {
                case "javascript":
                    return .javaScript
                case "python":
                    return .python
                case "java":
                    return .java
                case "html":
                    return .html
                case "css":
                    return .css
                case "json", "x-ndjson":
                    return .json
                case "markdown":
                    return .markdown
                case "xml":
                    return .html
                default:
                    return .plaintext
                }
            default:
                return .plaintext
            }
        }
    }
}

struct TextScrollView: UIViewRepresentable {
    let text: String
    let language: HighlightLanguage
    @Binding var isContentScrolling: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        
        // Create a hosting controller for the SwiftUI CodeText
        let hostingController = UIHostingController(rootView: AnyView(
            CodeText(text)
                .highlightLanguage(language)
        ))
        hostingController.view.backgroundColor = .clear
        hostingController.view.layoutMargins = .zero
        hostingController.view.insetsLayoutMarginsFromSafeArea = false
        
        // Add the hosting controller's view to the scroll view
        scrollView.addSubview(hostingController.view)
        context.coordinator.hostingController = hostingController
        
        // Set up constraints with negative top margin to eliminate padding
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: -35),
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
        
        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Update the text content if needed
        if let hostingController = context.coordinator.hostingController {
            hostingController.rootView = AnyView(
                CodeText(text)
                    .highlightLanguage(language)
            )
        }
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        let parent: TextScrollView
        weak var hostingController: UIHostingController<AnyView>?
        
        init(_ parent: TextScrollView) {
            self.parent = parent
        }
        
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.isContentScrolling = true
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.parent.isContentScrolling = false
                }
            }
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.parent.isContentScrolling = false
            }
        }
    }
}
