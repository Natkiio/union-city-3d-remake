extends Node
## Autoload "Quests": quest state, NPC state numbers, triggers, rewards, unlocks.
## Spec: docs/ORIGINAL_ANALYSIS.md section 11, docs/story.md. Data comes from
## the quest / npc / trig tables (Data.table merges the Cork overrides).
##
## Quest ids are the strings in the `ref` field ("900", "001", "500"); the
## table keys are "quest" + id. A quest is "locked" (nobody offers it yet),
## "available" (an NPC's current state offers it), "active" or "complete".
## Presentation never edits state directly: it calls start / complete /
## fire_trigger / advance_npc, and listens to Events.quest_changed and the
## signals below.
## Stateful system: group "stateful", reset(), to_dict(), from_dict(d).

## Generic hook for effects the world or ui must carry out: "startCutScene",
## "speech", "showHelp", "unlockDoor", "startEndingRush", "showEnding", "cash",
## "companion", "alert", "spawn" (Jeb and Paul ambush), "fixJack",
## "animateCharacter", "setupAnNPCDirect". `args` are plain values, text
## already filled. NPC on/off/removal goes through npc_changed instead.
signal story_action(action: String, args: Array)
## An NPC was switched on/off/removed or changed state (npc.gd refreshes).
signal npc_changed(npc_id: String)
signal section_unlocked(section_id: String)

const DONE := "complete"

## When true, a "startCutScene" action spawns a CutscenePlayer under the root.
var auto_play_cutscenes: bool = true

var _status: Dictionary = {}        # quest id -> "active" | "complete"
var _counts: Dictionary = {}        # quest id -> kills so far
var _started: Dictionary = {}       # quest id -> true after the first start
var _npc_state: Dictionary = {}     # npc name -> int
var _npc_off: Dictionary = {}       # npc name -> bool (overrides npc.json `off`)
var _npc_removed: Dictionary = {}   # npc name -> true
var _trig_done: Dictionary = {}     # trigger id -> bool (overrides trig.json)
var _sections: Dictionary = {}      # section id ("16") -> true
var _doors: Dictionary = {}         # unlocked door id -> true
var _end_locs: Dictionary = {}      # end location number -> true
var _companions: Dictionary = {}    # npc name -> "follower" | "partner"
var tracked: String = ""
var cash: int = 0
var ending_rush: bool = false
var ending_shown: bool = false


func _ready() -> void:
	add_to_group("stateful")
	Events.enemy_killed.connect(_on_enemy_killed)
	reset()


# --- stateful ----------------------------------------------------------------

func reset() -> void:
	_status.clear()
	_counts.clear()
	_started.clear()
	_npc_state.clear()
	_npc_off.clear()
	_npc_removed.clear()
	_trig_done.clear()
	_doors.clear()
	_end_locs.clear()
	_companions.clear()
	_sections.clear()
	tracked = ""
	cash = 0
	ending_rush = false
	ending_shown = false
	var secs := Data.table("sections")
	for id in secs:
		if secs[id] is Dictionary and secs[id].get("locked", true) == false:
			_sections[str(id)] = true


func to_dict() -> Dictionary:
	return {
		"status": _status.duplicate(), "counts": _counts.duplicate(),
		"started": _started.duplicate(), "npc_state": _npc_state.duplicate(),
		"npc_off": _npc_off.duplicate(), "npc_removed": _npc_removed.duplicate(),
		"trig_done": _trig_done.duplicate(), "sections": _sections.duplicate(),
		"doors": _doors.duplicate(), "end_locs": _end_locs.duplicate(),
		"companions": _companions.duplicate(), "tracked": tracked, "cash": cash,
		"ending_rush": ending_rush, "ending_shown": ending_shown,
	}


func from_dict(d: Dictionary) -> void:
	reset()
	_status = _strs(d.get("status", {}))
	_counts = _ints(d.get("counts", {}))
	_started = d.get("started", {}).duplicate()
	_npc_state = _ints(d.get("npc_state", {}))
	_npc_off = d.get("npc_off", {}).duplicate()
	_npc_removed = d.get("npc_removed", {}).duplicate()
	_trig_done = d.get("trig_done", {}).duplicate()
	if d.has("sections"):
		_sections = d["sections"].duplicate()
	_doors = d.get("doors", {}).duplicate()
	_end_locs = d.get("end_locs", {}).duplicate()
	_companions = _strs(d.get("companions", {}))
	tracked = str(d.get("tracked", ""))
	cash = int(d.get("cash", 0))
	ending_rush = bool(d.get("ending_rush", false))
	ending_shown = bool(d.get("ending_shown", false))


