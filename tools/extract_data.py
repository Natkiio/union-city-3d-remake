#!/usr/bin/env python3
"""Extract the original game's data tables from FFDec-decompiled ActionScript 2.

Usage: python3 -I tools/extract_data.py <DoAction.as> <out_dir>

Reads top-level statements of the form
    table.key = new Object();
    table.key.prop = <literal>;
and writes one JSON file per table. Anything that is not a plain literal
(string, number, true/false/null) is kept as {"$expr": "<source text>"} so
nothing is silently lost. Tables named skill_<x> are merged into "skills".

A final resolve pass replaces $expr nodes that can be evaluated: bare constants,
table references, and string concatenations of those. Player-dependent text
becomes {"template": ..., "placeholders": [...]}. Anything else stays $expr.
"""
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

SKIP_TABLES = {"ach", "Button"}  # achievement/UI plumbing, not gameplay
MISSING = object()  # "could not resolve" (None is a real JSON value)

# Per-location / cutscene / lighting tables go in a "world" subfolder.
WORLD_TABLE = re.compile(r"^(l\d+|lightTime\d+|cutScene\d+|shopSet\d+|fakeRoom)$")

# Functions that fill data tables with indented `table.a.b = value;` lines
# (quests, triggers, NPC dialogue). Their assignments are read like top-level ones.
TABLE_FUNCTIONS = re.compile(r"^(setQuestContents|defineTriggers|setNPCLoc\d+)$")
FUNC_DEF = re.compile(r"^function\s+(\w+)\s*\(")
ARRAY = re.compile(r"^(?:new Array\((.*)\)|\[(.*)\])$")

ASSIGN = re.compile(r"^([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+)\s*=\s*(.+?);\s*$")
SCALAR = re.compile(r"^(?:var\s+)?([A-Za-z_]\w*)\s*=\s*(.+?);\s*$")
NUMBER = re.compile(r"^-?\d+(?:\.\d+)?$")


def parse_value(raw):
    raw = raw.strip()
    if raw == "new Object()":
        return OrderedDict()
    if raw in ("new Array()", "[]"):
        return []
    am = ARRAY.match(raw)
    if am:
        items = [parse_value(x) for x in re.findall(r'"(?:[^"\\]|\\.)*"|[^,\s][^,]*', am.group(1) or am.group(2) or "")]
        return items
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


TOKEN = re.compile(r"""
    (?P<str>"(?:[^"\\]|\\.)*")
  | (?P<root>_root\[player\.sex\s*\+\s*"\w+"\])
  | (?P<path>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)
  | (?P<num>-?\d+)
  | (?P<plus>\+)
  | (?P<ws>\s+)
""", re.VERBOSE)
ROOT_FIELD = re.compile(r'_root\[player\.sex\s*\+\s*"(\w+)"\]')
AS2_ESCAPES = {"r": "\n", "n": "\n", "t": "\t"}  # AS2 \r is the line break the data uses


def unescape(body):
    return re.sub(r"\\(.)", lambda m: AS2_ESCAPES.get(m.group(1), m.group(1)), body)


def tokenize(raw):
    """Split `a + b + c` into (kind, text) operands; None if anything else appears."""
    operands, want_operand, pos = [], True, 0
    while pos < len(raw):
        m = TOKEN.match(raw, pos)
        if not m:
            return None
        pos, kind = m.end(), m.lastgroup
        if kind == "ws":
            continue
        if kind == "plus":
            if want_operand:
                return None
            want_operand = True
            continue
        if not want_operand:
            return None
        want_operand = False
        operands.append((kind, m.group(kind)))
    return None if want_operand else operands


def is_expr(node):
    return isinstance(node, dict) and set(node) == {"$expr"}


