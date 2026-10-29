extends Node
## Autoload "Data": loads and caches the JSON tables.
## Data.table("weapon") reads data/original/weapon.json; world tables use a
## subfolder name, e.g. Data.table("world/l16"). If data/cork/<same path> exists
## it is deep-merged over the original, so Cork content overrides names, text
## and the map without editing the extracted originals.

const ORIGINAL_DIR := "res://data/original/"
const CORK_DIR := "res://data/cork/"

var _cache: Dictionary = {}


func table(table_name: String) -> Dictionary:
	if _cache.has(table_name):
		return _cache[table_name]
	var merged: Dictionary = _read(ORIGINAL_DIR + table_name + ".json")
	var cork: Dictionary = _read(CORK_DIR + table_name + ".json")
	if not cork.is_empty():
		_merge(merged, cork)
	_cache[table_name] = merged
	return merged


## One record of a table, or {} if missing. Data.entry("enemy", "zombieSlow").
func entry(table_name: String, key: String) -> Dictionary:
	var rec: Variant = table(table_name).get(key, {})
	return rec if rec is Dictionary else {}


func has_table(table_name: String) -> bool:
	return not table(table_name).is_empty()


## Turns a text value from the tables into a string. Plain strings pass through;
## {"template": "Hi {PartnerName}", "placeholders": [...]} gets each {name}
## replaced from ctx. Unknown placeholders are left in place.
func text(value: Variant, ctx: Dictionary = {}) -> String:
	if value is String:
		return value
	if value is Dictionary and value.has("template"):
		var out: String = value["template"]
		for key in value.get("placeholders", []):
			if ctx.has(key):
				out = out.replace("{%s}" % key, str(ctx[key]))
		return out
	return ""


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("Data: %s is not a JSON object" % path)
	return {}


func _merge(base: Dictionary, over: Dictionary) -> void:
	for key in over:
		if base.get(key) is Dictionary and over[key] is Dictionary:
			_merge(base[key], over[key])
		else:
			base[key] = over[key]
