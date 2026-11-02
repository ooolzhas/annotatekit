#!/usr/bin/env python3
"""Cuts the hero demo's layers out of the Figma storyboard ("Frame 1046", exported per frame as figma/f1..f8.svg by
the Figma MCP) into site/reel-layers.js, for site/reel.js to stack and animate.

Every vector comes from Figma as is: text is outlined (SF Pro) and icons are the SF Symbols outlines, so the page
ships no font and nothing is redrawn. All layers share one coordinate system, the 546 x 890 "stage": the 418 x 890
phone frame with 64pt each side for the glass card that overhangs it (f3 and f4 are exported in that system already;
the others are shifted 64 right). Figma's glass doesn't survive SVG export (the "Glass Effect" groups come out empty
and the fills rely on blend modes an <svg> isolates), so every glass "BG" group is dropped here and its rounded rect
is listed in GLASS for reel.js to draw with backdrop-filter instead.

usage: python3 build.py   (writes ../../site/reel-layers.js)
"""
import json
import os
import re
from xml.dom import minidom

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "page", "reel-layers.js")
DOCS = {k: minidom.parse(os.path.join(HERE, "figma", f"{k}.svg")) for k in ("f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8")}
WIDE = {"f3", "f4"}   # exported 546 wide (card overhang); the rest are 418 wide


def by_id(doc, gid, parent_id=None):
    for e in doc.getElementsByTagName("g") + doc.getElementsByTagName("path") + doc.getElementsByTagName("rect"):
        if e.getAttribute("id") == gid and (parent_id is None or e.parentNode.getAttribute("id") == parent_id):
            return e
    raise KeyError(f"{gid} (in {parent_id})")


def screen_group(doc):
    """The clip-path group inside "State 1" that holds the screen's content."""
    state = by_id(doc, "State 1")
    return [c for c in state.childNodes if c.nodeType == 1][0]


def child(parent, gid):
    for c in parent.childNodes:
        if c.nodeType == 1 and (c.getAttribute("id") or c.tagName) == gid:
            return c
    raise KeyError(gid)


def refs(xml):
    return set(re.findall(r'url\(#([^)]+)\)', xml)) | set(re.findall(r'href="#([^"]+)"', xml))


def defs_for(doc, xml):
    """The <defs> children an element references, followed transitively."""
    defs = {e.getAttribute("id"): e for d in doc.getElementsByTagName("defs") for e in d.childNodes
            if e.nodeType == 1 and e.getAttribute("id")}
    want, seen, out = refs(xml), set(), []
    while want:
        i = want.pop()
        if i in seen or i not in defs:
            continue
        seen.add(i)
        x = defs[i].toxml()
        out.append(x)
        want |= refs(x)
    return out


GLASS = []


def strip_glass(node, frame, name):
    """Remove glass BG groups (recording each one's rect) so reel.js can draw real backdrop glass behind the content."""
    for bg in [g for g in node.getElementsByTagName("g") if re.fullmatch(r"BG(_\d+)?", g.getAttribute("id") or "")]:
        if not any((g.getAttribute("id") or "").startswith("Fill + Shadow") for g in bg.getElementsByTagName("g")):
            continue   # a solid button (the blue send), not glass: keep it as exported
        r = bg.getElementsByTagName("rect")
        if r:
            a = r[0].getAttribute
            x = float(a("x") or 0) + (0 if frame in WIDE else 64)
            GLASS.append({"layer": name, "x": x, "y": float(a("y") or 0), "w": float(a("width")), "h": float(a("height")),
                          "r": float(a("rx") or 0)})
        else:   # a pill drawn as a path: take its bounding box from the d attribute
            p = bg.getElementsByTagName("path")[0]
            nums = list(map(float, re.findall(r"-?\d+\.?\d*", p.getAttribute("d"))))
            xs, ys = nums[0::2], nums[1::2]
            x0 = min(xs) + (0 if frame in WIDE else 64)
            GLASS.append({"layer": name, "x": x0, "y": min(ys), "w": max(xs) - min(xs), "h": max(ys) - min(ys),
                          "r": (max(ys) - min(ys)) / 2})
        bg.parentNode.removeChild(bg)
    return node


