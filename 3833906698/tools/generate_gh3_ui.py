"""Generate Guitar Hero III style HUD and per-instrument note PNG assets.

Uses only the Python standard library (math, struct, zlib, os) so it works
without Pillow/NumPy. Instrument note sprites use luminance-shaded white/silver
so Project Zomboid's drawTextureScaled(..., a, r, g, b) tints them per lane.
"""

import math
import os
import struct
import zlib

OUT_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "mods", "Zomb-Band", "42", "media", "ui", "ZombBand")
)


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(edge0, edge1, x):
    if edge0 == edge1:
        return 1.0 if x >= edge1 else 0.0
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return a + (b - a) * t


def blend_over(dst, src):
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    out_a = sa + da * (1.0 - sa)
    if out_a <= 1e-6:
        return (0.0, 0.0, 0.0, 0.0)
    r = (sr * sa + dr * da * (1.0 - sa)) / out_a
    g = (sg * sa + dg * da * (1.0 - sa)) / out_a
    b = (sb * sa + db * da * (1.0 - sa)) / out_a
    return (r, g, b, out_a)


def write_png(path, width, height, sampler):
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0
        for x in range(width):
            r, g, b, a = sampler(x + 0.5, y + 0.5, width, height)
            raw.append(int(clamp(r) * 255 + 0.5))
            raw.append(int(clamp(g) * 255 + 0.5))
            raw.append(int(clamp(b) * 255 + 0.5))
            raw.append(int(clamp(a) * 255 + 0.5))

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def sdf_round_box(px, py, bx, by, radius):
    dx = abs(px) - bx + radius
    dy = abs(py) - by + radius
    ox = max(dx, 0.0)
    oy = max(dy, 0.0)
    return math.hypot(ox, oy) + min(max(dx, dy), 0.0) - radius


def sdf_star5(px, py, outer_r, inner_r):
    # 5-point upright star centered at (0, 0)
    ang = math.atan2(py, px) + math.pi / 2.0
    sector = (2.0 * math.pi) / 5.0
    local = ((ang % sector) - sector * 0.5)
    local = abs(local)
    half_sec = sector * 0.5
    p1x, p1y = outer_r, 0.0
    p2x, p2y = inner_r * math.cos(half_sec), inner_r * math.sin(half_sec)
    qx = math.hypot(px, py) * math.cos(local)
    qy = math.hypot(px, py) * math.sin(local)
    ex, ey = p2x - p1x, p2y - p1y
    wx, wy = qx - p1x, qy - p1y
    proj = clamp((wx * ex + wy * ey) / (ex * ex + ey * ey))
    cx, cy = qx - (p1x + ex * proj), qy - (p1y + ey * proj)
    sign = 1.0 if (qx - p1x) * ey - (qy - p1y) * ex < 0 else -1.0
    return sign * math.hypot(cx, cy)


