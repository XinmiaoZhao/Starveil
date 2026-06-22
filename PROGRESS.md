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

## Known Limitations

- Alignment handles translation and conservative similarity transforms. It does
  not yet solve lens distortion, projection distortion, local mesh warps, or
  atmospheric-refraction effects.
- Swift phase correlation resizes the working luminance images to power-of-two
  dimensions for Accelerate FFT support.
- Automatic sky masks are first-pass estimates. Complex horizons, trees, and
  buildings still require manual brush correction or an imported mask.
- Sky/ground scene modes do not support star-trail composition yet.
- XISF import is not implemented; convert XISF to 16-bit TIFF in PixInsight.
- Time-lapse batch output is not implemented.
- Memory use is simple and may be high for many large 16-bit frames.

## Next Milestones

1. Improve automatic sky segmentation with edge-aware horizon detection and
   better handling for trees/buildings.
2. Add local mesh or lens-aware sky alignment for ultra-wide lenses and longer
   sequences.
3. Add RAW-specific controls for white balance, highlight handling, and black
   level behavior.
4. Add chunked/streaming accumulation for lower memory use.
5. Add star-trail support for sky/ground scene modes.
6. Add time-lapse batch mode.
7. Build a signed/distributable `.app` package once the workflow stabilizes.
