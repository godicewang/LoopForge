#!/usr/bin/env python3
"""Render hash-bound native baseline/candidate comparison evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFont, ImageStat


CELL_NAMES = (
    "standard-expanded",
    "standard-narrow",
    "accessibility-expanded",
    "accessibility-narrow",
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def image_record(path: Path, image: Image.Image) -> dict[str, object]:
    rgb = image.convert("RGB")
    return {
        "path": str(path),
        "fileSHA256": sha256_bytes(path.read_bytes()),
        "pixelSHA256": sha256_bytes(rgb.tobytes()),
        "width": rgb.width,
        "height": rgb.height,
    }


def aligned_pair(baseline: Image.Image, candidate: Image.Image) -> tuple[Image.Image, Image.Image]:
    width = max(baseline.width, candidate.width)
    height = max(baseline.height, candidate.height)

    def pad(image: Image.Image) -> Image.Image:
        canvas = Image.new("RGB", (width, height), "#111111")
        x = (width - image.width) // 2
        y = (height - image.height) // 2
        canvas.paste(image.convert("RGB"), (x, y))
        return canvas

    return pad(baseline), pad(candidate)


def scaled(image: Image.Image, width: int) -> Image.Image:
    height = round(image.height * width / image.width)
    return image.resize((width, height), Image.Resampling.LANCZOS)


def render(args: argparse.Namespace) -> None:
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    font = ImageFont.load_default(size=20)
    small_font = ImageFont.load_default(size=15)
    rows: list[tuple[str, Image.Image, Image.Image, Image.Image]] = []
    metrics: dict[str, object] = {
        "schemaVersion": 1,
        "baselineRevision": args.baseline_revision,
        "candidateSourceSnapshotSHA256": args.candidate_snapshot,
        "alignment": "native pixels centered on an unscaled maximum-size canvas",
        "cells": [],
    }

    for index, name in enumerate(CELL_NAMES):
        baseline_path = args.images[index * 2].resolve()
        candidate_path = args.images[index * 2 + 1].resolve()
        baseline = Image.open(baseline_path).convert("RGB")
        candidate = Image.open(candidate_path).convert("RGB")
        baseline_aligned, candidate_aligned = aligned_pair(baseline, candidate)
        raw_diff = ImageChops.difference(baseline_aligned, candidate_aligned)
        visible_diff = ImageEnhance.Contrast(raw_diff).enhance(3.0)
        diff_path = output_dir / f"{args.prefix}-diff-{name}.png"
        visible_diff.save(diff_path)
        stat = ImageStat.Stat(raw_diff)
        mae = sum(stat.mean) / 3.0
        changed_pixels = sum(
            1 for pixel in raw_diff.convert("L").get_flattened_data() if pixel != 0
        )
        pixel_count = raw_diff.width * raw_diff.height
        metrics["cells"].append(
            {
                "name": name,
                "baseline": image_record(baseline_path, baseline),
                "candidate": image_record(candidate_path, candidate),
                "comparisonCanvas": {"width": raw_diff.width, "height": raw_diff.height},
                "meanAbsoluteChannelDelta": round(mae, 6),
                "changedPixelRatio": round(changed_pixels / pixel_count, 8),
                "visibleDifference": image_record(diff_path, visible_diff),
            }
        )
        rows.append((name, baseline_aligned, candidate_aligned, visible_diff))

    preview_width = 500
    gap = 18
    label_width = 220
    header_height = 52
    row_gap = 22
    preview_rows = []
    for name, baseline, candidate, difference in rows:
        images = [scaled(image, preview_width) for image in (baseline, candidate, difference)]
        height = max(image.height for image in images)
        preview_rows.append((name, images, height))

    sheet_width = label_width + preview_width * 3 + gap * 4
    sheet_height = header_height + sum(row[2] + row_gap for row in preview_rows) + gap
    sheet = Image.new("RGB", (sheet_width, sheet_height), "#101319")
    draw = ImageDraw.Draw(sheet)
    headers = ("cell", "baseline", "candidate", "3× contrast delta")
    header_x = (gap, label_width + gap * 2, label_width + preview_width + gap * 3, label_width + preview_width * 2 + gap * 4)
    for x, header in zip(header_x, headers):
        draw.text((x, 16), header, fill="#f0f4ff", font=font)

    y = header_height
    for name, images, height in preview_rows:
        draw.text((gap, y + 8), name.replace("-", "\n"), fill="#bac5d8", font=small_font, spacing=6)
        x = label_width + gap * 2
        for preview in images:
            sheet.paste(preview, (x, y))
            x += preview_width + gap
        y += height + row_gap

    sheet_path = output_dir / f"{args.prefix}-contact-sheet.jpg"
    sheet.save(sheet_path, quality=94, subsampling=0)
    metrics["contactSheet"] = image_record(sheet_path, sheet)
    metrics_path = output_dir / f"{args.prefix}-metrics.json"
    metrics_path.write_text(json.dumps(metrics, indent=2, ensure_ascii=False) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--baseline-revision", required=True)
    parser.add_argument("--candidate-snapshot", required=True)
    parser.add_argument(
        "images",
        type=Path,
        nargs=8,
        metavar=(
            "BASELINE_STANDARD_EXPANDED",
            "CANDIDATE_STANDARD_EXPANDED",
            "BASELINE_STANDARD_NARROW",
            "CANDIDATE_STANDARD_NARROW",
            "BASELINE_ACCESSIBILITY_EXPANDED",
            "CANDIDATE_ACCESSIBILITY_EXPANDED",
            "BASELINE_ACCESSIBILITY_NARROW",
            "CANDIDATE_ACCESSIBILITY_NARROW",
        ),
    )
    return parser.parse_args()


if __name__ == "__main__":
    render(parse_args())
