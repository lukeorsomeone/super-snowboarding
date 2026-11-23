extends Control
## Title screen, laid out for the 320x240 game screen.

const InputSetup := preload("res://scripts/input_setup.gd")
const RunState := preload("res://scripts/run_state.gd")
const LOGO_FONT := "res://assets/fonts/rave_logo.ttf"   # "The Rave Is In Your Pants" by Chequered Ink

var _prompt: Label
var _best_label: Label
var _riders: Control   # rider select overlay (starts the run)
var _help: Label
var _logo: Control
var _logo_snow: Label        # "SNOWBOARDING!" line, bounces a beat behind "SUPER"
var _snow_y := 0.0
var _impact_t := -10.0       # when the logo last hit the ground (for squash & stretch)
var _impact_amp := 0.0
var _impacts_done := 0
var _ui_t := -1.0            # when the prompt popped in
var _fade: ColorRect
var _music: AudioStreamPlayer
var _promo_path := ""
var _promo_started := false

# Opening timeline (seconds)
const FADE_IN := 1.0          # black -> picture, in chunky steps
const FADE_STEPS := 6
const MUSIC_FADE := 1.8       # title music volume ramp
const LOGO_DROP_START := 0.35
const LOGO_DROP_TIME := 1.3   # logo falls in from above and bounces to a stop
# Where the drop curve touches the ground, and how hard each bounce squashes the logo.
const IMPACTS := [0.3636, 0.7273, 0.9091]
const IMPACT_SQUASH := [0.32, 0.16, 0.08]
const HOP_SPEED := 2.4       # idle hops per second (x pi)
const HOP_HEIGHT := 5.0
const UI_SHOW := 1.4          # prompt + controls appear
const INPUT_READY := 0.8      # ignore presses before this (e.g. the one that skipped the intro)
const MUSIC_DB := -4.0
var _t := 0.0

const LOGO_CENTER := Vector2(160, 66)
const NAVY := Color(0.04, 0.08, 0.4)


func _ready() -> void:
	InputSetup.setup()
	Screen.stop_playlist()  # the title has its own theme
	Screen.run = null

	# A 320x240 shot of the valley rendered by the game itself
	# (re-capture with res://tools/capture_title_bg.tscn).
	var bg := TextureRect.new()
	bg.texture = load("res://assets/title_bg.png")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	_add_snow()

	var shade_grad := Gradient.new()
	shade_grad.set_color(0, Color(0.0, 0.03, 0.25, 0.0))
	shade_grad.set_color(1, Color(0.0, 0.03, 0.25, 0.75))
	var shade_tex := GradientTexture2D.new()
	shade_tex.gradient = shade_grad
	shade_tex.fill_from = Vector2(0, 0.4)
	shade_tex.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = shade_tex
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(shade)

	_build_logo()

	_place(_label("8 WORLDS  3 LIVES  NO FINISH LINE", 8, Color(0.75, 0.92, 1.0)), 0.61, 0.67)
	_prompt = _label("PRESS ENTER", 16, Color(1.0, 0.95, 0.5))
	_place(_prompt, 0.69, 0.79)
	_help = _label("", 8)
	_place(_help, 0.81, 0.95)
	_update_prompts(Screen.using_gamepad)
	Screen.input_device_changed.connect(_update_prompts)

	var fs := _label("F11 FULLSCREEN", 8, Color(0.75, 0.92, 1.0))
	fs.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	fs.anchor_left = 0.0
	fs.anchor_right = 0.5
	fs.offset_left = 6
	fs.offset_top = 6
	fs.offset_bottom = 16

	_best_label = _label("", 8)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_best_label.anchor_left = 0.5
	_best_label.anchor_right = 1.0
	_best_label.offset_right = -6
	_best_label.offset_top = 6
	_best_label.offset_bottom = 16
	var best := RunState.load_best_stage()
	if best > 0:
		_best_label.text = "BEST STAGE %d" % best

	_music = AudioStreamPlayer.new()
	_music.stream = load("res://assets/title_music.wav")
	_music.volume_db = -60.0   # fades up in _process
	_music.bus = "Music"
	add_child(_music)
	_music.finished.connect(_music.play)
	_music.play()

	# Black cover that fades away so the title eases in instead of popping on.
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	Screen.rider = preload("res://scripts/riders.gd").load_choice()
	_riders = preload("res://scripts/rider_select.gd").new()
	add_child(_riders)
	_riders.chosen.connect(_start_run)
	_help.visible = false
	_prompt.visible = false

	# Promo shot: `-- --promo=<file.png>` saves the logo over the background (no text,
	# no opening animation) at 320x240, then quits. Used for store-page art.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--promo="):
			_promo_path = a.substr(8)
			_t = 10.0   # skip the fade / logo drop


