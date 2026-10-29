class_name PointsPanel
extends VBoxContainer
## The character sheet body: header (name, level badge, XP, points to spend),
## attributes on the left, skills in grouped two-column grids on the right.
## "+" buttons spend Stats points unless allow_spend is false (skills sheet).
## Rebuilds itself on Events.stats_changed.

const SKILL_GROUPS := [
	["Combat", ["blunt", "blades", "pistols", "longGuns", "automatics", "specialWeapons"]],
	["Survival", ["sneak", "survival", "fitness", "firstAid"]],
	["Mind and social", ["smarts", "security", "searching", "speech"]],
]
const ATTR_W := 400
const STEP := Vector2(44, 44)

var allow_spend: bool = true
## Button to focus when the focused "+" disappears (set by the owner screen).
var fallback_focus: Control = null

var _focus_key: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	Events.stats_changed.connect(rebuild)
	rebuild()


func rebuild() -> void:
	var owner_focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner_focus != null and owner_focus.has_meta("key") and is_ancestor_of(owner_focus):
		_focus_key = str(owner_focus.get_meta("key"))
	ProgUI.clear(self)
	add_child(_header())
	add_child(_xp_row())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_attributes())
	var sep := VSeparator.new()
	body.add_child(sep)
	body.add_child(_skills())
	add_child(body)
	_restore_focus.call_deferred()


func _restore_focus() -> void:
	if _focus_key == "":
		return
	for b in find_children("*", "Button", true, false):
		if b.has_meta("key") and b.get_meta("key") == _focus_key and not (b as Button).disabled:
			b.grab_focus()
			return
	_focus_key = ""
	if fallback_focus != null and fallback_focus.is_inside_tree():
		fallback_focus.grab_focus()


# --- header -----------------------------------------------------------------

func _header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	# Level badge
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UITheme.box(UITheme.ACCENT, UITheme.ACCENT_HI, 2, 4, 6))
	badge.custom_minimum_size = Vector2(96, 0)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", -4)
	var bl := UITheme.label("LEVEL", UITheme.FS_SMALL, Color(1, 0.85, 0.8))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bn := UITheme.label(str(Stats.level), 48, Color.WHITE)
	bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(bl)
	bv.add_child(bn)
	badge.add_child(bv)
	h.add_child(badge)
	# Name and background
	var nv := VBoxContainer.new()
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var who := Stats.player_name if Stats.player_name != "" else "Survivor"
	nv.add_child(UITheme.label(who, 32))
	var bg := Stats.background.capitalize() if Stats.background != "" else "No background"
	nv.add_child(UITheme.label(bg, UITheme.FS_BODY, UITheme.TEXT_DIM))
	h.add_child(nv)
	# Points to spend
	if allow_spend:
		h.add_child(_points_chip("ATTRIBUTE POINTS", Stats.attribute_points))
		h.add_child(_points_chip("SKILL POINTS", Stats.skill_points))
	return h


