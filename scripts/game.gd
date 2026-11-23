extends Node3D
## One stage of an endless roguelike run: ride to the finish line, then pick an item. Lives,
## items and score carry through every lap of the 8 levels (see run_state.gd). Lose your last
## life and it's over.

const InputSetup := preload("res://scripts/input_setup.gd")
const Levels := preload("res://scripts/levels.gd")
const START_D := -8.0
const RunState := preload("res://scripts/run_state.gd")
const UpgradeScreen := preload("res://scripts/upgrade_screen.gd")
const Hud := preload("res://scripts/hud.gd")
const GAME_SCENE := "res://scenes/game.tscn"
const MILESTONE := 500.0
const INTRO_TIME := 4.5     # seconds of camera sweep before the 3 2 1
const COUNT_TIME := 3.0
const INTRO_SPEED := 16.0   # m/s the rider is already doing on the run-up

enum State { INTRO, COUNTDOWN, RUNNING, CLEAR, OVER }

@onready var course: Node3D = $Course
@onready var player: Node3D = $Player
@onready var cam: Camera3D = $Camera

var state := State.INTRO
var countdown := 3.0
var race_time := 0.0
var score := 0          # tricks + gifts (distance is added on top)
var gifts_taken := 0
var run: RefCounted               # the run in progress (Screen.run)
var lives: int:
	get: return run.lives
	set(v): run.lives = v
var distance := 0.0
var _next_milestone := MILESTONE
var _countdown_first := true
var level_def: Dictionary          # the level being played (see levels.gd)
var _stage_crashes := 0
var _clear_t := 0.0
var _upgrade: CanvasLayer
var _new_riders: Array[String] = []
var _intro_t := 0.0        # time into the camera sweep
var _ride_t := 0.0         # time into the scripted ride (sweep + countdown)
var _intro_ui: CanvasLayer
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _intro_labels: Control

var _hud: CanvasLayer
var _ui: Control              # the drawn HUD (hud.gd)
var _big_label: Label
var _results: PanelContainer
var _results_label: Label
var _trick_sfx: AudioStreamPlayer
var _pause: CanvasLayer
var _big_timer := 0.0


## Runs before the rider and course load, so they see the right level.
func _enter_tree() -> void:
	if Screen.run == null:
		Screen.run = RunState.new()   # started straight from the editor
	run = Screen.run
	Screen.level = run.lap_stage()


func _ready() -> void:
	InputSetup.setup()
	level_def = Levels.for_stage(run.stage)
	_apply_level_look()
	course.configure(level_def)
	course.finish_d = run.stage_length()
	course.build()
	player.course = course
	player.saved.connect(_on_item_saved)
	player.crashed.connect(_on_crashed)
	player.landed.connect(_on_landed)
	cam.target = player
	cam.course = course
	_build_hud()
	_build_intro_ui()
	_pause = preload("res://scripts/pause_menu.gd").new()
	add_child(_pause)
	_pause.restart_requested.connect(_new_run)
	_pause.quit_requested.connect(_quit_to_title)
	if level_def.get("theme", "snow") == "snow" or level_def.get("snowfall", false):
		_add_snowfall()
	_start_run()
	_setup_autopilot()
	_trick_sfx = AudioStreamPlayer.new()
	_trick_sfx.stream = load("res://assets/sfx/trick_points.mp3")
	_trick_sfx.bus = "SFX"
	add_child(_trick_sfx)
	Screen.track_changed.connect(_on_track_changed)
	Screen.play_level_music(level_def.get("music", ""))
	if Screen.current_track != "":
		_on_track_changed(Screen.current_track)


func _start_run() -> void:
	player.apply_run(run, level_def.get("gravity", 1.0))
	course.reset()
	var x: float = course.center_x(START_D)
	player.place(Vector3(x, course.height(x, -START_D), -START_D), course.track_yaw(0.0))
	course.runup = true
	_intro_t = 0.0
	_ride_t = 0.0
	_ride_intro(0.0)
	cam.snap()
	cam.intro_progress = 0.0
	_hud.visible = false
	_intro_ui.visible = true
	state = State.INTRO
	countdown = COUNT_TIME
	race_time = 0.0
	score = 0
	gifts_taken = 0
	distance = 0.0
	_stage_crashes = 0
	_next_milestone = MILESTONE
	_countdown_first = true
	_results.visible = false
	Screen.debug_tainted = Screen.debug_invincible or not is_equal_approx(Engine.time_scale, 1.0)


