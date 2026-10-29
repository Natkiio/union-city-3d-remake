extends Node
## Wires the systems together inside the run scene (scenes/main.tscn). Each
## owner exposes signals and an API; this node is the one place that connects
## them, so no system has to know about another's screens:
##
##   World.map_requested       -> map screen (UIController)
##   World.bed_used            -> sleep / wait dialog
##   World.trigger_entered(id) -> Quests.fire_trigger("trig<id>")
##   World.door_refused        -> HUD message
##   Quests.story_action       -> speech bubbles, doors, ending rush, ending
##                                screen, help and alert messages, cash...
##   Events.quest_changed      -> HUD toasts and quest-giver markers (! ?)
##   Settings brightness       -> the run scene's environment
##   PlayerProvider            -> restores a loaded player once it is placed
##
## Created by scripts/world/run_scene.gd (no class_name: it talks to the
## autoloads by name, which -s test scripts cannot compile in class scripts). Owner: integrate. See
## docs/integration.md.

const MARKER_NAME := "QuestMarker"
const MARKER_OFFER := "!"
const MARKER_TURN_IN := "?"
const BUBBLE_MIN_SECONDS := 2.5
const BUBBLE_SECONDS_PER_CHAR := 0.06

## showHelp ids used by trig.json, in our words.
const HELP := {
	"search": "Press E at cupboards, bins and boxes to search them.",
	"safehouse": "This is a safehouse: zombies do not come in here. Use the bed (or Z) to sleep or wait.",
	"sprint": "Hold Shift to run. Running uses stamina.",
}

var run: Node = null
## Quests known to be active, so the first quest_changed("active") reads as
## "accepted" and later ones as progress.
var _active: Dictionary = {}
var _ending_shown: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("run_glue")
	add_to_group("brightness_target")
	for id in Quests.active_quests():
		_active[id] = true
	World.map_requested.connect(_on_map_requested)
	World.bed_used.connect(_on_bed_used)
	World.trigger_entered.connect(_on_trigger_entered)
	World.door_refused.connect(_on_door_refused)
	World.room_entered.connect(_on_room_entered)
	Quests.story_action.connect(_on_story_action)
	Quests.npc_changed.connect(func(_id: String): refresh_markers())
	Events.quest_changed.connect(_on_quest_changed)
	Events.run_reset.connect(func(): _active.clear())
	Inventory.inventory_changed.connect(refresh_markers)
	apply_brightness(Settings.brightness_factor())
	refresh_markers()


## Called by the run scene after World built the first room.
func after_first_build() -> void:
	PlayerProvider.apply_pending(_player())
	refresh_markers()


func _player() -> Node3D:
	return run.get_player() if run != null and run.has_method("get_player") else null


func _controller() -> UIController:
	return get_tree().get_first_node_in_group("ui_controller") as UIController


func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")


func toast(text: String) -> void:
	var hud := _hud()
	if hud != null and hud.has_method("toast"):
		hud.toast(text)
	DebugLog.say("Glue", text)


# --- world -> ui ---------------------------------------------------------------

func _on_map_requested() -> void:
	var c := _controller()
	if c != null and not c.is_open():
		c.open_map()


func _on_bed_used() -> void:
	var c := _controller()
	if c != null and not c.is_open():
		c.open_sleep()


func _on_door_refused(_door_id: String, reason: String) -> void:
	match reason:
		"blocked":
			toast("It won't open.")
		"needs key":
			toast("Locked. You need a key.")
		"locked":
			toast("Locked.")
		_:
			toast(reason.capitalize() if reason != "" else "Locked.")


func _on_room_entered(_info: Dictionary) -> void:
	refresh_markers()


# --- world -> story ------------------------------------------------------------

## Trigger markers in the art are "trig<N>"; World strips the prefix.
func _on_trigger_entered(trigger_id: String) -> void:
	var id := trigger_id if trigger_id.begins_with("trig") else "trig" + trigger_id
	Quests.fire_trigger(id)


func _on_story_action(action: String, args: Array) -> void:
	match action:
		"speech":
			speech_bubble(str(args[0]) if args.size() > 0 else "player", str(args[1]) if args.size() > 1 else "")
		"unlockDoor":
			if args.size() > 0:
				World.unlock_door(str(args[0]))
		"startEndingRush":
			Director.start_ending_rush()
			toast("They're coming. Hold on.")
		"showEnding":
			show_ending()
		"cash":
			toast("+$%d" % int(args[0]) if args.size() > 0 else "Cash")
		"showHelp":
			var key := str(args[0]) if args.size() > 0 else ""
			toast(HELP.get(key, key.capitalize()))
		"alert":
			toast(str(args[0]) if args.size() > 0 else "")
		"companion":
			if args.size() > 1 and str(args[1]) != "removed":
				toast("%s is with you now." % _npc_name(str(args[0])))
		"spawn":
			_spawn_story_enemies(args)
		"startCutScene":
			pass # Quests plays it (CutscenePlayer)
		_:
			# setupAnNPCDirect, animateCharacter, fixJack: presentation only, no
			# state to change here (see docs/integration.md, known gaps).
			DebugLog.say("Glue", "story action %s %s not presented" % [action, str(args)])


