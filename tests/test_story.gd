extends "res://tests/test_base.gd"
## Story workstream: quests, NPC state, triggers, dialogue, cutscenes.

const TYPES := ["triggered", "talk", "fetch", "kill"]
const HANDLED_TRIG_FUNCS := ["setActiveQuest", "completeQuest", "startCutScene", "displayWorldSpeech",
	"unlockEndLoc", "turnOnNPC", "turnOffNPC", "removeNPC", "turnOnTrigger", "unlockAreas",
	"unlockArea", "unlockDoor", "addPartner", "startEndingRush", "showEnding", "showHelp",
	"addAlert", "triggerJebAndPaul", "fixJack"]

var Q: Node
var actions: Array = []


func run() -> void:
	Q = autoload("Quests")
	Q.auto_play_cutscenes = false
	Q.story_action.connect(func(a, args): actions.append([a, args]))
	_data_checks()
	_template_checks()
	_spine()
	_kill_quest()
	_side_quests()
	_dialogue_models()
	_cutscenes()
	_trigger_misc()
	await _box_checks()
	_save_round_trip()


func _fresh() -> void:
	autoload("Stats").reset()
	autoload("Inventory").reset()
	Q.reset()
	actions.clear()


# --- data ---------------------------------------------------------------------

func _data_checks() -> void:
	var table: Dictionary = autoload("Data").table("quest")
	check("quest table has 39 entries", table.size() == 39, str(table.size()))
	var ids: Array = Q.quest_ids()
	check("35 real quests (4 empty slots in the original)", ids.size() == 35, str(ids.size()))
	var npcs: Array = Q.npc_ids()
	var secs: Dictionary = autoload("Data").table("sections")
	var ctx_keys: Dictionary = StoryNames.context()
	var bad: Array = []
	for id in ids:
		var q: Dictionary = Q.quest_def(id)
		if str(q.get("ref")) != id:
			bad.append("%s ref" % id)
		if not TYPES.has(q.get("type")):
			bad.append("%s type %s" % [id, q.get("type")])
		if q.get("owner") != "Player" and not npcs.has(q.get("owner")):
			bad.append("%s owner %s" % [id, q.get("owner")])
		if q.has("talkReq") and not npcs.has(q["talkReq"]):
			bad.append("%s talkReq %s" % [id, q["talkReq"]])
		for ref in q.get("itemReq", []):
			if not Items.exists(ref):
				bad.append("%s itemReq %s" % [id, ref])
		for ref in q.get("startRewards", []) + q.get("rewards", []):
			if ref in ["follower", "partner"] or str(ref).begins_with("cash_"):
				continue
			if Q.item_name(ref) == ref: # mod variants resolve to "Base (mod)"
				bad.append("%s reward %s" % [id, ref])
		for sec in q.get("unlocks", []) + _arr(q.get("unlocksAreaStart")):
			if not secs.has(str(sec).trim_prefix("section")):
				bad.append("%s section %s" % [id, sec])
		for door in _arr(q.get("unlocksDoor")) + _arr(q.get("unlocksDoorStart")):
			# quest 005 points at a room (s2) that does not exist in l5: dead data in the original
			if id != "005" and not _door_room_exists(str(door)):
				bad.append("%s door %s" % [id, door])
		for n in q.get("changeStateStart", []) + q.get("changeStateComplete", []):
			if not npcs.has(n):
				bad.append("%s changeState %s" % [id, n])
		for t in _arr(q.get("triggerOnStart")) + _arr(q.get("triggerOnComplete")):
			if Q.trigger_def(str(t)).is_empty():
				bad.append("%s trigger %s" % [id, t])
		if q.has("startCutScene") and autoload("Data").table("world/cutScene%d" % int(q["startCutScene"])).is_empty():
			bad.append("%s cutscene" % id)
		var counts: Array = q.get("itemCount", [])
		if q.has("itemReq") and counts.size() != q["itemReq"].size():
			bad.append("%s itemCount size" % id)
		for field in ["desc", "shortDesc", "longDesc"]:
			bad.append_array(_missing_placeholders("%s.%s" % [id, field], q.get(field, ""), ctx_keys))
	check("all quests: owners, items, rewards, unlocks, doors, triggers, text resolve", bad.is_empty(), str(bad))
	# NPC references
	var nbad: Array = []
	for npc_id in npcs:
		var d: Dictionary = Q.npc_def(npc_id)
		for k in d:
			if str(k).begins_with("quest") and not str(k).contains("Req"):
				if not Q.has_quest(str(d[k])):
					nbad.append("%s.%s -> %s" % [npc_id, k, d[k]])
			if str(k).begins_with("content") or k == "fullName" or str(k).begins_with("say"):
				nbad.append_array(_missing_placeholders("%s.%s" % [npc_id, k], d[k], ctx_keys))
	check("npc quest refs and placeholders resolve", nbad.is_empty(), str(nbad))
	# triggers
	var tbad: Array = []
	var trig: Dictionary = autoload("Data").table("trig")
	for tid in trig:
		var t: Dictionary = trig[tid]
		for i in range(1, 10):
			var fn := str(t.get("func%d" % i, ""))
			if fn == "":
				continue
			if not HANDLED_TRIG_FUNCS.has(fn):
				tbad.append("%s %s unhandled" % [tid, fn])
			var v1: Variant = t.get("func%dvar1" % i)
			if fn in ["setActiveQuest", "completeQuest"] and not Q.has_quest(str(v1)):
				tbad.append("%s quest %s" % [tid, v1])
			if fn in ["turnOnNPC", "turnOffNPC", "removeNPC"] and not npcs.has(str(v1)):
				tbad.append("%s npc %s" % [tid, v1])
			if fn == "turnOnTrigger" and not trig.has(str(v1)):
				tbad.append("%s trig %s" % [tid, v1])
			if fn == "startCutScene" and autoload("Data").table("world/cutScene%d" % int(v1)).is_empty():
				tbad.append("%s cutscene %s" % [tid, v1])
			if fn == "displayWorldSpeech":
				tbad.append_array(_missing_placeholders(tid, t.get("func%dvar2" % i, ""), ctx_keys))
	check("55 triggers: functions handled, references resolve", tbad.is_empty() and trig.size() == 55, str(tbad) + " n=%d" % trig.size())
	var cbad: Array = []
	for n in range(1, 14):
		var c: Dictionary = autoload("Data").table("world/cutScene%d" % n)
		if c.is_empty():
			cbad.append(n)
	check("13 cutscene tables load", cbad.is_empty(), str(cbad))


