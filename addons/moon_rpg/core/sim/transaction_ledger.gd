class_name TransactionLedger
extends RefCounted
## Idempotent settlement ledger.
##
## Every economy / reward / card-pick request carries a stable `request_id`
## (e.g. "seat2:card_pick:elite_07:draw3"). Applying the same id again — a network resend,
## a reconnect replay, a double click — returns the stored result without re-running the effect,
## so nothing is double-charged, double-granted or double-occupied. The ledger serializes into
## the save so idempotency survives restarts.

signal applied(request_id: String, result: Variant)

var _done: Dictionary = {}      # request_id -> { result, tick, kind }
var _pending: Dictionary = {}   # request_id -> { kind, payload, since }
var max_history: int = 4096
var _order: Array[String] = []


## Declares an in-flight request (e.g. two players picking cards at once, awaiting commit).
func begin(request_id: String, kind: String = "", payload: Dictionary = {}, tick: int = 0) -> bool:
	if _done.has(request_id) or _pending.has(request_id):
		return false
	_pending[request_id] = {"kind": kind, "payload": payload.duplicate(true), "since": tick}
	return true


## Runs `effect` exactly once per request id; later calls return the first result.
## Returns { ok, duplicate, result }.
func apply(request_id: String, effect: Callable, kind: String = "", tick: int = 0) -> Dictionary:
	if request_id.is_empty():
		return {"ok": false, "duplicate": false, "result": null, "error": "empty_request_id"}
	if _done.has(request_id):
		return {"ok": true, "duplicate": true, "result": _done[request_id]["result"]}
	var result: Variant = effect.call() if effect.is_valid() else null
	_done[request_id] = {"result": result, "tick": tick, "kind": kind}
	_pending.erase(request_id)
	_order.append(request_id)
	if _order.size() > max_history:
		var old: String = _order.pop_front()
		_done.erase(old)
	applied.emit(request_id, result)
	return {"ok": true, "duplicate": false, "result": result}


func cancel(request_id: String) -> void:
	_pending.erase(request_id)


func is_applied(request_id: String) -> bool:
	return _done.has(request_id)


func result_of(request_id: String) -> Variant:
	return _done.get(request_id, {}).get("result", null)


func pending() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rid in _pending.keys():
		var p: Dictionary = (_pending[rid] as Dictionary).duplicate(true)
		p["request_id"] = rid
		out.append(p)
	return out


func serialize() -> Dictionary:
	return {"done": _done.duplicate(true), "pending": _pending.duplicate(true), "order": _order.duplicate()}


func deserialize(data: Dictionary) -> void:
	_done = (data.get("done", {}) as Dictionary).duplicate(true)
	_pending = (data.get("pending", {}) as Dictionary).duplicate(true)
	_order.clear()
	for rid in data.get("order", _done.keys()):
		_order.append(str(rid))