def make_gh3_gem(base_rgb):
    br, bg, bb = base_rgb

    def sample(x, y, w, h):
        nx = (x / w) * 2.0 - 1.0
        ny = (y / h) * 2.0 - 1.0
        r = math.hypot(nx, ny * 1.12)  # slightly perspective-ovalized puck
        if r > 0.96:
            return (0.0, 0.0, 0.0, 0.0)
        aa = 1.0 - smoothstep(0.90, 0.96, r)
        # Drop shadow below lower rim
        sh = 1.0 - smoothstep(0.76, 0.95, r)
        col = (0.04, 0.04, 0.05, 0.55 * aa)

        # Metallic chrome outer bezel (0.68 .. 0.88)
        if r < 0.88:
            bezel_mask = 1.0 - smoothstep(0.84, 0.88, r)
            metal_shine = 0.45 + 0.45 * math.sin(nx * 2.2 - ny * 2.8)
            bezel = (
                mix(0.28, 0.88, clamp(metal_shine)),
                mix(0.29, 0.90, clamp(metal_shine)),
                mix(0.32, 0.94, clamp(metal_shine)),
                bezel_mask,
            )
            col = blend_over(col, bezel)

        # Dark recessed groove (0.65 .. 0.72)
        if r < 0.73:
            groove_a = 1.0 - smoothstep(0.70, 0.73, r)
            col = blend_over(col, (0.08, 0.08, 0.10, groove_a))

        # Vivid colored core (0 .. 0.67)
        if r < 0.68:
            core_a = 1.0 - smoothstep(0.64, 0.68, r)
            radial = 1.0 - (r / 0.68) ** 1.8
            cr = clamp(br * (0.55 + 0.65 * radial))
            cg = clamp(bg * (0.55 + 0.65 * radial))
            cb = clamp(bb * (0.55 + 0.65 * radial))
            col = blend_over(col, (cr, cg, cb, core_a))

        # Glowing white inner ring (0.36 .. 0.47)
        ring_dist = abs(r - 0.41)
        if ring_dist < 0.075:
            ring_a = (1.0 - smoothstep(0.025, 0.075, ring_dist)) * 0.92
            col = blend_over(col, (0.98, 0.98, 1.0, ring_a))

        # Center bright dome + top specular highlight
        if r < 0.25:
            dome_a = (1.0 - smoothstep(0.14, 0.25, r)) * 0.88
            col = blend_over(col, (mix(br, 1.0, 0.65), mix(bg, 1.0, 0.65), mix(bb, 1.0, 0.65), dome_a))

        spec_d = math.hypot((nx + 0.14) * 1.15, (ny + 0.26) * 2.1)
        if spec_d < 0.36:
            spec_a = (1.0 - smoothstep(0.05, 0.36, spec_d)) * 0.78
            col = blend_over(col, (1.0, 1.0, 1.0, spec_a))

        return (col[0], col[1], col[2], col[3] * max(aa, sh * 0.4))

    return sample


def sample_star_gem(x, y, w, h):
    nx = (x / w) * 2.0 - 1.0
    ny = (y / h) * 2.0 - 1.0
    sd = sdf_star5(nx, ny, 0.88, 0.38)
    if sd > 0.09:
        return (0.0, 0.0, 0.0, 0.0)
    col = (0.0, 0.0, 0.0, 0.0)
    glow = (1.0 - smoothstep(-0.02, 0.09, sd)) * 0.65
    col = blend_over(col, (0.20, 0.85, 1.0, glow))
    if sd < 0.02:
        body_a = 1.0 - smoothstep(-0.02, 0.02, sd)
        core = clamp(1.0 + sd * 2.2)
        col = blend_over(
            col,
            (mix(0.18, 0.88, core), mix(0.72, 0.98, core), 1.0, body_a),
        )
    if sd < -0.14:
        in_a = 1.0 - smoothstep(-0.20, -0.14, sd)
        col = blend_over(col, (0.94, 0.99, 1.0, in_a * 0.9))
    return col


def sample_flame(x, y, w, h):
    nx = (x / w) * 2.0 - 1.0
    ny = (y / h) * 2.0 - 1.0
    # Upward teardrop flame profile anchored near bottom-center
    fy = (ny - 0.35) * 0.85
    widen = 1.0 + max(0.0, -fy) * 0.65
    ang = math.atan2(fy, nx)
    lick = 0.09 * math.sin(ang * 5.0) + 0.05 * math.cos(ang * 9.0)
    d = math.hypot(nx * 1.25 / widen, fy) + lick
    if d > 0.95:
        return (0.0, 0.0, 0.0, 0.0)
    outer = 1.0 - smoothstep(0.10, 0.95, d)
    mid = 1.0 - smoothstep(0.05, 0.60, d)
    core = 1.0 - smoothstep(0.02, 0.30, d)
    r = clamp(0.95 * outer + 0.25 * mid)
    g = clamp(0.28 * outer + 0.55 * mid + 0.35 * core)
    b = clamp(0.06 * outer + 0.15 * mid + 0.78 * core)
    a = clamp(outer * 0.85 + core * 0.25)
    return (r, g, b, a)


