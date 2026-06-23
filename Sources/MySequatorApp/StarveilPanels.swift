import AppKit
import MySequatorCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            imageActions
            sessionSummary
            imageList
            footer
        }
        .padding(16)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Starveil")
                .font(.largeTitle.bold())
            Text("Astrophotography stacking")
                .foregroundStyle(.secondary)
        }
    }

    private var imageActions: some View {
        HStack {
            Button("Add", action: model.chooseImages)
            Button("Remove", action: model.removeSelected)
                .disabled(model.selectedImage == nil)
            Button("Clear", action: model.clearImages)
                .disabled(model.imagePaths.isEmpty || model.isStacking)
        }
    }

    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(model.imagePaths.count) star images")
            Text("\(model.darkPaths.count) dark, \(model.flatPaths.count) flat")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var imageList: some View {
        List(selection: $model.selectedImage) {
            if model.imagePaths.isEmpty {
                Text("Add star images to begin.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.imagePaths, id: \.self) { url in
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .tag(url as URL?)
                }
            }
        }
        .frame(minHeight: 180)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: model.progress)
            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PreviewCanvasView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .textBackgroundColor)
                if let preview = model.preview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.showMaskOverlay,
                       let maskOverlay = model.maskOverlay,
                       model.sceneMode != .fullFrame {
                        Image(nsImage: maskOverlay)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                        Text("Add images to preview")
                            .font(.title3)
                        Text("Sky mask painting remains available on the preview canvas.")
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.paintMask(at: value.location, in: proxy.size)
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
    }
}

struct SettingsInspectorView: View {
    @ObservedObject var model: AppModel
    @State private var sessionExpanded = true
    @State private var stackExpanded = true
    @State private var outputExpanded = false
    @State private var rawExpanded = false
    @State private var skyMaskExpanded = true
    @State private var postExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                inspectorHeader
                sessionSection
                stackSection
                outputSection
                rawSection
                skyMaskSection
                postProcessingSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 440, maxHeight: .infinity)
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.title2.bold())
            Text("Stack, output, RAW, and mask controls")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var sessionSection: some View {
        SettingsSection("Session", isExpanded: $sessionExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Dark Frames", action: model.chooseDarks)
                    Button("Flat Frames", action: model.chooseFlats)
                }
                Text("\(model.darkPaths.count) dark frames, \(model.flatPaths.count) flat frames")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stackSection: some View {
        SettingsSection("Stack", isExpanded: $stackExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Scene", selection: $model.sceneMode) {
                    ForEach(SceneCompositionMode.allCases, id: \.self) { scene in
                        Text(scene.displayName).tag(scene)
                    }
                }
                Picker("Mode", selection: $model.mode) {
                    ForEach(CompositionMode.allCases.filter { model.sceneMode != .skyAndGround || $0 != .trails }, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Picker("Alignment", selection: $model.alignmentModel) {
                    ForEach(AlignmentModel.allCases, id: \.self) { alignment in
                        Text(alignment.displayName).tag(alignment)
                    }
                }
                Picker("Output stretch", selection: $model.stretch) {
                    ForEach(OutputStretch.allCases, id: \.self) { stretch in
                        Text(stretch.rawValue).tag(stretch)
                    }
                }
                .disabled(model.linearMaster)
            }
        }
    }

    private var outputSection: some View {
        SettingsSection("Output Advanced", isExpanded: $outputExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Output", text: $model.outputPath)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Choose Output", action: model.chooseOutput)
                    Spacer()
                }
                Toggle("PixInsight linear master", isOn: $model.linearMaster)
                Picker("TIFF depth", selection: $model.tiffDepth) {
                    ForEach(TIFFDepth.allCases, id: \.self) { depth in
                        Text(depth.rawValue).tag(depth)
                    }
                }
            }
        }
    }

    private var rawSection: some View {
        SettingsSection("RAW", isExpanded: $rawExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("White balance", selection: $model.rawWhiteBalanceMode) {
                    ForEach(RawWhiteBalanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker("Highlights", selection: $model.rawHighlightMode) {
                    ForEach(RawHighlightMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle("LibRaw auto brightness", isOn: $model.rawAutoBrightness)
                TextField("Black level", text: $model.rawBlackLevel)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var skyMaskSection: some View {
        SettingsSection("Sky Mask", isExpanded: $skyMaskExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if model.sceneMode == .fullFrame {
                    Text("Sky mask controls are disabled in full-frame mode.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Auto Mask", action: model.generateAutoMask)
                        .disabled(model.imagePaths.isEmpty || model.isMasking || model.sceneMode == .fullFrame)
                    Button("Import", action: model.importSkyMask)
                        .disabled(model.sceneMode == .fullFrame)
                    Button("Export", action: model.exportSkyMask)
                        .disabled(model.skyMask == nil)
                }
                HStack {
                    Button("Refine", action: model.refineSkyMask)
                        .disabled(model.skyMask == nil || model.imagePaths.isEmpty || model.isMasking)
                    Button("Clear", action: model.clearSkyMask)
                        .disabled(model.skyMask == nil)
                    Button("Invert", action: model.invertSkyMask)
                        .disabled(model.skyMask == nil)
                }
                Toggle("Show overlay", isOn: $model.showMaskOverlay)
                Picker("Tool", selection: $model.maskTool) {
                    ForEach(MaskTool.allCases, id: \.self) { tool in
                        Text(tool.displayName).tag(tool)
                    }
                }
                sliderRow("Brush", value: $model.brushSize, range: 4...200, suffix: "px")
                sliderRow("Guard", value: $model.skyGuardPixels, range: 0...64, suffix: "px")
                sliderRow("Feather", value: $model.maskFeatherPixels, range: 0...160, suffix: "px")
                Toggle("Refine edges", isOn: $model.refineSkyMaskEdges)
                sliderRow("Boundary", value: $model.boundaryProtectionPixels, range: 0...240, suffix: "px")
            }
        }
        .disabled(model.sceneMode == .fullFrame)
    }

    private var postProcessingSection: some View {
        SettingsSection("Post-processing", isExpanded: $postExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Reduce light pollution", isOn: $model.reduceLightPollution)
                    .disabled(model.linearMaster)
                Toggle("Enhance stars", isOn: $model.enhanceStars)
                    .disabled(model.linearMaster)
                if model.linearMaster {
                    Text("Post-processing is disabled for linear masters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded())) \(suffix)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    init(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 8)
        } label: {
            Text(title)
                .font(.headline)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
