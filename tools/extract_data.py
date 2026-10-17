#!/usr/bin/env python3
"""Extract the original game's data tables from FFDec-decompiled ActionScript 2.

Usage: python3 -I tools/extract_data.py <DoAction.as> <out_dir>

Reads top-level statements of the form
    table.key = new Object();
    table.key.prop = <literal>;
and writes one JSON file per table. Anything that is not a plain literal
(string, number, true/false/null) is kept as {"$expr": "<source text>"} so
nothing is silently lost. Tables named skill_<x> are merged into "skills".
"""
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

SKIP_TABLES = {"ach", "Button"}  # achievement/UI plumbing, not gameplay

# Per-location / cutscene / lighting tables go in a "world" subfolder.
WORLD_TABLE = re.compile(r"^(l\d+|lightTime\d+|cutScene\d+|shopSet\d+|fakeRoom)$")

ASSIGN = re.compile(r"^([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+)\s*=\s*(.+?);\s*$")
SCALAR = re.compile(r"^(?:var\s+)?([A-Za-z_]\w*)\s*=\s*(.+?);\s*$")
NUMBER = re.compile(r"^-?\d+(?:\.\d+)?$")


def parse_value(raw):
    raw = raw.strip()
    if raw == "new Object()":
        return OrderedDict()
    if raw == "new Array()":
        return []
    if raw in ("true", "false"):
        return raw == "true"
    if raw == "null":
        return None
    if NUMBER.match(raw):
        return float(raw) if "." in raw else int(raw)
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"' and '" + ' not in raw:
        try:
            return json.loads(raw)
        except ValueError:
            return raw[1:-1]
    return {"$expr": raw}


def set_path(root, path, value):
    node = root
    for part in path[:-1]:
        child = node.get(part)
        if not isinstance(child, dict):
            child = node[part] = OrderedDict()
        node = child
    # `x = new Object()` must not wipe properties already assigned.
    if isinstance(value, OrderedDict) and isinstance(node.get(path[-1]), dict):
        return
    node[path[-1]] = value


def main():
    src, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    tables = OrderedDict()
    constants = OrderedDict()   # name -> last literal value assigned at top level
    assigned = OrderedDict()    # name -> every literal value, to flag reassignments
    for line in src.read_text(encoding="utf-8", errors="replace").splitlines():
        if line[:1] in (" ", "\t", "}"):  # only top-level statements
            continue
        sm = SCALAR.match(line)
        if sm:
            val = parse_value(sm.group(2))
            if isinstance(val, (int, float, bool, str)) and not isinstance(val, dict):
                constants[sm.group(1)] = val
                assigned.setdefault(sm.group(1), []).append(val)
            continue
        m = ASSIGN.match(line)
        if not m:
            continue
        path = m.group(1).split(".")
        head = path[0]
        if head in SKIP_TABLES:
            continue
        if head.startswith("skill_"):
            path = ["skills", head[len("skill_"):]] + path[1:]
        set_path(tables, path, parse_value(m.group(2)))

    out_dir.mkdir(parents=True, exist_ok=True)
    dupes = {k: v for k, v in assigned.items() if len(set(map(repr, v))) > 1}
    out = {"constants": constants, "reassigned": dupes}
    (out_dir / "constants.json").write_text(
        json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"constants      {len(constants):4d} scalars, {len(dupes)} reassigned -> {out_dir / 'constants.json'}")
    for name, data in tables.items():
        # Skip one-off globals like `foo.bar = 3` that aren't real tables.
        if len(data) < 2 and not any(isinstance(v, dict) for v in data.values()):
            continue
        sub = out_dir / "world" if WORLD_TABLE.match(name) else out_dir
        sub.mkdir(parents=True, exist_ok=True)
        path = sub / f"{name}.json"
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"{name:14s} {len(data):4d} entries -> {path}")


if __name__ == "__main__":
    main()
