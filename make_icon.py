#!/usr/bin/env python3
"""Generates the Get Up and Walk app icon at assets/icon.png (1024x1024)."""

import os

from PIL import Image, ImageDraw

S = 4              # supersampling factor
SIZE = 1024
C = SIZE * S

# Deep pine green to a brighter green: same family as the accent used in the UI.
TOP = (13, 58, 43)
BOTTOM = (32, 138, 83)
WHITE = (255, 255, 255, 255)


def squircle_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1],
                                        radius=radius, fill=255)
    return m


def vertical_gradient(size, top, bottom):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t)
                                 for i in range(3)))
    return g.resize((size, size), Image.BILINEAR)


def thick_polyline(draw, points, width, fill):
    r = width / 2
    for a, b in zip(points, points[1:]):
        draw.line([a, b], fill=fill, width=int(width))
    for p in points:
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=fill)


def build():
    inset = 92 * S
    plate = C - inset * 2
    radius = int(plate * 0.2237)

    canvas = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    grad = vertical_gradient(plate, TOP, BOTTOM).convert("RGBA")
    grad.putalpha(squircle_mask(plate, radius))
    canvas.alpha_composite(grad, (inset, inset))

    fig = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(fig)

    # Coordinates on the 1024 grid; DX/DY nudge the figure into balance.
    DX, DY = 22, 6
    def P(x, y):
        return ((x + DX) * S, (y + DY) * S)

    head_c, head_r = P(498, 244), 74 * S
    d.ellipse([head_c[0] - head_r, head_c[1] - head_r,
               head_c[0] + head_r, head_c[1] + head_r], fill=WHITE)

    limb = 70 * S
    torso     = [P(482, 378), P(518, 556)]
    front_leg = [P(518, 556), P(608, 668), P(596, 792)]
    back_leg  = [P(518, 556), P(428, 674), P(366, 782)]
    front_arm = [P(488, 404), P(578, 448), P(598, 542)]
    back_arm  = [P(488, 404), P(400, 458), P(374, 552)]

    for path, w in ((back_arm, limb * 0.76), (back_leg, limb),
                    (torso, limb), (front_leg, limb), (front_arm, limb * 0.76)):
        thick_polyline(d, path, w, WHITE)

    # Fading footsteps behind the figure: the visual echo of repeated reminders.
    for i, (x, y, r, a) in enumerate([(300, 812, 20, 150),
                                      (240, 830, 15, 95),
                                      (190, 844, 11, 55)]):
        cx, cy = P(x, y)
        rr = r * S
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(255, 255, 255, a))

    canvas.alpha_composite(fig)
    os.makedirs("assets", exist_ok=True)
    canvas.resize((SIZE, SIZE), Image.LANCZOS).save("assets/icon.png")
    print("wrote assets/icon.png")


if __name__ == "__main__":
    build()
