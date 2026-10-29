extends CanvasLayer
## Lockpick minigame screen, built in code. Logic lives in PickGame; this only
## draws it and maps input.
##
## Controls: hold W / Up / left mouse to push the current pin up, release to let
## it fall; D / Right / Space / right mouse sets the pin. The pin glows when it
## is inside the sweet spot. [Force] rolls the force chance (a failure breaks the
## lock for good); [Exit] / Esc gives up.

signal finished(success: bool)

const PIN_W := 46.0
const PIN_GAP := 30.0

var game: PickGame
var def: Dictionary = {}
var on_done: Callable = Callable()
var push_held: bool = false
var rng := RandomNumberGenerator.new()
var _board: Control
var _status: Label
var _title: Label
var _force_btn: Button
var _closed: bool = false


class Board extends Control:
	var ui

	func _draw() -> void:
		var g: PickGame = ui.game
		if g == null:
			return
		var top := 20.0
		var scale := (size.y - 40.0) / 70.0  # PIN_TOP..PIN_BOTTOM spans 65, plus slack
		for i in g.pin_count():
			var x: float = 40.0 + i * (ui.PIN_W + ui.PIN_GAP)
			draw_rect(Rect2(x - 4, top, ui.PIN_W + 8, size.y - 40), Color(0.15, 0.13, 0.1))
			var y: float = g.heights[i]
			var py := top + (y - PickGame.PIN_TOP) * scale
			var lit: bool = i == g.current and g.in_spot(i, y)
			var col := Color(0.35, 0.35, 0.38)
			if i < g.current:
				col = Color(0.3, 0.7, 0.35)
			elif i == g.current:
				col = Color(1.0, 0.9, 0.3) if lit else Color(0.75, 0.75, 0.8)
			draw_rect(Rect2(x, py, ui.PIN_W, 14), col)
			draw_rect(Rect2(x + ui.PIN_W * 0.5 - 3, py + 14, 6, size.y - 40 + top - py - 14), col.darkened(0.3))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	_build()


## Starts a pick on `lock_def` (see Locks). `done` gets called with the result.
func start(lock_def: Dictionary, done: Callable) -> void:
	def = lock_def
	on_done = done
	rng.randomize()
	var diff: String = def.get("lock_diff", "normal")
	game = PickGame.create(Stats.adjusted_skill("security"), Stats.attr("luck"), diff, rng)
	get_tree().paused = true
	if _board != null:
		_refresh_text()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 380)
	panel.position = Vector2(-260, -190)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	box.add_child(_title)
	_board = Board.new()
	(_board as Board).ui = self
	_board.custom_minimum_size = Vector2(480, 220)
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.gui_input.connect(_on_board_input)
	box.add_child(_board)
	_status = Label.new()
	box.add_child(_status)
	var help := Label.new()
	help.text = "Hold W / Up / left click: push pin.   D / Right / Space / right click: set pin."
	help.add_theme_font_size_override("font_size", 12)
	box.add_child(help)
	var row := HBoxContainer.new()
	box.add_child(row)
	_force_btn = Button.new()
	_force_btn.pressed.connect(_on_force)
	row.add_child(_force_btn)
	var exit := Button.new()
	exit.name = "ExitButton"
	exit.text = "Exit"
	exit.pressed.connect(func() -> void: _close(false))
	row.add_child(exit)
	if game != null:
		_refresh_text()


func _refresh_text() -> void:
	var adj := Stats.adjusted_skill("security")
	var diff: String = def.get("lock_diff", "normal")
	_title.text = "%s LOCK [%d]  (feels %s)" % [diff.to_upper(), Locks.required_skill(diff), Locks.difficulty_label(adj, diff).to_upper()]
	_force_btn.visible = def.get("can_force", true)
	_force_btn.text = "Force lock: %d%%" % Locks.force_chance(adj, Stats.attr("luck"), diff)
	_status.text = "Pin %d / %d" % [mini(game.current + 1, game.pin_count()), game.pin_count()]


func _process(delta: float) -> void:
	if game == null or _closed:
		return
	game.tick(delta, push_held)
	_board.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	_handle_input(event)


func _input(event: InputEvent) -> void:
	_handle_input(event)


func _handle_input(event: InputEvent) -> void:
	if game == null or _closed:
		return
	if event is InputEventKey and not event.echo:
		match event.keycode:
			KEY_W, KEY_UP:
				push_held = event.pressed
			KEY_D, KEY_RIGHT, KEY_SPACE:
				if event.pressed:
					set_pin()
			KEY_ESCAPE:
				if event.pressed:
					_close(false)


func _on_board_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			push_held = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			set_pin()


func set_pin() -> void:
	var out := game.lock_pin()
	if out == PickGame.Outcome.COMPLETE:
		Locks.complete(def)
		_sfx("door")
		_close(true)
	else:
		_sfx("ui_click")
		_refresh_text()


func _on_force() -> void:
	var ok := Locks.force(def, rng)
	_sfx("door" if ok else "dry_click")
	_close(ok)


func _sfx(sound: String) -> void:
	var s := get_node_or_null("/root/Sfx")
	if s != null:
		s.play(sound)


func _close(success: bool) -> void:
	if _closed:
		return
	_closed = true
	get_tree().paused = false
	finished.emit(success)
	if on_done.is_valid():
		on_done.call(success)
	queue_free()