def sample_rock_meter(x, y, w, h):
    # Semi-circular GH3 rock gauge arch facing upward from bottom center
    nx = (x / w) * 2.0 - 1.0
    ny = ((y / h) - 0.88) * (-2.0 * h / w) * 1.02
    r = math.hypot(nx, ny)
    if ny < -0.12 or r > 0.96:
        return (0.0, 0.0, 0.0, 0.0)
    col = (0.0, 0.0, 0.0, 0.0)
    # Dark obsidian face
    face_a = 1.0 - smoothstep(0.90, 0.95, r)
    if ny < 0.0:
        face_a *= 1.0 - smoothstep(-0.08, 0.0, ny)
    col = blend_over(col, (0.07, 0.06, 0.08, face_a * 0.94))
    # Colored band (r in 0.44 .. 0.82)
    ang = math.atan2(max(0.0, ny), nx)  # pi (left) .. 0 (right)
    frac = 1.0 - (ang / math.pi)  # 0 left -> 1 right
    if 0.42 <= r <= 0.84 and ny >= 0.0:
        band_a = smoothstep(0.42, 0.46, r) * (1.0 - smoothstep(0.80, 0.84, r))
        if frac < 0.333:
            br, bg, bb = (0.86, 0.14, 0.14)
        elif frac < 0.666:
            br, bg, bb = (0.94, 0.78, 0.14)
        else:
            br, bg, bb = (0.18, 0.84, 0.30)
        # Subtle divider ticks
        tick = abs(frac - 0.333) < 0.012 or abs(frac - 0.666) < 0.012
        shade = 0.72 + 0.28 * ((r - 0.42) / 0.42)
        if tick:
            br, bg, bb = (0.12, 0.10, 0.10)
        col = blend_over(col, (br * shade, bg * shade, bb * shade, band_a * 0.95))
    # Molten gold outer metallic rim (0.82 .. 0.93)
    if 0.80 <= r <= 0.94 and ny >= -0.02:
        rim_a = smoothstep(0.80, 0.83, r) * (1.0 - smoothstep(0.90, 0.94, r))
        shine = 0.55 + 0.35 * math.sin(ang * 3.0 + 0.6)
        col = blend_over(col, (0.88 * shine, 0.68 * shine, 0.24 * shine, rim_a))
    # Inner hub arc (r < 0.24)
    if r < 0.24 and ny >= -0.02:
        hub_a = 1.0 - smoothstep(0.20, 0.24, r)
        col = blend_over(col, (0.72, 0.56, 0.22, hub_a))
    return col


def sample_gh3_emblem(x, y, w, h):
    nx = (x / w) * 2.0 - 1.0
    ny = (y / h) * 2.0 - 1.0
    col = (0.0, 0.0, 0.0, 0.0)
    # Winged metallic crest blades behind pick
    ax = abs(nx)
    wing_y = ny + 0.12 - ax * 0.22
    wing_band = math.sin(max(0.0, wing_y + 0.45) * 26.0)
    if ax > 0.26 and ax < 0.95 and -0.45 < wing_y < 0.28:
        taper = 1.0 - smoothstep(0.35, 0.94, ax)
        w_env = smoothstep(-0.45, -0.32, wing_y) * (1.0 - smoothstep(0.12 * taper + 0.04, 0.28 * taper + 0.06, wing_y))
        feather = 0.65 + 0.35 * smoothstep(-0.3, 0.6, wing_band)
        wa = w_env * (1.0 - smoothstep(0.85, 0.95, ax))
        col = blend_over(col, (0.78 * feather, 0.62 * feather, 0.24 * feather, wa * 0.92))

    # Central rounded guitar pick shield
    py = ny - 0.04
    pick_d = ((nx / 0.58) ** 2 + ((py + 0.12) / 0.62) ** 2) - 1.0
    # Taper bottom tip
    if py > 0.0:
        narrow = 1.0 - 0.48 * clamp(py / 0.72)
        pick_d = math.hypot(nx / (0.56 * narrow), (py + 0.12) / 0.70) - 1.0
    else:
        pick_d = math.hypot(nx / 0.58, (py + 0.12) / 0.58) - 1.0

    if pick_d < 0.12:
        border_a = 1.0 - smoothstep(0.06, 0.12, pick_d)
        col = blend_over(col, (0.90, 0.72, 0.26, border_a))
    if pick_d < 0.0:
        inner_a = 1.0 - smoothstep(-0.04, 0.0, pick_d)
        grad = clamp(1.0 - (ny + 0.6) * 0.55)
        col = blend_over(col, (mix(0.32, 0.78, grad), 0.06, 0.09, inner_a))

    # Inner dark flame motif + lightning star inside the crest
    sd = sdf_star5(nx, ny - 0.02, 0.32, 0.14)
    if sd < 0.03:
        st_a = 1.0 - smoothstep(-0.01, 0.03, sd)
        col = blend_over(col, (1.0, 0.88, 0.44, st_a))
    return col


