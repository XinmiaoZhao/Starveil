from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Literal


CompositionMode = Literal["mean", "sigma", "trails"]
OutputStretch = Literal["none", "auto", "hdr"]
ProgressCallback = Callable[[str, float], None]


@dataclass(slots=True)
class StackOptions:
    mode: CompositionMode = "sigma"
    base_path: Path | None = None
    dark_paths: list[Path] = field(default_factory=list)
    flat_paths: list[Path] = field(default_factory=list)
    output_stretch: OutputStretch = "none"
    auto_brightness: bool = False
    hdr: bool = False
    reduce_light_pollution: bool = False
    light_pollution_strength: float = 0.45
    enhance_stars: bool = False
    star_enhancement_strength: float = 0.35
    sigma: float = 2.2
    alignment_max_dim: int = 1200


@dataclass(slots=True)
class AlignmentInfo:
    path: Path
    dy: int
    dx: int
    peak: float


@dataclass(slots=True)
class StackResult:
    image: object
    base_path: Path
    alignments: list[AlignmentInfo]
