extends Control
## Rider select (320x240), shown after the title screen, before a run starts.
## 6 cards in a 3x2 grid with each rider's portrait; slots past the last rider say
## COMING SOON. Arrows / stick move, Enter picks (and remembers) the rider, Esc goes back.

signal closed
signal chosen

const Riders := preload("res://scripts/riders.gd")

const COLS := 3
const CARD := Vector2(84, 80)          # whole card: portrait + name strip
const THUMB := Vector2(76, 57)         # 4:3, like the game screen
const GAP := Vector2(10, 8)
const GRID_TOP := 30.0

const NAVY := Color(0.04, 0.08, 0.4)
const CARD_BG := Color(0.03, 0.06, 0.25, 0.92)
const SEL_COLOR := Color(1.0, 0.92, 0.4)
const TEXT := Color(0.85, 0.92, 1.0)
const LOCK_TEXT := Color(1.0, 0.55, 0.6)
const SOON_TEXT := Color(0.6, 0.65, 0.8)

var _sel := 0
var _opened_frame := -1
var _cards: Array[Dictionary] = []    # {root, home, frame, thumb, shade, label, status, pop_t, shake_t}
var _info: Label
var _best: Label
var _hint: Label
var _t := 0.0
var _open_t := 0.0
var _title: Label
var _title_y := 6.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func open() -> void:
	visible = true
	_opened_frame = Engine.get_process_frames()
	_open_t = _t
	for c in _cards:
		c.pop_t = -10.0
		c.shake_t = -10.0
	_sel = clampi(Screen.rider, 1, Riders.count()) - 1
	_refresh_all()


func close() -> void:
	visible = false
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	# selected card frame pulses gently
	var f: ColorRect = _cards[_sel].frame
	f.color = SEL_COLOR.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 6.0))
	_animate()
	if Engine.get_process_frames() == _opened_frame:
		return  # ignore the Enter that opened us

	if _pressed("back") or _pressed("pause"):
		Screen.sfx("back")
		close()
		return
	var move := Vector2i.ZERO
	if _pressed("ui_left") or _pressed("steer_left"):
		move.x = -1
	elif _pressed("ui_right") or _pressed("steer_right"):
		move.x = 1
	elif _pressed("ui_up") or _pressed("tuck"):
		move.y = -1
	elif _pressed("ui_down") or _pressed("brake"):
		move.y = 1
	if move != Vector2i.ZERO:
		var col := posmod(_sel % COLS + move.x, COLS)
		var row := posmod(floori(_sel / float(COLS)) + move.y, ceili(Riders.SLOTS / float(COLS)))
		_sel = row * COLS + col
		_cards[_sel].pop_t = _t
		Screen.sfx("move_down" if move.x + move.y > 0 else "move_up", -4.0)
		_refresh_all()
	elif _pressed("confirm") or _pressed("ui_accept"):
		_choose()


func _pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _choose() -> void:
	var n := _sel + 1
	if n > Riders.count() or not Riders.is_unlocked(n):
		_cards[_sel].shake_t = _t
		Screen.sfx("back")
		Screen.rumble(0.3, 0.0, 0.1)
		return
	Screen.rider = n
	Riders.save_choice(n)
	Screen.sfx("confirm")
	visible = false
	chosen.emit()


# ---------------------------------------------------------------- bounce

## Cards drop in one by one and bounce on opening; the selected card hops with a little
## squash, springs when you land on it, and wobbles "no" if it's locked.
func _animate() -> void:
	var opened := _t - _open_t
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var root: Control = c.root
		var home: Vector2 = c.home
		var selected := i == _sel

		# intro: staggered drop with a bouncy landing and an elastic pop in size
		var k := clampf((opened - i * 0.06) / 0.55, 0.0, 1.0)
		var y := (1.0 - _ease_out_bounce(k)) * -40.0
		var grow := _ease_out_back(clampf((opened - i * 0.06) / 0.35, 0.0, 1.0))
		var sx := grow
		var sy := grow

		if selected:
			var hop := absf(sin(_t * 5.0))
			y -= hop * 3.0
			var squash := pow(1.0 - hop, 6.0) * 0.1
			sx *= 1.08 + squash
			sy *= 1.08 - squash

		# spring when the cursor lands on it
		var since_pop: float = _t - c.pop_t
		var spring := 0.22 * exp(-7.0 * since_pop) * cos(since_pop * 22.0)
		sx += spring
		sy += spring

		# locked: shake side to side
		var since_shake: float = _t - c.shake_t
		var x := sin(since_shake * 45.0) * 4.0 * exp(-7.0 * since_shake)

		root.position = home + Vector2(roundf(x), roundf(y))
		root.scale = Vector2(maxf(sx, 0.0), maxf(sy, 0.0))
		root.rotation_degrees = sin(_t * 3.0) * 1.5 if selected else 0.0

	# heading bobs along
	var th := absf(sin(_t * 2.5))
	_title.position.y = _title_y - roundf(th * 3.0)
	var ts := pow(1.0 - th, 6.0) * 0.08
	_title.scale = Vector2(1.0 + ts, 1.0 - ts)


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


func _ease_out_back(x: float) -> float:
	var c1 := 2.2
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


