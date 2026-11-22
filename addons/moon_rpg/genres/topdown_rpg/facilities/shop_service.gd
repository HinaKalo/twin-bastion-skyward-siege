class_name ShopService
extends RefCounted
## Traditional JRPG Item & Equipment Shop Service.
## Supports stock limits, StoryBlackboard unlock conditions, Guild/affinity discounts, and sell-back.

var _shops: Dictionary = {} # shop_id -> Array[{ item_id, price, stock (-1 = infinite), condition }]


func define_shop(shop_id: String, catalog: Array) -> void:
	var normalized: Array[Dictionary] = []
	for entry in catalog:
		if typeof(entry) == TYPE_DICTIONARY:
			normalized.append({
				"item_id": str(entry.get("item_id", "")),
				"price": maxi(1, int(entry.get("price", 10))),
				"stock": int(entry.get("stock", -1)),
				"condition": str(entry.get("condition", "")),
			})
	_shops[shop_id] = normalized


func get_visible_catalog(shop_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _shops.get(shop_id, []):
		var cond := str(entry["condition"])
		if cond.is_empty() or (StoryBlackboard != null and StoryBlackboard.check(cond)):
			out.append(entry)
	return out


func get_buy_price(base_price: int, discount_rate: float = 0.0) -> int:
	return maxi(1, int(round(float(base_price) * clampf(1.0 - discount_rate, 0.25, 1.0))))


func buy(shop_id: String, item_id: String, count: int = 1, discount_rate: float = 0.0) -> Dictionary:
	if count <= 0 or not _shops.has(shop_id):
		return {"ok": false, "reason": "无效商品"}
	for entry in _shops[shop_id]:
		if str(entry["item_id"]) != item_id:
			continue
		var stock := int(entry["stock"])
		if stock >= 0 and stock < count:
			return {"ok": false, "reason": "库存不足"}
		var total_cost := get_buy_price(int(entry["price"]), discount_rate) * count
		if InventoryManager and InventoryManager.gold < total_cost:
			return {"ok": false, "reason": "金币不足"}
		if InventoryManager:
			InventoryManager.add_gold(-total_cost)
			InventoryManager.add_item(item_id, count)
		if stock >= 0:
			entry["stock"] = stock - count
		return {"ok": true, "cost": total_cost}
	return {"ok": false, "reason": "商品不存在"}


func sell(item_id: String, unit_sell_price: int, count: int = 1) -> Dictionary:
	if count <= 0 or InventoryManager == null or not InventoryManager.has_item(item_id, count):
		return {"ok": false, "reason": "物品数量不足"}
	InventoryManager.remove_item(item_id, count)
	var revenue := maxi(1, unit_sell_price) * count
	InventoryManager.add_gold(revenue)
	return {"ok": true, "revenue": revenue}
