import AppKit
import ImageIO
import MySequatorCore
import SwiftUI

enum MaskTool: String, CaseIterable, Sendable {
    case brushSky
    case eraseGround

    var displayName: String {
        switch self {
        case .brushSky:
            return "Brush Sky"
        case .eraseGround:
            return "Erase Ground"
        }
    }

    var paintValue: UInt8 {
        switch self {
        case .brushSky:
            return 255
        case .eraseGround:
            return 0
        }
    }
}

private extension SceneCompositionMode {
    var displayName: String {
        switch self {
        case .fullFrame:
            return "Full frame"
        case .skyFreezeGround:
            return "Sky + freeze ground"
        case .skyAndGround:
            return "Sky + ground stack"
        }
    }
}

private extension AlignmentModel {
    var displayName: String {
        switch self {
        case .conservative:
            return "Conservative"
        case .wideAngle:
            return "Wide angle"
        }
    }
}

private extension RawWhiteBalanceMode {
    var displayName: String {
        switch self {
        case .camera:
            return "Camera"
        case .auto:
            return "Auto"
        case .none:
            return "None"
        }
    }
}

private extension RawHighlightMode {
    var displayName: String {
        switch self {
        case .clip:
            return "Clip"
        case .unclip:
            return "Unclip"
        case .blend:
            return "Blend"
        case .rebuild:
            return "Rebuild"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var imagePaths: [URL] = []
    @Published var darkPaths: [URL] = []
    @Published var flatPaths: [URL] = []
    @Published var outputPath: String = FileManager.default.currentDirectoryPath + "/stacked.tiff"
    @Published var mode: CompositionMode = .sigma
    @Published var sceneMode: SceneCompositionMode = .skyFreezeGround {
        didSet {
            if sceneMode == .skyAndGround, mode == .trails {
                mode = .sigma
            }
        }
    }
    @Published var skyMask: SkyMask?
    @Published var maskOverlay: NSImage?
    @Published var showMaskOverlay = true
    @Published var maskTool: MaskTool = .brushSky
    @Published var brushSize = 48.0
    @Published var skyGuardPixels = 8.0
    @Published var maskFeatherPixels = 24.0
    @Published var refineSkyMaskEdges = true
    @Published var boundaryProtectionPixels = 80.0
    @Published var alignmentModel: AlignmentModel = .conservative
    @Published var rawWhiteBalanceMode: RawWhiteBalanceMode = .camera
    @Published var rawAutoBrightness = false
    @Published var rawHighlightMode: RawHighlightMode = .clip
    @Published var rawBlackLevel = ""
    @Published var stretch: OutputStretch = .none
    @Published var tiffDepth: TIFFDepth = .uint16
    @Published var reduceLightPollution = false
    @Published var enhanceStars = false
    @Published var linearMaster = false {
        didSet {
            if linearMaster {
                stretch = .none
                tiffDepth = .float32
                reduceLightPollution = false
                enhanceStars = false
            }
        }
    }
    @Published var selectedImage: URL?
    @Published var preview: NSImage?
    @Published var status = "Add star images to begin."
    @Published var progress = 0.0
    @Published var isStacking = false
    @Published var isMasking = false
    @Published var previewPixelSize = CGSize(width: 1, height: 1)
    private var previewCache: [URL: NSImage] = [:]
    private var previewSizeCache: [URL: CGSize] = [:]
    private var previewTask: Task<Void, Never>?

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.title = "Choose star images"
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        presentPanel(panel) { [weak self, panel] response in
            guard response == .OK, let self else { return }
            for url in panel.urls where !imagePaths.contains(url) {
                imagePaths.append(url)
            }
            selectedImage = imagePaths.last
            status = "\(imagePaths.count) star images ready."
            loadPreview()
        }
    }

    func removeSelected() {
        guard let selectedImage, let index = imagePaths.firstIndex(of: selectedImage) else { return }
        imagePaths.remove(at: index)
        self.selectedImage = imagePaths.last
        status = "\(imagePaths.count) star images ready."
        loadPreview()
    }

    func clearImages() {
        imagePaths.removeAll()
        selectedImage = nil
        preview = nil
        status = "Add star images to begin."
    }

    func chooseDarks() {
        chooseMultipleFiles(title: "Choose dark frames") { [weak self] urls in
            self?.darkPaths = urls
        }
    }

    func chooseFlats() {
        chooseMultipleFiles(title: "Choose flat frames") { [weak self] urls in
            self?.flatPaths = urls
        }
    }

    func chooseOutput() {
        let panel = NSSavePanel()
        panel.title = "Choose output file"
        panel.nameFieldStringValue = "stacked.tiff"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        presentPanel(panel) { [weak self, panel] response in
            guard response == .OK, let url = panel.url else { return }
            guard let self else { return }
            outputPath = url.path
        }
    }

    func loadPreview() {
        previewTask?.cancel()
        guard let selectedImage else { return }
        if let cached = previewCache[selectedImage] {
            preview = cached
            previewPixelSize = previewSizeCache[selectedImage] ?? cached.size
            refreshMaskOverlay()
            return
        }
        status = "Loading preview \(selectedImage.lastPathComponent)..."
        let url = selectedImage
        previewTask = Task { [weak self] in
            do {
                let bitmap = try await Task.detached {
                    try PreviewBitmap.load(url: url, maxPixelSize: 1400)
                }.value
                guard !Task.isCancelled else { return }
                let image = bitmap.makeImage()
                guard !Task.isCancelled else { return }
                self?.previewCache[url] = image
                self?.previewSizeCache[url] = CGSize(width: bitmap.width, height: bitmap.height)
                if self?.selectedImage == url {
                    self?.preview = image
                    self?.previewPixelSize = CGSize(width: bitmap.width, height: bitmap.height)
                    self?.refreshMaskOverlay()
                    self?.status = "\(self?.imagePaths.count ?? 0) star images ready."
                }
            } catch {
                guard !Task.isCancelled else { return }
                if self?.selectedImage == url {
                    self?.status = "Preview failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func stack() {
        guard !imagePaths.isEmpty else {
            status = "Add at least one star image."
            return
        }
        let output = URL(fileURLWithPath: outputPath)
        let rawOptions: RawProcessingOptions
        do {
            rawOptions = try makeRawOptions()
        } catch {
            status = error.localizedDescription
            return
        }
        let stackOptions = StackOptions(
            mode: mode,
            darkPaths: darkPaths,
            flatPaths: flatPaths,
            outputStretch: stretch,
            reduceLightPollution: reduceLightPollution,
            enhanceStars: enhanceStars,
            alignmentModel: alignmentModel,
            rawOptions: rawOptions,
            linearMaster: linearMaster
        )
        let saveOptions = SaveOptions(tiffDepth: tiffDepth, clip: !linearMaster)
        let scene = sceneMode
        let mask = skyMask
        let maskOptions = SkyMaskOptions(
            skyGuardPixels: Int(skyGuardPixels.rounded()),
            featherPixels: Int(maskFeatherPixels.rounded()),
            refineEdges: refineSkyMaskEdges,
            boundaryProtectionPixels: Int(boundaryProtectionPixels.rounded())
        )
        progress = 0
        isStacking = true
        status = "Starting stack..."

        Task {
            do {
                let paths = imagePaths
                let result = try await Task.detached {
                    var options = stackOptions
                    options.sceneMode = scene
                    options.skyMask = mask
                    options.skyMaskOptions = maskOptions
                    return try stackImages(paths, options: options) { message, fraction in
                        Task { @MainActor in
                            self.status = message
                            self.progress = fraction
                        }
                    }
                }.value
                if let generatedMask = result.skyMask {
                    skyMask = generatedMask
                    refreshMaskOverlay()
                }
                try await Task.detached {
                    try saveImage(result.image, to: output, options: saveOptions)
                }.value
                status = "Saved \(output.path)"
                progress = 1
            } catch {
                status = "Stack failed: \(error.localizedDescription)"
            }
            isStacking = false
        }
    }

    func generateAutoMask() {
        guard let url = baseImageURL else {
            status = "Add star images before generating a sky mask."
            return
        }
        let options = SkyMaskOptions(
            skyGuardPixels: Int(skyGuardPixels.rounded()),
            featherPixels: Int(maskFeatherPixels.rounded()),
            refineEdges: refineSkyMaskEdges,
            boundaryProtectionPixels: Int(boundaryProtectionPixels.rounded())
        )
        let rawOptions: RawProcessingOptions
        do {
            rawOptions = try makeRawOptions()
        } catch {
            status = error.localizedDescription
            return
        }
        isMasking = true
        status = "Generating sky mask \(url.lastPathComponent)..."
        Task {
            do {
                let mask = try await Task.detached {
                    let image = try loadImage(url, rawOptions: rawOptions)
                    return try autoSkyMask(for: image, options: options)
                        .refinedForForegroundEdges(baseImage: image, options: options)
                }.value
                skyMask = mask
                refreshMaskOverlay()
                status = "Sky mask ready."
            } catch {
                status = "Sky mask failed: \(error.localizedDescription)"
            }
            isMasking = false
        }
    }

    func refineSkyMask() {
        guard let mask = skyMask, let url = baseImageURL else {
            status = "Generate or import a sky mask before refining."
            return
        }
        let options = SkyMaskOptions(
            skyGuardPixels: Int(skyGuardPixels.rounded()),
            featherPixels: Int(maskFeatherPixels.rounded()),
            refineEdges: true,
            boundaryProtectionPixels: Int(boundaryProtectionPixels.rounded())
        )
        let rawOptions: RawProcessingOptions
        do {
            rawOptions = try makeRawOptions()
        } catch {
            status = error.localizedDescription
            return
        }
        isMasking = true
        status = "Refining sky mask edges..."
        Task {
            do {
                let refined = try await Task.detached {
                    let image = try loadImage(url, rawOptions: rawOptions)
                    return mask.refinedForForegroundEdges(baseImage: image, options: options)
                }.value
                skyMask = refined
                refreshMaskOverlay()
                status = "Sky mask refined."
            } catch {
                status = "Mask refine failed: \(error.localizedDescription)"
            }
            isMasking = false
        }
    }

    func importSkyMask() {
        let panel = NSOpenPanel()
        panel.title = "Import sky mask"
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        presentPanel(panel) { [weak self, panel] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                do {
                    let mask = try await Task.detached {
                        try loadSkyMask(url)
                    }.value
                    skyMask = mask
                    refreshMaskOverlay()
                    status = "Imported sky mask \(url.lastPathComponent)."
                } catch {
                    status = "Mask import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func exportSkyMask() {
        guard let mask = skyMask else {
            status = "No sky mask to export."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export sky mask"
        panel.nameFieldStringValue = "sky-mask.png"
        panel.canCreateDirectories = true
        presentPanel(panel) { [weak self, panel] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                do {
                    try await Task.detached {
                        try saveSkyMask(mask, to: url)
                    }.value
                    status = "Exported sky mask \(url.lastPathComponent)."
                } catch {
                    status = "Mask export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func clearSkyMask() {
        guard var mask = skyMask else { return }
        mask.clear(to: 0)
        skyMask = mask
        refreshMaskOverlay()
    }

    func invertSkyMask() {
        guard var mask = skyMask else { return }
        mask.invert()
        skyMask = mask
        refreshMaskOverlay()
    }

    func paintMask(at location: CGPoint, in viewSize: CGSize) {
        guard sceneMode != .fullFrame, var mask = skyMask else { return }
        let rect = fittedPreviewRect(in: viewSize)
        guard rect.contains(location), rect.width > 0, rect.height > 0 else { return }
        let nx = (location.x - rect.minX) / rect.width
        let ny = (location.y - rect.minY) / rect.height
        let x = min(max(Int((nx * CGFloat(mask.width)).rounded()), 0), mask.width - 1)
        let y = min(max(Int((ny * CGFloat(mask.height)).rounded()), 0), mask.height - 1)
        let radius = max(1, Int(brushSize.rounded()))
        mask.paint(centerX: x, centerY: y, radius: radius, value: maskTool.paintValue)
        skyMask = mask
        refreshMaskOverlay()
    }

    func refreshMaskOverlay() {
        guard let skyMask else {
            maskOverlay = nil
            return
        }
        maskOverlay = skyMask.makeOverlayImage(maxPixelSize: 1400)
    }

    private var baseImageURL: URL? {
        guard !imagePaths.isEmpty else { return nil }
        return imagePaths[imagePaths.count / 2]
    }

    private func makeRawOptions() throws -> RawProcessingOptions {
        let blackText = rawBlackLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        let blackLevel: Int?
        if blackText.isEmpty {
            blackLevel = nil
        } else if let value = Int(blackText), value >= 0, value <= Int(Int32.max) {
            blackLevel = value
        } else {
            throw MySequatorError.invalidOption("RAW black level must be a non-negative 32-bit integer.")
        }
        return RawProcessingOptions(
            whiteBalanceMode: rawWhiteBalanceMode,
            noAutoBrightness: !rawAutoBrightness,
            highlightMode: rawHighlightMode,
            userBlackLevel: blackLevel
        )
    }

    private func fittedPreviewRect(in viewSize: CGSize) -> CGRect {
        guard previewPixelSize.width > 0, previewPixelSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }
        let scale = min(viewSize.width / previewPixelSize.width, viewSize.height / previewPixelSize.height)
        let width = previewPixelSize.width * scale
        let height = previewPixelSize.height * scale
        return CGRect(
            x: (viewSize.width - width) / 2,
            y: (viewSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func chooseMultipleFiles(title: String, completion: @escaping @MainActor ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        presentPanel(panel) { [panel] response in
            completion(response == .OK ? panel.urls : [])
        }
    }

    private func presentPanel(_ panel: NSSavePanel, completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = presentationWindow {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window) { response in
                Task { @MainActor in
                    completion(response)
                }
            }
        } else {
            panel.begin { response in
                Task { @MainActor in
                    completion(response)
                }
            }
        }
    }

    private var presentationWindow: NSWindow? {
        if let keyWindow = NSApp.keyWindow, keyWindow.isVisible {
            return keyWindow
        }
        if let mainWindow = NSApp.mainWindow, mainWindow.isVisible {
            return mainWindow
        }
        return NSApp.windows.first { window in
            window.isVisible && !window.isMiniaturized && window.parent == nil
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        HStack(spacing: 12) {
            sidebar
                .frame(width: 330)
            preview
        }
        .padding(12)
        .onChange(of: model.selectedImage) { _ in
            model.loadPreview()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Star Images")
                .font(.headline)
            HStack {
                Button("Add", action: model.chooseImages)
                Button("Remove", action: model.removeSelected)
                    .disabled(model.selectedImage == nil)
                Button("Clear", action: model.clearImages)
                    .disabled(model.imagePaths.isEmpty)
            }
            List(selection: $model.selectedImage) {
                ForEach(model.imagePaths, id: \.self) { url in
                    Text(url.lastPathComponent)
                        .tag(url as URL?)
                }
            }
            .frame(minHeight: 180)

            GroupBox("Calibration") {
                VStack(alignment: .leading) {
                    HStack {
                        Button("Dark Frames", action: model.chooseDarks)
                        Button("Flat Frames", action: model.chooseFlats)
                    }
                    Text("\(model.darkPaths.count) dark, \(model.flatPaths.count) flat")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("RAW") {
                VStack(alignment: .leading) {
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
                    HStack {
                        Text("Black level")
                        TextField("Camera default", text: $model.rawBlackLevel)
                            .frame(width: 120)
                    }
                }
            }

            GroupBox("Output") {
                VStack(alignment: .leading) {
                    HStack {
                        TextField("Output", text: $model.outputPath)
                        Button("Choose", action: model.chooseOutput)
                    }
                    Toggle("PixInsight linear master", isOn: $model.linearMaster)
                    Picker("TIFF depth", selection: $model.tiffDepth) {
                        ForEach(TIFFDepth.allCases, id: \.self) { depth in
                            Text(depth.rawValue).tag(depth)
                        }
                    }
                }
            }

            GroupBox("Stack Options") {
                VStack(alignment: .leading) {
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
                    Toggle("Reduce light pollution", isOn: $model.reduceLightPollution)
                        .disabled(model.linearMaster)
                    Toggle("Enhance stars", isOn: $model.enhanceStars)
                        .disabled(model.linearMaster)
                }
            }

            GroupBox("Sky Mask") {
                VStack(alignment: .leading) {
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
                        Toggle("Overlay", isOn: $model.showMaskOverlay)
                    }
                    Picker("Tool", selection: $model.maskTool) {
                        ForEach(MaskTool.allCases, id: \.self) { tool in
                            Text(tool.displayName).tag(tool)
                        }
                    }
                    HStack {
                        Text("Brush")
                        Slider(value: $model.brushSize, in: 4...200)
                        Text("\(Int(model.brushSize.rounded())) px")
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Guard")
                        Slider(value: $model.skyGuardPixels, in: 0...64)
                        Text("\(Int(model.skyGuardPixels.rounded())) px")
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Feather")
                        Slider(value: $model.maskFeatherPixels, in: 0...160)
                        Text("\(Int(model.maskFeatherPixels.rounded())) px")
                            .monospacedDigit()
                    }
                    Toggle("Refine edges", isOn: $model.refineSkyMaskEdges)
                    HStack {
                        Text("Boundary")
                        Slider(value: $model.boundaryProtectionPixels, in: 0...240)
                        Text("\(Int(model.boundaryProtectionPixels.rounded())) px")
                            .monospacedDigit()
                    }
                }
            }
            .disabled(model.sceneMode == .fullFrame)

            Button("Stack Images", action: model.stack)
                .disabled(model.imagePaths.isEmpty || model.isStacking)
                .frame(maxWidth: .infinity)
            ProgressView(value: model.progress)
            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            ZStack {
                if let preview = model.preview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.showMaskOverlay, let maskOverlay = model.maskOverlay, model.sceneMode != .fullFrame {
                        Image(nsImage: maskOverlay)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    }
                } else {
                    Text("Preview")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.paintMask(at: value.location, in: proxy.size)
                    }
            )
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct PreviewBitmap: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    static func load(url: URL, maxPixelSize: Int) throws -> PreviewBitmap {
        let options = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            throw MySequatorError.loadFailed("Unable to create preview source.")
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: false,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            let image = try loadImage(url)
            return image.makePreviewBitmap(maxPixelSize: maxPixelSize)
        }

        let width = thumbnail.width
        let height = thumbnail.height
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MySequatorError.loadFailed("Unable to create preview context.")
        }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
        return PreviewBitmap(width: width, height: height, pixels: pixels)
    }

    func makeImage() -> NSImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return NSImage(size: .zero)
        }
        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }
}

private extension SkyMask {
    func makeOverlayImage(maxPixelSize: Int) -> NSImage {
        let scale = min(Float(maxPixelSize) / Float(max(width, height)), 1)
        let outWidth = max(1, Int((Float(width) * scale).rounded()))
        let outHeight = max(1, Int((Float(height) * scale).rounded()))
        var pixels = Array(repeating: UInt8(0), count: outWidth * outHeight * 4)
        for y in 0..<outHeight {
            let sourceY = min(height - 1, Int((Float(y) / Float(outHeight)) * Float(height)))
            for x in 0..<outWidth {
                let sourceX = min(width - 1, Int((Float(x) / Float(outWidth)) * Float(width)))
                let alphaValue = alpha[sourceY * width + sourceX]
                let dst = (y * outWidth + x) * 4
                pixels[dst + 0] = 0
                pixels[dst + 1] = 180
                pixels[dst + 2] = 255
                pixels[dst + 3] = UInt8((Float(alphaValue) * 0.38).rounded())
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: outWidth,
                height: outHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: outWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return NSImage(size: .zero)
        }
        return NSImage(cgImage: cgImage, size: CGSize(width: outWidth, height: outHeight))
    }
}

private extension FloatRGBImage {
    func makePreviewBitmap(maxPixelSize: Int) -> PreviewBitmap {
        let scale = min(Float(maxPixelSize) / Float(max(width, height)), 1)
        let outWidth = max(1, Int((Float(width) * scale).rounded()))
        let outHeight = max(1, Int((Float(height) * scale).rounded()))
        let clippedImage = clipped()
        var pixels = Array(repeating: UInt8(255), count: outWidth * outHeight * 4)
        for y in 0..<outHeight {
            let sourceY = min(height - 1, Int((Float(y) / scale).rounded()))
            for x in 0..<outWidth {
                let sourceX = min(width - 1, Int((Float(x) / scale).rounded()))
                let pixel = sourceY * width + sourceX
                let outPixel = y * outWidth + x
                let src = pixel * 3
                let dst = outPixel * 4
                pixels[dst + 0] = UInt8((clippedImage.data[src + 0] * 255).rounded())
                pixels[dst + 1] = UInt8((clippedImage.data[src + 1] * 255).rounded())
                pixels[dst + 2] = UInt8((clippedImage.data[src + 2] * 255).rounded())
            }
        }
        return PreviewBitmap(width: outWidth, height: outHeight, pixels: pixels)
    }

    func makePreviewImage(maxSize: CGSize) -> NSImage {
        let clippedImage = clipped()
        var pixels = Array(repeating: UInt8(255), count: width * height * 4)
        for pixel in 0..<pixelCount {
            let src = pixel * 3
            let dst = pixel * 4
            pixels[dst + 0] = UInt8((clippedImage.data[src + 0] * 255).rounded())
            pixels[dst + 1] = UInt8((clippedImage.data[src + 1] * 255).rounded())
            pixels[dst + 2] = UInt8((clippedImage.data[src + 2] * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return NSImage(size: .zero)
        }
        let original = NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
        let scale = min(maxSize.width / CGFloat(width), maxSize.height / CGFloat(height), 1)
        original.size = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        return original
    }
}