func _start_run() -> void:
	Screen.run = RunState.new()
	Screen.sfx("start", -2.0, 0.0)
	Screen.go("res://scenes/game.tscn")


func _save_promo() -> void:
	for c in get_children():
		if c is Label:
			c.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	Screen.viewport.get_texture().get_image().save_png(_promo_path)
	get_tree().quit()


## Show controller buttons or keyboard keys depending on what the player last touched.
func _update_prompts(gamepad: bool) -> void:
	if gamepad:
		_prompt.text = "PRESS START"
		_help.text = "STICK STEER  RT TUCK  LT BRAKE  A JUMP\nIN AIR: STICK SPIN/FLIP  START PAUSE"
	else:
		_prompt.text = "PRESS ENTER"
		_help.text = "A/D STEER  W TUCK  S BRAKE  SPACE JUMP\nIN AIR: A/D SPIN  W/S FLIP  ESC PAUSE"


func _pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


## Two layers of pixel snow drifting over the background: small slow flakes far away,
## bigger faster ones up close.
func _add_snow() -> void:
	for layer in [[150, 1.0, 12.0, 22.0, 7.0, 0.75], [45, 2.0, 26.0, 40.0, 4.5, 0.95]]:
		var p := CPUParticles2D.new()
		p.amount = layer[0]
		p.lifetime = layer[4]
		p.preprocess = layer[4]
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(220, 4)
		p.position = Vector2(140, -6)
		p.direction = Vector2(0.25, 1.0)
		p.spread = 10.0
		p.gravity = Vector2(5.0, 6.0)
		p.initial_velocity_min = layer[2]
		p.initial_velocity_max = layer[3]
		p.scale_amount_min = layer[1]
		p.scale_amount_max = layer[1]
		p.color = Color(1.0, 1.0, 1.0, layer[5])
		var tint := Gradient.new()
		tint.set_color(0, Color(1, 1, 1))
		tint.set_color(1, Color(0.8, 0.88, 1.0))
		p.color_initial_ramp = tint
		add_child(p)


## The game logo, set in the logo font: big "SUPER", a red swoosh, then "SNOWBOARDING!".
func _build_logo() -> void:
	var font: FontFile = load(LOGO_FONT)
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE   # crisp pixels on the 240p screen
	font.hinting = TextServer.HINTING_NONE

	_logo = Control.new()
	_logo.position = LOGO_CENTER
	_logo.rotation_degrees = -6.0
	_logo.pivot_offset = Vector2(0, 40)   # squash from the bottom, like it's landing
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)

	var sup := _logo_label(font, "SUPER", 46, Color(0.93, 0.97, 1.0), 6, Vector2(3, 3))
	sup.position = Vector2(-160, -48)
	sup.size = Vector2(320, 56)

	var swoosh := ColorRect.new()
	swoosh.color = Color(0.95, 0.15, 0.2)
	swoosh.position = Vector2(-72, 9)
	swoosh.size = Vector2(144, 3)
	swoosh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.add_child(swoosh)
	var swoosh_edge := ColorRect.new()
	swoosh_edge.color = NAVY
	swoosh_edge.position = Vector2(-72, 12)
	swoosh_edge.size = Vector2(144, 2)
	swoosh_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.add_child(swoosh_edge)

	var snow := _logo_label(font, "SNOWBOARDING!", 18, Color(1.0, 0.85, 0.2), 5, Vector2(2, 2))
	snow.position = Vector2(-160, 15)
	snow.size = Vector2(320, 26)
	snow.pivot_offset = snow.size / 2.0
	_logo_snow = snow
	_snow_y = snow.position.y