class Resolver:
    def __init__(self, tables, constants, source_text):
        self.tables = tables
        self.constants = constants
        # Fallback for names assigned inside functions: last `name = literal;` wins.
        self.source_scalars = OrderedDict()
        for line in source_text.splitlines():
            sm = SCALAR.match(line.strip())
            if sm:
                val = parse_value(sm.group(2))
                if isinstance(val, (int, float, bool, str)):
                    self.source_scalars[sm.group(1)] = val
        self.memo = {}
        self.active = set()

    def node_at(self, parts):
        node = self.tables
        for part in parts:
            if isinstance(node, dict) and part in node:
                node = node[part]
            elif isinstance(node, list) and part.isdigit() and int(part) < len(node):
                node = node[int(part)]
            else:
                return MISSING
        return node

    def value_of(self, ref):
        parts = ref.split(".")
        if len(parts) == 1:
            if ref in self.constants:
                return self.constants[ref]
            return self.source_scalars.get(ref, MISSING)
        return self.resolve_at(parts)

    def resolve_at(self, parts):
        """Resolved value of the node at `parts`, evaluating $expr nodes on demand."""
        key = tuple(parts)
        node = self.node_at(parts)
        if not is_expr(node):
            return node
        if key in self.memo:
            return self.memo[key]
        if key in self.active:  # reference cycle
            return MISSING
        self.active.add(key)
        value = self.evaluate(node["$expr"])
        self.active.discard(key)
        self.memo[key] = value
        return value

    def evaluate(self, raw):
        operands = tokenize(raw.strip())
        if not operands:
            return MISSING
        if len(operands) == 1 and operands[0][0] == "path":
            # Rule 1/2: a bare reference takes the referenced value as-is.
            ref = operands[0][1]
            if ref.startswith("player."):
                return MISSING  # a value, not text; leave it for the consumer
            return self.value_of(ref)
        if operands[0][0] in ("num", "plus"):
            return MISSING
        parts = []  # ("lit", text) or ("ph", name)
        for i, (kind, text) in enumerate(operands):
            if kind == "str":
                parts.append(("lit", unescape(text[1:-1])))
            elif kind == "root":
                parts.append(("ph", ROOT_FIELD.match(text).group(1)))
            elif kind == "num":
                parts.append(("lit", text))
            else:  # path
                head, _, field = text.partition(".")
                if head == "player" and field and "." not in field:
                    parts.append(("ph", "player" + field[0].upper() + field[1:]))
                    continue
                value = self.value_of(text)
                if value is MISSING or isinstance(value, (dict, list, bool)):
                    return MISSING
                parts.append(("lit", str(value)))
        template, placeholders = "", []
        for kind, value in parts:
            if kind == "lit":
                if "{" in value or "}" in value:
                    return MISSING  # would collide with placeholder syntax
                template += value
            else:
                template += "{" + value + "}"
                if value not in placeholders:
                    placeholders.append(value)
        if not placeholders:
            return template
        return OrderedDict([("template", template), ("placeholders", placeholders)])

    def substitute(self):
        def visit(node, parts):
            children = node.items() if isinstance(node, dict) else enumerate(node)
            for key, child in list(children):
                child_parts = parts + (str(key),)
                if is_expr(child):
                    value = self.resolve_at(child_parts)
                    if value is not MISSING:
                        node[key] = value
                elif isinstance(child, (dict, list)):
                    visit(child, child_parts)
        visit(self.tables, ())


def main():
    src, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    tables = OrderedDict()
    constants = OrderedDict()   # name -> last literal value assigned at top level
    assigned = OrderedDict()    # name -> every literal value, to flag reassignments
    current_fn = None
    source_text = src.read_text(encoding="utf-8", errors="replace")
    for line in source_text.splitlines():
        fm = FUNC_DEF.match(line)
        if fm:
            current_fn = fm.group(1)
        elif line.startswith("}"):
            current_fn = None
        if line[:1] in (" ", "\t", "}"):
            # Indented lines only count inside the table-filling functions.
            if current_fn and TABLE_FUNCTIONS.match(current_fn):
                line = line.strip()
                m = ASSIGN.match(line)
                if m:
                    set_path(tables, m.group(1).split("."), parse_value(m.group(2)))
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

    Resolver(tables, constants, source_text).substitute()
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
