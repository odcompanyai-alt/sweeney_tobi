"""Generate Tobias's body-part sprites (PNG) and their pivot data.

Run:  python3 tools/make_parts.py
Writes assets/parts/*.png and scripts/part_data.gd.
Everything is drawn in "units" (1 unit = 1 px at pet scale 1.0) and
exported at 2 px/unit so the pet stays crisp when enlarged.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "parts")
GD_OUT = os.path.join(ROOT, "scripts", "part_data.gd")

EXPORT_PX = 2          # output pixels per unit
SS = 4                 # supersampling factor
U = EXPORT_PX * SS     # canvas pixels per unit while drawing
OUTLINE_W = 2.0        # units

C = {
    "outline": (74, 50, 40),
    "hair": (227, 176, 122),
    "hair_dark": (200, 141, 86),
    "hair_light": (242, 202, 152),
    "skin": (252, 245, 231),
    "skin_dark": (238, 224, 200),
    "scarf": (33, 70, 118),
    "scarf_dark": (23, 50, 88),
    "scarf_light": (52, 94, 148),
    "embroid": (186, 48, 66),
    "vest": (110, 108, 70),
    "vest_dark": (88, 86, 56),
    "vest_light": (138, 136, 92),
    "shirt": (250, 250, 246),
    "shirt_dark": (226, 226, 218),
    "skirt": (124, 36, 52),
    "skirt_dark": (94, 26, 39),
    "shoe": (40, 44, 62),
    "shoe_light": (70, 76, 100),
    "wood": (205, 156, 98),
    "wood_dark": (166, 118, 68),
    "wood_light": (225, 184, 128),
    "label": (250, 240, 214),
    "bottle": (92, 170, 120),
    "bottle_dark": (60, 128, 86),
    "cork": (176, 120, 70),
    "whisky": (200, 124, 50),
    "whisky_dark": (156, 88, 32),
    "whisky_light": (246, 214, 160),
    "plate": (238, 241, 247),
    "plate_dark": (206, 212, 224),
    "crust": (234, 176, 96),
    "crust_dark": (198, 130, 64),
    "crust_light": (250, 218, 156),
    "stamp_red": (181, 31, 43),
    "gold": (234, 182, 72),
    "gold_dark": (190, 138, 40),
    "gold_light": (255, 232, 156),
    "watch_face": (253, 250, 240),
}


class Part:
    def __init__(self, name, x0, y0, x1, y1):
        m = OUTLINE_W + 1
        self.name = name
        self.x0, self.y0 = x0 - m, y0 - m
        self.x1, self.y1 = x1 + m, y1 + m
        self.w = int(round((self.x1 - self.x0) * U))
        self.h = int(round((self.y1 - self.y0) * U))
        self.fill = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.fill)

    # --- coordinate helpers -------------------------------------------
    def p(self, x, y):
        return ((x - self.x0) * U, (y - self.y0) * U)

    def box(self, cx, cy, rx, ry):
        a = self.p(cx - rx, cy - ry)
        b = self.p(cx + rx, cy + ry)
        return [a[0], a[1], b[0], b[1]]

    # --- primitives -----------------------------------------------------
    def ellipse(self, cx, cy, rx, ry, col):
        self.d.ellipse(self.box(cx, cy, rx, ry), fill=col)

    def circle(self, cx, cy, r, col):
        self.ellipse(cx, cy, r, r, col)

    def rrect(self, x0, y0, x1, y1, r, col):
        a, b = self.p(x0, y0), self.p(x1, y1)
        self.d.rounded_rectangle([a[0], a[1], b[0], b[1]], radius=r * U, fill=col)

    def poly(self, pts, col):
        self.d.polygon([self.p(x, y) for x, y in pts], fill=col)

    def line(self, pts, width, col):
        pp = [self.p(x, y) for x, y in pts]
        self.d.line(pp, fill=col, width=int(width * U), joint="curve")
        r = width * U / 2
        for x, y in (pp[0], pp[-1]):
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=col)

    def arc(self, cx, cy, rx, ry, a0, a1, width, col):
        self.d.arc(self.box(cx, cy, rx, ry), a0, a1, fill=col, width=int(width * U))
        # round caps
        for a in (a0, a1):
            t = math.radians(a)
            x, y = cx + rx * math.cos(t), cy + ry * math.sin(t)
            r = width / 2
            self.circle(x, y, r, col)

    # --- finishing ------------------------------------------------------
    def save(self, outline=True):
        img = self.fill
        if outline:
            alpha = np.array(img.split()[3]) > 127
            dil = alpha.copy()
            r = OUTLINE_W * U
            for rad in (r, r * 0.5):
                for k in range(48):
                    t = 2 * math.pi * k / 48
                    dx, dy = int(round(rad * math.cos(t))), int(round(rad * math.sin(t)))
                    dil |= np.roll(np.roll(alpha, dy, axis=0), dx, axis=1)
            base = np.zeros((self.h, self.w, 4), dtype=np.uint8)
            base[dil] = (*C["outline"], 255)
            out = Image.fromarray(base, "RGBA")
            out.alpha_composite(img)
            img = out
        img = img.resize((self.w // SS, self.h // SS), Image.LANCZOS)
        img.save(os.path.join(OUT_DIR, self.name + ".png"))
        pivot = (-self.x0 * EXPORT_PX, -self.y0 * EXPORT_PX)
        return self.name, pivot


# ======================================================================
# Parts. Origin of each part = its pivot.
# ======================================================================

def head():
    # pivot: neck (bottom centre of the face). Head spans y -84..0
    p = Part("head", -52, -86, 52, 2)
    # ears
    for s in (-1, 1):
        p.circle(41 * s, -36, 10, C["skin_dark"])
        p.circle(41 * s, -36, 8.2, C["skin"])
        p.circle(42 * s, -36, 4, C["skin_dark"])
    # head (the bald dome is visible when the wig comes off)
    p.ellipse(0, -42, 42, 41, C["skin"])
    p.ellipse(0, -14, 26, 10, C["skin_dark"])  # soft chin shade
    p.ellipse(0, -18, 30, 12, C["skin"])
    return p.save()


def wig_shape(p, col, grow=0.0):
    cx, cy, R = 0, -50, 42
    for k in range(13):
        t = math.radians(188 + k * (164 / 12))
        p.circle(cx + (R - 8) * math.cos(t), cy + (R - 8) * math.sin(t) * 0.95, 14 + grow, col)
    p.ellipse(cx, -68, 38 + grow, 22 + grow, col)
    # side tufts that frame the face above the ears
    for s in (-1, 1):
        p.circle(40 * s, -50, 9.5 + grow, col)
        p.circle(37 * s, -60, 11 + grow, col)
    # fringe scallops (curly bangs)
    for i, x in enumerate((-29, -15, 0, 15, 29)):
        p.circle(x, -62 + (2.5 if i % 2 == 0 else 0), 9 + grow, col)


def curl(p, x, y, r, turns, col, flip=1):
    pts = []
    n = 24
    for i in range(n + 1):
        f = i / n
        t = flip * (f * turns * 2 * math.pi) + math.pi * 0.5
        rr = r * (1 - 0.65 * f)
        pts.append((x + rr * math.cos(t), y + rr * math.sin(t)))
    p.line(pts, 1.9, col)


def wig():
    # same origin as the head so it sits on it at offset (0, 0)
    p = Part("wig", -56, -104, 56, -38)
    wig_shape(p, C["hair_dark"], grow=0.0)
    wig_shape(p, C["hair"], grow=-1.8)
    # highlights
    p.ellipse(-12, -82, 13, 5.5, C["hair_light"])
    p.ellipse(15, -80, 7, 3.5, C["hair_light"])
    # curls
    d = C["hair_dark"]
    for i, (x, y) in enumerate([(-30, -72), (-8, -74), (16, -71), (34, -62),
                                (-38, -56), (-20, -63), (4, -63), (24, -57)]):
        curl(p, x, y, 5.5, 0.85, d, 1 if i % 2 else -1)
    # little curl on the very top
    curl(p, 3, -94, 5, 0.9, d, 1)
    return p.save()


def body():
    # pivot: bottom centre of the skirt. Neck at (0, -44)
    p = Part("body", -30, -48, 30, 2)
    # shirt
    p.rrect(-24, -46, 24, -12, 12, C["shirt"])
    # vest
    p.rrect(-21, -42, 21, -8, 9, C["vest"])
    p.line([(-19, -15), (19, -15)], 1.0, C["vest_dark"])
    p.line([(-4, -38), (-4, -14)], 1.0, C["vest_light"])
    p.line([(4, -38), (4, -14)], 1.0, C["vest_light"])
    # skirt
    p.poly([(-23, -14), (23, -14), (27, -1), (-27, -1)], C["skirt"])
    p.rrect(-27, -6, 27, 0, 3, C["skirt"])
    p.line([(-25, -4), (25, -4)], 1.2, C["skirt_dark"])
    for x in (-13, 13):
        p.line([(x, -11), (x * 1.1, -5)], 1.0, C["skirt_dark"])
    return p.save()


def scarf_wrap():
    # pivot: neck
    p = Part("scarf_wrap", -28, -9, 28, 10)
    p.rrect(-27, -8, 27, 8, 8, C["scarf"])
    p.rrect(-27, 2, 27, 8, 5, C["scarf_dark"])
    p.line([(-20, -3), (16, -4)], 1.3, C["scarf_light"])
    # knot
    p.ellipse(13, 2, 8, 7, C["scarf_dark"])
    p.ellipse(13, 1, 6.5, 5.5, C["scarf"])
    return p.save()


def scarf_tail():
    # pivot: top of the hanging end
    p = Part("scarf_tail", -9, -2, 12, 31)
    p.poly([(-7, 0), (7, 0), (10, 29), (-4, 30)], C["scarf"])
    p.poly([(5, 0), (7, 0), (10, 29), (7.5, 29)], C["scarf_dark"])
    p.line([(-3, 27), (9, 26.3)], 1.0, C["scarf_dark"])
    # leaf embroidery (chevrons)
    e = C["embroid"]
    for i, y in enumerate((10, 17, 24)):
        x = 2 + i * 0.7
        p.line([(x - 4, y - 3), (x, y), (x + 4, y - 3)], 1.6, e)
    p.line([(2, 8), (4.2, 28)], 0.9, e)
    return p.save()


def arm():
    # pivot: shoulder. Points down.
    p = Part("arm", -9, -4, 9, 30)
    p.rrect(-7, -3, 7, 16, 7, C["shirt"])
    p.line([(-5, 13), (5, 13)], 1.0, C["shirt_dark"])
    p.circle(0, 20, 8, C["skin"])
    p.ellipse(-2, 18, 3, 2.4, (255, 252, 244))
    return p.save()


def foot():
    # pivot: bottom centre
    p = Part("foot", -12, -14, 12, 1)
    p.ellipse(0, -6.5, 11.5, 7, C["shoe"])
    p.ellipse(-3, -9, 4.5, 2.2, C["shoe_light"])
    return p.save()


def box():
    # Pirelli's elixir crate. pivot: bottom centre, top surface at y = -40
    p = Part("box", -38, -42, 38, 1)
    p.rrect(-37, -41, 37, 0, 4, C["wood"])
    p.rrect(-37, -41, 37, -35, 3, C["wood_light"])
    for y in (-27, -14):
        p.line([(-34, y), (34, y)], 1.2, C["wood_dark"])
    for x in (-31, 31):
        p.line([(x, -36), (x, -3)], 2.4, C["wood_dark"])
    # nails
    for x in (-31, 31):
        for y in (-32, -7):
            p.circle(x, y, 1.3, C["outline"])
    # label with a tiny elixir bottle
    p.rrect(-14, -30, 14, -9, 3, C["label"])
    p.rrect(-4, -24, 4, -12, 2.5, C["bottle"])
    p.rrect(-2, -27, 2, -23, 1, C["bottle_dark"])
    p.rrect(-2.2, -29, 2.2, -26.5, 1, C["cork"])
    p.ellipse(-1.6, -18, 1.1, 3, (190, 240, 205))
    for x in (-10, 10):
        p.line([(x - 1.5, -19), (x + 1.5, -19)], 0.9, C["embroid"])
        p.line([(x, -20.5), (x, -17.5)], 0.9, C["embroid"])
    return p.save()


def whiskey():
    # pivot: where the hand grips the bottle
    p = Part("whiskey", -8, -27, 8, 14)
    p.rrect(-2.6, -23, 2.6, -11, 1.5, C["whisky"])
    p.rrect(-3.3, -27, 3.3, -22, 1.2, C["cork"])
    p.rrect(-7, -14, 7, 13, 4, C["whisky"])
    p.rrect(-7, 1, 7, 13, 4, C["whisky_dark"])
    p.rrect(-5.5, -7, 5.5, 4, 1.5, C["label"])
    p.line([(-3, -3.5), (3, -3.5)], 0.9, C["embroid"])
    p.line([(-3, -0.5), (3, -0.5)], 0.8, C["whisky_dark"])
    p.rrect(-5.6, -12, -3.9, -8, 0.8, C["whisky_light"])
    p.rrect(-5.6, 5, -3.9, 10, 0.8, C["whisky_light"])
    return p.save()


def pie():
    # pivot: centre of the plate
    p = Part("pie", -27, -18, 27, 7)
    p.ellipse(0, 1.5, 26, 5, C["plate"])
    p.ellipse(0, 0.5, 21, 3.4, C["plate_dark"])
    p.rrect(-20, -8, 20, 1, 4, C["crust_dark"])
    p.ellipse(0, -8, 20, 7, C["crust"])
    for x in (-10, 0, 10):
        p.line([(x - 4, -13), (x + 4, -3.5)], 1.1, C["crust_dark"])
    for x in (-10, 0, 10):
        p.line([(x + 4, -13), (x - 4, -3.5)], 1.1, C["crust_dark"])
    p.ellipse(-8, -11, 5, 1.6, C["crust_light"])
    for x in range(-17, 18, 5):
        p.circle(x, -1.5, 1.2, C["crust_light"])
    return p.save()


def stamp():
    # big rubber stamp, pivot: middle of the handle
    p = Part("stamp", -18, -18, 18, 21)
    p.rrect(-3.8, -8, 3.8, 9, 2, C["wood_dark"])
    p.circle(0, -11, 7, C["wood"])
    p.circle(-2.2, -13, 2.4, C["wood_light"])
    p.rrect(-17, 7, 17, 15, 3, C["wood"])
    p.line([(-14, 9.5), (14, 9.5)], 1.0, C["wood_light"])
    p.rrect(-16, 13.5, 16, 20, 2, C["stamp_red"])
    return p.save()


def pocketwatch():
    # pivot: centre of the dial (the second hand is drawn in code)
    p = Part("pocketwatch", -11, -17, 13, 13)
    for x, y in ((7, 7), (9.5, 9.5), (11.5, 12)):
        p.circle(x, y, 1.6, C["gold_dark"])
    p.rrect(-2.2, -16, 2.2, -11, 1.2, C["gold_dark"])
    p.circle(0, -16.5, 2.0, C["gold"])
    p.circle(0, 0, 10, C["gold_dark"])
    p.circle(0, 0, 9, C["gold"])
    p.circle(0, 0, 7.2, C["watch_face"])
    for k in range(12):
        t = math.radians(k * 30)
        p.circle(5.8 * math.sin(t), -5.8 * math.cos(t), 0.55 if k % 3 else 0.8, C["outline"])
    p.line([(0, 0), (0, -4.2)], 0.9, C["outline"])
    p.line([(0, 0), (2.8, 1.2)], 0.9, C["outline"])
    p.ellipse(-4.5, -5.5, 2.2, 1.1, C["gold_light"])
    return p.save()


def write_gd(entries):
    lines = [
        "# Generated by tools/make_parts.py — do not edit by hand.",
        "extends RefCounted",
        "",
        "const PX_PER_UNIT := %d" % EXPORT_PX,
        "",
        "# part name -> pivot in texture pixels",
        "const PIVOTS := {",
    ]
    for name, (px, py) in entries:
        lines.append('\t"%s": Vector2(%.1f, %.1f),' % (name, px, py))
    lines.append("}")
    with open(GD_OUT, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    entries = [head(), wig(), body(), scarf_wrap(), scarf_tail(), arm(), foot(), box(), whiskey(), pie(), stamp(), pocketwatch()]
    write_gd(entries)
    print("wrote", ", ".join(n for n, _ in entries))


if __name__ == "__main__":
    main()
