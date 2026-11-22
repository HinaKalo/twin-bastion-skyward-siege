class_name TDPathLane
extends RefCounted
## Arc-Length Parameterized Waypoint Lane for Tower Defense games.
## Ensures creeps move at exact constant speed along arbitrary polyline routes
## and allows O(1) comparison of creep progress (`0.0` start -> `1.0` base goal).

var lane_id: String = "lane_1"
var waypoints: PackedVector2Array = PackedVector2Array()
var _cum_lengths: PackedFloat32Array = PackedFloat32Array()
var total_length: float = 0.0


func setup(id: String, points: Array) -> void:
	lane_id = id
	waypoints = PackedVector2Array()
	_cum_lengths = PackedFloat32Array()
	total_length = 0.0
	for p in points:
		if p is Vector2:
			waypoints.append(p)
		elif typeof(p) == TYPE_ARRAY and p.size() >= 2:
			waypoints.append(Vector2(float(p[0]), float(p[1])))
	if waypoints.is_empty():
		return
	_cum_lengths.append(0.0)
	for i in range(1, waypoints.size()):
		total_length += waypoints[i - 1].distance_to(waypoints[i])
		_cum_lengths.append(total_length)


func get_point_at_progress(progress: float) -> Vector2:
	if waypoints.is_empty():
		return Vector2.ZERO
	if waypoints.size() == 1 or total_length <= 0.001:
		return waypoints[0]
	var target_dist := clampf(progress, 0.0, 1.0) * total_length
	for i in range(1, _cum_lengths.size()):
		if target_dist <= _cum_lengths[i] or i == _cum_lengths.size() - 1:
			var seg_start := _cum_lengths[i - 1]
			var seg_len := maxf(0.0001, _cum_lengths[i] - seg_start)
			var local_t := clampf((target_dist - seg_start) / seg_len, 0.0, 1.0)
			return waypoints[i - 1].lerp(waypoints[i], local_t)
	return waypoints[waypoints.size() - 1]


func advance_progress(current_progress: float, speed_px_per_sec: float, delta: float) -> float:
	if total_length <= 0.001:
		return 1.0
	return clampf(current_progress + (speed_px_per_sec * delta) / total_length, 0.0, 1.0)
