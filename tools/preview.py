"""Quick static preview of the rig (mirrors pet.gd's default layout).

Run:  python3 tools/preview.py OUT.png
"""
import math
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARTS = os.path.join(ROOT, "assets", "parts")
S = 4  # preview pixels per unit
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PIVOTS = {}
for line in open(os.path.join(ROOT, "scripts", "part_data.gd")):
    if "Vector2(" in line:
        name = line.split('"')[1]
        a, b = line.split("Vector2(")[1].split(")")[0].split(",")
        PIVOTS[name] = (float(a), float(b))


def tex(name):
    im = Image.open(os.path.join(PARTS, name + ".png"))
    return im.resize((im.width * S // 2, im.height * S // 2), Image.LANCZOS)


def put(canvas, name, x, y, rot=0.0, flip=False):
    im = tex(name)
    px, py = PIVOTS[name][0] * S / 2, PIVOTS[name][1] * S / 2
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
        px = im.width - px
    # pad so pivot is centre, then rotate
    w, h = im.size
    R = int(math.hypot(max(px, w - px), max(py, h - py))) + 2
    pad = Image.new("RGBA", (2 * R, 2 * R))
    pad.paste(im, (int(R - px), int(R - py)))
    pad = pad.rotate(-rot, resample=Image.BICUBIC)
    ox, oy = canvas.width / 2 + x * S, canvas.height - 40 + y * S
    canvas.alpha_composite(pad, (int(ox - R), int(oy - R)))


def face(d, canvas, hx, hy, wig=True):
    def P(x, y):
        return (canvas.width / 2 + (hx + x) * S, canvas.height - 40 + (hy + y) * S)

    def ell(x, y, rx, ry, col):
        a, b = P(x - rx, y - ry), P(x + rx, y + ry)
        d.ellipse([a, b], fill=col)

    for s in (-1, 1):
        ell(24 * s, -24, 5.5, 3.2, (255, 170, 170, 120))
        ell(15 * s, -34, 5.0, 6.0, (26, 22, 24, 255))
        ell(15 * s - 1.6, -36.4, 1.8, 1.8, (255, 255, 255, 255))
        ell(15 * s + 1.8, -31.8, 0.8, 0.8, (255, 255, 255, 220))
        a, b = P(15 * s - 5.5, -46), P(15 * s + 5.5, -35)
        d.arc([a, b], 225, 315, fill=(232, 116, 59, 255), width=int(1.8 * S))
    ell(0, -26.5, 1.6, 1.4, (205, 132, 92, 255))
    a, b = P(-5, -27), P(5, -20)
    d.arc([a, b], 20, 160, fill=(232, 116, 59, 255), width=int(1.6 * S))


def compose(pose, out=None, bg=(235, 238, 242, 255)):
    W, H = 200 * S // 1, 170 * S
    c = Image.new("RGBA", (W, H), bg)
    put(c, "foot", -11, 0)
    put(c, "foot", 11, 0, flip=True)
    put(c, "arm", -23, -44, pose.get("al", 18))
    put(c, "arm", 23, -44, pose.get("ar", -18), flip=True)
    put(c, "body", 0, -6)
    put(c, "scarf_tail", 12, -46)
    put(c, "head", 0, -48, pose.get("hr", 0))
    if pose.get("wig", True):
        put(c, "wig", 0, -48)
    put(c, "scarf_wrap", 0, -48)
    face(ImageDraw.Draw(c), c, 0, -48)
    if out:
        c.save(out)
    return c


def make_icon(out):
    c = compose({}, None, bg=(0, 0, 0, 0))
    cx, by = c.width / 2, c.height - 40
    box = (int(cx - 66 * S), int(by - 160 * S), int(cx + 66 * S), int(by - 28 * S))
    c.crop(box).resize((256, 256), Image.LANCZOS).save(out)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "preview.png"
    compose({}, out)
    base, ext = os.path.splitext(out)
    compose({"wig": False}, base + "_bald" + ext)
    make_icon(os.path.join(ROOT, "icon.png"))
    print("ok")
