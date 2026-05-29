#!/usr/bin/env python3
from __future__ import annotations

import math
import shutil
import subprocess
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "Assets" / "AppIcon"
PNG_PATH = ICON_DIR / "Mneme.png"
ICONSET_DIR = ICON_DIR / "Mneme.iconset"
ICNS_PATH = ICON_DIR / "Mneme.icns"
ICO_PATH = ICON_DIR / "Mneme.ico"


def lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def mix(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(lerp(c1[i], c2[i], t) for i in range(3))


def rounded_mask(size: int, radius: int, inset: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((inset, inset, size - inset, size - inset), radius=radius, fill=255)
    return mask


def draw_glow_line(
    image: Image.Image,
    points: list[tuple[int, int]],
    color: tuple[int, int, int],
    width: int,
    glow_width: int,
) -> None:
    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.line(points, fill=(*color, 120), width=glow_width, joint="curve")
    for x, y in points:
        glow_draw.ellipse(
            (x - glow_width // 2, y - glow_width // 2, x + glow_width // 2, y + glow_width // 2),
            fill=(*color, 120),
        )
    glow = glow.filter(ImageFilter.GaussianBlur(20))
    image.alpha_composite(glow)

    draw = ImageDraw.Draw(image)
    shadow_points = [(x + 0, y + 10) for x, y in points]
    draw.line(shadow_points, fill=(0, 0, 0, 88), width=width + 8, joint="curve")
    draw.line(points, fill=(*color, 245), width=width, joint="curve")
    for x, y in points:
        draw.ellipse((x - width // 2, y - width // 2, x + width // 2, y + width // 2), fill=(*color, 245))


def make_icon() -> Image.Image:
    size = 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((92, 112, 932, 952), radius=220, fill=(0, 0, 0, 190))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    image.alpha_composite(shadow)

    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = rounded_mask(size, radius=220, inset=72)
    pixels = base.load()
    top_left = (5, 14, 20)
    mid = (13, 55, 58)
    bottom_right = (19, 99, 105)
    for y in range(size):
        for x in range(size):
            if mask.getpixel((x, y)) == 0:
                continue
            diagonal = (x + y) / (2 * (size - 1))
            radial = min(math.hypot(x - 360, y - 270) / 760, 1)
            color = mix(top_left, mid, min(diagonal * 1.35, 1))
            color = mix(color, bottom_right, max(0, 1 - radial) * 0.42)
            pixels[x, y] = (*color, 255)
    image.alpha_composite(base)

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((92, 92, 912, 912), radius=194, outline=(179, 255, 238, 42), width=5)
    draw.rounded_rectangle((124, 118, 900, 528), radius=170, outline=(255, 255, 255, 22), width=4)

    for offset, alpha in [(0, 52), (32, 34), (64, 22)]:
        draw.arc(
            (250 + offset, 226 + offset, 774 - offset, 750 - offset),
            start=206,
            end=344,
            fill=(164, 255, 240, alpha),
            width=3,
        )

    lens = Image.new("RGBA", image.size, (0, 0, 0, 0))
    lens_draw = ImageDraw.Draw(lens)
    lens_draw.ellipse((296, 252, 724, 680), outline=(131, 246, 224, 54), width=50)
    lens_draw.ellipse((296, 252, 724, 680), outline=(228, 255, 249, 108), width=22)
    lens_draw.line((650, 642, 776, 768), fill=(124, 238, 218, 190), width=50)
    lens_draw.line((650, 642, 776, 768), fill=(233, 255, 250, 125), width=20)
    lens = lens.filter(ImageFilter.GaussianBlur(0.2))
    image.alpha_composite(lens)

    path = [(330, 584), (426, 404), (512, 566), (608, 394), (700, 560)]
    draw_glow_line(image, path, (119, 244, 220), width=50, glow_width=84)

    draw = ImageDraw.Draw(image)
    node_fill = (234, 255, 249, 255)
    node_ring = (72, 190, 178, 255)
    for x, y in path:
        draw.ellipse((x - 39, y - 39, x + 39, y + 39), fill=(0, 0, 0, 80))
        draw.ellipse((x - 34, y - 34, x + 34, y + 34), fill=node_ring)
        draw.ellipse((x - 22, y - 22, x + 22, y + 22), fill=node_fill)
        draw.ellipse((x - 9, y - 9, x + 9, y + 9), fill=(12, 83, 85, 255))

    highlight = Image.new("RGBA", image.size, (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.ellipse((208, 112, 650, 360), fill=(255, 255, 255, 42))
    highlight = highlight.filter(ImageFilter.GaussianBlur(30))
    image.alpha_composite(highlight)
    return image


def write_iconset(icon: Image.Image) -> None:
    if ICONSET_DIR.exists():
        shutil.rmtree(ICONSET_DIR)
    ICONSET_DIR.mkdir(parents=True)
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, size in sizes.items():
        resized = icon.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(ICONSET_DIR / name)


def write_icns_from_pngs() -> None:
    chunks = [
        ("icp4", ICONSET_DIR / "icon_16x16.png"),
        ("icp5", ICONSET_DIR / "icon_32x32.png"),
        ("icp6", ICONSET_DIR / "icon_32x32@2x.png"),
        ("ic07", ICONSET_DIR / "icon_128x128.png"),
        ("ic08", ICONSET_DIR / "icon_256x256.png"),
        ("ic09", ICONSET_DIR / "icon_512x512.png"),
        ("ic10", ICONSET_DIR / "icon_512x512@2x.png"),
    ]
    payload = bytearray()
    for chunk_type, path in chunks:
        data = path.read_bytes()
        payload.extend(struct.pack(">4sI", chunk_type.encode("ascii"), len(data) + 8))
        payload.extend(data)

    ICNS_PATH.write_bytes(struct.pack(">4sI", b"icns", len(payload) + 8) + payload)


def write_ico(icon: Image.Image) -> None:
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    icon.save(ICO_PATH, format="ICO", sizes=sizes)


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    icon = make_icon()
    icon.save(PNG_PATH)
    write_iconset(icon)
    try:
        subprocess.run(
            ["iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(ICNS_PATH)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        write_icns_from_pngs()
    write_ico(icon)
    print(PNG_PATH)
    print(ICNS_PATH)
    print(ICO_PATH)


if __name__ == "__main__":
    main()
