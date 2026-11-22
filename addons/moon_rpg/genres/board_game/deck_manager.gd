class_name DeckManager
extends RefCounted
## Pure-Data Card / Deckbuilding Engine (Slay the Spire / Gloomhaven / Tabletop style).
## Supports deterministic seeded Fisher-Yates shuffling (multiplayer & replay safe),
## draw/hand/discard/exhaust piles, auto-reshuffle on empty draw pile, peek/scry,
## and full `serialize()` / `deserialize()`.

signal card_drawn(card: Dictionary)
signal card_played(card: Dictionary)
signal card_discarded(card: Dictionary)
signal card_exhausted(card: Dictionary)
signal deck_reshuffled(count: int)

var max_hand_size: int = 10
var draw_pile: Array[Dictionary] = []
var hand: Array[Dictionary] = []
var discard_pile: Array[Dictionary] = []
var exhaust_pile: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _uid_counter: int = 0


func _init(seed_val: int = 0) -> void:
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()


func set_seed(seed_val: int) -> void:
	_rng.seed = seed_val


func add_card(card_def: Dictionary, pile: String = "draw") -> Dictionary:
	_uid_counter += 1
	var card := card_def.duplicate(true)
	if not card.has("uid"):
		card["uid"] = "card_%d" % _uid_counter
	match pile:
		"hand":
			hand.append(card)
		"discard":
			discard_pile.append(card)
		"exhaust":
			exhaust_pile.append(card)
		_:
			draw_pile.append(card)
	return card


func shuffle_draw_pile() -> void:
	var n := draw_pile.size()
	for i in range(n - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = tmp


func reshuffle_discard_into_draw() -> int:
	if discard_pile.is_empty():
		return 0
	var count := discard_pile.size()
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	shuffle_draw_pile()
	deck_reshuffled.emit(count)
	return count


func draw(count: int = 1) -> Array[Dictionary]:
	var drawn: Array[Dictionary] = []
	for _i in range(count):
		if hand.size() >= max_hand_size:
			break
		if draw_pile.is_empty():
			if reshuffle_discard_into_draw() == 0:
				break
		var c: Dictionary = draw_pile.pop_back()
		hand.append(c)
		drawn.append(c)
		card_drawn.emit(c)
	return drawn


func play_card(uid: String, exhaust: bool = false) -> Dictionary:
	for i in range(hand.size()):
		if str(hand[i].get("uid", "")) == uid:
			var c: Dictionary = hand[i]
			hand.remove_at(i)
			if exhaust or bool(c.get("exhaust", false)):
				exhaust_pile.append(c)
				card_exhausted.emit(c)
			else:
				discard_pile.append(c)
			card_played.emit(c)
			return c
	return {}


func discard_card(uid: String) -> bool:
	for i in range(hand.size()):
		if str(hand[i].get("uid", "")) == uid:
			var c: Dictionary = hand[i]
			hand.remove_at(i)
			discard_pile.append(c)
			card_discarded.emit(c)
			return true
	return false


func discard_hand() -> int:
	var count := hand.size()
	while not hand.is_empty():
		var c: Dictionary = hand.pop_back()
		discard_pile.append(c)
		card_discarded.emit(c)
	return count


func peek_top(count: int = 3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := mini(count, draw_pile.size())
	for i in range(n):
		out.append(draw_pile[draw_pile.size() - 1 - i])
	return out


func serialize() -> Dictionary:
	return {
		"max_hand_size": max_hand_size,
		"draw_pile": draw_pile.duplicate(true),
		"hand": hand.duplicate(true),
		"discard_pile": discard_pile.duplicate(true),
		"exhaust_pile": exhaust_pile.duplicate(true),
	}


func deserialize(data: Dictionary) -> void:
	max_hand_size = int(data.get("max_hand_size", 10))
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	for c in data.get("draw_pile", []): draw_pile.append(c)
	for c in data.get("hand", []): hand.append(c)
	for c in data.get("discard_pile", []): discard_pile.append(c)
	for c in data.get("exhaust_pile", []): exhaust_pile.append(c)
