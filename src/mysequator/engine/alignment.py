from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .io import resize_float


@dataclass(frozen=True, slots=True)
class Shift:
    dy: int
    dx: int
    peak: float


def _prepare_for_phase_correlation(image: np.ndarray, max_dim: int) -> tuple[np.ndarray, float]:
    h, w = image.shape
    scale = 1.0
    work = image.astype(np.float32, copy=False)

    longest = max(h, w)
    if longest > max_dim:
        scale = max_dim / float(longest)
        new_w = max(32, int(round(w * scale)))
        new_h = max(32, int(round(h * scale)))
        work = resize_float(work, (new_w, new_h))

    work = work.astype(np.float32, copy=False)
    work = work - np.median(work)
    spread = np.percentile(np.abs(work), 95)
    if spread > 0:
        work = np.clip(work / spread, -1.0, 1.0)

    wy = np.hanning(work.shape[0]).astype(np.float32)
    wx = np.hanning(work.shape[1]).astype(np.float32)
    work = work * wy[:, None] * wx[None, :]
    return work, scale


def estimate_translation(reference: np.ndarray, moving: np.ndarray, max_dim: int = 1200) -> Shift:
    """Estimate integer translation needed to align moving onto reference."""
    if reference.shape != moving.shape:
        raise ValueError("Reference and moving images must have the same shape.")

    ref, ref_scale = _prepare_for_phase_correlation(reference, max_dim)
    mov, mov_scale = _prepare_for_phase_correlation(moving, max_dim)
    if ref.shape != mov.shape or abs(ref_scale - mov_scale) > 1e-6:
        raise ValueError("Prepared reference and moving images must have the same shape.")

    eps = np.finfo(np.float32).eps
    ref_fft = np.fft.fft2(ref)
    mov_fft = np.fft.fft2(mov)
    cross_power = ref_fft * np.conj(mov_fft)
    cross_power /= np.maximum(np.abs(cross_power), eps)
    correlation = np.fft.ifft2(cross_power).real

    peak_index = np.unravel_index(int(np.argmax(correlation)), correlation.shape)
    peak_y, peak_x = int(peak_index[0]), int(peak_index[1])
    h, w = correlation.shape
    if peak_y > h // 2:
        peak_y -= h
    if peak_x > w // 2:
        peak_x -= w

    inv_scale = 1.0 / ref_scale
    return Shift(
        dy=int(round(peak_y * inv_scale)),
        dx=int(round(peak_x * inv_scale)),
        peak=float(correlation[peak_index]),
    )


def translate_with_mask(image: np.ndarray, dy: int, dx: int) -> tuple[np.ndarray, np.ndarray]:
    """Translate an image without wraparound and return valid-pixel mask."""
    h, w = image.shape[:2]
    shifted = np.zeros_like(image)
    mask = np.zeros((h, w), dtype=bool)

    src_y0 = max(0, -dy)
    src_y1 = min(h, h - dy)
    dst_y0 = max(0, dy)
    dst_y1 = min(h, h + dy)
    src_x0 = max(0, -dx)
    src_x1 = min(w, w - dx)
    dst_x0 = max(0, dx)
    dst_x1 = min(w, w + dx)

    if src_y1 <= src_y0 or src_x1 <= src_x0:
        return shifted, mask

    shifted[dst_y0:dst_y1, dst_x0:dst_x1] = image[src_y0:src_y1, src_x0:src_x1]
    mask[dst_y0:dst_y1, dst_x0:dst_x1] = True
    return shifted, mask
