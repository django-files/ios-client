import SwiftUI

struct FileContextMenuButtons: View {
    var onPreview: () -> Void
    var onCopyShareLink: () -> Void
    var onCopyRawLink: () -> Void
    var onSetPrivate: () -> Void
    var onShowInMaps: () -> Void
    
    var body: some View {
        Group {
            Button {
                onPreview()
            } label: {
                Label("Open Preview", systemImage: "arrow.up.forward.app")
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
                onSetPrivate()
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