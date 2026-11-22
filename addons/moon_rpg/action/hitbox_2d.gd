class_name Hitbox2D
extends Area2D
## Frame-driven melee/skill attack Hitbox.
## Deduplicates hits per activation window, delivers structured payload to Hurtbox2D,
## and emits `hit_landed` so the attacker can trigger Pogo bounce, Rally heal, or recoil.

signal hit_landed(hurtbox: Hurtbox2D, payload: Dictionary)

var owner_actor: Node = null
var active_payload: Dictionary = {}
var _hit_targets: Dictionary = {}
var _shape: CollisionShape2D = null


func _ready() -> void:
	monitoring = false
	monitorable = false
	area_entered.connect(_on_area_entered)
	_ensure_shape()


func _ensure_shape() -> void:
	_shape = get_node_or_null("CollisionShape2D")
	if _shape == null:
		_shape = CollisionShape2D.new()
		_shape.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = Vector2(36, 32)
		_shape.shape = rect
		add_child(_shape)


func activate(payload: Dictionary, box_size: Vector2 = Vector2(38, 32), offset: Vector2 = Vector2(26, -24)) -> void:
	_ensure_shape()
	active_payload = payload
	_hit_targets.clear()
	if _shape.shape is RectangleShape2D:
		(_shape.shape as RectangleShape2D).size = box_size
	position = offset
	monitoring = true
	queue_redraw()


func deactivate() -> void:
	monitoring = false
	_hit_targets.clear()
	queue_redraw()


func _draw() -> void:
	if not monitoring or MoonRPG == null or not MoonRPG.debug_hitboxes:
		return
	if _shape != null and _shape.shape is RectangleShape2D:
		var sz := (_shape.shape as RectangleShape2D).size
		var rect := Rect2(-sz * 0.5, sz)
		draw_rect(rect, Color(1.0, 0.2, 0.2, 0.32), true)
		draw_rect(rect, Color(1.0, 0.3, 0.3, 0.9), false, 1.0)


func _on_area_entered(area: Area2D) -> void:
	if not monitoring:
		return
	if not (area is Hurtbox2D):
		return
	var hurtbox := area as Hurtbox2D
	if hurtbox.owner_actor == owner_actor:
		return
	var tid := hurtbox.get_instance_id()
	if _hit_targets.has(tid):
		return
	_hit_targets[tid] = true
	var payload := active_payload.duplicate(true)
	payload["attacker"] = owner_actor
	payload["hit_pos"] = hurtbox.global_position + Vector2(0, -16)
	hurtbox.receive_hit(payload)
	hit_landed.emit(hurtbox, payload)
