class_name PointsPanel
extends VBoxContainer
## Attribute and skill rows with "+" buttons that spend Stats points.
## Rebuilds itself on Events.stats_changed. Used by the level-up and skills screens.

var allow_spend: bool = true


func _ready() -> void:
	Events.stats_changed.connect(rebuild)
	rebuild()


func rebuild() -> void:
	ProgUI.clear(self)
	add_child(ProgUI.label("Level %d    XP %d / %d" % [Stats.level, Stats.xp, Stats.xp_to_next()], 20))
	add_child(ProgUI.label("Attribute points: %d    Skill points: %d" % [Stats.attribute_points, Stats.skill_points]))
	add_child(ProgUI.label("Attributes", 18))
	for a in Stats.ATTRIBUTES:
		add_child(_row(a, Stats.attr_base(a), Stats.attr(a), Stats.attribute_points > 0, func(): Stats.spend_attr(a)))
	add_child(ProgUI.label("Skills (raw / effective)", 18))
	for s in Stats.skill_names():
		add_child(_row(s, Stats.skill(s), Stats.adjusted_skill(s), Stats.skill_points > 0, func(): Stats.spend_skill(s)))
	add_child(ProgUI.label("Max health %d    Carry %d    Stamina %d" % [Stats.max_health(), Stats.carry_weight(), Stats.stamina_max()]))


func _row(row_name: String, raw: int, eff: int, can_spend: bool, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	var n := ProgUI.label(row_name.capitalize())
	n.custom_minimum_size.x = 180
	h.add_child(n)
	h.add_child(ProgUI.label("%d / %d" % [raw, eff]))
	if allow_spend:
		var b := ProgUI.button("+", cb)
		b.disabled = not can_spend
		h.add_child(b)
	return h