func _arr(v: Variant) -> Array:
	if v == null:
		return []
	return v if v is Array else [v]


func _door_room_exists(door_id: String) -> bool:
	# l5_s1_b1_f1_r403_door1 -> world/l5 s1 b1 f1 r403
	var parts := door_id.split("_")
	if parts.size() < 6:
		return false
	var node: Variant = autoload("Data").table("world/" + parts[0])
	for key in parts.slice(1, 5):
		if not (node is Dictionary) or not (node as Dictionary).has(key):
			return false
		node = node[key]
	return node is Dictionary


func _missing_placeholders(label: String, value: Variant, ctx: Dictionary) -> Array:
	var out: Array = []
	if value is Dictionary and value.has("placeholders"):
		for p in value["placeholders"]:
			if not ctx.has(p):
				out.append("%s {%s}" % [label, p])
		var filled: String = autoload("Data").text(value, ctx)
		if filled.contains("{"):
			out.append("%s unfilled" % label)
	return out


func _template_checks() -> void:
	_fresh()
	var s: Node = autoload("Stats")
	s.set_identity("Sean Murphy", "male")
	var ctx: Dictionary = StoryNames.context()
	var q: Dictionary = Q.quest_def("902")
	var short: String = autoload("Data").text(q["longDesc"], ctx)
	check("template fills partner name (male player)", short.contains(str(ctx["PartnerNameShort"])) and not short.contains("{"), short)
	check("name context has first/last name", ctx["playerFirstName"] == "Sean" and ctx["playerLastName"] == "Murphy", str(ctx.get("playerLastName")))
	s.set_identity("Niamh Ryan", "female")
	var ctx2: Dictionary = StoryNames.context()
	check("female player gets a male partner", ctx2["Partner"] == "husband" and ctx2["PartnerSex"] == "he" and ctx2["PartnerName"] != ctx["PartnerName"], str(ctx2["PartnerName"]))
	var barry: String = Dialogue.build("Barry")["text"]
	check("dialogue text has no raw placeholders", not barry.contains("{") and barry.contains(str(ctx2["PartnerName"])), barry.substr(0, 40))
	s.set_identity("Sean Murphy", "male")


