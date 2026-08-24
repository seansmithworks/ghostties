#!/usr/bin/env python3
"""Robot-ghost sprite exploration.

EXPLORATION ONLY. Nothing here is wired into the site. See README.md
in this directory for status, rationale, and open questions.

Holds the nine 12x12 sprite grids plus the continuous tonal-shading
algorithm (flood-fill edge classification -> highlight/shadow tint).
Run directly to render two preview PNGs next to this script:

    python3 sprites.py

Requires only Pillow (already installed in this environment).
"""

from __future__ import annotations

from collections import deque

from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# Sprite data
# ---------------------------------------------------------------------------
# Glyphs: X = body, e = eye/dark recess, l = lit accent, . = empty.
# Every row is exactly 12 chars; every sprite is exactly 12 rows.

SPRITES: dict[str, tuple[list[str], str]] = {
    "flicker": (
        [
            "....X..X....",
            ".....XX.....",
            "..XXXXXXXX..",
            ".XXXXXXXXXX.",
            "XXXXXXXXXXXX",
            "XX.ee..ee.XX",
            "XX.ee..ee.XX",
            "XXXXXXXXXXXX",
            "XXXXXXXXXXXX",
            "XXXXXXXXXXXX",
            "X.XXXXXXXX.X",
            "XX.XX..XX.XX",
        ],
        "#ff6b5b",
    ),
    "shade": (
        [
            "..XXXXXXXX..",
            ".XXXXXXXXXX.",
            "XXXXXXXXXXXX",
            "X.eeeeeeee.X",
            "X.eeeeeeee.X",
            "XXXXXXXXXXXX",
            "XXXXXXXXXXXX",
            "XXXXXXXXXXXX",
            "X.XXXXXXXX.X",
            "XXXXXXXXXXXX",
            "XX.XX..XX.XX",
            "XX.XX..XX.XX",
        ],
        "#ff9de0",
    ),
    "murk": (
        [
            ".XXXXXXXXXX.",
            "XXXXXXXXXXXX",
            "X.XXXXXXXX.X",
            "X.eXXXXXXe.X",
            "X.eeXXXXee.X",
            "X.XXXXXXXX.X",
            "XXXXXXXXXXXX",
            "X..........X",
            "XXXXXXXXXXXX",
            "XXXXXXXXXXXX",
            ".X.X.XX.X.X.",
            ".X.X.XX.X.X.",
        ],
        "#7cc4ff",
    ),
    "haze": (
        [
            "...XXXXXX...",
            "..XlXXXXlX..",
            ".XXXXXXXXXX.",
            "XXXXXXXXXXXX",
            "XX.ee..ee.XX",
            "XXXXXXXXXXXX",
            "XlXXXXXXXXlX",
            "XXXXXXXXXXXX",
            "XXXXXXXXXXXX",
            "XlXXXXXXXXlX",
            "XX.XX..XX.XX",
            "XX.XX..XX.XX",
        ],
        "#ffa64d",
    ),
    "specter": (
        [
            ".....l......",
            ".....X......",
            ".....X......",
            "..XXXXXXXX..",
            ".XXXXXXXXXX.",
            "XXXXXXXXXXXX",
            "XX.eeeeee.XX",
            "XX.eeeeee.XX",
            "XXXXXXXXXXXX",
            "XXXXXXXXXXXX",
            "X.XXXXXXXX.X",
            "XX.XX..XX.XX",
        ],
        "#c58bff",
    ),
    "wisp": (
        [
            "....XXXX....",
            "...XXXXXX...",
            "X.XXXXXXXX.X",
            "XX.X.ee.ee.X",
            "XXXXXXXXXXXX",
            "X.XXXXXXXX.X",
            "...XXXXXX...",
            "...XXXXXX...",
            "..XXXXXXXX..",
            ".XX.XXXX.XX.",
            "....l..l....",
            ".....ll.....",
        ],
        "#ffd54f",
    ),
    "phantom": (
        [
            ".XXXXXXXXXX.",
            "XXXXXXXXXXXX",
            "XXXXXXXXXXXX",
            "X.ee....ee.X",
            "X.ee....ee.X",
            "XXXXXXXXXXXX",
            "X..XXXXXX..X",
            "XXXXXXXXXXXX",
            "X..X....X..X",
            "XXXXXXXXXXXX",
            "XX.XX..XX.XX",
            "XX.XX..XX.XX",
        ],
        "#6b8cff",
    ),
    "ember": (
        [
            "..XXXXXXXX..",
            ".XXXXXXXXXX.",
            "XXXXXXXXXXXX",
            "XX.ee..ee.XX",
            "XXXXXXXXXXXX",
            "X.XXXXXXXX.X",
            "X.XllllllX.X",
            "X.XllllllX.X",
            "X.XXXXXXXX.X",
            "XXXXXXXXXXXX",
            "XX.XX..XX.XX",
            "X..X....X..X",
        ],
        "#7ee787",
    ),
    "chill": (
        [
            "...XXXXXX...",
            "..XXXXXXXX..",
            "X.XXXXXXXX.X",
            "XX.X.ee.ee.X",
            "X.XXXXXXXX.X",
            "XXXXXXXXXXXX",
            "X.X.X..X.X.X",
            "XXXXXXXXXXXX",
            "X.X.X..X.X.X",
            "XXXXXXXXXXXX",
            "XX.XX..XX.XX",
            ".X.X.XX.X.X.",
        ],
        "#5be0c8",
    ),
}

