class_name DialogueBox
extends CanvasLayer
## Dialogue panel. It only displays the model it is handed and reports the
## button the player picked; it knows nothing about quests (see dialogue.gd).
##
## Model keys: npc (id), name, title, text, buttons [{action, label}],
## reward (line under the text), pause (bool, default true),
## auto_close (seconds after the text finishes; for caption lines, 0 = never).
## E or a click finishes the typewriter; once finished, E presses the button
## when there is exactly one. 1, 2, 3 press that button.

signal choice_made(action: String)
signal closed()

const CHARS_PER_SECOND := 90.0
const INK := Color(0.04, 0.04, 0.05)
const PAPER := Color(0.97, 0.96, 0.92)
const CAPTION_PAPER := Color(0.96, 0.87, 0.52)
const SCREEN_MARGIN := 24.0

var model: Dictionary = {}
var typing: bool = false
var free_on_close: bool = true

var _name_label: Label
var _text: RichTextLabel
var _reward: Label
var _buttons: HBoxContainer
var _balloon: ComicBalloon
var _content: MarginContainer
var _font: FontVariation
var _paused_by_me: bool = false
var _auto_left: float = -1.0
var _age: int = 0
var _big: bool = false
var _caption: bool = false


static func create() -> DialogueBox:
	return load("res://scenes/story/dialogue_box.tscn").instantiate() as DialogueBox


func _ready() -> void:
	add_to_group("run_overlay") # freed by GameState.reset_run
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 55 # below UIController (60) so map, pause and level-up screens cover captions
	_build()
	visible = false


func _build() -> void:
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.variation_embolden = 0.55
	_font.spacing_glyph = 1
	_balloon = ComicBalloon.new()
	_balloon.mouse_filter = Control.MOUSE_FILTER_STOP
	_balloon.gui_input.connect(_on_panel_input)
	add_child(_balloon)
	_content = MarginContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("margin_left", 20)
	_content.add_theme_constant_override("margin_right", 24)
	_content.add_theme_constant_override("margin_top", 16)
	_content.add_theme_constant_override("margin_bottom", 14)
	_balloon.add_child(_content)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	_content.add_child(box)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.scroll_active = false
	_text.fit_content = true
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_color_override("default_color", INK)
	_text.add_theme_font_override("normal_font", _font)
	_text.add_theme_font_size_override("normal_font_size", 22)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)
	_reward = Label.new()
	_reward.add_theme_color_override("font_color", INK)
	_reward.add_theme_font_override("font", _font)
	_reward.add_theme_font_size_override("font_size", 18)
	box.add_child(_reward)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", 14)
	box.add_child(_buttons)
	# Narrow black name tag stuck to the top-left corner (narration style).
	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_font_override("font", _font)
	_name_label.add_theme_font_size_override("font_size", 15)
	var tab := StyleBoxFlat.new()
	tab.bg_color = INK
	tab.content_margin_left = 10
	tab.content_margin_right = 10
	tab.content_margin_top = 2
	tab.content_margin_bottom = 3
	_name_label.add_theme_stylebox_override("normal", tab)
	_balloon.add_child(_name_label)


func _button_style(inverted: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color.WHITE if inverted else INK
	st.border_color = INK
	st.set_border_width_all(3)
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	return st


func _make_button(label: String) -> Button:
	var b := Button.new()
	b.text = label.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 18)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE if k == "font_color" else INK)
	b.add_theme_stylebox_override("normal", _button_style(false))
	b.add_theme_stylebox_override("hover", _button_style(true))
	b.add_theme_stylebox_override("pressed", _button_style(true))
	return b


## Shows a model (replacing any current one) and starts the typewriter.
func show_model(m: Dictionary) -> void:
	if _balloon == null:
		_ready()
	var first := not visible
	model = m
	var nm := str(m.get("name", "")).to_upper()
	if str(m.get("title", "")) != "":
		nm += "  /  " + str(m["title"]).to_upper()
	_name_label.text = nm
	_name_label.visible = nm != ""
	var shown := str(m.get("text", "")).to_upper()
	_text.text = shown
	_big = (m.get("buttons", []) as Array).size() > 1 or str(m.get("reward", "")) != "" or shown.length() > 170
	_caption = str(m.get("kind", "")) == "line" and _speaker_node(false) == null
	_age = 0
	_layout_text(shown)
	_text.visible_ratio = 0.0
	typing = true
	_reward.text = str(m.get("reward", ""))
	_reward.visible = _reward.text != ""
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	var list: Array = m.get("buttons", [])
	for i in list.size():
		var b := _make_button(str(list[i].get("label", "OK")))
		b.pressed.connect(press_button.bind(i))
		b.visible = false
		_buttons.add_child(b)
	_auto_left = -1.0
	visible = true
	if m.get("pause", true) and not _paused_by_me and not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	if first and str(m.get("npc", "")) != "":
		_sys("Events").dialogue_started.emit(str(m["npc"]))
	if str(m.get("text", "")) == "":
		finish_text()