# --- the main-story spine ------------------------------------------------------------

## Talks to an NPC the way the player does: open, take the offered action.
func _talk(npc: String, action: String = "") -> Dictionary:
	Q.on_talk(npc)
	var m: Dictionary = Dialogue.build(npc)
	if action != "":
		Dialogue.choose(m, action)
	return m


func _spine() -> void:
	_fresh()
	var inv: Node = autoload("Inventory")
	var xp0: int = autoload("Stats").xp
	check("only section 16 unlocked at start", Q.is_section_unlocked(16) and not Q.is_section_unlocked(9) and not Q.is_section_unlocked("section13"))
	Q.begin_story()
	check("900 active after trig1", Q.is_active("900"))
	check("trig1 requested cutscene 10", actions.any(func(a): return a[0] == "startCutScene" and a[1][0] == 10))
	check("trig1 does not run twice", not Q.fire_trigger("trig1"))
	Q.fire_trigger("trig8")
	check("900 complete, 901 active", Q.is_complete("900") and Q.is_active("901"))
	Q.fire_trigger("trig9")
	Q.fire_trigger("trig10")
	check("902 complete unlocks sections 13 and 9", Q.is_complete("902") and Q.is_section_unlocked(13) and Q.is_section_unlocked("section9"))
	check("903 active after trig10", Q.is_active("903"))
	Q.fire_trigger("trig11")
	check("904 (talk to Shenice) active", Q.is_active("904") and not Q.is_section_unlocked(12))
	var m := _talk("Shenice")
	check("talking to Shenice completes 904 and unlocks Newtown", Q.is_complete("904") and Q.is_section_unlocked(12))
	check("Shenice now offers 905", m["quest"] == "905" and m["kind"] == "offer", str(m.get("kind")))
	Dialogue.choose(m, "accept")
	check("accepting starts 905", Q.is_active("905"))
	check("trig12 unlocks section 11", Q.fire_trigger("trig12") and Q.is_section_unlocked(11))
	Q.fire_trigger("trig21")
	check("trig21 unlocks the stadium", Q.is_section_unlocked(5))
	Q.fire_trigger("trig23")
	check("905 complete, 906 active, XP awarded", Q.is_complete("905") and Q.is_active("906") and (autoload("Stats").level > 1 or autoload("Stats").xp > xp0))
	Q.fire_trigger("trig22")
	check("906 complete, 907 active", Q.is_complete("906") and Q.is_active("907"))
	Q.fire_trigger("trig24")
	check("907 complete, 908 active", Q.is_complete("907") and Q.is_active("908"))
	m = _talk("Barry")
	check("talking to Barry completes 908 and he offers 909", Q.is_complete("908") and m["quest"] == "909" and m["kind"] == "offer", str(m))
	Dialogue.choose(m, "accept")
	check("909 active and the door behind Barry unlocked", Q.is_active("909") and Q.is_door_unlocked("l5_s1_b1_f1_r403_door1"))
	Q.fire_trigger("trig25")
	check("909 complete, 910 active", Q.is_complete("909") and Q.is_active("910"))
	m = _talk("Barry")
	check("Barry (909 done, 910 talk) completes 910", Q.is_complete("910"))
	check("Barry shows the 909 done text with an advance button", m["kind"] == "done" and m["buttons"][0]["action"] == "advance", str(m.get("kind")))
	Dialogue.choose(m, "advance")
	check("advance moves Barry to state 2", Q.npc_state("Barry") == 2)
	m = _talk("Barry")
	check("Barry offers 911", m["quest"] == "911" and m["kind"] == "offer")
	Dialogue.choose(m, "accept")
	check("911 active and the command post door unlocked", Q.is_active("911") and Q.is_door_unlocked("l5_s1_b1_f1_r404_door2"))
	Q.fire_trigger("trig27")
	check("911 complete moves Barry to state 3, 912 active", Q.is_complete("911") and Q.npc_state("Barry") == 3 and Q.is_active("912"))
	m = _talk("Barry")
	check("Barry (912 talk quest) completes 912 and offers 913", Q.is_complete("912") and m["quest"] == "913" and m["kind"] == "offer")
	Dialogue.choose(m, "accept")
	check("913 started: stadium key handed over", Q.is_active("913") and inv.has_item(Q.item_name("stadiumKey")))
	Q.fire_trigger("trig29")
	check("trig29 turns on safeRoomBarry", Q.npc_active("safeRoomBarry") and Q.npc_state("safeRoomBarry") == 1)
	_talk("safeRoomBarry")
	check("talking to safeRoomBarry completes 913", Q.is_complete("913"))
	m = Dialogue.build("safeRoomBarry")
	check("safeRoomBarry offers 914", m["quest"] == "914" and m["kind"] == "offer", str(m.get("quest")))
	Dialogue.choose(m, "accept")
	check("914 active, sewer key given", Q.is_active("914") and inv.has_item(Q.item_name("sewerKey")))
	_talk("Partner")
	check("talking to the partner completes 914", Q.is_complete("914"))
	m = Dialogue.build("Partner")
	Dialogue.choose(Dialogue.build("Partner", 1), "advance") # no-op safety
	check("Partner offers 915", m["quest"] == "915" and m["kind"] == "offer", str(m.get("kind")))
	Dialogue.choose(m, "accept")
	check("915 active", Q.is_active("915"))
	m = Dialogue.build("Partner")
	check("915 waits for the key", m["kind"] == "waiting" and not Q.requirements_met("915"), str(m.get("kind")))
	check("complete refused without the key", not Q.complete("915") and not Q.is_complete("915"))
	inv.add_item(Q.item_name("questHERCkey"))
	m = Dialogue.build("Partner")
	check("with the key the dialogue offers a turn in", m["kind"] == "ready", str(m.get("kind")))
	var nxt := Dialogue.choose(m, "turn_in")
	check("turn in completes 915: key consumed, partner joins", Q.is_complete("915") and not inv.has_item(Q.item_name("questHERCkey")) and Q.has_partner())
	check("turn in returns the completed dialogue", nxt.get("kind") == "done", str(nxt.get("kind")))
	Q.fire_trigger("trig32")
	check("trig32 unlocks Cobh and arms the cutscene triggers", Q.is_section_unlocked(6) and not Q.trigger_done("trig35"))
	Q.fire_trigger("trig35")
	check("trig35 starts 916 and requests cutscene 3", Q.is_active("916") and actions.any(func(a): return a[0] == "startCutScene" and a[1][0] == 3))
	Q.fire_trigger("trig38")
	check("trig38 completes 916", Q.is_complete("916"))
	Q.set_npc_on("Jack", true)
	m = _talk("Jack")
	check("Jack state 1 is plain talk with a change_state button", m["kind"] == "info" and m["buttons"][0]["action"] == "change_state", str(m.get("buttons")))
	Dialogue.choose(m, "change_state")
	check("Jack advances to state 2", Q.npc_state("Jack") == 2)
	m = Dialogue.build("Jack")
	Dialogue.choose(m, "accept")
	check("917 active, Waterside unlocked (unlocksAreaStart) and cutscene 6 asked", Q.is_active("917") and Q.is_section_unlocked(14) and actions.any(func(a): return a[0] == "startCutScene" and a[1][0] == 6))
	check("trig39 completes 917, starts 918", Q.fire_trigger("trig39") and Q.is_complete("917") and Q.is_active("918"))
	check("completing 917 moved Jack to state 3", Q.npc_state("Jack") == 3)
	m = Dialogue.build("Jack")
	check("Jack offers 918", m["quest"] == "918")
	Dialogue.choose(m, "accept")
	m = Dialogue.build("Jack")
	check("918 needs C4 x3, caps x3, timer", Q.missing_items("918").size() == 3 and m["kind"] == "waiting", str(Q.missing_items("918").size()))
	inv.add_item(Q.item_name("explosivesC4"), 1.0, 3)
	inv.add_item(Q.item_name("explosivesBlastingCap"), 1.0, 3)
	check("two of three items is not enough", not Q.requirements_met("918"))
	inv.add_item(Q.item_name("explosivesTimer"), 1.0, 1)
	check("918 requirements met", Q.requirements_met("918"))
	m = Dialogue.build("Jack")
	Dialogue.choose(m, "turn_in")
	check("918 complete: reward XM8, items taken, Jack state 4", Q.is_complete("918") and inv.has_item(Q.item_name("XM8_specOps")) and not inv.has_item(Q.item_name("explosivesC4")) and Q.npc_state("Jack") == 4)
	m = Dialogue.build("Jack")
	check("Jack offers 919", m["quest"] == "919" and m["kind"] == "offer", str(m))
	Dialogue.choose(m, "accept")
	check("919 start triggers trig40 and trig44", Q.is_active("919") and Q.trigger_done("trig40") and Q.trigger_done("trig44") and Q.has_partner())
	check("trig40 swaps Jack for the wall crew", not Q.npc_active("Jack") and Q.npc_active("JackWall"))
	Q.fire_trigger("trig41")
	check("trig41: 919 complete, Union Island unlocked, cutscene 7", Q.is_complete("919") and Q.is_section_unlocked(7) and Q.has_end_loc(6) and actions.any(func(a): return a[0] == "startCutScene" and a[1][0] == 7))
	Q.fire_trigger("trig45")
	check("ending rush trigger sets the flag", Q.ending_rush)
	Q.fire_trigger("trig61")
	check("showEnding trigger", Q.ending_shown and actions.any(func(a): return a[0] == "showEnding"))
	check("20 main quests complete", _count_complete(range(900, 920)) >= 19, str(_count_complete(range(900, 920))))
	var rows: Array = Q.journal()
	check("journal rows have title, description, status, reward", rows.size() > 10 and rows[0].has_all(["title", "description", "status", "reward"]) and rows[0]["title"] != "")