## Jeb and Paul's ambush. Human enemies belong to the companions workstream;
## when Companions offers spawn_enemy(npc_id, x) it places them.
func _spawn_story_enemies(ids: Array) -> void:
	var comp := get_node_or_null("/root/Companions")
	var p := _player()
	for id in ids:
		if comp != null and comp.has_method("spawn_enemy") and p != null:
			comp.spawn_enemy(str(id), p.global_position.x + 4.0)
		else:
			DebugLog.say("Glue", "no human enemy spawner for %s" % id)


func _npc_name(npc_id: String) -> String:
	var d: Dictionary = Quests.npc_def(npc_id)
	return Data.text(d.get("name", npc_id), StoryNames.context()) if not d.is_empty() else npc_id


## A caption above the speaker ("player", "partner", "npc_<id>" or an NPC id)
## for a few seconds. Falls back to the player when the speaker is not here.
func speech_bubble(speaker: String, text: String) -> Label3D:
	var target: Node3D = _speaker_node(speaker)
	if target == null or text == "":
		return null
	var old := target.get_node_or_null("SpeechBubble")
	if old != null:
		old.free()
	var l := Label3D.new()
	l.name = "SpeechBubble"
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.005
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1, 1, 1)
	l.position = Vector3(0, 2.2, 0)
	target.add_child(l)
	var t := l.create_tween()
	t.tween_interval(maxf(BUBBLE_MIN_SECONDS, text.length() * BUBBLE_SECONDS_PER_CHAR))
	t.tween_property(l, "modulate:a", 0.0, 0.4)
	t.tween_callback(l.queue_free)
	return l


func _speaker_node(speaker: String) -> Node3D:
	var id := speaker.trim_prefix("npc_")
	if speaker != "player" and World.level() != null:
		for n in World.level().find_children("NPC_" + id, "", true, false):
			if n is Node3D and n.visible:
				return n
	return _player()


func show_ending() -> Control:
	if _ending_shown:
		return null
	_ending_shown = true
	var c := _controller()
	var screen := EndingScreen.new()
	if c != null:
		c.close_all()
		return c.open(screen)
	add_child(screen)
	return screen


# --- quests -> hud ---------------------------------------------------------------

func _on_quest_changed(id: String, state: String) -> void:
	var title := Data.text(Quests.quest_def(id).get("desc", id), StoryNames.context())
	if state == Quests.DONE:
		_active.erase(id)
		toast("Quest complete: %s" % title)
		Sfx.play("level_up")
	elif not _active.has(id):
		_active[id] = true
		toast("New quest: %s" % title)
		Sfx.play("ui_click")
	else:
		var progress := Quests.progress_text(id)
		if progress != "":
			toast("%s: %s" % [title, progress])
	refresh_markers()


## "!" over an NPC whose current state offers a quest not yet taken, "?" over
## one whose active quest can be handed in now.
static func marker_for(npc_id: String) -> String:
	var q: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Quests")
	if not q.npc_active(npc_id):
		return ""
	var qid: String = q.npc_quest(npc_id)
	if qid == "":
		return ""
	match q.status(qid):
		"available":
			return MARKER_OFFER
		"active":
			return MARKER_TURN_IN if q.requirements_met(qid) else ""
	return ""


func refresh_markers() -> void:
	var level := World.level()
	if level == null or not is_instance_valid(level):
		return
	for npc in level.find_children("NPC_*", "", true, false):
		if not (npc is Node3D) or not ("npc_id" in npc):
			continue
		var mark := marker_for(str(npc.npc_id))
		var label: Label3D = npc.get_node_or_null(MARKER_NAME)
		if mark == "":
			if label != null:
				label.visible = false
			continue
		if label == null:
			label = Label3D.new()
			label.name = MARKER_NAME
			label.font_size = 96
			label.pixel_size = 0.006
			label.outline_size = 18
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.position = Vector3(0, 2.5, 0)
			label.modulate = Color(1.0, 0.85, 0.2)
			npc.add_child(label)
		label.text = mark
		label.visible = true


# --- settings ----------------------------------------------------------------------

## Brightness 0..1 from Settings (0.5 = unchanged) as an environment
## adjustment. Called on ready and by Settings.apply.
func apply_brightness(factor: float) -> void:
	if run == null:
		return
	var we: WorldEnvironment = run.get_node_or_null("WorldEnvironment")
	if we == null or we.environment == null:
		return
	we.environment.adjustment_enabled = true
	we.environment.adjustment_brightness = factor