# Grayscale/white luminance-shaded sprites for drawTextureScaled color tinting
def sample_note_pick(x, y, w, h):
    nx = (x / w) * 2.0 - 1.0
    ny = (y / h) * 2.0 - 1.0
    # Downward-pointing guitar pick
    py = ny + 0.05
    narrow = 1.0 - 0.52 * clamp(max(0.0, py) / 0.85)
    d = math.hypot(nx / (0.80 * narrow), (py + 0.10) / 0.84) - 1.0
    if d > 0.08:
        return (0.0, 0.0, 0.0, 0.0)
    a = 1.0 - smoothstep(-0.02, 0.08, d)
    shade = 0.82 - 0.25 * (nx * nx + ny * ny)
    if d > -0.14:
        shade = 1.0
    spec = 1.0 - smoothstep(0.05, 0.35, math.hypot(nx + 0.18, ny + 0.25))
    v = clamp(shade + spec * 0.25)
    return (v, v, v, a)


def sample_note_pad(x, y, w, h):
    nx = (x / w) * 2.0 - 1.0
    ny = (y / h) * 2.0 - 1.0
    d = sdf_round_box(nx, ny, 0.82, 0.58, 0.24)
    if d > 0.08:
        return (0.0, 0.0, 0.0, 0.0)
    a = 1.0 - smoothstep(-0.02, 0.08, d)
    rim = 1.0 - smoothstep(-0.18, -0.06, d)
    center = 1.0 - smoothstep(0.18, 0.42, math.hypot(nx, ny * 1.2))
    v = clamp(0.68 + 0.28 * rim + 0.26 * center)
    return (v, v, v, a)


def sample_note_key(x, y, w, h):
    nx = (x / w) * 2.0 - 1.0
    ny = (y / h) * 2.0 - 1.0
    d = sdf_round_box(nx, ny, 0.78, 0.82, 0.14)
    if d > 0.06:
        return (0.0, 0.0, 0.0, 0.0)
    a = 1.0 - smoothstep(-0.01, 0.06, d)
    # Piano key bevel top->bottom
    v = 0.96 - 0.28 * clamp((ny + 0.8) / 1.6)
    if abs(nx) > 0.62 or ny > 0.64:
        v *= 0.75
    return (clamp(v), clamp(v), clamp(v), a)


def sample_note_vocal(x, y, w, h):
    nx = (x / w) * 2.0 - 1.0
    ny = (y / h) * 2.0 - 1.0
    d = sdf_round_box(nx, ny, 0.88, 0.54, 0.50)
    if d > 0.08:
        return (0.0, 0.0, 0.0, 0.0)
    a = 1.0 - smoothstep(-0.02, 0.08, d)
    highlight = 1.0 - smoothstep(0.0, 0.45, abs(ny + 0.14))
    v = clamp(0.72 + 0.28 * highlight)
    return (v, v, v, a)


