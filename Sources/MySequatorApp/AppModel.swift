import AppKit
import Foundation
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

extension SceneCompositionMode {
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

extension AlignmentModel {
    var displayName: String {
        switch self {
        case .conservative:
            return "Conservative"
        case .wideAngle:
            return "Wide angle"
        }
    }
}

extension RawWhiteBalanceMode {
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

extension RawHighlightMode {
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
    @Published var alignmentModel: AlignmentModel = .wideAngle
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
    @Published var previewZoom = 1.0
    @Published private(set) var canUndoMask = false
    @Published private(set) var canRedoMask = false
    private var previewCache: [URL: NSImage] = [:]
    private var previewSizeCache: [URL: CGSize] = [:]
    private var previewTask: Task<Void, Never>?
    private var maskUndoStack: [SkyMask?] = []
    private var maskRedoStack: [SkyMask?] = []
    private let maxMaskHistoryDepth = 40
    private var activeMaskStrokePoint: CGPoint?
    private var activeMaskStrokeValue: UInt8?

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
                    replaceSkyMask(generatedMask, undoable: true)
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
                replaceSkyMask(mask, undoable: true)
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
                replaceSkyMask(refined, undoable: true)
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
                    replaceSkyMask(mask, undoable: true)
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
        replaceSkyMask(mask, undoable: true)
        status = "Sky mask cleared."
    }

    func invertSkyMask() {
        guard var mask = skyMask else { return }
        mask.invert()
        replaceSkyMask(mask, undoable: true)
        status = "Sky mask inverted."
    }

    @discardableResult
    func beginMaskStroke(atImageLocation location: CGPoint, imageViewSize: CGSize, erasing: Bool) -> Bool {
        guard sceneMode != .fullFrame, var mask = skyMask else { return false }
        guard let point = maskPoint(forImageLocation: location, imageViewSize: imageViewSize, mask: mask) else {
            return false
        }

        pushMaskUndoSnapshot()
        let value = erasing ? MaskTool.eraseGround.paintValue : maskTool.paintValue
        activeMaskStrokePoint = point
        activeMaskStrokeValue = value
        let radius = max(1, Int(brushSize.rounded()))
        mask.paint(centerX: Int(point.x.rounded()), centerY: Int(point.y.rounded()), radius: radius, value: value)
        skyMask = mask
        refreshMaskOverlay()
        return true
    }

    @discardableResult
    func continueMaskStroke(atImageLocation location: CGPoint, imageViewSize: CGSize, erasing: Bool) -> Bool {
        guard sceneMode != .fullFrame, var mask = skyMask else { return false }
        guard let point = maskPoint(forImageLocation: location, imageViewSize: imageViewSize, mask: mask) else {
            return false
        }
        guard let previousPoint = activeMaskStrokePoint else {
            return beginMaskStroke(atImageLocation: location, imageViewSize: imageViewSize, erasing: erasing)
        }

        let value = activeMaskStrokeValue ?? (erasing ? MaskTool.eraseGround.paintValue : maskTool.paintValue)
        paintMaskSegment(&mask, from: previousPoint, to: point, value: value)
        activeMaskStrokePoint = point
        skyMask = mask
        refreshMaskOverlay()
        return true
    }

    func endMaskStroke() {
        activeMaskStrokePoint = nil
        activeMaskStrokeValue = nil
    }

    func undoMaskEdit() {
        guard let previous = maskUndoStack.popLast() else { return }
        maskRedoStack.append(skyMask)
        skyMask = previous
        endMaskStroke()
        refreshMaskOverlay()
        updateMaskHistoryState()
        status = previous == nil ? "Mask edit undone; no sky mask." : "Mask edit undone."
    }

    func redoMaskEdit() {
        guard let next = maskRedoStack.popLast() else { return }
        maskUndoStack.append(skyMask)
        skyMask = next
        endMaskStroke()
        refreshMaskOverlay()
        updateMaskHistoryState()
        status = next == nil ? "Mask edit redone; no sky mask." : "Mask edit redone."
    }

    func toggleMaskTool() {
        maskTool = maskTool == .brushSky ? .eraseGround : .brushSky
        status = "\(maskTool.displayName) selected."
    }

    func zoomIn() {
        previewZoom = min(8.0, previewZoom * 1.25)
    }

    func zoomOut() {
        previewZoom = max(1.0, previewZoom / 1.25)
    }

    func resetZoom() {
        previewZoom = 1.0
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

    private func replaceSkyMask(_ newMask: SkyMask?, undoable: Bool) {
        if undoable, skyMask != newMask {
            pushMaskUndoSnapshot()
        }
        skyMask = newMask
        endMaskStroke()
        refreshMaskOverlay()
    }

    private func pushMaskUndoSnapshot() {
        maskUndoStack.append(skyMask)
        if maskUndoStack.count > maxMaskHistoryDepth {
            maskUndoStack.removeFirst(maskUndoStack.count - maxMaskHistoryDepth)
        }
        maskRedoStack.removeAll()
        updateMaskHistoryState()
    }

    private func updateMaskHistoryState() {
        canUndoMask = !maskUndoStack.isEmpty
        canRedoMask = !maskRedoStack.isEmpty
    }

    private func maskPoint(forImageLocation location: CGPoint, imageViewSize: CGSize, mask: SkyMask) -> CGPoint? {
        guard imageViewSize.width > 0, imageViewSize.height > 0 else { return nil }
        guard location.x >= 0,
              location.y >= 0,
              location.x <= imageViewSize.width,
              location.y <= imageViewSize.height else {
            return nil
        }

        let nx = min(max(location.x / imageViewSize.width, 0), 1)
        let ny = min(max(location.y / imageViewSize.height, 0), 1)
        return CGPoint(
            x: nx * CGFloat(mask.width - 1),
            y: ny * CGFloat(mask.height - 1)
        )
    }

    private func paintMaskSegment(_ mask: inout SkyMask, from start: CGPoint, to end: CGPoint, value: UInt8) {
        let radius = max(1, Int(brushSize.rounded()))
        let distance = hypot(Double(end.x - start.x), Double(end.y - start.y))
        let spacing = max(1.0, Double(radius) * 0.45)
        let steps = max(1, Int(ceil(distance / spacing)))

        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t
            mask.paint(centerX: Int(x.rounded()), centerY: Int(y.rounded()), radius: radius, value: value)
        }
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