func _count_complete(nums: Array) -> int:
	var n := 0
	for i in nums:
		if Q.is_complete(str(i)):
			n += 1
	return n


# --- side content ---------------------------------------------------------------------

func _kill_quest() -> void:
	_fresh()
	var events: Array = []
	autoload("Events").quest_changed.connect(func(id, st): events.append([id, st]))
	var m := _talk("Fred")
	check("Fred offers 500", m["quest"] == "500" and m["kind"] == "offer", str(m.get("quest")))
	Dialogue.choose(m, "accept")
	check("500 active", Q.is_active("500"))
	autoload("Events").enemy_killed.emit("zombieSlow", 1, 10)
	autoload("Events").enemy_killed.emit("zombieFast", 1, 10)
	check("two kills counted, not ready", Q.kill_count("500") == 2 and not Q.requirements_met("500"))
	check("Fred waits", Dialogue.build("Fred")["kind"] == "waiting")
	autoload("Events").enemy_killed.emit("zombieFat", 1, 10)
	autoload("Events").enemy_killed.emit("zombieFast", 1, 10)
	check("kill count caps at 3", Q.kill_count("500") == 3 and Q.requirements_met("500"))
	var gained: Array = []
	autoload("Events").xp_gained.connect(func(n, why): gained.append([n, why]))
	Dialogue.choose(Dialogue.build("Fred"), "turn_in")
	check("turn in completes 500: 100 quest XP and the door opens", Q.is_complete("500") and gained == [[100, "quest"]] and Q.is_door_unlocked("l16_s2_b0_f0_r1_entr1"), str(gained))
	check("quest_changed events carried the states", events.any(func(e): return e == ["500", "active"]) and events.any(func(e): return e == ["500", "complete"]))
	check("progress text for the journal", Q.progress_text("500") == "3/3 zombies", Q.progress_text("500"))
	autoload("Events").enemy_killed.emit("zombieFast", 1, 10)
	check("kills after completion are ignored", Q.kill_count("500") == 3)


