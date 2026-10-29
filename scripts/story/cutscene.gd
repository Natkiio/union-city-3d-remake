class_name CutscenePlayer
extends Node
## Plays a cutScene<N> table (world/cutScene1..13): a timeline of actions, each
## {func, var1, var2, timing in ms}. Speech goes to the dialogue box as a
## caption; other actions are handed on as signals/Quests hooks.
##
##   displayWorldSpeech(speaker, text)  -> speech signal + caption
##   setupAnNPCDirect(n)                -> Quests.story_action("setupAnNPCDirect")
##   removePartner()                    -> Quests.remove_partner()
##   animateCharacter(target, anim)     -> Quests.story_action("animateCharacter")
##
## Skip with Escape (ui_cancel) or skip(): pending speech is dropped, pending
## state changes still run. The timeline can be stepped without rendering:
## load_cutscene(n); begin(false); step(ms).

signal speech(speaker: String, text: String)
signal action_run(func_name: String, args: Array)
signal finished(number: int, skipped: bool)

## Time after the last action before the scene ends.
const TAIL_MS := 2500

var number: int = 0
var lock_controls: bool = false
var timeline: Array = []   # [{t, func, var1, var2, done}]
var time_ms: float = 0.0
var playing: bool = false
var use_box: bool = true
var end_ms: float = 0.0
var _box: DialogueBox = null


## Loads and starts cutscene `num` under the tree root. Returns the player.
static func play_cutscene(tree: SceneTree, num: int) -> CutscenePlayer:
	var cp := CutscenePlayer.new()
	if not cp.load_cutscene(num):
		cp.free()
		return null
	tree.root.add_child.call_deferred(cp)
	cp.begin.call_deferred(true)
	return cp


func _ready() -> void:
	add_to_group("run_overlay") # freed by GameState.reset_run


func load_cutscene(num: int) -> bool:
	var t = _sys("Data").table("world/cutScene%d" % num)
	if t.is_empty():
		return false
	number = num
	lock_controls = bool(t.get("lockControls", false))
	timeline.clear()
	var i := 1
	while t.has("action%d" % i):
		var a: Dictionary = t["action%d" % i]
		timeline.append({"t": float(a.get("timing", 0)), "func": str(a.get("func", "")),
			"var1": a.get("var1"), "var2": a.get("var2"), "done": false, "order": i})
		i += 1
	timeline.sort_custom(func(x, y): return x["t"] < y["t"] or (x["t"] == y["t"] and x["order"] < y["order"]))
	end_ms = TAIL_MS + (timeline[-1]["t"] if not timeline.is_empty() else 0.0)
	return true


## Starts the timeline. `with_box` shows speech in a DialogueBox.
func begin(with_box: bool = true) -> void:
	use_box = with_box
	time_ms = 0.0
	playing = true
	for a in timeline:
		a["done"] = false
	if use_box and is_inside_tree():
		_box = DialogueBox.create()
		_box.free_on_close = false
		get_tree().root.add_child(_box)
	step(0.0)


func _process(delta: float) -> void:
	if playing:
		step(delta * 1000.0)


## Advances the clock and runs every action that has come due.
func step(dt_ms: float) -> void:
	if not playing:
		return
	time_ms += dt_ms
	for a in timeline:
		if not a["done"] and a["t"] <= time_ms:
			a["done"] = true
			_run(a, false)
	if time_ms >= end_ms:
		_finish(false)


func skip() -> void:
	if not playing:
		return
	for a in timeline:
		if not a["done"]:
			a["done"] = true
			_run(a, true)
	_finish(true)


func _unhandled_input(event: InputEvent) -> void:
	if playing and event.is_action_pressed("ui_cancel"):
		skip()
		get_viewport().set_input_as_handled()


func _run(a: Dictionary, skipping: bool) -> void:
	var fn: String = a["func"]
	match fn:
		"displayWorldSpeech":
			if skipping:
				return
			var who := speaker_label(str(a["var1"]))
			var text = _sys("Data").text(a["var2"], StoryNames.context())
			speech.emit(who, text)
			if _box != null:
				_box.show_model(Dialogue.line_model(who, text, 0.0, str(a["var1"])))
			action_run.emit(fn, [str(a["var1"]), text])
		"removePartner":
			_sys("Quests").remove_partner()
			action_run.emit(fn, [])
		_:
			var args: Array = []
			for k in ["var1", "var2"]:
				if a[k] != null:
					args.append(a[k])
			_sys("Quests").story_action.emit(fn, args)
			action_run.emit(fn, args)


## "player", "partner", "npc_Jack" -> a display name.
func speaker_label(who: String) -> String:
	var ctx := StoryNames.context()
	if who == "player":
		return str(ctx.get("playerName", "You"))
	if who == "partner":
		return str(ctx.get("PartnerName", "Partner"))
	if who.begins_with("npc_"):
		var id := who.trim_prefix("npc_")
		var d = _sys("Quests").npc_def(id)
		return _sys("Data").text(d.get("fullName", d.get("name", id)), ctx).strip_edges() if not d.is_empty() else id
	return "Survivor"


func _finish(skipped: bool) -> void:
	playing = false
	if _box != null:
		_box.free_on_close = true
		_box.close()
		_box = null
	_sys("Events").trigger_fired.emit("cutscene%d" % number)
	finished.emit(number, skipped)
	if is_inside_tree():
		queue_free()

static func _sys(system: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(system)
