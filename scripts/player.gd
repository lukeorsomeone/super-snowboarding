extends Node3D
## Arcade snowboarder. Rides the course's analytic height field kinematically:
## gravity pulls along the slope, the board's edge grip kills sideways sliding (carving),
## and dropping off a ramp lip launches you into the air.

signal crashed
## flips: full flips completed (+ = backflips, - = frontflips)
signal landed(air_time: float, half_spins: int, flips: int)
## An item stopped a crash.
signal saved(item_name: String)

const MeshUtil := preload("res://scripts/mesh_util.gd")
const Riders := preload("res://scripts/riders.gd")

const GRAVITY := 24.0
const MAX_SPEED := 46.0
const JUMP_SPEED := 7.5
const AIR_SPIN_RATE := 6.5
const FLIP_RATE := 6.8          # rad/s while holding tuck (front flip) or brake (back flip) in the air
const FLIP_ASSIST := 3.5        # with no flip input, ease towards upright at this rate...
const FLIP_ASSIST_RANGE := 1.3  # ...if within this many radians of it
const FLIP_LAND_LIMIT := 0.75   # land further off upright than this and you wipe out
const FLIP_PIVOT := Vector3(0.0, 0.9, 0.0)   # flips turn around the rider's middle, not the feet

var course: Node3D
var air_gravity := GRAVITY       # lower on the moon, for long floaty jumps
# Set from the run's items by apply_run().
var max_speed := MAX_SPEED
var turn_mult := 1.0
var jump_speed := JUMP_SPEED
var spin_rate := AIR_SPIN_RATE
var flip_rate := FLIP_RATE
var flip_land_limit := FLIP_LAND_LIMIT
var spin_land_limit := 0.9
var hit_scale := 1.0
var safe_time := 1.5
var shields := 0
var phase_item := false
var phase_cooldown := 0.0
var controls_enabled := false
var frozen := true
var auto_brake := false
var scripted := false           # the stage intro is steering the rider (see ride_to)

var vel := Vector3.ZERO
var yaw := 0.0
var speed := 0.0
var grounded := true
var air_time := 0.0
var spin_accum := 0.0
var flip_accum := 0.0           # total flip rotation this jump (+ = backwards)
var launched_from_ramp := false # flips (front and back) are only allowed off a ramp
var crash_timer := 0.0
var ghost_timer := 0.0

var _model: Node3D
var _rider: Node3D
var _spray: CPUParticles3D
var _blob: MeshInstance3D
var _anim: AnimationPlayer
var _carve_sfx: AudioStreamPlayer
var _wind_sfx: AudioStreamPlayer
var _carve_level := 0.0
var _wind_level := 0.0
var _steer := 0.0
var _tuck := false
var _brake := false
var _skid := 0.0
var _lean := 0.0
var _crouch := 0.0
var _pitch := 0.0
var _tumble := 0.0


func _ready() -> void:
	_build_model()
	_build_audio()


# ---------------------------------------------------------------- audio

func _build_audio() -> void:
	# Both loops play constantly; their volume and pitch follow the ride.
	_carve_sfx = AudioStreamPlayer.new()
	_carve_sfx.stream = load("res://assets/sfx/snowboard.wav")  # loops (set in its import settings)
	_carve_sfx.volume_db = -80.0
	_carve_sfx.bus = "SFX"
	add_child(_carve_sfx)
	_carve_sfx.play()

	var wind: AudioStreamMP3 = load("res://assets/sfx/wind.mp3")
	wind.loop = true
	_wind_sfx = AudioStreamPlayer.new()
	_wind_sfx.stream = wind
	_wind_sfx.volume_db = -80.0
	_wind_sfx.bus = "SFX"
	add_child(_wind_sfx)
	_wind_sfx.play()


