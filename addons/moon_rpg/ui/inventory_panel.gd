class_name InventoryPanel
extends Control
## Toggleable (`I`) Inventory, Equipment, ASTLIBRA-Style Mastery & Live Stat Panel.

var _panel: PanelContainer
var _stats_label: Label
var _equip_box: VBoxContainer
var _bag_box: VBoxContainer
var _player_ref: Actor2D = null


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	size = Vector2(360, 200)
	position = Vector2(60, 35)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := AssetRegistry.get_ui_stylebox("panel_wood", 8.0) if AssetRegistry else null
	if sb != null:
		_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	_panel.add_child(root)

	var header := Label.new()
	header.text = "角色背包 / 装备 / 熟练度精通 [I 关闭]"
	header.add_theme_font_size_override("font_size", 9)
	header.add_theme_color_override("font_color", Color(1.0, 0.90, 0.55))
	root.add_child(header)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 8)
	root.add_child(cols)

	# Left column: Stats + Equipment
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	cols.add_child(left)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 8)
	left.add_child(_stats_label)

	var eq_title := Label.new()
	eq_title.text = "— 当前装备 —"
	eq_title.add_theme_font_size_override("font_size", 8)
	eq_title.add_theme_color_override("font_color", Color(0.85, 0.82, 0.68))
	left.add_child(eq_title)

	_equip_box = VBoxContainer.new()
	_equip_box.add_theme_constant_override("separation", 2)
	left.add_child(_equip_box)

	# Right column: Bag items (scrollable)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(scroll)

	_bag_box = VBoxContainer.new()
	_bag_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_bag_box)

	if EventBus:
		EventBus.player_registered.connect(func(p: Node):
			if p is Actor2D:
				_player_ref = p as Actor2D
				refresh()
		)
		EventBus.inventory_changed.connect(refresh)
		EventBus.player_stats_changed.connect(refresh)
		EventBus.mastery_updated.connect(func(_i, _x, _m, _u): refresh())


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()
		if AudioManager:
			AudioManager.play_sfx("sfx.ui_confirm")
	else:
		if AudioManager:
			AudioManager.play_sfx("sfx.ui_back")


func refresh() -> void:
	if not visible or InventoryManager == null:
		return
	if _player_ref != null and _player_ref.stat_block != null:
		var sb := _player_ref.stat_block
		_stats_label.text = "Lv.%d  金币:%d\nHP:%d/%d  ST:%d/%d\nATK:%d  DEF:%d  暴击:%d%%" % [
			sb.level, InventoryManager.gold,
			int(sb.hp), int(sb.get_stat("max_hp")),
			int(sb.st), int(sb.get_stat("max_st")),
			int(sb.get_stat("atk")), int(sb.get_stat("def")),
			int(sb.get_stat("crit_rate") * 100.0),
		]

	for c in _equip_box.get_children():
		c.queue_free()
	var slot_labels := {
		"weapon": "武器", "sub_weapon": "副手", "armor": "防具",
		"accessory_1": "饰品1", "accessory_2": "饰品2",
	}
	for s in InventoryManager.EQUIP_SLOTS:
		var iid: String = str(InventoryManager.equipment.get(s, ""))
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 8)
		if iid.is_empty():
			lbl.text = "%s: [空]" % slot_labels.get(s, s)
			lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		else:
			var idef := DataRegistry.get_item(iid)
			var iname := LocaleManager.tr_key(str(idef.get("name_key", iid)), {}, iid)
			var mxp := int(InventoryManager.mastery_xp.get(iid, 0))
			var mmax := int(idef.get("mastery_max_xp", 0))
			var mstr := " [精通★]" if bool(InventoryManager.mastery_unlocked.get(iid, false)) else (" (%d/%d)" % [mxp, mmax] if mmax > 0 else "")
			lbl.text = "%s: %s%s" % [slot_labels.get(s, s), iname, mstr]
		_equip_box.add_child(lbl)

	for c in _bag_box.get_children():
		c.queue_free()
	for iid in InventoryManager.bag.keys():
		var count := int(InventoryManager.bag[iid])
		var idef := DataRegistry.get_item(str(iid))
		var iname := LocaleManager.tr_key(str(idef.get("name_key", iid)), {}, str(iid))
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 8)
		var itype := str(idef.get("type", ""))
		var action_hint := "[装备]" if itype == "equipment" else ("[使用]" if itype == "consumable" else "")
		btn.text = "%s x%d %s" % [iname, count, action_hint]
		var icon := AssetRegistry.get_icon(str(idef.get("icon_key", ""))) if AssetRegistry else null
		if icon != null:
			btn.icon = icon
			btn.expand_icon = true
		var item_key := str(iid)
		btn.pressed.connect(func(): InventoryManager.use_item(item_key))
		_bag_box.add_child(btn)
	if _bag_box.get_child_count() > 0:
		(_bag_box.get_child(0) as Control).grab_focus()
