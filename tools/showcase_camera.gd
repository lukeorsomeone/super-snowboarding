extends Camera3D
## Dev tool: a close-up camera for store-page shots. It rides just ahead of the rider and
## off to their chest side, looking back at them, so you see their face and every trick.
## Turned on by `-- --autopilot --showcam[=ahead,side,height]` (see game.gd).

var target: Node3D
var course: Node3D
var ahead := 3.0    # metres in front of the rider (along their direction of travel)
var side := 2.0     # metres out to the side the rider faces (+ = their chest side)
var height := 1.1   # metres above the rider's feet

var _dir := Vector3(0, 0, -1)
var _base_y := 0.0
var _started := false


func _ready() -> void:
	process_priority = 20   # after the player and the chase camera have moved
	fov = 55.0


func _process(delta: float) -> void:
	if target == null:
		return
	var v: Vector3 = target.vel
	var hv := Vector3(v.x, 0.0, v.z)
	if hv.length() > 2.0:
		_dir = _dir.lerp(hv.normalized(), 1.0 - exp(-4.0 * delta)).normalized()
	var p: Vector3 = target.global_position
	# Follow the rider's height with a little lag, so a jump rises up through the frame
	# but long drops never leave the camera hanging high above them.
	if not _started:
		_base_y = p.y
		_started = true
	_base_y = minf(lerpf(_base_y, p.y, 1.0 - exp(-5.0 * delta)), p.y)   # lag going up only
	var right := Vector3(-_dir.z, 0.0, _dir.x)
	var pos := p + _dir * ahead + right * side
	pos.y = _base_y + height
	pos.y = maxf(pos.y, course.height(pos.x, pos.z) + 0.5)
	global_position = pos
	look_at(p + Vector3.UP * 0.85, Vector3.UP)
