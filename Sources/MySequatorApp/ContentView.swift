import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var isSettingsPresented = true

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            PreviewCanvasView(model: model)
                .navigationTitle("Starveil")
                .toolbar {
                    ToolbarItemGroup {
                        Button(action: model.chooseImages) {
                            Label("Add Images", systemImage: "plus")
                        }
                        Button(action: model.undoMaskEdit) {
                            Label("Undo Mask Edit", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!model.canUndoMask)
                        .keyboardShortcut("z", modifiers: .command)
                        Button(action: model.redoMaskEdit) {
                            Label("Redo Mask Edit", systemImage: "arrow.uturn.forward")
                        }
                        .disabled(!model.canRedoMask)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                    }
                    ToolbarItemGroup {
                        Button(action: model.zoomOut) {
                            Label("Zoom Out", systemImage: "minus.magnifyingglass")
                        }
                        .disabled(model.preview == nil || model.previewZoom <= 1.0)
                        .keyboardShortcut("-", modifiers: .command)
                        Button(action: model.resetZoom) {
                            Label("Reset Zoom", systemImage: "magnifyingglass")
                        }
                        .disabled(model.preview == nil || model.previewZoom == 1.0)
                        .keyboardShortcut("0", modifiers: .command)
                        Button(action: model.zoomIn) {
                            Label("Zoom In", systemImage: "plus.magnifyingglass")
                        }
                        .disabled(model.preview == nil || model.previewZoom >= 8.0)
                        .keyboardShortcut("=", modifiers: .command)
                    }
                    ToolbarItemGroup {
                        Button(action: model.stack) {
                            Label("Stack", systemImage: "square.stack.3d.up")
                        }
                        .disabled(model.imagePaths.isEmpty || model.isStacking)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isSettingsPresented.toggle()
                        } label: {
                            Label("Settings", systemImage: "sidebar.right")
                        }
                        .help(isSettingsPresented ? "Hide settings" : "Show settings")
                    }
                }
                .inspector(isPresented: $isSettingsPresented) {
                    SettingsInspectorView(model: model)
                        .inspectorColumnWidth(min: 360, ideal: 400, max: 440)
                }
        }
        .onChange(of: model.selectedImage) { _, _ in
            model.loadPreview()
        }
    }
}
