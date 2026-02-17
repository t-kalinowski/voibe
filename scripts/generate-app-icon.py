#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import argparse
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent


def _lerp(a: int, b: int, t: float) -> int:
    return int(round(a + (b - a) * t))


def create_master_icon(size: int = 1024) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    card_box = (70, 54, size - 70, size - 86)
    radius = 220

    # Soft drop shadow.
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(card_box, radius=radius, fill=(8, 15, 38, 135))
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))
    img.alpha_composite(shadow)

    # Blue vertical gradient card.
    gradient = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gradient)
    top = (12, 158, 237)   # sky blue
    bottom = (29, 78, 216)  # deep blue
    for y in range(size):
        t = y / (size - 1)
        color = (_lerp(top[0], bottom[0], t), _lerp(top[1], bottom[1], t), _lerp(top[2], bottom[2], t), 255)
        gd.line((0, y, size, y), fill=color)

    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle(card_box, radius=radius, fill=255)
    img.paste(gradient, (0, 0), mask)

    # Subtle top highlight.
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gl = ImageDraw.Draw(glow)
    gl.ellipse((120, -210, size - 120, 460), fill=(255, 255, 255, 46))
    glow = glow.filter(ImageFilter.GaussianBlur(18))
    img.alpha_composite(glow)

    # Center ring behind waveform bars.
    ring = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    cx = cy = size // 2
    rr = int(size * 0.24)
    rd.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=(255, 255, 255, 34), outline=(255, 255, 255, 120), width=10)
    img.alpha_composite(ring)

    # Waveform bars (mirrors menubar "waveform" concept).
    bars = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bars)
    bar_width = int(size * 0.065)
    bar_gap = int(size * 0.04)
    heights = [190, 300, 390, 300, 190]
    total_width = len(heights) * bar_width + (len(heights) - 1) * bar_gap
    x = cx - total_width // 2
    for h in heights:
        y0 = cy - h // 2
        y1 = cy + h // 2
        bd.rounded_rectangle((x, y0, x + bar_width, y1), radius=bar_width // 2, fill=(255, 255, 255, 245))
        x += bar_width + bar_gap

    bars_shadow = bars.filter(ImageFilter.GaussianBlur(5))
    img.alpha_composite(bars_shadow)
    img.alpha_composite(bars)

    return img


def write_iconset(master: Image.Image, iconset_dir: Path) -> dict[int, bytes]:
    iconset_dir.mkdir(parents=True, exist_ok=True)
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
    png_by_size: dict[int, bytes] = {}
    for name, px in sizes.items():
        icon = master.resize((px, px), Image.Resampling.LANCZOS)
        output_path = iconset_dir / name
        icon.save(output_path, format="PNG")
        png_by_size[px] = output_path.read_bytes()
    return png_by_size


def build_icns(png_by_size: dict[int, bytes], icns_path: Path) -> None:
    # PNG-compressed icon types supported by modern macOS.
    icon_types = {
        16: b"icp4",
        32: b"icp5",
        64: b"icp6",
        128: b"ic07",
        256: b"ic08",
        512: b"ic09",
        1024: b"ic10",
    }

    chunks = []
    for size, icon_type in icon_types.items():
        data = png_by_size[size]
        length = 8 + len(data)
        chunks.append(icon_type + struct.pack(">I", length) + data)

    body = b"".join(chunks)
    header = b"icns" + struct.pack(">I", 8 + len(body))
    icns_path.write_bytes(header + body)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Voibe app icon assets (.iconset and .icns).")
    parser.add_argument(
        "--out-dir",
        default=str(ROOT / "dist" / "icon-assets"),
        help="Output directory for generated icon files.",
    )
    args = parser.parse_args()

    out_dir = Path(args.out_dir).resolve()
    iconset_dir = out_dir / "AppIcon.iconset"
    icns_path = out_dir / "AppIcon.icns"
    master_path = out_dir / "AppIcon-master.png"

    out_dir.mkdir(parents=True, exist_ok=True)
    master = create_master_icon(1024)
    master.save(master_path, format="PNG")
    png_by_size = write_iconset(master, iconset_dir)
    build_icns(png_by_size, icns_path)
    print(f"Generated {icns_path}")


if __name__ == "__main__":
    main()