## Debug menu: jumps the rider further down the course, keeping their speed.
func debug_warp(metres: float) -> void:
	if state != State.RUNNING or player.crash_timer > 0.0:
		return
	Screen.debug_tainted = true
	var d := maxf(-player.position.z, 0.0) + metres
	var lx: float = player.position.x - course.center_x(-player.position.z)
	var x: float = course.center_x(d) + lx
	player.position = Vector3(x, course.height(x, -d), -d)
	player.grounded = true
	player.ghost_timer = 1.5
	course.debug_jump(d)
	cam.snap()
	distance = d
	_next_milestone = (floorf(d / MILESTONE) + 1.0) * MILESTONE


func debug_set_hud(on: bool) -> void:
	_hud.visible = on and state != State.INTRO


func _process(delta: float) -> void:
	match state:
		State.INTRO:
			_intro_t += delta
			_ride_intro(delta)
			cam.intro_progress = _intro_t / INTRO_TIME
			_update_intro_ui()
			var skip := _intro_t > 0.25 and (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("jump"))
			if skip or _autopilot:
				_ride_t = INTRO_TIME
				_ride_intro(0.0)
				_end_intro()
			elif _intro_t >= INTRO_TIME:
				_end_intro()
		State.COUNTDOWN:
			_ride_intro(delta)
			var before := int(ceil(countdown))
			countdown -= delta
			if countdown > 0.0:
				var n := int(ceil(countdown))
				_show_big(str(n), 0.4)
				if n != before or _countdown_first:
					Screen.sfx("tick", -2.0, 0.0)
					_countdown_first = false
			else:
				_show_big("GO!", 0.9)
				Screen.sfx("go", -1.0, 0.0)
				state = State.RUNNING
				player.scripted = false
				player.controls_enabled = true
				course.runup = false
		State.RUNNING:
			race_time += delta
			distance = maxf(distance, -player.position.z)
			if distance >= _next_milestone:
				_pop_trick("%d M!" % int(_next_milestone), 1.6)
				Screen.sfx("milestone")
				Screen.rumble(0.4, 0.2, 0.2)
				_next_milestone += MILESTONE
			if distance >= run.stage_length():
				_clear_stage()
		State.CLEAR:
			_clear_t -= delta
			if _clear_t <= 0.0 and _upgrade == null:
				_open_upgrades()
		State.OVER:
			if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("restart"):
				Screen.sfx("confirm")
				_new_run()
				return

	course.focus_d = -player.position.z

	if state == State.OVER and Input.is_action_just_pressed("back"):
		Screen.sfx("back")
		_quit_to_title()
		return
	if (state == State.INTRO or state == State.COUNTDOWN or state == State.RUNNING) and Input.is_action_just_pressed("pause"):
		_pause.open()
		return

	_collect_gifts()
	_update_hud(delta)
	if _autopilot:
		_drive_autopilot()


# ---------------------------------------------------------------- stage intro

## Carves down the run-up so the rider reaches the start line just as the countdown hits GO.
func _ride_intro(delta: float) -> void:
	_ride_t = minf(_ride_t + delta, INTRO_TIME + COUNT_TIME)
	var left := INTRO_TIME + COUNT_TIME - _ride_t
	var d := START_D - INTRO_SPEED * left
	var fade := smoothstep(0.0, 2.5, left)
	var lx := 3.5 * sin(_ride_t * 1.5) * fade
	var lx_rate := 3.5 * 1.5 * cos(_ride_t * 1.5) * fade
	var x: float = course.center_x(d) + lx
	player.ride_to(Vector3(x, course.height(x, -d), -d), atan2(-lx_rate, INTRO_SPEED), INTRO_SPEED, -sin(_ride_t * 1.5) * fade)


func _end_intro() -> void:
	state = State.COUNTDOWN
	cam.end_intro()
	_intro_ui.visible = false
	_hud.visible = not Screen.debug_hide_hud
	_countdown_first = true