def layer(name, frame, nodes, clip=True, glass=False):
    """Serialise nodes (from one frame) as a standalone stage-sized <svg>, ids prefixed so layers can share a page."""
    doc = DOCS[frame]
    nodes = [n.cloneNode(True) for n in nodes]
    if glass:
        nodes = [strip_glass(n, frame, name) for n in nodes]
    body = "".join(n.toxml() for n in nodes)
    if clip:   # the screen's rounded clip, from the same frame
        sg = screen_group(doc)
        body = f'<g clip-path="{sg.getAttribute("clip-path")}">{body}</g>'
    defs = defs_for(doc, body)
    shift = "" if frame in WIDE else ' transform="translate(64 0)"'
    svg = f'<svg viewBox="0 0 546 890" fill="none" xmlns="http://www.w3.org/2000/svg"><defs>{"".join(defs)}</defs><g{shift}>{body}</g></svg>'
    p = name.replace(" ", "")
    ids = set(re.findall(r'id="([^"]+)"', svg))
    for i in sorted(ids, key=len, reverse=True):
        svg = svg.replace(f'id="{i}"', f'id="{p}-{i}"').replace(f"url(#{i})", f"url(#{p}-{i})").replace(f'href="#{i}"', f'href="#{p}-{i}"')
    svg = re.sub(r'\s(id)="[^"]*-(?:[^"]*[^\x00-\x7f][^"]*)"', "", svg)          # drop mojibake layer-name ids
    svg = re.sub(r">\s+<", "><", svg)
    svg = re.sub(r'(<g id="[^"]*-Pulsing Wave)"', r'\1" class="reel-halo"', svg)   # the status dot's breathing halo
    # Figma draws the spinner's conic fade as a clipped <foreignObject>; Chrome mis-places it once the pin has a
    # filter, and the spokes are drawn again right after it anyway, so keep the plain spokes only
    def spokes(m):   # the clip path is the spinner's eight spokes: draw them as a plain white shape that CSS spins
        d = re.search(r'<clipPath id="%s"><path d="([^"]+)"' % re.escape(m.group(1)), svg)
        return f'<path class="reel-spin" d="{d.group(1)}" fill="white"/>' if d else ""
    svg = re.sub(r'<g clip-path="url\(#([^)]*angular[^)]*)\)" data-figma-skip-parse="true">.*?</foreignObject></g></g>', spokes, svg)
    # Figma's export writes WebKit-only blend modes into its filters; Chrome rejects the whole value
    svg = svg.replace('mode="plus-lighter"', 'mode="screen"').replace('mode="plus-darker"', 'mode="multiply"')
    return name, svg


def marks(frame):
    """Frame 1027's annotation marks (selections, loop, pins): everything but the overlay, hint, toolbar and scrim."""
    f1027 = child(screen_group(DOCS[frame]), "Frame 1027")
    skip = {"Overlay", "Glow", "Rectangle 4", "HStack", "Interactive"}
    return [c for c in f1027.childNodes if c.nodeType == 1 and (c.getAttribute("id") or c.tagName) not in skip]


def in1027(frame, gid):
    return child(child(screen_group(DOCS[frame]), "Frame 1027"), gid)


L = {}
f1s = screen_group(DOCS["f1"])
f1044 = by_id(DOCS["f1"], "Frame 1044")
add = lambda nt: L.__setitem__(nt[0], nt[1])
add(layer("bezel", "f1", [[c for c in f1044.childNodes if c.nodeType == 1 and c.tagName == "rect"][0]], clip=False))
add(layer("base", "f1", [c for c in f1s.childNodes if c.nodeType == 1 and (c.getAttribute("id") or "") in ("", "Top", "Bottom")]))
add(layer("body", "f1", [child(f1s, "Body")]))
add(layer("bodyFinal", "f8", [child(screen_group(DOCS["f8"]), "Body")]))
add(layer("pillAnnotate", "f1", [child(f1s, "Interactive")], glass=True))
add(layer("pillDone", "f8", [child(screen_group(DOCS["f8"]), "Interactive")], glass=True))
for f in ("f2", "f3", "f5", "f6", "f7"):
    add(layer(f"overlay{f[1]}", f, [in1027(f, "Overlay")] + ([in1027(f, "Glow")] if f == "f2" else [])))
for f in ("f3", "f5", "f6", "f7"):
    add(layer(f"scrim{f[1]}", f, [in1027(f, "Rectangle 4")]))
for f in ("f2", "f5", "f6", "f7"):
    add(layer(f"hint{f[1]}", f, [in1027(f, "HStack")]))
for f in ("f2", "f5", "f6"):
    tb = in1027(f, "Interactive").cloneNode(True)
    if f == "f2":   # "2 notes" appears with the second pin (the count text animates on its own, snappy 0.2)
        count = [p for p in tb.getElementsByTagName("path") if p.getAttribute("id") == "2 notes"][0]
        add(layer("count2", f, [count.cloneNode(True)]))
        count.parentNode.removeChild(count)
    add(layer(f"toolbar{f[1]}", f, [tb], glass=True))
