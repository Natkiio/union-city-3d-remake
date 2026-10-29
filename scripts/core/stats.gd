extends Node
## Autoload "Stats". Character sheet: attributes, skills, level, XP, derived
## stats. Spec: docs/ORIGINAL_ANALYSIS.md sections 1-2; notes in
## docs/progression.md. Owner: progression.
##
## Public contract (other systems code against these): attr, skill,
## adjusted_skill, max_health, carry_weight, add_xp, level. Survival applies
## hunger/sleep penalties through set_penalty().

const ATTRIBUTES: Array[String] = ["strength", "precision", "intellect", "endurance", "luck"]

var level: int = 1
var xp: int = 0
var attribute_points: int = 0
var skill_points: int = 0
var player_name: String = ""
var sex: String = "male"
var background: String = ""

var _attrs: Dictionary = {}
var _skills: Dictionary = {}
var _penalties: Dictionary = {} # attribute name -> points subtracted (transient, owned by Survival)


func _ready() -> void:
	add_to_group("stateful")
	reset()
	Events.enemy_killed.connect(_on_enemy_killed)


# --- constants and tables -------------------------------------------------

func _c(key: String) -> Variant:
	return Data.table("constants").get("constants", {}).get(key)


func level_cap() -> int:
	return int(_c("levelCap"))


func attribute_max() -> int:
	return int(_c("attributeMax"))


func skill_max() -> int:
	return int(_c("skillMax"))


## All 15 skill names (table entries that have an "attr").
func skill_names() -> Array[String]:
	var out: Array[String] = []
	var t := Data.table("skills")
	for k in t:
		if t[k] is Dictionary and t[k].has("attr"):
			out.append(k)
	return out


## Attribute a skill depends on, "" if unknown.
func skill_attr(skill_name: String) -> String:
	return str(Data.entry("skills", skill_name).get("attr", ""))


func background_refs() -> Array:
	return Data.table("pre").keys()


# --- reads ------------------------------------------------------------------

## Attribute value including penalties (floor 1). Base 5.
func attr(attr_name: String) -> int:
	return maxi(1, int(_attrs.get(attr_name, _c("attributeBase"))) - int(_penalties.get(attr_name, 0)))


## Attribute value with no penalties (what spending and the sheet show).
func attr_base(attr_name: String) -> int:
	return int(_attrs.get(attr_name, _c("attributeBase")))


## Raw skill points (base 7).
func skill(skill_name: String) -> int:
	return int(_skills.get(skill_name, _c("skillBase")))


## round(skill + attribute * 1.6 - 5). Use this for every skill check.
func adjusted_skill(skill_name: String) -> int:
	var a := skill_attr(skill_name)
	var bonus: float = 0.0
	if a != "":
		bonus = attr(a) * float(_c("attributeMod")) - float(_c("attributeBase"))
	return roundi(skill(skill_name) + bonus)


## round(20 + endurance^2 + level * 10).
func max_health() -> float:
	var e := attr("endurance")
	return float(roundi(20 + e * e + level * 10))


## strength * 10.
func carry_weight() -> float:
	return float(attr("strength") * 10)


func xp_to_next() -> int:
	return level_xp(level)


## 100 * L^2 (round(20*L*(5L)/100) * 100). Per level, not cumulative.
func level_xp(for_level: int) -> int:
	return roundi(float(_c("levelXPMult")) * for_level * (5 * for_level) / 100.0) * 100


func stamina_max() -> int:
	return roundi(level + attr("endurance") + adjusted_skill("fitness") + 56)


## Stamina regained per tick (starts 15 ticks after last use; that timer is the user's).
func stamina_regen() -> float:
	return maxf(0.1, roundi((attr("endurance") + adjusted_skill("fitness")) / 20.0))


## Health regained per tick once regen has started (15 ticks after a hit).
func health_regen_per_tick() -> float:
	return max_health() / 200.0 * (attr("endurance") + roundi(adjusted_skill("survival") / 5.0)) / 2.0


## Stamina cost of an action ("run", "shove", "jump") after the fitness discount.
func stamina_cost(action: String) -> float:
	var base := {"run": 1.0, "shove": 1.0, "jump": 5.0}.get(action, 0.0) as float
	return base - base / 100.0 * adjusted_skill("fitness") / 10.0


## Crit chance in percent: round(luck / 7 + adjustedSkill(weaponSkill) / 11).
func crit_chance(skill_name: String) -> int:
	return roundi(attr("luck") / 7.0 + adjusted_skill(skill_name) / float(_c("critSkillReduction")))


## Placeholder context for Data.text (names in quest/NPC templates).
func name_context() -> Dictionary:
	return {"playerName": player_name, "sex": sex}


## Books: adds n points to a skill, capped at skill_max(). Returns points actually added.
func add_skill_points(skill_name: String, n: int) -> int:
	var before := skill(skill_name)
	_skills[skill_name] = mini(before + n, skill_max())
	Events.stats_changed.emit()
	return skill(skill_name) - before


# --- penalties (Survival) -----------------------------------------------------

## Subtract n from an attribute until cleared (n = 0). Not saved; Survival re-applies.
func set_penalty(attr_name: String, n: int) -> void:
	if n <= 0:
		_penalties.erase(attr_name)
	else:
		_penalties[attr_name] = n
	Events.stats_changed.emit()