func _update_audio(dt: float) -> void:
	var k := 1.0 - exp(-10.0 * dt)
	# Board on snow: louder and grittier with speed and sideways skidding, silent in the air.
	var on_snow := grounded and crash_timer <= 0.0 and not frozen
	var carve_target := 0.0
	if on_snow:
		carve_target = clampf(speed / 30.0, 0.0, 1.0) * 0.8 + clampf(_skid / 12.0, 0.0, 0.4)
		if _brake:
			carve_target += 0.25
	_carve_level = lerpf(_carve_level, clampf(carve_target, 0.0, 1.0), k)
	_carve_sfx.volume_db = linear_to_db(maxf(_carve_level, 0.0001)) - 2.0
	_carve_sfx.pitch_scale = clampf(0.85 + speed / 80.0 + _skid / 40.0, 0.7, 1.5)

	# Wind: builds with speed, gusts up while airborne.
	var wind_target := pow(clampf(speed / 45.0, 0.0, 1.0), 1.5)
	if not grounded and crash_timer <= 0.0:
		wind_target += 0.3
	if frozen:
		wind_target = 0.08
	_wind_level = lerpf(_wind_level, clampf(wind_target, 0.0, 1.0), 1.0 - exp(-4.0 * dt))
	_wind_sfx.volume_db = linear_to_db(maxf(_wind_level, 0.0001)) - 4.0
	_wind_sfx.pitch_scale = clampf(0.9 + speed / 120.0, 0.8, 1.3)


## Applies the run's items. Called at the start of each stage, which recharges them.
func apply_run(run: RefCounted, level_gravity: float) -> void:
	max_speed = MAX_SPEED * (1.1 if run.has("wax") else 1.0)
	turn_mult = 1.2 if run.has("bindings") else 1.0
	jump_speed = JUMP_SPEED * (1.3 if run.has("boots") else 1.0)
	spin_rate = AIR_SPIN_RATE * (1.25 if run.has("spin") else 1.0)
	flip_rate = FLIP_RATE * (1.2 if run.has("flip") else 1.0)
	flip_land_limit = FLIP_LAND_LIMIT + (0.4 if run.has("soft") else 0.0)
	spin_land_limit = 0.9 + (0.4 if run.has("soft") else 0.0)
	hit_scale = 0.75 if run.has("slim") else 1.0
	safe_time = 3.0 if run.has("wind") else 1.5
	air_gravity = GRAVITY * level_gravity * (0.8 if run.has("feather") else 1.0)
	shields = 1 if run.has("socks") else 0
	phase_item = run.has("ghost")
	phase_cooldown = 0.0


func place(at: Vector3, facing: float) -> void:
	position = at
	yaw = facing
	vel = Vector3.ZERO
	speed = 0.0
	grounded = true
	air_time = 0.0
	spin_accum = 0.0
	flip_accum = 0.0
	crash_timer = 0.0
	ghost_timer = 0.0
	_tumble = 0.0
	frozen = true
	scripted = false
	controls_enabled = false
	auto_brake = false
	rotation = Vector3(0, yaw, 0)


## Stage intro: carves the rider along a set path, with the normal riding visuals and sound.
func ride_to(at: Vector3, facing: float, spd: float, steer: float) -> void:
	frozen = false
	scripted = true
	position = at
	yaw = facing
	var hv := _forward() * spd
	vel = Vector3(hv.x, _follow_rate(hv), hv.z)
	speed = spd
	grounded = true
	_steer = steer
	_tuck = false
	_brake = false
	_skid = absf(steer) * 3.0


func push(amount: float) -> void:
	var fwd := _forward()
	vel.x += fwd.x * amount
	vel.z += fwd.z * amount


func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _process(delta: float) -> void:
	if course == null:
		return
	var dt := minf(delta, 1.0 / 30.0)
	if not frozen and not scripted:
		if crash_timer > 0.0:
			_update_crash(dt)
		else:
			_simulate(dt)
	rotation.y = yaw
	_animate(dt)
	_update_audio(dt)


# ---------------------------------------------------------------- movement

func _simulate(dt: float) -> void:
	_steer = 0.0
	_tuck = false
	_brake = auto_brake
	if controls_enabled:
		_steer = Input.get_axis("steer_right", "steer_left")
		_tuck = Input.is_action_pressed("tuck")
		_brake = Input.is_action_pressed("brake")
		if grounded and Input.is_action_just_pressed("jump"):
			vel.y += jump_speed
			grounded = false
			air_time = 0.0
			spin_accum = 0.0
			flip_accum = 0.0
			launched_from_ramp = _on_ramp()

	if grounded:
		_ground_step(dt)
	else:
		_air_step(dt)
	ghost_timer = maxf(ghost_timer - dt, 0.0)
	phase_cooldown = maxf(phase_cooldown - dt, 0.0)
	_check_bounds()
	_check_obstacles()
	speed = Vector2(vel.x, vel.z).length()


