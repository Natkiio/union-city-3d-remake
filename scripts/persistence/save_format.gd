class_name SaveFormat
extends RefCounted
## Pure helpers for the save file: parse, validate, migrate, normalise.
## No autoload access, so tests can feed it arbitrary text.

const VERSION := 1
const GAME := "cork"

## Old version -> Callable(data: Dictionary) -> Dictionary that returns data at
## version + 1. Add an entry whenever VERSION is bumped. The version-0 entry
## is the worked example: v0 stored the player name at top level as `player`
## and had no `header`.
static var MIGRATIONS: Dictionary = {
	0: _migrate_0_to_1,
}


static func _migrate_0_to_1(data: Dictionary) -> Dictionary:
	var header: Dictionary = data.get("header", {}) if data.get("header") is Dictionary else {}
	if data.has("player"):
		header["name"] = str(data["player"])
		data.erase("player")
	data["header"] = header
	data["version"] = 1
	return data


## Returns {"ok": bool, "error": String, "data": Dictionary}. data is fully
## validated, migrated and number-normalised when ok.
static func parse(text: String, migrations: Dictionary = MIGRATIONS, current_version: int = VERSION) -> Dictionary:
	if text.strip_edges().is_empty():
		return _fail("empty file")
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("invalid JSON: %s" % json.get_error_message())
	if not (json.data is Dictionary):
		return _fail("root is not an object")
	var data: Dictionary = json.data
	if data.get("game", GAME) != GAME:
		return _fail("not a cork save")
	if not data.has("version") or not (data["version"] is float or data["version"] is int):
		return _fail("missing version")
	var v := int(data["version"])
	if v > current_version:
		return _fail("save is from a newer version (%d > %d)" % [v, current_version])
	if v < 0:
		return _fail("bad version")
	while v < current_version:
		if not migrations.has(v):
			return _fail("no migration from version %d" % v)
		var migrated: Variant = migrations[v].call(data)
		if not (migrated is Dictionary) or int(migrated.get("version", -1)) != v + 1:
			return _fail("migration from version %d failed" % v)
		data = migrated
		v += 1
	if not (data.get("systems") is Dictionary):
		return _fail("missing systems")
	for key in data["systems"]:
		if not (data["systems"][key] is Dictionary):
			return _fail("system %s is not an object" % key)
	if data.has("providers") and not (data["providers"] is Dictionary):
		return _fail("providers is not an object")
	if data.has("providers"):
		for key in data["providers"]:
			if not (data["providers"][key] is Dictionary):
				return _fail("provider %s is not an object" % key)
	if data.has("header") and not (data["header"] is Dictionary):
		return _fail("header is not an object")
	data["game"] = GAME
	return {"ok": true, "error": "", "data": normalize(data)}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "data": {}}


## JSON has one number type, so Godot reads every number back as a float.
## Whole floats become ints again so counts, levels and minutes keep their
## type. (A weight of 1.0 comes back as 1; typed float vars accept that.)
static func normalize(v: Variant) -> Variant:
	if v is float:
		if is_finite(v) and v == floorf(v) and absf(v) < 9.0e15:
			return int(v)
		return v
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = normalize(v[k])
		return out
	if v is Array:
		var out_a := []
		for e in v:
			out_a.append(normalize(e))
		return out_a
	return v


## Deep equality that treats 3 and 3.0 as equal and floats within `eps`.
static func deep_equal(a: Variant, b: Variant, eps: float = 0.0005) -> bool:
	var a_num: bool = a is int or a is float
	var b_num: bool = b is int or b is float
	if a_num and b_num:
		return absf(float(a) - float(b)) <= eps
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not deep_equal(a[k], b[k], eps):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not deep_equal(a[i], b[i], eps):
				return false
		return true
	return a == b
