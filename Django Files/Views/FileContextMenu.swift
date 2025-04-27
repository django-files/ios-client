import SwiftUI

struct FileContextMenuButtons: View {
    
    var isPreviewing: Bool = false
    
    var onPreview: () -> Void
    var onCopyShareLink: () -> Void
    var onCopyRawLink: () -> Void
    var onTogglePrivate: () -> Void
    var onShowInMaps: () -> Void
    
    var body: some View {
        Group {
            if !isPreviewing {
                Button {
                    onPreview()
                } label: {
                    Label("Open Preview", systemImage: "arrow.up.forward.app")
                }
            }
            
            Button {
                onCopyShareLink()
            } label: {
                Label("Copy Share Link", systemImage: "link")
            }
            
            Button {
                onCopyRawLink()
            } label: {
                Label("Copy Raw Link", systemImage: "link.circle")
            }
            
            Button {
                onTogglePrivate()
            } label: {
                Label("Set Private", systemImage: "lock")
            }
            
            Button {
                onShowInMaps()
            } label: {
                Label("Show in Maps", systemImage: "mappin")
            }
        }
    }
} 
