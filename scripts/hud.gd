extends CanvasLayer
## In-run HUD. Reads autoload state (Stats, Clock, Survival, Director, World,
## Inventory, Events) and the player node; changes nothing.
##
## Top left: health, stamina, XP and level, hunger and sleep, item count.
## Top right: day and clock, location and danger. Top centre: warnings.
## Bottom left: pickup toasts. Bottom right: weapon and ammo.
## Also hosts the UIController (pause, map, rest, skills, level-up screens).

const LOW_HEALTH_FRACTION: float = 0.3
const MAX_TOASTS := 4
const TOAST_SECONDS := 3.0
const HUNGER_NAMES := ["Fed", "Peckish", "Hungry", "Starving", "Famished"]
const SLEEP_NAMES := ["Rested", "Alert", "Tired", "Drowsy", "Exhausted"]

var player = null
var root: Control
var tl_panel: PanelContainer
var tr_panel: PanelContainer
var warn_panel: PanelContainer
var toast_box: VBoxContainer
var weapon_label: Label
var health_bar: ProgressBar
var health_label: Label
var stamina_bar: ProgressBar
var xp_bar: ProgressBar
var level_label: Label
var hunger_label: Label
var sleep_label: Label
var items_label: Label
var clock_label: Label
var place_label: Label
var danger_label: Label
var rush_label: Label
var weight_label: Label
var controller: UIController

var shown_state: Array = []
var _toasts: Array = []  # [Label, seconds left]
var _rush: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keep readouts live while paused
	add_to_group("hud")
	_build()
	Inventory.item_added.connect(_on_item_added)
	Events.rush_started.connect(func(): _rush = true)
	Events.rush_ended.connect(func(): _rush = false)
	Events.run_reset.connect(func(): _rush = false)
	Events.xp_gained.connect(func(n: int, _why: String): toast("+%d XP" % n))
	Events.level_up.connect(func(l: int): toast("Level %d" % l))
	if get_tree().get_first_node_in_group("ui_controller") == null:
		controller = UIController.new()
		add_child(controller)
	_rush = Director.rush_active
	_process(0.0)


