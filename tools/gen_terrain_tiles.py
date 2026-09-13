#!/usr/bin/env python3
"""Generate the island terrain tile atlas.

Palette and motifs are lifted from the top-down grass/dirt/stone tileset the
owner picked. That sheet only reached us as a lossy 1800x1200 marketing preview
with no recoverable pixel grid (edge run-lengths measure 1,2,3,4,6,7,8,10...
with no consistent multiple), so its *tiles* cannot be sliced cleanly. Its
exact colours survive resampling perfectly though, so they are sampled here and
the tiles are redrawn crisp at 16px instead of upscaled into mush.

Swap this for real slices the moment the source PNG/zip turns up - keep the row
order and nothing else in the project changes.

Output: assets/tiles/island_terrain.png - 4 variants across, one terrain per
row, 16x16, in the row order consumed by scripts/world/island_generator.gd.

    python3 tools/gen_terrain_tiles.py
"""
import os
import random
import struct
import zlib

TILE = 16
VARIANTS = 4


def rgb(h):
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


# Sampled from the reference sheet. Row order must match Terrain in
# island_generator.gd. (base, shade, highlight, style)
TERRAINS = [
    # Deep water: the sheet's blue darkened, since it has no ocean tile at all -
    # only surface wave overlays on transparent background.
    ("deep_water",    rgb("445ea0"), rgb("3b5390"), rgb("5574bf"), "water"),
    ("shallow_water", rgb("5574bf"), rgb("4f6ab4"), rgb("5f7fc9"), "water"),
    # The sheet has no sand, so beaches use its dirt brown.
    ("sand",          rgb("9f5f3f"), rgb("945f3f"), rgb("aa6a4a"), "speck"),
    ("grass",         rgb("7f9f55"), rgb("7f9455"), rgb("9fb455"), "blades"),
    ("forest",        rgb("6a8a4a"), rgb("5f7f42"), rgb("7f9f55"), "blades"),
    ("rock",          rgb("b47f3f"), rgb("aa6a3f"), rgb("b4743f"), "speck"),
]


def make_tile(base, shade, highlight, style, rng):
    """A TILE x TILE grid of RGB tuples."""
    px = [[base] * TILE for _ in range(TILE)]

    if style == "water":
        # Blobby horizontal streaks, echoing the reference sheet's wave shapes.
        for _ in range(3):
            y = rng.randrange(TILE)
            x0 = rng.randrange(TILE)
            length = rng.randint(3, 6)
            for i in range(length):
                px[y][(x0 + i) % TILE] = highlight
            if rng.random() < 0.6:
                y2 = (y - 1) % TILE
                for i in range(1, max(2, length - 1)):
                    px[y2][(x0 + i) % TILE] = highlight
        for _ in range(2):
            y = rng.randrange(TILE)
            x0 = rng.randrange(TILE)
            for i in range(rng.randint(2, 4)):
                px[y][(x0 + i) % TILE] = shade
        return px

    # Scattered specks so large flat areas do not read as solid colour.
    for _ in range(22):
        px[rng.randrange(TILE)][rng.randrange(TILE)] = shade
    if style == "blades":
        # Short upright marks, the closest 16px echo of the sheet's leafy grass.
        for _ in range(9):
            x = rng.randrange(TILE)
            y = rng.randrange(TILE - 1)
            px[y][x] = highlight
            if rng.random() < 0.5:
                px[y + 1][x] = highlight
    else:
        for _ in range(12):
            px[rng.randrange(TILE)][rng.randrange(TILE)] = highlight
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

    for r, (_name, base, shade, highlight, style) in enumerate(TERRAINS):
        tiles = [make_tile(base, shade, highlight, style, rng) for _ in range(VARIANTS)]
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
        print("  row %d = %-14s #%02x%02x%02x" % (i, t[0], t[1][0], t[1][1], t[1][2]))


if __name__ == "__main__":
    main()
