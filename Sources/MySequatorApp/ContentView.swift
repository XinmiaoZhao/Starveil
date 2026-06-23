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
                        Button(action: model.generateAutoMask) {
                            Label("Auto Mask", systemImage: "wand.and.stars")
                        }
                        .disabled(model.imagePaths.isEmpty || model.isMasking || model.sceneMode == .fullFrame)
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