# ---------------------------------------------------------------- drawing

func _refresh_all() -> void:
	for i in _cards.size():
		_refresh_card(i)
	move_child(_cards[_sel].root, get_child_count() - 1)   # selected card in front
	var n := _sel + 1
	_best.text = ""
	if n > Riders.count():
		_info.text = "NEW RIDER COMING SOON"
		_info.label_settings.font_color = SOON_TEXT
	elif not Riders.is_unlocked(n):
		_info.text = "LOCKED RIDER"
		_info.label_settings.font_color = LOCK_TEXT
		_best.text = Riders.goal_text(n)
	else:
		var r := Riders.get_rider(n)
		_info.text = "%s THE %s" % [r.name, r.species]
		_info.label_settings.font_color = SEL_COLOR
		if n == Screen.rider:
			_best.text = "CURRENT RIDER"
	if Screen.using_gamepad:
		_hint.text = "STICK SELECT   A CHOOSE   B BACK"
	else:
		_hint.text = "ARROWS SELECT   ENTER CHOOSE   ESC BACK"


func _refresh_card(i: int) -> void:
	var c: Dictionary = _cards[i]
	var n := i + 1
	var selected := i == _sel
	(c.frame as ColorRect).color = SEL_COLOR if selected else NAVY
	var shade: ColorRect = c.shade
	var status: Label = c.status
	var label: Label = c.label
	if n > Riders.count():
		label.text = "???"
		shade.color = Color(0.02, 0.03, 0.12, 0.85)
		status.text = "COMING\nSOON"
		status.label_settings.font_color = SOON_TEXT
		label.label_settings.font_color = SOON_TEXT
	elif not Riders.is_unlocked(n):
		label.text = "???"
		shade.color = Color(0.02, 0.03, 0.12, 0.88)
		status.text = "LOCKED"
		status.label_settings.font_color = LOCK_TEXT
		label.label_settings.font_color = LOCK_TEXT
	else:
		label.text = Riders.get_rider(n).name
		shade.color = Color(0, 0, 0, 0)
		status.text = ""
		label.label_settings.font_color = SEL_COLOR if selected else TEXT


func _label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = Screen.classic_font
	ls.font_size = size
	ls.font_color = color
	ls.shadow_color = Color(0.0, 0.02, 0.15)
	ls.shadow_size = 0
	ls.shadow_offset = Vector2.ONE * (size / 8.0)
	ls.line_spacing = 2.0
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _rect(parent: Control, color: Color, pos: Vector2, size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _build() -> void:
	# darken the title screen behind us
	_rect(self, Color(0.0, 0.02, 0.15, 0.82), Vector2.ZERO, Vector2(320, 240))

	_title = _label(self, 16, SEL_COLOR)
	_title.text = "SELECT RIDER"
	_title.position = Vector2(0, _title_y)
	_title.size = Vector2(320, 18)
	_title.pivot_offset = _title.size / 2.0

	var grid_w := COLS * CARD.x + (COLS - 1) * GAP.x
	var left := (320.0 - grid_w) / 2.0
	for i in Riders.SLOTS:
		var n := i + 1
		var pos := Vector2(left + (i % COLS) * (CARD.x + GAP.x), GRID_TOP + floori(i / float(COLS)) * (CARD.y + GAP.y))
		var root := Control.new()
		root.position = pos
		root.size = CARD
		root.pivot_offset = CARD / 2.0
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		var frame := _rect(root, NAVY, Vector2.ZERO, CARD)
		_rect(root, CARD_BG, Vector2(2, 2), CARD - Vector2(4, 4))
		var tpos := Vector2((CARD.x - THUMB.x) / 2.0, 3)

		var thumb := TextureRect.new()
		thumb.position = tpos
		thumb.size = THUMB
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if n <= Riders.count():
			thumb.texture = Riders.load_thumb(n)
		root.add_child(thumb)
		if thumb.texture == null:
			# no screenshot (coming soon, or not captured yet): a plain dark panel
			_rect(root, Color(0.08, 0.1, 0.3), tpos, THUMB)

		var shade := _rect(root, Color(0, 0, 0, 0), tpos, THUMB)
		var status := _label(root, 8, LOCK_TEXT)
		status.position = tpos
		status.size = THUMB

		var label := _label(root, 8, TEXT)
		label.position = Vector2(0, tpos.y + THUMB.y + 3)
		label.size = Vector2(CARD.x, 14)

		_cards.append({"root": root, "home": pos, "frame": frame, "thumb": thumb, "shade": shade,
			"label": label, "status": status, "pop_t": -10.0, "shake_t": -10.0})

	var info_y := GRID_TOP + 2 * CARD.y + GAP.y + 6
	_info = _label(self, 8, SEL_COLOR)
	_info.position = Vector2(0, info_y)
	_info.size = Vector2(320, 10)
	_best = _label(self, 8, TEXT)
	_best.position = Vector2(0, info_y + 12)
	_best.size = Vector2(320, 10)
	_hint = _label(self, 8, Color(0.75, 0.92, 1.0))
	_hint.position = Vector2(0, 226)
	_hint.size = Vector2(320, 10)
