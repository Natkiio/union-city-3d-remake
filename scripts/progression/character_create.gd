extends Control
## Character creation: pick a premade background, or spend 10 points and choose
## 4 skills. Talks to Stats only. Emits `confirmed` after Stats is set up.
## Scene: scenes/ui/character_create.tscn

signal confirmed

var _spend: Dictionary = {}
var _picks: Array = []
var _custom: bool = false
var _ref: String = ""
var _name_edit: LineEdit
var _sex: OptionButton
var _body: VBoxContainer
var _msg: Label


func _ready() -> void:
	var box := ProgUI.backdrop(self)
	box.add_child(ProgUI.label("Create your survivor", 28))
	var top := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name"
	_name_edit.custom_minimum_size.x = 220
	top.add_child(_name_edit)
	_sex = OptionButton.new()
	_sex.add_item("male")
	_sex.add_item("female")
	top.add_child(_sex)
	top.add_child(ProgUI.button("Premade backgrounds", func(): _custom = false; _refresh()))
	top.add_child(ProgUI.button("Spend points", func(): _custom = true; _refresh()))
	box.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	box.add_child(scroll)
	_msg = ProgUI.label("")
	box.add_child(_msg)
	box.add_child(ProgUI.button("Confirm", confirm))
	_refresh()


func _refresh() -> void:
	ProgUI.clear(_body)
	if _custom:
		var left: int = int(Data.table("constants")["constants"]["attributePointsMax"]) - _spent()
		_body.add_child(ProgUI.label("Attribute points left: %d    Skills chosen: %d / 4" % [left, _picks.size()], 18))
		for a in Stats.ATTRIBUTES:
			var h := HBoxContainer.new()
			h.add_child(ProgUI.label("%s %d" % [a.capitalize(), 5 + int(_spend.get(a, 0))]))
			h.add_child(ProgUI.button("-", func(): _bump(a, -1)))
			h.add_child(ProgUI.button("+", func(): _bump(a, 1)))
			_body.add_child(h)
		for s in Stats.skill_names():
			var cb := CheckBox.new()
			cb.text = s.capitalize()
			cb.button_pressed = s in _picks
			cb.toggled.connect(func(on): _toggle(s, on))
			_body.add_child(cb)
	else:
		var pre := Data.table("pre")
		for ref in pre:
			var r: Dictionary = pre[ref]
			var txt := "%s: STR %d PRE %d INT %d END %d LCK %d  [%s, %s, %s, %s]" % [r.name, r.strength, r.precision, r.intellect, r.endurance, r.luck, r.skill1, r.skill2, r.skill3, r.skill4]
			var b := ProgUI.button(("> " if ref == _ref else "") + txt, func(): _ref = ref; _refresh())
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.tooltip_text = str(r.desc)
			_body.add_child(b)


func _spent() -> int:
	var t := 0
	for a in _spend:
		t += int(_spend[a])
	return t


func _bump(a: String, d: int) -> void:
	var v := int(_spend.get(a, 0)) + d
	if v < 0 or _spent() + d > 10 or 5 + v > 10:
		return
	_spend[a] = v
	_refresh()


func _toggle(s: String, on: bool) -> void:
	if on and _picks.size() < 4 and s not in _picks:
		_picks.append(s)
	elif not on:
		_picks.erase(s)
	_refresh()


## Applies the choice to Stats. Returns false (and shows why) if incomplete.
func confirm() -> bool:
	var ok := false
	if _custom:
		ok = Stats.create_custom(_spend, _picks)
	else:
		ok = _ref != "" and Stats.set_background(_ref)
	if not ok:
		_msg.text = "Pick a background or a valid point spend."
		return false
	Stats.set_identity(_name_edit.text.strip_edges(), _sex.get_item_text(_sex.selected))
	confirmed.emit()
	return true
