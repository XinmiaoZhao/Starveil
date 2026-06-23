# PROGRESS.md

This file tracks implementation progress and near-term roadmap. User setup
instructions belong in `README.md`; contributor rules belong in `AGENTS.md`.

## Public Sequator Workflow Notes

From the official Sequator site and manual:

- It stacks multiple star images by tracking and aligning stars.
- It supports dark/noise frames, flat/vignetting frames, TIFF/JPEG output,
  star-aligned stacking, star-trail mode, sky-region masks, auto brightness,
  HDR output, dynamic-noise reduction, distortion correction, light-pollution
  reduction, star enhancement, merge-pixels, and time-lapse batches.
- The official download page states Sequator currently supports Windows only.
- Sequator is not open source and is marked all rights reserved, so this project
  is an independent implementation rather than a port.

Sources:

- https://sites.google.com/view/sequator/
- https://sites.google.com/view/sequator/manual
- https://sites.google.com/view/sequator/download
- https://sites.google.com/view/sequator/qa

## Completed in Milestone 0.1

- Created Python package structure under `src/mysequator`.
- Added conda environment definition.
- Added Tkinter desktop GUI.
- Added command-line entry point.
- Added macOS `.app` launcher wrapper that uses the local `./.conda` env.
- Implemented image loading and saving for TIFF/JPEG/PNG/BMP.
- Implemented RAW camera input through conda-forge `rawpy`/LibRaw.
- Implemented dark-frame median subtraction.
- Implemented flat-frame median correction.
- Implemented phase-correlation translation alignment.
- Implemented non-wrapping image translation with validity masks.
- Implemented mean, sigma-clipped mean, and star-trail max composition modes.
- Implemented basic auto brightness, HDR stretch, broad light-pollution
  subtraction, and mild star enhancement.
- Added synthetic unit tests for alignment and pipeline behavior.

## Completed in Milestone 0.2

- Added a SwiftPM project with `MySequatorCore`, `MySequatorApp`,
  `mysequator-swift`, `MySequatorCoreTestRunner`, and `MySequatorCoreTests`.
- Reimplemented the core engine in Swift using `FloatRGBImage` linear RGB data.
- Added C support shims for LibRaw RAW decoding, libtiff TIFF I/O, and
  Accelerate-backed 2D phase-correlation alignment.
- Implemented Swift dark/flat calibration, non-wrapping translation masks,
  mean, sigma-clipped mean, and star-trail max composition.
- Implemented Swift auto stretch, HDR stretch, broad light-pollution reduction,
  and mild star enhancement.
- Added Swift 16-bit TIFF, 32-bit float TIFF, JPEG, and PNG output.
- Added a Swift CLI, including `--linear-master` and `--tiff-depth float32` for
  PixInsight-oriented linear masters.
- Added a first SwiftUI desktop app matching the existing Python/Tk workflow.
- Kept the Python implementation as a reference and regression comparison path.

## Verification

- Created the local conda environment at `./.conda`.
- Added a root-level import bridge package so `python -m mysequator...` resolves
  the `src/` layout from the project root without pip registration.
- Installed `rawpy` through conda for RAW camera input.
- Installed `tifffile` through conda for 16-bit RGB TIFF support.
- Ran `conda run -p ./.conda python -m pytest`: 7 tests passed.
- Ran `conda run -p ./.conda python -m mysequator --help` to verify
  the CLI entry point loads.
- Ran `conda run -p ./.conda python -c "import rawpy; print(rawpy.__version__)"`
  to verify RAW support is importable.
- Ran a TIFF smoke test confirming RGB values round-trip through `save_image`
  and `load_image`.
- Verified Xcode 26.5 is selected with `xcodebuild -version`.
- Ran `swift test`: 9 Swift XCTest tests passed.
- Ran `swift run MySequatorCoreTestRunner`: 9 standalone Swift smoke tests
  passed.
