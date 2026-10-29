extends "res://tests/test_base.gd"
## Foundation checks: data layer, event bus, stateful reset.

func run() -> void:
	var data := autoload("Data")
	var weapons: Dictionary = data.table("weapon")
	check("Data loads the weapon table", weapons.size() == 57, "n=%d" % weapons.size())
	check("Data.entry returns a record", data.entry("enemy", "zombieSlow").has("healthBonus"))
	check("Data.entry on a missing key is empty", data.entry("enemy", "nope").is_empty())
	check("Data loads world tables", data.has_table("world/l16"))
	var tpl := {"template": "Hi {A} {B}", "placeholders": ["A", "B"]}
	check("Data.text fills a template", data.text(tpl, {"A": "x", "B": "y"}) == "Hi x y")
	check("Data.text passes plain strings", data.text("plain") == "plain")

	var inv := autoload("Inventory")
	inv.add_item("Bandages", 0.5, 2)
	var snap: Dictionary = inv.to_dict()
	autoload("GameState").reset_run()
	check("reset_run empties inventory", inv.items.is_empty())
	inv.from_dict(snap)
	check("from_dict restores inventory", inv.items.get("Bandages", {}).get("count", 0) == 2)
	inv.reset()
