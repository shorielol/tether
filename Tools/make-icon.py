"""Writes Tether's AppIcon.icon: two interlocked rings (dusk = strap, ember = phone) on deep navy."""
import json, math, os, sys

OUT = sys.argv[1]
C = 512            # canvas centre (1024 artboard)
R = 204            # ring radius (to stroke centre)
W = 84             # stroke width
OFF = 128          # each centre's offset from the middle
GAP = 20           # clearance either side of the blue ring where ember dips under it
DUSK, EMBER = "#8C9BFF", "#FF8A4C"

blue_c = (C - OFF, C)
ember_c = (C + OFF, C)

def pt(c, deg):
    a = math.radians(deg)
    return c[0] + R * math.cos(a), c[1] + R * math.sin(a)

# Bottom crossing of the two rings (SVG y grows downwards).
h = math.sqrt(R * R - OFF * OFF)
cross = (C, C + h)
cross_deg = math.degrees(math.atan2(cross[1] - ember_c[1], cross[0] - ember_c[0]))
# The blue stroke crosses the ember path at angle theta, so its footprint along that path is W / sin(theta).
theta = math.acos((2 * R * R - (2 * OFF) ** 2) / (2 * R * R))
half_gap = math.degrees(math.asin((W / 2 / math.sin(theta) + GAP) / R))
start, end = cross_deg + half_gap, cross_deg - half_gap + 360
(sx, sy), (ex, ey) = pt(ember_c, start), pt(ember_c, end)

def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            + body + '</svg>\n')

os.makedirs(f"{OUT}/Assets", exist_ok=True)
with open(f"{OUT}/Assets/strap.svg", "w") as f:
    f.write(svg(f'<circle cx="{blue_c[0]}" cy="{blue_c[1]}" r="{R}" fill="none" stroke="{DUSK}" stroke-width="{W}"/>'))
with open(f"{OUT}/Assets/phone.svg", "w") as f:
    f.write(svg(f'<path d="M {sx:.2f} {sy:.2f} A {R} {R} 0 1 1 {ex:.2f} {ey:.2f}" fill="none" '
                f'stroke="{EMBER}" stroke-width="{W}" stroke-linecap="butt"/>'))

def layer(name):
    return {"glass": True, "hidden": False, "image-name": f"{name}.svg", "name": name,
            "position": {"scale": 1, "translation-in-points": [0, 0]}}

icon = {
    "fill": {"automatic-gradient": "srgb:0.10588,0.12157,0.22745,1.00000"},
    "groups": [{
        "hidden": False,
        "layers": [layer("phone"), layer("strap")],   # first is frontmost
        "shadow": {"kind": "neutral", "opacity": 0.5},
        "translucency": {"enabled": True, "value": 0.4},
    }],
    "supported-platforms": {"squares": "shared"},
}
with open(f"{OUT}/icon.json", "w") as f:
    json.dump(icon, f, indent=2)
print("crossing at", cross, "gap", round(half_gap * 2, 1), "deg")
