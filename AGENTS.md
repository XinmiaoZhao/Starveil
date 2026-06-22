# AGENTS.md

This file is for future coding agents and contributors working in this
repository. Keep user instructions in `README.md` and project status in
`PROGRESS.md`; do not duplicate those sections here.

## Project Boundaries

- MySequator is an independent implementation. Do not copy Sequator assets,
  binaries, source code, UI images, or reverse engineer private behavior.
- Use public descriptions only to understand workflows and expected feature
  categories.
- Prefer small, testable engine modules under `Sources/MySequatorCore`.
- Keep SwiftUI GUI code in `Sources/MySequatorApp`; do not mix
  image-processing logic into view code.
- The Python implementation under `src/mysequator` is a reference path. Keep
  Python engine code under `src/mysequator/engine` and Python GUI code under
  `src/mysequator/ui` when touching that path.

## Dependency Rules

- Install dependencies with conda, not pip.
- Keep `environment.yml` as the source of truth for runtime and test
  dependencies.
- Swift RAW support uses conda-forge LibRaw through the C support shim and
  should stay isolated behind the image I/O interface.
- Python RAW support uses conda-forge `rawpy` and should stay isolated behind
  the Python image I/O interface.
- XISF support is intentionally deferred. Prefer robust TIFF workflows unless a
  full testable XISF reader is added.

## Engineering Priorities

- Preserve 16-bit data paths whenever possible.
- Prefer deterministic algorithms and focused tests over opaque GUI-only
  behavior.
- Keep memory use visible. Large astro frames can exhaust RAM quickly when
  stacked as `N x H x W x C` arrays.
- Add progress callbacks to long-running engine functions before wiring them
  into the GUI.

## Testing

- Run Swift tests with:

```bash
swift test
swift run MySequatorCoreTestRunner
```

- Run Python reference tests with:

```bash
conda run -p ./.conda python -m pytest
```

- Add synthetic image tests for alignment and stacking changes.
- For GUI changes, keep manual verification notes in `PROGRESS.md`.
