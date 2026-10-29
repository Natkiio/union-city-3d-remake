extends "res://tests/test_base.gd"
## Cork content checks: every data/cork file parses, merged tables keep the
## original structure, no original-city words survive in text, and template
## placeholders match their placeholder lists.

const CORK_DIR := "res://data/cork/"

# Words from the original game's setting that must not appear in merged text.
const BANNED := [
	"union city", "union park", "union island", "union security", "ucpd", "herc", "homeland",
	"brookvale", "trenton", "green plains", "northwood", "uptown", "newtown", "canal park",
	"waterside", "whistler", "pinedale", "riverside", "downtown", "glendale", "jonestown",
	"fort tran", "jefferson", "tanner", "houston st", "washington ave", "lincoln ave",
	"freeman", "stanton", "ballpark", "earl of burger", "red rum", "king-o-pawn", "harrison",
	"stan's", "plenty phone", "boothtique", "9th street", "smith st", "park blvd", "8th ave",
	"merchant st", "mens room", "u-conbank", "united arms", "tinyurl",
]

# Fields that hold display text. `name` on npc.json is an id and is exempt.
const TEXT_FIELDS := ["name", "desc", "shortDesc", "longDesc", "fullName", "title", "heading", "body",
	"content", "startLocName", "endLocName", "var2", "template"]

var _files: Array = []


func _collect(dir_path: String, prefix: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".json"):
			_files.append(prefix + f.trim_suffix(".json"))
	for sub in d.get_directories():
		_collect(dir_path + sub + "/", prefix + sub + "/")


func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _is_text_field(k: String) -> bool:
	return k in TEXT_FIELDS or k.begins_with("content") or k.begins_with("say") \
		or k.begins_with("confirm") or k.begins_with("decline") or k.begins_with("func")


## Recursively compares structure: same keys, same list sizes, same numbers and
## bools, same template placeholder lists. Strings may differ.
func _same_shape(a: Variant, b: Variant, path: String, ignore_extra: Array, out: Array) -> void:
	if a is Dictionary and b is Dictionary:
		var ka: Array = a.keys()
		var kb: Array = b.keys()
		for k in ka:
			if not b.has(k):
				out.append("%s: missing key %s" % [path, k])
		for k in kb:
			if not a.has(k) and not (k in ignore_extra):
				out.append("%s: extra key %s" % [path, k])
		for k in ka:
			if b.has(k):
				_same_shape(a[k], b[k], path + "/" + str(k), ignore_extra, out)
	elif a is Array and b is Array:
		if a.size() != b.size():
			out.append("%s: list size %d vs %d" % [path, a.size(), b.size()])
		else:
			for i in a.size():
				_same_shape(a[i], b[i], path + "[%d]" % i, ignore_extra, out)
	elif a is String and b is String:
		pass
	elif typeof(a) != typeof(b) or a != b:
		out.append("%s: %s vs %s" % [path, str(a), str(b)])


func _scan_text(v: Variant, key: String, path: String, file: String, out: Array) -> void:
	if v is Dictionary:
		for k in v:
			_scan_text(v[k], str(k), path + "/" + str(k), file, out)
	elif v is Array:
		for i in v.size():
			_scan_text(v[i], key, path, file, out)
	elif v is String:
		if file == "npc" and key == "name":
			return
		if not _is_text_field(key):
			return
		var low: String = v.to_lower()
		for w in BANNED:
			if low.contains(w):
				out.append("%s: '%s' in %s" % [path, w, v.substr(0, 60)])


func _check_templates(v: Variant, path: String, out: Array) -> void:
	if v is Dictionary:
		if v.has("template"):
			var rx := RegEx.new()
			rx.compile("\\{(\\w+)\\}")
			var used := {}
			for m in rx.search_all(str(v["template"])):
				used[m.get_string(1)] = true
			var declared := {}
			for p in v.get("placeholders", []):
				declared[p] = true
			for u in used:
				if not declared.has(u):
					out.append("%s: {%s} not in placeholders" % [path, u])
			for d in declared:
				if not used.has(d):
					out.append("%s: placeholder %s unused" % [path, d])
		else:
			for k in v:
				_check_templates(v[k], path + "/" + str(k), out)
	elif v is Array:
		for i in v.size():
			_check_templates(v[i], path + "[%d]" % i, out)


func run() -> void:
	var data := autoload("Data")
	_collect(CORK_DIR, "")
	check("cork files present", _files.size() >= 30, "n=%d" % _files.size())
	var required := ["sections", "quest", "npc", "notes", "trig", "dialogs", "world/l1", "world/l16"]
	for r in required:
		check("cork has %s" % r, _files.has(r))
	for i in range(1, 17):
		check("cork has world/l%d" % i, _files.has("world/l%d" % i))

	for f in _files:
		var over: Variant = _parse(CORK_DIR + f + ".json")
		check("%s parses as object" % f, over is Dictionary)
		if not (over is Dictionary):
			continue
		var orig: Variant = _parse("res://data/original/" + f + ".json")
		check("%s has an original" % f, orig is Dictionary)
		if not (orig is Dictionary):
			continue
		var merged: Dictionary = data.table(f)
		var issues: Array = []
		_same_shape(orig, merged, f, ["desc"] if f == "sections" else [], issues)
		check("%s keeps original structure" % f, issues.is_empty(), "; ".join(issues.slice(0, 3)))
		issues = []
		_scan_text(merged, "", f, f.get_file() if not f.contains("/") else f, issues)
		check("%s has no original-city words" % f, issues.is_empty(), "; ".join(issues.slice(0, 3)))
		issues = []
		_check_templates(over, f, issues)
		check("%s templates match placeholders" % f, issues.is_empty(), "; ".join(issues.slice(0, 3)))

	# Quests: ids, rewards and requirements unchanged.
	var quests: Dictionary = data.table("quest")
	var oq: Dictionary = _parse("res://data/original/quest.json")
	check("quest ids unchanged", quests.keys() == oq.keys())
	var bad: Array = []
	for id in oq:
		for field in ["XPreward", "rewards", "itemReq", "itemCount", "unlocks", "talkReq", "type", "owner", "loc", "ref"]:
			if oq[id].has(field) and quests[id].get(field) != oq[id][field]:
				bad.append("%s.%s" % [id, field])
	check("quest rewards and requirements unchanged", bad.is_empty(), ", ".join(bad.slice(0, 5)))
	check("main story spine present", ["quest900", "quest915", "quest919"].all(func(q): return quests.has(q)))
	check("quest 900 retitled", data.text(quests["quest900"]["desc"]) == "Breaking Through")
	check("section 5 is Páirc Uí Chaoimh", data.entry("sections", "5")["name"] == "Páirc Uí Chaoimh")
	var names := {}
	for k in data.table("sections"):
		names[data.table("sections")[k]["name"]] = true
	check("section names are unique", names.size() == 16)

	# Danger levels kept.
	var danger := {16: 1, 9: 4, 13: 7, 12: 9, 5: 10, 15: 10, 11: 11, 6: 16, 14: 20, 7: 25}
	var dok := true
	for s in danger:
		var w: Dictionary = data.table("world/l%d" % s)
		if int(w.get("danger", -1)) != danger[s]:
			dok = false
	check("danger levels per section unchanged", dok)
