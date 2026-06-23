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

## Collaboration and Repository Status

- The shared GitHub repository is
  `git@github.com:XinmiaoZhao/Starveil.git`.
- Future development should start with `git pull --ff-only` to incorporate
  remote changes before editing.
- After implementation and verification, changes should normally be committed
  and pushed directly unless tests fail, the work is incomplete, or review is
  explicitly requested.
- Local-only datasets, generated stacks, app backups, build outputs, ignored
  `archive/` folders, and the user-provided `SHIGUREStacker-source/` reference
  drop are ignored by Git.

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
- Kept the conservative similarity/translation path as the default core and CLI
  alignment behavior.
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

## Post-v0.7 Mask and UI Fixes

- Fixed sky/ground boundary bleed in non-integer sky warps. Masked bilinear
  sampling now rejects an output pixel unless all four source taps are inside
  the sky source mask, preventing ground pixels from being interpolated into
  aligned sky near the seam.
- Added an XCTest regression for the masked bilinear edge case where the nearest
  source pixel is sky but a neighboring interpolation tap is ground.
- Updated the Starveil GUI default alignment model to `wideAngle` after testing
  showed conservative similarity alignment can stretch edge stars on broad RAW
  landscape sequences. The conservative model remains selectable in Settings,
  and the core/CLI default stays conservative for compatibility.
- Improved mask editing in the SwiftUI preview canvas:
  - visible brush footprint under the pointer,
  - continuous interpolated strokes for fast drags,
  - Option-drag temporary ground erasing,
  - mask undo/redo with Cmd-Z and Cmd-Shift-Z,
  - preview zoom with Cmd+=, Cmd+-, and Cmd+0.
- Removed the destructive `Auto Mask` action from the top toolbar and renamed
  the inspector action to `Generate Auto Mask`, so manual masks are less likely
  to be overwritten accidentally. Auto/import/refine/clear/invert and brush
  strokes are now undoable.

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
- Raised the SwiftUI app minimum to macOS 14 and rebuilt the Starveil UI around
  native `NavigationSplitView` plus a right-side Settings inspector.
- Moved the crowded left-column controls into collapsible inspector sections:
  Session, Stack, Output Advanced, RAW, Sky Mask, and Post-processing. The left
  sidebar now stays focused on image selection, calibration counts, progress,
  and status.

## Swift-Only Source Tree Cleanup

- Moved the old Python/Tk implementation, Python tests, Python packaging file,
  and old `MySequator.app` Python launcher into ignored local
  `archive/python-reference-v0.7/`.
- Removed Python reference tests from XCTest and the standalone Swift smoke
  runner. The active verification path is now Swift-only:
  - `swift test`
  - `swift run MySequatorCoreTestRunner`
- Simplified `environment.yml` to the conda-forge C libraries needed by Swift:
  LibRaw and libtiff.
- The GitHub repository now tracks the current Swift/SwiftUI implementation
  rather than carrying an obsolete Python application beside it. The archived
  Python code remains available locally when present and through Git history.

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

## Development Priorities After Milestone 0.7

Starveil has moved beyond the basic "can stack images" stage. The next phase
should focus on making it a reliable linear landscape astrophotography stacking
preprocessor for PixInsight, Lightroom, Photoshop, and similar workflows.

The target workflows are:

- Workflow A: Lightroom-rendered TIFF input.
  RAW -> Lightroom light RAW rendering -> 16-bit TIFF -> Starveil sky/ground
  stacking -> Lightroom or Photoshop final edit. This is broadly usable now.
- Workflow B: strict linear RAW stacking.
  RAW -> Starveil strict linear RAW stacking -> sky/ground composition ->
  32-bit TIFF or FITS master -> PixInsight basic stretch -> Lightroom final
  photographic edit. This is partially usable today and needs a stricter v0.8
  contract.
- Workflow C: professional layered output.
  RAW -> Starveil strict linear stacking -> exported sky stack, ground stack,
  hard mask, soft mask, edge mask, and blended preview -> dedicated sky/ground
  processing -> manual blend. This is the highest-quality long-term workflow
  and is not complete yet.

### Milestone 0.8: Strict Linear Master and Professional Layers

Goal: make Starveil produce trustworthy linear masters and professional layer
outputs for PixInsight, Lightroom, and Photoshop workflows.

Required work:

