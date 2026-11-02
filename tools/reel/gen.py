#!/usr/bin/env python3
"""Generates scene.rml for the annotatekit.com hero reel: the Figma storyboard ("Frame 1046") rebuilt as a
Rive scene, with every beat keyed on one timeline. Re-time the reel by editing the T table below, then
`./render.sh` renders frames with the Rive CLI and encodes the alpha videos.

Coordinates are Figma's, in points. The artboard is the phone frame (418 x 890: 8pt bezel around the
402 x 874 screen) plus a 64pt margin each side, because the glass card overhangs the phone by 41.5pt
and the page shows through where it does. Everything sits under one root node scaled 2x for a retina render.
"""
import math
import sys

FPS = 60
DURATION = 17.2          # seconds, the loop
ART_W, ART_H = 546, 950  # points; the render is 2x
FX, FY = 64, 20          # phone frame origin in the artboard
SX, SY = FX + 8, FY + 8  # screen origin

# ---- the timeline: seconds into the loop. Cue times for the site's terminal are read from here too. ----
T = dict(
    tap_pill=1.00,       # finger on the Annotate pill
    enter=1.10,          # overlay in: dim + glow, toolbar, hint
    loop0=2.10, loop1=3.00, pin1=3.00,          # circle drawn round the title, pin 1
    sel2=3.90, pin2=4.05,                       # tap the tall bar, pin 2
    sel3=5.00, pin3=5.15, card_in=5.25,         # tap the button, glass card jumps in
    type0=6.20, type1=7.70,                     # "Make it accent color"
    send=8.40, card_out=8.45,                   # send tap, card drops away
    connected=9.10,                             # toolbar: Claude is connected
    send_all=10.20,                             # send tapped on the toolbar: pins spin, glow goes green
    pin_done1=12.60, pin_done2=12.90, pin_done3=13.20,
    applied=13.40,                              # glow back to blue, "Changes applied, reinstalling"
    dismiss=14.90,                              # overlay out, the app is changed
    reset=16.40, loop_end=DURATION,
)
NOTE_TEXT = "Make it accent color"

BLUE = "FF0088FF"
PIN_BLUE = "FF0090FF"
GREEN = "FF34C759"
FONT_ID = "0:9000"
AX_WGHT, AX_WDTH = 2003265652, 2003072104

_id = [100]


def nid():
    _id[0] += 1
    return f"0:{_id[0]}"


class Anim:
    """Keyframes by object id and property; emitted as one LinearAnimation."""

    EASES = {
        "out": (0.16, 1.0, 0.3, 1.0),
        "inout": (0.65, 0.0, 0.35, 1.0),
        "in": (0.5, 0.0, 0.9, 0.4),
        "soft": (0.25, 0.1, 0.25, 1.0),
    }

    def __init__(self):
        self.tracks = {}

    def key(self, obj, prop, points, kind="double"):
        """points: [(t_seconds, value, ease)], ease in hold|linear|EASES. The ease shapes the segment that starts here."""
        self.tracks.setdefault((obj, prop, kind), []).extend(points)

    def fade(self, obj, t0, t1, a=0.0, b=1.0, ease="soft"):
        self.key(obj, "opacity", [(0, a, "hold"), (t0, a, ease), (t1, b, "hold")])

    def pulse(self, obj, t0, t1, ease="soft"):
        """Visible from t0 to t1."""
        self.key(obj, "opacity", [(0, 0, "hold"), (t0, 1, "hold"), (t1, 0, "hold")])

    def xml(self):
        out = [f'<LinearAnimation duration="{int(DURATION * FPS)}" fps="{FPS}" loopValue="oneShot" name="Reel" id="0:6">']
        for (obj, prop, kind), pts in self.tracks.items():
            pts = sorted(pts, key=lambda p: p[0])
            # collapse duplicate times: later wins
            dedup = {}
            for t, v, e in pts:
                dedup[round(t * FPS)] = (v, e)
            frames = sorted(dedup.items())
            out.append(f'  <KeyedObject objectId="{obj}"><KeyedProperty property="{prop}">')
            for i, (fr, (v, e)) in enumerate(frames):
                last = i == len(frames) - 1
                tag = {"double": "KeyFrameDouble", "color": "KeyFrameColor"}[kind]
                val = v if kind == "color" else f"{v:.4f}"
                if last or e == "hold":
                    out.append(f'    <{tag} value="{val}" frame="{fr}"/>')
                elif e == "linear":
                    out.append(f'    <{tag} value="{val}" frame="{fr}" interpolationType="linear"/>')
                else:
                    x1, y1, x2, y2 = self.EASES[e]
                    out.append(f'    <{tag} value="{val}" frame="{fr}" interpolationType="cubic">'
                               f'<CubicEaseInterpolator x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"/></{tag}>')
            out.append("  </KeyedProperty></KeyedObject>")
        out.append("</LinearAnimation>")
        return "\n".join(out)


A = Anim()
layers = []  # bottom -> top; emitted reversed (RML paints the first child on top)


def color(c):
    return f'<SolidColor colorValue="{c}" name="C"/>'