func _process(delta: float) -> void:
	if not visible:
		return
	_place()
	if typing:
		var total := maxi(_text.get_total_character_count(), 1)
		_text.visible_ratio = minf(1.0, _text.visible_ratio + delta * CHARS_PER_SECOND / total)
		if _text.visible_ratio >= 1.0:
			finish_text()
	elif _auto_left > 0.0:
		_auto_left -= delta
		if _auto_left <= 0.0:
			close()


## Reveals all the text and shows the buttons.
func finish_text() -> void:
	typing = false
	_text.visible_ratio = 1.0
	for b in _buttons.get_children():
		b.visible = true
	var auto := float(model.get("auto_close", 0.0))
	if auto > 0.0:
		_auto_left = auto


## E / click: finish the typewriter, or press the only button.
func advance() -> void:
	if typing:
		finish_text()
	elif (model.get("buttons", []) as Array).size() == 1:
		press_button(0)


func press_button(index: int) -> void:
	var list: Array = model.get("buttons", [])
	if typing or index < 0 or index >= list.size():
		return
	choice_made.emit(str(list[index].get("action", "close")))


func close() -> void:
	if not visible and not _paused_by_me:
		return
	visible = false
	if _paused_by_me:
		get_tree().paused = false
		_paused_by_me = false
	var id := str(model.get("npc", ""))
	if id != "":
		_sys("Events").dialogue_ended.emit(id)
	closed.emit()
	if free_on_close:
		queue_free()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey or event is InputEventMouseButton):
		return
	if event.is_action_pressed("interact"):
		advance()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var idx: int = event.keycode - KEY_1
		if idx >= 0 and idx < 3 and not typing:
			press_button(idx)
			get_viewport().set_input_as_handled()


## Picks the text width: as wide as the text wants, up to a cap.
func _layout_text(shown: String) -> void:
	var vp := get_viewport().get_visible_rect().size
	var cap := 820.0 if _big else minf(vp.x * 0.4, 620.0)
	var want := _font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 12.0
	var w := clampf(want, 150.0, cap)
	if _big:
		w = maxf(w, 560.0)
	_text.custom_minimum_size = Vector2(w, 0)
	_content.reset_size()
	_balloon.size = _content.get_combined_minimum_size()


## The 3D node that is talking, or null (narration / unknown speaker).
func _speaker_node(need_visible: bool = true) -> Node3D:
	var n = model.get("speaker_node", null)
	if n is Node3D and is_instance_valid(n):
		return n
	var id := str(model.get("npc", ""))
	if id == "":
		id = str(model.get("speaker", ""))
	if id == "" or id == "partner" or not is_inside_tree():
		return null
	if id == "player":
		return null # thoughts are narration
	id = id.trim_prefix("npc_")
	for c in get_tree().get_nodes_in_group("npc"):
		if c is Node3D and str(c.get("npc_id")) == id:
			return c
	return null


func _place() -> void:
	_age += 1
	var vp := get_viewport().get_visible_rect().size
	_content.size = _content.get_combined_minimum_size()
	var sz := _content.size
	_balloon.size = sz
	_balloon.modulate.a = 0.0 if _age < 3 else 1.0
	var tab_h := _name_label.get_combined_minimum_size().y if _name_label.visible else 0.0
	_name_label.position = Vector2(14, -tab_h + 1)
	_name_label.size = _name_label.get_combined_minimum_size()
	var node := _speaker_node()
	var cam := get_viewport().get_camera_3d()
	var head := Vector2.ZERO
	var has_head := false
	if node != null and cam != null:
		var wp := node.global_position + Vector3(0, 2.0, 0)
		if not cam.is_position_behind(wp):
			head = cam.unproject_position(wp)
			has_head = true
	var pos: Vector2
	if _caption or not has_head:
		_balloon.paper = CAPTION_PAPER if _caption else PAPER
		_balloon.is_caption = _caption
		pos = Vector2((vp.x - sz.x) * 0.5, 150.0) if _caption else Vector2((vp.x - sz.x) * 0.5, vp.y - sz.y - 30.0)
		_balloon.tail_to = Vector2.INF
	else:
		_balloon.paper = PAPER
		_balloon.is_caption = false
		if _big:
			pos = Vector2(clampf(head.x - sz.x * 0.5, SCREEN_MARGIN, vp.x - sz.x - SCREEN_MARGIN), vp.y - sz.y - 30.0)
		else:
			pos = Vector2(head.x - sz.x * 0.5, head.y - sz.y - 56.0)
			if pos.y < SCREEN_MARGIN + tab_h:
				pos.y = head.y + 70.0 # no room above: hang below
		pos.x = clampf(pos.x, SCREEN_MARGIN, vp.x - sz.x - SCREEN_MARGIN)
		pos.y = clampf(pos.y, SCREEN_MARGIN + tab_h, vp.y - sz.y - SCREEN_MARGIN)
		_balloon.tail_to = head + Vector2(0, -6) - pos
	_balloon.position = pos
	_balloon.indicator = 0
	if typing:
		_balloon.indicator = 1
	elif (model.get("buttons", []) as Array).is_empty() and float(model.get("auto_close", 0.0)) <= 0.0:
		_balloon.indicator = 2
	_balloon.queue_redraw()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()

