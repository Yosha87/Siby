#!/usr/bin/env python3
"""Neon logos for Siby, Toby and Gaby (2x2 glowing letters on black).

  Siby - Scid Improved By Yosha   (blue)
  Gaby - Games Archive By Yosha   (violet)
  Toby - The Oracle By Yosha      (pink)

Blue, violet, pink: Yosha's colours; Triby is their gradient (2026-11-10;
Gaby was orange and Toby green before).

Writes:
  scidvspc/icons/siby.ico (16 to 256 px, Siby.exe icon), siby.png, toby.png, gaby.png (512 px)
  scidvspc/tcl/moderne/logos.tcl: the same as base64 PNGs (16 to 128 px) for Tk
  outils/logos/*-acrostiche.png: the full name in columns (README, About)

Usage: python3 outils/logos/generer_logos.py   (Linux, Windows or macOS; needs Pillow)

The font (Liberation Sans Bold, SIL Open Font License, see fonts/) ships with
the repository so the result is the same on every system.
"""
import base64
import io
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))

# Bundled font first, then common system fonts as a fallback
FONT_CANDIDATES = [
    os.path.join(HERE, "fonts", "LiberationSans-Bold.ttf"),
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf",
    "C:\\Windows\\Fonts\\arialbd.ttf",
    "C:\\Windows\\Fonts\\arial.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "arialbd.ttf",
    "arial.ttf",
]

LOGOS = {
    # name: (2x2 letters, glow color, core color, words of the full name)
    "siby": ("SIBY", (64, 196, 255), (200, 240, 255), ["SCID", "IMPROVED", "BY", "YOSHA"]),
    "toby": ("TOBY", (255, 122, 184), (255, 214, 232), ["THE", "ORACLE", "BY", "YOSHA"]),
    "gaby": ("GABY", (160, 104, 255), (222, 204, 255), ["GAMES", "ARCHIVE", "BY", "YOSHA"]),
}

_font_path = None


def font(size):
    """Bold font of the given pixel size (bundled font, else a system one)."""
    global _font_path
    if _font_path is None:
        for path in FONT_CANDIDATES:
            try:
                ImageFont.truetype(path, 10)
                _font_path = path
                break
            except OSError:
                continue
        else:
            sys.exit("No usable bold font found (expected outils/logos/fonts/LiberationSans-Bold.ttf)")
    return ImageFont.truetype(_font_path, size)


def draw_centered(draw, x, y, letter, fnt, fill):
    """Draw a letter centered on (x, y) using its actual outline, not the
    font's line height (accents and descenders would push capitals down)."""
    left, top, right, bottom = fnt.getbbox(letter, anchor="la")
    draw.text((x - (left + right) / 2, y - (top + bottom) / 2), letter, font=fnt, fill=fill, anchor="la")


def neon(size, letters, glow, core, font_px, blur):
    """letters: list of (x, y, letter) centers; returns a black RGBA image."""
    fnt = font(font_px)

    def layer(color):
        # (transparent background of the same color, so blurring does not mix it with black)
        img = Image.new("RGBA", size, color + (0,))
        draw = ImageDraw.Draw(img)
        for x, y, letter in letters:
            draw_centered(draw, x, y, letter, fnt, color + (255,))
        return img

    def strong_blur(radius, gain):
        img = layer(glow).filter(ImageFilter.GaussianBlur(radius))
        img.putalpha(img.getchannel("A").point(lambda a: min(255, int(a * gain))))
        return img

    result = Image.new("RGBA", size, (0, 0, 0, 255))
    if blur > 0:
        # wide soft halo, then a tight one: the neon glow (blur opacity is
        # boosted, otherwise the halo fades into the black)
        result = Image.alpha_composite(result, strong_blur(blur * 1.8, 2.2))
        result = Image.alpha_composite(result, strong_blur(max(1, blur * 0.7), 2.5))
        result = Image.alpha_composite(result, strong_blur(max(0.6, blur * 0.2), 1.5))
    return Image.alpha_composite(result, layer(core))