def rect(x, y, w, h, r, fill=None, stroke=None, sw=1, name="Rect", oid=None, extra="", feather=None, opacity=None, cx=False):
    """Rounded rect with its top-left at x,y (origin 0,0 so scaling pivots at the corner unless cx)."""
    oid = oid or nid()
    px, py = (x + w / 2, y + h / 2)
    o = f' opacity="{opacity}"' if opacity is not None else ""
    s = f'<Shape x="{px}" y="{py}" name="{name}" id="{oid}"{o}>'
    s += f'<Rectangle width="{w}" height="{h}" cornerRadiusTL="{r}" name="P"/>'
    if stroke:
        s += f'<Stroke thickness="{sw}" name="S">{color(stroke)}</Stroke>'
    if fill:
        if feather:
            s += f'<Fill fillRule="clockwise" name="F">{color(fill)}<Feather strength="{feather[0]}" offsetY="{feather[1]}" name="Fe"/></Fill>'
        elif fill.startswith("<"):
            s += f'<Fill name="F">{fill}</Fill>'
        else:
            s += f'<Fill name="F">{color(fill)}</Fill>'
    s += extra + "</Shape>"
    return s, oid


def ellipse(cx, cy, w, h, fill=None, stroke=None, sw=1, name="Ellipse", oid=None, opacity=None):
    oid = oid or nid()
    o = f' opacity="{opacity}"' if opacity is not None else ""
    s = f'<Shape x="{cx}" y="{cy}" name="{name}" id="{oid}"{o}><Ellipse width="{w}" height="{h}" name="P"/>'
    if stroke:
        s += f'<Stroke thickness="{sw}" cap="round" join="round" name="S">{color(stroke)}</Stroke>'
    if fill:
        s += f'<Fill name="F">{color(fill)}</Fill>'
    return s + "</Shape>", oid


def poly(points, stroke, sw, closed=False, name="Path", oid=None, trim=None, radius=0, fill=None):
    oid = oid or nid()
    s = f'<Shape name="{name}" id="{oid}"><PointsPath isClosed="{"true" if closed else "false"}" name="P">'
    for px, py in points:
        s += f'<StraightVertex x="{px}" y="{py}" radius="{radius}"/>'
    s += "</PointsPath>"
    if stroke:
        s += f'<Stroke thickness="{sw}" cap="round" join="round" name="S">{color(stroke)}'
        if trim:
            s += f'<TrimPath start="0" end="{trim[0]}" name="Trim" id="{trim[1]}"/>'
        s += "</Stroke>"
    if fill:
        s += f'<Fill name="F">{color(fill)}</Fill>'
    return s + "</Shape>", oid


def text(x, y, content, size, weight=400, fill="FF000000", ox=0.0, oy=0.5, name="Text", oid=None, opacity=None, width=None):
    oid = oid or nid()
    sid = nid()
    o = f' opacity="{opacity}"' if opacity is not None else ""
    sizing = "autoWidth"
    return (f'<Text x="{x}" y="{y}" sizingValue="{sizing}" originX="{ox}" originY="{oy}" name="{name}" id="{oid}"{o}>'
            f'<TextStylePaint fontSize="{size}" fontAssetId="{FONT_ID}" name="S" id="{sid}">'
            f'<TextStyleAxis tag="{AX_WGHT}" axisValue="{weight}" name="W"/>'
            f'<Fill name="F">{color(fill)}</Fill></TextStylePaint>'
            f'<TextValueRun styleId="{sid}" text="{content}" name="R"/></Text>'), oid


def rich(x, y, runs, size, weight=500, ox=0.5, oy=0.5, name="Rich", oid=None, opacity=None):
    """One Text with several coloured runs: runs = [(string, ARGB)]."""
    oid = oid or nid()
    o = f' opacity="{opacity}"' if opacity is not None else ""
    styles, vals = "", ""
    for i, (str_, fill) in enumerate(runs):
        sid = nid()
        styles += (f'<TextStylePaint fontSize="{size}" fontAssetId="{FONT_ID}" name="S{i}" id="{sid}">'
                   f'<TextStyleAxis tag="{AX_WGHT}" axisValue="{weight}" name="W"/><Fill name="F">{color(fill)}</Fill></TextStylePaint>')
        vals += f'<TextValueRun styleId="{sid}" text="{str_}" name="R{i}"/>'
    return (f'<Text x="{x}" y="{y}" sizingValue="autoWidth" originX="{ox}" originY="{oy}" name="{name}" id="{oid}"{o}>{styles}{vals}</Text>'), oid


def node(children, x=0, y=0, name="Node", oid=None, opacity=None, sx=None, sy=None, clip=None, up=True):
    """children are listed bottom -> top (up=True) or top-first; RML paints the first child on top."""
    oid = oid or nid()
    if up:
        children = list(reversed(children))
    a = f' x="{x}" y="{y}"'
    if opacity is not None:
        a += f' opacity="{opacity}"'
    if sx is not None:
        a += f' scaleX="{sx}"'
    if sy is not None:
        a += f' scaleY="{sy}"'
    c = f'<ClippingShape sourceId="{clip}" name="Clip"/>' if clip else ""
    return f'<Node{a} name="{name}" id="{oid}">{c}{"".join(children)}</Node>', oid


def stack(items):
    """items listed bottom -> top, returned top-first for RML."""
    return list(reversed(items))


# ------------------------------------------------------------------------------------------------
# The app screen (State coordinates: 402 x 874, origin top-left of the screen)
# ------------------------------------------------------------------------------------------------
BG, CARD, SKEL, BTN, BTN_IN = "FFF7F7F7", "FFFFFFFF", "FFF2F2F2", "FFEBEBEB", "FFDFDFDF"
screen_items = []   # bottom -> top
screen_items.append(rect(0, 0, 402, 874, 0, BG, name="Screen bg")[0])

