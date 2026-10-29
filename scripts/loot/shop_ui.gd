class_name ShopUI
extends CanvasLayer
## Shop screen: stock on the left (click to buy), your sellable items on the
## right (click to sell). Built in code; pauses the game while open.
## World instantiates scenes/ui/shop.tscn and calls open(shop_set).

var set_id: Variant = 1
var _cash_label: Label
var _buy_list: VBoxContainer
var _sell_list: VBoxContainer
var _message: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-340, -230)
	panel.custom_minimum_size = Vector2(680, 460)
	add_child(panel)
	var root := VBoxContainer.new()
	panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "SHOP"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_cash_label = Label.new()
	head.add_child(_cash_label)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	_buy_list = _column(cols, "BUY (click)")
	_sell_list = _column(cols, "SELL (click)")
	_message = Label.new()
	root.add_child(_message)
	var close_btn := Button.new()
	close_btn.text = "[E] Leave"
	close_btn.pressed.connect(close)
	root.add_child(close_btn)


func _column(parent: Control, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var l := Label.new()
	l.text = heading
	col.add_child(l)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(320, 300)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


func open(shop_set: Variant) -> void:
	set_id = shop_set
	visible = true
	get_tree().paused = true
	_message.text = ""
	_refresh()


func close() -> void:
	visible = false
	get_tree().paused = false


func _refresh() -> void:
	for c in _buy_list.get_children():
		c.queue_free()
	for c in _sell_list.get_children():
		c.queue_free()
	_cash_label.text = "Cash: $%d" % Shop.cash()
	for row in Shop.stock(set_id):
		var b := Button.new()
		var cost := Shop.price(row["cost"])
		b.text = "%s   $%d" % [row["name"], cost]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = cost > Shop.cash()
		b.pressed.connect(_on_buy.bind(row))
		_buy_list.add_child(b)
	for item_name in Inventory.items:
		var value := Shop.sell_price(item_name)
		if value <= 0:
			continue
		var s := Button.new()
		s.text = "%s x%d   $%d" % [item_name, Inventory.items[item_name]["count"], value]
		s.alignment = HORIZONTAL_ALIGNMENT_LEFT
		s.pressed.connect(_on_sell.bind(item_name))
		_sell_list.add_child(s)


func _on_buy(row: Dictionary) -> void:
	_message.text = "Bought %s." % row["name"] if Shop.buy(row) else "Not enough cash."
	_refresh()


func _on_sell(item_name: String) -> void:
	_message.text = "Sold %s." % item_name if Shop.sell(item_name) else "Can't sell that."
	_refresh()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		close()