static func _sys(system: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(system)


## The drawn balloon: jittered hard ink outline, solid black drop shadow, and
## an optional tail wedge toward the speaker. Local coordinates, origin at the
## top-left of the balloon.
class ComicBalloon extends Control:
	var paper: Color = Color(0.97, 0.96, 0.92)
	var is_caption: bool = false
	var tail_to: Vector2 = Vector2.INF
	var indicator: int = 0 # 0 none, 1 dots (typing), 2 triangle (press E)

	func _outline() -> PackedVector2Array:
		var w := size.x
		var h := size.y
		var r := 3.0 if is_caption else 16.0
		var rng := RandomNumberGenerator.new()
		rng.seed = int(w * 31.0 + h * 17.0)
		var pts := PackedVector2Array()
		var j := 1.6 if is_caption else 1.4
		# Walk clockwise from top-left: top, right, bottom (right to left), left.
		var corners := [Vector2(r, 0), Vector2(w - r, 0), Vector2(w, r), Vector2(w, h - r),
			Vector2(w - r, h), Vector2(r, h), Vector2(0, h - r), Vector2(0, r)]
		var edges := [[0, 1], [2, 3], [4, 5], [6, 7]]
		var arcs := [Vector2(w - r, r), Vector2(w - r, h - r), Vector2(r, h - r), Vector2(r, r)]
		for ei in 4:
			var a: Vector2 = corners[edges[ei][0]]
			var b: Vector2 = corners[edges[ei][1]]
			var n := maxi(2, int(a.distance_to(b) / 46.0))
			for i in n:
				var t := float(i) / n
				var p := a.lerp(b, t) + Vector2(rng.randf_range(-j, j), rng.randf_range(-j, j))
				pts.append(p)
			# end of the straight edge, then the corner arc
			pts.append(b)
			if r > 4.0:
				var c: Vector2 = arcs[ei]
				var a0: float = [-PI / 2.0, 0.0, PI / 2.0, PI][ei]
				for k in range(1, 4):
					var ang: float = a0 + (PI / 2.0) * k / 4.0
					pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		return pts

	## The tail points at the speaker but stays a short wedge, never a needle.
	func _tip(tail_x: float, y0: float) -> Vector2:
		var base := Vector2(tail_x, y0)
		var d := tail_to - base
		var lim := 62.0
		return base + d.normalized() * minf(d.length(), lim) if d.length() > 0.1 else base

	func _draw() -> void:
		var tail_side := 0
		var tail_x := 0.0
		if not is_caption and tail_to != Vector2.INF:
			tail_side = 1 if tail_to.y > size.y * 0.5 else -1
			tail_x = clampf(tail_to.x, 36.0, size.x - 36.0)
		var body := _outline()
		var shadow := Vector2(7, 7)
		var ink := Color(0.04, 0.04, 0.05)
		var shadow_pts := PackedVector2Array()
		for p in body:
			shadow_pts.append(p + shadow)
		draw_colored_polygon(shadow_pts, ink)
		var tail_poly := PackedVector2Array()
		if tail_side != 0:
			var y0 := size.y if tail_side == 1 else 0.0
			var inward := -tail_side * 10.0
			var tip := _tip(tail_x, y0)
			tail_poly = PackedVector2Array([
				Vector2(tail_x - 19.0, y0 + inward), Vector2(tail_x + 19.0, y0 + inward), tip])
			var sh := PackedVector2Array()
			for p in tail_poly:
				sh.append(p + shadow)
			draw_colored_polygon(sh, ink)
			# black wedge slightly bigger than the paper one makes the outline
			var big := PackedVector2Array([
				tail_poly[0] + Vector2(-4, 0), tail_poly[1] + Vector2(4, 0),
				tip + Vector2(0, 3.0 * tail_side)])
			draw_colored_polygon(big, ink)
		draw_colored_polygon(body, paper)
		var outline := body.duplicate()
		outline.append(body[0])
		draw_polyline(outline, ink, 5.0, true)
		if tail_side != 0:
			var y0 := size.y if tail_side == 1 else 0.0
			var tip := _tip(tail_x, y0)
			var inner := PackedVector2Array([
				Vector2(tail_x - 14.0, y0 - tail_side * 4.0), Vector2(tail_x + 14.0, y0 - tail_side * 4.0), tip])
			draw_colored_polygon(inner, paper)
			# erase the border across the mouth of the tail
			draw_line(Vector2(tail_x - 13.0, y0), Vector2(tail_x + 13.0, y0), paper, 7.0)
		if indicator == 1:
			var t := Time.get_ticks_msec() / 220
			for i in 3:
				draw_circle(Vector2(size.x - 38 + i * 9, size.y - 12), 2.6 if (t + i) % 3 != 0 else 3.6, ink)
		elif indicator == 2:
			var bob := sin(Time.get_ticks_msec() / 160.0) * 2.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(size.x - 30, size.y - 20 + bob), Vector2(size.x - 14, size.y - 20 + bob),
				Vector2(size.x - 22, size.y - 9 + bob)]), ink)