# status bar and toolbar circles
def status_bar():
    out = []
    out.append(text(62, 32, "10:09", 17, 600, name="Clock", ox=0.5)[0].replace('x="62"', 'x="77"'))
    # cellular bars
    for i, h in enumerate((4, 6, 8.5, 11)):
        out.append(rect(300 + i * 4.4, 38 - h, 3, h, 1, "FF000000", name="Bar")[0])
    # wifi: three arcs approximated by a small filled wedge
    out.append(poly([(325, 29.5), (332.5, 29.5), (329, 37)], None, 0, closed=True, fill="FF000000", name="Wifi")[0])
    # battery
    out.append(rect(346, 27, 25, 12, 3.8, None, stroke="66000000", sw=1, name="Battery")[0])
    out.append(rect(348, 29, 21, 8, 2.2, "FF000000", name="Charge")[0])
    return out

screen_items.extend(status_bar())
for cx in (38, 364):
    screen_items.append(ellipse(cx, 84, 44, 44, "FFEFEFEF", name="Tool circle")[0])
    screen_items.append(rect(cx - 9, 75, 18, 18, 5, "FFE0E0E0", name="Tool glyph")[0])
screen_items.append(rect(24, 140, 96, 16, 8, SKEL, name="Eyebrow")[0])

# title: normal and larger variants crossfade when the app is "changed"
title_a, title_a_id = text(24, 181, "AnnotateKit", 28, 600, ox=0.0, oy=0.5, name="Title")
title_b, title_b_id = text(24, 183, "AnnotateKit", 34, 600, ox=0.0, oy=0.5, name="Title large", opacity=0)
screen_items.append(title_a)
screen_items.append(title_b)

# activity card (y 222) and its content, in a group so the whole stack can shift after the title grows
act_items = []
act_items.append(rect(16, 0, 370, 186, 28, CARD, name="Activity card")[0])
for x0 in (36, 156):
    act_items.append(rect(x0, 24, 96, 24, 8, SKEL, name="Stat")[0] if x0 == 36 else "")
stat2, stat2_id = rect(156, 24, 96, 24, 8, SKEL, name="Stat 2")
act_items.append(stat2)
act_items.append(rect(36, 54, 48, 12, 6, SKEL, name="Stat sub")[0])
stat2_sub, stat2_sub_id = rect(156, 54, 48, 12, 6, SKEL, name="Stat 2 sub")
act_items.append(stat2_sub)
bars = [(16, 56, 24), (64.9, 29, 51), (113.7, 47, 33), (162.6, 39, 41), (211.4, 65, 15), (260.3, 53, 27)]
for bx, by, bh in bars:
    act_items.append(rect(16 + bx + 4 - 16, 90 + by, 44.9, bh, 12, SKEL, name="Bar")[0])
tall_gray, tall_gray_id = rect(16 + 309.1 + 4 - 16, 90, 44.9, 80, 12, SKEL, name="Tall bar")
tall_blue, tall_blue_id = rect(16 + 309.1 + 4 - 16, 90, 44.9, 80, 12, BLUE, name="Tall bar blue", opacity=0)
act_items.append(tall_gray)
act_items.append(tall_blue)
act_node, act_id = node(act_items, 0, 222, name="Activity")
screen_items.append(act_node)

# list card (y 432)
list_items = [rect(16, 0, 370, 128, 28, CARD, name="List card")[0]]
for ry, w1, w2 in ((0, 128, 58), (64, 96, 90)):
    list_items.append(ellipse(36 + 16, ry + 32, 32, 32, SKEL, name="Avatar")[0])
    list_items.append(rect(16 + 68, ry + 24, w1, 16, 8, SKEL, name="Row text")[0])
    list_items.append(rect(16 + (212 if ry == 0 else 180), ry + 24, w2, 16, 8, SKEL, name="Row meta")[0])
    list_items.append(rect(16 + 286, ry + 24, 64, 16, 8, SKEL, name="Row value")[0])
list_items.append(rect(16 + 68, 64, 302, 1, 0, "FFF0F0F0", name="Divider")[0])
list_node, list_id = node(list_items, 0, 432, name="List")
screen_items.append(list_node)

# primary button (y 584): gray, with a blue copy that fades in
btn_items = [rect(16, 0, 370, 64, 32, BTN, name="Button")[0], rect(16 + 105, 20, 128, 24, 6, BTN_IN, name="Button label")[0]]
btn_blue = [rect(16, 0, 370, 64, 32, BLUE, name="Button blue")[0], rect(16 + 105, 20, 128, 24, 6, "FF40A6FF", name="Button label blue")[0]]
btn_gray_node, btn_gray_id = node(btn_items, 0, 584, name="Button group")
btn_blue_node, btn_blue_id = node(btn_blue, 0, 584, name="Button group blue", opacity=0)
screen_items.append(btn_gray_node)
screen_items.append(btn_blue_node)

# ---- annotation overlay -------------------------------------------------------------------------
dim, dim_id = rect(0, 0, 402, 874, 0, "7A000000", name="Dim", opacity=0)
screen_items.append(dim)

glow_c = nid()
glow = (f'<Shape x="201" y="437" name="Glow" id="{nid()}" opacity="0">'
        f'<Rectangle width="402" height="874" cornerRadiusTL="62" name="P"/>'
        f'<Stroke thickness="40" name="S"><SolidColor colorValue="FF0A84FF" name="C" id="{glow_c}"/><Feather strength="34" name="Fe"/></Stroke></Shape>')
glow_id = glow.split('id="')[1].split('"')[0]
glow2_c = nid()
glow2 = (f'<Shape x="201" y="437" name="Glow core" id="{nid()}" opacity="0">'
         f'<Rectangle width="402" height="874" cornerRadiusTL="62" name="P"/>'
         f'<Stroke thickness="14" name="S"><SolidColor colorValue="FF0A84FF" name="C" id="{glow2_c}"/><Feather strength="14" name="Fe"/></Stroke></Shape>')
