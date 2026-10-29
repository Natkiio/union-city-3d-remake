#!/usr/bin/env python3
"""Extract room layouts and map positions from the original SWF.

The location tables (data/original/world/l*.json) list what is in each room
but not where: room widths, door, stair and container positions live in the
room movieclips of the SWF. This tool reads an FFDec XML dump of the SWF and
writes, per section, the named markers of every room symbol
(`l<sec>_s<st>_b<b>_f<f>_r<r>`), plus the world map's section positions.

Output (committed, regenerate rather than hand-edit):
  data/original/world/layout/l<N>.json   {room_id: {width, left, floor_y, markers: [...]}}
  data/original/world/map.json           {"<N>": {"x": px, "y": px}}

Only numbers and marker names are written: no art, shapes or code.

Usage:
  java -jar ffdec-cli.jar -swf2xml reference/union_city.swf /tmp/uc.xml
  python3 -I tools/extract_layout.py /tmp/uc.xml data/original/world
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOM_RE = re.compile(r"^l(\d+)_s\d+_b\d+_f\d+_r\d+$")
# Marker prefixes the original's setupRoom() reacts to (first four letters of
# the instance name), plus the two geometry markers.
PREFIXES = {
    "door", "entr", "exit", "sup", "sdwn", "drop", "strt", "area", "room", "uprm",
    "dnrm", "ltrm", "rtrm", "cont", "abed", "body", "note", "bloc", "noSp", "trig",
    "shop", "lstr", "lstf", "lhom", "lhmf", "lsml", "lsmg", "lflu", "lflf",
}
TWIPS = 20.0


def matrix_of(el):
    m = el.find("matrix")
    if m is None:
        return (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
    g = lambda k, d: float(m.get(k, d))
    sx = g("scaleX", 1.0) if m.get("hasScale") == "true" else 1.0
    sy = g("scaleY", 1.0) if m.get("hasScale") == "true" else 1.0
    r0 = g("rotateSkew0", 0.0) if m.get("hasRotate") == "true" else 0.0
    r1 = g("rotateSkew1", 0.0) if m.get("hasRotate") == "true" else 0.0
    return (sx, r0, r1, sy, g("translateX", 0.0), g("translateY", 0.0))


def apply(mat, rect):
    sx, r0, r1, sy, tx, ty = mat
    x0, y0, x1, y1 = rect
    pts = [(x, y) for x in (x0, x1) for y in (y0, y1)]
    xs = [x * sx + y * r1 + tx for x, y in pts]
    ys = [x * r0 + y * sy + ty for x, y in pts]
    return (min(xs), min(ys), max(xs), max(ys))


def union(a, b):
    if a is None:
        return b
    if b is None:
        return a
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def rect_of(el):
    return (float(el.get("Xmin")), float(el.get("Ymin")), float(el.get("Xmax")), float(el.get("Ymax")))


def load(xml_path):
    """Returns (rects, sprites, exports): leaf bounds by id, sprite frame-1
    placements by id, exported name -> id."""
    rects, sprites, exports = {}, {}, {}
    depth = 0
    for event, el in ET.iterparse(xml_path, events=("start", "end")):
        if event == "start":
            depth += 1
            continue
        depth -= 1
        if depth != 2 or el.tag != "item":
            continue
        t = el.get("type", "")
        if t.startswith("DefineShape"):
            rects[el.get("shapeId")] = rect_of(el.find("shapeBounds"))
        elif t.startswith("DefineMorphShape"):
            rects[el.get("characterId")] = rect_of(el.find("startBounds"))
        elif t == "DefineTextTag" or t == "DefineText2Tag":
            rects[el.get("characterID")] = rect_of(el.find("textBounds"))
        elif t == "DefineEditTextTag":
            b = el.find("bounds")
            if b is not None:
                rects[el.get("characterID")] = rect_of(b)
        elif t == "DefineSpriteTag":
            places = []
            for sub in el.find("subTags"):
                st = sub.get("type", "")
                if st == "ShowFrameTag":
                    break
                if st.startswith("PlaceObject") and sub.get("characterId"):
                    places.append((sub.get("characterId"), sub.get("name"), matrix_of(sub)))
            sprites[el.get("spriteId")] = places
        elif t == "ExportAssetsTag":
            for cid, name in zip(el.find("tags"), el.find("names")):
                exports[name.text] = cid.text
        el.clear()
    return rects, sprites, exports


def make_bounds(rects, sprites):
    cache = {}

    def bounds(cid, stack=()):
        if cid in cache:
            return cache[cid]
        if cid in rects:
            return rects[cid]
        if cid not in sprites or cid in stack:
            return None
        r = None
        for child, _name, mat in sprites[cid]:
            b = bounds(child, stack + (cid,))
            if b is not None:
                r = union(r, apply(mat, b))
        cache[cid] = r
        return r

    return bounds


def rnd(v):
    return round(v / TWIPS, 1)


def room_layout(sid, rects, sprites, bounds):
    out = {"markers": []}
    for child, name, mat in sprites.get(sid, []):
        if not name:
            continue
        b = bounds(child)
        box = apply(mat, b) if b is not None else (mat[4], mat[5], mat[4], mat[5])
        if name == "bounds":
            out["left"] = rnd(box[0])
            out["width"] = rnd(box[2] - box[0])
            out["top"] = rnd(box[1])
            out["height"] = rnd(box[3] - box[1])
            continue
        if name == "floorMarker":
            out["floor_y"] = rnd(mat[5])
            continue
        if name[:4] not in PREFIXES and name[:3] not in ("sup",):
            continue
        out["markers"].append({
            "name": name,
            "x": rnd(mat[4]), "y": rnd(mat[5]),
            "left": rnd(box[0]), "right": rnd(box[2]),
            "top": rnd(box[1]), "bottom": rnd(box[3]),
            "flip": mat[0] < 0,
        })
    out["markers"].sort(key=lambda m: (m["x"], m["name"]))
    return out


def main(xml_path, out_dir):
    rects, sprites, exports = load(xml_path)
    bounds = make_bounds(rects, sprites)
    per_section = {}
    for name, cid in exports.items():
        m = ROOM_RE.match(name)
        if m:
            per_section.setdefault(m.group(1), {})[name] = room_layout(cid, rects, sprites, bounds)
    os.makedirs(os.path.join(out_dir, "layout"), exist_ok=True)
    for sec, rooms in sorted(per_section.items(), key=lambda kv: int(kv[0])):
        path = os.path.join(out_dir, "layout", "l%s.json" % sec)
        with open(path, "w") as f:
            json.dump(dict(sorted(rooms.items())), f, indent=1, sort_keys=True)
            f.write("\n")
        print("%s: %d rooms" % (path, len(rooms)))

    world_map = {}
    for child, name, mat in sprites.get(exports.get("worldMap"), []):
        if name and re.fullmatch(r"section\d+", name):
            world_map[name[7:]] = {"x": rnd(mat[4]), "y": rnd(mat[5])}
    path = os.path.join(out_dir, "map.json")
    with open(path, "w") as f:
        json.dump(dict(sorted(world_map.items(), key=lambda kv: int(kv[0]))), f, indent=1)
        f.write("\n")
    print("%s: %d sections" % (path, len(world_map)))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
