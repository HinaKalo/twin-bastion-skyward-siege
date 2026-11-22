class_name PixelVFX
extends RefCounted
## Zero-Asset Procedural Pixel-Art VFX Toolkit.
## Provides instant tactile visual polish even without external VFX spritesheets:
## - `spawn_slash_arc`: Crisp crescent sword slash arc
## - `spawn_burst`: Gravity-affected pixel spark / dust burst
## - `spawn_ambient_motes`: Gently floating fireflies / dust motes across a world Rect2


class _SlashArcNode extends Node2D:
	var facing: float = 1.0
	var radius: float = 34.0
	var color: Color = Color(1.0, 0.85, 0.45)
	var duration: float = 0.14
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var age := clampf(_t / maxf(0.001, duration), 0.0, 1.0)
		var base_ang := 0.0 if facing >= 0.0 else PI
		var r := radius * (0.84 + age * 0.20)
		var a0 := base_ang - 0.85 + age * 0.22
		var a1 := base_ang + 0.72 + age * 0.22
		draw_arc(Vector2.ZERO, r, a0, a1, 14, Color(color.r, color.g, color.b, 1.0 - age), 4.0)
		draw_arc(Vector2.ZERO, r - 2.5, a0, a1, 14, Color(1.0, 0.96, 0.82, 1.0 - age), 2.0)


class _BurstNode extends Node2D:
	var particles: Array[Dictionary] = []

	func _process(delta: float) -> void:
		for i in range(particles.size() - 1, -1, -1):
			var p: Dictionary = particles[i]
			p["life"] = float(p["life"]) - delta
			if float(p["life"]) <= 0.0:
				particles.remove_at(i)
				continue
			p["vy"] = float(p["vy"]) + 340.0 * delta
			p["x"] = float(p["x"]) + float(p["vx"]) * delta
			p["y"] = float(p["y"]) + float(p["vy"]) * delta
		if particles.is_empty():
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		for p in particles:
			var col: Color = p["color"]
			var a := clampf(float(p["life"]) * 4.0, 0.0, 1.0)
			draw_rect(Rect2(float(p["x"]), float(p["y"]), 3.0, 3.0), Color(col.r, col.g, col.b, a))


class _AmbientMotesNode extends Node2D:
	var motes: Array[Dictionary] = []
	var color: Color = Color(1.0, 0.92, 0.58, 0.45)
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		for m in motes:
			var ph := float(m["phase"])
			var spd := float(m["speed"])
			var ox := sin(_t * spd * 0.7 + ph) * 8.0
			var oy := cos(_t * spd + ph) * 10.0
			var a := color.a * (0.45 + 0.55 * (0.5 + 0.5 * sin(_t * spd * 1.4 + ph)))
			draw_rect(Rect2(float(m["x"]) + ox, float(m["y"]) + oy, 2.5, 2.5), Color(color.r, color.g, color.b, a))


static func spawn_slash_arc(parent: Node, pos: Vector2, facing: float = 1.0, radius: float = 34.0, color: Color = Color(1.0, 0.85, 0.45)) -> Node2D:
	var n := _SlashArcNode.new()
	n.position = pos
	n.facing = facing
	n.radius = radius
	n.color = color
	n.z_index = 18
	if parent != null:
		parent.add_child(n)
	return n


static func spawn_burst(parent: Node, pos: Vector2, color: Color = Color(1.0, 0.88, 0.45), count: int = 10) -> Node2D:
	var n := _BurstNode.new()
	n.position = pos
	n.z_index = 18
	for _i in range(count):
		n.particles.append({
			"x": 0.0, "y": 0.0,
			"vx": randf_range(-110.0, 110.0),
			"vy": randf_range(-150.0, -25.0),
			"life": randf_range(0.18, 0.42),
			"color": color,
		})
	if parent != null:
		parent.add_child(n)
	return n


static func spawn_ambient_motes(parent: Node, bounds: Rect2, count: int = 24, color: Color = Color(1.0, 0.92, 0.58, 0.48)) -> Node2D:
	var n := _AmbientMotesNode.new()
	n.color = color
	n.z_index = 12
	for _i in range(count):
		n.motes.append({
			"x": randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
			"y": randf_range(bounds.position.y, bounds.position.y + bounds.size.y),
			"phase": randf_range(0.0, TAU),
			"speed": randf_range(0.8, 1.8),
		})
	if parent != null:
		parent.add_child(n)
	return n