glow2_id = glow2.split('id="')[1].split('"')[0]
screen_items += [glow, glow2]

# hand-drawn loop round the title (State coords): a spiral that overlaps itself at the start
loop_pts = []
cx, cy, rx, ry = 88, 62 + 98 - 2, 88, 34
for i in range(0, 61):
    th = math.radians(-100 - 360 * i / 60 * 1.06)
    k = 1 + 0.035 * (i / 60)
    loop_pts.append((round(rx * k * math.cos(th), 2), round(ry * k * math.sin(th), 2)))
trim_id = nid()
loop_shape, loop_id = poly(loop_pts, "FFFFFFFF", 4, trim=(0, trim_id), name="Title loop")
loop_cx, loop_cy = 170 - 64 - 8 + 8, 189 - 8
loop_node, loop_node_id = node([loop_shape], loop_cx, loop_cy, name="Loop")
screen_items.append(loop_node)


def brackets(x, y, w, h, tint="1FFFFFFF"):
    """Corner brackets plus a faint fill, State coords."""
    g = [rect(x, y, w, h, 12, tint, name="Sel fill")[0]]
    L = 11
    for (ax, ay, dx, dy) in ((x, y, 1, 1), (x + w, y, -1, 1), (x, y + h, 1, -1), (x + w, y + h, -1, -1)):
        pts = [(ax + dx * L, ay), (ax, ay), (ax, ay + dy * L)]
        g.append(poly(pts, "FFFFFFFF", 3, radius=4, name="Corner")[0])
    return g


sel2_node, sel2_id = node(brackets(323, 310, 49, 84), name="Selection bar", opacity=0)
sel3_node, sel3_id = node(brackets(14, 582, 374, 68), name="Selection button", opacity=0)
screen_items += [sel2_node, sel3_node]


def pin(cx, cy, number, oid_prefix):
    """A 28pt pin with plus / number / spinner / check faces, each keyed by opacity. Returns node + face ids."""
    ids = {k: nid() for k in ("root", "plus", "num", "spin", "check", "ring")}
    face_plus = node([
        rect(cx - 6, cy - 1, 12, 2, 1, "FFFFFFFF", name="Plus h")[0],
        rect(cx - 1, cy - 6, 2, 12, 1, "FFFFFFFF", name="Plus v")[0]], name="Plus", oid=ids["plus"], opacity=0)[0]
    face_num = text(cx, cy + 0.5, str(number), 15, 700, "FFFFFFFF", ox=0.5, oy=0.5, name="Num", oid=ids["num"], opacity=0)[0]
    spokes = []
    for i in range(8):
        a = math.radians(i * 45)
        spokes.append(rect(cx - 1, cy - 8.5, 2, 4.5, 1, "FFFFFFFF", name="Spoke", opacity=round(1 - i * 0.11, 2)).__getitem__(0).replace(
            f'<Shape x="{cx}" y="{cy - 8.5 + 2.25}"', f'<Shape x="{cx + math.sin(a) * 6.25:.2f}" y="{cy - math.cos(a) * 6.25:.2f}" rotation="{a:.4f}"'))
    face_spin = node(spokes, name="Spinner", oid=ids["spin"], opacity=0)[0]
    check = poly([(cx - 5, cy + 0.5), (cx - 1.5, cy + 4), (cx + 5.5, cy - 4)], "FFFFFFFF", 2.8, name="Check")[0]
    face_check = node([check], name="Check", oid=ids["check"], opacity=0)[0]
    disc_id = nid()
    disc = ellipse(cx, cy, 28, 28, PIN_BLUE, name="Pin disc", oid=disc_id)[0]
    root = node([disc, face_plus, face_num, face_spin, face_check], name=f"Pin {oid_prefix}", oid=ids["root"], opacity=0, sx=1, sy=1)[0]
    # pivot at the pin centre: wrap so scale pops from its own centre
    ids["disc"] = disc_id
    return root, ids, (cx, cy)


# State coords: Marker 1 (149,144) -> centre (163,158); Marker 2 (348,326) -> (362,340); Marker 3 (115,594) -> (129,608)
pin_pos = {1: (163, 158), 2: (362, 340), 3: (129, 608)}
pins = {}
pin_nodes = {}
for n, (cx, cy) in pin_pos.items():
    root, ids, _ = pin(0, 0, n, str(n))
    wrap, wrap_id = node([root], cx, cy, name=f"Pin {n} at")
    pins[n] = ids
    pin_nodes[n] = wrap
    screen_items.append(wrap)

# ---- toolbar (State coords: artboard - (72, 28)) --------------------------------------------------
def glass_circle(cx, cy, d, name):
    return [
        ellipse(cx, cy, d, d, "55FFFFFF", stroke="66FFFFFF", sw=1, name=name + " glass")[0],
    ]


tb = []
tb_back = glass_circle(68 - 8, 822 - 8 - 0, 52, "Back")
tb_send = glass_circle(350 - 8, 822 - 8, 52, "Send")
tb.append(rect(209 - 8 - 107, 796 - 0, 214, 52, 26, "99FFFFFF", stroke="80FFFFFF", sw=1, name="Label pill")[0])
tb.extend(tb_back + tb_send)
tb.append(poly([(60 - 8 + 2, 822 - 8 - 7), (60 - 8 - 4, 822 - 8), (60 - 8 + 2, 822 - 8 + 7)], "FF111111", 2.6, name="Back chevron")[0])
send_dis = node([poly([(350 - 8, 822 - 8 + 7), (350 - 8, 822 - 8 - 7)], "66000000", 2.6, name="Arrow stem")[0],
                 poly([(350 - 8 - 7, 822 - 8 - 1), (350 - 8, 822 - 8 - 8), (350 - 8 + 7, 822 - 8 - 1)], "66000000", 2.6, name="Arrow head")[0]], name="Send arrow dim")
