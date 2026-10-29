class_name Items
extends RefCounted
## One lookup over every item table: weapon, clothing, food, meds, books,
## junk, questItem. Items.find("Bandages") or Items.find("bandage") both give
##   {kind, ref, key, name, weight, rec}
## where `rec` is the raw table row. Ammo ("9mm Ammo") is not a table item;
## Items.kind() reports "ammo" for it but find() returns {}.

## Lookup order when a name or ref exists in more than one table.
const KINDS := ["weapon", "clothing", "food", "meds", "books", "junk", "questItem"]

static var _by_name: Dictionary = {}
static var _by_ref: Dictionary = {}
static var _rows: Array = []


static func find(name_or_ref: String) -> Dictionary:
	_build()
	if _by_name.has(name_or_ref):
		return _by_name[name_or_ref]
	return _by_ref.get(name_or_ref, {})


static func exists(name_or_ref: String) -> bool:
	return not find(name_or_ref).is_empty()


## Table kind of an item, "ammo" for "<type> Ammo", "" when unknown.
static func kind(name_or_ref: String) -> String:
	var info := find(name_or_ref)
	if not info.is_empty():
		return info["kind"]
	if name_or_ref.ends_with(" Ammo"):
		return "ammo"
	return ""


## Weight in lbs, or `fallback` when the item is unknown.
static func weight(name_or_ref: String, fallback: float = 1.0) -> float:
	var info := find(name_or_ref)
	return info["weight"] if not info.is_empty() else fallback


## Every item of one kind (rows as returned by find), table order.
static func all(kind_filter: String = "") -> Array:
	_build()
	var out: Array = []
	for info in _rows:
		if kind_filter == "" or info["kind"] == kind_filter:
			out.append(info)
	return out


## One row by table and key, e.g. Items.in_table("books", "specialWeapons").
static func in_table(kind_name: String, key: String) -> Dictionary:
	_build()
	for info in _rows:
		if info["kind"] == kind_name and info["key"] == key:
			return info
	return {}


## Drops the cache (after Data tables change).
static func clear_cache() -> void:
	_rows.clear()
	_by_name.clear()
	_by_ref.clear()


static func _build() -> void:
	if not _rows.is_empty():
		return
	var data: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Data")
	for k in KINDS:
		var table: Dictionary = data.table(k)
		for key in table:
			var rec: Dictionary = table[key]
			var info := {
				"kind": k,
				"key": key,
				"ref": rec.get("ref", key),
				"name": rec.get("name", key),
				"weight": float(rec.get("weight", 0.0)),
				"rec": rec,
			}
			_rows.append(info)
			# First table in KINDS order wins a shared name, key or ref.
			if not _by_name.has(info["name"]):
				_by_name[info["name"]] = info
			for id in [info["key"], info["ref"]]:
				if not _by_ref.has(id):
					_by_ref[id] = info
