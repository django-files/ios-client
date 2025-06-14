import SwiftUI

struct FileContextMenuButtons: View {
    
    var isPreviewing: Bool = false
    var isPrivate: Bool = false
    
    var onPreview: () -> Void = {}
    var onCopyShareLink: () -> Void = {}
    var onCopyRawLink: () -> Void = {}
    var openRawBrowser: () -> Void = {}
    var onTogglePrivate: () -> Void = {}
    var setExpire: () -> Void = {}
    var setPassword: () -> Void = {}
    var addToAlbum: () -> Void = {}
    var manageAlbums: () -> Void = {}
    var renameFile: () -> Void = {}
    var deleteFile: () -> Void = {}
    
    var body: some View {
        Group {
            if !isPreviewing {
                Button {
                    onPreview()
                } label: {
                    Label("Open Preview", systemImage: "arrow.up.forward.app")
                }
            
            
                Button {
                    onCopyShareLink()
                    notifyClipboard()
                } label: {
                    Label("Copy Share Link", systemImage: "link")
                }
                
                Button {
                    onCopyRawLink()
                    notifyClipboard()
                } label: {
                    Label("Copy Raw Link", systemImage: "link.circle")
                }
            }
            
            Button {
                openRawBrowser()
            } label: {
                Label("Open Raw in Browser", systemImage: "globe")
            }
            
            Divider()
            Button {
                onTogglePrivate()
            } label: {
                if isPrivate {
                    Label("Make Public", systemImage: "lock.open")
                } else {
                    Label("Make Private", systemImage: "lock")
                }
            }
            
            Button {
                setExpire()
            } label: {
                Label("Set Expire", systemImage: "calendar.badge.exclamationmark")
            }
            
            Button {
                setPassword()
            } label: {
                Label("Set Password", systemImage: "key")
            }

//            Divider()
//            Button {
//                addToAlbum()
//            } label: {
//                Label("Add To Album", systemImage: "rectangle.stack.badge.plus")
//            }
//
            Divider()
            
            Button {
                renameFile()
            } label: {
                Label("Rename File", systemImage: "character.cursor.ibeam")
            }
            Divider()
            Button(role: .destructive) {
                deleteFile()
            } label: {
                Label("Delete File", systemImage: "trash")
            }
        }
    }
}


struct FileShareMenu: View {
    var onCopyShareLink: () -> Void = {}
    var onCopyRawLink: () -> Void = {}
    var openRawBrowser: () -> Void = {}

    var body: some View {
        Group {
            Button {
                onCopyShareLink()
                notifyClipboard()
            } label: {
                Label("Copy Share Link", systemImage: "link")
            }
            Button {
                onCopyRawLink()
                notifyClipboard()
            } label: {
                Label("Copy Raw Link", systemImage: "link.circle")
            }
        }
    }
}

func notifyClipboard() {
    // Generate haptic feedback
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.success)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        ToastManager.shared.showToast(message: "Copied to clipboard")
    }
}