func _ground_step(dt: float) -> void:
	var hv := Vector3(vel.x, 0.0, vel.z)
	var turn_rate := lerpf(2.6, 1.5, clampf(hv.length() / MAX_SPEED, 0.0, 1.0)) * turn_mult
	yaw = wrapf(yaw + _steer * turn_rate * dt, -PI, PI)
	var fwd := _forward()
	var right := Vector3(-fwd.z, 0.0, fwd.x)

	var grad: Vector2 = course.gradient(position.x, position.z)
	hv += Vector3(-grad.x, 0.0, -grad.y) * GRAVITY * dt

	var vf := hv.dot(fwd)
	var vs := hv.dot(right)
	var grip := 2.5 if _brake else 7.0
	var new_vs := vs * exp(-grip * dt)
	var scrubbed := absf(vs) - absf(new_vs)
	vf += signf(vf) * scrubbed * (0.15 if _brake else 0.55)
	var drag := 0.0016 if _tuck else 0.003
	var decel := (drag * vf * vf + 0.5) * dt
	if _brake:
		decel += absf(vf) * 1.6 * dt
	vf = clampf(move_toward(vf, 0.0, decel), -max_speed, max_speed)
	_skid = absf(vs)
	hv = fwd * vf + right * new_vs

	var nx := position.x + hv.x * dt
	var nz := position.z + hv.z * dt
	var nh: float = course.height(nx, nz)
	var follow := (nh - position.y) / dt
	var ballistic := vel.y - GRAVITY * dt
	if follow < ballistic - 0.5:
		# The ground drops away faster than gravity can pull us down: we're airborne.
		launched_from_ramp = _on_ramp()   # check before moving off the lip
		grounded = false
		air_time = 0.0
		spin_accum = 0.0
		flip_accum = 0.0
		vel = Vector3(hv.x, vel.y - air_gravity * dt, hv.z)
		position = Vector3(nx, position.y + vel.y * dt, nz)
	else:
		vel = Vector3(hv.x, follow, hv.z)
		position = Vector3(nx, nh, nz)


func _air_step(dt: float) -> void:
	air_time += dt
	var spin := _steer * spin_rate * dt
	yaw += spin
	spin_accum += spin
	# Flips: hold tuck to flip forwards, brake to flip backwards.
	var flip_in := 0.0
	if controls_enabled:
		flip_in = Input.get_axis("tuck", "brake")
		if not launched_from_ramp:
			flip_in = 0.0   # no flips from a flat-ground jump
	if flip_in != 0.0:
		flip_accum += flip_in * flip_rate * dt
	else:
		# Let go and you straighten up if you're close to upright (keeps landings fair).
		var off := wrapf(flip_accum, -PI, PI)
		if absf(off) < FLIP_ASSIST_RANGE:
			flip_accum -= signf(off) * minf(absf(off), FLIP_ASSIST * dt)
	vel.y -= air_gravity * dt
	position += vel * dt
	var gh: float = course.height(position.x, position.z)
	if position.y <= gh:
		position.y = gh
		_land()


func _land() -> void:
	grounded = true
	var hv := Vector3(vel.x, 0.0, vel.z)
	var half_spins := int(round(absf(spin_accum) / PI))
	# Landed on your head (or back) mid-flip: wipe out.
	var flip_off := wrapf(flip_accum, -PI, PI)
	if absf(flip_off) > flip_land_limit:
		spin_accum = 0.0
		flip_accum = 0.0
		_start_crash()
		return
	var flips := int(round(flip_accum / TAU))
	if hv.length() > 3.0:
		var ang := absf(_forward().signed_angle_to(hv, Vector3.UP))
		var off := minf(ang, PI - ang)  # landing switch (backwards) is fine
		if off > spin_land_limit:
			spin_accum = 0.0
			flip_accum = 0.0
			_start_crash()
			return
		yaw = atan2(-hv.x, -hv.z)
		hv *= 0.96
	vel = Vector3(hv.x, _follow_rate(hv), hv.z)
	if air_time > 0.35:
		landed.emit(air_time, half_spins, flips)
	air_time = 0.0
	spin_accum = 0.0
	flip_accum = 0.0


