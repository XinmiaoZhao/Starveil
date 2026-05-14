from __future__ import annotations

import argparse
from pathlib import Path

from .engine import StackOptions, stack_images
from .engine.io import save_image


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Stack star-field images on macOS.")
    parser.add_argument("images", nargs="+", type=Path, help="Star images to stack")
    parser.add_argument("-o", "--output", required=True, type=Path, help="Output .tif/.tiff/.jpg/.png path")
    parser.add_argument("--base", type=Path, default=None, help="Base frame path")
    parser.add_argument("--dark", action="append", type=Path, default=[], help="Dark frame path; repeatable")
    parser.add_argument("--flat", action="append", type=Path, default=[], help="Flat frame path; repeatable")
    parser.add_argument("--mode", choices=["mean", "sigma", "trails"], default="sigma")
    parser.add_argument("--sigma", type=float, default=2.2)
    parser.add_argument("--no-auto-brightness", action="store_true")
    parser.add_argument("--hdr", action="store_true")
    parser.add_argument("--reduce-light-pollution", action="store_true")
    parser.add_argument("--light-pollution-strength", type=float, default=0.45)
    parser.add_argument("--enhance-stars", action="store_true")
    parser.add_argument("--star-enhancement-strength", type=float, default=0.35)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    options = StackOptions(
        mode=args.mode,
        base_path=args.base,
        dark_paths=args.dark,
        flat_paths=args.flat,
        auto_brightness=not args.no_auto_brightness,
        hdr=args.hdr,
        reduce_light_pollution=args.reduce_light_pollution,
        light_pollution_strength=args.light_pollution_strength,
        enhance_stars=args.enhance_stars,
        star_enhancement_strength=args.star_enhancement_strength,
        sigma=args.sigma,
    )

    def progress(message: str, fraction: float) -> None:
        print(f"{fraction:6.1%} {message}")

    result = stack_images(args.images, options=options, progress=progress)
    save_image(result.image, args.output)
    print(f"Saved {args.output}")
    print("Alignment shifts:")
    for item in result.alignments:
        print(f"  {item.path.name}: dy={item.dy:+d}, dx={item.dx:+d}, peak={item.peak:.4f}")
    return 0
