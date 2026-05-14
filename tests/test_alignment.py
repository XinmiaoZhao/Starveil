from __future__ import annotations

import numpy as np

from mysequator.engine.alignment import estimate_translation, translate_with_mask


def _stars(shape: tuple[int, int], points: list[tuple[int, int]]) -> np.ndarray:
    image = np.zeros(shape, dtype=np.float32)
    for y, x in points:
        image[y, x] = 1.0
        image[y - 1 : y + 2, x - 1 : x + 2] += 0.25
    return np.clip(image, 0.0, 1.0)


def test_estimate_translation_returns_shift_to_apply_to_moving() -> None:
    reference = _stars((128, 128), [(30, 42), (65, 80), (90, 25), (101, 104)])
    moving, _ = translate_with_mask(reference[:, :, None], dy=7, dx=-5)
    moving_gray = moving[:, :, 0]

    shift = estimate_translation(reference, moving_gray, max_dim=128)

    assert shift.dy == -7
    assert shift.dx == 5


def test_translate_with_mask_does_not_wrap() -> None:
    image = np.ones((8, 8, 3), dtype=np.float32)
    shifted, mask = translate_with_mask(image, dy=2, dx=-3)

    assert shifted[:2].sum() == 0
    assert shifted[:, -3:].sum() == 0
    assert mask.sum() == 30

