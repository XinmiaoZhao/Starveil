from __future__ import annotations

from pathlib import Path

import numpy as np

from .io import load_image


def median_frame(paths: list[Path]) -> np.ndarray | None:
    if not paths:
        return None
    frames = [load_image(path) for path in paths]
    _assert_same_shape(frames)
    return np.median(np.stack(frames, axis=0), axis=0).astype(np.float32)


def calibrate(image: np.ndarray, dark: np.ndarray | None, flat: np.ndarray | None) -> np.ndarray:
    out = image.astype(np.float32, copy=True)
    if dark is not None:
        _assert_shape(out, dark)
        out = np.maximum(out - dark, 0.0)

    if flat is not None:
        _assert_shape(out, flat)
        flat_safe = np.maximum(flat, 1e-4)
        channel_median = np.median(flat_safe.reshape(-1, flat_safe.shape[-1]), axis=0)
        out = out * channel_median.reshape(1, 1, -1) / flat_safe

    return np.clip(out, 0.0, 1.0)


def _assert_same_shape(frames: list[np.ndarray]) -> None:
    first_shape = frames[0].shape
    for frame in frames[1:]:
        _assert_shape(frames[0], frame)
    if len(first_shape) != 3 or first_shape[2] != 3:
        raise ValueError("Images must be RGB.")


def _assert_shape(a: np.ndarray, b: np.ndarray) -> None:
    if a.shape != b.shape:
        raise ValueError(f"Image shape mismatch: {a.shape} != {b.shape}")
