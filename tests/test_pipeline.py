from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

from mysequator.engine import StackOptions, stack_images
from mysequator.engine.alignment import translate_with_mask
from mysequator.engine.io import load_image, save_image


def _make_rgb_star_field() -> np.ndarray:
    image = np.zeros((96, 96, 3), dtype=np.float32)
    points = [(18, 20), (32, 70), (45, 40), (72, 60), (80, 24)]
    for y, x in points:
        image[y - 1 : y + 2, x - 1 : x + 2, :] = (0.55, 0.6, 1.0)
        image[y, x, :] = 1.0
    image += 0.03
    return np.clip(image, 0.0, 1.0)


def _save(path: Path, image: np.ndarray) -> None:
    Image.fromarray((np.clip(image, 0, 1) * 255).astype(np.uint8), mode="RGB").save(path)


def test_stack_images_aligns_and_averages(tmp_path: Path) -> None:
    base = _make_rgb_star_field()
    rng = np.random.default_rng(42)
    shifts = [(0, 0), (3, -2), (-4, 5), (2, 4)]
    paths = []
    for index, (dy, dx) in enumerate(shifts):
        shifted, _ = translate_with_mask(base, dy=dy, dx=dx)
        noisy = np.clip(shifted + rng.normal(0, 0.01, shifted.shape), 0, 1)
        path = tmp_path / f"frame_{index}.png"
        _save(path, noisy)
        paths.append(path)

    result = stack_images(paths, options=StackOptions(mode="sigma", auto_brightness=False))

    assert result.image.shape == base.shape
    assert len(result.alignments) == 4
    assert float(result.image.max()) > 0.5


def test_tiff_roundtrip_preserves_16_bit_rgb(tmp_path: Path) -> None:
    image = np.zeros((12, 10, 3), dtype=np.float32)
    image[:, :, 0] = 0.25
    image[:, :, 1] = 0.5
    image[:, :, 2] = 0.75
    path = tmp_path / "roundtrip.tiff"

    save_image(image, path)
    loaded = load_image(path)

    assert loaded.shape == image.shape
    assert np.allclose(loaded[0, 0], [0.25, 0.5, 0.75], atol=1 / 65535)
