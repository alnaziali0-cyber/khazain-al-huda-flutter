#!/usr/bin/env python3
"""image-to-ui — extract a `UIPatch` from a reference screenshot.

This is the optional external CLI of the Khazain Al-Huda developer panel. It
reads a PNG, clusters its colours (greys and whites excluded), estimates the
type scale and the grid, maps every colour to the nearest existing design
token and writes the resulting `UIPatch` as JSON — the exact document the
in-app Image→UI engine applies.

The in-app engine performs the same extraction on the device; this CLI exists
for generating a patch outside the phone (CI, design review, bulk presets).

Usage:
    python3 tools/image-to-ui/image_to_ui.py reference.png \
        --tokens apps/mobile/lib/design/tokens/app_tokens.dart \
        --out patch.json

No third-party dependencies: the PNG decoder below uses zlib from the
standard library.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import zlib

# --------------------------------------------------------------------------
# PNG decoding
# --------------------------------------------------------------------------


def read_png(path: str):
    """Return (width, height, rgba bytes) for a PNG file."""
    with open(path, "rb") as handle:
        data = handle.read()

    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")

    pos = 8
    width = height = bit_depth = colour_type = 0
    idat = bytearray()
    palette = b""

    while pos < len(data):
        length = int.from_bytes(data[pos:pos + 4], "big")
        chunk_type = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length

        if chunk_type == b"IHDR":
            width = int.from_bytes(chunk[0:4], "big")
            height = int.from_bytes(chunk[4:8], "big")
            bit_depth = chunk[8]
            colour_type = chunk[9]
        elif chunk_type == b"PLTE":
            palette = chunk
        elif chunk_type == b"IDAT":
            idat += chunk
        elif chunk_type == b"IEND":
            break

    if bit_depth != 8:
        raise ValueError("only 8-bit PNG files are supported")

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour_type]
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    pixels = bytearray(height * stride)

    previous = bytearray(stride)
    offset = 0
    for row in range(height):
        filter_type = raw[offset]
        offset += 1
        line = bytearray(raw[offset:offset + stride])
        offset += stride

        if filter_type == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filter_type == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif filter_type == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif filter_type == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = previous[i]
                c = previous[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF

        pixels[row * stride:(row + 1) * stride] = line
        previous = line

    # Expand to RGBA.
    rgba = bytearray(width * height * 4)
    for index in range(width * height):
        source = index * channels
        target = index * 4
        if colour_type == 6:
            rgba[target:target + 4] = pixels[source:source + 4]
        elif colour_type == 2:
            rgba[target:target + 3] = pixels[source:source + 3]
            rgba[target + 3] = 255
        elif colour_type == 0:
            value = pixels[source]
            rgba[target] = rgba[target + 1] = rgba[target + 2] = value
            rgba[target + 3] = 255
        elif colour_type == 4:
            value = pixels[source]
            rgba[target] = rgba[target + 1] = rgba[target + 2] = value
            rgba[target + 3] = pixels[source + 1]
        else:  # palette
            entry = pixels[source] * 3
            rgba[target:target + 3] = palette[entry:entry + 3]
            rgba[target + 3] = 255

    return width, height, bytes(rgba)


# --------------------------------------------------------------------------
# Colour maths
# --------------------------------------------------------------------------


def is_neutral(r: int, g: int, b: int) -> bool:
    high = max(r, g, b)
    low = min(r, g, b)
    if high == 0:
        return True
    return (high - low) / high < 0.12


def to_lab(r: int, g: int, b: int):
    def channel(value: float) -> float:
        normalised = value / 255
        if normalised <= 0.04045:
            return normalised / 12.92
        return ((normalised + 0.055) / 1.055) ** 2.4

    rl = channel(r)
    gl = channel(g)
    bl = channel(b)

    x = (rl * 0.4124 + gl * 0.3576 + bl * 0.1805) / 0.95047
    y = rl * 0.2126 + gl * 0.7152 + bl * 0.0722
    z = (rl * 0.0193 + gl * 0.1192 + bl * 0.9505) / 1.08883

    def f(t: float) -> float:
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def delta_e(first, second) -> float:
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(first, second)))


# --------------------------------------------------------------------------
# Extraction
# --------------------------------------------------------------------------


def kmeans(samples, k: int, iterations: int = 12):
    if not samples:
        return []
    k = min(k, len(samples))
    centroids = [samples[(i * 7919) % len(samples)] for i in range(k)]
    counts = [0] * k

    for _ in range(iterations):
        buckets = [[] for _ in range(k)]
        for sample in samples:
            best = 0
            best_distance = float("inf")
            for index, centroid in enumerate(centroids):
                distance = sum((a - b) ** 2 for a, b in zip(sample, centroid))
                if distance < best_distance:
                    best_distance = distance
                    best = index
            buckets[best].append(sample)
        for index, bucket in enumerate(buckets):
            if bucket:
                centroids[index] = tuple(
                    sum(point[channel] for point in bucket) // len(bucket)
                    for channel in range(3)
                )
                counts[index] = len(bucket)
            else:
                counts[index] = 0

    return [
        (centroid, counts[index])
        for index, centroid in enumerate(centroids)
        if counts[index] > 0
    ]


def analyse(path: str, tokens: dict, max_width: int = 160, clusters: int = 6):
    width, height, rgba = read_png(path)
    scale = min(1.0, max_width / width)
    sample_width = max(1, int(width * scale))
    sample_height = max(1, int(height * scale))

    samples = []
    row_ink = [0.0] * sample_height
    column_ink = [0.0] * sample_width

    for y in range(sample_height):
        source_y = min(height - 1, int(y / scale))
        for x in range(sample_width):
            source_x = min(width - 1, int(x / scale))
            index = (source_y * width + source_x) * 4
            r, g, b = rgba[index], rgba[index + 1], rgba[index + 2]
            luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
            if 0.08 < luma <= 0.82:
                row_ink[y] += 1
                column_ink[x] += 1
                if not is_neutral(r, g, b):
                    samples.append((r, g, b))

    found = kmeans(samples, clusters)
    total = sum(count for _, count in found) or 1

    matches = []
    new_tokens = []
    for centroid, count in found:
        lab = to_lab(*centroid)
        best_name, best_delta = None, float("inf")
        for name, hex_value in tokens.items():
            raw = int(hex_value.lstrip("#"), 16)
            token_lab = to_lab((raw >> 16) & 0xFF, (raw >> 8) & 0xFF, raw & 0xFF)
            distance = delta_e(lab, token_lab)
            if distance < best_delta:
                best_delta = distance
                best_name = name
        entry = {
            "hex": "#%02X%02X%02X" % centroid,
            "weight": round(count / total, 4),
            "nearestToken": best_name,
            "deltaE": round(best_delta, 2),
        }
        if best_name is None or best_delta >= 6:
            new_tokens.append(entry)
        else:
            matches.append(entry)

    # Type scale from the height of the ink bands.
    bands = []
    current = 0
    threshold = sample_height * 0.012
    for value in row_ink:
        if value > threshold:
            current += 1
        else:
            if current > 0:
                bands.append(current)
            current = 0
    if current > 0:
        bands.append(current)

    type_scale = {}
    if bands:
        bands.sort()
        median = bands[len(bands) // 2]
        body = min(20.0, max(11.0, median * 2.6))
        type_scale = {
            "display": round(min(34.0, max(18.0, body * 1.7)), 1),
            "h1": round(min(28.0, max(16.0, body * 1.45)), 1),
            "h2": round(min(22.0, max(14.0, body * 1.2)), 1),
            "body": round(body, 1),
        }

    # Grid from the vertical gutters.
    gaps = []
    run = 0
    gutter_threshold = sample_width * 0.004
    for value in column_ink:
        if value <= gutter_threshold:
            run += 1
        else:
            if run > 0:
                gaps.append(run)
            run = 0
    if run > 0:
        gaps.append(run)

    columns = 4
    ratio = 0.35
    tile = sample_width / (columns + (columns - 1) * ratio)
    side_padding = max(0.0, (sample_width - columns * tile - (columns - 1) * tile * ratio) / 2)

    return {
        "size": {"width": width, "height": height},
        "matches": matches,
        "newTokens": new_tokens,
        "typeScale": type_scale,
        "grid": {
            "columns": columns,
            "gutter": ratio,
            "sidePadding": round(side_padding, 2),
            "tileAspect": 1,
        },
        "gaps": sorted(gaps)[len(gaps) // 2] if gaps else 0,
    }


# --------------------------------------------------------------------------
# Tokens
# --------------------------------------------------------------------------


def load_tokens(path: str) -> dict:
    """Reads the palette out of the Dart token file."""
    with open(path, "r", encoding="utf-8") as handle:
        source = handle.read()
    pattern = re.compile(r"static const Color (\w+)\s*=\s*Color\(0x([0-9A-Fa-f]{8})\);")
    tokens = {}
    for name, value in pattern.findall(source):
        tokens[name] = "#" + value[2:].upper()
    return tokens


def build_patch(report: dict) -> dict:
    colors = {}
    for match in report["matches"]:
        colors[match["nearestToken"]] = match["hex"]

    typography = {}
    for key, size in report["typeScale"].items():
        typography[key] = {
            "size": size,
            "weight": 700 if key != "body" else 400,
            "lineHeight": 1.35,
            "family": "NotoNaskhArabicUI",
        }

    return {
        "version": 1,
        "tokens": {
            "colors": colors,
            "typography": typography,
            "grid": {
                str(key): float(value)
                for key, value in report["grid"].items()
            },
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", help="reference PNG file")
    parser.add_argument(
        "--tokens",
        default=os.path.join(
            "apps", "mobile", "lib", "design", "tokens", "app_tokens.dart"
        ),
        help="the Dart token file to match the colours against",
    )
    parser.add_argument("--out", default="patch.json", help="output UIPatch file")
    parser.add_argument("--report", help="optional path for the raw analysis report")
    args = parser.parse_args()

    tokens = load_tokens(args.tokens)
    if not tokens:
        print("no palette found in %s" % args.tokens, file=sys.stderr)
        return 2

    report = analyse(args.image, tokens)
    patch = build_patch(report)

    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(patch, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    if args.report:
        with open(args.report, "w", encoding="utf-8") as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2)
            handle.write("\n")

    print("wrote %s" % args.out)
    for match in report["matches"]:
        print("  update %-14s %s (dE %.1f)" % (
            match["nearestToken"], match["hex"], match["deltaE"]))
    for entry in report["newTokens"]:
        print("  new    %-14s %s (dE %.1f from %s)" % (
            entry["nearestToken"] or "-", entry["hex"], entry["deltaE"],
            entry["nearestToken"] or "-"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
