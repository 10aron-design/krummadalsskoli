#!/usr/bin/env python3
"""Generate the Private Ledger app logo (seal/rosette) as SVG sources.

Brand: dark ink-green field, gold guilloche rosette, central 'kr' wordmark.
Mirrors the hero <svg class="rosette"> in the web app so the icon == the UI.
Outputs:
  assets/icon-only.svg   1024 square, transparent-safe ink field, full bleed seal
  assets/splash.svg       2732 square, centered seal on ink field
  assets/apple-touch.svg  180 square (also reused as in-app touch icon)
"""
import math, os

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "assets")
os.makedirs(ASSETS, exist_ok=True)

INK   = "#0B1F15"
INK2  = "#10271B"
GOLD  = "#C9A227"
GOLDB = "#E8C766"
GOLDD = "#8a7227"
PAPER = "#F6F1E3"

def guilloche(cx, cy, base_rx, step, count, scale=1.0):
    """Concentric rotated ellipses, same recipe as the site's rosette."""
    out = []
    for i in range(count):
        rx = (base_rx + i * step)
        ry = rx * 0.55
        rot = i * 10
        out.append(
            f'<ellipse cx="{cx}" cy="{cy}" rx="{rx:.2f}" ry="{ry:.2f}" '
            f'transform="rotate({rot} {cx} {cy})"/>'
        )
    return "\n      ".join(out)

def seal(size, full_bleed):
    """Return inner SVG markup for a seal centered in a `size` square."""
    cx = cy = size / 2
    pad = size * (0.0 if full_bleed else 0.14)
    R = (size / 2) - pad                      # outer reach of the seal
    base_rx = R * 0.235
    step    = R * 0.041
    rings = guilloche(cx, cy, base_rx, step, 18)
    frame_inset = size * 0.085
    frame = "" if full_bleed else (
        f'<rect x="{frame_inset}" y="{frame_inset}" '
        f'width="{size-2*frame_inset}" height="{size-2*frame_inset}" rx="{size*0.06}" '
        f'fill="none" stroke="{GOLDD}" stroke-width="{size*0.006}" opacity="0.55"/>'
        f'<rect x="{frame_inset*1.45}" y="{frame_inset*1.45}" '
        f'width="{size-2*frame_inset*1.45}" height="{size-2*frame_inset*1.45}" rx="{size*0.05}" '
        f'fill="none" stroke="{GOLD}" stroke-width="{size*0.0028}" '
        f'stroke-dasharray="{size*0.012} {size*0.016}" opacity="0.5"/>'
    )
    core_r = R * 0.30
    kr_size = R * 0.30
    sub_size = R * 0.082
    return f'''
  <defs>
    <radialGradient id="bg" cx="50%" cy="42%" r="72%">
      <stop offset="0%" stop-color="{INK2}"/>
      <stop offset="100%" stop-color="{INK}"/>
    </radialGradient>
    <radialGradient id="core" cx="50%" cy="38%" r="70%">
      <stop offset="0%" stop-color="{INK2}"/>
      <stop offset="100%" stop-color="#0a1a12"/>
    </radialGradient>
  </defs>
  <rect x="0" y="0" width="{size}" height="{size}" rx="{0 if full_bleed else size*0.22}" fill="url(#bg)"/>
  {frame}
  <g fill="none" stroke="{GOLD}" stroke-width="{R*0.006:.2f}" opacity="0.85">
      {rings}
  </g>
  <circle cx="{cx}" cy="{cy}" r="{core_r:.2f}" fill="url(#core)" stroke="{GOLDB}" stroke-width="{R*0.012:.2f}"/>
  <circle cx="{cx}" cy="{cy}" r="{core_r*0.84:.2f}" fill="none" stroke="{GOLD}" stroke-width="{R*0.006:.2f}" opacity="0.7"/>
  <text x="{cx}" y="{cy + kr_size*0.30:.1f}" text-anchor="middle"
        font-family="Georgia, 'Times New Roman', serif" font-weight="bold"
        font-size="{kr_size:.1f}" fill="{GOLDB}">kr</text>
  <text x="{cx}" y="{cy + core_r*0.62:.1f}" text-anchor="middle"
        font-family="Georgia, serif" letter-spacing="{R*0.02:.1f}"
        font-size="{sub_size:.1f}" fill="{GOLD}" opacity="0.8">EST. MMXXVI</text>
'''

def svg(size, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 {size} {size}">{body}</svg>\n')

# icon: full-bleed seal (iOS masks corners itself)
icon = svg(1024, seal(1024, full_bleed=True))
with open(os.path.join(ASSETS, "icon-only.svg"), "w", encoding="utf-8") as f:
    f.write(icon)

# splash: smaller centered seal on full ink field
sp = 2732
seal_sz = 1000
offset = (sp - seal_sz) / 2
splash_body = (
    f'<rect x="0" y="0" width="{sp}" height="{sp}" fill="{INK}"/>'
    f'<g transform="translate({offset} {offset})">{seal(seal_sz, full_bleed=False)}</g>'
)
with open(os.path.join(ASSETS, "splash.svg"), "w", encoding="utf-8") as f:
    f.write(svg(sp, splash_body))
with open(os.path.join(ASSETS, "splash-dark.svg"), "w", encoding="utf-8") as f:
    f.write(svg(sp, splash_body))

# apple-touch / web icon (rounded handled by OS)
with open(os.path.join(ASSETS, "apple-touch.svg"), "w", encoding="utf-8") as f:
    f.write(svg(180, seal(180, full_bleed=True)))

print("logo SVGs written to", ASSETS)
for n in os.listdir(ASSETS):
    print("  ", n)