- Ran `swift run mysequator-swift --help` to verify the Swift CLI loads.
- Ran `swift build --product MySequatorApp` to verify the SwiftUI app builds.
- Fixed RAW workflow regressions found with three Sony A7C II 14mm ARW test
  frames:
  - GUI preview now uses ImageIO thumbnails with an in-memory cache instead of
    full linear RAW decoding on every selection change.
  - The stack pipeline reuses the already decoded base frame instead of loading
    it twice.
  - `MySequatorCore` is optimized even in debug SwiftPM builds, and the C shim
    is compiled with `-O3`, avoiding huge debug-mode slowdowns on full-frame
    RAW arrays.
  - Mean and star-trail accumulation use optimized C loops instead of Swift
    debug loops over tens of millions of pixels.
  - Alignment now tries star-point translation matching before falling back to
    whole-frame phase correlation, so wide-angle sky+ground frames no longer
    bias to zero shift.
  - Verified the A7C II test stack reports shifts `DSC05766: dy=-2 dx=+4`,
    `DSC05767: dy=0 dx=0`, and `DSC05768: dy=+2 dx=-4`.
- Fixed SwiftUI file dialogs to present as app/window-modal panels after
  explicit app activation, avoiding keyboard-focus failures in open/save
  dialogs launched from the SwiftPM app.

## Completed in Milestone 0.3

- Added Swift sky/ground scene composition modes:
  - `fullFrame` preserves the existing full-frame behavior.
  - `skyFreezeGround` stacks the star-aligned sky and keeps the base-frame
    ground fixed.
  - `skyAndGround` stacks the star-aligned sky and separately stacks the
    unshifted ground.
- Added `SkyMask`, `SkyMaskOptions`, mask import/export, inward sky-side
  feathering, and guard-pixel seam protection.
- Added a conservative `ImageTransform` abstraction with translation and
  similarity-transform support. Star matching now prefers stars inside the sky
  mask for sky/ground modes.
- Added SwiftUI sky-mask workflow: scene picker, auto mask, import/export,
  overlay, brush, erase, clear, invert, guard, and feather controls.
- Added CLI options `--scene`, `--sky-mask`, `--write-sky-mask`,
  `--sky-guard`, and `--mask-feather`.
- Added Swift XCTest coverage for sky mask round-trip, inward feathering,
  transform warp validity, sky-freeze-ground composition, sky/ground stacking,
  and rejecting `trails` in sky/ground scene modes.
- Verified with the three Sony A7C II 14mm ARW test frames:
  - `sky-freeze-ground` completed and exported an automatic sky mask.
  - `sky-ground` completed using the exported mask.
  - Both modes reported stable sky alignments around `DSC05766: dy=-3 dx=+3`
    and `DSC05768: dy=+3 dx=-2`.

## Completed in Milestone 0.4

- Added edge-aware sky-mask refinement for sky/ground scene modes.
  - Refinement works near the sky/ground seam and pulls dark bottom-connected
    foreground details, such as tree branches, ridges, and building edges, into
    the ground mask.
  - The existing guard-pixel and feather controls still decide the final blend
    ramp after the hard mask has been refined.
- Added `SkyMaskOptions.refineEdges`, `boundaryProtectionPixels`, and
  `darkForegroundPercentile`.
- Enabled refinement by default for generated and imported masks in
  `skyFreezeGround` and `skyAndGround`; users can disable it when they want to
  trust an external mask exactly.
- Added SwiftUI controls for edge refinement and boundary protection, plus a
  manual Refine action for imported or edited masks.
- Added CLI options `--no-refine-sky-mask` and `--boundary-protection`.
- Added synthetic XCTest coverage for:
  - bottom-connected dark foreground being absorbed into the ground mask,
  - isolated dark sky patches staying sky,
  - disabled refinement preserving the original mask,
  - refined masks preserving foreground edges during sky-freeze-ground stacking.
- The refinement design references the user-provided `SHIGUREStacker-source`
  edge-protection and bottom-connectivity ideas. It remains independent of
  Sequator source code, assets, binaries, and private behavior.

## Completed in Milestone 0.5

- Added `AlignmentModel` with conservative and wide-angle modes.
- Implemented an optional second-order polynomial inverse warp for wide-angle
  star alignment when the star matcher finds enough inliers.
- Kept the conservative similarity/translation path as the default alignment
  behavior.
