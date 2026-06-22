# MySequator

MySequator is an independent macOS star-field stacking app inspired by the
publicly documented workflow of Sequator. It does not use Sequator source code,
assets, binaries, or reverse engineered behavior.

The main implementation is now a Swift + SwiftUI SwiftPM project. The previous
Python/Tk implementation remains in the repository as a reference implementation
and regression comparison target.

The first milestone focuses on the core macOS workflow:

- import multiple star-field images
- optional dark-frame subtraction and flat-frame correction
- estimate star-field translation/similarity transforms from star points, with
  phase-correlation fallback
- stack aligned frames with mean, sigma-clipped mean, or star-trail max mode
- stack only the sky while freezing the ground, or stack sky and ground in
  separate coordinate systems
- generate, import, export, and brush-edit a sky mask in the SwiftUI GUI
- read RAW camera files through LibRaw, plus TIFF/JPEG/PNG/BMP
- export 16-bit TIFF, 32-bit float TIFF, or 8-bit JPEG/PNG
- keep output linear by default, with optional auto or HDR stretch
- run from a SwiftUI desktop GUI or a command-line interface

Advanced Sequator-style features such as high-quality automatic segmentation,
XISF import, wide-angle distortion correction, and batch time-lapse output are
tracked in `PROGRESS.md`.

## Setup

Install Xcode and select it as the active developer directory:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Create the local conda environment. Swift links against the conda-provided
LibRaw and libtiff libraries for RAW and TIFF support.

```bash
conda env create -p ./.conda -f environment.yml
```

If the environment already exists:

```bash
conda env update -p ./.conda -f environment.yml --prune
```

## Run the SwiftUI GUI

```bash
swift run MySequatorApp
```

For repeated large RAW stacks, a release run is still recommended:

```bash
swift run -c release MySequatorApp
```

## Run the Swift CLI

```bash
swift run mysequator-swift -- \
  --output stacked.tiff \
  --mode sigma \
  --stretch none \
  image_001.tif image_002.tif image_003.tif image_004.tif
```

For a PixInsight-oriented linear master:

```bash
swift run mysequator-swift -- \
  --output stacked-linear.tiff \
  --linear-master \
  --tiff-depth float32 \
  image_001.cr3 image_002.cr3 image_003.cr3 image_004.cr3
```

Useful options:

- `--base PATH`: choose the base frame; otherwise the middle file is used
- `--dark PATH`: add one or more dark frames
- `--flat PATH`: add one or more flat frames
- `--mode mean|sigma|trails`: choose the composition mode
- `--scene full|sky-freeze-ground|sky-ground`: choose full-frame stacking,
  sky stacking with frozen ground, or separate sky/ground stacking
- `--sky-mask PATH`: import a grayscale mask where white is sky
- `--write-sky-mask PATH`: write the generated or imported sky mask
- `--sky-guard PX`: exclude a hard band on the sky side of the seam
- `--mask-feather PX`: feather the sky/ground seam inward into the sky
- `--stretch none|auto|hdr`: choose linear output or a display stretch
- `--linear-master`: force linear processing and 32-bit float TIFF output
- `--tiff-depth uint16|float32`: choose TIFF output depth
- `--reduce-light-pollution`: subtract a broad low-frequency background
- `--enhance-stars`: apply a mild star/detail boost

Example sky-only stack with frozen ground:

```bash
swift run -c release mysequator-swift -- \
  --output stacked-sky-freeze.tiff \
  --scene sky-freeze-ground \
  --mode sigma \
  --write-sky-mask sky-mask.png \
  image_001.arw image_002.arw image_003.arw
```

## Test

```bash
swift test
swift run MySequatorCoreTestRunner
conda run -p ./.conda python -m pytest
```

The standalone Swift test runner is a plain executable smoke test; the full
Swift coverage, including sky/ground tests, lives in XCTest.

## Python Reference Implementation

The older Python GUI still works as a reference path:

```bash
conda run -p ./.conda python run_gui.py
```

This also works from the project root:

```bash
conda run -p ./.conda python -m mysequator.ui.app
```

You can also double-click `MySequator.app` after the conda environment has been
created in `./.conda`.

The Python CLI remains available:

```bash
conda run -p ./.conda python run_cli.py \
  --output stacked.tiff \
  --mode sigma \
  --stretch none \
  image_001.tif image_002.tif image_003.tif image_004.tif
```

From the project root, you can also use `python -m mysequator` in place of
`python run_cli.py`.

RAW extensions supported through LibRaw include common DSLR/mirrorless formats
such as `.arw`, `.cr2`, `.cr3`, `.dng`, `.nef`, `.orf`, `.raf`, and `.rw2`.

XISF is not a direct input format in this milestone. Use PixInsight to convert
XISF files to 16-bit TIFF before stacking.

## Current limitations

- Alignment supports translation and a conservative similarity transform.
  Long sequences, very wide lenses, or strong field rotation still need a
  future mesh/local warp module.
- Automatic sky masks are a first-pass estimate. Complex horizons, trees, and
  buildings should be corrected with the GUI brush/erase tools or an imported
  mask.
- RAW loading uses LibRaw with camera white balance, no automatic brightening,
  16-bit decode, and linear gamma before the internal float pipeline.
- Lightroom can edit exported TIFF files, but those files do not re-enter
  Adobe's original RAW processing pipeline.
- XISF files should be converted to 16-bit TIFF in PixInsight first.
- Star-trail mode is currently full-frame only; it is disabled for sky/ground
  scene modes.

## Project docs

- `README.md`: user-facing setup, run commands, and current usage limits.
- `AGENTS.md`: development rules for future coding agents and contributors.
- `PROGRESS.md`: implementation status, decisions made, and next milestones.
