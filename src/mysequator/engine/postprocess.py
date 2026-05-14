from __future__ import annotations

import numpy as np
from PIL import Image, ImageFilter

from .io import luminance


def apply_auto_brightness(image: np.ndarray, target_percentile: float = 99.7, target_value: float = 0.92) -> np.ndarray:
    value = float(np.percentile(luminance(image), target_percentile))
    if value <= 1e-6:
        return image
    scale = target_value / value
    return np.clip(image * scale, 0.0, 1.0)


def apply_hdr_stretch(image: np.ndarray) -> np.ndarray:
    lo = np.percentile(image.reshape(-1, image.shape[-1]), 0.2, axis=0)
    hi = np.percentile(image.reshape(-1, image.shape[-1]), 99.9, axis=0)
    span = np.maximum(hi - lo, 1e-5)
    return np.clip((image - lo.reshape(1, 1, -1)) / span.reshape(1, 1, -1), 0.0, 1.0)


def reduce_light_pollution(image: np.ndarray, strength: float = 0.45) -> np.ndarray:
    """Subtract a broad low-frequency color background estimate."""
    h, w = image.shape[:2]
    small_w = max(16, min(96, w // 24))
    small_h = max(16, min(96, h // 24))
    background = np.zeros_like(image)

    for channel in range(3):
        channel_u16 = np.round(np.clip(image[:, :, channel], 0.0, 1.0) * 65535).astype(np.uint16)
        pil = Image.fromarray(channel_u16, mode="I;16")
        low = pil.resize((small_w, small_h), resample=Image.BILINEAR)
        low = low.filter(ImageFilter.GaussianBlur(radius=2))
        high = low.resize((w, h), resample=Image.BICUBIC)
        background[:, :, channel] = np.asarray(high, dtype=np.float32) / 65535.0

    neutral = np.percentile(background.reshape(-1, 3), 5, axis=0).reshape(1, 1, 3)
    corrected = image - strength * (background - neutral)
    return np.clip(corrected, 0.0, 1.0)


def enhance_stars(image: np.ndarray, strength: float = 0.35) -> np.ndarray:
    """Mild unsharp-mask enhancement aimed at small bright details."""
    h, w = image.shape[:2]
    enhanced = np.empty_like(image)
    for channel in range(3):
        channel_u16 = np.round(np.clip(image[:, :, channel], 0.0, 1.0) * 65535).astype(np.uint16)
        pil = Image.fromarray(channel_u16, mode="I;16")
        blur = pil.filter(ImageFilter.GaussianBlur(radius=max(1.0, min(h, w) / 900.0)))
        base = np.asarray(pil, dtype=np.float32) / 65535.0
        smooth = np.asarray(blur, dtype=np.float32) / 65535.0
        detail = np.maximum(base - smooth, 0.0)
        enhanced[:, :, channel] = base + strength * detail
    return np.clip(enhanced, 0.0, 1.0)