func _side_quests() -> void:
	_fresh()
	var inv: Node = autoload("Inventory")
	# Ed and Ray: talk quest (001) then fetch (004) with a state hand-off.
	var ed := _talk("Ed")
	check("Ed offers 001", ed["quest"] == "001")
	Dialogue.choose(ed, "accept")
	check("001 starts and sets Ray to state 2", Q.is_active("001") and Q.npc_state("Ray") == 2)
	_talk("Ray")
	check("talking to Ray completes 001", Q.is_complete("001"))
	var ray := Dialogue.build("Ray")
	check("Ray (state 2) offers 003", ray["quest"] == "003", str(ray.get("quest")))
	Dialogue.choose(ray, "accept")
	_talk("Ed")
	check("talking to Ed completes 003", Q.is_complete("003"))
	# Cash and item rewards, companion flag
	check("quest 015 pays cash", Q.quest_def("015")["rewards"] == ["cash_500"])
	for ref in ["gas", "fanBelt", "socketSet"]:
		inv.add_item(Q.item_name(ref), 1.0, 3 if ref == "gas" else 1)
	Q.start("015")
	check("015 requirements met", Q.requirements_met("015"))
	check("015 completes: cash paid, items taken", Q.complete("015") and Q.cash == 500 and not inv.has_item(Q.item_name("fanBelt")))
	check("015 changes Clarence and Fern to state 2", Q.npc_state("Clarence") == 2 and Q.npc_state("Fern") == 2)
	check("015 fires trig51 which removes Jeb and Paul", not Q.npc_active("Jeb") and not Q.npc_active("Paul") and actions.any(func(a): return a[0] == "spawn"))
	inv.add_item(Q.item_name("kellyGlasses"))
	Q.start("011")
	Q.complete("011")
	check("follower reward flags Kelly as a companion", Q.companions().get("Kelly") == "follower")
	# fetch with item counts that are plural
	Q.start("007")
	inv.add_item(Q.item_name("brokenBoard"))
	inv.add_item(Q.item_name("nails"), 1.0, 1)
	inv.add_item(Q.item_name("tape"))
	check("007 needs 2 nails", not Q.requirements_met("007") and Q.missing_items("007")[0]["need"] == 2)
	inv.add_item(Q.item_name("nails"))
	check("007 met with 2 nails", Q.requirements_met("007"))
	check("starting a quest twice is refused", not Q.start("007") and Q.complete("007") and not Q.complete("007"))
	# NPC flags
	check("Williams is flagged hostile-capable", Q.npc_is_enemy("Williams") and not Q.npc_is_enemy("Ed"))
	check("generic HERC soldier is not friendly", not Q.npc_is_friendly("HERCsoldier") and Q.npc_is_friendly("Ed"))
	check("NPCs with the string state off start off", not Q.npc_active("newBarry") and not Q.npc_active("safeRoomBarry") and Q.npc_active("Ed"))
	check("status: offered quest is available, unoffered is locked", Q.status("500") == "available" and Q.status("919") == "locked", Q.status("919"))


