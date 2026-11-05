"""Draws the RLMM logo: UDK's glossy black badge with the Rocket League Mapmaking emblem in place of the letters "UDK"
and a green chevron. Writes ..\\RLMM.ico (16-256 px) and ..\\logo.png (256 px).

    python -I make-logo.py [--preview out.png]

Needs Pillow. rlmm.png (the RocketLeagueMapmaking logo) is the only input; the badge is drawn from geometry.
"""
import math, os, struct, sys
from io import BytesIO
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
_arg = lambda k, d: sys.argv[sys.argv.index(k) + 1] if k in sys.argv else d
EMBLEM = os.path.join(HERE, _arg('--emblem', 'rlmm.png'))   # rlmm.png (full colour) or any black-on-white emblem (drawn in silver)
CHEVRON = _arg('--chevron', 'green')                       # green, or rl (Rocket League blue/orange)
S = 2048                      # master canvas (square); everything is drawn here and scaled down
BH = S * 0.94                # badge height
BW = BH * 0.882               # badge width (UDK badge proportions)
X0 = (S - BW) / 2
Y0 = (S - BH) / 2 + S * 0.004


def P(u, v):                  # badge-relative (0..1) -> canvas
    return (X0 + u * BW, Y0 + v * BH)


SHOULDER = 0.835              # where the straight sides turn towards the bottom point
SHARP = [P(0, 0), P(1, 0), P(1, SHOULDER), P(0.5, 1.0), P(0, SHOULDER)]
RADII = [0.085, 0.085, 0.035, 0.05, 0.035]   # fillet radius per corner, as a fraction of the badge width


def offset_polygon(pts, d):
    """Move every edge of a convex, clockwise (screen coords) polygon inwards by d."""
    n = len(pts)
    lines = []
    for i in range(n):
        (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % n]
        ex, ey = x2 - x1, y2 - y1
        l = math.hypot(ex, ey)
        nx, ny = -ey / l, ex / l          # inward normal for clockwise order in screen space
        lines.append(((x1 + nx * d, y1 + ny * d), (ex, ey)))
    out = []
    for i in range(n):
        (p, r), (q, s) = lines[i - 1], lines[i]
        cross = r[0] * s[1] - r[1] * s[0]
        t = ((q[0] - p[0]) * s[1] - (q[1] - p[1]) * s[0]) / cross
        out.append((p[0] + t * r[0], p[1] + t * r[1]))
    return out


def rounded(pts, radii, shrink=0.0):
    """Polygon outline with every corner filleted; radii in badge widths, reduced by `shrink` pixels."""
    out = []
    n = len(pts)
    for i in range(n):
        p, a, b = pts[i], pts[i - 1], pts[(i + 1) % n]
        r = max(1.0, radii[i] * BW - shrink)
        u1 = ((a[0] - p[0]), (a[1] - p[1])); l1 = math.hypot(*u1); u1 = (u1[0] / l1, u1[1] / l1)
        u2 = ((b[0] - p[0]), (b[1] - p[1])); l2 = math.hypot(*u2); u2 = (u2[0] / l2, u2[1] / l2)
        half = math.acos(max(-1, min(1, u1[0] * u2[0] + u1[1] * u2[1]))) / 2
        t = r / math.tan(half)
        bis = (u1[0] + u2[0], u1[1] + u2[1]); lb = math.hypot(*bis); bis = (bis[0] / lb, bis[1] / lb)
        c = (p[0] + bis[0] * r / math.sin(half), p[1] + bis[1] * r / math.sin(half))
        s1 = (p[0] + u1[0] * t, p[1] + u1[1] * t)
        s2 = (p[0] + u2[0] * t, p[1] + u2[1] * t)
        a1 = math.atan2(s1[1] - c[1], s1[0] - c[0])
        a2 = math.atan2(s2[1] - c[1], s2[0] - c[0])
        da = a2 - a1
        while da > math.pi: da -= 2 * math.pi
        while da < -math.pi: da += 2 * math.pi
        for k in range(33):
            ang = a1 + da * k / 32
            out.append((c[0] + r * math.cos(ang), c[1] + r * math.sin(ang)))
    return out


def shape_mask(inset):
    m = Image.new('L', (S, S), 0)
    ImageDraw.Draw(m).polygon(rounded(offset_polygon(SHARP, inset), RADII, inset), fill=255)
    return m


def vgradient(stops, y0=0, y1=S):
    """RGBA image with a vertical gradient through (position 0..1, (r,g,b,a)) stops between rows y0 and y1."""
    col = Image.new('RGBA', (1, S))
    px = col.load()
    for y in range(S):
        t = min(1.0, max(0.0, (y - y0) / float(y1 - y0)))
        for i in range(len(stops) - 1):
            (ta, ca), (tb, cb) = stops[i], stops[i + 1]
            if ta <= t <= tb:
                f = 0 if tb == ta else (t - ta) / (tb - ta)
                px[0, y] = tuple(int(round(ca[k] + (cb[k] - ca[k]) * f)) for k in range(4))
                break
    return col.resize((S, S))


