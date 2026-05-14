# MySequator

MySequator is an independent macOS star-field stacking app inspired by the
publicly documented workflow of Sequator. It does not use Sequator source code,
assets, binaries, or reverse engineered behavior.

The first milestone focuses on the core macOS workflow:

- import multiple star-field images
- optional dark-frame subtraction and flat-frame correction
- estimate star-field translation with phase correlation
- stack aligned frames with mean, sigma-clipped mean, or star-trail max mode
- read RAW camera files through LibRaw/rawpy, plus TIFF/JPEG/PNG/BMP
- export 16-bit TIFF or 8-bit JPEG/PNG
- keep output linear by default, with optional auto or HDR stretch
- run from a Tkinter desktop GUI or a command-line interface

Advanced Sequator-style features such as freeze-ground compositing, irregular
sky masks, XISF import, wide-angle distortion correction, and batch time-lapse
output are tracked in `PROGRESS.md`.

## Setup with conda

```bash
conda env create -p ./.conda -f environment.yml
```

If the environment already exists:

```bash
conda env update -p ./.conda -f environment.yml --prune
```

## Run the GUI

```bash
conda run -p ./.conda python run_gui.py
```

This also works from the project root:

```bash
conda run -p ./.conda python -m mysequator.ui.app
```

You can also double-click `MySequator.app` after the conda environment has been
created in `./.conda`.

## Run from CLI

```bash
conda run -p ./.conda python run_cli.py \
  --output stacked.tiff \
  --mode sigma \
  --stretch none \
  image_001.tif image_002.tif image_003.tif image_004.tif
```

From the project root, you can also use `python -m mysequator` in place of
`python run_cli.py`.

Useful options:

- `--base PATH`: choose the base frame; otherwise the middle file is used
- `--dark PATH`: add one or more dark frames
- `--flat PATH`: add one or more flat frames
- `--mode mean|sigma|trails`: choose the composition mode
- `--stretch none|auto|hdr`: choose linear output or a display stretch
- `--reduce-light-pollution`: subtract a broad low-frequency background
- `--enhance-stars`: apply a mild star/detail boost

RAW extensions supported through `rawpy` include common DSLR/mirrorless formats
such as `.arw`, `.cr2`, `.cr3`, `.dng`, `.nef`, `.orf`, `.raf`, and `.rw2`.

XISF is not a direct input format in this milestone. Use PixInsight to convert
XISF files to 16-bit TIFF before stacking.

## Current limitations

- Alignment is translational. It works best for short tripod sequences and
  moderate field of view images. Long sequences, very wide lenses, or strong
  field rotation need a future similarity/mesh warp module.
- RAW loading uses LibRaw/rawpy with camera white balance, no automatic
  brightening, 16-bit output, and linear gamma.
- XISF files should be converted to 16-bit TIFF in PixInsight first.
- Freeze-ground compositing is not implemented yet.

## Project docs

- `README.md`: user-facing setup, run commands, and current usage limits.
- `AGENTS.md`: development rules for future coding agents and contributors.
- `PROGRESS.md`: implementation status, decisions made, and next milestones.