send_blue_disc = ellipse(350 - 8, 822 - 8, 52, 52, BLUE, name="Send blue", opacity=0)
send_arrow_w = node([poly([(350 - 8, 822 - 8 + 7), (350 - 8, 822 - 8 - 7)], "FFFFFFFF", 2.6, name="Arrow stem")[0],
                     poly([(350 - 8 - 7, 822 - 8 - 1), (350 - 8, 822 - 8 - 8), (350 - 8 + 7, 822 - 8 - 1)], "FFFFFFFF", 2.6, name="Arrow head")[0]], name="Send arrow white", opacity=0)
tb.append(send_dis[0])
tb.append(send_blue_disc[0])
tb.append(send_arrow_w[0])
SEND_BLUE, SEND_ARROW_W, SEND_DIS = send_blue_disc[1], send_arrow_w[1], send_dis[1]

# label variants (centre of the pill) and hint variants (above it), swapped with hold keys
LABEL_CX, LABEL_Y = 209 - 8, 822 - 8
HINT_Y = 770 + 0 - 8 + 0
labels = {}
for key, s in (("none", "No notes yet"), ("1", "1 note"), ("2", "2 notes"), ("3", "3 notes"), ("3sent", "3 notes sent")):
    t, tid = text(LABEL_CX, LABEL_Y, s, 17, 500, "FF111111", ox=0.5, oy=0.5, name=f"Label {key}", opacity=0)
    labels[key] = tid
    tb.append(t)
hints = {}      # key -> id; "work"/"applied" keys carry a second counter: hints["work", i]
HINT_W, HINT_DIM, HINT_G = "F2FFFFFF", "8CFFFFFF", GREEN
def hint(key, label, secs=None):
    runs = [("●  ", HINT_G), (label, HINT_W)]
    if secs is not None:
        runs.append((f"  {secs}s", HINT_DIM))
    t_, tid = rich(LABEL_CX, HINT_Y, runs, 12.5, 500, name=f"Hint {key}", opacity=0)
    hints[key] = tid
    tb.append(t_)
t_, tid = text(LABEL_CX, HINT_Y, "Draw, tap or hold to annotate", 12.5, 500, "F2FFFFFF", ox=0.5, oy=0.5, name="Hint draw", opacity=0)
hints["draw"] = tid
tb.append(t_)
hint("conn", "Claude is connected")
for i in range(0, 6):
    hint(("work", i), "Claude is working…", i)
for i in range(0, 4):
    hint(("applied", i), "Changes applied, reinstalling", i)
tb_node, tb_id = node(tb, name="Toolbar", opacity=0)
screen_items.append(tb_node)

# ---- Annotate pill and Done pill (State coords) ---------------------------------------------------
def pill(cx, cy, w, label, name):
    items = [rect(cx - w / 2, cy - 22, w, 44, 22, "FFFFFFFF", name=name + " bg", feather=None)[0].replace("<Fill", '<Fill'),
             rect(cx - w / 2, cy - 22, w, 44, 22, None, stroke="14000000", sw=1, name=name + " rim")[0]]
    items.append(ellipse(cx - w / 2 + 20, cy, 8, 8, GREEN, name=name + " dot")[0])
    items.append(text(cx - w / 2 + 32, cy, label, 17, 500, "FF000000", ox=0.0, oy=0.5, name=name + " label")[0])
    return items

PILL_Y = 826 - 8 + 0
annotate_node, annotate_id = node(pill(209 - 8, PILL_Y, 120, "Annotate", "Annotate"), name="Annotate pill")
done_node, done_id = node(pill(209 - 8, PILL_Y, 184, "Done · 3 changes", "Done"), name="Done pill", opacity=0)
screen_items += [annotate_node, done_node]
screen_items.append(rect(154, 13.7, 94, 37, 18.5, "FF000000", name="Island")[0])

# the screen node, clipped to the rounded screen
clip_shape = (f'<Shape x="201" y="437" name="Screen mask" id="0:8001"><Rectangle width="402" height="874" cornerRadiusTL="62" name="P"/></Shape>')
screen_node, screen_id = node(screen_items, SX, SY, name="Screen", clip="0:8001")
# the mask must live in the same space as the screen content: put it inside the screen node (State coords)
screen_node = screen_node[:-len("</Node>")] + clip_shape + "</Node>"

# ---- phone body -----------------------------------------------------------------------------------
shadow = rect(FX, FY, 418, 890, 70, "59000000", name="Phone shadow", feather=(34, 26))[0]
bezel = rect(FX, FY, 418, 890, 70, "FF000000", name="Bezel")[0]

# ---- glass card (artboard coords; above the bezel; overhangs 41.5 each side) ----------------------
CARD_X, CARD_Y_REST, CARD_W, CARD_H = 22, 706, 501, 162
card = []
card.append(rect(CARD_X, 0, CARD_W, CARD_H, 48, "000000", name="Card shadow", feather=(26, 16), opacity=0.45)[0].replace('"000000"', '"66000000"'))
body_fill = ('<LinearGradient startX="0" startY="-81" endX="0" endY="81" name="G">'
             '<GradientStop colorValue="B8EEEEEE" position="0"/><GradientStop colorValue="B8CFE0F4" position="1"/></LinearGradient>')