def layer(fill, mask):
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    if isinstance(fill, tuple): fill = Image.new('RGBA', (S, S), fill)
    out.paste(fill, (0, 0), mask)
    return out


def masked(img, mask):
    a = ImageChops.multiply(img.getchannel('A'), mask)
    out = img.copy(); out.putalpha(a)
    return out


def emblem_mask():
    src = Image.open(EMBLEM).convert('RGBA')
    bg = Image.new('RGBA', src.size, (255, 255, 255, 255))
    lum = Image.alpha_composite(bg, src).convert('L')
    ink = lum.point(lambda v: 255 - v)
    ink = ink.crop(ink.point(lambda v: 255 if v > 40 else 0).getbbox())
    h = int(BH * 0.585)
    w = int(ink.width * h / ink.height)
    big = ink.resize((w, h), Image.LANCZOS)
    big = big.point(lambda v: 0 if v < 96 else 255 if v > 160 else int((v - 96) * 255 / 64))  # crisp upscaled edges
    m = Image.new('L', (S, S), 0)
    cx, cy = P(0.5, 0.425)
    m.paste(big, (int(cx - w / 2), int(cy - h / 2)))
    return m


def render():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    outer = shape_mask(0)

    # soft drop shadow
    sh = outer.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: v * 0.55)
    sh = ImageChops.offset(sh, 0, int(S * 0.008))
    img = Image.alpha_composite(img, layer((0, 0, 0, 255), sh))

    # bevelled metal rim: bright at the top, dark at the bottom, with a light lip
    rim = vgradient([(0, (178, 178, 178, 255)), (0.18, (120, 120, 120, 255)), (0.6, (62, 62, 62, 255)),
                     (1, (92, 92, 92, 255))], int(Y0), int(Y0 + BH))
    img = Image.alpha_composite(img, masked(rim, outer))
    lip = ImageChops.subtract(outer, shape_mask(S * 0.004))
    img = Image.alpha_composite(img, layer((235, 235, 235, 110), lip))

    # black glass body
    body = shape_mask(BW * 0.03)
    img = Image.alpha_composite(img, layer((6, 6, 7, 255), body))

    # gloss: the lighter upper part, ending in a sweep that dips to the right, like UDK's badge
    sweep = Image.new('L', (S, S), 0)
    pts = [(X0 - 10, Y0 - 10)]
    for k in range(65):
        u = k / 64
        pts.append(P(u, 0.445 + 0.12 * u ** 1.8))
    pts.append((X0 + BW + 10, Y0 - 10))
    ImageDraw.Draw(sweep).polygon(pts, fill=255)
    gloss = vgradient([(0, (112, 112, 116, 255)), (0.55, (58, 58, 62, 255)), (1, (34, 34, 37, 255))],
                      int(Y0), int(Y0 + BH * 0.56))
    img = Image.alpha_composite(img, masked(gloss, ImageChops.multiply(body, sweep.filter(ImageFilter.GaussianBlur(1.5)))))

    # thin inner keyline
    key = ImageChops.subtract(shape_mask(BW * 0.052), shape_mask(BW * 0.058))
    img = Image.alpha_composite(img, layer((92, 92, 96, 150), key))

    if CHEVRON == 'green':
        tl, tr, tip = P(0.275, SHOULDER + 0.008), P(0.725, SHOULDER + 0.008), P(0.5, SHOULDER + 0.097)
        tri = Image.new('L', (S, S), 0)
        ImageDraw.Draw(tri).polygon([tl, tr, tip], fill=255)
        glow_b = tri.filter(ImageFilter.GaussianBlur(S * 0.018)).point(lambda v: v * 0.6)
        img = Image.alpha_composite(img, masked(layer((40, 200, 60, 255), glow_b), body))
        green = vgradient([(0, (150, 240, 140, 255)), (1, (18, 110, 30, 255))], int(tl[1]), int(tip[1]))
        img = Image.alpha_composite(img, masked(green, tri))
        edge = Image.new('L', (S, S), 0)
        ImageDraw.Draw(edge).line([tl, tr], fill=255, width=int(S * 0.006))
        img = Image.alpha_composite(img, layer((255, 255, 255, 200), edge))
    else:
        img = rl_chevron(img, body)
    if EMBLEM.endswith('rlmm.png'):
        return color_emblem(img, body, sweep)
    # the emblem, in brushed silver like UDK's letters, with a cast shadow and a top highlight
    em = emblem_mask()
    shadow = ImageChops.offset(em, int(S * 0.006), int(S * 0.009)).filter(ImageFilter.GaussianBlur(S * 0.006))
    img = Image.alpha_composite(img, layer((0, 0, 0, 230), shadow))
    top, bot = em.getbbox()[1], em.getbbox()[3]
    silver = vgradient([(0, (246, 246, 248, 255)), (0.48, (214, 214, 218, 255)), (0.52, (196, 196, 200, 255)),
                        (1, (168, 168, 174, 255))], top, bot)
    img = Image.alpha_composite(img, masked(silver, em))
    hi = ImageChops.subtract(em, ImageChops.offset(em, 0, int(S * 0.004)))
    img = Image.alpha_composite(img, layer((255, 255, 255, 170), hi))
    return img