# --- dialogue -------------------------------------------------------------------------

func _dialogue_models() -> void:
	_fresh()
	var m := Dialogue.build("Ed")
	check("offer model: accept/decline buttons from confirm1/decline1", m["kind"] == "offer" and m["buttons"].size() == 2 and m["buttons"][0]["label"] == "ACCEPT" and m["buttons"][1]["action"] == "decline", str(m["buttons"]))
	check("offer model shows the reward", m["reward"].contains("XP"), m["reward"])
	check("offer text is content1", m["text"].contains("fence"), m["text"].substr(0, 30))
	Dialogue.choose(m, "decline")
	check("declining does nothing", Q.status("001") == "available")
	Dialogue.choose(m, "accept")
	m = Dialogue.build("Ed")
	check("active model uses content1active and reqNotMet", m["text"].begins_with("Go talk to Ray") and m["kind"] == "waiting" or m["kind"] == "ready", str(m["kind"]))
	check("talk quest 001 is 'ready' only through on_talk, button is the reqNotMet one", m["buttons"][0]["label"] in ["Not yet", "HERE THEY ARE"], m["buttons"][0]["label"])
	Q.on_talk("Ray")
	m = Dialogue.build("Ed")
	check("complete model uses content1complete or falls back, with compResp", m["kind"] == "done" and m["buttons"][0]["action"] == "advance", str(m["kind"]))
	Dialogue.choose(m, "advance")
	check("advance moves Ed to state 2", Q.npc_state("Ed") == 2)
	m = Dialogue.build("Ed")
	check("state 2 offers 004", m["quest"] == "004" and m["text"].begins_with("What?"))
	var plain := Dialogue.build("Williams")
	check("plain NPC: one OK button, no quest", plain["quest"] == "" and plain["buttons"].size() == 1 and plain["text"] != "", str(plain.get("text")))
	check("Formal placeholder filled in soldier speech", not plain["text"].contains("{"))
	check("NPC with no content for its state has no model", Dialogue.build("HERCsoldier").is_empty())
	check("full name template filled for the partner", not Dialogue.build("Partner")["name"].contains("{"), Dialogue.build("Partner")["name"])
	check("every NPC with content builds a model without raw placeholders", _all_models_clean())