- Added CLI and SwiftUI alignment controls:
  - `--alignment conservative|wide-angle`
  - GUI `Alignment` picker
- Added synthetic XCTest coverage proving the wide-angle path can select a
  polynomial warp on distorted star fields.

## Completed in Milestone 0.6

- Added float FITS output for `.fit`, `.fits`, and `.fts` paths.
  - The writer emits a 32-bit big-endian RGB FITS cube suitable for linear
    astro post-processing workflows.
- Allowed star-trail composition in `skyFreezeGround` mode. The sky is no
  longer aligned in this mode, preserving trails while keeping the ground fixed.
- Kept `trails` disabled for `skyAndGround`, where separate sky/ground
  accumulation still needs a dedicated design.
- Added XCTest coverage for FITS header/data layout and sky-freeze-ground
  trails validation.

## Completed in Milestone 0.7

- Added first-pass RAW processing controls:
  - `RawProcessingOptions.whiteBalanceMode`
  - `RawProcessingOptions.noAutoBrightness`
  - `RawProcessingOptions.highlightMode`
  - `RawProcessingOptions.userBlackLevel`
- Added a LibRaw C shim entry point that accepts those RAW decode options while
  preserving the previous default behavior: camera white balance, no automatic
  brightening, clipped highlights, and camera/default black level.
- Passed RAW options through dark/flat calibration, base loading, all stack
  frame loads, and GUI auto/refine sky-mask image loads.
- Added CLI options:
  - `--raw-white-balance camera|auto|none`
  - `--raw-auto-bright`
  - `--no-raw-auto-bright`
  - `--raw-highlight clip|unclip|blend|rebuild`
  - `--raw-black-level VALUE`
- Added SwiftUI RAW controls for white balance, highlight handling, LibRaw auto
  brightness, and black level.
- Added a progress callback message with an estimated working-memory footprint
  for the current stack dimensions, frame count, composition mode, and scene
  mode.
- Added XCTest coverage for RAW defaults and memory-estimate scaling.

## Desktop App Packaging

- Added a user-facing macOS app identity named **Starveil** while keeping the
  internal SwiftPM product names stable.
- Generated a Starveil app icon with the built-in image-generation model and
  stored the project asset under `Resources/`.
- Added `scripts/install_starveil_app.sh` to build the release SwiftUI app,
  package it as `Starveil.app`, install it to `~/Applications` for Launchpad,
  and register it with Launch Services.
- The installer preserves any previous Launchpad install under
  `AppBackups/PreviousLaunchpadBuild-YYYYMMDD-HHMMSS.app`. Backups are not
  named `Starveil.app`, and `AppBackups/` is ignored by Git.

## Known Limitations

- Alignment handles translation, conservative similarity transforms, and an
  optional second-order polynomial wide-angle model. It does not yet solve local
  mesh warps, lens-profile-aware warps, projection changes, or
  atmospheric-refraction effects.
- Swift phase correlation resizes the working luminance images to power-of-two
  dimensions for Accelerate FFT support.
- Automatic sky masks now include dark connected foreground edge refinement,
  but highly complex horizons, trees, and buildings can still require manual
  brush correction or an imported mask.
- Star-trail composition works for full-frame and sky-freeze-ground modes, but
  not for separate sky/ground stacking.
- RAW controls expose first-pass LibRaw decode parameters only. They do not yet
  include camera-profile management, per-channel custom white balance, or
  demosaic algorithm selection.
- XISF import is not implemented; convert XISF to 16-bit TIFF in PixInsight.
- Time-lapse batch output is not implemented.
- Memory use is now estimated and reported, but the sigma stacker still keeps
  frame data in memory instead of using chunked/streaming accumulation.

## Next Milestones

1. Add local mesh or lens-aware sky alignment for ultra-wide lenses and longer
   sequences.
2. Add chunked/streaming accumulation for lower memory use on long RAW
   sequences.
3. Extend star-trail support to separate sky/ground stacking if the desired
   compositing behavior is defined.
4. Add time-lapse batch mode.
5. Build a notarized distributable `.app` or `.dmg` package once the workflow
   stabilizes.