def icon(name, n):
    letters, glow, core, _ = LOGOS[name]
    # very small sizes: less glow, bigger letters
    small = n <= 32
    font_px = int(n * (0.40 if small else 0.33))
    c1, c2 = n * (0.30 if small else 0.32), n * (0.70 if small else 0.68)
    positions = [(c1, c1, letters[0]), (c2, c1, letters[1]), (c1, c2, letters[2]), (c2, c2, letters[3])]
    blur = 0 if n <= 16 else n * 0.03
    img = neon((n, n), positions, glow, core, font_px, blur)
    # slightly rounded corners
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, n - 1, n - 1], radius=max(2, n // 9), fill=255)
    img.putalpha(mask)
    return img


def acrostic(name):
    _, glow, core, words = LOGOS[name]
    width, height = 600, 600
    step_x, step_y, font_px = 110, 60, 46
    x0 = width / 2 - step_x * (len(words) - 1) / 2
    positions = []
    for i, word in enumerate(words):
        for j, letter in enumerate(word):
            positions.append((x0 + i * step_x, 90 + j * step_y, letter))
    return neon((width, height), positions, glow, core, font_px, 8)


def png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def main():
    icons_dir = os.path.join(ROOT, "scidvspc", "icons")
    tcl = ["###", "### Siby: neon logos (generated by outils/logos/generer_logos.py)",
           "###   Siby - Scid Improved By Yosha, Toby - The Oracle By Yosha,",
           "###   Gaby - Games Archive By Yosha", "###", "",
           "namespace eval ::moderne::logos {", "  variable donnees", "  array set donnees {}", "}", ""]
    for name in LOGOS:
        icon(name, 512).save(os.path.join(icons_dir, name + ".png"))
        acrostic(name).save(os.path.join(HERE, name + "-acrostiche.png"))
        for n in (16, 24, 32, 48, 64, 128):
            data = base64.b64encode(png_bytes(icon(name, n))).decode()
            tcl.append("set ::moderne::logos::donnees(%s,%d) {%s}" % (name, n, data))
    sizes = [16, 24, 32, 48, 64, 128, 256]
    icon("siby", 256).save(os.path.join(icons_dir, "siby.ico"), sizes=[(n, n) for n in sizes],
                           append_images=[icon("siby", n) for n in sizes[:-1]])
    tcl += ["",
            "### Tk image of a logo (name: siby, toby, gaby; size: 16 to 128)",
            "proc ::moderne::logos::image {nom taille} {",
            "  variable donnees",
            "  set img ::moderne::logos::$nom$taille",
            "  if {$img ni [::image names]} {",
            "    if {![info exists donnees($nom,$taille)]} { return {} }",
            "    ::image create photo $img -format png -data $donnees($nom,$taille)",
            "  }",
            "  return $img",
            "}",
            "",
            "### Window icon (taskbar, Alt+Tab): Siby",
            "proc ::moderne::logos::appliquer {} {",
            "  set imgs {}",
            "  foreach n {128 64 48 32 16} { lappend imgs [image siby $n] }",
            "  catch {wm iconphoto . -default {*}$imgs}",
            "}",
            "",
            "### Database switcher icon: Gaby for a database whose name starts",
            "### with \"gaby\"; {} otherwise",
            "proc ::moderne::logos::iconeBase {b} {",
            "  if {![::moderne::actif]} { return {} }",
            "  if {[catch {file tail [sc_base filename $b]} nom]} { return {} }",
            "  if {![string match -nocase gaby* $nom]} { return {} }",
            "  return [image gaby 32]",
            "}",
            "",
            "if {[::moderne::actif]} { ::moderne::logos::appliquer }",
            "",
            "### End of Siby", ""]
    with open(os.path.join(ROOT, "scidvspc", "tcl", "moderne", "logos.tcl"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(tcl))
    print("ok (font: %s)" % _font_path)


if __name__ == "__main__":
    main()