func _all_models_clean() -> bool:
	for npc_id in Q.npc_ids():
		var m := Dialogue.build(npc_id)
		if not m.is_empty() and (m["text"].contains("{") or m["name"].contains("{")):
			print("dirty model: ", npc_id)
			return false
	return true


func _box_checks() -> void:
	_fresh()
	var box := DialogueBox.create()
	root.add_child(box)
	await frames(1)
	var m := Dialogue.build("Ed")
	box.show_model(m)
	check("box pauses the game while open", paused)
	check("box types text out", box.typing)
	var picked: Array = []
	box.choice_made.connect(func(a): picked.append(a))
	box.press_button(0)
	check("buttons are ignored while typing", picked.is_empty())
	box.advance()
	check("advance finishes the typewriter", not box.typing)
	box.advance()
	check("two buttons: advance does not choose for the player", picked.is_empty())
	box.press_button(1)
	check("press_button reports the action", picked == ["decline"], str(picked))
	box.close()
	await frames(1)
	check("close unpauses", not paused)
	# real session through Dialogue.open
	var live := Dialogue.open(self_tree(), "Ed")
	check("Dialogue.open returns a box", live != null)
	live.finish_text()
	live.press_button(0)
	check("accept via the box starts the quest and closes", Q.is_active("001") and not paused)
	await frames(2)
	# NPC node
	var npc: StoryNPC = load("res://scenes/story/npc.tscn").instantiate()
	npc.setup("Ed")
	root.add_child(npc)
	await frames(2)
	check("npc has a Visual child and is recessed in Z", npc.get_node_or_null("Visual") != null and npc.position.z < 0.0)
	var shape: CollisionShape3D = npc.get_node("CollisionShape3D")
	var reach: float = npc.position.z + shape.position.z + (shape.shape as BoxShape3D).size.z / 2.0
	check("trigger zone reaches the Z=0 lane", reach >= 0.0, str(reach))
	check("npc is hoverable on the pick layer", npc.is_in_group("hoverable") and npc.collision_layer & 2 != 0)
	npc.set_highlighted(true)
	check("hover highlight toggles", npc.hovered)
	var lines_before := root.get_child_count()
	var b := npc.interact()
	check("npc interact opens dialogue", b != null and root.get_child_count() == lines_before + 1)
	b.close()
	await frames(2)
	Q.set_npc_on("Ed", false)
	check("switching an NPC off hides it", not npc.visible)
	Q.set_npc_on("Ed", true)
	check("switching on shows it again", npc.visible)
	npc.queue_free()
	var hostile: StoryNPC = load("res://scenes/story/npc.tscn").instantiate()
	hostile.setup("Williams")
	root.add_child(hostile)
	await frames(1)
	check("enemy flag carried to the node", hostile.enemy_flag)
	hostile.queue_free()


func self_tree() -> SceneTree:
	return self


# --- cutscenes ------------------------------------------------------------------------