def rl_chevron(img, body):
    # chevron: Rocket League blue meets orange at the point
    tl, tr, tip = P(0.275, SHOULDER + 0.008), P(0.725, SHOULDER + 0.008), P(0.5, SHOULDER + 0.097)
    mid = P(0.5, SHOULDER + 0.008)
    glow = Image.new('L', (S, S), 0)
    ImageDraw.Draw(glow).polygon([tl, tr, tip], fill=255)
    glow_b = glow.filter(ImageFilter.GaussianBlur(S * 0.018)).point(lambda v: v * 0.6)
    left = Image.new('L', (S, S), 0); ImageDraw.Draw(left).rectangle([0, 0, mid[0], S], fill=255)
    right = ImageChops.invert(left)
    img = Image.alpha_composite(img, masked(layer((30, 120, 255, 255), ImageChops.multiply(glow_b, left)), body))
    img = Image.alpha_composite(img, masked(layer((255, 130, 20, 255), ImageChops.multiply(glow_b, right)), body))
    blue = vgradient([(0, (92, 172, 255, 255)), (1, (8, 66, 196, 255))], int(tl[1]), int(tip[1]))
    orange = vgradient([(0, (255, 196, 92, 255)), (1, (214, 84, 0, 255))], int(tl[1]), int(tip[1]))
    img = Image.alpha_composite(img, masked(blue, ImageChops.multiply(glow, left)))
    img = Image.alpha_composite(img, masked(orange, ImageChops.multiply(glow, right)))
    edge = Image.new('L', (S, S), 0)
    ImageDraw.Draw(edge).line([tl, tr], fill=255, width=int(S * 0.006))
    img = Image.alpha_composite(img, layer((255, 255, 255, 200), edge))
    return img


def color_emblem(img, body, sweep):
    """The full-colour emblem set into the glass: cast shadow, then the emblem, then a faint gloss over its top half."""
    src = Image.open(EMBLEM).convert('RGBA')
    src = src.crop(src.getchannel('A').point(lambda v: 255 if v > 20 else 0).getbbox())
    h = int(BH * 0.64)
    w = int(src.width * h / src.height)
    big = src.resize((w, h), Image.LANCZOS)
    em = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    cx, cy = P(0.5, 0.43)
    em.paste(big, (int(cx - w / 2), int(cy - h / 2)))
    a = em.getchannel('A')
    shadow = ImageChops.offset(a, int(S * 0.006), int(S * 0.010)).filter(ImageFilter.GaussianBlur(S * 0.008))
    img = Image.alpha_composite(img, layer((0, 0, 0, 255), shadow.point(lambda v: v * 0.9)))
    img = Image.alpha_composite(img, em)
    sheen = vgradient([(0, (255, 255, 255, 70)), (1, (255, 255, 255, 8))], int(Y0), int(Y0 + BH * 0.56))
    img = Image.alpha_composite(img, masked(sheen, ImageChops.multiply(ImageChops.multiply(a, sweep), body)))
    return img

def dib_frame(im):
    s = im.width
    mask_stride = ((s + 31) // 32) * 4
    hdr = struct.pack('<IiiHHIIiiII', 40, s, s * 2, 1, 32, 0, s * s * 4 + mask_stride * s, 0, 0, 0, 0)
    px = im.convert('RGBA').tobytes('raw', 'BGRA', 0, -1)   # bottom-up rows
    return hdr + px + bytes(mask_stride * s)


def write_ico(master, path, sizes=(16, 20, 24, 32, 40, 48, 64, 128, 256)):
    frames = []
    for s in sizes:
        im = master.resize((s, s), Image.LANCZOS)
        if s >= 256:
            b = BytesIO(); im.save(b, 'PNG'); frames.append((s, b.getvalue()))
        else:
            frames.append((s, dib_frame(im)))
    out = struct.pack('<HHH', 0, 1, len(frames))
    off = 6 + 16 * len(frames)
    for s, data in frames:
        out += struct.pack('<BBBBHHII', s % 256, s % 256, 0, 0, 1, 32, len(data), off)
        off += len(data)
    with open(path, 'wb') as f:
        f.write(out + b''.join(d for _, d in frames))


if __name__ == '__main__':
    master = render()
    if '--preview' in sys.argv:
        master.save(sys.argv[sys.argv.index('--preview') + 1])
    else:
        wiz = os.path.dirname(HERE)
        write_ico(master, os.path.join(wiz, 'RLMM.ico'))
        master.resize((256, 256), Image.LANCZOS).save(os.path.join(wiz, 'logo.png'))
        print('Wrote RLMM.ico and logo.png to ' + wiz)
