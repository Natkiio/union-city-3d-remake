class_name Shop
extends RefCounted
## Shop rules (ORIGINAL_ANALYSIS section 7, `shopSet1..6`). Pure static
## functions plus cash helpers.
##
## Cash is an inventory item named "Cash" (weight 0, count = dollars), the same
## thing container loot hands out, so it saves with Inventory and needs no new
## API. The original's discount uses the raw Smarts skill, not the adjusted one.
## Only shopSet1 and shopSet2 exist in the extracted data.
## Selling is our addition (the original has no sell screen): a sold item
## fetches SELL_FRACTION of its base shop price, and only items that appear in
## a shop set can be sold.

const CASH_ITEM := "Cash"
const MAX_ITEMS := 9
const SELL_FRACTION := 0.5


## `ceil(cost * (100 - smarts / 2) / 100)`.
static func discount_cost(cost: int, smarts: int) -> int:
	return ceili(cost * ((100.0 - smarts / 2.0) / 100.0))


## Price the player pays now (uses the raw Smarts skill).
static func price(cost: int) -> int:
	return discount_cost(cost, LootRules.auto("Stats").skill("smarts"))


## Items of shopSet<set_id>: up to 9 of {ref, cost, num, name, item} sorted by
## slot number. `item` is the resolved inventory entry.
static func stock(set_id: Variant) -> Array:
	var table: Dictionary = (Engine.get_main_loop() as SceneTree).root.get_node("Data").table("world/shopSet%s" % str(set_id))
	var out: Array = []
	for key in table:
		var row: Dictionary = table[key]
		var item := LootRules.resolve(str(row.get("ref", "")))
		if item.is_empty():
			continue
		var label: String = item["name"]
		if item.get("mod", "") != "":
			label += " (%s)" % item["mod"]
		if item["kind"] == "ammo":
			label += " x%d" % item["count"]
		out.append({"ref": row["ref"], "cost": int(row.get("cost", 0)), "num": int(row.get("num", 0)),
			"name": label, "item": item})
	out.sort_custom(func(a, b): return a["num"] < b["num"])
	return out.slice(0, MAX_ITEMS)


# --- Cash ---------------------------------------------------------------------

static func cash() -> int:
	return int(LootRules.auto("Inventory").items.get(CASH_ITEM, {}).get("count", 0))


static func add_cash(amount: int) -> void:
	if amount > 0:
		LootRules.auto("Inventory").add_item(CASH_ITEM, 0.0, amount)


static func spend_cash(amount: int) -> bool:
	if amount > cash():
		return false
	if amount > 0:
		LootRules.auto("Inventory").remove_item(CASH_ITEM, amount)
	return true


# --- Trading ------------------------------------------------------------------

## Buys one stock row (as returned by stock()). Returns false if too poor.
static func buy(row: Dictionary) -> bool:
	var cost := price(row["cost"])
	if not spend_cash(cost):
		return false
	var item: Dictionary = row["item"]
	LootRules.auto("Inventory").add_item(item["name"], item["weight"], item["count"])
	return true


## Base cost of an item name in any shop set, or 0 when no shop sells it.
static func base_cost(item_name: String) -> int:
	for n in range(1, 7):
		for row in stock(n):
			if row["item"]["name"] == item_name:
				# Ammo rows are priced per box; sell per box worth too.
				return row["cost"]
	return 0


static func sell_price(item_name: String) -> int:
	return int(base_cost(item_name) * SELL_FRACTION)


## Sells one unit of an inventory item. Ammo sells one box's rows are not
## split: an ammo stack must hold the box count to be sold (rare, skip).
static func sell(item_name: String) -> bool:
	var value := sell_price(item_name)
	if value <= 0 or not LootRules.auto("Inventory").has_item(item_name):
		return false
	var row_count := 1
	for n in range(1, 7):
		for row in stock(n):
			if row["item"]["name"] == item_name:
				row_count = row["item"]["count"]
	if LootRules.auto("Inventory").items[item_name]["count"] < row_count:
		return false
	LootRules.auto("Inventory").remove_item(item_name, row_count)
	add_cash(value)
	return true