card.append(rect(CARD_X, 0, CARD_W, CARD_H, 48, body_fill, stroke="80FFFFFF", sw=1.5, name="Card glass")[0])
for bx in (CARD_X + 12, CARD_X + CARD_W - 40):   # refraction bands near the edges
    card.append(rect(bx, 8, 28, CARD_H - 16, 14, "14000000", name="Card band", feather=(10, 0))[0])
ph, ph_id = text(53, 728 + 20 - CARD_Y_REST, "Describe the change", 24, 400, "73000000", ox=0.0, oy=0.5, name="Placeholder")
card.append(ph)
# typed text revealed by a clip that opens in steps
typed_t, typed_id = text(53, 728 + 20 - CARD_Y_REST, NOTE_TEXT, 24, 400, "FF000000", ox=0.0, oy=0.5, name="Typed", opacity=0)
clip_id, clip_src = nid(), nid()
typed_clip_shape = (f'<Shape x="53" y="{728 + 20 - CARD_Y_REST}" name="Typed clip" id="{clip_src}">'
                    f'<Rectangle width="0" height="60" originX="0" originY="0.5" name="P" id="{clip_id}"/></Shape>')
typed_node = typed_t.replace('opacity="0">', 'opacity="0"><ClippingShape sourceId="%s" name="Clip"/>' % clip_src, 1)
card.append(typed_node)
card.append(typed_clip_shape)
# controls row, y centre 822 -> relative 822-706=116
ROW = 822 - CARD_Y_REST
for cx in (68, 328, 403, 478):
    card.append(ellipse(cx, ROW, 66, 66, "12000000", name="Control")[0])
card.append(rect(110, ROW - 32.5, 97, 65, 32.5, "12000000", name="Fix pill")[0])
card.append(text(133, ROW, "Fix", 24, 500, "FF111111", ox=0.0, oy=0.5, name="Fix label")[0])
card.append(poly([(184, ROW - 4), (189, ROW - 9), (194, ROW - 4)], "FF111111", 2.2, name="Up")[0])
card.append(poly([(184, ROW + 4), (189, ROW + 9), (194, ROW + 4)], "FF111111", 2.2, name="Down")[0])
card.append(poly([(321, ROW - 9), (335, ROW + 9)], "FF111111", 2.8, name="X1")[0])
card.append(poly([(335, ROW - 9), (321, ROW + 9)], "FF111111", 2.8, name="X2")[0])
card.append(poly([(396, ROW + 8), (396, ROW - 2), (402, ROW - 8), (412, ROW - 8)], "FF111111", 2.6, radius=5, name="Redo")[0])
card.append(poly([(406, ROW - 13), (413, ROW - 8), (406, ROW - 3)], "FF111111", 2.6, name="Redo head")[0])
# paperclip: a long capsule outline with an inner hook
card.append(poly([(60, ROW + 9), (72, ROW - 3), (75, ROW - 12), (68, ROW - 14), (56, ROW - 2), (54, ROW + 6), (59, ROW + 13), (67, ROW + 12), (78, ROW + 1)], "FF111111", 2.4, radius=4, name="Clip")[0])
card_send_blue = ellipse(478, ROW, 66, 66, BLUE, name="Card send blue", opacity=0)
card.append(card_send_blue[0])
card.append(node([poly([(478, ROW + 9), (478, ROW - 9)], "FFFFFFFF", 3, name="Stem")[0],
                  poly([(478 - 9, ROW - 1), (478, ROW - 10), (478 + 9, ROW - 1)], "FFFFFFFF", 3, name="Head")[0]], name="Card arrow white", oid=nid(), opacity=0)[0])
CARD_SEND_BLUE = card_send_blue[1]
# the arrow (white) is the last node emitted above; recover its id for keys
card_arrow_id = card[-1].split('id="')[1].split('"')[0]
card_node, card_id = node(card, 0, 980, name="Glass card")

# ---- touch ring ---------------------------------------------------------------------------------------
# (not in the storyboard, so none)

# ---- assemble -----------------------------------------------------------------------------------------
BG_BACKDROP = sys.argv[2] if len(sys.argv) > 2 else None   # "FF000000"/"FFFFFFFF": opaque backdrop for matting (see matte.py)
root_children = [shadow, bezel, screen_node, card_node]   # bottom -> top
if BG_BACKDROP:
    root_children.insert(0, rect(0, 0, ART_W, ART_H, 0, BG_BACKDROP, name="Matte backdrop")[0])
root, root_id = node(root_children, 0, 0, name="Root", sx=2, sy=2)

# ================================================================================================
# keyframes
# ================================================================================================
t = T
A.key(dim_id, "opacity", [(0, 0, "hold"), (t["enter"], 0, "soft"), (t["enter"] + 0.5, 1, "hold"),
                          (t["dismiss"], 1, "soft"), (t["dismiss"] + 0.45, 0, "hold")])
for gid, peak in ((glow_id, 0.8), (glow2_id, 0.55)):
    A.key(gid, "opacity", [(0, 0, "hold"), (t["enter"], 0, "soft"), (t["enter"] + 0.6, peak, "hold"),
                           (t["dismiss"], peak, "soft"), (t["dismiss"] + 0.5, 0, "hold")])
# glow colour: blue -> green while Claude works -> blue
for cid in (glow_c, glow2_c):
    A.key(cid, "colorValue", [(0, "FF0A84FF", "hold"), (t["send_all"], "FF0A84FF", "linear"), (t["send_all"] + 0.6, "FF30D158", "hold"),
                              (t["applied"], "FF30D158", "linear"), (t["applied"] + 0.6, "FF0A84FF", "hold")], kind="color")

