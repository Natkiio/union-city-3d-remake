class_name StoryNames
extends RefCounted
## Placeholder values for quest, NPC and cutscene text templates
## ({PartnerName}, {Formal}, ...). The extractor stores them as templates and
## leaves the values to the game; the original keyed them by the player's sex.
## Cork names live here because they are game data we invent, not text in the
## extracted tables.

const BY_SEX := {
	"male": {
		"Partner": "wife", "PartnerStart": "Wife",
		"PartnerName": "Aoife", "PartnerNameShort": "Aoife",
		"PartnerSex": "she", "PartnerSexStart": "She", "PartnerSexAddress": "her",
		"PlayerSexAddress": "him",
		"Title": "Mr.", "Formal": "sir", "FormalStart": "Sir",
		"Older": "lad", "Friendly": "boy", "Young": "young fella",
	},
	"female": {
		"Partner": "husband", "PartnerStart": "Husband",
		"PartnerName": "Cian", "PartnerNameShort": "Cian",
		"PartnerSex": "he", "PartnerSexStart": "He", "PartnerSexAddress": "him",
		"PlayerSexAddress": "her",
		"Title": "Ms.", "Formal": "ma'am", "FormalStart": "Ma'am",
		"Older": "miss", "Friendly": "girl", "Young": "young one",
	},
}


## Everything Data.text needs, from Stats (player name, sex).
static func context() -> Dictionary:
	var stats: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Stats")
	var base: Dictionary = stats.name_context()
	var sex: String = str(base.get("sex", "male"))
	var ctx: Dictionary = (BY_SEX.get(sex, BY_SEX["male"]) as Dictionary).duplicate()
	var full := str(base.get("playerName", "")).strip_edges()
	var parts := full.split(" ", false)
	ctx["playerFirstName"] = parts[0] if parts.size() > 0 else "Player"
	ctx["playerLastName"] = parts[parts.size() - 1] if parts.size() > 1 else "Walsh"
	ctx.merge(base, false)
	return ctx
