#!/usr/bin/env python3
"""Generate GitRelay AppIcon PNGs (Linux-friendly mirror of generate-icon.swift)."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ASSET_PATH = Path("gitrelay/Assets.xcassets/AppIcon.appiconset")

SIZES = [
    ("icon_16.png", 16),
    ("icon_16@2x.png", 32),
    ("icon_32.png", 32),
    ("icon_32@2x.png", 64),
    ("icon_128.png", 128),
    ("icon_128@2x.png", 256),
    ("icon_256.png", 256),
    ("icon_256@2x.png", 512),
    ("icon_512.png", 512),
    ("icon_512@2x.png", 1024),
]

STROKE_WIDTH = 0.044
NODE_RADIUS = 0.072
OUTER_RADIUS = NODE_RADIUS + STROKE_WIDTH / 2
INNER_RADIUS = NODE_RADIUS - STROKE_WIDTH / 2
FORK = (0.5, 0.505)
NODES = [(0.5, 0.69), (0.293, 0.283), (0.707, 0.283)]
PLATE_EXPONENT = 5.0
PLATE_SAMPLE_COUNT = 720

PLATE_TOP = (52, 52, 55)
PLATE_BOTTOM = (33, 33, 36)
BRANCH = (255, 255, 255, 255)


def signed_power(value: float, exponent: float) -> float:
    magnitude = abs(value) ** exponent
    return -magnitude if value < 0 else magnitude


def plate_outline(sample_count: int = PLATE_SAMPLE_COUNT) -> list[tuple[float, float]]:
    exponent = 2 / PLATE_EXPONENT
    points: list[tuple[float, float]] = []
    for index in range(sample_count):
        angle = 2 * math.pi * index / sample_count
        points.append(
            (
                0.5 + 0.5 * signed_power(math.cos(angle), exponent),
                0.5 + 0.5 * signed_power(math.sin(angle), exponent),
            )
        )
    return points


def edge_point(node: tuple[float, float], target: tuple[float, float]) -> tuple[float, float]:
    dx = target[0] - node[0]
    dy = target[1] - node[1]
    length = math.hypot(dx, dy)
    if length <= 0:
        return node
    scale = OUTER_RADIUS / length
    return (node[0] + dx * scale, node[1] + dy * scale)


def canvas_point(point: tuple[float, float], size: int) -> tuple[float, float]:
    return point[0] * size, (1 - point[1]) * size


def ellipse_bbox(center: tuple[float, float], radius: float) -> list[float]:
    return [
        center[0] - radius,
        center[1] - radius,
        center[0] + radius,
        center[1] + radius,
    ]


def render_icon(pixels: int) -> Image.Image:
    size = pixels
    outline = [canvas_point(point, size) for point in plate_outline()]

    plate_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(plate_mask).polygon(outline, fill=255)

    gradient = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    grad_draw = ImageDraw.Draw(gradient)
    for y in range(size):
        t = 1 - y / max(size - 1, 1)
        color = tuple(
            int(PLATE_BOTTOM[i] + (PLATE_TOP[i] - PLATE_BOTTOM[i]) * t) for i in range(3)
        ) + (255,)
        grad_draw.line([(0, y), (size, y)], fill=color)

    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    image.paste(gradient, mask=plate_mask)

    branch = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(branch)
    stroke = max(1, round(STROKE_WIDTH * size))

    for node in NODES:
        start = canvas_point(edge_point(node, FORK), size)
        end = canvas_point(FORK, size)
        draw.line([start, end], fill=BRANCH, width=stroke)

    outer_mask = Image.new("L", (size, size), 0)
    inner_mask = Image.new("L", (size, size), 0)
    outer_draw = ImageDraw.Draw(outer_mask)
    inner_draw = ImageDraw.Draw(inner_mask)
    for node in NODES:
        center = canvas_point(node, size)
        outer_draw.ellipse(ellipse_bbox(center, OUTER_RADIUS * size), fill=255)
        inner_draw.ellipse(ellipse_bbox(center, INNER_RADIUS * size), fill=255)
    ring_mask = ImageChops.subtract(outer_mask, inner_mask)
    rings = Image.new("RGBA", (size, size), BRANCH)
    branch.paste(rings, mask=ring_mask)

    return Image.alpha_composite(image, branch)


def main() -> None:
    ASSET_PATH.mkdir(parents=True, exist_ok=True)
    for filename, px in SIZES:
        out = ASSET_PATH / filename
        render_icon(px).save(out, format="PNG")
        print(f"  {filename:<20} {px}x{px}  {out.stat().st_size:,} bytes")
    print(f"\nWrote {len(SIZES)} icon PNGs to {ASSET_PATH}")


if __name__ == "__main__":
    main()