func _build_intro_ui() -> void:
	_intro_ui = CanvasLayer.new()
	_intro_ui.layer = 6
	add_child(_intro_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_ui.add_child(root)
	_bar_top = ColorRect.new()
	_bar_bottom = ColorRect.new()
	for bar in [_bar_top, _bar_bottom]:
		bar.color = Color.BLACK
		bar.size = Vector2(320, 34)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
	_intro_labels = Control.new()
	_intro_labels.size = Vector2(320, 240)
	_intro_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_intro_labels)
	var stage := _make_label(_intro_labels, 8, Color(0.6, 0.95, 1.0))
	stage.position = Vector2(0, 12)
	stage.size = Vector2(320, 10)
	stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.text = run.stage_label()
	var level_name := _make_label(_intro_labels, 16, Color(1.0, 0.92, 0.4))
	level_name.position = Vector2(0, 212)
	level_name.size = Vector2(320, 18)
	level_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_name.text = level_def.name
	var hint := _make_label(_intro_labels, 8, Color(0.6, 0.65, 0.8))
	hint.position = Vector2(0, 12)
	hint.size = Vector2(314, 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.text = "A SKIP" if Screen.using_gamepad else "ENTER SKIP"
	_update_intro_ui()


## Letterbox bars slide away as the shot settles behind the rider.
func _update_intro_ui() -> void:
	var k := 1.0 - smoothstep(INTRO_TIME - 0.6, INTRO_TIME, _intro_t)
	var h := roundf(34.0 * k)
	_bar_top.position.y = h - 34.0
	_bar_bottom.position.y = 240.0 - h
	_intro_labels.position.y = 0.0
	_intro_labels.modulate.a = k


# ---------------------------------------------------------------- dev: autopilot capture
# `-- --autopilot --frames=<dir>` rides automatically (aims at ramps, ollies, spins a 360)
# and saves every rendered frame — used to make trailers, screenshots and GIFs.

var _autopilot := false
var _frames_dir := ""
var _frame_no := 0
var _was_air := false


func _setup_autopilot() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autopilot":
			_autopilot = true
		elif a.begins_with("--frames="):
			_frames_dir = a.substr(9)
	if _frames_dir != "":
		RenderingServer.frame_post_draw.connect(_save_frame)


func _save_frame() -> void:
	get_tree().root.get_texture().get_image().save_png("%s/f%05d.png" % [_frames_dir, _frame_no])
	_frame_no += 1


func _hold(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


func _drive_autopilot() -> void:
	if state != State.RUNNING:
		return
	var d: float = -player.position.z
	var air: bool = not player.grounded
	if air != _was_air:
		print("AUTOPILOT %s frame=%d d=%d" % ["TAKEOFF" if air else "LANDING", _frame_no, int(d)])
		_was_air = air
	if air:
		# spin one full rotation, then straighten up to land clean
		_hold("steer_left", absf(player.spin_accum) < TAU - 0.35)
		_hold("steer_right", false)
		_hold("tuck", false)
		_hold("jump", false)
		return
	# find the next ramp ahead and line up with it
	var target_lx := 0.0
	var ramp_d := -1.0
	var c := int(floor(d / 96.0))   # course chunk length
	for cc in range(c, c + 4):
		var r: Dictionary = course._ramp_for_chunk(cc)
		if not r.is_empty() and r.d > d + 0.5:
			target_lx = r.x
			ramp_d = r.d
			break
	var ahead := d + 14.0
	var tx: float = course.center_x(ahead) + target_lx
	var to := Vector2(tx - player.position.x, -ahead - player.position.z)
	var want_yaw := atan2(-to.x, -to.y)
	var err := wrapf(want_yaw - player.yaw, -PI, PI)
	_hold("steer_left", err > 0.04)
	_hold("steer_right", err < -0.04)
	_hold("tuck", true)
	_hold("jump", ramp_d > 0.0 and ramp_d - d < 1.2)


func _total_score() -> int:
	return run.score + score + int(distance)


func _clear_stage() -> void:
	state = State.CLEAR
	player.controls_enabled = false
	player.auto_brake = true
	for a in ["steer_left", "steer_right", "tuck", "jump"]:
		if _autopilot:
			_hold(a, false)
	run.cheated = run.cheated or Screen.debug_tainted
	if _stage_crashes == 0:
		run.clean_stage = true
	_new_riders = run.reach_stage(run.stage + 1)
	if run.lap_stage() == RunState.STAGES:   # beat The Moon: on to a harder lap
		_new_riders.append_array(run.bank_win())
		_show_big("LAP %d!" % (run.lap() + 2), 1.4)
		_pop_trick("YOU BEAT THE MOON!" if run.lap() == 0 else "IT GETS HARDER", 1.6)
	else:
		_show_big("STAGE CLEAR", 1.4)
	Screen.sfx("milestone")
	Screen.rumble(0.5, 0.5, 0.4)
	_clear_t = 1.5


func _open_upgrades() -> void:
	_upgrade = UpgradeScreen.new()
	_upgrade.run = run
	_upgrade.new_riders = _new_riders
	add_child(_upgrade)
	_upgrade.chosen.connect(_on_item_chosen)
	if _autopilot:
		_upgrade.choose(0)


func _on_item_chosen(id: String) -> void:
	run.add_item(id)
	run.score = _total_score()
	run.stage += 1
	Screen.sfx("start", -2.0, 0.0)
	Screen.go.call_deferred(GAME_SCENE)


## Starts over from stage 1 with the same rider. Leaving a run still counts its progress.
func _new_run() -> void:
	_record_run()
	Screen.run = RunState.new()
	Screen.go(GAME_SCENE)


func _quit_to_title() -> void:
	_record_run()
	Screen.run = null
	Screen.go("res://scenes/title.tscn")


func _record_run() -> void:
	run.cheated = run.cheated or Screen.debug_tainted
	run.finish(_total_score())


func _apply_level_look() -> void:
	Levels.apply_look(level_def, $WorldEnvironment, $Sun)


func _run_over() -> void:
	state = State.OVER
	player.controls_enabled = false
	player.auto_brake = true
	run.cheated = run.cheated or Screen.debug_tainted
	var total := _total_score()
	var result: Dictionary = run.finish(total)
	Screen.sfx("new_best" if result.new_best else "run_over", -2.0, 0.0)
	Screen.rumble(0.5, 0.9, 0.6)
	_show_big("RUN OVER", 2.5)
	var lines := ""
	var news: Array[String] = []
	for rider_name in result.riders:
		news.append("NEW RIDER: %s" % rider_name)
	for item_name in result.unlocked:
		news.append("NEW ITEM: %s" % item_name)
	for line in news.slice(0, 3):
		lines += line + "\n"
	if news.size() > 3:   # keeps the results inside the panel
		lines += "+%d MORE UNLOCKS\n" % (news.size() - 3)
	if run.cheated:
		lines += "DEBUG RUN - NOT SAVED\n"
	_results_label.text = "%s\n\nREACHED %s\n%s\n\nITEMS  %d\nGIFTS  %d\nTRICK POINTS  %d\n\nSCORE  %d\n%s\n%s%s" % [
		"RUN OVER", run.stage_label(), level_def.name,
		run.items.size(), run.gifts_total, run.trick_points, total,
		"NEW BEST!" if result.new_best else "BEST  %d" % result.best_score,
		lines + "\n" if lines != "" else "\n",
		"A NEW RUN   B MENU" if Screen.using_gamepad else "ENTER NEW RUN   ESC MENU"]
	_results.visible = true


func _on_item_saved(item_name: String) -> void:
	_pop_trick("%s!" % item_name, 1.6)
	_ui.flash_name(item_name)
	Screen.sfx("milestone", -4.0)
	cam.shake(0.2)


func _collect_gifts() -> void:
	if state == State.COUNTDOWN:
		return
	var pp: Vector3 = player.position + Vector3.UP * 0.9
	var reach := 6.0 if run.has("magnet") else 3.0
	var reach_sq := 30.0 if run.has("magnet") else 2.6
	for g in course.gifts:
		if g.taken:
			continue
		var gp: Vector3 = g.node.position
		if absf(gp.z - pp.z) > reach:
			continue
		if pp.distance_squared_to(gp) < reach_sq:
			g.taken = true
			g.node.visible = false
			gifts_taken += 1
			if state == State.RUNNING:
				var value: int = run.gift_value()
				score += value
				run.gifts += 1
				run.gifts_total += 1
				_ui.gift_pop(value)
				if run.has("santa") and run.gifts_total % 25 == 0 and run.heal():
					_pop_trick("SANTA'S SACK  +1 LIFE", 1.6)
					_ui.flash("santa")
				Screen.sfx("gift", -4.0)
				Screen.rumble(0.3, 0.0, 0.06)


const FLIP_POINTS := 500   # per full flip, on top of air and spin points


func _on_landed(air_time: float, half_spins: int, flips: int) -> void:
	if state != State.RUNNING:
		return
	var pts := int(air_time * 100.0)
	var parts: Array[String] = []
	if half_spins > 0:
		parts.append("%d" % (half_spins * 180))
		pts += half_spins * 150
	if flips != 0:
		var n := absi(flips)
		var kind := "BACKFLIP" if flips > 0 else "FRONTFLIP"
		parts.append(kind if n == 1 else ("DOUBLE " if n == 2 else "%dX " % n) + kind)
		pts += n * FLIP_POINTS
	var trick := " ".join(parts)
	if trick == "":
		trick = "BIG AIR" if air_time > 1.2 else "AIR"
	elif flips == 0:
		trick += " SPIN"
	if run.has("spin"):
		pts += half_spins * 75
	pts = int(pts * run.trick_multiplier())
	score += pts
	run.trick_points += pts
	run.best_flips = maxi(run.best_flips, absi(flips))
	_pop_trick(("%s +%d" if flips != 0 else "%s  +%d") % [trick, pts], 1.6 if flips != 0 else 1.4)
	if run.has("rocket") and (half_spins > 0 or flips != 0):
		player.push(9.0)
		_ui.flash("rocket")
	if run.has("adrenaline") and run.trick_points >= run.next_adrenaline:
		while run.trick_points >= run.next_adrenaline:
			run.next_adrenaline += RunState.ADRENALINE_STEP
		if run.heal():
			_pop_trick("ADRENALINE  +1 LIFE", 1.6)
			_ui.flash("adrenaline")
	_trick_sfx.pitch_scale = 1.0 + 0.08 * half_spins + 0.12 * absi(flips)  # bigger tricks sound brighter
	_trick_sfx.play()
	Screen.rumble(0.25 + air_time * 0.2, 0.15 + air_time * 0.3, 0.15)   # bigger air = harder landing


func _on_crashed() -> void:
	cam.shake(0.5)
	if state != State.RUNNING:
		return
	_stage_crashes += 1
	lives -= 1
	if lives <= 0 and run.has("phoenix") and not run.phoenix_used:
		run.phoenix_used = true
		lives = 1
		_show_big("REBORN!", 1.4)
		_pop_trick("PHOENIX FEATHER", 1.6)
		_ui.flash("phoenix")
		Screen.sfx("new_best", -4.0, 0.0)
	elif lives <= 0:
		_run_over()
	else:
		_show_big("WIPEOUT!", 1.2)
		Screen.sfx("wipeout")
		Screen.rumble(0.6, 1.0, 0.45)
		_pop_trick("%d %s LEFT" % [lives, "LIFE" if lives == 1 else "LIVES"], 1.4)


# ---------------------------------------------------------------- HUD

## HUD is laid out for the 320x240 game screen; font sizes are multiples of 8 (pixel font).
func _make_label(parent: Control, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = Screen.pixel_font
	ls.font_size = size
	ls.font_color = color
	ls.shadow_color = Color(0.02, 0.04, 0.25)
	ls.shadow_size = 0
	ls.shadow_offset = Vector2.ONE * float(size / 8)
	ls.line_spacing = 2.0
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.visible = not Screen.debug_hide_hud
	_hud = layer
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_ui = Hud.new()
	_ui.setup(run)
	root.add_child(_ui)

	_big_label = _make_label(root, 32, Color(1.0, 0.95, 0.5))
	_big_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_big_label.offset_bottom = -76
	_big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_results = PanelContainer.new()
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_results.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Teal text-block panel from FREE PSX UI by rohhsa (rohhsa.itch.io).
	var panel := StyleBoxTexture.new()
	panel.texture = load("res://assets/ui/panel.png")
	panel.set_content_margin_all(12)
	_results.add_theme_stylebox_override("panel", panel)
	root.add_child(_results)
	_results_label = _make_label(_results, 8)
	_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results.visible = false


func _update_hud(delta: float) -> void:
	_ui.refresh(delta, _total_score(), _fmt(race_time), player.speed, player.max_speed, distance, run.stage_length())
	_big_timer = maxf(_big_timer - delta, 0.0)
	_big_label.modulate.a = clampf(_big_timer * 4.0, 0.0, 1.0)


func _on_track_changed(title: String) -> void:
	_ui.show_track(title)


func _show_big(text: String, seconds: float) -> void:
	_big_label.text = text
	_big_timer = seconds


func _pop_trick(text: String, seconds: float) -> void:
	_ui.pop(text, seconds)


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]


func _add_snowfall() -> void:
	var p := CPUParticles3D.new()
	p.amount = 1500
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(45, 2, 45)
	p.direction = Vector3(0, -1, 0)
	p.spread = 15.0
	p.gravity = Vector3(0, -1.5, 0)
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	var m := StandardMaterial3D.new()
	m.albedo_texture = player._soft_dot()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.85)
	quad.material = m
	p.mesh = quad
	p.position = Vector3(0, 14, -25)
	cam.add_child(p)
