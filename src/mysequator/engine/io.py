from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image
import tifffile


RASTER_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".tif",
    ".tiff",
    ".bmp",
}

RAW_EXTENSIONS = {
    ".3fr",
    ".arw",
    ".bay",
    ".cr2",
    ".cr3",
    ".crw",
    ".dcr",
    ".dng",
    ".erf",
    ".fff",
    ".iiq",
    ".kdc",
    ".mef",
    ".mos",
    ".mrw",
    ".nef",
    ".nrw",
    ".orf",
    ".pef",
    ".raf",
    ".raw",
    ".rw2",
    ".rwl",
    ".sr2",
    ".srf",
    ".srw",
    ".x3f",
}

SUPPORTED_EXTENSIONS = RASTER_EXTENSIONS | RAW_EXTENSIONS
OUTPUT_EXTENSIONS = {".tif", ".tiff", ".jpg", ".jpeg", ".png"}


def assert_supported(path: Path) -> None:
    if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        supported = ", ".join(sorted(SUPPORTED_EXTENSIONS))
        raise ValueError(f"Unsupported image type for {path.name}; use {supported}.")


def load_image(path: Path) -> np.ndarray:
    """Load an image as RGB float32 in the 0..1 range."""
    assert_supported(path)
    ext = path.suffix.lower()
    if ext in RAW_EXTENSIONS:
        return _load_raw(path)

    if ext in {".tif", ".tiff"}:
        arr = tifffile.imread(path)
        return _array_to_rgb_float(arr)

    with Image.open(path) as img:
        if img.mode in {"I;16", "I;16B", "I;16L"}:
            arr = np.asarray(img, dtype=np.uint16)
            if arr.ndim == 2:
                arr = np.repeat(arr[:, :, None], 3, axis=2)
            return arr.astype(np.float32) / 65535.0

        if img.mode == "I":
            arr = np.asarray(img, dtype=np.int32)
            arr = np.clip(arr, 0, 65535).astype(np.float32) / 65535.0
            if arr.ndim == 2:
                arr = np.repeat(arr[:, :, None], 3, axis=2)
            return arr

        rgb = img.convert("RGB")
        arr = np.asarray(rgb)
        return arr.astype(np.float32) / 255.0


def save_image(image: np.ndarray, path: Path) -> None:
    """Save RGB float image to TIFF/JPEG/PNG based on extension."""
    path.parent.mkdir(parents=True, exist_ok=True)
    clipped = np.clip(image, 0.0, 1.0)
    ext = path.suffix.lower()

    if ext in {".tif", ".tiff"}:
        arr16 = np.round(clipped * 65535.0).astype(np.uint16)
        tifffile.imwrite(path, arr16, photometric="rgb")
        return

    if ext in {".jpg", ".jpeg"}:
        arr8 = np.round(clipped * 255.0).astype(np.uint8)
        Image.fromarray(arr8, mode="RGB").save(path, quality=95, subsampling=0)
        return

    if ext == ".png":
        arr8 = np.round(clipped * 255.0).astype(np.uint8)
        Image.fromarray(arr8, mode="RGB").save(path)
        return

    supported = ", ".join(sorted(OUTPUT_EXTENSIONS))
    raise ValueError(f"Output must end with one of: {supported}")


def _load_raw(path: Path) -> np.ndarray:
    try:
        import rawpy
    except ImportError as exc:
        raise ImportError("RAW support requires rawpy. Install it with conda-forge rawpy.") from exc

    with rawpy.imread(str(path)) as raw:
        rgb = raw.postprocess(
            use_camera_wb=True,
            no_auto_bright=True,
            output_bps=16,
            gamma=(1, 1),
            user_flip=0,
        )
    return _array_to_rgb_float(rgb)


def _array_to_rgb_float(arr: np.ndarray) -> np.ndarray:
    arr = np.asarray(arr)
    if arr.ndim == 2:
        arr = np.repeat(arr[:, :, None], 3, axis=2)
    elif arr.ndim == 3 and arr.shape[0] in {3, 4} and arr.shape[-1] not in {3, 4}:
        arr = np.moveaxis(arr, 0, -1)
    elif arr.ndim != 3:
        raise ValueError(f"Unsupported TIFF shape: {arr.shape}")

    if arr.shape[-1] == 4:
        arr = arr[:, :, :3]
    if arr.shape[-1] == 1:
        arr = np.repeat(arr, 3, axis=2)
    if arr.shape[-1] != 3:
        raise ValueError(f"Unsupported TIFF channel count: {arr.shape[-1]}")

    if np.issubdtype(arr.dtype, np.integer):
        scale = float(np.iinfo(arr.dtype).max)
        return np.clip(arr.astype(np.float32) / scale, 0.0, 1.0)
    return np.clip(arr.astype(np.float32), 0.0, 1.0)


def luminance(image: np.ndarray) -> np.ndarray:
    if image.ndim == 2:
        return image.astype(np.float32, copy=False)
    rgb = image[:, :, :3].astype(np.float32, copy=False)
    return 0.2126 * rgb[:, :, 0] + 0.7152 * rgb[:, :, 1] + 0.0722 * rgb[:, :, 2]


def resize_float(image: np.ndarray, size: tuple[int, int], resample: int = Image.BICUBIC) -> np.ndarray:
    """Resize a float image with Pillow and return float32 in the original range."""
    lo = float(np.nanmin(image))
    hi = float(np.nanmax(image))
    if hi <= lo:
        return np.full((size[1], size[0]), lo, dtype=np.float32)

    normalized = np.clip((image - lo) / (hi - lo), 0.0, 1.0)
    pil = Image.fromarray(np.round(normalized * 65535.0).astype(np.uint16), mode="I;16")
    out = np.asarray(pil.resize(size, resample=resample), dtype=np.float32) / 65535.0
    return out * (hi - lo) + lo
