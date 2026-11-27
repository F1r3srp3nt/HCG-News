#!/usr/bin/env python3
"""Builds the transparent HCG logo variants used by the app from the website's assets.

Usage: python3 logos.py <dir with hcg-news-logo.png and hcg-future-logo.png> <output dir>
(Download them from news.hakmicapitalgroup.com; see docs/DESIGN-SYSTEM.md.)
Requires numpy and Pillow. The logo geometry is never changed: only margins are trimmed
and colours/transparency remapped.
"""
import sys, numpy as np
from PIL import Image

src, out = sys.argv[1], sys.argv[2]

def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)

def trim(rgba, thr, pad):
    ys, xs = np.where(rgba[..., 3] > thr)
    return rgba[max(ys.min() - pad, 0):ys.max() + pad + 1, max(xs.min() - pad, 0):xs.max() + pad + 1]

def web_filter(rgb):  # the website's .official-logo filter: brightness(1.22) contrast(.94)
    return (rgb * 1.22 - 127.5) * 0.94 + 127.5

def save(arr, name, width=None):
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGBA')
    if width and im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(f'{out}/{name}.png', optimize=True)
    print(name, im.size)

# Classic: already transparent silver lettering.
c = trim(np.asarray(Image.open(f'{src}/hcg-news-logo.png').convert('RGBA')).astype(float), 8, 2)
d = c.copy(); d[..., :3] = web_filter(c[..., :3]); save(d, 'HCGClassicLogo-dark')
a = c[..., 3]; intensity = c[..., :3].mean(axis=2) * a / 255
g = 22 + (intensity / 255) * 48                       # graphite ink, highlights slightly lighter
save(np.dstack([g, g, g + 2, ss(6, 70, a) * 255]), 'HCGClassicLogo-light')

# Future: glowing lettering on black -> transparency from brightness.
f = np.asarray(Image.open(f'{src}/hcg-future-logo.png').convert('RGB')).astype(float)
m = f.max(axis=2)
alpha = np.clip((m - 14) / 241, 0, 1)
colour = np.clip(f / np.maximum(alpha[..., None], 1e-6), 0, 255) * (alpha[..., None] > 0)
rgba = trim(np.dstack([colour, alpha * 255]), 60, 24)
dk = rgba.copy(); dk[..., :3] = web_filter(rgba[..., :3]); save(dk, 'HCGFutureLogo-dark', 1200)
# Light: an "engraved" negative: bright lines become dark ink, cyan edges deep signal blue.
ys, xs = np.where(alpha * 255 > 60)
f = f[max(ys.min() - 24, 0):ys.max() + 25, max(xs.min() - 24, 0):xs.max() + 25]; m = f.max(axis=2); rgb = f / 255
mx, mn = rgb.max(axis=2), rgb.min(axis=2)
sat = np.clip(np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0) * 1.3, 0, 1)[..., None]
ink = np.clip((m - 34) / 221, 0, 1) ** 0.72
col = np.array([0.08, 0.08, 0.09]) * (1 - sat) + np.array([0.0, 0.31, 0.50]) * sat
save(np.dstack([col * 255, ink * 255]), 'HCGFutureLogo-light', 1200)