func _logo_label(font: Font, text: String, size: int, color: Color, outline: int, shadow: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = NAVY
	ls.shadow_color = Color(0.0, 0.02, 0.15, 0.85)
	ls.shadow_size = outline
	ls.shadow_offset = shadow
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.add_child(l)
	return l


func _label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = Screen.classic_font
	ls.font_size = size
	ls.font_color = color
	ls.shadow_color = Color(0.02, 0.04, 0.25)
	ls.shadow_size = 0
	ls.shadow_offset = Vector2.ONE * float(size / 8)
	ls.line_spacing = 2.0
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(l)
	return l


func _place(l: Label, top: float, bottom: float) -> void:
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = top
	l.anchor_bottom = bottom


func _process(delta: float) -> void:
	_t += delta

	# Fade in from black in a few hard steps (PS1-style, not a smooth video fade).
	var f := clampf(_t / FADE_IN, 0.0, 1.0)
	_fade.color.a = 1.0 - floorf(f * FADE_STEPS) / FADE_STEPS
	_fade.visible = _fade.color.a > 0.0

	# Title music swells up instead of starting at full volume.
	var m := clampf(_t / MUSIC_FADE, 0.0, 1.0)
	_music.volume_db = lerpf(-40.0, MUSIC_DB, sqrt(m)) if m < 1.0 else MUSIC_DB

	_animate_logo()

	if _promo_path != "":
		_logo.position.y = LOGO_CENTER.y
		_logo.scale = Vector2.ONE
		_logo.rotation_degrees = -6.0
		_logo_snow.position.y = _snow_y
		_logo_snow.scale = Vector2.ONE
		if not _promo_started:
			_promo_started = true
			_save_promo()
		return

	# Prompt and controls only once the logo has landed.
	var ui_on := _t >= UI_SHOW
	_help.visible = ui_on
	_prompt.visible = ui_on
	if ui_on:
		_animate_prompt()

	if _t < INPUT_READY:
		return
	if _riders.visible:
		return   # the menus handle input while they're open
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("click"):
		Screen.sfx("confirm")
		_riders.open()


## Logo: drops in and bounces to a stop (squashing on each landing), then keeps hopping
## on the spot with a little squash every time it touches down, and wobbles side to side.
func _animate_logo() -> void:
	var k := clampf((_t - LOGO_DROP_START) / LOGO_DROP_TIME, 0.0, 1.0)
	var y := (1.0 - _ease_out_bounce(k)) * -140.0
	var squash := 0.0

	# a big squash each time the falling logo hits the ground
	while _impacts_done < IMPACTS.size() and k >= IMPACTS[_impacts_done]:
		_impact_t = _t
		_impact_amp = IMPACT_SQUASH[_impacts_done]
		_impacts_done += 1
	var since := _t - _impact_t
	squash += _impact_amp * exp(-7.0 * since) * cos(since * 24.0)

	# once landed: keep hopping, squashing a little on each touch-down
	var settle := smoothstep(1.0, 1.4, (_t - LOGO_DROP_START) / LOGO_DROP_TIME)
	var hop := absf(sin(_t * HOP_SPEED))
	y -= hop * HOP_HEIGHT * settle
	squash += pow(1.0 - hop, 6.0) * 0.07 * settle

	_logo.position.y = LOGO_CENTER.y + round(y)
	_logo.scale = Vector2(1.0 + squash, 1.0 - squash)
	_logo.rotation_degrees = -6.0 + sin(_t * 1.7) * 2.0 * settle

	# "SNOWBOARDING!" hops a beat behind, like it's being dragged along
	var hop2 := absf(sin(_t * HOP_SPEED - 0.7))
	_logo_snow.position.y = _snow_y - round(hop2 * 3.0 * settle)
	var s2 := pow(1.0 - hop2, 6.0) * 0.1 * settle
	_logo_snow.scale = Vector2(1.0 + s2, 1.0 - s2)


## "PRESS ENTER" pops in with a springy overshoot, then hops in time with the logo.
func _animate_prompt() -> void:
	if _ui_t < 0.0:
		_ui_t = _t
	_prompt.pivot_offset = _prompt.size / 2.0
	var pop := clampf((_t - _ui_t) / 0.5, 0.0, 1.0)
	var grow := _ease_out_elastic(pop)
	var hop := absf(sin(_t * HOP_SPEED * 2.0))
	var squash := pow(1.0 - hop, 6.0) * 0.12
	_prompt.scale = Vector2(grow * (1.0 + squash), grow * (1.0 - squash))
	var off := -roundf(hop * 3.0)
	_prompt.offset_top = off
	_prompt.offset_bottom = off


## Falls and bounces three times, each bounce smaller (classic "bounce out" curve).
func _ease_out_bounce(x: float) -> float:
	var n1 := 7.5625
	var d1 := 2.75
	if x < 1.0 / d1:
		return n1 * x * x
	elif x < 2.0 / d1:
		x -= 1.5 / d1
		return n1 * x * x + 0.75
	elif x < 2.5 / d1:
		x -= 2.25 / d1
		return n1 * x * x + 0.9375
	x -= 2.625 / d1
	return n1 * x * x + 0.984375


## Shoots past 1 and springs back a few times before settling.
func _ease_out_elastic(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * TAU / 3.0) + 1.0


## Overshoots slightly past 1 then settles back — a small landing bounce.
func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