GRID_SIZE = 12

for _name, (_rows, _color) in SPRITES.items():
    assert len(_rows) == GRID_SIZE, f"{_name}: expected {GRID_SIZE} rows, got {len(_rows)}"
    for _r, _row in enumerate(_rows):
        assert len(_row) == GRID_SIZE, (
            f"{_name}: row {_r} has length {len(_row)}, expected {GRID_SIZE} ({_row!r})"
        )
    _bad = set("".join(_rows)) - set("Xel.")
    assert not _bad, f"{_name}: unexpected glyphs {_bad}"

BG_COLOR = "#08070a"
EYE_COLOR = "#0d0b12"
LIT_COLOR = "#fffbe8"


# ---------------------------------------------------------------------------
# Tonal shading
#
# Shading level is continuous, 1.0..4.0 (not discrete presets):
#   i = (level - 1) / 3          # 0.0 at level 1, 1.0 at level 4
#   shadow_mult    = lerp(1.0, 0.58, i)
#   highlight_mult = lerp(1.0, 1.34, i)
#
# Edge classification uses a flood fill from OUTSIDE the sprite to tell
# true silhouette edges from interior holes (eye slots, vents, gaps
# between legs/treads):
#   - "outer-edge":  the empty neighbour is reachable from outside the
#                     sprite (part of the flooded background).
#   - "inner-edge":  the empty neighbour is empty but enclosed (not
#                     reachable from outside) -- an interior hole.
#
# Highlight triggers on a cell whose UP or LEFT neighbour is a gap.
# Shadow triggers on a cell whose DOWN or RIGHT neighbour is a gap.
# Outer edges are checked before inner edges (outer wins if both are
# present for the same cell/direction-group).
#
# Interior edges fade in only at higher levels -- this is the key fix
# that keeps rest-state shading reading as *lighting* rather than a
# heavy outline: their tone weight is
#   weight = clamp((i - 0.55) / 0.45, 0, 1)
# blended from the base color toward the tone color. Outer edges always
# use full weight (1.0).
# ---------------------------------------------------------------------------


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def clamp(v: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, v))


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def rgb_to_hex(rgb: tuple[float, float, float]) -> str:
    return "#" + "".join(f"{max(0, min(255, round(c))):02x}" for c in rgb)


def scale_color(rgb: tuple[int, int, int], mult: float) -> tuple[float, float, float]:
    return (rgb[0] * mult, rgb[1] * mult, rgb[2] * mult)


def blend(base: tuple[int, int, int], target: tuple[float, float, float], t: float) -> tuple[float, float, float]:
    return (
        lerp(base[0], target[0], t),
        lerp(base[1], target[1], t),
        lerp(base[2], target[2], t),
    )


def flood_outside(rows: list[str]) -> set[tuple[int, int]]:
    """Flood fill through empty cells starting from a 1-cell padding
    border around the sprite. Returns the set of (x, y) coordinates in
    padded space (0..GRID_SIZE+1) that are reachable "outside" cells,
    including the real grid cells that are empty and connect to the
    outside.
    """
    size = GRID_SIZE + 2  # padded dimensions
    visited: set[tuple[int, int]] = set()
    start = (0, 0)
    queue = deque([start])
    visited.add(start)

    def is_empty(px: int, py: int) -> bool:
        # padded coords -> grid coords
        gx, gy = px - 1, py - 1
        if 0 <= gx < GRID_SIZE and 0 <= gy < GRID_SIZE:
            return rows[gy][gx] == "."
        return True  # outside the real grid is always "empty"/passable

    while queue:
        px, py = queue.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = px + dx, py + dy
            if 0 <= nx < size and 0 <= ny < size and (nx, ny) not in visited and is_empty(nx, ny):
                visited.add((nx, ny))
                queue.append((nx, ny))

    return visited


def cell(rows: list[str], x: int, y: int) -> str:
    if 0 <= x < GRID_SIZE and 0 <= y < GRID_SIZE:
        return rows[y][x]
    return "."


