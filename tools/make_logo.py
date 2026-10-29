"""Turn the Sweeney Todd logo into a transparent stamp sprite with a white halo.

Run:  python3 tools/make_logo.py
Reads tools/logo_source.png, writes assets/logo/sweeney_logo.png.
"""
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "logo_source.png")
OUT = os.path.join(ROOT, "assets", "logo", "sweeney_logo.png")
OUT_WIDTH = 1200

out = Image.open(SRC).convert("RGBA")
if out.getextrema()[3][0] == 255:
    # no transparency in the source: key out the white background
    img = np.asarray(out.convert("RGB")).astype(np.float32) / 255.0
    alpha = np.clip((1.0 - img.min(axis=2) - 0.1) / 0.9, 0.0, 1.0)
    safe = np.maximum(alpha, 1e-4)[..., None]
    rgb = np.clip((img - (1.0 - safe)) / safe, 0.0, 1.0)
    out = Image.fromarray((np.dstack([rgb, alpha]) * 255).astype(np.uint8), "RGBA")
out = out.crop(out.getbbox())
pad = 40
canvas = Image.new("RGBA", (out.width + pad * 2, out.height + pad * 2))
canvas.paste(out, (pad, pad))
# white halo so the stamp reads on dark wallpapers too
a = canvas.split()[3].point(lambda v: 255 if v > 40 else 0)
halo_a = a.filter(ImageFilter.MaxFilter(17)).filter(ImageFilter.GaussianBlur(3)).point(lambda v: min(255, int(v * 1.6)))
halo = Image.new("RGBA", canvas.size, (255, 255, 255, 0))
halo.putalpha(halo_a.point(lambda v: int(v * 0.92)))
halo.alpha_composite(canvas)
canvas = halo
h = round(canvas.height * OUT_WIDTH / canvas.width)
canvas.resize((OUT_WIDTH, h), Image.LANCZOS).save(OUT)
print("wrote", OUT, OUT_WIDTH, h)