func clear_penalties() -> void:
	_penalties.clear()
	Events.stats_changed.emit()


# --- XP and levelling ---------------------------------------------------------

## Awards XP; levels up when the threshold is reached (XP then resets to 0).
func add_xp(amount: int, reason: String = "") -> void:
	if amount <= 0 or level >= level_cap():
		return
	xp += amount
	Events.xp_gained.emit(amount, reason)
	if xp >= xp_to_next():
		xp = 0
		level += 1
		attribute_points += int(_c("playerAttPoints"))
		skill_points += int(_c("playerSkillPoints"))
		Events.level_up.emit(level)
	Events.stats_changed.emit()


## round(round(danger * 5) + 5) * enemy.xpBonus; 0 when level - danger > 4.
func kill_xp(enemy_ref: String, danger: int) -> int:
	if level - danger > int(_c("XPcutOff")):
		return 0
	var base := roundi(danger * 5.0) + 5
	var bonus: float = float(Data.entry("enemy", enemy_ref).get("xpBonus", 1.0))
	return roundi(base * bonus)


func _on_enemy_killed(enemy_ref: String, danger: int, xp_hint: int) -> void:
	var amount := kill_xp(enemy_ref, danger)
	if amount > 0 and xp_hint > 0:
		amount = xp_hint # the emitter already applied its own bonus
	add_xp(amount, "kill:" + enemy_ref)


## Death costs half the current XP.
func apply_death_penalty() -> void:
	xp = int(xp / 2)
	Events.stats_changed.emit()


# --- spending points ----------------------------------------------------------

func spend_attr(attr_name: String) -> bool:
	if attr_name not in ATTRIBUTES or attribute_points <= 0 or attr_base(attr_name) >= attribute_max():
		return false
	_attrs[attr_name] = attr_base(attr_name) + 1
	attribute_points -= 1
	Events.stats_changed.emit()
	return true


func spend_skill(skill_name: String) -> bool:
	if skill_attr(skill_name) == "" or skill_points <= 0 or skill(skill_name) >= skill_max():
		return false
	_skills[skill_name] = skill(skill_name) + 1
	skill_points -= 1
	Events.stats_changed.emit()
	return true


# --- character creation -------------------------------------------------------

## Starts a fresh level-1 character from a premade background: its attributes,
## and +selectedSkillBonus on each of its four skills. False if unknown.
func set_background(ref: String) -> bool:
	var pre := Data.entry("pre", ref)
	if pre.is_empty():
		return false
	_fresh()
	background = ref
	for a in ATTRIBUTES:
		_attrs[a] = clampi(int(pre.get(a, _c("attributeBase"))), 1, attribute_max())
	for i in range(1, int(_c("numSelectedSkills")) + 1):
		_boost_skill(str(pre.get("skill%d" % i, "")))
	Events.stats_changed.emit()
	return true


## Free-spend creation: `spend` maps attribute -> points added to base 5 (total
## <= attributePointsMax, each result <= attributeStartMax); `picks` are up to
## numSelectedSkills distinct skills that get the selected-skill bonus.
func create_custom(spend: Dictionary, picks: Array) -> bool:
	var total := 0
	for a in spend:
		if a not in ATTRIBUTES or int(spend[a]) < 0:
			return false
		total += int(spend[a])
		if int(_c("attributeBase")) + int(spend[a]) > int(_c("attributeStartMax")):
			return false
	if total > int(_c("attributePointsMax")) or picks.size() > int(_c("numSelectedSkills")):
		return false
	for p in picks:
		if skill_attr(p) == "" or picks.count(p) > 1:
			return false
	_fresh()
	for a in spend:
		_attrs[a] = attr_base(a) + int(spend[a])
	for p in picks:
		_boost_skill(p)
	Events.stats_changed.emit()
	return true


func set_identity(new_name: String, new_sex: String) -> void:
	player_name = new_name
	sex = new_sex if new_sex in ["male", "female"] else "male"
	Events.stats_changed.emit()


func _boost_skill(skill_name: String) -> void:
	if skill_attr(skill_name) != "":
		_skills[skill_name] = mini(skill(skill_name) + int(_c("selectedSkillBonus")), skill_max())


func _fresh() -> void:
	level = 1
	xp = 0
	attribute_points = 0
	skill_points = 0
	background = ""
	_penalties.clear()
	_attrs.clear()
	_skills.clear()
	for a in ATTRIBUTES:
		_attrs[a] = int(_c("attributeBase"))
	for s in skill_names():
		_skills[s] = int(_c("skillBase"))


# --- stateful -----------------------------------------------------------------

func reset() -> void:
	_fresh()
	player_name = ""
	sex = "male"


func to_dict() -> Dictionary:
	return {
		"level": level, "xp": xp, "attribute_points": attribute_points,
		"skill_points": skill_points, "name": player_name, "sex": sex,
		"background": background, "attrs": _attrs.duplicate(), "skills": _skills.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	_fresh()
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	attribute_points = int(d.get("attribute_points", 0))
	skill_points = int(d.get("skill_points", 0))
	player_name = str(d.get("name", ""))
	sex = str(d.get("sex", "male"))
	background = str(d.get("background", ""))
	for k in d.get("attrs", {}):
		_attrs[k] = int(d["attrs"][k])
	for k in d.get("skills", {}):
		_skills[k] = int(d["skills"][k])
	Events.stats_changed.emit()