## True while the board is on a kicker ramp (its run-up or lip).
func _on_ramp() -> bool:
	var d := -position.z
	return course._ramp_height(d, position.x - course.center_x(d)) > 0.05


func _follow_rate(hv: Vector3) -> float:
	var step := 0.05
	var p := position + hv * step
	return (course.height(p.x, p.z) - course.height(position.x, position.z)) / step


func _check_bounds() -> void:
	var d := -position.z
	var c: float = course.center_x(d)
	var lim: float = course.half_width - 0.6
	var lx := position.x - c
	if absf(lx) > lim:
		var s := signf(lx)
		position.x = c + s * lim
		if vel.x * s > 0.0:
			vel.x = -vel.x * 0.3
			vel.z *= 0.92
		if grounded:
			position.y = course.height(position.x, position.z)
	if position.z > 30.0:
		position.z = 30.0
		vel.z = minf(vel.z, 0.0)


func _check_obstacles() -> void:
	if ghost_timer > 0.0 or Screen.debug_invincible:
		return
	for o in course.obstacles:
		var p: Vector3 = o.pos
		if absf(p.z - position.z) > 4.0:
			continue
		var r: float = (o.radius + 0.35) * hit_scale
		var dx := position.x - p.x
		var dz := position.z - p.z
		if dx * dx + dz * dz < r * r and position.y < p.y + o.height:
			if phase_item and phase_cooldown <= 0.0:
				phase_cooldown = 12.0
				ghost_timer = 0.8
				saved.emit("GHOST WAX")
				return
			_start_crash()
			return


func _start_crash() -> void:
	var shielded := shields > 0 and not Screen.debug_invincible
	if shielded:
		shields -= 1
		ghost_timer = 1.5
		saved.emit("LUCKY SOCKS")
	if Screen.debug_invincible or shielded:   # a bad landing just straightens the rider out
		var hv := Vector3(vel.x, 0.0, vel.z)
		if hv.length() > 3.0:
			yaw = atan2(-hv.x, -hv.z)
		vel.y = _follow_rate(hv)
		air_time = 0.0
		return
	crash_timer = 1.6
	_tumble = 0.0
	flip_accum = 0.0
	grounded = false
	vel = Vector3(vel.x * 0.25, maxf(vel.y, 0.0) + 3.0, vel.z * 0.25)
	crashed.emit()


func _update_crash(dt: float) -> void:
	crash_timer -= dt
	_tumble += dt * 9.0 * clampf(crash_timer, 0.0, 1.0)
	vel.x = move_toward(vel.x, 0.0, 8.0 * dt)
	vel.z = move_toward(vel.z, 0.0, 8.0 * dt)
	vel.y -= air_gravity * dt
	position += vel * dt
	var gh: float = course.height(position.x, position.z)
	if position.y < gh:
		position.y = gh
		vel.y = 0.0
	_check_bounds()
	speed = Vector2(vel.x, vel.z).length()
	if crash_timer <= 0.0:
		# Back on your feet, pointing down the hill, briefly invulnerable.
		yaw = course.track_yaw(-position.z)
		var hv := _forward() * 4.0
		position.y = course.height(position.x, position.z)
		vel = Vector3(hv.x, _follow_rate(hv), hv.z)
		grounded = true
		ghost_timer = safe_time
		_tumble = 0.0


# ---------------------------------------------------------------- visuals