# Marks. Selections and the loop come from frames 2 and 3 with their pins taken out; every pin is cut per state
# (f2/f3 number or "+", f6 spinner, f7 check) into its disc and its glyph, so a state change can crossfade the disc
# and scale the glyph the way the overlay does (PinBadge: glyph scale 0.5 + opacity, snappy 0.25).
PIN_AT = {1: (171, 166), 2: (370, 348), 3: (137, 616)}   # pin centres in phone-frame coordinates


def is_marker(n):
    return n.nodeType == 1 and n.tagName == "g" and (n.getAttribute("id") or "").startswith("Marker")


def without_markers(node):
    n = node.cloneNode(True)
    for m in [g for g in n.getElementsByTagName("g") if is_marker(g)]:
        m.parentNode.removeChild(m)
    return n


def pin_of(marker, frame):
    d = marker.getElementsByTagName("path")[0].getAttribute("d")
    x, y = map(float, re.match(r"M([\d.]+) ([\d.]+)", d).groups())
    x -= 64 if frame in WIDE else 0
    cx, cy = x + 14, y
    return min(PIN_AT, key=lambda k: (PIN_AT[k][0] - cx) ** 2 + (PIN_AT[k][1] - cy) ** 2)


def is_glyph(c):
    return c.nodeType == 1 and (c.getAttribute("fill") == "white" or "angular" in (c.getAttribute("clip-path") or ""))


f1027 = lambda f: child(screen_group(DOCS[f]), "Frame 1027")
add(layer("loop", "f2", [in1027("f2", "Ellipse 1")]))
add(layer("sel2", "f2", [without_markers(in1027("f2", "Selection 1"))]))
add(layer("sel3", "f3", [without_markers(in1027("f3", "Selection 2"))]))
for f in ("f2", "f3", "f6", "f7"):
    for m in [g for g in f1027(f).getElementsByTagName("g") if is_marker(g)]:
        n = pin_of(m, f)
        if f == "f3" and n != 3:
            continue
        disc = m.cloneNode(True)
        for c in [c for c in disc.childNodes if is_glyph(c)]:
            disc.removeChild(c)
        glyph = DOCS[f].createElement("g")
        for c in [c for c in m.childNodes if is_glyph(c)]:
            glyph.appendChild(c.cloneNode(True))
        add(layer(f"pin{n}s{f[1]}disc", f, [disc]))
        add(layer(f"pin{n}s{f[1]}glyph", f, [glyph]))
# the glass card: placeholder (f3) and typed (f4); the typed text on its own so it can be revealed letter by letter
card3 = by_id(DOCS["f3"], "HStack", "Frame 1044")
card4 = by_id(DOCS["f4"], "HStack", "Frame 1044")
add(layer("card3", "f3", [card3], clip=False, glass=True))
c4 = card4.cloneNode(True)
typed = child(c4, "VStack")
c4.removeChild(typed)
add(layer("card4", "f4", [c4], clip=False, glass=True))
add(layer("typed", "f4", [typed], clip=False))

# the typed note is revealed a letter at a time: prefix widths in SF Pro Regular 25.5 (-0.645 tracking), as Figma sets it
from PIL import ImageFont
_f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 255)
_f.set_variation_by_axes([100, 28, 400, 400])
NOTE = "Make it accent color"
TYPED = [round(_f.getlength(NOTE[:i]) / 10 - 0.645 * i, 2) for i in range(len(NOTE) + 1)]

glass = {}
for g in GLASS:
    glass.setdefault(g["layer"], []).append({k: round(v, 2) for k, v in g.items() if k != "layer"})
with open(OUT, "w") as f:
    f.write("/* Generated by tools/hero-html/build.py from the Figma storyboard: do not edit. */\n")
    f.write("window.REEL_SVG = " + json.dumps(L, ensure_ascii=False, separators=(",", ":")) + ";\n")
    f.write("window.REEL_GLASS = " + json.dumps(glass, separators=(",", ":")) + ";\n")
    f.write("window.REEL_TYPED = " + json.dumps(TYPED) + ";\n")
print(f"wrote {OUT}: {len(L)} layers, {sum(map(len, glass.values()))} glass shapes, {os.path.getsize(OUT) // 1024} KB")
for k, v in glass.items():
    print(k, v)
