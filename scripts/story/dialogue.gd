class_name Dialogue
extends RefCounted
## Builds dialogue models from npc.json and the quest state, applies the
## player's choice to Quests, and runs a session on a DialogueBox.
##
## Selection mirrors the original: the NPC's current `state` picks
## content<N>; if that state hands out quest<N> the text becomes
## content<N>active while the quest runs and content<N>complete afterwards,
## with buttons confirm/decline, reqMet or reqNotMet, compResp.

const ACTIONS := ["accept", "decline", "turn_in", "close", "advance", "change_state"]


## The model for `npc_id` as it stands now (or at `state_override` >= 0).
## {} if the NPC has nothing to say.
static func build(npc_id: String, state_override: int = -1) -> Dictionary:
	var d: Dictionary = _sys("Quests").npc_def(npc_id)
	if d.is_empty():
		return {}
	var ctx := StoryNames.context()
	var state: int = state_override if state_override >= 0 else _sys("Quests").npc_state(npc_id)
	var m := {
		"npc": npc_id, "state": state, "quest": "", "kind": "info", "pause": true,
		"name": _sys("Data").text(d.get("fullName", d.get("name", npc_id)), ctx),
		"title": _sys("Data").text(d.get("title", ""), ctx), "text": "", "reward": "", "buttons": [],
	}
	var content_key := "content%d" % state
	if not d.has(content_key):
		var idle: Variant = d.get("say1A", "")
		if str(idle) == "" and not (idle is Dictionary):
			return {}
		m["text"] = _sys("Data").text(idle, ctx)
		m["buttons"] = [_btn("close", "OK")]
		return m
	var qid := str(d.get("quest%d" % state, ""))
	var text: Variant = d[content_key]
	if qid == "":
		m["text"] = _sys("Data").text(text, ctx)
		if d.has("changeState%d" % state):
			m["buttons"] = [_btn("change_state", _label(d, "confirm%d" % state, "OK", ctx))]
		else:
			m["buttons"] = [_btn("close", _label(d, "confirm%d" % state, "OK", ctx))]
		return m
	m["quest"] = qid
	var status: String = _sys("Quests").status(qid)
	if status == "complete":
		m["kind"] = "done"
		text = d.get(content_key + "complete", d.get(content_key + "active", text))
		m["buttons"] = [_btn("advance", _label(d, "compResp%d" % state, "OK", ctx))]
	elif status == "active":
		text = d.get(content_key + "active", text)
		if _sys("Quests").requirements_met(qid):
			m["kind"] = "ready"
			m["buttons"] = [_btn("turn_in", _label(d, "reqMet%d" % state, "OK", ctx))]
		else:
			m["kind"] = "waiting"
			m["buttons"] = [_btn("close", _label(d, "reqNotMet%d" % state, "OK", ctx))]
	else:
		m["kind"] = "offer"
		m["reward"] = _reward_line(qid)
		m["buttons"] = [
			_btn("accept", _label(d, "confirm%d" % state, "ACCEPT", ctx)),
			_btn("decline", _label(d, "decline%d" % state, "DECLINE", ctx)),
		]
	m["text"] = _sys("Data").text(text, ctx)
	return m


## Applies a button's action to the quest state. Returns the next model to
## show, or {} to close the dialogue.
static func choose(model: Dictionary, action: String) -> Dictionary:
	var npc_id := str(model.get("npc", ""))
	var qid := str(model.get("quest", ""))
	match action:
		"accept":
			_sys("Quests").start(qid)
		"turn_in":
			if _sys("Quests").complete(qid):
				return build(npc_id, int(model.get("state", -1)))
		"advance":
			if _sys("Quests").npc_state(npc_id) == int(model.get("state", -1)):
				_sys("Quests").advance_npc(npc_id)
		"change_state":
			var d: Dictionary = _sys("Quests").npc_def(npc_id)
			_sys("Quests").set_npc_state(npc_id, int(d.get("changeState%d" % int(model.get("state", 0)), -1)))
	return {}


## A one-line caption model (cutscene speech): no buttons, no pause.
static func line_model(speaker: String, text: String, seconds: float = 0.0) -> Dictionary:
	if seconds <= 0.0:
		seconds = 1.2 + text.length() * 0.045
	return {"npc": "", "name": speaker, "title": "", "text": text, "buttons": [],
		"reward": "", "pause": false, "auto_close": seconds, "kind": "line"}


## Talks to an NPC: completes talk quests aimed at them, then opens the box
## and drives it until the player closes it. Returns the box, or null when
## there is nothing to say.
static func open(tree: SceneTree, npc_id: String) -> DialogueBox:
	_sys("Quests").on_talk(npc_id)
	var model := build(npc_id)
	if model.is_empty():
		return null
	var box := DialogueBox.create()
	tree.root.add_child(box)
	var session := Session.new()
	session.box = box
	session.model = model
	box.choice_made.connect(session.on_choice)
	box.set_meta("session", session) # keep the session alive with the box
	box.show_model(model)
	return box


class Session extends RefCounted:
	var box: DialogueBox
	var model: Dictionary

	func on_choice(action: String) -> void:
		var next := Dialogue.choose(model, action)
		if next.is_empty():
			box.close()
		else:
			model = next
			box.show_model(next)


static func _btn(action: String, label: String) -> Dictionary:
	return {"action": action, "label": label}


static func _label(d: Dictionary, key: String, fallback: String, ctx: Dictionary) -> String:
	var s = _sys("Data").text(d.get(key, ""), ctx)
	return s if s != "" else fallback


static func _reward_line(qid: String) -> String:
	var r: String = _sys("Quests").reward_text(qid)
	return "Reward: " + r if r != "" else ""

static func _sys(system: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(system)