func _cutscenes() -> void:
	_fresh()
	var cp := CutscenePlayer.new()
	check("cutscene 2 loads", cp.load_cutscene(2))
	check("timeline sorted by timing", cp.timeline[0]["t"] <= cp.timeline[1]["t"] and cp.timeline.size() == 4)
	var said: Array = []
	cp.speech.connect(func(who, text): said.append([who, text]))
	var done: Array = []
	cp.finished.connect(func(n, skipped): done.append([n, skipped]))
	cp.begin(false)
	check("nothing said at t=0", said.is_empty())
	cp.step(5.0)
	check("first line (timing 1ms) plays at once", said.size() == 1, str(said))
	cp.step(2000.0)
	check("t=2000: still one line (next at 2500)", said.size() == 1)
	cp.step(600.0)
	check("t=2600: second line", said.size() == 2 and said[1][0] != "")
	cp.step(10000.0)
	check("all four lines said and the scene finished", said.size() == 4 and done == [[2, false]], str(done))
	check("player speaker is named", said[0][0] == autoload("Stats").player_name or said[0][0] != "", said[0][0])
	# skip drops speech but runs state changes: cutscene 6 removes the partner
	Q.add_companion("Partner", "partner")
	var cp6 := CutscenePlayer.new()
	cp6.load_cutscene(6)
	var said6: Array = []
	cp6.speech.connect(func(w, t): said6.append(t))
	var acts: Array = []
	cp6.action_run.connect(func(f, a): acts.append(f))
	cp6.begin(false)
	cp6.skip()
	check("skip finishes at once", not cp6.playing)
	check("skip still runs removePartner", not Q.has_partner() and acts.has("removePartner"))
	check("skip did not replay later speech", said6.size() <= 1)
	var cp7 := CutscenePlayer.new()
	cp7.load_cutscene(7)
	actions.clear()
	cp7.begin(false)
	cp7.step(4500.0)
	check("cutscene 7 hands the wall explosion to the world", actions.any(func(a): return a[0] == "animateCharacter" and a[1] == ["wallExplosion", "explode"]), str(actions))
	check("NPC speaker names resolve", cp7.speaker_label("npc_JackWall") != "" and cp7.speaker_label("npc_Jack") != "npc_Jack")
	cp7.skip()
	check("every cutscene has valid timing", _all_cutscenes_ok())
	for c in [cp, cp6, cp7]:
		c.free()


func _all_cutscenes_ok() -> bool:
	for n in range(1, 14):
		var c := CutscenePlayer.new()
		var ok := c.load_cutscene(n) and not c.timeline.is_empty() and c.end_ms > 0.0
		c.free()
		if not ok:
			return false
	return true


func _trigger_misc() -> void:
	_fresh()
	var fired: Array = []
	autoload("Events").trigger_fired.connect(func(id): fired.append(id))
	Q.fire_trigger("trig3")
	check("trigger_fired emitted", fired.has("trig3"))
	check("speech trigger became a speech action", actions.any(func(a): return a[0] == "speech" and a[1][0] == "player"))
	check("pre-armed triggers (triggered=true) do not fire", not Q.fire_trigger("trig14") and Q.trigger_done("trig14"))
	Q.fire_trigger("trig49")
	check("turnOnTrigger re-arms trig14", Q.fire_trigger("trig14") and Q.is_complete("009") and Q.is_active("010"))
	check("unknown trigger is refused", not Q.fire_trigger("nope"))


# --- persistence ------------------------------------------------------------------------

func _save_round_trip() -> void:
	_fresh()
	var inv: Node = autoload("Inventory")
	Q.start("500")
	autoload("Events").enemy_killed.emit("zombieSlow", 1, 5)
	Q.fire_trigger("trig8")
	Q.start("002")
	Q.complete("010")
	Q.set_npc_state("Ed", 2)
	Q.unlock_section(13)
	Q.unlock_door("l5_s1_b1_f1_r403_door1")
	Q.add_companion("Hank", "follower")
	Q.set_npc_on("Jack", true)
	Q.fire_trigger("trig19")
	Q.cash = 40
	var json := JSON.stringify(Q.to_dict())
	var back: Dictionary = JSON.parse_string(json)
	Q.reset()
	check("reset clears quests and sections", Q.active_quests().is_empty() and not Q.is_section_unlocked(13) and Q.is_section_unlocked(16))
	Q.from_dict(back)
	check("round trip keeps quest status", Q.is_active("500") and Q.is_active("901") and Q.is_complete("900") and Q.is_complete("010") and Q.is_active("002"))
	check("round trip keeps kill count as int", Q.kill_count("500") == 1 and typeof(Q.kill_count("500")) == TYPE_INT)
	check("round trip keeps NPC state and flags", Q.npc_state("Ed") == 2 and Q.npc_active("Jack") and Q.companions().get("Hank") == "follower")
	check("round trip keeps unlocks, triggers, cash", Q.is_section_unlocked(13) and Q.is_door_unlocked("l5_s1_b1_f1_r403_door1") and Q.trigger_done("trig8") and Q.has_end_loc(11) and Q.cash == 40)
	check("quests join the stateful group", Q.is_in_group("stateful"))
	Q.reset()
	inv.reset()
