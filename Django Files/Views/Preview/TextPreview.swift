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
    
    var body: some View {
        ScrollView(showsIndicators: true) {
            ZStack {
                if let content = content, let text = String(data: content, encoding: .utf8) {
                    CodeText(text)
                        .highlightLanguage(determineLanguage(from: mimeType, fileName: fileName))
                        .padding()
                } else {
                    Text("Unable to decode text content")
                        .foregroundColor(.red)
                }
            }
            .padding(.top, 40)
        }
        .refreshable(action: {}) // Empty refreshable to disable pull-to-refresh
        .scrollDisabled(false) // Explicitly enable scrolling
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
