extends Control
## Chemistry Set studio intro (320x240), timed to the 9.2 s jingle.
## The logo fills up from the bottom like liquid being poured, bubbles fizz in the tubes,
## "CHEMISTRY SET" types in with a light sweep, then it fades to the title screen.
## Enter / Esc / click skips.

const InputSetup := preload("res://scripts/input_setup.gd")
const NEXT_SCENE := "res://scenes/title.tscn"
const LOGO_POS := Vector2(96, 30)       # 128x128 logo shown 1:1 (crisp pixels)
const LOGO_SIZE := 128.0
# Liquid surface (logo-local pixels) and bubble tint for each tube.
const TUBES := [
	[Vector2(17, 32), Color(0.75, 0.95, 0.6)],
	[Vector2(64, 43), Color(1.0, 0.75, 0.78)],
	[Vector2(110, 59), Color(0.75, 0.86, 1.0)],
]

# Timeline (seconds)
const T_FILL_START := 0.4
const T_FILL_END := 2.0
const T_BUBBLES := 1.2
const T_TEXT_START := 2.2
const T_TEXT_END := 3.2
const SHINES := [3.6, 6.2]
const SHINE_TIME := 0.9
const T_FADE_OUT := 8.3
const T_END := 9.2

var _t := 0.0
var _done := false
var _skip_from := -1.0
var _clip: Control
var _logo: TextureRect
var _bubble_layer: Control
var _bubbles: Array = []          # [ColorRect, top_y, speed]
var _spawn_acc := 0.0
var _text: Label
var _shine: ShaderMaterial
var _fade: ColorRect
var _jingle: AudioStreamPlayer


func _ready() -> void:
	InputSetup.setup()
	Screen.stop_playlist()

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# The logo sits inside a clipping box that grows upward = "filling" reveal.
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.position = LOGO_POS + Vector2(0, LOGO_SIZE)
	_clip.size = Vector2(LOGO_SIZE, 0)
	add_child(_clip)
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/intro/chemistry_set_logo.png")
	_logo.size = Vector2(LOGO_SIZE, LOGO_SIZE)
	_clip.add_child(_logo)

	_bubble_layer = Control.new()
	_bubble_layer.position = LOGO_POS
	add_child(_bubble_layer)

	var font: FontFile = load("res://assets/fonts/emotion_engine.ttf")   # Emotion Engine by Pixel Sagas
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	_text = Label.new()
	_text.text = "CHEMISTRY SET"
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = 32
	ls.font_color = Color(0.9, 0.93, 1.0)
	ls.shadow_color = Color(0.1, 0.12, 0.3)
	ls.shadow_size = 0
	ls.shadow_offset = Vector2(2, 2)
	_text.label_settings = ls
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.position = Vector2(0, 168)
	_text.size = Vector2(320, 44)
	_text.visible_ratio = 0.0
	_shine = ShaderMaterial.new()
	_shine.shader = load("res://shaders/shine.gdshader")
	_text.material = _shine
	add_child(_text)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)

	_jingle = AudioStreamPlayer.new()
	_jingle.stream = load("res://assets/intro/chemistry_set_jingle.wav")
	_jingle.bus = "Music"
	add_child(_jingle)
	_jingle.play()


func _process(delta: float) -> void:
	_t += delta

	# Fill: reveal the logo bottom-up, easing out, in whole pixels.
	var f := clampf((_t - T_FILL_START) / (T_FILL_END - T_FILL_START), 0.0, 1.0)
	f = 1.0 - pow(1.0 - f, 2.0)
	var h := roundf(LOGO_SIZE * f)
	_clip.position.y = LOGO_POS.y + LOGO_SIZE - h
	_clip.size.y = h
	_logo.position.y = -(LOGO_SIZE - h)

	_update_bubbles(delta)

	# Title types in letter by letter.
	_text.visible_ratio = clampf((_t - T_TEXT_START) / (T_TEXT_END - T_TEXT_START), 0.0, 1.0)

	# Light sweeps across the text.
	var shine_x := -100.0
	for s in SHINES:
		var k: float = (_t - s) / SHINE_TIME
		if k >= 0.0 and k <= 1.0:
			shine_x = lerpf(-40.0, 360.0, k)
	_shine.set_shader_parameter("shine_x", roundf(shine_x))

	# Skip on any confirm/back/click after a moment.
	if _skip_from < 0.0 and _t > 0.3:
		for a in ["confirm", "back", "click"]:
			if InputMap.has_action(a) and Input.is_action_just_pressed(a):
				_skip_from = _t
	if _skip_from >= 0.0:
		var k2 := clampf((_t - _skip_from) / 0.3, 0.0, 1.0)
		_fade.color.a = k2
		_jingle.volume_db = linear_to_db(maxf(1.0 - k2, 0.001))
		if k2 >= 1.0:
			_finish()
	else:
		_fade.color.a = clampf((_t - T_FADE_OUT) / (T_END - T_FADE_OUT), 0.0, 1.0)
		if _t >= T_END:
			_finish()


func _update_bubbles(delta: float) -> void:
	if _t > T_BUBBLES and _t < T_FADE_OUT:
		_spawn_acc += delta * 14.0
		while _spawn_acc >= 1.0:
			_spawn_acc -= 1.0
			_spawn_bubble()
	for i in range(_bubbles.size() - 1, -1, -1):
		var b: Array = _bubbles[i]
		var r: ColorRect = b[0]
		b[3] -= b[2] * delta
		r.position.y = roundf(b[3])
		if b[3] <= b[1]:
			r.queue_free()
			_bubbles.remove_at(i)


func _spawn_bubble() -> void:
	var tube: Array = TUBES[randi() % TUBES.size()]
	var top: Vector2 = tube[0]
	var r := ColorRect.new()
	r.color = tube[1]
	r.size = Vector2(2, 2) if randf() < 0.7 else Vector2(1, 1)
	var y := top.y + randf_range(8.0, minf(46.0, 118.0 - top.y))
	r.position = Vector2(roundf(top.x + randf_range(-6.0, 6.0)), roundf(y))
	_bubble_layer.add_child(r)
	_bubbles.append([r, top.y + 1.0, randf_range(10.0, 20.0), y])


func _finish() -> void:
	if _done:
		return
	_done = true
	Screen.go(NEXT_SCENE)
