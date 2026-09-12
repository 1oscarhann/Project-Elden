#!/usr/bin/env python3
"""Generate the placeholder island terrain tile atlas.

None of the CraftPix packs we kept contain ground tiles (the dungeon pack that
did was dropped - wrong art style for a sunny island), so the terrain is
programmer-art until a proper cozy tileset is sourced. Swap the PNG and this
script goes away; nothing else needs to change.

Output: assets/tiles/island_terrain.png - 4 variants across, one terrain per row,
16x16 tiles, in the row order consumed by scripts/world/island_generator.gd.

    python3 tools/gen_terrain_tiles.py
"""
import os
import random
import struct
import zlib

TILE = 16
VARIANTS = 4

# (name, base, speck_dark, speck_light, style) - row order must match Terrain in
# island_generator.gd.
TERRAINS = [
    ("deep_water",    (0x24, 0x54, 0x7a), (0x1e, 0x49, 0x6c), (0x2e, 0x62, 0x8a), "wave"),
    ("shallow_water", (0x49, 0x8a, 0xb0), (0x3f, 0x7d, 0xa2), (0x5c, 0x9e, 0xc2), "wave"),
    ("sand",          (0xe0, 0xd0, 0xa0), (0xd2, 0xc0, 0x8c), (0xec, 0xdd, 0xb4), "speck"),
    ("grass",         (0x6a, 0x9e, 0x52), (0x5d, 0x8e, 0x47), (0x7a, 0xaf, 0x5f), "speck"),
    ("forest",        (0x49, 0x77, 0x3c), (0x3f, 0x69, 0x34), (0x55, 0x86, 0x46), "speck"),
    ("rock",          (0x8b, 0x8a, 0x84), (0x77, 0x76, 0x71), (0x9d, 0x9c, 0x96), "speck"),
]


def make_tile(base, dark, light, style, rng):
    """Return a TILE x TILE grid of RGB tuples with a little texture in it."""
    px = [[base] * TILE for _ in range(TILE)]
    if style == "wave":
        # Soft horizontal banding reads as water without animating anything.
        for y in range(TILE):
            for x in range(TILE):
                band = (x + (y // 2) * 3) % 16
                if band < 2:
                    px[y][x] = light
                elif band > 13:
                    px[y][x] = dark
        for _ in range(6):
            px[rng.randrange(TILE)][rng.randrange(TILE)] = light
    else:
        # Scattered specks so large flat areas do not look like solid colour.
        for _ in range(26):
            px[rng.randrange(TILE)][rng.randrange(TILE)] = dark
        for _ in range(14):
            px[rng.randrange(TILE)][rng.randrange(TILE)] = light
    return px


def write_png(path, width, height, rows):
    """Minimal RGBA8 PNG writer (no third-party deps available)."""
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    blob = b"\x89PNG\r\n\x1a\n"
    blob += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    blob += chunk(b"IDAT", zlib.compress(raw, 9))
    blob += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(blob)


def main():
    rng = random.Random(20240612)  # fixed seed => regenerating gives identical art
    width, height = TILE * VARIANTS, TILE * len(TERRAINS)
    rows = [bytearray() for _ in range(height)]

    for r, (_name, base, dark, light, style) in enumerate(TERRAINS):
        tiles = [make_tile(base, dark, light, style, rng) for _ in range(VARIANTS)]
        for y in range(TILE):
            row = rows[r * TILE + y]
            for tile in tiles:
                for x in range(TILE):
                    row += bytes(tile[y][x]) + b"\xff"

    out = os.path.join("assets", "tiles", "island_terrain.png")
    write_png(out, width, height, rows)
    print("wrote %s  (%dx%d, %d terrains x %d variants @ %dpx)"
          % (out, width, height, len(TERRAINS), VARIANTS, TILE))
    for i, t in enumerate(TERRAINS):
        print("  row %d = %s" % (i, t[0]))


if __name__ == "__main__":
    main()
