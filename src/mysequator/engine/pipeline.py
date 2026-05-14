from __future__ import annotations

from pathlib import Path

import numpy as np

from .alignment import estimate_translation, translate_with_mask
from .calibration import calibrate, median_frame
from .io import load_image, luminance
from .models import AlignmentInfo, ProgressCallback, StackOptions, StackResult
from .postprocess import apply_auto_brightness, apply_hdr_stretch, enhance_stars, reduce_light_pollution


def stack_images(
    image_paths: list[Path],
    options: StackOptions | None = None,
    progress: ProgressCallback | None = None,
) -> StackResult:
    options = options or StackOptions()
    paths = [Path(path) for path in image_paths]
    if len(paths) < 1:
        raise ValueError("Add at least one star image.")

    base_path = Path(options.base_path) if options.base_path else paths[len(paths) // 2]
    if base_path not in paths:
        paths = [base_path, *paths]

    _report(progress, "Preparing calibration frames", 0.02)
    dark = median_frame([Path(path) for path in options.dark_paths])
    flat = median_frame([Path(path) for path in options.flat_paths])

    _report(progress, f"Loading base frame {base_path.name}", 0.08)
    base = calibrate(load_image(base_path), dark, flat)
    base_gray = luminance(base)

    aligned_frames: list[np.ndarray] = []
    masks: list[np.ndarray] = []
    alignments: list[AlignmentInfo] = []

    total = len(paths)
    for index, path in enumerate(paths):
        fraction_base = 0.1 + 0.68 * (index / max(total, 1))
        _report(progress, f"Aligning {path.name}", fraction_base)
        frame = calibrate(load_image(path), dark, flat)
        if frame.shape != base.shape:
            raise ValueError(f"{path.name} has shape {frame.shape}, expected {base.shape}.")

        if path == base_path:
            dy = dx = 0
            peak = 1.0
            aligned = frame
            mask = np.ones(frame.shape[:2], dtype=bool)
        elif options.mode == "trails":
            dy = dx = 0
            peak = 1.0
            aligned = frame
            mask = np.ones(frame.shape[:2], dtype=bool)
        else:
            shift = estimate_translation(base_gray, luminance(frame), max_dim=options.alignment_max_dim)
            dy, dx, peak = shift.dy, shift.dx, shift.peak
            aligned, mask = translate_with_mask(frame, dy, dx)

        aligned_frames.append(aligned)
        masks.append(mask)
        alignments.append(AlignmentInfo(path=path, dy=dy, dx=dx, peak=peak))

    _report(progress, "Stacking aligned frames", 0.82)
    stacked = _compose(aligned_frames, masks, options)

    _report(progress, "Applying post-processing", 0.9)
    if options.reduce_light_pollution:
        stacked = reduce_light_pollution(stacked, options.light_pollution_strength)
    if options.enhance_stars:
        stacked = enhance_stars(stacked, options.star_enhancement_strength)
    stretch = options.output_stretch
    if options.hdr:
        stretch = "hdr"
    elif options.auto_brightness:
        stretch = "auto"

    if stretch == "hdr":
        stacked = apply_hdr_stretch(stacked)
    elif stretch == "auto":
        stacked = apply_auto_brightness(stacked)
    elif stretch != "none":
        raise ValueError(f"Unknown output stretch mode: {stretch}")

    _report(progress, "Done", 1.0)
    return StackResult(image=np.clip(stacked, 0.0, 1.0), base_path=base_path, alignments=alignments)


def _compose(frames: list[np.ndarray], masks: list[np.ndarray], options: StackOptions) -> np.ndarray:
    if options.mode == "trails":
        return np.max(np.stack(frames, axis=0), axis=0)

    if options.mode == "mean" or len(frames) < 4:
        return _masked_mean(frames, masks)

    if options.mode == "sigma":
        return _sigma_clipped_mean(frames, masks, options.sigma)

    raise ValueError(f"Unknown composition mode: {options.mode}")


def _masked_mean(frames: list[np.ndarray], masks: list[np.ndarray]) -> np.ndarray:
    accumulator = np.zeros_like(frames[0], dtype=np.float64)
    weights = np.zeros(frames[0].shape[:2] + (1,), dtype=np.float64)
    for frame, mask in zip(frames, masks):
        weight = mask[:, :, None].astype(np.float64)
        accumulator += frame.astype(np.float64) * weight
        weights += weight
    return (accumulator / np.maximum(weights, 1.0)).astype(np.float32)


def _sigma_clipped_mean(frames: list[np.ndarray], masks: list[np.ndarray], sigma: float) -> np.ndarray:
    stack = np.stack(frames, axis=0).astype(np.float32)
    mask_stack = np.stack(masks, axis=0)[:, :, :, None]
    valid = np.broadcast_to(mask_stack, stack.shape)
    stack_nan = np.where(valid, stack, np.nan)

    median = np.nanmedian(stack_nan, axis=0)
    deviation = np.abs(stack_nan - median)
    mad = np.nanmedian(deviation, axis=0)
    robust_sigma = np.maximum(1.4826 * mad, 1e-5)
    keep = deviation <= (sigma * robust_sigma)
    clipped = np.where(valid & keep, stack, np.nan)
    mean = np.nanmean(clipped, axis=0)

    fallback = _masked_mean(frames, masks)
    return np.where(np.isfinite(mean), mean, fallback).astype(np.float32)


def _report(progress: ProgressCallback | None, message: str, fraction: float) -> None:
    if progress:
        progress(message, max(0.0, min(1.0, fraction)))