- Add a strict linear master workflow, such as `--strict-linear` or
  `--workflow linear-master`.
- In strict linear mode, force-disable display-oriented processing: LibRaw auto
  brightness, auto stretch, HDR stretch, light-pollution reduction, star
  enhancement, gamma encoding, tone curves, JPEG/PNG-style rendering, and any
  hidden photographic transform.
- Allow only linear operations in strict mode: RAW black-level correction,
  white balance, demosaic, dark/flat calibration, linear alignment/warping,
  mean or sigma-clipped stacking, and mask-based sky/ground composition.
- Emit an explicit log message that strict linear mode is enabled and no gamma,
  tone curve, stretch, light-pollution reduction, or enhancement is applied.
- Add professional layered output, with CLI options such as `--write-layers`,
  `--output-sky`, `--output-ground`, `--output-hard-mask`,
  `--output-soft-mask`, `--output-edge-mask`, and `--output-blended`.
- Add GUI output modes for blended-only, professional layers, or both.
- For `skyFreezeGround`, export a star-aligned sky stack, base-frame ground,
  masks, and blended preview. For `skyAndGround`, export a star-aligned sky
  stack and unshifted ground stack in original coordinates.
- Export diagnostic masks: hard sky mask, soft/feathered alpha mask, and edge
  transition mask. Keep all masks pixel-aligned with output layers; prefer
  16-bit grayscale TIFF where feasible.
- Preserve linear-output integrity with 32-bit float TIFF/FITS defaults in
  strict mode, no gamma encoding, and clipping only when a selected output
  format requires it.
- Embed useful metadata where possible: Starveil version, workflow, scene mode,
  RAW decode choices, stack mode, alignment model, mask guard/feather values,
  `Linear=true`, `Gamma=none`, and `ToneCurve=none`.
- Add XCTest and CLI-level coverage for strict-mode option enforcement,
  layered sky/ground/mask output, soft-mask transition validity, edge-mask
  locality, and 32-bit float TIFF/FITS linear value preservation.
- Update user documentation for the three workflows and clearly state that
  strict linear output is intended for later stretching, not immediate visual
  appeal.

### Milestone 0.9: Sky/Ground Boundary Quality

Goal: reduce black edges, white halos, ghosting, blurred ridgelines,
tree-branch artifacts, and ground contamination near the horizon.

Required work:

- Improve edge-aware alpha blending so strong foreground edges favor the ground
  layer, smooth sky regions favor the sky layer, bottom-connected dark
  structures remain ground, and isolated dark sky patches remain sky.
- Add boundary diagnostics for hard mask, soft mask, edge transition zone,
  refined foreground regions, sky-contamination warnings, and alignment
  residual overlays when available.
- Add sky-contamination checks near the boundary. Warn on unusually high
  boundary variance, remaining bottom-connected foreground in the sky mask,
  guard pixels that may be too small, or feather widths that look too wide or
  too narrow.
- Continue improving the manual correction workflow with zoomable preview,
  original/mask/overlay/boundary-zone toggles, better brush/erase controls, and
  clearer hard-vs-soft mask display.

### Milestone 1.0: Long Sequences, Ultra-Wide Lenses, and Stability

Goal: make Starveil reliable for longer RAW sequences, ultra-wide Milky Way
lenses, and high-resolution modern cameras.

Required work:

- Add chunked or streaming accumulation: tile-based accumulation, streaming
  mean, streaming variance, two-pass sigma clipping, and a user-facing memory
  budget or memory-mode setting.
- Improve wide-angle alignment beyond the current optional second-order
  polynomial warp with local mesh, piecewise affine, grid-based, or later
  lens-profile-aware alignment.
- Constrain stronger sky warps to the sky mask; keep ground fixed or separately
  accumulated depending on scene mode.
- Add alignment diagnostics per frame: selected alignment model, matched star
  count, inlier count, RMS residual, max residual, and fallback reason.
- Add warnings for too few stars, too few inliers, wide-angle residual not
  improving over conservative alignment, large edge residuals, and possible
  local misalignment.
- Add automatic fallback from wide-angle to conservative alignment when the
  wide-angle fit is unreliable.
- Defer time-lapse batch mode until strict linear output, professional layers,
  boundary quality, alignment reliability, and memory stability are solid.

Do not prioritize one-click photographic filters, heavy built-in color grading,
or cosmetic effects before these workflow foundations are stable.
