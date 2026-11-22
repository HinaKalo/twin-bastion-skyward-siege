extends Node
## Unified Script & Formula Extension Bridge.
## Defaults to Godot's built-in Expression evaluator + GDScript hook registry.
## Designed with a pluggable ScriptBackend interface so Lua (via lua-gdextension)
## can be attached later without modifying any engine subsystem.


class ScriptBackend extends RefCounted:
	func get_backend_name() -> String:
		return "base"

	func eval_formula(_expr: String, _context: Dictionary) -> float:
		return 0.0

	func eval_condition(_expr: String, _context: Dictionary) -> bool:
		return false

	func invoke_hook(_hook_name: String, _payload: Dictionary) -> Variant:
		return null


class BuiltinExpressionBackend extends ScriptBackend:
	var _hooks: Dictionary = {}

	func get_backend_name() -> String:
		return "gdscript_expression"

	func register_hook(hook_name: String, callable: Callable) -> void:
		_hooks[hook_name] = callable

	func unregister_hook(hook_name: String) -> void:
		_hooks.erase(hook_name)

	func has_hook(hook_name: String) -> bool:
		return _hooks.has(hook_name)

	func eval_formula(expr: String, context: Dictionary) -> float:
		var trimmed := expr.strip_edges()
		if trimmed.is_empty():
			return 0.0
		var result: Variant = _eval_raw(trimmed, context)
		if typeof(result) == TYPE_INT or typeof(result) == TYPE_FLOAT:
			return float(result)
		return 0.0

	func eval_condition(expr: String, context: Dictionary) -> bool:
		var trimmed := expr.strip_edges()
		if trimmed.is_empty():
			return true
		var result: Variant = _eval_raw(trimmed, context)
		return true if result else false

	func invoke_hook(hook_name: String, payload: Dictionary) -> Variant:
		if _hooks.has(hook_name):
			var cb: Callable = _hooks[hook_name]
			if cb.is_valid():
				return cb.call(payload)
		return null

	func _eval_raw(expr_text: String, context: Dictionary) -> Variant:
		var expression := Expression.new()
		var resolved_ctx := context.duplicate()
		# Auto-default unset blackboard/flag/quest identifiers so story conditions
		# like `tag_spared_boss and flag_forest_cleared` cleanly evaluate to false.
		var rx := RegEx.new()
		rx.compile("\\b((?:tag|flag|bb|choice|arc|quest)_[A-Za-z0-9_]+)\\b")
		for m in rx.search_all(expr_text):
			var ident := m.get_string(1)
			if not resolved_ctx.has(ident):
				if ident.begins_with("tag_") or ident.begins_with("flag_"):
					resolved_ctx[ident] = false
				elif ident.begins_with("choice_") or ident.begins_with("arc_"):
					resolved_ctx[ident] = ""
				else:
					resolved_ctx[ident] = 0

		var keys := PackedStringArray()
		var values: Array = []
		for k in resolved_ctx.keys():
			keys.append(str(k))
			values.append(resolved_ctx[k])
		var err := expression.parse(expr_text, keys)
		if err != OK:
			push_warning("[ScriptBridge] Expression parse error (%s): %s" % [expression.get_error_text(), expr_text])
			return null
		var result: Variant = expression.execute(values, null, false)
		if expression.has_execute_failed():
			push_warning("[ScriptBridge] Expression execute error (%s): %s" % [expression.get_error_text(), expr_text])
			return null
		return result


## Optional stub showing the exact contract for plugging in lua-gdextension later.
class LuaBackendStub extends ScriptBackend:
	var _lua_state: Object = null

	func _init(lua_state: Object = null) -> void:
		_lua_state = lua_state

	func get_backend_name() -> String:
		return "lua_gdextension"

	func eval_formula(expr: String, context: Dictionary) -> float:
		if _lua_state == null:
			push_warning("[ScriptBridge] Lua state not attached; cannot evaluate formula: %s" % expr)
			return 0.0
		# Example integration when lua-gdextension is installed:
		# _lua_state.set_globals(context)
		# return float(_lua_state.do_string("return " + expr))
		return 0.0

	func eval_condition(expr: String, context: Dictionary) -> bool:
		if _lua_state == null:
			return false
		return bool(eval_formula(expr, context))

	func invoke_hook(hook_name: String, payload: Dictionary) -> Variant:
		if _lua_state == null:
			return null
		return _lua_state.call("invoke_hook", hook_name, payload)


var _backend: ScriptBackend = BuiltinExpressionBackend.new()
var _builtin_hooks: BuiltinExpressionBackend = _backend as BuiltinExpressionBackend


func set_backend(backend: ScriptBackend) -> void:
	if backend != null:
		_backend = backend


func get_backend() -> ScriptBackend:
	return _backend


func get_backend_name() -> String:
	return _backend.get_backend_name()


func register_hook(hook_name: String, callable: Callable) -> void:
	_builtin_hooks.register_hook(hook_name, callable)


func unregister_hook(hook_name: String) -> void:
	_builtin_hooks.unregister_hook(hook_name)


func eval_formula(expr: String, context: Dictionary = {}) -> float:
	return _backend.eval_formula(expr, context)


func eval_condition(expr: String, context: Dictionary = {}) -> bool:
	return _backend.eval_condition(expr, context)


func invoke_hook(hook_name: String, payload: Dictionary = {}) -> Variant:
	if _builtin_hooks.has_hook(hook_name):
		return _builtin_hooks.invoke_hook(hook_name, payload)
	return _backend.invoke_hook(hook_name, payload)
