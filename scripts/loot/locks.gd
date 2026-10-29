class_name Locks
extends RefCounted
## Locks on doors and containers (ORIGINAL_ANALYSIS section 10).
##
## A lock def is a Dictionary:
##   id         unique lock id (container id, or "<room path>_<door>")
##   lock_diff  "very easy" | "easy" | "normal" | "hard" | "very hard"
##   door_id    full door id a key's `door` field must equal (doors, optional)
##   needs_key  true: only the matching key opens it, never lockpicking
##   can_force  false for doors and for containers that hold their own key
##              (default true for containers)
## State (unlocked, broken) lives in LootState.locks[id].
##
## try_open() answers immediately for keys and refusals and starts the minigame
## otherwise; `on_done.call(success: bool)` is always called, now or later.

enum Result { OPENED, STARTED, DENIED }

const DIFFS := ["very easy", "easy", "normal", "hard", "very hard"]
const PINS := {"very easy": 1, "easy": 2, "normal": 2, "hard": 3, "very hard": 3}
const K := {"very easy": 1.65, "easy": 1.4, "normal": 1.15, "hard": 0.85, "very hard": 0.625}
const REQ_KEYS := {"very easy": "lockSkillReq_veryEasy", "easy": "lockSkillReq_easy",
	"normal": "lockSkillReq_normal", "hard": "lockSkillReq_hard", "very hard": "lockSkillReq_veryHard"}
const LOCKPICK_SCENE := "res://scenes/loot/lockpick.tscn"

## Why the last try_open was denied (for the interaction prompt).
static var last_denied_reason: String = ""


static func required_skill(diff: String) -> int:
	return int(LootRules._const(REQ_KEYS.get(diff, "lockSkillReq_normal"), 45))


## Pins the player must set. The doc lists 1/2/2/3/3 by difficulty; the original
## loop runs one extra visible pin 0 that is never picked **(verify)**.
static func pin_count(diff: String) -> int:
	return PINS.get(diff, 2)


static func diff_k(diff: String) -> float:
	return K.get(diff, 1.15)


## Sweet spot half-width: min(10, adjustedSkill(security) / 5 * k).
static func half_width(adjusted_security: int, diff: String) -> float:
	return minf(LootRules._const("securitySkillModMax", 10), adjusted_security / LootRules._const("secSkillMod", 5) * diff_k(diff))


## Force lock chance in percent: min(95, round((adjustedSkill(security) + luck) * k)).
static func force_chance(adjusted_security: int, luck: int, diff: String) -> int:
	return mini(95, roundi((adjusted_security + luck) * diff_k(diff)))


## Roll for forcing: random(100) + 1 <= chance.
static func force_roll(chance: int, rng: RandomNumberGenerator) -> bool:
	return LootRules.rnd(rng, 100) + 1 <= chance


## The lock can be tried at all when adjusted security >= required - 25.
static func can_attempt(adjusted_security: int, diff: String) -> bool:
	return adjusted_security >= roundi(required_skill(diff) - LootRules._const("secSkillBuffer", 25))


## Difficulty label from adjusted security minus the required skill.
static func difficulty_label(adjusted_security: int, diff: String) -> String:
	var d := adjusted_security - required_skill(diff)
	if d > 30:
		return "very easy"
	if d > 15:
		return "easy"
	if d > -15:
		return "normal"
	if d > -45:
		return "hard"
	return "very hard"


## Security XP: round(25 + level) + ceil(adjustedSkill(smarts) / 30).
static func security_xp(level: int, adjusted_smarts: int) -> int:
	return roundi(LootRules._const("skillUse_security", 25) + level) + ceili(adjusted_smarts / LootRules._const("xpSmartsBonusDiv", 30))


# --- State -------------------------------------------------------------------

static func is_unlocked(def: Dictionary) -> bool:
	return LootRules.auto("LootState").get_lock(str(def.get("id", ""))).get("unlocked", false)


static func is_broken(def: Dictionary) -> bool:
	return LootRules.auto("LootState").get_lock(str(def.get("id", ""))).get("broken", false)


static func unlock(def: Dictionary) -> void:
	var st: Dictionary = LootRules.auto("LootState").get_lock(str(def.get("id", "")))
	st["unlocked"] = true
	LootRules.auto("LootState").set_lock(str(def.get("id", "")), st)


static func break_lock(def: Dictionary) -> void:
	var st: Dictionary = LootRules.auto("LootState").get_lock(str(def.get("id", "")))
	st["broken"] = true
	LootRules.auto("LootState").set_lock(str(def.get("id", "")), st)


## The inventory item name of a key for this lock, or "" (questItem whose
## `door` equals def.door_id, or the lock id when door_id is absent).
static func find_key(def: Dictionary) -> String:
	var want: String = str(def.get("door_id", def.get("id", "")))
	for item_name in LootRules.auto("Inventory").items:
		var info := Items.find(item_name)
		if not info.is_empty() and info["kind"] == "questItem" and info["rec"].get("door", "") == want:
			return item_name
	return ""


# --- Entry point -------------------------------------------------------------

## Tries to open a lock. Keys are checked first (and consumed on use), then the
## skill gate, then the minigame is started under `host`'s scene tree.
static func try_open(def: Dictionary, host: Node, on_done: Callable) -> int:
	last_denied_reason = ""
	if not def.get("locked", true) or is_unlocked(def):
		on_done.call(true)
		return Result.OPENED
	if is_broken(def):
		last_denied_reason = "LOCK IS BROKEN"
		on_done.call(false)
		return Result.DENIED
	var key := find_key(def)
	if key != "":
		LootRules.auto("Inventory").remove_item(key, 1)
		unlock(def)
		on_done.call(true)
		return Result.OPENED
	if def.get("needs_key", false):
		last_denied_reason = "KEY REQUIRED"
		on_done.call(false)
		return Result.DENIED
	var diff: String = def.get("lock_diff", "normal")
	var adj: int = LootRules.auto("Stats").adjusted_skill("security")
	if not can_attempt(adj, diff):
		last_denied_reason = "SECURITY SKILL TOO LOW - NEED %d" % roundi(required_skill(diff) - LootRules._const("secSkillBuffer", 25))
		on_done.call(false)
		return Result.DENIED
	var ui: Node = load(LOCKPICK_SCENE).instantiate()
	host.get_tree().root.add_child(ui)
	ui.start(def, on_done)
	return Result.STARTED


## A successful pick or force: unlocks and grants security XP.
static func complete(def: Dictionary) -> void:
	unlock(def)
	LootRules.auto("Stats").add_xp(security_xp(LootRules.auto("Stats").level, LootRules.auto("Stats").adjusted_skill("smarts")), "security")


## Force attempt: rolls once; on failure the lock is permanently broken.
static func force(def: Dictionary, rng: RandomNumberGenerator = null) -> bool:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var chance := force_chance(LootRules.auto("Stats").adjusted_skill("security"), LootRules.auto("Stats").attr("luck"), def.get("lock_diff", "normal"))
	var ok := force_roll(chance, rng)
	if ok:
		complete(def)
	else:
		break_lock(def)
	return ok
