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
- Implemented dark-frame median subtraction.
- Implemented flat-frame median correction.
- Implemented phase-correlation translation alignment.
- Implemented non-wrapping image translation with validity masks.
- Implemented mean, sigma-clipped mean, and star-trail max composition modes.
- Implemented basic auto brightness, HDR stretch, broad light-pollution
  subtraction, and mild star enhancement.
- Added synthetic unit tests for alignment and pipeline behavior.

## Verification

- Created the local conda environment at `./.conda`.
- Installed `tifffile` through conda for 16-bit RGB TIFF support.
- Ran `PYTHONPATH=src conda run -p ./.conda python -m pytest`: 4 tests passed.
- Ran `PYTHONPATH=src conda run -p ./.conda python -m mysequator --help` to verify
  the CLI entry point loads.
- Ran a TIFF smoke test confirming RGB values round-trip through `save_image`
  and `load_image`.

## Known Limitations

- Alignment handles translation only. It does not yet solve rotation, scale,
  lens distortion, projection distortion, or atmospheric-refraction effects.
- Freeze-ground foreground/sky compositing is not implemented.
- Sky mask drawing is not implemented.
- RAW decoding is not implemented.
- Time-lapse batch output is not implemented.
- Memory use is simple and may be high for many large 16-bit frames.

## Next Milestones

1. Add similarity-transform alignment using detected star control points and
   RANSAC.
2. Add a sky-mask editor in the GUI and pass masks into star detection,
   light-pollution reduction, and future freeze-ground logic.
3. Add optional RAW decoding with conda-forge `rawpy`.
4. Add chunked/streaming accumulation for lower memory use.
5. Add freeze-ground compositing as a separate engine module.
6. Add time-lapse batch mode.
7. Build a signed/distributable `.app` package once the workflow stabilizes.