# annotate pill: pressed at tap_pill, gone once the toolbar is in; back as "Annotate" at reset
A.key(annotate_id, "opacity", [(0, 1, "hold"), (t["enter"], 1, "soft"), (t["enter"] + 0.25, 0, "hold"),
                               (t["dismiss"] + 0.3, 0, "hold"), (t["reset"], 0, "soft"), (t["reset"] + 0.5, 1, "hold")])
A.key(annotate_id, "scaleX", [(0, 1, "hold"), (t["tap_pill"], 1, "out"), (t["tap_pill"] + 0.1, 0.94, "out"), (t["tap_pill"] + 0.3, 1, "hold")])
A.key(annotate_id, "scaleY", [(0, 1, "hold"), (t["tap_pill"], 1, "out"), (t["tap_pill"] + 0.1, 0.94, "out"), (t["tap_pill"] + 0.3, 1, "hold")])
# done pill: replaces the toolbar on dismiss, fades at reset
A.key(done_id, "opacity", [(0, 0, "hold"), (t["dismiss"] + 0.3, 0, "soft"), (t["dismiss"] + 0.75, 1, "hold"), (t["reset"], 1, "soft"), (t["reset"] + 0.4, 0, "hold")])

# toolbar group
A.key(tb_id, "opacity", [(0, 0, "hold"), (t["enter"] + 0.1, 0, "soft"), (t["enter"] + 0.55, 1, "hold"),
                         (t["card_in"] - 0.05, 1, "soft"), (t["card_in"] + 0.2, 0, "hold"),     # hidden while the card is up
                         (t["card_out"] + 0.25, 0, "soft"), (t["card_out"] + 0.6, 1, "hold"),
                         (t["dismiss"], 1, "soft"), (t["dismiss"] + 0.3, 0, "hold")])
SEND_ACTIVE_T = t["card_out"] + 0.6


def swap(ids_times):
    """ids_times: [(id, t_on, t_off)] with hold keys."""
    for oid, a, b in ids_times:
        A.key(oid, "opacity", [(0, 0, "hold"), (a, 1, "hold")] + ([(b, 0, "hold")] if b is not None else []))

swap([(labels["none"], 0, t["loop1"]), (labels["1"], t["loop1"], t["pin2"]), (labels["2"], t["pin2"], t["pin3"]),
      (labels["3"], t["pin3"], t["send_all"]), (labels["3sent"], t["send_all"], None)])
# hints: draw prompt, "connected" after the card sends, then "working" (counting) and "applied" (counting)
swap([(hints["draw"], 0, t["card_in"]), (hints["conn"], t["connected"], t["send_all"])])
tw = t["send_all"]
for i in range(0, 6):
    a_, b_ = tw + i, min(tw + i + 1, t["applied"])
    if a_ < t["applied"]:
        swap([(hints[("work", i)], a_, b_)])
ta = t["applied"]
for i in range(0, 4):
    a_, b_ = ta + i, min(ta + i + 1, t["dismiss"])
    if a_ < t["dismiss"]:
        swap([(hints[("applied", i)], a_, b_)])
# send button: active (blue) when notes are queued
A.key(SEND_BLUE, "opacity", [(0, 0, "hold"), (SEND_ACTIVE_T, 1, "hold"), (t["send_all"], 0, "hold")])
A.key(SEND_ARROW_W, "opacity", [(0, 0, "hold"), (SEND_ACTIVE_T, 1, "hold"), (t["send_all"], 0, "hold")])
A.key(SEND_DIS, "opacity", [(0, 1, "hold"), (SEND_ACTIVE_T, 0, "hold"), (t["send_all"], 1, "hold")])

# title loop draw-on and pin 1
A.key(trim_id, "end", [(0, 0, "hold"), (t["loop0"], 0, "inout"), (t["loop1"], 1, "hold")])
A.key(loop_node_id, "opacity", [(0, 1, "hold"), (t["dismiss"], 1, "soft"), (t["dismiss"] + 0.4, 0, "hold")])

# selections
for sid, ts in ((sel2_id, t["sel2"]), (sel3_id, t["sel3"])):
    A.key(sid, "opacity", [(0, 0, "hold"), (ts, 0, "out"), (ts + 0.2, 1, "hold"), (t["dismiss"], 1, "soft"), (t["dismiss"] + 0.4, 0, "hold")])

# pins: pop in as "+" (pin 3) or number, spinner while working, check when applied
pin_times = {1: (t["pin1"], "num", t["pin_done1"]), 2: (t["pin2"], "num", t["pin_done2"]), 3: (t["pin3"], "plus", t["pin_done3"])}
for n, (tin, face, tdone) in pin_times.items():
    ids = pins[n]
    root_k = ids["root"]
    A.key(root_k, "opacity", [(0, 0, "hold"), (tin, 1, "hold"), (t["dismiss"], 1, "soft"), (t["dismiss"] + 0.35, 0, "hold")])
    for ax in ("scaleX", "scaleY"):
        A.key(root_k, ax, [(0, 0.2, "hold"), (tin, 0.2, "out"), (tin + 0.16, 1.18, "out"), (tin + 0.3, 1, "hold")])
    if n == 3:
        A.key(ids["plus"], "opacity", [(0, 0, "hold"), (tin, 1, "hold"), (t["card_out"], 0, "hold")])
        A.key(ids["num"], "opacity", [(0, 0, "hold"), (t["card_out"], 1, "hold"), (t["send_all"], 0, "hold")])
    else:
        A.key(ids["num"], "opacity", [(0, 0, "hold"), (tin, 1, "hold"), (t["send_all"], 0, "hold")])
    A.key(ids["spin"], "opacity", [(0, 0, "hold"), (t["send_all"], 1, "hold"), (tdone, 0, "hold")])
    A.key(ids["check"], "opacity", [(0, 0, "hold"), (tdone, 1, "hold")])
