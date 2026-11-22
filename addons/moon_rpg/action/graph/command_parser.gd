class_name CommandParser
extends RefCounted
## Motion-command parser (ported from Tideforge `combo.gd`).
##
## Quarter-circle forward (down -> down+side -> side) on either side:
## - neutral down opens a `window_frames` (22) window
## - down + side inside the window records the side
## - releasing down while holding that side arms the command for `ready_frames` (9)
## Skipping the diagonal, or letting the armed state lapse, falls back to the plain move.
## `up + heavy` (without down) reports the "launcher" command.

var window_frames: int = 22
var ready_frames: int = 9
var leniency_frames: int = 0

var cmd_window: int = 0
var cmd_side: int = 0
var cmd_ready: int = 0
var ready_side: int = 0


func feed(dir: Vector2i) -> void:
	if cmd_window > 0:
		cmd_window -= 1
	if cmd_ready > 0:
		cmd_ready -= 1
	if dir.y > 0 and dir.x == 0:
		cmd_window = window_frames + leniency_frames
		cmd_side = 0
	elif dir.y > 0 and dir.x != 0 and cmd_window > 0:
		cmd_side = dir.x
	elif dir.y <= 0 and dir.x != 0 and cmd_side != 0 and dir.x == cmd_side and cmd_window > 0:
		cmd_ready = ready_frames + leniency_frames
		ready_side = cmd_side
		cmd_window = 0
		cmd_side = 0


## Command available for a press made with stick `dir`. Returns "qcf", "launcher" or "".
func command_for(dir: Vector2i) -> String:
	if cmd_ready > 0 and (dir.x == 0 or dir.x == ready_side):
		return "qcf"
	if dir.y < 0:
		return "launcher"
	return ""


func consume() -> void:
	cmd_ready = 0
	cmd_window = 0
	cmd_side = 0


func reset() -> void:
	consume()
	ready_side = 0