func _ints(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[str(k)] = int(src[k])
	return out


func _strs(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[str(k)] = str(src[k])
	return out


# --- quest lookup -------------------------------------------------------------

## Every real quest id in table order (empty placeholder records are skipped).
func quest_ids() -> Array[String]:
	var out: Array[String] = []
	var t := Data.table("quest")
	for key in t:
		if t[key] is Dictionary and not (t[key] as Dictionary).is_empty():
			out.append(str(t[key].get("ref", str(key).trim_prefix("quest"))))
	return out


func quest_def(id: String) -> Dictionary:
	return Data.entry("quest", "quest" + id)


func has_quest(id: String) -> bool:
	return not quest_def(id).is_empty()


func status(id: String) -> String:
	var s: String = _status.get(id, "")
	if s != "":
		return s
	for npc_id in npc_ids():
		if npc_active(npc_id) and npc_quest(npc_id) == id:
			return "available"
	return "locked"


func is_active(id: String) -> bool:
	return _status.get(id, "") == "active"


func is_complete(id: String) -> bool:
	return _status.get(id, "") == DONE


func active_quests() -> Array[String]:
	var out: Array[String] = []
	for id in quest_ids():
		if is_active(id):
			out.append(id)
	return out


func completed_quests() -> Array[String]:
	var out: Array[String] = []
	for id in quest_ids():
		if is_complete(id):
			out.append(id)
	return out


func kill_count(id: String) -> int:
	return int(_counts.get(id, 0))


# --- starting and completing ------------------------------------------------------

## Accepts a quest (setActiveQuest). False if unknown, active or already done.
func start(id: String) -> bool:
	var q := quest_def(id)
	if q.is_empty() or _status.has(id):
		return false
	_status[id] = "active"
	if tracked == "":
		tracked = id
	_counts[id] = 0
	var first := not _started.has(id)
	_started[id] = true
	_change_states(q.get("changeStateStart", []), q.get("changeStateStartNum", []))
	if q.has("unlocksAreaStart"):
		unlock_section(str(q["unlocksAreaStart"]))
	for t in _as_array(q.get("triggerOnStart", [])):
		fire_trigger(str(t), true)
	if first:
		if q.has("startCutScene"):
			_emit_action("startCutScene", [int(q["startCutScene"])])
		for ref in q.get("startRewards", []):
			_give_item(str(ref))
	for door in _as_array(q.get("unlocksDoorStart", [])):
		unlock_door(str(door))
	Events.quest_changed.emit(id, "active")
	return true


## True when the quest's requirement is satisfied: items in the inventory
## (fetch), kills reached (kill). Talk and triggered quests need nothing.
func requirements_met(id: String) -> bool:
	var q := quest_def(id)
	match str(q.get("type", "")):
		"fetch":
			return _missing(q).is_empty()
		"kill":
			return kill_count(id) >= int(q.get("killCount", 1))
	return true


## Item shortfalls of a fetch quest: [{ref, name, need, have}] (empty if met).
func missing_items(id: String) -> Array:
	return _missing(quest_def(id))


func _missing(q: Dictionary) -> Array:
	var out: Array = []
	var refs: Array = q.get("itemReq", [])
	var counts: Array = q.get("itemCount", [])
	for i in refs.size():
		var need := int(counts[i]) if i < counts.size() else 1
		var item := item_name(str(refs[i]))
		var have := int(Inventory.items.get(item, {}).get("count", 0))
		if have < need:
			out.append({"ref": str(refs[i]), "name": item, "need": need, "have": have})
	return out


## Completes a quest (completeQuest): fetch takes the items, kill needs the
## count. Returns false if it was already done or the requirement is unmet.
func complete(id: String) -> bool:
	var q := quest_def(id)
	if q.is_empty() or is_complete(id):
		return false
	var kind := str(q.get("type", ""))
	if (kind == "fetch" or kind == "kill") and not requirements_met(id):
		return false
	if kind == "fetch":
		var refs: Array = q.get("itemReq", [])
		var counts: Array = q.get("itemCount", [])
		for i in refs.size():
			Inventory.remove_item(item_name(str(refs[i])), int(counts[i]) if i < counts.size() else 1)
	_status[id] = DONE
	if tracked == id:
		tracked = ""
	_give_rewards(q)
	for door in _as_array(q.get("unlocksDoor", [])):
		unlock_door(str(door))
	_change_states(q.get("changeStateComplete", []), q.get("changeStateCompleteNum", []))
	for t in _as_array(q.get("triggerOnComplete", [])):
		fire_trigger(str(t), true)
	Events.quest_changed.emit(id, DONE)
	return true


func _give_rewards(q: Dictionary) -> void:
	for ref in q.get("rewards", []):
		var r := str(ref)
		if r == "follower":
			add_companion(str(q.get("owner", "")), "follower")
		elif r == "partner":
			add_companion("Partner", "partner")
		else:
			_give_item(r)
	for sec in q.get("unlocks", []):
		unlock_section(str(sec))
	var xp := int(q.get("XPreward", 0))
	if xp > 0:
		Stats.add_xp(xp, "quest")


func _give_item(ref: String) -> void:
	if ref.begins_with("cash_"):
		var amount := int(ref.trim_prefix("cash_"))
		cash += amount
		_emit_action("cash", [amount])
		return
	Inventory.add_item(item_name(ref))


## Display name of an item ref (Items lookup); the ref itself if unknown.
## Weapon mod variants ("PPM9_suppressed") are not rows in the item tables yet:
## they resolve to the base weapon's name plus the mod, "PPM9 (suppressed)".
func item_name(ref: String) -> String:
	var info := Items.find(ref)
	if not info.is_empty():
		return str(info["name"])
	var cut := ref.rfind("_")
	if cut > 0:
		var base := Items.find(ref.substr(0, cut))
		if not base.is_empty():
			return "%s (%s)" % [base["name"], ref.substr(cut + 1)]
	return ref


## Talk quests: opening a dialogue with `npc_id` completes every active talk
## quest that names them in talkReq. Returns the ids completed.
func on_talk(npc_id: String) -> Array[String]:
	var done: Array[String] = []
	for id in active_quests():
		var q := quest_def(id)
		if q.get("type", "") == "talk" and str(q.get("talkReq", "")) == npc_id:
			if complete(id):
				done.append(id)
	return done


func _on_enemy_killed(enemy_ref: String, _danger: int, _xp: int) -> void:
	for id in active_quests():
		var q := quest_def(id)
		if q.get("type", "") != "kill" or not _kill_matches(q, enemy_ref):
			continue
		_counts[id] = mini(kill_count(id) + 1, int(q.get("killCount", 1)))
		Events.quest_changed.emit(id, "active")


func _kill_matches(q: Dictionary, enemy_ref: String) -> bool:
	var kind := str(q.get("killType", ""))
	if kind != "" and not enemy_ref.begins_with(kind):
		return false
	var cur: Variant = World.get("current")
	if not (cur is Dictionary) or (cur as Dictionary).is_empty():
		return true
	for pair in [["killLocation", "section"], ["killStreet", "street"], ["killBuilding", "building"], ["killFloor", "floor"], ["killRoom", "room"]]:
		if q.has(pair[0]) and (cur as Dictionary).has(pair[1]):
			if _num(q[pair[0]]) != _num(cur[pair[1]]):
				return false
	return true


func _num(v: Variant) -> int:
	var digits := ""
	for c in str(v):
		if c >= "0" and c <= "9":
			digits += c
	return int(digits) if digits != "" else -1


func _as_array(v: Variant) -> Array:
	if v is Array:
		return v
	if v == null or str(v) == "":
		return []
	return [v]


func _change_states(names: Variant, nums: Variant) -> void:
	var n: Array = _as_array(names)
	var m: Array = _as_array(nums)
	for i in n.size():
		set_npc_state(str(n[i]), int(m[i]) if i < m.size() else -1)


# --- NPC state -------------------------------------------------------------------

## NPC record: the npc table, or scripts/story/story_extras.gd for NPCs the
## tables lack (quest 500's Fred).
func npc_def(npc_id: String) -> Dictionary:
	var d := Data.entry("npc", npc_id)
	if d.is_empty() and StoryExtras.NPCS.has(npc_id):
		return StoryExtras.NPCS[npc_id]
	return d


func npc_ids() -> Array[String]:
	var out: Array[String] = []
	for k in Data.table("npc"):
		out.append(str(k))
	for k in StoryExtras.NPCS:
		if not out.has(k):
			out.append(str(k))
	return out


## Dialogue state number (npc.json `state`, 0 if the NPC has none).
func npc_state(npc_id: String) -> int:
	if _npc_state.has(npc_id):
		return int(_npc_state[npc_id])
	var raw: Variant = npc_def(npc_id).get("state", 0)
	return 1 if raw is String else int(raw) # "off" NPCs wake up in state 1


## Sets the state; a negative number advances by one when that content exists.
func set_npc_state(npc_id: String, n: int = -1) -> void:
	if npc_def(npc_id).is_empty():
		return
	if n < 0:
		var next := npc_state(npc_id) + 1
		if not npc_def(npc_id).has("content%d" % next):
			return
		n = next
	_npc_state[npc_id] = n
	npc_changed.emit(npc_id)


## Moves an NPC to its next dialogue state when one exists (after a quest turn-in).
func advance_npc(npc_id: String) -> void:
	set_npc_state(npc_id, -1)


## The quest id the NPC's current state hands out ("" if none).
func npc_quest(npc_id: String) -> String:
	return str(npc_def(npc_id).get("quest%d" % npc_state(npc_id), ""))


func npc_active(npc_id: String) -> bool:
	if _npc_removed.has(npc_id):
		return false
	var d := npc_def(npc_id)
	if d.is_empty():
		return false
	# In the data an NPC that is switched off has the string state "off"
	# (the separate `off` field is never read by the original).
	return not bool(_npc_off.get(npc_id, d.get("state", 1) is String))


## turnOnNPC / turnOffNPC. Turning on resets the dialogue state to 1.
func set_npc_on(npc_id: String, on: bool) -> void:
	if npc_def(npc_id).is_empty():
		return
	_npc_off[npc_id] = not on
	if on:
		_npc_state[npc_id] = 1
	npc_changed.emit(npc_id)


func remove_npc(npc_id: String) -> void:
	_npc_removed[npc_id] = true
	npc_changed.emit(npc_id)


## Hostile-capable human (npc.json `enemy` is "true"); spawning them as
## enemies is the world's job.
func npc_is_enemy(npc_id: String) -> bool:
	return str(npc_def(npc_id).get("enemy", "false")) == "true"


func npc_is_friendly(npc_id: String) -> bool:
	var d := npc_def(npc_id)
	if d.has("friendly"):
		return bool(d["friendly"])
	return not npc_is_enemy(npc_id)


# --- companions (data only; AI is a later wave) ---------------------------------------

func add_companion(npc_id: String, kind: String) -> void:
	_companions[npc_id] = kind
	_emit_action("companion", [npc_id, kind])
	npc_changed.emit(npc_id)


func remove_partner() -> void:
	_companions.erase("Partner")
	_emit_action("companion", ["Partner", "removed"])


func companions() -> Dictionary:
	return _companions.duplicate()


func has_partner() -> bool:
	return _companions.has("Partner")


# --- unlocks -----------------------------------------------------------------------

func _section_id(v: Variant) -> String:
	return str(_num(v))


func is_section_unlocked(section: Variant) -> bool:
	return _sections.has(_section_id(section))


func unlock_section(section: Variant) -> void:
	var id := _section_id(section)
	if id == "-1" or _sections.has(id):
		return
	_sections[id] = true
	section_unlocked.emit(id)


func unlocked_sections() -> Array[String]:
	var out: Array[String] = []
	for k in _sections:
		out.append(str(k))
	return out


func unlock_door(door_id: String) -> void:
	if door_id == "" or _doors.has(door_id):
		return
	_doors[door_id] = true
	_emit_action("unlockDoor", [door_id])


## True once a quest or trigger opened this door id (l5_s1_b1_f1_r403_door1).
func is_door_unlocked(door_id: String) -> bool:
	return _doors.has(door_id)


func has_end_loc(n: Variant) -> bool:
	return _end_locs.has(str(n))


# --- triggers -----------------------------------------------------------------------

func trigger_def(trigger_id: String) -> Dictionary:
	return Data.entry("trig", trigger_id)


func trigger_done(trigger_id: String) -> bool:
	return bool(_trig_done.get(trigger_id, trigger_def(trigger_id).get("triggered", false)))


## Runs a trigger once (again if it is `multi`, or `forced`). The world calls
## this when the player walks into a trigger zone. Returns true if it ran.
func fire_trigger(trigger_id: String, forced: bool = false) -> bool:
	var t := trigger_def(trigger_id)
	if t.is_empty():
		return false
	if trigger_done(trigger_id) and not t.get("multi", false) and not forced:
		return false
	_trig_done[trigger_id] = true
	for i in range(1, 10):
		var fn := str(t.get("func%d" % i, ""))
		if fn == "":
			continue
		var args: Array = []
		for j in range(1, 5):
			args.append(t.get("func%dvar%d" % [i, j]))
		_run_action(fn, args)
	Events.trigger_fired.emit(trigger_id)
	return true


func _run_action(fn: String, a: Array) -> void:
	match fn:
		"setActiveQuest":
			start(str(a[0]))
		"completeQuest":
			complete(str(a[0]))
		"startCutScene":
			_emit_action("startCutScene", [int(a[0])])
		"displayWorldSpeech":
			_emit_action("speech", [str(a[0]), Data.text(a[1], StoryNames.context())])
		"unlockEndLoc":
			_end_locs[str(a[0])] = true
		"turnOnNPC":
			set_npc_on(str(a[0]), true)
		"turnOffNPC":
			set_npc_on(str(a[0]), false)
		"removeNPC":
			remove_npc(str(a[0]))
		"turnOnTrigger":
			_trig_done[str(a[0])] = false
		"unlockAreas":
			unlock_section(a[1] if a[1] != null else a[0])
		"unlockArea":
			unlock_section(a[0])
		"unlockDoor":
			unlock_door(str(a[0]))
		"addPartner":
			add_companion("Partner", "partner")
		"startEndingRush":
			ending_rush = true
			if "ending_rush" in Director:
				Director.set("ending_rush", true)
			_emit_action("startEndingRush", [])
		"showEnding":
			ending_shown = true
			_emit_action("showEnding", [])
		"showHelp":
			_emit_action("showHelp", [str(a[0]), a[1]])
		"addAlert":
			_emit_action("alert", [str(a[0])])
		"triggerJebAndPaul":
			_emit_action("spawn", ["JebEnemy", "PaulEnemy"])
		"fixJack":
			_emit_action("fixJack", [])
		_:
			push_warning("Quests: unknown trigger function %s" % fn)


func _emit_action(action: String, args: Array) -> void:
	story_action.emit(action, args)
	if action == "startCutScene" and auto_play_cutscenes and is_inside_tree():
		CutscenePlayer.play_cutscene(get_tree(), int(args[0]))


## Starts the story for a new game: fires trig1 (quest 900 and cutscene 10).
func begin_story() -> void:
	fire_trigger("trig1")


# --- journal --------------------------------------------------------------------------

func track(id: String) -> void:
	if is_active(id):
		tracked = id


## Journal rows for the quest log screen: active quests first, then (optionally)
## completed ones. Each row: {id, title, short, description, status, reward,
## progress, tracked}. Text has its placeholders filled.
func journal(include_complete: bool = true) -> Array:
	var rows: Array = []
	var ctx := StoryNames.context()
	var ids: Array[String] = active_quests()
	if include_complete:
		ids.append_array(completed_quests())
	for id in ids:
		var q := quest_def(id)
		rows.append({
			"id": id,
			"title": Data.text(q.get("desc", ""), ctx),
			"short": Data.text(q.get("shortDesc", ""), ctx),
			"description": Data.text(q.get("longDesc", ""), ctx),
			"status": status(id),
			"reward": reward_text(id),
			"progress": progress_text(id),
			"tracked": tracked == id,
		})
	return rows


func reward_text(id: String) -> String:
	var q := quest_def(id)
	var parts: Array[String] = []
	var xp := int(q.get("XPreward", 0))
	if xp > 0:
		parts.append("%d XP" % xp)
	for ref in q.get("rewards", []):
		var r := str(ref)
		if r == "follower":
			parts.append("%s joins you" % str(q.get("owner", "")))
		elif r == "partner":
			pass
		elif r.begins_with("cash_"):
			parts.append("$%s" % r.trim_prefix("cash_"))
		else:
			parts.append(item_name(r))
	return ", ".join(parts)


func progress_text(id: String) -> String:
	var q := quest_def(id)
	match str(q.get("type", "")):
		"kill":
			return "%d/%d %s" % [kill_count(id), int(q.get("killCount", 1)), str(q.get("killDesc", "")).to_lower()]
		"fetch":
			var refs: Array = q.get("itemReq", [])
			var counts: Array = q.get("itemCount", [])
			var bits: Array[String] = []
			for i in refs.size():
				var need := int(counts[i]) if i < counts.size() else 1
				var have := mini(int(Inventory.items.get(item_name(str(refs[i])), {}).get("count", 0)), need)
				bits.append("%s %d/%d" % [item_name(str(refs[i])), have, need])
			return ", ".join(bits)
	return ""