def sample_note_notehead(x, y, w, h):
    nx = (x / w) * 2.0 - 1.0
    ny = (y / h) * 2.0 - 1.0
    # Tilted musical notehead oval + right vertical stem
    ca, sa = math.cos(-0.42), math.sin(-0.42)
    rx = nx * ca - ny * sa
    ry = nx * sa + ny * ca
    head_d = math.hypot((rx + 0.16) / 0.58, (ry - 0.24) / 0.42) - 1.0
    stem_d = sdf_round_box(nx - 0.34, ny + 0.20, 0.11, 0.58, 0.05)
    d = min(head_d * 0.42, stem_d)
    if d > 0.07:
        return (0.0, 0.0, 0.0, 0.0)
    a = 1.0 - smoothstep(-0.02, 0.07, d)
    v = clamp(0.95 - 0.20 * math.hypot(nx, ny))
    return (v, v, v, a)


def sample_note_valve(x, y, w, h):
    nx = (x / w) * 2.0 - 1.0
    ny = (y / h) * 2.0 - 1.0
    r = math.hypot(nx, ny)
    if r > 0.92:
        return (0.0, 0.0, 0.0, 0.0)
    a = 1.0 - smoothstep(0.84, 0.92, r)
    outer_ring = 1.0 - smoothstep(0.02, 0.12, abs(r - 0.72))
    pearl = 1.0 - smoothstep(0.32, 0.46, r)
    v = clamp(0.62 + 0.38 * outer_ring + 0.35 * pearl)
    return (v, v, v, a)


def sample_note_arrow(x, y, w, h):
    nx = (x / w) * 2.0 - 1.0
    ny = (y / h) * 2.0 - 1.0
    # Upward chevron wind arrow
    chevron = abs(ny + 0.38 - abs(nx) * 0.78) - 0.22
    side = abs(nx) - 0.80
    d = max(chevron, side)
    if d > 0.08:
        return (0.0, 0.0, 0.0, 0.0)
    a = 1.0 - smoothstep(-0.02, 0.08, d)
    v = clamp(0.98 - 0.22 * abs(nx))
    return (v, v, v, a)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    gems = [
        ("GH3_Gem_1.png", (0.16, 0.92, 0.32)),
        ("GH3_Gem_2.png", (0.98, 0.20, 0.23)),
        ("GH3_Gem_3.png", (1.00, 0.84, 0.16)),
        ("GH3_Gem_4.png", (0.20, 0.56, 1.00)),
        ("GH3_Gem_5.png", (1.00, 0.48, 0.12)),
    ]
    for name, rgb in gems:
        write_png(os.path.join(OUT_DIR, name), 96, 96, make_gh3_gem(rgb))

    write_png(os.path.join(OUT_DIR, "GH3_Gem_Star.png"), 96, 96, sample_star_gem)
    write_png(os.path.join(OUT_DIR, "GH3_Flame.png"), 128, 128, sample_flame)
    write_png(os.path.join(OUT_DIR, "GH3_RockMeter.png"), 220, 120, sample_rock_meter)
    write_png(os.path.join(OUT_DIR, "GH3_Emblem.png"), 192, 192, sample_gh3_emblem)

    shapes = [
        ("GH3_Note_Pick.png", sample_note_pick),
        ("GH3_Note_Pad.png", sample_note_pad),
        ("GH3_Note_Key.png", sample_note_key),
        ("GH3_Note_Vocal.png", sample_note_vocal),
        ("GH3_Note_Notehead.png", sample_note_notehead),
        ("GH3_Note_Valve.png", sample_note_valve),
        ("GH3_Note_Arrow.png", sample_note_arrow),
    ]
    for name, fn in shapes:
        write_png(os.path.join(OUT_DIR, name), 96, 96, fn)

    print(f"Generated {len(gems) + 4 + len(shapes)} GH3 UI assets in {OUT_DIR}")


if __name__ == "__main__":
    main()