# spinner rotation
for n in pins:
    sp = pins[n]["spin"]
    pts = [(0, 0.0, "hold")]
    tt = t["send_all"]
    pts.append((tt, 0.0, "linear"))
    pts.append((t["applied"], 2 * math.pi * 1.5 * (t["applied"] - tt) / 1.0, "hold"))
    A.key(sp, "rotation", pts)

# the glass card: jumps in from below the phone, overshooting, then drops away on send
CARD_REST_REL = CARD_Y_REST
ci, co = t["card_in"], t["card_out"]
A.key(card_id, "y", [(0, 980, "hold"), (ci, 980, "out"), (ci + 0.34, CARD_REST_REL - 22, "out"), (ci + 0.62, CARD_REST_REL, "hold"),
                     (co, CARD_REST_REL, "in"), (co + 0.4, 990, "hold")])
A.key(typed_id, "opacity", [(0, 0, "hold"), (t["type0"], 1, "hold")])
# typed one character at a time: the clip opens to each prefix width (measured with the same font)
from PIL import ImageFont
_f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 100)
_f.set_variation_by_axes([100, 28, 400, 400])
pre = [_f.getlength(NOTE_TEXT[:i]) / 100 * 24 + 2 for i in range(len(NOTE_TEXT) + 1)]
n = len(NOTE_TEXT)
A.key(clip_id, "width", [(0, 0, "hold")] + [(t["type0"] + (t["type1"] - t["type0"]) * (i / n) ** 0.9, pre[i], "hold") for i in range(1, n + 1)])
A.key(ph_id, "opacity", [(0, 1, "hold"), (t["type0"], 0, "hold")])
A.key(CARD_SEND_BLUE, "opacity", [(0, 0, "hold"), (t["type0"] + 0.1, 1, "hold")])
A.key(card_arrow_id, "opacity", [(0, 0, "hold"), (t["type0"] + 0.1, 1, "hold")])

# the "changed" app, crossfaded in as the overlay dismisses
d0, d1 = t["dismiss"], t["dismiss"] + 0.5
A.fade(tall_blue_id, d0, d1)
A.fade(btn_blue_id, d0, d1)
A.key(title_a_id, "opacity", [(0, 1, "hold"), (d0, 1, "soft"), (d1, 0, "hold"), (t["reset"], 0, "soft"), (t["reset"] + 0.5, 1, "hold")])
A.key(title_b_id, "opacity", [(0, 0, "hold"), (d0, 0, "soft"), (d1, 1, "hold"), (t["reset"], 1, "soft"), (t["reset"] + 0.5, 0, "hold")])
A.key(act_id, "y", [(0, 222, "hold"), (d0, 222, "out"), (d1, 229, "hold"), (t["reset"], 229, "soft"), (t["reset"] + 0.5, 222, "hold")])
A.key(list_id, "y", [(0, 432, "hold"), (d0, 432, "out"), (d1, 439, "hold"), (t["reset"], 439, "soft"), (t["reset"] + 0.5, 432, "hold")])
A.key(btn_gray_id, "y", [(0, 584, "hold"), (d0, 584, "out"), (d1, 591, "hold"), (t["reset"], 591, "soft"), (t["reset"] + 0.5, 584, "hold")])
A.key(btn_blue_id, "y", [(0, 584, "hold"), (d0, 584, "out"), (d1, 591, "hold"), (t["reset"], 591, "soft"), (t["reset"] + 0.5, 584, "hold")])
A.key(stat2_id, "opacity", [(0, 1, "hold"), (d0, 1, "soft"), (d1, 0, "hold"), (t["reset"], 0, "soft"), (t["reset"] + 0.5, 1, "hold")])
A.key(stat2_sub_id, "opacity", [(0, 1, "hold"), (d0, 1, "soft"), (d1, 0, "hold"), (t["reset"], 0, "soft"), (t["reset"] + 0.5, 1, "hold")])
# back to the start for the loop
r0, r1 = t["reset"], t["reset"] + 0.5
A.key(tall_blue_id, "opacity", [(d1, 1, "soft"), (r0, 1, "soft"), (r1, 0, "hold")])
A.key(btn_blue_id, "opacity", [(d1, 1, "soft"), (r0, 1, "soft"), (r1, 0, "hold")])

# ---- write the file ---------------------------------------------------------------------------------
def build():
    body = root
    xml = f'''<Rive version="1" kind="fragment">
    <Artboard width="{ART_W * 2}" height="{ART_H * 2}" name="Reel" id="0:2" defaultStateMachineId="0:7">
        {body}
        <StateMachine name="SM" id="0:7">
            <StateMachineLayer name="L" id="0:8">
                <AnyState x="0" y="0"/><ExitState x="400" y="0"/>
                <EntryState x="0" y="100"><StateTransition stateToId="0:21"/></EntryState>
                <AnimationState x="200" y="100" animationId="0:6" id="0:21"/>
            </StateMachineLayer>
        </StateMachine>
        {A.xml()}
    </Artboard>
    <FontAsset file="font.ttf" name="UI" id="{FONT_ID}"/>
</Rive>
'''
    return xml


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "scene.rml"
    open(out, "w").write(build())
    print("wrote", out, "ids", _id[0])
