# AGENTS.md

This file is for future coding agents and contributors working in this
repository. Keep user instructions in `README.md` and project status in
`PROGRESS.md`; do not duplicate those sections here.

## Project Boundaries

- MySequator is an independent implementation. Do not copy Sequator assets,
  binaries, source code, UI images, or reverse engineer private behavior.
- Use public descriptions only to understand workflows and expected feature
  categories.
- Prefer small, testable engine modules under `src/mysequator/engine`.
- Keep GUI code in `src/mysequator/ui`; do not mix image-processing logic into
  Tk event handlers.

## Dependency Rules

- Install dependencies with conda, not pip.
- Keep `environment.yml` as the source of truth for runtime and test
  dependencies.
- RAW support should be added as an optional conda-forge dependency, likely
- RAW support uses conda-forge `rawpy` and should stay isolated behind the image
  I/O interface.
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

- Run tests with:

```bash
conda run -p ./.conda pytest
```

- Add synthetic image tests for alignment and stacking changes.
- For GUI changes, keep manual verification notes in `PROGRESS.md`.