func _points_chip(title: String, n: int) -> Control:
	var lit := n > 0
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(190, 0)
	p.add_theme_stylebox_override("panel", UITheme.box(
		Color(0.22, 0.17, 0.05) if lit else Color(0.11, 0.11, 0.12),
		UITheme.WARN if lit else UITheme.PANEL_EDGE, 2 if lit else 1, 4, 6))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	var t := UITheme.label(title, UITheme.FS_SMALL, UITheme.WARN if lit else UITheme.TEXT_DIM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var num := UITheme.label(str(n), 40, UITheme.WARN if lit else UITheme.TEXT_DIM)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(num)
	p.add_child(v)
	return p


func _xp_row() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.add_child(UITheme.label("XP", UITheme.FS_SMALL, UITheme.TEXT_DIM))
	var b := UITheme.bar(UITheme.XP, 14.0, 100.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.max_value = maxf(1.0, float(Stats.xp_to_next()))
	b.value = float(Stats.xp)
	h.add_child(b)
	h.add_child(UITheme.label("%d / %d" % [Stats.xp, Stats.xp_to_next()], UITheme.FS_SMALL, UITheme.TEXT_DIM))
	return h


# --- attributes ---------------------------------------------------------------

func _attributes() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = ATTR_W
	v.add_theme_constant_override("separation", 8)
	v.add_child(_heading("Attributes"))
	for a in Stats.ATTRIBUTES:
		var can: bool = allow_spend and Stats.attribute_points > 0 and Stats.attr_base(a) < Stats.attribute_max()
		v.add_child(_row(a, Stats.attr_base(a), Stats.attr_base(a), Stats.attribute_max(), 24, 60, can,
			func(): Stats.spend_attr(a), "", Stats.attr(a)))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	v.add_child(_heading("Derived"))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.add_child(_chip("Health", str(int(Stats.max_health()))))
	chips.add_child(_chip("Carry", str(int(Stats.carry_weight()))))
	chips.add_child(_chip("Stamina", str(Stats.stamina_max())))
	v.add_child(chips)
	return v


func _chip(title: String, value: String) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.12, 0.12, 0.13), UITheme.PANEL_EDGE, 1, 3, 6))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	var t := UITheme.label(title, UITheme.FS_SMALL, UITheme.TEXT_DIM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var n := UITheme.label(value, 24)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(n)
	p.add_child(v)
	return p


# --- skills ---------------------------------------------------------------------

func _skills() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	var known := Stats.skill_names()
	for g in SKILL_GROUPS:
		v.add_child(_heading(g[0]))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 6)
		for s in g[1]:
			if s not in known:
				continue
			var can: bool = allow_spend and Stats.skill_points > 0 and Stats.skill(s) < Stats.skill_max()
			var r := _row(s, Stats.skill(s), Stats.adjusted_skill(s), Stats.skill_max(), 18, 46, can,
				func(): Stats.spend_skill(s), Stats.skill_attr(s))
			r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(r)
		v.add_child(grid)
	return v


func _heading(text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(UITheme.label(text.to_upper(), UITheme.FS_BODY, UITheme.ACCENT_HI))
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(line)
	return h


## One stat row: name, bar of the raw value, the number that counts, a "+" step.
## `shown` is the big number (raw attribute, or effective skill).
func _row(key: String, raw: int, shown: int, maxv: int, _bar_h: int, height: int, can_spend: bool,
		cb: Callable, attr_of: String, effective_attr: int = -1) -> Control:
	var info: Dictionary = Data.entry("skills", key)
	var is_attr := attr_of == ""
	var p := PanelContainer.new()
	p.custom_minimum_size.y = height
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var lit := can_spend
	p.add_theme_stylebox_override("panel", UITheme.box(
		Color(0.16, 0.14, 0.10) if lit else Color(0.11, 0.11, 0.12),
		UITheme.WARN.darkened(0.25) if lit else Color(0.2, 0.2, 0.2), 1, 3, 4))
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 10
	var tip := str(info.get("desc", ""))
	if not is_attr:
		tip += "\n\nRaised by %s. Effective skill = raw + attribute bonus." % attr_of.capitalize()
	elif effective_attr != raw:
		tip += "\n\nCurrently %d after hunger and sleep penalties." % effective_attr
	p.tooltip_text = tip
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 3)
	var name_row := HBoxContainer.new()
	name_row.add_child(UITheme.label(str(info.get("title", key)).capitalize(), UITheme.FS_BODY + (3 if is_attr else 0)))
	if not is_attr:
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_row.add_child(sp)
		name_row.add_child(UITheme.label("raw %d" % raw, UITheme.FS_SMALL, UITheme.TEXT_DIM))
	mid.add_child(name_row)
	var b := UITheme.bar(UITheme.GOOD if not lit else UITheme.WARN, 8.0, 60.0)
	b.max_value = maxv
	b.value = raw
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	mid.add_child(b)
	h.add_child(mid)
	var num_box := VBoxContainer.new()
	num_box.alignment = BoxContainer.ALIGNMENT_CENTER
	num_box.add_theme_constant_override("separation", -3)
	var n := UITheme.label(str(shown), 34 if is_attr else 26, UITheme.WARN if lit else UITheme.TEXT)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.custom_minimum_size.x = 44
	num_box.add_child(n)
	h.add_child(num_box)
	if allow_spend:
		var btn := Button.new()
		btn.text = "+"
		btn.custom_minimum_size = STEP if is_attr else Vector2(38, 36)
		btn.add_theme_font_size_override("font_size", 26)
		btn.disabled = not can_spend
		btn.tooltip_text = "Spend a point on %s" % str(info.get("title", key)).capitalize()
		btn.set_meta("key", key)
		btn.pressed.connect(cb)
		h.add_child(btn)
	return p
