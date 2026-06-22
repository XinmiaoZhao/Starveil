import Foundation
import MySequatorCore

struct CLIOptions {
    var images: [URL] = []
    var output: URL?
    var base: URL?
    var darks: [URL] = []
    var flats: [URL] = []
    var mode: CompositionMode = .sigma
    var sceneMode: SceneCompositionMode = .fullFrame
    var skyMask: URL?
    var writeSkyMask: URL?
    var skyGuardPixels = 8
    var maskFeatherPixels = 24
    var sigma: Float = 2.2
    var stretch: OutputStretch = .none
    var reduceLightPollution = false
    var lightPollutionStrength: Float = 0.45
    var enhanceStars = false
    var starEnhancementStrength: Float = 0.35
    var linearMaster = false
    var tiffDepth: TIFFDepth = .uint16
}

func printUsage() {
    print("""
    Usage:
      mysequator-swift --output stacked.tiff [options] image_001.tif image_002.tif ...

    Options:
      --base PATH
      --dark PATH                         Repeatable
      --flat PATH                         Repeatable
      --mode mean|sigma|trails
      --scene full|sky-freeze-ground|sky-ground
      --sky-mask PATH
      --write-sky-mask PATH
      --sky-guard PX
      --mask-feather PX
      --sigma VALUE
      --stretch none|auto|hdr
      --reduce-light-pollution
      --light-pollution-strength VALUE
      --enhance-stars
      --star-enhancement-strength VALUE
      --linear-master                     Force linear output and disable display processing
      --tiff-depth uint16|float32
      -o, --output PATH
      -h, --help
    """)
}

func parseArguments(_ args: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var index = 0
    while index < args.count {
        let arg = args[index]
        func requireValue() throws -> String {
            guard index + 1 < args.count else {
                throw MySequatorError.invalidOption("Missing value for \(arg).")
            }
            index += 1
            return args[index]
        }

        switch arg {
        case "--":
            break
        case "-h", "--help":
            printUsage()
            exit(0)
        case "-o", "--output":
            options.output = URL(fileURLWithPath: try requireValue())
        case "--base":
            options.base = URL(fileURLWithPath: try requireValue())
        case "--dark":
            options.darks.append(URL(fileURLWithPath: try requireValue()))
        case "--flat":
            options.flats.append(URL(fileURLWithPath: try requireValue()))
        case "--mode":
            let value = try requireValue()
            guard let mode = CompositionMode(rawValue: value) else {
                throw MySequatorError.invalidOption("Unknown mode: \(value).")
            }
            options.mode = mode
        case "--scene":
            let value = try requireValue()
            switch value {
            case "full", "full-frame", "fullFrame":
                options.sceneMode = .fullFrame
            case "sky-freeze-ground", "skyFreezeGround":
                options.sceneMode = .skyFreezeGround
            case "sky-ground", "sky-and-ground", "skyAndGround":
                options.sceneMode = .skyAndGround
            default:
                throw MySequatorError.invalidOption("Unknown scene mode: \(value).")
            }
        case "--sky-mask":
            options.skyMask = URL(fileURLWithPath: try requireValue())
        case "--write-sky-mask":
            options.writeSkyMask = URL(fileURLWithPath: try requireValue())
        case "--sky-guard":
            guard let value = Int(try requireValue()) else {
                throw MySequatorError.invalidOption("Invalid sky guard.")
            }
            options.skyGuardPixels = value
        case "--mask-feather":
            guard let value = Int(try requireValue()) else {
                throw MySequatorError.invalidOption("Invalid mask feather.")
            }
            options.maskFeatherPixels = value
        case "--sigma":
            guard let value = Float(try requireValue()) else {
                throw MySequatorError.invalidOption("Invalid sigma.")
            }
            options.sigma = value
        case "--stretch":
            let value = try requireValue()
            guard let stretch = OutputStretch(rawValue: value) else {
                throw MySequatorError.invalidOption("Unknown stretch: \(value).")
            }
            options.stretch = stretch
        case "--auto-brightness":
            options.stretch = .auto
        case "--no-auto-brightness":
            options.stretch = .none
        case "--hdr":
            options.stretch = .hdr
        case "--reduce-light-pollution":
            options.reduceLightPollution = true
        case "--light-pollution-strength":
            guard let value = Float(try requireValue()) else {
                throw MySequatorError.invalidOption("Invalid light-pollution strength.")
            }
            options.lightPollutionStrength = value
        case "--enhance-stars":
            options.enhanceStars = true
        case "--star-enhancement-strength":
            guard let value = Float(try requireValue()) else {
                throw MySequatorError.invalidOption("Invalid star-enhancement strength.")
            }
            options.starEnhancementStrength = value
        case "--linear-master":
            options.linearMaster = true
            options.stretch = .none
            options.tiffDepth = .float32
        case "--tiff-depth":
            let value = try requireValue()
            guard let depth = TIFFDepth(rawValue: value) else {
                throw MySequatorError.invalidOption("Unknown TIFF depth: \(value).")
            }
            options.tiffDepth = depth
        default:
            if arg.hasPrefix("-") {
                throw MySequatorError.invalidOption("Unknown option: \(arg).")
            }
            options.images.append(URL(fileURLWithPath: arg))
        }
        index += 1
    }
    return options
}

do {
    let cli = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    guard let output = cli.output else {
        throw MySequatorError.invalidOption("--output is required.")
    }
    guard !cli.images.isEmpty else {
        throw MySequatorError.invalidOption("Add at least one star image.")
    }

    let skyMask = try cli.skyMask.map(loadSkyMask)
    let options = StackOptions(
        mode: cli.mode,
        sceneMode: cli.sceneMode,
        basePath: cli.base,
        darkPaths: cli.darks,
        flatPaths: cli.flats,
        skyMask: skyMask,
        skyMaskOptions: SkyMaskOptions(skyGuardPixels: cli.skyGuardPixels, featherPixels: cli.maskFeatherPixels),
        outputStretch: cli.stretch,
        reduceLightPollution: cli.reduceLightPollution,
        lightPollutionStrength: cli.lightPollutionStrength,
        enhanceStars: cli.enhanceStars,
        starEnhancementStrength: cli.starEnhancementStrength,
        sigma: cli.sigma,
        linearMaster: cli.linearMaster
    )

    let result = try stackImages(cli.images, options: options) { message, fraction in
        print(String(format: "%6.1f%% %@", fraction * 100, message))
        fflush(stdout)
    }
    print("Saving \(output.path)")
    fflush(stdout)
    try saveImage(result.image, to: output, options: SaveOptions(tiffDepth: cli.tiffDepth, clip: !cli.linearMaster))
    if let writeSkyMask = cli.writeSkyMask, let skyMask = result.skyMask {
        try saveSkyMask(skyMask, to: writeSkyMask)
        print("Saved sky mask \(writeSkyMask.path)")
    }
    print("Saved \(output.path)")
    print("Alignment shifts:")
    for item in result.alignments {
        print(String(format: "  %@: dy=%+d, dx=%+d, peak=%.4f", item.path.lastPathComponent, item.dy, item.dx, item.peak))
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    printUsage()
    exit(1)
}