func _animate(dt: float) -> void:
	var k := 1.0 - exp(-8.0 * dt)
	var target_lean := 0.0
	if grounded and crash_timer <= 0.0:
		target_lean = _steer * clampf(speed / 20.0, 0.2, 1.0) * 0.45
	_lean = lerpf(_lean, target_lean, k)

	var target_crouch := 0.0
	if _tuck or (not grounded and crash_timer <= 0.0):
		target_crouch = 1.0
	elif _brake:
		target_crouch = 0.5
	_crouch = lerpf(_crouch, target_crouch, k)

	var target_pitch := 0.0
	if crash_timer <= 0.0:
		if grounded:
			var f := _forward()
			var a: float = course.height(position.x + f.x * 0.8, position.z + f.z * 0.8)
			var b: float = course.height(position.x - f.x * 0.8, position.z - f.z * 0.8)
			target_pitch = atan((a - b) / 1.6)
		elif speed > 1.0:
			target_pitch = atan2(vel.y, speed) * 0.5
	_pitch = lerpf(_pitch, target_pitch, k)

	if crash_timer > 0.0:
		_model.rotation = Vector3(_tumble, 0.0, _tumble * 0.5)
		_model.position = Vector3.ZERO
	else:
		# flip_accum > 0 = backflip = nose up (+X), so it adds straight onto the pitch
		_model.rotation = Vector3(_pitch + flip_accum, 0.0, _lean)
		# shift the model so mid-flip it turns about its middle (blends to normal near upright)
		var w := clampf(absf(flip_accum) / 0.6, 0.0, 1.0)
		_model.position = (FLIP_PIVOT - _model.basis * FLIP_PIVOT) * w
	_play_state_animation()
	_model.visible = ghost_timer <= 0.0 or fmod(ghost_timer, 0.2) > 0.08

	var gh: float = course.height(position.x, position.z)
	_blob.global_position = Vector3(position.x, gh + 0.06, position.z)
	_blob.rotation = Vector3(0.0, yaw, 0.0)
	_blob.scale = Vector3.ONE * clampf(1.0 - (position.y - gh) * 0.08, 0.4, 1.0)

	_spray.emitting = grounded and crash_timer <= 0.0 and not frozen and speed > 6.0
	_spray.initial_velocity_max = 2.0 + _skid * 0.6 + speed * 0.06


func _play_state_animation() -> void:
	if _anim == null:
		return
	var want := "ride"
	if crash_timer > 0.0:
		want = "crash"
	elif not grounded:
		want = "air"
	elif _tuck:
		want = "tuck"
	elif _brake:
		want = "brake"
	if _anim.current_animation != want and _anim.has_animation(want):
		_anim.play(want, 0.15)


func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	# Sugar glider rider + board from assets/models/sugar_glider.glb (made in Blender).
	# The model faces +Z with the board along X; turn it 90 degrees so the board runs
	# along the direction of travel (-Z) and the rider stands sideways facing +X.
	# Whichever rider was picked on the rider select (see riders.gd).
	# surfing levels (the beach) swap everyone into swimwear with a surfboard
	var surf: bool = preload("res://scripts/levels.gd").get_level(Screen.level).get("surf", false)
	var model: PackedScene = load(Riders.model_for(Screen.rider, surf))
	_rider = model.instantiate()
	_rider.rotation_degrees = Vector3(0, 90, 0)
	_model.add_child(_rider)
	for mi in _rider.find_children("*", "MeshInstance3D", true, false):
		MeshUtil.apply_ps1(mi)
	# Skeletal animations keyed in Blender: ride, tuck, brake, air, crash.
	_anim = _rider.find_child("AnimationPlayer", true, false)
	if _anim != null:
		for n in _anim.get_animation_list():
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		_anim.play("ride")
	_spray = CPUParticles3D.new()
	_spray.amount = 90
	_spray.lifetime = 0.7
	_spray.local_coords = false
	_spray.emitting = false
	_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_spray.emission_sphere_radius = 0.2
	_spray.direction = Vector3(0, 1, 1)
	_spray.spread = 35.0
	_spray.initial_velocity_min = 1.5
	_spray.initial_velocity_max = 5.0
	_spray.gravity = Vector3(0, -9, 0)
	_spray.scale_amount_min = 0.3
	_spray.scale_amount_max = 0.8
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	_spray.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = _soft_dot()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.billboard_keep_scale = true
	pm.vertex_color_use_as_albedo = true
	quad.material = pm
	_spray.mesh = quad
	_spray.position = Vector3(0, 0.05, 0.7)
	_model.add_child(_spray)

	# PS1-style blob shadow (no real-time shadows with per-vertex lighting).
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.1, 2.0)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(0.05, 0.08, 0.35, 0.55)
	bm.albedo_texture = _soft_dot()
	plane.material = bm
	_blob = MeshInstance3D.new()
	_blob.mesh = plane
	_blob.top_level = true
	add_child(_blob)


func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	return t
