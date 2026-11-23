extends Camera3D
## Third-person chase camera that trails the rider's direction of travel.
## The faster you go, the closer and lower it tucks in behind the rider.

# Framing at a standstill...
const DIST_SLOW := 5.2
const HEIGHT_SLOW := 4.5
const FOV_SLOW := 68.0
# ...and at top speed.
const DIST_FAST := 3.8
const HEIGHT_FAST := 3.6
const FOV_FAST := 74.0
const FAST_SPEED := 40.0   # m/s (~145 km/h) where the fast framing is fully reached

# Where the camera aims: a point down the slope in front of the rider, so the
# rider sits in the lower part of the screen and you can see what's coming.
const LOOK_AHEAD_SLOW := 10.0   # metres in front of the rider
const LOOK_AHEAD_FAST := 14.0   # look further ahead at speed
const LOOK_GROUND_BLEND := 0.7  # 0 = aim at rider height, 1 = aim at the snow ahead
const LOOK_LIFT := 0.6          # aim this far above the snow
const INTRO_SWEEP := TAU * 1.3  # how far the camera circles the rider in the stage intro

var target: Node3D
var course: Node3D
var _dir := Vector3(0, 0, -1)
var _shake := 0.0
var _zoom := 0.0   # 0 = slow framing, 1 = fast framing (smoothed)
var _offset := Vector3.ZERO   # smoothed camera position relative to the rider
var _look := Vector3.ZERO     # smoothed aim point (stops bumps in the snow jittering the view)
## Stage intro: 0..1 sweeps around the rider and settles exactly on the chase view. -1 = off.
var intro_progress := -1.0


func _ready() -> void:
	process_priority = 10  # run after the player has moved


func snap() -> void:
	_dir = Vector3(-sin(target.yaw), 0.0, -cos(target.yaw))
	_zoom = 0.0
	global_position = _desired()
	_offset = global_position - target.global_position
	_look = _look_point()
	look_at(_look, Vector3.UP)
	fov = FOV_SLOW


func end_intro() -> void:
	intro_progress = -1.0
	_offset = _desired() - target.global_position
	_look = _look_point()
	global_position = target.global_position + _offset
	look_at(_look, Vector3.UP)


## Close and low at first, circling the rider, then rising into the normal chase position.
func _apply_intro() -> void:
	var p := clampf(intro_progress, 0.0, 1.0)
	var sweep := 1.0 - pow(1.0 - p, 1.7)
	var settle := smoothstep(0.5, 1.0, p)
	var chase := _desired() - target.global_position
	var chase_h := Vector2(chase.x, chase.z).length()
	var radius := lerpf(4.2, chase_h, settle)
	var height := lerpf(1.25, chase.y, settle)
	var around := (-_dir).rotated(Vector3.UP, -INTRO_SWEEP * (1.0 - sweep))
	var pos: Vector3 = target.global_position + around * radius + Vector3.UP * height
	pos.y = maxf(pos.y, course.height(pos.x, pos.z) + 0.6)
	global_position = pos
	var chest: Vector3 = target.global_position + Vector3.UP * 0.95
	look_at(chest.lerp(_look_point(), settle), Vector3.UP)
	fov = lerpf(50.0, lerpf(FOV_SLOW, FOV_FAST, _zoom), settle)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _desired() -> Vector3:
	var dist := lerpf(DIST_SLOW, DIST_FAST, _zoom)
	var height := lerpf(HEIGHT_SLOW, HEIGHT_FAST, _zoom)
	var p := target.global_position - _dir * dist + Vector3.UP * height
	p.y = maxf(p.y, course.height(p.x, p.z) + 1.0)
	return p


func _look_point() -> Vector3:
	# Aim well ahead of the rider, following the slope down, so the camera
	# looks over the rider's head at the run in front of them.
	var p := target.global_position + _dir * lerpf(LOOK_AHEAD_SLOW, LOOK_AHEAD_FAST, _zoom)
	var ground_y: float = course.height(p.x, p.z) + LOOK_LIFT
	var rider_y: float = target.global_position.y + 0.8
	p.y = lerpf(rider_y, ground_y, LOOK_GROUND_BLEND)
	return p


func _process(delta: float) -> void:
	if target == null:
		return
	var v: Vector3 = target.vel
	var hv := Vector3(v.x, 0.0, v.z)
	var want := _dir
	if hv.length() > 2.0:
		want = hv.normalized()
	_dir = _dir.lerp(want, 1.0 - exp(-3.0 * delta)).normalized()

	# Ease the zoom so it glides in as you pick up speed and back out when you slow.
	var spd: float = target.speed
	var target_zoom := smoothstep(6.0, FAST_SPEED, spd)
	_zoom = lerpf(_zoom, target_zoom, 1.0 - exp(-2.0 * delta))

	# Smooth the offset from the rider (not the world position), so going faster
	# doesn't make the camera fall further behind.
	var want_offset := _desired() - target.global_position
	_offset = _offset.lerp(want_offset, 1.0 - exp(-8.0 * delta))
	global_position = target.global_position + _offset
	var floor_y: float = course.height(global_position.x, global_position.z) + 1.0
	global_position.y = maxf(global_position.y, floor_y)
	if _look == Vector3.ZERO:
		_look = _look_point()
	_look = _look.lerp(_look_point(), 1.0 - exp(-10.0 * delta))
	look_at(_look, Vector3.UP)
	fov = lerpf(fov, lerpf(FOV_SLOW, FOV_FAST, _zoom), 1.0 - exp(-3.0 * delta))
	if intro_progress >= 0.0:
		_apply_intro()
	_shake = maxf(_shake - delta, 0.0)
	h_offset = randf_range(-1.0, 1.0) * _shake * 0.4
	v_offset = randf_range(-1.0, 1.0) * _shake * 0.4