def render_sprite(rows: list[str], base_hex: str, level: float) -> Image.Image:
    level = clamp(level, 1.0, 4.0)
    i = (level - 1.0) / 3.0
    shadow_mult = lerp(1.0, 0.58, i)
    highlight_mult = lerp(1.0, 1.34, i)
    inner_weight = clamp((i - 0.55) / 0.45, 0.0, 1.0)

    base_rgb = hex_to_rgb(base_hex)
    shadow_rgb = scale_color(base_rgb, shadow_mult)
    highlight_rgb = scale_color(base_rgb, highlight_mult)

    outside = flood_outside(rows)

    img = Image.new("RGB", (GRID_SIZE, GRID_SIZE))

    def is_outer_gap(gx: int, gy: int) -> bool:
        # padded coords for the flooded set
        return (gx + 1, gy + 1) in outside

    for y in range(GRID_SIZE):
        for x in range(GRID_SIZE):
            g = rows[y][x]
            if g == ".":
                img.putpixel((x, y), hex_to_rgb(BG_COLOR))
                continue
            if g == "e":
                img.putpixel((x, y), hex_to_rgb(EYE_COLOR))
                continue
            if g == "l":
                img.putpixel((x, y), hex_to_rgb(LIT_COLOR))
                continue

            # g == "X": tonal shading candidate
            up, left = cell(rows, x, y - 1), cell(rows, x - 1, y)
            down, right = cell(rows, x, y + 1), cell(rows, x + 1, y)

            highlight_dirs = [(x, y - 1, up), (x - 1, y, left)]
            shadow_dirs = [(x, y + 1, down), (x + 1, y, right)]

            def classify(dirs: list[tuple[int, int, str]]) -> str | None:
                # returns "outer", "inner", or None
                gaps = [(gx, gy) for gx, gy, gv in dirs if gv == "."]
                if not gaps:
                    return None
                if any(is_outer_gap(gx, gy) for gx, gy in gaps):
                    return "outer"
                return "inner"

            highlight_kind = classify(highlight_dirs)
            shadow_kind = classify(shadow_dirs)

            rgb: tuple[float, float, float] = base_rgb  # type: ignore[assignment]
            if highlight_kind == "outer":
                rgb = highlight_rgb
            elif shadow_kind == "outer":
                rgb = shadow_rgb
            elif highlight_kind == "inner":
                rgb = blend(base_rgb, highlight_rgb, inner_weight)
            elif shadow_kind == "inner":
                rgb = blend(base_rgb, shadow_rgb, inner_weight)

            img.putpixel((x, y), tuple(round(c) for c in rgb))

    return img


# ---------------------------------------------------------------------------
# Preview rendering
# ---------------------------------------------------------------------------

SCALE = 16
PAD = SCALE
LABEL_H = 18


def upscale(img: Image.Image, scale: int = SCALE) -> Image.Image:
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def get_font():
    try:
        return ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 12)
    except Exception:
        return ImageFont.load_default()


def render_roster(level: float = 2.4) -> Image.Image:
    names = list(SPRITES.keys())
    cols, rows_n = 3, 3
    sprite_px = GRID_SIZE * SCALE
    cell_w = sprite_px + PAD
    cell_h = sprite_px + PAD + LABEL_H
    width = cols * cell_w + PAD
    height = rows_n * cell_h + PAD

    sheet = Image.new("RGB", (width, height), hex_to_rgb(BG_COLOR))
    draw = ImageDraw.Draw(sheet)
    font = get_font()

    for idx, name in enumerate(names):
        row_grid, color = SPRITES[name]
        sprite_img = upscale(render_sprite(row_grid, color, level))
        col, row = idx % cols, idx // cols
        x = PAD // 2 + col * cell_w
        y = PAD // 2 + row * cell_h
        sheet.paste(sprite_img, (x, y))
        draw.text((x, y + sprite_px + 2), f"{name} (L{level})", fill="#e8e6f0", font=font)

    return sheet


def render_ramp(name: str = "ember", levels: list[float] | None = None) -> Image.Image:
    if levels is None:
        levels = [1.0, 2.0, 2.4, 3.0, 4.0]
    rows_grid, color = SPRITES[name]
    sprite_px = GRID_SIZE * SCALE
    cell_w = sprite_px + PAD
    cell_h = sprite_px + PAD + LABEL_H
    width = len(levels) * cell_w + PAD
    height = cell_h + PAD

    strip = Image.new("RGB", (width, height), hex_to_rgb(BG_COLOR))
    draw = ImageDraw.Draw(strip)
    font = get_font()

    for idx, level in enumerate(levels):
        sprite_img = upscale(render_sprite(rows_grid, color, level))
        x = PAD // 2 + idx * cell_w
        y = PAD // 2
        strip.paste(sprite_img, (x, y))
        draw.text((x, y + sprite_px + 2), f"{name} L{level}", fill="#e8e6f0", font=font)

    return strip


def main() -> None:
    import os

    out_dir = os.path.dirname(os.path.abspath(__file__))

    roster = render_roster(level=2.4)
    roster_path = os.path.join(out_dir, "roster_sheet.png")
    roster.save(roster_path)
    print(f"wrote {roster_path} ({roster.width}x{roster.height})")

    ramp = render_ramp(name="ember", levels=[1.0, 2.0, 2.4, 3.0, 4.0])
    ramp_path = os.path.join(out_dir, "level_ramp.png")
    ramp.save(ramp_path)
    print(f"wrote {ramp_path} ({ramp.width}x{ramp.height})")


if __name__ == "__main__":
    main()