func _build() -> void:
	root = Control.new()
	root.theme = UITheme.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# top left
	tl_panel = _corner(Control.PRESET_TOP_LEFT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	tl_panel.add_child(v)
	health_bar = UITheme.bar(UITheme.GOOD, 24)
	health_label = UITheme.outline(UITheme.label("HP", UITheme.FS_BODY, Color.WHITE))
	_overlay(health_bar, health_label)
	v.add_child(health_bar)
	stamina_bar = UITheme.bar(UITheme.STAMINA, 10)
	v.add_child(stamina_bar)
	xp_bar = UITheme.bar(UITheme.XP, 8)
	v.add_child(xp_bar)
	level_label = UITheme.label("Lv 1", UITheme.FS_SMALL, UITheme.XP)
	v.add_child(level_label)
	var vit := HBoxContainer.new()
	vit.add_theme_constant_override("separation", 12)
	hunger_label = UITheme.label("", UITheme.FS_SMALL)
	sleep_label = UITheme.label("", UITheme.FS_SMALL)
	vit.add_child(hunger_label)
	vit.add_child(sleep_label)
	v.add_child(vit)
	items_label = UITheme.label("", UITheme.FS_SMALL, UITheme.TEXT_DIM)
	v.add_child(items_label)

	# top right
	tr_panel = _corner(Control.PRESET_TOP_RIGHT)
	var r := VBoxContainer.new()
	tr_panel.add_child(r)
	clock_label = UITheme.label("", UITheme.FS_HEAD)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	place_label = UITheme.label("", UITheme.FS_BODY)
	place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	danger_label = UITheme.label("", UITheme.FS_SMALL, UITheme.TEXT_DIM)
	danger_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for l in [clock_label, place_label, danger_label]:
		r.add_child(l)

	# top centre warnings
	warn_panel = PanelContainer.new()
	root.add_child(warn_panel)
	warn_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	warn_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var w := VBoxContainer.new()
	warn_panel.add_child(w)
	rush_label = UITheme.label("THEY'RE COMING", UITheme.FS_BODY, UITheme.BAD)
	weight_label = UITheme.label("OVERLOADED", UITheme.FS_BODY, UITheme.WARN)
	for l in [rush_label, weight_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		w.add_child(l)

	# bottom left toasts
	toast_box = VBoxContainer.new()
	root.add_child(toast_box)
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	toast_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# bottom right weapon
	weapon_label = UITheme.outline(UITheme.label("Fists", UITheme.FS_BODY + 2))
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(weapon_label)
	weapon_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	weapon_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	weapon_label.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _corner(preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.05, 0.06, 0.72), UITheme.PANEL_EDGE, 1, 3, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	p.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 12)
	p.grow_horizontal = Control.GROW_DIRECTION_END if preset == Control.PRESET_TOP_LEFT else Control.GROW_DIRECTION_BEGIN
	return p


func _overlay(bar: Control, label: Label) -> void:
	bar.add_child(label)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	_update_vitals()
	_update_clock_and_place()
	_update_warnings()
	_update_weapon()
	_tick_toasts(delta)


func _text(l: Label, text: String) -> void:
	if l.text != text:
		l.text = text


func _update_vitals() -> void:
	var hp: float = Stats.max_health()
	var hp_max: float = hp
	var st: float = Stats.stamina_max()
	var st_max: float = st
	var perm: float = hp
	if is_instance_valid(player):
		hp = player.health
		hp_max = player.max_health
		perm = player.perm_health
		st = player.stamina
		st_max = maxf(player.stamina_max, 1.0)
	health_bar.max_value = hp_max
	health_bar.value = hp
	_text(health_label, "HP %d / %d" % [ceili(hp), hp_max])
	UITheme.set_bar_color(health_bar, UITheme.BAD if hp < hp_max * LOW_HEALTH_FRACTION else UITheme.GOOD)
	stamina_bar.max_value = maxf(st_max, 1.0)
	stamina_bar.value = st
	var need: int = maxi(Stats.xp_to_next(), 1)
	xp_bar.max_value = need
	xp_bar.value = Stats.xp
	_text(level_label, "Lv %d   XP %d / %d" % [Stats.level, Stats.xp, need])
	var survivor: bool = Survival.is_survivor()
	hunger_label.visible = survivor
	sleep_label.visible = survivor
	if survivor:
		var h: int = clampi(Survival.hunger_state(), 0, 4)
		var s: int = clampi(Survival.sleep_state(), 0, 4)
		_text(hunger_label, HUNGER_NAMES[h])
		_text(sleep_label, SLEEP_NAMES[s])
		hunger_label.add_theme_color_override("font_color", _level_color(h))
		sleep_label.add_theme_color_override("font_color", _level_color(s))
	_text(items_label, "Items %d  %.1f / %.0f lbs  [I]" % [Inventory.item_count(), Inventory.total_weight(), Inventory.carry_limit()])


static func _level_color(n: int) -> Color:
	if n <= 1:
		return UITheme.GOOD
	return UITheme.WARN if n == 2 else UITheme.BAD


func _update_clock_and_place() -> void:
	_text(clock_label, "Day %d  %s" % [Clock.day(), Clock.time_text()])
	var cur: Dictionary = {}
	if "current" in World and World.current is Dictionary:
		cur = World.current
	var place := ""
	var danger := Director.danger
	if not cur.is_empty():
		var sec: Dictionary = Data.entry("sections", str(cur.get("section", "")))
		place = str(sec.get("name", cur.get("section", "")))
		danger = int(cur.get("danger", danger))
		if bool(cur.get("safehouse", false)):
			place += " (safehouse)"
	_text(place_label, place if place != "" else "Cork")
	_text(danger_label, "Safe" if danger <= 0 else "Danger %d" % danger)


func _update_warnings() -> void:
	rush_label.visible = _rush
	weight_label.visible = Inventory.overweight or Inventory.is_overweight()
	warn_panel.visible = rush_label.visible or weight_label.visible


func _update_weapon() -> void:
	var weapon: String = player.equipped_weapon if is_instance_valid(player) else ""
	var loaded := -1
	var reserve := 0
	var reloading: bool = is_instance_valid(player) and player.reloading
	var gun := Weapon.from_ref(weapon)
	if gun != null:
		loaded = Inventory.get_magazine(gun.display_name, gun.mag_size)
		reserve = Inventory.items.get(gun.ammo_item_name(), {}).get("count", 0)
	var state := [weapon, loaded, reserve, reloading]
	if state == shown_state:
		return
	shown_state = state
	if gun != null:
		var status := "  RELOADING" if reloading else ""
		weapon_label.text = "%s\nAmmo: %d / %d%s" % [gun.display_name, loaded, reserve, status]
		weapon_label.add_theme_color_override("font_color", UITheme.BAD if loaded + reserve == 0 else UITheme.TEXT)
	else:
		weapon_label.text = "Fists"
		weapon_label.add_theme_color_override("font_color", UITheme.TEXT)


func _on_item_added(item_name: String) -> void:
	toast("Picked up: %s" % item_name)


## Shows a short message bottom left. Fades after `seconds`.
func toast(text: String, seconds: float = TOAST_SECONDS) -> void:
	var l := UITheme.outline(UITheme.label(text, UITheme.FS_BODY))
	toast_box.add_child(l)
	_toasts.append([l, seconds])
	while _toasts.size() > MAX_TOASTS:
		var old: Array = _toasts.pop_front()
		old[0].queue_free()


func _tick_toasts(delta: float) -> void:
	for t in _toasts.duplicate():
		t[1] -= delta
		t[0].modulate.a = clampf(t[1] / 0.5, 0.0, 1.0)
		if t[1] <= 0.0:
			t[0].queue_free()
			_toasts.erase(t)


## Rects of the HUD blocks that are currently visible, for layout checks.
func block_rects() -> Dictionary:
	var out := {}
	for pair in [["top_left", tl_panel], ["top_right", tr_panel], ["warnings", warn_panel],
			["toasts", toast_box], ["weapon", weapon_label]]:
		var c: Control = pair[1]
		if c.is_visible_in_tree() and c.size != Vector2.ZERO:
			out[pair[0]] = c.get_global_rect()
	return out
